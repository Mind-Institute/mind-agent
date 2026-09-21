-- ============================================================
-- Remover o schema `eventos` — e antes, os cinco leitores dele
-- ============================================================
-- Projeto: mind-agent (ymnmotgglsrxmjmonwjz)
--
-- O QUE ISTO É
-- Pedido da Adriana em 21/09/2026: "apague eventos". O schema tem duas
-- tabelas (`knowledge_documents`, `knowledge_chunks`), ambas com ZERO
-- linhas desde a criação, feitas para uma base de conhecimento genérica
-- de eventos fora do Summit que nunca veio.
--
-- POR QUE NÃO É UM `DROP SCHEMA` DE UMA LINHA
-- Cinco funções vivas citam `eventos`, e o Postgres NÃO registra
-- dependência nenhuma delas (pg_depend = 0, medido em 21/09). Um
-- `drop schema eventos cascade` não derrubaria nenhuma: as cinco
-- sobreviveriam e quebrariam em execução, sem aviso no momento do drop.
--
--   função                                   | como toca `eventos`
--   -----------------------------------------|----------------------------
--   mind_intelligence_buscar_contextual      | LÊ as duas tabelas (UNION)
--   mind_intelligence_ler_contextual         | LÊ knowledge_documents
--   mind_knowledge_preparar_chunks           | 'eventos' numa allowlist
--   mind_intelligence_chunks_pendentes       | 'eventos' numa allowlist
--   mind_intelligence_embedding_registrar    | 'eventos' numa allowlist
--
-- As duas primeiras são `language sql`: o corpo inteiro é planejado a
-- cada chamada. Com a tabela ausente, a consulta INTEIRA falha — não só
-- o galho de `eventos`. E `mind_intelligence_buscar_contextual` é a
-- busca de conhecimento do agente (`_shared/agent-intelligence.ts`):
-- derrubar a tabela primeiro quebraria a busca para TODAS as rotas.
--
-- Por isso a ordem aqui é: primeiro reescrever as cinco funções sem o
-- galho, depois derrubar o schema, depois provar que nada mais o cita.
--
-- O QUE MUDA DE COMPORTAMENTO: NADA
-- Em `buscar_contextual`, `eventos` era o galho PADRÃO — a rota que não
-- fosse uma das seis conhecidas (`summit_b2c`, `summit_b2b`,
-- `concierge_summit`, `cliente_suporte`, `institute`, `dash`) lia dali.
-- Como a tabela sempre esteve vazia, essa rota sempre recebeu zero
-- candidatos. Sem o galho, recebe zero candidatos. Idem em
-- `ler_contextual`. As três allowlists passam a recusar 'eventos' com a
-- mensagem que já existe ("schema de knowledge não permitido") em vez
-- de aceitar e falhar em "relation does not exist" — erro mais claro,
-- mesmo resultado.
--
-- O QUE MUDA DE DECLARAÇÃO: UMA COISA, E VALE DIZER
-- Deixa de existir um lugar para conhecimento de rota que não seja de
-- produto. Antes isso era um acidente (galho para tabela vazia); agora
-- é fato declarado: o conhecimento do Mind vive em `summit_2026`,
-- `institute` e `dash`. Se um dia houver evento fora dessas três casas,
-- ele ganha casa própria pela Inbox do `registry` — não ressuscita este.
--
-- DE ONDE VEM O CÓDIGO DAS FUNÇÕES
-- Do banco vivo em 21/09/2026 (`pg_get_functiondef`), não do repositório.
-- O banco está à frente do repositório em 93 migrations
-- (MAPA_SUPABASE_20260921.md, divergência 5); copiar do arquivo
-- versionado poderia regredir uma alteração aplicada depois. As cinco
-- versões aqui são as vivas menos as linhas de `eventos`, e nada mais.
--
-- ORDEM EM RELAÇÃO A OUTRAS MIGRATIONS
-- `20260921160000_objetivo_declarado_por_tabela.sql` comenta as duas
-- tabelas de `eventos` e tem uma guarda que exige exatamente 89 tabelas
-- sem comentário. Ela precisa rodar ANTES desta — e roda, pelo carimbo.
-- Se alguém aplicar esta primeiro à mão, aquela falha alto na guarda
-- (87 <> 89) e em `comment on table eventos.*`; nada silencioso.
--
-- DESFAZER
-- O schema volta com `create schema eventos` e as duas tabelas do stub
-- (`20260829185445_historical_prod_stub.sql`); as cinco funções voltam
-- com o `create or replace` de `20260903110000_core_contexto_agentico_
-- unificado.sql` — ATENÇÃO à ressalva acima: aquele arquivo pode não
-- ser a versão viva. Não há dado a recuperar: as tabelas estavam vazias.
--
-- SEGURANÇA
-- Nenhuma tabela com dado é tocada. As cinco funções mantêm assinatura,
-- `security definer`, `set search_path to ''` e grants (o `create or
-- replace` preserva ACL). Migration é boundary de deploy: este arquivo
-- não foi executado contra produção.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. As três allowlists: sai 'eventos'
-- ------------------------------------------------------------
create or replace function public.mind_knowledge_preparar_chunks(p_schema text)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $$
declare
  v_count integer;
