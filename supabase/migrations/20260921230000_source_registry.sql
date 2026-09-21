-- ============================================================
-- Source Registry — o registro de quem manda em cada fonte
-- ============================================================
-- Projeto: mind-agent (ymnmotgglsrxmjmonwjz)
--
-- O QUE ISTO É
-- Duas tabelas e cinco funções que respondem, para qualquer fonte de
-- dado do sistema: o que ela é, de que produto fala, qual competência
-- pode consumi-la, e QUEM MANDA no fato que ela carrega.
--
-- Mais o caminho pelo qual uma fonte nova entra: alguém (ou o detector)
-- registra uma pendência, uma classificação é PROPOSTA, e uma pessoa
-- decide. A proposta nunca decide sozinha.
--
-- POR QUE UM REGISTRO, E NÃO DEDUÇÃO NO CONSUMIDOR
-- Hoje, quem escreve código que lê uma tabela decide sozinho se aquilo
-- é fonte ou cópia. Duas pessoas decidem diferente e o sistema passa a
-- afirmar duas verdades. D1 (PROJECT_STATE v9) tornou isso caro: se o
-- Supabase é a fonte da verdade do histórico do cliente, precisa haver
-- um lugar único que diga, fonte por fonte, o que é verdade — e que
-- mudar isso seja decisão registrada, não patch.
--
-- A FORMA VEM DE ALGO QUE JÁ FUNCIONA
-- `engagement.identidade_fusoes` + `mind_conflito_registrar` /
-- `mind_pendencias_listar` / `mind_pendencia_resolver`, a forma canônica
-- de `docs/CORE_UNIVERSAL.md:88`:
--
--   detecta -> persiste evidência -> vira pendência
--           -> NÃO faz auto-merge -> resolução humana
--
-- Inclusive a idempotência: índice único PARCIAL `where status='pendente'`.
-- É o índice que impede a mesma tabela virar quarenta pendências — não
-- um `if exists` na função, que corre em condição de corrida.
--
-- TRÊS FALHAS DO PADRÃO CANÔNICO QUE AQUI SÃO CORRIGIDAS
-- 1. `mind_pendencia_resolver` não checa papel nenhum: qualquer
--    `service_role` resolve. Aqui o papel é checado dentro do SQL, no
--    modelo de `mind_admin_mutate_resource` (erro 42501).
-- 2. `identidade_fusoes` não sabe quem decidiu. Aqui há `resolvido_por`,
--    e a decisão vira linha em `public.mind_admin_audit`.
-- 3. Nenhuma das três filas existentes separa o que a IA propôs do que
--    a pessoa escolheu — e essa é exatamente a diferença entre APROVAR
--    e AJUSTAR. Aqui `proposta` e `decisao` são colunas distintas.
--
-- O QUE ISTO NÃO FAZ
--   - não toca nenhuma tabela, função, policy ou dado existente;
--   - APROVAR NÃO TORNA A FONTE CONSUMÍVEL. Habilitar é outro passo, em
--     `agentes.kit_blocos`, escrito por alguém. Aprovar classifica;
--     não injeta nada no Kit;
--   - resolver não ativa: `mind_registry_resolver` registra a decisão,
--     `mind_registry_ativar` grava a fonte. Dois escritores, dois passos,
--     como manda "resolver != executar";
--   - não cria proveniência por linha nem por coluna (BACKLOG.md:499);
--   - não liga cron. O detector roda à mão até o volume justificar.
--
-- UMA COISA DO PLANO QUE A INVESTIGAÇÃO DERRUBOU
-- O plano previa adicionar `registry.fontes` aos triggers de
-- `concierge.bump_config_revisao`. NÃO FOI FEITO, por duas razões
-- medidas em 21/09/2026:
--
--   (a) as 6 tabelas que carregam esse trigger são todas configuração
--       de runtime do agente — `concierge.config`, `feature_flags`,
--       `ferramentas`, `prompts`, `templates` e `intelligence.intencoes`.
--       O registry é metadado de governança: classificar uma fonte não
--       muda nada que o Kit leia. Disparar o sinal seria dizer ao Kit
--       Loader "sua config mudou, recarregue" quando nada que ele lê
--       mudou — invalidação falsa no caminho quente do agente, a cada
--       classificação;
--   (b) `concierge.config_revisao` não é lido por nenhuma função do
--       banco nem por nenhum arquivo versionado do repositório. O sinal
--       existe e ninguém escuta. (Ressalva honesta: 18 das 28 Edge
--       Functions não são versionadas aqui, então pode haver leitor que
--       este repositório não mostra. Mesmo que haja, (a) continua de pé.)
--
-- QUEM RESPONDE
-- Adriana aprova (D2). Vinicius executa o banco (D2). A classificação
-- de cada fonte é decisão dela; a carga e a manutenção, dele.
--
-- DESFAZER
--   drop schema registry cascade;
--   drop function if exists public.mind_registry_registrar(text,text,text,jsonb,text,text);
--   drop function if exists public.mind_registry_pendencias(text,text,integer,integer);
--   drop function if exists public.mind_registry_resolver(uuid,text,jsonb,uuid,uuid,text);
--   drop function if exists public.mind_registry_ativar(uuid,uuid,uuid);
--   drop function if exists public.mind_registry_propor(text,text);
-- Nada fora do schema `registry` e dessas cinco funções é criado, então
-- o desfazer é completo e não deixa resíduo.
--
-- SEGURANÇA
-- RLS ligada nas duas tabelas, sem policy: ninguém lê pelo PostgREST.
-- O acesso é só pelas funções, `security definer`, com grant de execute
-- apenas a `service_role` — o mesmo desenho de `identidade_fusoes`.
-- `mind_registry_resolver` e `mind_registry_ativar` exigem papel
-- `administrador` ou `aprovador` em `public.mind_admin_users`.
-- Nenhuma das funções lê dado de negócio: só catálogo e o próprio
-- registro.
-- ============================================================

