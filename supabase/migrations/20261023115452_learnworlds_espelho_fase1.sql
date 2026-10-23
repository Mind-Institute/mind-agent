-- LearnWorlds, Fase 1 — espelho de leitura (aprovado pela Adriana em 23/10/2026).
--
-- Tudo de LearnWorlds mora no schema `learnworlds`. Quatro tabelas de ENTRADA (D9: guardam o que a API
-- devolve, sem tratamento), escritas só pela Edge Function `learnworlds-sync`:
--   learnworlds.cursos      um curso (o `id` é o código/slug do LearnWorlds)
--   learnworlds.programas   um bundle / learning program ou plano de assinatura
--   learnworlds.usuarios    uma pessoa da escola
--   learnworlds.matriculas  pessoa × produto (curso, bundle ou plano)
-- `usuarios` e `matriculas` entram na Regra #1 (D5/D6) por `mind_pessoa_ligar_tabela`: a porta única
-- resolve o `mind_id` antes da escrita e grava o ID do LearnWorlds em `engagement.identidades`.
--
-- O mapa programa → produto do LearnWorlds continua um só: `learnworlds.produtos` (tratamento, à mão).
-- O cruzamento aparece nos DOIS schemas, como a Adriana pediu: `learnworlds.v_cursos_no_catalogo`
-- (cada curso/programa do LearnWorlds e se está à venda) e `catalogo.v_produtos_learnworlds` (cada produto
-- do catálogo e o ID dele no LearnWorlds), para quem lê o catálogo saber o código do curso.
--
-- Estado das varreduras: `crm.sync_estado` (casa existente), fontes `learnworlds_usuarios` e
-- `learnworlds_matriculas`. Credencial: secrets da Edge Function; `platform.integracoes` guarda só o nome.
-- Funções nascem fechadas (25/09): só `service_role` executa.

set lock_timeout = '10s';

-- ------------------------------------------------------------------ entrada: cursos
create table if not exists learnworlds.cursos (
  id              text primary key,
  titulo          text,
  acesso          text,
  categorias      text[] not null default '{}',
  preco_original  numeric,
  preco_desconto  numeric,
  preco_final     numeric,
  criado_lw       timestamptz,
  modificado_lw   timestamptz,
  payload         jsonb not null,
  sincronizado_em timestamptz not null default now()
);
comment on table learnworlds.cursos is
  'Entrada (D9): os cursos da escola como GET /v2/courses do LearnWorlds devolve. `id` é o código do curso no LearnWorlds. Escrita só pela edge learnworlds-sync. Aprovado pela Adriana em 23/10/2026.';
comment on column learnworlds.cursos.id is 'Código (slug) do curso no LearnWorlds; é o `productId` para matricular.';
comment on column learnworlds.cursos.acesso is 'Como o LearnWorlds expõe o curso (free, paid, private, draft, coming soon…).';
comment on column learnworlds.cursos.payload is 'O curso inteiro como a API devolveu.';

-- ------------------------------------------------------------------ entrada: programas
create table if not exists learnworlds.programas (
  id              text not null,
  tipo            text not null check (tipo in ('bundle', 'subscription')),
  titulo          text,
  acesso          text,
  cursos          text[] not null default '{}',
  preco           numeric,
  criado_lw       timestamptz,
  modificado_lw   timestamptz,
  payload         jsonb not null,
  sincronizado_em timestamptz not null default now(),
  primary key (tipo, id)
);
comment on table learnworlds.programas is
  'Entrada (D9): bundles / learning programs (GET /v2/bundles) e planos de assinatura (GET /v2/subscription-plans) do LearnWorlds. Escrita só pela edge learnworlds-sync. Aprovado pela Adriana em 23/10/2026.';
comment on column learnworlds.programas.cursos is 'Os cursos que o programa inclui (ids do LearnWorlds), como a API devolve em `products`.';

-- ------------------------------------------------------------------ entrada: usuarios
create table if not exists learnworlds.usuarios (
  id              text primary key,
  email           text,
  username        text,
  primeiro_nome   text,
  sobrenome       text,
  tags            text[] not null default '{}',
  suspenso        boolean,
  papel           text,
  criado_lw       timestamptz,
  ultimo_login    timestamptz,
  payload         jsonb not null,
  sincronizado_em timestamptz not null default now()
);
comment on table learnworlds.usuarios is
  'Entrada (D9): as pessoas da escola como GET /v2/users do LearnWorlds devolve. Na Regra #1: o mind_id vem da porta única (e-mail + learnworlds_user_id). Escrita só pela edge learnworlds-sync. Aprovado pela Adriana em 23/10/2026.';