begin
  if p_schema not in ('summit_2026','institute','dash') then
    raise exception 'schema de knowledge não permitido';
  end if;

  execute format(
    'create unique index if not exists %I on %I.knowledge_chunks(doc_id,ordem,indice)',
    'knowledge_chunks_doc_ordem_indice_uidx', p_schema);
  execute format(
    'create index if not exists %I on %I.knowledge_chunks(stale desc,ordem,id) where embedding is null or stale or modelo_embedding is distinct from %L',
    'knowledge_chunks_embedding_pendente_idx',p_schema,'text-embedding-3-small');

  execute format($sql$
    insert into %I.knowledge_chunks
      (doc_id,ordem,texto,metadata,embedding,stale,embedado_em,modelo_embedding,indice)
    select d.id, g.ordem,
           substring(d.corpo from 1 + ((g.ordem-1)*3500) for 4000),
           jsonb_build_object('document_hash',d.hash,'titulo',d.titulo),
           null, true, null, null, 'principal'
    from %I.knowledge_documents d
    cross join lateral generate_series(
      1, greatest(1,ceil(length(coalesce(d.corpo,'')) / 3500.0)::int)
    ) g(ordem)
    where d.ativo and btrim(coalesce(d.corpo,''))<>''
    on conflict (doc_id,ordem,indice) do update
    set texto=excluded.texto,
        metadata=excluded.metadata,
        embedding=case
          when %I.knowledge_chunks.metadata->>'document_hash'
               is distinct from excluded.metadata->>'document_hash' then null
          else %I.knowledge_chunks.embedding end,
        stale=case
          when %I.knowledge_chunks.metadata->>'document_hash'
               is distinct from excluded.metadata->>'document_hash' then true
          else %I.knowledge_chunks.stale end,
        embedado_em=case
          when %I.knowledge_chunks.metadata->>'document_hash'
               is distinct from excluded.metadata->>'document_hash' then null
          else %I.knowledge_chunks.embedado_em end,
        modelo_embedding=case
          when %I.knowledge_chunks.metadata->>'document_hash'
               is distinct from excluded.metadata->>'document_hash' then null
          else %I.knowledge_chunks.modelo_embedding end
  $sql$,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema);

  get diagnostics v_count=row_count;
  return v_count;
end;
$$;

create or replace function public.mind_intelligence_chunks_pendentes(p_schema text, p_limite integer default 50)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $$
declare
  v_saida jsonb;
begin
  if p_schema not in ('summit_2026','institute','dash') then
    raise exception 'schema de knowledge não permitido';
  end if;

  execute format($sql$
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',id,'texto',texto,'metadata',metadata
    ) order by ordem,id),'[]'::jsonb)
    from (
      select id,texto,metadata,ordem
      from %I.knowledge_chunks
      where embedding is null or stale or modelo_embedding is distinct from 'text-embedding-3-small'
      order by stale desc,ordem,id
      limit $1
    ) pendentes
  $sql$,p_schema)
  into v_saida
  using least(100,greatest(1,coalesce(p_limite,50)));

  return v_saida;
end;
$$;

create or replace function public.mind_intelligence_embedding_registrar(p_schema text, p_chunk_id uuid, p_embedding vector, p_modelo text default 'text-embedding-3-small'::text)
 returns boolean
 language plpgsql
 security definer
 set search_path to ''
as $$
declare
  v_count integer;
begin
  if p_schema not in ('summit_2026','institute','dash') then
    raise exception 'schema de knowledge não permitido';
  end if;
  if p_modelo<>'text-embedding-3-small' then
    raise exception 'modelo de embedding não permitido';
  end if;

  execute format(
    'update %I.knowledge_chunks set embedding=$1,stale=false,embedado_em=now(),modelo_embedding=$2 where id=$3',
    p_schema
  ) using p_embedding,p_modelo,p_chunk_id;
  get diagnostics v_count=row_count;
  return v_count=1;
end;
$$;

