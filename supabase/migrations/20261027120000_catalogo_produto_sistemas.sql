-- CORRESPONDÊNCIA DE CADA PRODUTO COM OS SISTEMAS EXTERNOS (Adriana, 27/10/2026; gate D2 aprovado
-- por ela na mesma data: tabela nova no schema catalogo, como autoridade única).
--
-- Por quê: cada produto do catálogo precisa dizer qual é o código dele na Eduzz (para atribuir a
-- receita), na InfinitePay (gateway do checkout próprio) e no LearnWorlds (para liberar a matrícula
-- automaticamente). Até hoje isso morava em três lugares desencontrados:
--   · checkout.produto_externo  — de-para InfinitePay/Eduzz → produto. Existia e estava vazio;
--   · learnworlds.produtos      — programa do Institute → curso/bundle. 4 linhas; é o que a
--                                 matrícula automática (api.fila_de_provisionamento) lê;
--   · nada ligava um produto Eduzz a um produto do catálogo.
--
-- Daqui em diante a autoridade é catalogo.produto_sistemas. As duas tabelas antigas viram views com
-- as mesmas colunas, lidas de cá: api.fila_de_provisionamento, api.aviso_do_pedido, api.admin_acessos
-- e as views do LearnWorlds continuam funcionando sem mudar uma linha. eduzz.produto_catalogo
-- continua sendo a tradução comercial de cada produto Eduzz (ano, categoria, lote); a ligação dele
-- com o produto do catálogo passa a ser a linha ('eduzz', <id do produto Eduzz>) aqui.
--
-- Chave pelo CÓDIGO do produto (não pelo id): é o que checkout.produto_externo já usava, o código não
-- se edita pelo painel, e as views antigas são lidas pela equipe sem acesso direto a catalogo.produtos.

create table catalogo.produto_sistemas (
  id uuid primary key default gen_random_uuid(),
  produto_codigo text not null references catalogo.produtos(codigo) on update cascade on delete cascade,
  sistema text not null check (sistema in ('eduzz', 'infinitepay', 'learnworlds')),
  id_externo text not null check (btrim(id_externo) <> ''),
  -- Só o LearnWorlds distingue o que é o identificador: curso, bundle ou assinatura.
  tipo text,
  observacao text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint produto_sistemas_tipo_check check (
    (sistema = 'learnworlds' and tipo in ('course', 'bundle', 'subscription'))
    or (sistema <> 'learnworlds' and tipo is null)
  ),
  -- Um identificador externo pertence a um produto só: é o que torna a atribuição de receita inequívoca.
  constraint produto_sistemas_externo_unico unique (sistema, id_externo)
);

-- A matrícula automática libera UM destino por produto.
create unique index produto_sistemas_um_lms_por_produto
  on catalogo.produto_sistemas (produto_codigo) where sistema = 'learnworlds';
create index produto_sistemas_produto on catalogo.produto_sistemas (produto_codigo);

comment on table catalogo.produto_sistemas is
  'Correspondência de cada produto do catálogo com os sistemas externos: Eduzz (atribuir receita), InfinitePay (checkout próprio) e LearnWorlds (matrícula automática). Autoridade única desde 27/10/2026; learnworlds.produtos e checkout.produto_externo são views desta tabela. Editada pelo painel (Catálogo).';
comment on column catalogo.produto_sistemas.id_externo is
  'O identificador no sistema: id do produto na Eduzz, SKU na InfinitePay, id do curso/bundle/assinatura no LearnWorlds.';

alter table catalogo.produto_sistemas enable row level security;
create policy equipe_le_produto_sistemas on catalogo.produto_sistemas
  for select to authenticated using (seguranca.eh_equipe());
grant select on catalogo.produto_sistemas to authenticated;
grant select, insert, update, delete on catalogo.produto_sistemas to service_role;

-- O que já existe vem junto.
insert into catalogo.produto_sistemas (produto_codigo, sistema, id_externo, tipo, observacao, atualizado_em)
select ip.produto_codigo, 'learnworlds', m.lms_id, m.tipo, m.observacao, m.atualizado_em
  from learnworlds.produtos m
  join institute.programas ip on ip.codigo = m.programa_codigo
 where ip.produto_codigo is not null;

insert into catalogo.produto_sistemas (produto_codigo, sistema, id_externo, observacao, atualizado_em)
select produto_codigo, sistema, sku_externo, observacao, atualizado_em
  from checkout.produto_externo;

-- As views que dependem das tabelas antigas saem e voltam iguais (definição e permissões).
drop view api.admin_acessos;
drop view catalogo.v_produtos_learnworlds;
drop view learnworlds.v_cursos_no_catalogo;
drop table learnworlds.produtos;
drop table checkout.produto_externo;

-- learnworlds.produtos: mesmas colunas de antes. Só aparecem produtos com programa no Institute,
-- que é a chave que a matrícula automática do checkout próprio usa.
create view learnworlds.produtos with (security_invoker = true) as
select ip.codigo as programa_codigo,
       s.tipo,
       s.id_externo as lms_id,
       s.observacao,
       s.atualizado_em
  from catalogo.produto_sistemas s
  join institute.programas ip on ip.produto_codigo = s.produto_codigo
 where s.sistema = 'learnworlds';
comment on view learnworlds.produtos is
  'Em que curso ou bundle do LearnWorlds cada programa matricula. View de catalogo.produto_sistemas desde 27/10/2026 — edite lá (painel → Catálogo).';
grant select on learnworlds.produtos to authenticated;

-- checkout.produto_externo: mesmas colunas de antes.
create view checkout.produto_externo with (security_invoker = true) as
select s.sistema,
       s.id_externo as sku_externo,
       s.produto_codigo,
       s.observacao,
       s.atualizado_em
  from catalogo.produto_sistemas s
 where s.sistema in ('infinitepay', 'eduzz');