begin;

create schema if not exists registry;

comment on schema registry is
  'O registro de fontes do Mind: o que cada fonte de dado e, de que produto fala, quem manda no fato que ela carrega, e a fila de decisao para o que ainda nao foi classificado. Metadado de governanca, nunca dado de negocio.';

-- ------------------------------------------------------------
-- 1. As fontes conhecidas e classificadas
-- ------------------------------------------------------------
create table if not exists registry.fontes (
  id              uuid primary key default gen_random_uuid(),

  -- onde a fonte mora. Nao ha FK para pg_class: uma fonte pode ser
  -- descontinuada e a classificacao dela continua sendo historia util.
  schema_nome     text not null,
  objeto          text not null,

  -- o que ela e
  conceito        text,
  produto         text,
  rota            text,

  -- proveniencia canonica de PROJECT_STATE.md secao 8. Seis valores,
  -- nao quatro: quem classifica precisa poder dizer que nao sabe, e
  -- LEGACY_DUPLICATE e veredito de auditoria, nao chute.
  natureza        text not null default 'UNKNOWN'
                  check (natureza in ('SOURCE','MIRROR','LOCAL_AUTHORITATIVE',
                                      'DERIVED','LEGACY_DUPLICATE','UNKNOWN')),

  -- Quem manda no fato. Lista fechada: autoridade em texto livre vira
  -- vocabulario paralelo em duas semanas.
  --
  -- 'yazo' continua na lista, mas NAO e a autoridade do credenciamento
  -- (ver mind_registry_propor). Fica disponivel para um fato que seja
  -- genuinamente interno da ferramenta deles, se aparecer. Se nunca
  -- aparecer, o valor sai numa migration de uma linha — estreitar
  -- CHECK e barato, alargar depois de ter dado e que e caro.
  autoridade      text not null default 'desconhecida'
                  check (autoridade in ('mind','hubspot','eduzz','yazo',
                                        'learnworlds','desconhecida')),

  observacao      text,

  -- uma classificacao vigente por fonte; as anteriores viram historia
  status          text not null default 'ativa'
                  check (status in ('ativa','substituida')),

  aprovado_por    uuid,
  aprovado_em     timestamptz,
  pendencia_id    uuid,
  criado_em       timestamptz not null default now()
);