-- ------------------------------------------------------------
-- 2. Os dois leitores: sai o galho de `eventos`
-- ------------------------------------------------------------
create or replace function public.mind_intelligence_buscar_contextual(p_necessidade text, p_limite integer default 6, p_rota text default null::text, p_canal text default null::text, p_produto_codigo text default null::text, p_embedding vector default null::vector)
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $$
  with cfg as (
    select least(10,greatest(1,coalesce(p_limite,6))) n,
           plainto_tsquery('portuguese',coalesce(btrim(p_necessidade),'')) q
  ), docs as (
    select 'summit_2026' origem,d.* from summit_2026.knowledge_documents d
    where coalesce(p_rota,'') in ('summit_b2c','summit_b2b','concierge_summit','cliente_suporte')
    union all
    select 'institute',d.* from institute.knowledge_documents d where p_rota='institute'
    union all
    select 'dash',d.* from dash.knowledge_documents d where p_rota='dash'
  ), permitidos as (
    select d.* from docs d
    where d.ativo
      and (d.valido_de is null or d.valido_de<=now())
      and (d.valido_ate is null or d.valido_ate>now())
      and (d.produto_codigo is null or p_produto_codigo is null or d.produto_codigo=p_produto_codigo)
      and (coalesce(p_canal,'')<>'whatsapp' or d.aprovado_treble)
      and (coalesce(p_canal,'')='whatsapp' or cardinality(d.agents)=0 or 'concierge'=any(d.agents))
  ), chunks as (
    select 'summit_2026' origem,c.* from summit_2026.knowledge_chunks c
    union all select 'institute',c.* from institute.knowledge_chunks c
    union all select 'dash',c.* from dash.knowledge_chunks c
  ), texto as (
    select c.origem,c.id,c.doc_id,
           row_number() over(order by ts_rank_cd(c.tsv,cfg.q) desc) pos
    from chunks c join permitidos d on d.origem=c.origem and d.id=c.doc_id cross join cfg
    where c.tsv@@cfg.q
    order by pos limit (select n*4 from cfg)
  ), vetor as (
    select c.origem,c.id,c.doc_id,
           row_number() over(order by c.embedding OPERATOR(public.<=>) p_embedding) pos
    from chunks c join permitidos d on d.origem=c.origem and d.id=c.doc_id cross join cfg
    where p_embedding is not null and c.embedding is not null and not c.stale
      and c.modelo_embedding='text-embedding-3-small'
    order by pos limit (select n*4 from cfg)
  ), fundido as (
    select origem,id,doc_id,sum(score) score
    from (
      select origem,id,doc_id,1.0/(60+pos) score from texto
      union all
      select origem,id,doc_id,1.0/(60+pos) score from vetor
    ) x group by origem,id,doc_id
  ), conhecimento as (
    select distinct on (d.origem,d.id)
      jsonb_build_object(
        'tipo','conhecimento','id',d.origem || ':' || d.id::text,
        'titulo',d.titulo,
        'resumo',left(c.texto,220),
        'fonte',d.origem,
        'score',round(f.score::numeric,6)) candidato,
      f.score
    from fundido f
    join chunks c on c.origem=f.origem and c.id=f.id
    join permitidos d on d.origem=f.origem and d.id=f.doc_id
    order by d.origem,d.id,f.score desc
  ), busca_evento as (
    select case when coalesce(p_rota,'') in ('summit_b2c','summit_b2b','concierge_summit','cliente_suporte')
      then public.mindagent_chat_search('mind-summit-2026',p_necessidade,(select n from cfg))
      else '{}'::jsonb end j
  ), outros as (
    select jsonb_build_object('tipo','palestrante','id',e->>'id','titulo',e->>'name',
      'resumo',nullif(concat_ws(' · ',nullif(e->>'role',''),nullif(e->>'organization','')),'')) candidato,
      0.01::double precision score
    from busca_evento,lateral jsonb_array_elements(coalesce(j->'speakers','[]'::jsonb)) e
    union all
    select jsonb_build_object('tipo','sessao','id',e->>'id','titulo',e->>'title',
      'resumo',nullif(concat_ws(' · ',nullif(e->>'type',''),nullif(e->>'starts_at_local',''),nullif(e->>'location','')),'')),
      0.01::double precision
    from busca_evento,lateral jsonb_array_elements(coalesce(j->'sessions','[]'::jsonb)) e
  ), todos as (
    select candidato,score from conhecimento
    union all select candidato,score from outros
  )
  select jsonb_build_object(
    'necessidade',p_necessidade,
    'escopo',jsonb_build_object('rota',p_rota,'canal',p_canal,'produto_codigo',p_produto_codigo),
    'motor',case when p_embedding is null then 'lexical' else 'hibrido' end,
    'candidatos',coalesce((select jsonb_agg(candidato order by score desc,candidato->>'titulo')
      from (select * from todos order by score desc limit (select n from cfg)) z),'[]'::jsonb),
    'total',coalesce((select count(*) from (select * from todos limit (select n from cfg)) z),0),
    'como_usar','Leia o candidato relevante com ler_intelligence. Resultado vazio não autoriza completar de memória.'
  );