comment on view checkout.produto_externo is
  'De-para: o identificador que o gateway usa <-> o produto do Mind. View de catalogo.produto_sistemas desde 27/10/2026 — edite lá (painel → Catálogo).';
grant select on checkout.produto_externo to authenticated;

create view api.admin_acessos with (security_invoker = true) as
SELECT a.id,
    a.status,
    a.nome,
    a.oferta_codigo,
    a.programa_codigo,
    a.destino,
    a.destino_user_id,
    a.destino_curso_id,
    a.tentativas,
    a.ultimo_erro,
    a.provisionado_em,
    a.observacao,
    a.criado_em,
    p.nsu AS pedido_nsu,
    p.pago_em,
    c.id AS comprador_id,
    COALESCE(p.comprador_nome, c.nome) AS comprador_nome,
    COALESCE(p.comprador_email, c.email) AS comprador_email,
    COALESCE(p.comprador_telefone, c.telefone) AS comprador_telefone,
    m.tipo AS lms_tipo,
    m.lms_id
   FROM learnworlds.acessos a
     JOIN checkout.pedidos p ON p.id = a.pedido_id
     JOIN checkout.compradores c ON c.id = a.comprador_id
     LEFT JOIN learnworlds.produtos m ON m.programa_codigo = a.programa_codigo;
grant select on api.admin_acessos to authenticated;

-- As duas leituras do LearnWorlds ↔ catálogo passam a olhar a correspondência por PRODUTO: um produto
-- sem programa no Institute (ex.: a pré-certificação) também aparece. Colunas iguais às de antes.
create view catalogo.v_produtos_learnworlds as
SELECT cp.codigo AS catalogo_codigo,
    cp.nome AS catalogo_nome,
    cp.vende,
    cp.ativo,
    cp.vende_de,
    cp.vende_ate,
    ip.codigo AS programa_codigo,
    s.tipo AS lw_tipo,
    s.id_externo AS lw_id,
    COALESCE(c.titulo, p.titulo) AS lw_titulo,
    COALESCE(c.acesso, p.acesso) AS lw_acesso,
        CASE
            WHEN s.id_externo IS NULL THEN 'sem curso no LearnWorlds'::text
            WHEN c.id IS NULL AND p.id IS NULL THEN 'mapeado, mas não encontrado no LearnWorlds'::text
            ELSE 'mapeado'::text
        END AS situacao_lw
   FROM catalogo.produtos cp
     LEFT JOIN institute.programas ip ON ip.produto_codigo = cp.codigo
     LEFT JOIN catalogo.produto_sistemas s ON s.produto_codigo = cp.codigo AND s.sistema = 'learnworlds'
     LEFT JOIN learnworlds.cursos c ON s.tipo = 'course'::text AND c.id = s.id_externo
     LEFT JOIN learnworlds.programas p ON (s.tipo = ANY (ARRAY['bundle'::text, 'subscription'::text])) AND p.tipo = s.tipo AND p.id = s.id_externo
  WHERE ip.codigo IS NOT NULL OR s.id IS NOT NULL;
comment on view catalogo.v_produtos_learnworlds is
  'Cada produto do catálogo que tem programa no Institute ou correspondência no LearnWorlds, e o ID do curso/bundle dele lá (catalogo.produto_sistemas). Pedido da Adriana em 23/10/2026; por produto desde 27/10/2026.';
grant select on catalogo.v_produtos_learnworlds to service_role;

create view learnworlds.v_cursos_no_catalogo as
WITH lw AS (
         SELECT 'course'::text AS tipo,
            c.id,
            c.titulo,
            c.acesso,
            c.sincronizado_em
           FROM learnworlds.cursos c
        UNION ALL
         SELECT p.tipo,
            p.id,
            p.titulo,
            p.acesso,
            p.sincronizado_em
           FROM learnworlds.programas p
        )
 SELECT lw.tipo AS lw_tipo,
    lw.id AS lw_id,
    lw.titulo AS lw_titulo,
    lw.acesso AS lw_acesso,
    ip.codigo AS programa_codigo,
    cp.codigo AS catalogo_codigo,
    cp.nome AS catalogo_nome,
    cp.vende,
    cp.ativo,
    cp.vende_de,
    cp.vende_ate,
        CASE
            WHEN cp.codigo IS NULL THEN 'sem produto no catálogo'::text
            WHEN cp.ativo AND cp.vende AND (cp.vende_de IS NULL OR cp.vende_de <= now()) AND (cp.vende_ate IS NULL OR cp.vende_ate > now()) THEN 'à venda'::text
            ELSE 'fora de venda'::text
        END AS situacao,
    ( SELECT count(*) AS count
           FROM learnworlds.matriculas mt
          WHERE mt.produto_tipo = lw.tipo AND mt.produto_id = lw.id AND mt.ausente_desde IS NULL) AS matriculas_vigentes,
    lw.sincronizado_em
   FROM lw
     LEFT JOIN catalogo.produto_sistemas s ON s.sistema = 'learnworlds' AND s.tipo = lw.tipo AND s.id_externo = lw.id
     LEFT JOIN catalogo.produtos cp ON cp.codigo = s.produto_codigo
     LEFT JOIN institute.programas ip ON ip.produto_codigo = cp.codigo;
comment on view learnworlds.v_cursos_no_catalogo is
  'Cada curso/programa do LearnWorlds, o produto do catálogo a que corresponde (catalogo.produto_sistemas) e se está à venda. Pedido da Adriana em 23/10/2026.';
grant select on learnworlds.v_cursos_no_catalogo to service_role;