comment on table registry.fontes is
  'Uma linha por fonte de dado conhecida e classificada: onde mora, de que produto fala, qual rota pode consumi-la, que natureza tem e quem manda no fato. Uma classificacao ativa por fonte; as anteriores ficam como substituida.';

comment on column registry.fontes.natureza is
  'O que esta TABELA e, mecanicamente: copia de algo de fora (MIRROR), casa autoral (LOCAL_AUTHORITATIVE), conclusao de outra coisa (DERIVED). Responde "como o dado chegou aqui".';

comment on column registry.fontes.autoridade is
  'Quem manda no FATO, que e outra pergunta: quem o observou. Autoridade segue o processo, nao o fornecedor. MIRROR com autoridade mind nao e contradicao — e espelho de dado nosso operado por ferramenta de terceiro, como o credenciamento do Summit. Nao ajustar um campo para "combinar" com o outro.';

-- O que garante "uma versao vigente por chave" — mesmo desenho do
-- unique parcial de participante_memoria.
create unique index if not exists fontes_ativa_uk
  on registry.fontes (schema_nome, objeto)
  where status = 'ativa';

create index if not exists fontes_produto_idx  on registry.fontes (produto)    where status = 'ativa';
create index if not exists fontes_natureza_idx on registry.fontes (natureza)   where status = 'ativa';
create index if not exists fontes_autoridade_idx on registry.fontes (autoridade) where status = 'ativa';

-- ------------------------------------------------------------
-- 2. A fila de decisao
-- ------------------------------------------------------------
create table if not exists registry.pendencias (
  id              uuid primary key default gen_random_uuid(),

  tipo            text not null
                  check (tipo in ('fonte_nova','casa_nova','mudanca_proveniencia','conflito')),

  -- a chave de identidade da pendencia. Para fonte_nova e
  -- 'schema.objeto'; para conflito, o que estiver em disputa.
  chave           text not null,

  status          text not null default 'pendente'
                  check (status in ('pendente','aprovada','ajustada','ignorada')),

  motivo          text not null,

  -- o que a IA (ou a regra) sugeriu
  proposta        jsonb,
  proposta_modelo text,
  proposta_versao text,

  -- o que a pessoa escolheu. Diferente de proposta quando ela ajusta —
  -- e e essa diferenca que mede se a proposta esta boa.
  decisao         jsonb,

  criado_em       timestamptz not null default now(),
  resolvido_em    timestamptz,
  resolvido_por   uuid,
  ativado_em      timestamptz
);

comment on table registry.pendencias is
  'Uma linha por coisa detectada e ainda nao decidida sobre a estrutura do banco. Guarda separadamente o que a IA propos e o que a pessoa escolheu. Idempotente por indice unico parcial: a mesma coisa nao vira duas pendencias abertas.';

-- A idempotencia real. Por indice, nao por `if exists` na funcao: duas
-- rodadas do detector ao mesmo tempo nao criam duas pendencias.
create unique index if not exists pendencias_abertas_uk
  on registry.pendencias (tipo, chave)
  where status = 'pendente';

create index if not exists pendencias_status_idx
  on registry.pendencias (status, tipo, criado_em desc);

-- Pendencia decidida como aprovada/ajustada e ainda nao ativada fica
-- visivel de graca — e o modo de falha que este projeto ja cometeu tres
-- vezes: decidir e nunca executar.
create index if not exists pendencias_a_ativar_idx
  on registry.pendencias (resolvido_em)
  where status in ('aprovada','ajustada') and ativado_em is null;

alter table registry.fontes     enable row level security;
alter table registry.pendencias enable row level security;

-- Sem policy: nada de PostgREST direto. So as funcoes abaixo entram.
grant usage on schema registry to service_role;
grant select, insert, update, delete on registry.fontes     to service_role;
grant select, insert, update, delete on registry.pendencias to service_role;