comment on column learnworlds.usuarios.id is 'ID da pessoa no LearnWorlds ({{USER.ID}} no código da escola).';

-- ------------------------------------------------------------------ entrada: matriculas
create table if not exists learnworlds.matriculas (
  usuario_id      text not null,
  produto_tipo    text not null check (produto_tipo in ('course', 'bundle', 'subscription')),
  produto_id      text not null,
  email           text,
  visto_em        timestamptz not null default now(),
  ausente_desde   timestamptz,
  payload         jsonb not null,
  primary key (usuario_id, produto_tipo, produto_id)
);
comment on table learnworlds.matriculas is
  'Entrada (D9): quem tem acesso a cada produto no LearnWorlds (GET /v2/courses/{id}/users e /v2/users/by-product). Uma linha por pessoa × produto. Na Regra #1. Escrita só pela edge learnworlds-sync. Aprovado pela Adriana em 23/10/2026.';
comment on column learnworlds.matriculas.visto_em is 'Última varredura em que a pessoa apareceu na lista do produto.';
comment on column learnworlds.matriculas.ausente_desde is 'A lista completa do produto terminou sem esta pessoa (saiu do produto no LearnWorlds). Nulo = matrícula vigente.';
comment on column learnworlds.matriculas.payload is 'A pessoa como a lista do produto devolveu.';
create index if not exists matriculas_produto_idx on learnworlds.matriculas (produto_tipo, produto_id);

-- ------------------------------------------------------------------ fechadas
alter table learnworlds.cursos enable row level security;
alter table learnworlds.programas enable row level security;
alter table learnworlds.usuarios enable row level security;
alter table learnworlds.matriculas enable row level security;
revoke all on table learnworlds.cursos, learnworlds.programas, learnworlds.usuarios, learnworlds.matriculas
  from public, anon, authenticated;
grant select on table learnworlds.cursos, learnworlds.programas, learnworlds.usuarios, learnworlds.matriculas
  to service_role;

-- ------------------------------------------------------------------ Regra #1
select public.mind_pessoa_ligar_tabela('learnworlds.usuarios'::regclass,
  '{"nome": ["primeiro_nome", "sobrenome"], "emails": ["email"], "learnworlds_user_id": "id"}'::jsonb);
select public.mind_pessoa_ligar_tabela('learnworlds.matriculas'::regclass,
  '{"emails": ["email"], "learnworlds_user_id": "usuario_id"}'::jsonb);