$$;

create or replace function public.mind_intelligence_ler_contextual(p_tipo text, p_id text, p_rota text default null::text, p_canal text default null::text, p_produto_codigo text default null::text, p_corte integer default 1200)
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $$
  select case lower(coalesce(p_tipo,''))
    when 'palestrante' then public.mind_intelligence_ler('palestrante',p_id,p_corte)
    when 'sessao' then public.mind_intelligence_ler('sessao',p_id,p_corte)
    when 'conhecimento' then (
      with alvo as (
        select case when p_id like '%:%' then split_part(p_id,':',1) else 'summit_2026' end origem,
               case when p_id like '%:%' then split_part(p_id,':',2) else p_id end id
      ), docs as (
        select 'summit_2026' origem,d.* from summit_2026.knowledge_documents d
        union all select 'institute',d.* from institute.knowledge_documents d
        union all select 'dash',d.* from dash.knowledge_documents d
      )
      select jsonb_strip_nulls(jsonb_build_object(
        'tipo','conhecimento','id',d.origem || ':' || d.id::text,
        'titulo',d.titulo,'categoria',d.tipo_conteudo,'problema',d.problema,
        'resultado_desejado',d.resultado_desejado,'audiencia',d.audiencia,
        'cluster',d.cluster,'corpo',public.mind_txt_corta(d.corpo,greatest(200,least(4000,coalesce(p_corte,1200)))*3),
        'autor',d.autor,'url',d.url,'produto_codigo',d.produto_codigo))
      from docs d join alvo a on a.origem=d.origem and d.id::text=a.id
      where d.ativo
        and (d.valido_de is null or d.valido_de<=now())
        and (d.valido_ate is null or d.valido_ate>now())
        and (d.produto_codigo is null or p_produto_codigo is null or d.produto_codigo=p_produto_codigo)
        and (coalesce(p_canal,'')<>'whatsapp' or d.aprovado_treble)
        and (coalesce(p_canal,'')='whatsapp' or cardinality(d.agents)=0 or 'concierge'=any(d.agents))
        and (
          (p_rota in ('summit_b2c','summit_b2b','concierge_summit','cliente_suporte') and d.origem='summit_2026')
          or (p_rota='institute' and d.origem='institute')
          or (p_rota='dash' and d.origem='dash')
        )
      limit 1
    )
    else null end;
$$;

-- ------------------------------------------------------------
-- 3. Agora sim: ninguém mais lê, o schema pode sair
-- ------------------------------------------------------------
-- Guarda: se alguma linha tiver aparecido entre a medição e a aplicação,
-- parar. Apagar dado é decisão diferente de apagar casa vazia.
do $$
declare n bigint;
begin
  -- Reaplicar nao pode virar erro confuso: se o schema ja se foi, diz e segue.
  if not exists (select 1 from pg_namespace where nspname = 'eventos') then
    raise notice 'remover_schema_eventos: o schema ja nao existe; nada a apagar.';
    return;
  end if;
  execute 'select (select count(*) from eventos.knowledge_documents)'
       || ' + (select count(*) from eventos.knowledge_chunks)' into n;
  if n > 0 then
    raise exception
      'remover_schema_eventos: o schema tem % linha(s). Foi medido vazio em 21/09/2026 — algo gravou ali desde entao. Nao apagar sem olhar.', n;
  end if;
end $$;

drop schema if exists eventos cascade;

-- ------------------------------------------------------------
-- 4. Prova: nenhuma função do banco cita mais `eventos`
-- ------------------------------------------------------------
-- `\m` é fronteira de palavra e `_` conta como letra, então
-- `treble_eventos` e `jornada_eventos` — tabelas de outro assunto — não
-- casam. Só `eventos.` e o literal 'eventos'.
do $$
declare v_resto text;
begin
  select string_agg(p.pronamespace::regnamespace::text||'.'||p.proname, ', ' order by 1)
    into v_resto
    from pg_proc p
   where (p.prosrc ~* '\meventos\s*\.' or p.prosrc ~* '''eventos''')
     and (select count(*) from pg_depend d join pg_extension e on e.oid=d.refobjid
           where d.objid=p.oid and d.deptype='e') = 0;

  if v_resto is not null then
    raise exception
      'remover_schema_eventos: ainda citam eventos e quebrariam em execucao: %', v_resto;
  end if;

  if exists (select 1 from pg_namespace where nspname = 'eventos') then
    raise exception 'remover_schema_eventos: o schema ainda existe.';
  end if;
end $$;

commit;