commit;

-- ============================================================
-- As funcoes. Um escritor unico por coisa, como manda
-- docs/CORE_UNIVERSAL.md:103.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 3. mind_registry_propor — a classificacao proposta
-- ------------------------------------------------------------
-- PROPOE, NUNCA DECIDE (BACKLOG.md:662).
--
-- Comeca deterministica de proposito: regra sobre schema e chave
-- estrangeira explica a maior parte dos casos, e regra errada e visivel
-- e corrigivel — palpite de modelo nao e. So ganha LLM se as regras se
-- mostrarem insuficientes, o que da para medir depois da primeira
-- dezena de pendencias: e so contar quantas foram AJUSTADAS em vez de
-- APROVADAS. As colunas proposta_modelo e proposta_versao ja existem
-- para o dia em que isso acontecer.
create or replace function public.mind_registry_propor(
  p_schema text,
  p_objeto text
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_oid        oid;
  v_comentario text;
  v_natureza   text;
  v_autoridade text;
  v_produto    text;
  v_rota       text;
  v_conceito   text;
  v_fk_para    text[];
begin
  select c.oid into v_oid
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = p_schema and c.relname = p_objeto and c.relkind = 'r';

  if v_oid is null then
    return jsonb_build_object('ok', false, 'motivo', 'objeto_inexistente');
  end if;

  select coalesce(trim(d.description), '') into v_comentario
    from pg_description d where d.objoid = v_oid and d.objsubid = 0;

  -- para onde esta tabela aponta: e o sinal mais forte de a que
  -- assunto ela pertence
  select array_agg(distinct k.confrelid::regclass::text)
    into v_fk_para
    from pg_constraint k
   where k.conrelid = v_oid and k.contype = 'f';

  -- Natureza, por schema. O schema no Mind ja carrega a intencao:
  -- crm e eduzz sao espelhos por construcao, agentes e catalogo sao
  -- autorais.
  v_natureza := case
    when p_schema in ('crm','eduzz','credenciamento_summit_2026','learnworlds') then 'MIRROR'
    when p_schema in ('agentes','catalogo','concierge','mind','seguranca','registry') then 'LOCAL_AUTHORITATIVE'
    when p_schema in ('engagement','pessoas','checkout','treble') then 'LOCAL_AUTHORITATIVE'
    when p_schema in ('intelligence') then 'DERIVED'
    else 'UNKNOWN'
  end;

  -- Autoridade, pela origem real do fato (PROJECT_STATE.md secao 8).
  --
  -- A REGRA: autoridade segue o PROCESSO, nao o FORNECEDOR. A pergunta
  -- nao e "em que sistema o dado esta", e "quem observou o fato".
  --
  --   Eduzz e LearnWorlds observam fato que nos NAO conseguimos observar
  --   — se o pagamento liquidou, se a pessoa assistiu. Autoridade deles
  --   de verdade: trocar de fornecedor muda quem observa.
  --
  --   A Yazo NAO observa nada nosso. O credenciamento acontece na nossa
  --   porta, no nosso evento, pela nossa equipe; a Yazo e a ferramenta
  --   que o opera, e daria para ter feito no papel. Por isso
  --   credenciamento_summit_2026 e 'mind', nao 'yazo' — correcao da
  --   Adriana em 21/09/2026. Trocar a Yazo no ano que vem nao move a
  --   autoridade.
  v_autoridade := case
    when p_schema = 'crm'                        then 'hubspot'
    when p_schema = 'eduzz'                      then 'eduzz'
    when p_schema = 'credenciamento_summit_2026' then 'mind'
    when p_schema = 'learnworlds'                then 'learnworlds'
    when v_natureza = 'LOCAL_AUTHORITATIVE'      then 'mind'
    else 'desconhecida'
  end;

  -- Produto, pelo schema quando ele e de produto
  v_produto := case
    when p_schema in ('summit_2026','credenciamento_summit_2026') then 'summit'
    when p_schema in ('institute')                                then 'institute'
    when p_schema in ('dash')                                     then 'dash'
    else null
  end;

  -- Rota que pode consumir. So onde a ligacao e inequivoca; no resto,
  -- null — e null aqui e honesto, nao preguica.
  v_rota := case
    when p_schema = 'concierge'                                   then 'concierge'
    when p_schema in ('checkout','catalogo')                      then 'vendas'
    when p_schema in ('summit_2026','credenciamento_summit_2026') then 'concierge'
    else null
  end;

  -- Conceito: a primeira frase do comentario, quando existe. O texto
  -- foi escrito para explicar a tabela; reescrever aqui seria inventar.
  v_conceito := nullif(trim(split_part(v_comentario, '.', 1)), '');

  return jsonb_build_object(
    'ok',          true,
    'schema_nome', p_schema,
    'objeto',      p_objeto,
    'conceito',    v_conceito,
    'produto',     v_produto,
    'rota',        v_rota,
    'natureza',    v_natureza,
    'autoridade',  v_autoridade,
    -- NATUREZA e AUTORIDADE respondem perguntas diferentes, e a
    -- combinacao que parece contraditoria e justamente a informativa.
    -- Sem esta linha, alguem le `MIRROR` + `mind`, acha que e erro, e
    -- "conserta" um dos dois — desfazendo a correcao de 21/09. O
    -- credenciamento e o caso exato: a tabela e mecanicamente um
    -- espelho, e o fato continua sendo nosso.
    'leitura', case
      when v_natureza = 'MIRROR' and v_autoridade = 'mind'
        then 'Espelho de dado NOSSO, operado por ferramenta de terceiro. A tabela e copia; o fato e do Mind. Nao trocar um dos dois para "ficarem coerentes": eles respondem perguntas diferentes.'
      when v_natureza = 'MIRROR'
        then 'Espelho de fato que nasce fora. A origem continua mandando; esta copia nao vira segunda fonte autoral.'
      when v_natureza = 'LOCAL_AUTHORITATIVE'
        then 'Casa autoral do Mind: o fato nasce aqui.'
      when v_natureza = 'DERIVED'
        then 'Derivada de outra coisa. Nao e fonte: e conclusao.'
      else 'Sem natureza determinada pela regra — precisa de olho humano.'
    end,
    'evidencia',   jsonb_build_object(
      'tem_comentario', v_comentario <> '',
      'aponta_para',    coalesce(to_jsonb(v_fk_para), '[]'::jsonb),
      'colunas',        (select count(*) from pg_attribute a
                          where a.attrelid = v_oid and a.attnum > 0 and not a.attisdropped),
      'linhas',         (xpath('/row/c/text()',
                          query_to_xml(format('select count(*) as c from %I.%I', p_schema, p_objeto),
                          false, true, '')))[1]::text::bigint,
      'tem_rls',        (select c.relrowsecurity from pg_class c where c.oid = v_oid)
    ),
    'confianca', case when v_natureza = 'UNKNOWN' or v_comentario = '' then 'baixa' else 'media' end
  );
end $$;

comment on function public.mind_registry_propor(text,text) is
  'Propoe a classificacao de uma fonte lendo o catalogo: schema, comentario, chaves e contagem. Deterministica de proposito. PROPOE, NUNCA DECIDE.';

-- ------------------------------------------------------------
-- 4. mind_registry_registrar — o escritor unico de pendencias
-- ------------------------------------------------------------
-- Idempotente pelo indice unico parcial, nao por checagem previa:
-- `on conflict do nothing` deixa o banco resolver a corrida. Duas
-- rodadas do detector ao mesmo tempo nao criam duas pendencias.
create or replace function public.mind_registry_registrar(
  p_tipo    text,
  p_chave   text,
  p_motivo  text,
  p_proposta jsonb   default null,
  p_modelo   text    default null,
  p_versao   text    default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare v_id uuid;
begin
  if p_chave is null or btrim(p_chave) = '' then
    raise exception using errcode = '22023', message = 'chave_obrigatoria';
  end if;
  if p_tipo not in ('fonte_nova','casa_nova','mudanca_proveniencia','conflito') then
    raise exception using errcode = '22023', message = 'tipo_de_pendencia_invalido';
  end if;
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception using errcode = '22023', message = 'motivo_obrigatorio';
  end if;

  insert into registry.pendencias (tipo, chave, motivo, proposta, proposta_modelo, proposta_versao)
  values (p_tipo, btrim(p_chave), p_motivo, p_proposta, p_modelo, p_versao)
  on conflict do nothing
  returning id into v_id;

  -- v_id nulo significa que ja havia uma pendencia aberta para a mesma
  -- coisa. Nao e erro: e a idempotencia funcionando.
  if v_id is null then
    return jsonb_build_object('ok', true, 'criada', false, 'motivo', 'ja_pendente');
  end if;
  return jsonb_build_object('ok', true, 'criada', true, 'id', v_id);
end $$;

comment on function public.mind_registry_registrar(text,text,text,jsonb,text,text) is
  'Escritor unico de registry.pendencias. Idempotente pelo indice unico parcial where status=pendente: a mesma coisa nao vira duas pendencias abertas.';

-- ------------------------------------------------------------
-- 5. mind_registry_pendencias — a leitura
-- ------------------------------------------------------------
create or replace function public.mind_registry_pendencias(
  p_status text    default 'pendente',
  p_tipo   text    default null,
  p_limite integer default 50,
  p_offset integer default 0
) returns table (
  id uuid, tipo text, chave text, status text, motivo text,
  proposta jsonb, decisao jsonb, proposta_modelo text, proposta_versao text,
  criado_em timestamptz, resolvido_em timestamptz, resolvido_por uuid,
  ativado_em timestamptz, a_ativar boolean
)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select p.id, p.tipo, p.chave, p.status, p.motivo,
         p.proposta, p.decisao, p.proposta_modelo, p.proposta_versao,
         p.criado_em, p.resolvido_em, p.resolvido_por, p.ativado_em,
         (p.status in ('aprovada','ajustada') and p.ativado_em is null) as a_ativar
    from registry.pendencias p
   where (p_status is null or p.status = p_status)
     and (p_tipo   is null or p.tipo   = p_tipo)
   order by p.criado_em desc
   limit greatest(coalesce(p_limite, 50), 1)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

comment on function public.mind_registry_pendencias(text,text,integer,integer) is
  'Le a fila de decisao. A coluna a_ativar expoe pendencia decidida e nunca executada — o modo de falha que este sistema ja cometeu tres vezes.';

commit;

begin;

-- ------------------------------------------------------------
-- 6. mind_registry_resolver — a decisao
-- ------------------------------------------------------------
-- RESOLVER NAO ATIVA. Aqui so se registra o que a pessoa decidiu; quem
-- grava a fonte e mind_registry_ativar. E a mesma separacao que
-- mind_pendencia_resolver ja pratica ("NAO executa merge: so registra a
-- decisao") — e a razao e que decidir e executar falham por motivos
-- diferentes e devem poder ser auditados separadamente.
--
-- Diferente do canonico, AQUI O PAPEL E CHECADO. `mind_pendencia_resolver`
-- nao checa nada: qualquer service_role resolve 1.604 pendencias de
-- identidade. Este nao repete isso.
create or replace function public.mind_registry_resolver(
  p_id         uuid,
  p_status     text,
  p_decisao    jsonb default null,
  p_actor_id   uuid  default null,
  p_request_id uuid  default null,
  p_nota       text  default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_role  text;
  v_antes registry.pendencias%rowtype;
begin
  if p_status not in ('aprovada','ajustada','ignorada') then
    raise exception using errcode = '22023', message = 'status_de_resolucao_invalido';
  end if;

  -- O gate de papel, no modelo de mind_admin_mutate_resource:1569.
  select role into v_role
    from public.mind_admin_users
   where user_id = p_actor_id and active;

  if v_role is null or v_role not in ('administrador','aprovador') then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  end if;

  -- AJUSTADA exige dizer o que mudou. Sem isso, "ajustada" vira um
  -- sinonimo de "aprovada" e a medicao de qualidade da proposta — que e
  -- o que decide se vale trocar a regra por um modelo — se perde.
  if p_status = 'ajustada' and (p_decisao is null or p_decisao = '{}'::jsonb) then
    raise exception using errcode = '22023', message = 'ajuste_exige_decisao';
  end if;

  select * into v_antes from registry.pendencias where id = p_id;
  if v_antes.id is null then
    return jsonb_build_object('ok', false, 'motivo', 'pendencia_inexistente');
  end if;
  if v_antes.status <> 'pendente' then
    return jsonb_build_object('ok', false, 'motivo', 'ja_resolvida', 'status', v_antes.status);
  end if;

  update registry.pendencias
     set status        = p_status,
         decisao       = coalesce(p_decisao, proposta),
         resolvido_em  = now(),
         resolvido_por = p_actor_id
   where id = p_id;

  -- Quem decidiu o que, e quando. identidade_fusoes nao sabe isso.
  insert into public.mind_admin_audit
    (actor_user_id, action, resource, record_id, record_label,
     before_data, after_data, request_id)
  values
    (p_actor_id, 'resolver', 'registry_pendencia', p_id::text,
     v_antes.tipo || ': ' || v_antes.chave,
     to_jsonb(v_antes),
     jsonb_build_object('status', p_status, 'decisao', coalesce(p_decisao, v_antes.proposta), 'nota', p_nota),
     p_request_id);

  return jsonb_build_object(
    'ok', true, 'id', p_id, 'status', p_status,
    -- o proximo passo e explicito de proposito: aprovar nao ativa
    'proximo_passo', case when p_status in ('aprovada','ajustada')
                          then 'mind_registry_ativar' else null end);
end $$;

comment on function public.mind_registry_resolver(uuid,text,jsonb,uuid,uuid,text) is
  'Registra a decisao humana sobre uma pendencia e audita quem decidiu. Exige papel administrador ou aprovador. NAO ativa a fonte: isso e mind_registry_ativar.';

-- ------------------------------------------------------------
-- 7. mind_registry_ativar — o segundo passo, separado
-- ------------------------------------------------------------
-- Grava a classificacao decidida em registry.fontes. A classificacao
-- anterior da mesma fonte, se houver, vira 'substituida' — historia,
-- nao lixo: e assim que se responde "desde quando isto mudou".
--
-- ATIVAR NAO TORNA A FONTE CONSUMIVEL PELO AGENTE. Habilitar e uma
-- linha em agentes.kit_blocos, escrita por alguem. Classificar e dizer
-- o que a coisa e; injetar no Kit e outra decisao, com outro gate.
create or replace function public.mind_registry_ativar(
  p_id         uuid,
  p_actor_id   uuid default null,
  p_request_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_role   text;
  v_pend   registry.pendencias%rowtype;
  v_d      jsonb;
  v_schema text;
  v_objeto text;
  v_novo   uuid;
begin
  select role into v_role
    from public.mind_admin_users
   where user_id = p_actor_id and active;

  if v_role is null or v_role not in ('administrador','aprovador') then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  end if;

  select * into v_pend from registry.pendencias where id = p_id;
  if v_pend.id is null then
    return jsonb_build_object('ok', false, 'motivo', 'pendencia_inexistente');
  end if;
  if v_pend.status not in ('aprovada','ajustada') then
    return jsonb_build_object('ok', false, 'motivo', 'pendencia_nao_aprovada', 'status', v_pend.status);
  end if;
  if v_pend.ativado_em is not null then
    return jsonb_build_object('ok', true, 'ja_ativada', true, 'motivo', 'nada_a_fazer');
  end if;

  v_d      := coalesce(v_pend.decisao, v_pend.proposta, '{}'::jsonb);
  v_schema := coalesce(v_d->>'schema_nome', split_part(v_pend.chave, '.', 1));
  v_objeto := coalesce(v_d->>'objeto',      split_part(v_pend.chave, '.', 2));

  if v_schema = '' or v_objeto = '' then
    return jsonb_build_object('ok', false, 'motivo', 'destino_indeterminado');
  end if;

  -- a classificacao anterior vira historia, nao some
  update registry.fontes
     set status = 'substituida'
   where schema_nome = v_schema and objeto = v_objeto and status = 'ativa';

  insert into registry.fontes
    (schema_nome, objeto, conceito, produto, rota, natureza, autoridade,
     observacao, status, aprovado_por, aprovado_em, pendencia_id)
  values
    (v_schema, v_objeto,
     v_d->>'conceito', v_d->>'produto', v_d->>'rota',
     coalesce(v_d->>'natureza',   'UNKNOWN'),
     coalesce(v_d->>'autoridade', 'desconhecida'),
     v_d->>'observacao', 'ativa', p_actor_id, now(), p_id)
  returning id into v_novo;

  update registry.pendencias set ativado_em = now() where id = p_id;

  insert into public.mind_admin_audit
    (actor_user_id, action, resource, record_id, record_label,
     before_data, after_data, request_id)
  values
    (p_actor_id, 'ativar', 'registry_fonte', v_novo::text,
     v_schema || '.' || v_objeto, null, v_d, p_request_id);

  return jsonb_build_object('ok', true, 'fonte_id', v_novo,
                            'fonte', v_schema || '.' || v_objeto,
                            'consumivel_pelo_agente', false);
end $$;

comment on function public.mind_registry_ativar(uuid,uuid,uuid) is
  'Grava em registry.fontes a classificacao ja decidida, substituindo a anterior sem apaga-la. Exige papel administrador ou aprovador. NAO torna a fonte consumivel pelo agente: isso e uma linha em agentes.kit_blocos.';

-- ------------------------------------------------------------
-- 8. Permissoes — so o service_role entra, e so pelas funcoes
-- ------------------------------------------------------------
revoke all on function public.mind_registry_propor(text,text)                            from public;
revoke all on function public.mind_registry_registrar(text,text,text,jsonb,text,text)    from public;
revoke all on function public.mind_registry_pendencias(text,text,integer,integer)        from public;
revoke all on function public.mind_registry_resolver(uuid,text,jsonb,uuid,uuid,text)     from public;
revoke all on function public.mind_registry_ativar(uuid,uuid,uuid)                       from public;

grant execute on function public.mind_registry_propor(text,text)                         to service_role;
grant execute on function public.mind_registry_registrar(text,text,text,jsonb,text,text) to service_role;
grant execute on function public.mind_registry_pendencias(text,text,integer,integer)     to service_role;
grant execute on function public.mind_registry_resolver(uuid,text,jsonb,uuid,uuid,text)  to service_role;
grant execute on function public.mind_registry_ativar(uuid,uuid,uuid)                    to service_role;

-- ------------------------------------------------------------
-- 9. Prova de que nasceu inteiro
-- ------------------------------------------------------------
do $$
declare n_tab int; n_fn int; n_idx int;
begin
  select count(*) into n_tab from pg_tables where schemaname = 'registry';
  select count(*) into n_fn  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname like 'mind_registry_%';
  select count(*) into n_idx from pg_indexes
   where schemaname = 'registry' and indexname in ('fontes_ativa_uk','pendencias_abertas_uk');

  if n_tab <> 2 then
    raise exception 'source_registry: esperava 2 tabelas em registry, encontrei %.', n_tab;
  end if;
  if n_fn <> 5 then
    raise exception 'source_registry: esperava 5 funcoes mind_registry_*, encontrei %.', n_fn;
  end if;
  -- os dois indices parciais sao a idempotencia inteira. Sem eles as
  -- tabelas existem e a garantia, nao.
  if n_idx <> 2 then
    raise exception 'source_registry: os indices unicos parciais nao foram criados (encontrei %). Sem eles nao ha idempotencia.', n_idx;
  end if;
end $$;

commit;