-- ------------------------------------------------------------------ escritor único
-- Grava o que a edge leu. Existente: só UPDATE (a porta única não roda de novo se e-mail, nome e ID
-- não mudaram); novo: INSERT, e a porta única resolve a pessoa. Assim uma varredura completa não
-- re-resolve a escola inteira.
create or replace function public.learnworlds_espelho_gravar(p_entidade text, p_itens jsonb, p_contexto jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ins int := 0; v_upd int := 0;
  v_tipo text := p_contexto->>'tipo';
  v_prod text := p_contexto->>'produto_id';
  v_ptipo text := p_contexto->>'produto_tipo';
begin
  if jsonb_typeof(coalesce(p_itens, '[]'::jsonb)) <> 'array' then
    raise exception using errcode = '22023', message = 'itens_nao_sao_lista';
  end if;

  if p_entidade = 'cursos' then
    with d as (
      select i->>'id' as id, i->>'title' as titulo, i->>'access' as acesso,
             coalesce(array(select jsonb_array_elements_text(case when jsonb_typeof(i->'categories') = 'array' then i->'categories' else '[]' end)), '{}') as categorias,
             case when jsonb_typeof(i->'original_price') = 'number' then (i->>'original_price')::numeric end as po,
             case when jsonb_typeof(i->'discount_price') = 'number' then (i->>'discount_price')::numeric end as pd,
             case when jsonb_typeof(i->'final_price') = 'number' then (i->>'final_price')::numeric end as pf,
             case when jsonb_typeof(i->'created') = 'number' then to_timestamp((i->>'created')::double precision) end as criado,
             case when jsonb_typeof(i->'modified') = 'number' then to_timestamp((i->>'modified')::double precision) end as modificado, i as payload
        from jsonb_array_elements(p_itens) i where nullif(i->>'id','') is not null
    ), u as (
      update learnworlds.cursos c set titulo = d.titulo, acesso = d.acesso, categorias = d.categorias,
             preco_original = d.po, preco_desconto = d.pd, preco_final = d.pf, criado_lw = d.criado,
             modificado_lw = d.modificado, payload = d.payload, sincronizado_em = now()
        from d where c.id = d.id returning c.id
    ), n as (
      insert into learnworlds.cursos (id, titulo, acesso, categorias, preco_original, preco_desconto, preco_final,
                                      criado_lw, modificado_lw, payload)
      select d.id, d.titulo, d.acesso, d.categorias, d.po, d.pd, d.pf, d.criado, d.modificado, d.payload
        from d where not exists (select 1 from learnworlds.cursos c where c.id = d.id)
      returning id
    )
    select (select count(*) from n), (select count(*) from u) into v_ins, v_upd;

  elsif p_entidade = 'programas' then
    if v_tipo not in ('bundle', 'subscription') then
      raise exception using errcode = '22023', message = 'tipo_de_programa_invalido';
    end if;
    with d as (
      select i->>'id' as id, i->>'title' as titulo, i->>'access' as acesso,
             -- `products` vem como {"courses": [...]} nos bundles; lista solta também é aceita.
             coalesce(array(
               select x from jsonb_array_elements_text(
                 case when jsonb_typeof(i->'products'->'courses') = 'array' then i->'products'->'courses'
                      when jsonb_typeof(i->'products') = 'array' then i->'products'
                      else '[]' end) x
             ), '{}') as cursos,
             case when jsonb_typeof(i->'price') = 'number' then (i->>'price')::numeric end as preco,
             case when jsonb_typeof(i->'created') = 'number' then to_timestamp((i->>'created')::double precision) end as criado,
             case when jsonb_typeof(i->'modified') = 'number' then to_timestamp((i->>'modified')::double precision) end as modificado, i as payload
        from jsonb_array_elements(p_itens) i where nullif(i->>'id','') is not null
    ), u as (
      update learnworlds.programas p set titulo = d.titulo, acesso = d.acesso, cursos = d.cursos, preco = d.preco,
             criado_lw = d.criado, modificado_lw = d.modificado, payload = d.payload, sincronizado_em = now()
        from d where p.tipo = v_tipo and p.id = d.id returning p.id
    ), n as (
      insert into learnworlds.programas (id, tipo, titulo, acesso, cursos, preco, criado_lw, modificado_lw, payload)
      select d.id, v_tipo, d.titulo, d.acesso, d.cursos, d.preco, d.criado, d.modificado, d.payload
        from d where not exists (select 1 from learnworlds.programas p where p.tipo = v_tipo and p.id = d.id)
      returning id
    )
    select (select count(*) from n), (select count(*) from u) into v_ins, v_upd;

  elsif p_entidade = 'usuarios' then
    with d as (
      select i->>'id' as id, lower(btrim(i->>'email')) as email, i->>'username' as username,
             nullif(btrim(i->>'first_name'),'') as primeiro_nome, nullif(btrim(i->>'last_name'),'') as sobrenome,
             coalesce(array(select jsonb_array_elements_text(case when jsonb_typeof(i->'tags') = 'array' then i->'tags' else '[]' end)), '{}') as tags,
             case when jsonb_typeof(i->'is_suspended') = 'boolean' then (i->>'is_suspended')::boolean end as suspenso, i->'role'->>'level' as papel,
             case when jsonb_typeof(i->'created') = 'number' then to_timestamp((i->>'created')::double precision) end as criado,
             case when jsonb_typeof(i->'last_login') = 'number' then to_timestamp((i->>'last_login')::double precision) end as ultimo_login, i as payload
        from jsonb_array_elements(p_itens) i where nullif(i->>'id','') is not null
    ), u as (
      update learnworlds.usuarios x set email = d.email, username = d.username, primeiro_nome = d.primeiro_nome,
             sobrenome = d.sobrenome, tags = d.tags, suspenso = d.suspenso, papel = d.papel, criado_lw = d.criado,
             ultimo_login = d.ultimo_login, payload = d.payload, sincronizado_em = now()
        from d where x.id = d.id returning x.id
    ), n as (
      insert into learnworlds.usuarios (id, email, username, primeiro_nome, sobrenome, tags, suspenso, papel,
                                        criado_lw, ultimo_login, payload)
      select d.id, d.email, d.username, d.primeiro_nome, d.sobrenome, d.tags, d.suspenso, d.papel, d.criado,
             d.ultimo_login, d.payload
        from d where not exists (select 1 from learnworlds.usuarios x where x.id = d.id)
      returning id
    )
    select (select count(*) from n), (select count(*) from u) into v_ins, v_upd;

  elsif p_entidade = 'matriculas' then
    if nullif(v_prod,'') is null or v_ptipo not in ('course', 'bundle', 'subscription') then
      raise exception using errcode = '22023', message = 'produto_invalido';
    end if;
    with d as (
      select i->>'id' as usuario_id, lower(btrim(i->>'email')) as email, i as payload
        from jsonb_array_elements(p_itens) i where nullif(i->>'id','') is not null
    ), u as (
      update learnworlds.matriculas m set email = d.email, visto_em = now(), ausente_desde = null, payload = d.payload
        from d where m.usuario_id = d.usuario_id and m.produto_tipo = v_ptipo and m.produto_id = v_prod
      returning m.usuario_id
    ), n as (
      insert into learnworlds.matriculas (usuario_id, produto_tipo, produto_id, email, payload)
      select d.usuario_id, v_ptipo, v_prod, d.email, d.payload
        from d where not exists (select 1 from learnworlds.matriculas m
                                  where m.usuario_id = d.usuario_id and m.produto_tipo = v_ptipo and m.produto_id = v_prod)
      returning usuario_id
    )
    select (select count(*) from n), (select count(*) from u) into v_ins, v_upd;

  elsif p_entidade = 'matriculas_fim' then
    -- A lista do produto terminou: quem não apareceu desde o início desta varredura saiu do produto.
    update learnworlds.matriculas m set ausente_desde = now()
     where m.produto_tipo = v_ptipo and m.produto_id = v_prod
       and m.visto_em < (p_contexto->>'inicio')::timestamptz and m.ausente_desde is null;
    get diagnostics v_upd = row_count;

  else
    raise exception using errcode = '22023', message = 'entidade_desconhecida';
  end if;

  return jsonb_build_object('inseridos', v_ins, 'atualizados', v_upd);
end;
$$;
revoke all on function public.learnworlds_espelho_gravar(text, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.learnworlds_espelho_gravar(text, jsonb, jsonb) to service_role;
comment on function public.learnworlds_espelho_gravar(text, jsonb, jsonb) is
  'Escritor único das tabelas de entrada do LearnWorlds (cursos, programas, usuarios, matriculas, matriculas_fim). Chamada só pela edge learnworlds-sync.';

-- Lê e atualiza a linha da fonte em crm.sync_estado (casa existente). p_patch nulo = só lê.
create or replace function public.learnworlds_espelho_estado(p_fonte text, p_patch jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_linha crm.sync_estado%rowtype;
begin
  if p_fonte not in ('learnworlds_usuarios', 'learnworlds_matriculas') then
    raise exception using errcode = '22023', message = 'fonte_invalida';
  end if;
  if p_patch is not null then
    insert into crm.sync_estado (fonte, status) values (p_fonte, 'ocioso') on conflict (fonte) do nothing;
    update crm.sync_estado s set
      status            = coalesce(p_patch->>'status', s.status),
      cursor            = case when p_patch ? 'cursor' then p_patch->>'cursor' else s.cursor end,
      registros_lidos   = coalesce((p_patch->>'registros_lidos')::int, s.registros_lidos),
      registros_gravados= coalesce((p_patch->>'registros_gravados')::int, s.registros_gravados),
      erro              = case when p_patch ? 'erro' then p_patch->>'erro' else s.erro end,
      iniciado_em       = coalesce((p_patch->>'iniciado_em')::timestamptz, s.iniciado_em),
      concluido_em      = coalesce((p_patch->>'concluido_em')::timestamptz, s.concluido_em),
      carga_completa_em = coalesce((p_patch->>'carga_completa_em')::timestamptz, s.carga_completa_em),
      tabela_destino    = coalesce(p_patch->>'tabela_destino', s.tabela_destino),
      chave_destino     = coalesce(p_patch->>'chave_destino', s.chave_destino)
     where s.fonte = p_fonte;
  end if;
  select * into v_linha from crm.sync_estado where fonte = p_fonte;
  return case when found then to_jsonb(v_linha) else '{}'::jsonb end;
end;
$$;
revoke all on function public.learnworlds_espelho_estado(text, jsonb) from public, anon, authenticated;
grant execute on function public.learnworlds_espelho_estado(text, jsonb) to service_role;
comment on function public.learnworlds_espelho_estado(text, jsonb) is
  'Estado das varreduras do LearnWorlds em crm.sync_estado (fontes learnworlds_usuarios e learnworlds_matriculas). Chamada só pela edge learnworlds-sync.';

-- ------------------------------------------------------------------ cruzamento, nos dois schemas
-- Um curso ou programa do LearnWorlds e o produto do catálogo a que ele corresponde, pelo mapa
-- learnworlds.produtos → institute.programas → catalogo.produtos.
create or replace view learnworlds.v_cursos_no_catalogo as
with lw as (
  select 'course'::text as tipo, c.id, c.titulo, c.acesso, c.sincronizado_em from learnworlds.cursos c
  union all
  select p.tipo, p.id, p.titulo, p.acesso, p.sincronizado_em from learnworlds.programas p
)
select lw.tipo as lw_tipo, lw.id as lw_id, lw.titulo as lw_titulo, lw.acesso as lw_acesso,
       m.programa_codigo, cp.codigo as catalogo_codigo, cp.nome as catalogo_nome,
       cp.vende, cp.ativo, cp.vende_de, cp.vende_ate,
       case
         when cp.codigo is null then 'sem produto no catálogo'
         when cp.ativo and cp.vende
              and (cp.vende_de is null or cp.vende_de <= now())
              and (cp.vende_ate is null or cp.vende_ate > now()) then 'à venda'
         else 'fora de venda'
       end as situacao,
       (select count(*) from learnworlds.matriculas mt
         where mt.produto_tipo = lw.tipo and mt.produto_id = lw.id and mt.ausente_desde is null) as matriculas_vigentes,
       lw.sincronizado_em
  from lw
  left join learnworlds.produtos m on m.tipo = lw.tipo and m.lms_id = lw.id
  left join institute.programas ip on ip.codigo = m.programa_codigo
  left join catalogo.produtos cp on cp.codigo = ip.produto_codigo;
comment on view learnworlds.v_cursos_no_catalogo is
  'Cada curso/programa do LearnWorlds, o produto do catálogo a que corresponde (pelo mapa learnworlds.produtos) e se está à venda. Pedido da Adriana em 23/10/2026.';

-- Cada produto do catálogo que tem programa, com o ID dele no LearnWorlds: quem lê o catálogo sabe o
-- código do curso para matricular.
create or replace view catalogo.v_produtos_learnworlds as
select cp.codigo as catalogo_codigo, cp.nome as catalogo_nome, cp.vende, cp.ativo, cp.vende_de, cp.vende_ate,
       ip.codigo as programa_codigo, m.tipo as lw_tipo, m.lms_id as lw_id,
       coalesce(c.titulo, p.titulo) as lw_titulo, coalesce(c.acesso, p.acesso) as lw_acesso,
       case
         when m.lms_id is null then 'sem curso no LearnWorlds'
         when c.id is null and p.id is null then 'mapeado, mas não encontrado no LearnWorlds'
         else 'mapeado'
       end as situacao_lw
  from catalogo.produtos cp
  join institute.programas ip on ip.produto_codigo = cp.codigo
  left join learnworlds.produtos m on m.programa_codigo = ip.codigo
  left join learnworlds.cursos c on m.tipo = 'course' and c.id = m.lms_id
  left join learnworlds.programas p on m.tipo in ('bundle', 'subscription') and p.tipo = m.tipo and p.id = m.lms_id;
comment on view catalogo.v_produtos_learnworlds is
  'Cada produto do catálogo que tem programa no Institute e o ID do curso/bundle dele no LearnWorlds (pelo mapa learnworlds.produtos). Pedido da Adriana em 23/10/2026.';

revoke all on table learnworlds.v_cursos_no_catalogo, catalogo.v_produtos_learnworlds from public, anon, authenticated;
grant select on table learnworlds.v_cursos_no_catalogo, catalogo.v_produtos_learnworlds to service_role;

-- ------------------------------------------------------------------ registro da integração (só o nome do secret)
insert into platform.integracoes (codigo, rotulo, base_url, secret_ref, config)
values ('learnworlds', 'LearnWorlds (escola do Mind Institute)', 'https://my.mindinstitute.com.br/admin/api',
        'LEARNWORLDS_CLIENT_SECRET',
        '{"client_id_ref": "LEARNWORLDS_CLIENT_ID", "limite": "30 chamadas a cada 10 s", "edge": "learnworlds-sync"}'::jsonb)
on conflict (codigo) do nothing;
