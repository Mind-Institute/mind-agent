-- Painel Agent Intelligence, 22/10/2026 — três consertos observados nos logs com a Adriana usando a tela.
--
-- 1) "Liga/desliga trava 125 s e devolve 503". As funções do painel sinalizam conflito de versão com
--    errcode 40001 (serialization_failure). O PostgREST trata 40001 como falha transitória e REPETE a
--    chamada até o gateway desistir (504 após ~125 s); o log do Postgres mostra dezenas de
--    `admin_conflict` em 300 ms para o mesmo pedido. O conflito passa a 55000
--    (object_not_in_prerequisite_state), que ninguém repete. As Edge mapeiam pelo texto
--    `admin_conflict`, então nada muda para a tela além de responder em milissegundos.
do $$
declare
  r record;
  src text;
begin
  for r in
    select p.oid, p.proname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prosrc like '%40001%'
  loop
    src := pg_get_functiondef(r.oid);
    src := replace(src, 'errcode = ''40001''', 'errcode = ''55000''');
    src := replace(src, 'errcode=''40001''', 'errcode=''55000''');
    if src like '%40001%' then
      raise exception 'função % cita 40001 em outro contexto; revisar à mão', r.proname;
    end if;
    execute src;
  end loop;
end $$;

-- 2) "Gerar embeddings não funciona". O indexador chama mind_knowledge_preparar_chunks a cada rodada e a
--    função refazia TODOS os trechos (2,9 mi de caracteres de transcrição) toda vez: passa de 8 s e o
--    PostgREST cancela (statement_timeout do authenticator). Agora só entra documento sem trecho ou cujo
--    hash mudou; o resto é pulado. Com nada novo, a chamada volta em milissegundos.
CREATE OR REPLACE FUNCTION public.mind_knowledge_preparar_chunks(p_schema text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_count integer;
  v_trechos integer := 0;
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

  -- Caminho geral (todo documento que não é transcrição/slides do Summit).
  -- Incremental: documento cujo primeiro trecho já carrega o hash atual é pulado.
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
      and (%L <> 'summit_2026' or coalesce(d.tipo_conteudo,'') not in ('transcricao','slides'))
      and not exists (
        select 1 from %I.knowledge_chunks c
         where c.doc_id = d.id and c.ordem = 1 and c.indice = 'principal'
           and c.metadata->>'document_hash' = d.hash)
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
  $sql$,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema);

  get diagnostics v_count=row_count;

  if p_schema = 'summit_2026' then
    with docs as (
      select d.id, d.hash, d.titulo, d.tipo_conteudo tipo, d.corpo, d.sessao_id,
             coalesce(nullif(btrim(s.titulo),''), d.titulo) sessao,
             coalesce(nullif(btrim(d.metadata->'cabecalho'->>'Palestrantes'),''),
                      nullif(btrim(d.metadata->>'speaker'),''),
                      (select string_agg(pe.nome, ', ' order by pe.nome)
                         from summit_2026.session_speakers ss
                         join ecossistema.palestrantes_especialistas pe on pe.id = ss.speaker_id
                        where ss.sessao_id = d.sessao_id)) palestrantes
        from summit_2026.knowledge_documents d
        left join summit_2026.sessions s on s.id = d.sessao_id
       where d.ativo and d.tipo_conteudo in ('transcricao','slides')
         and btrim(coalesce(d.corpo,'')) <> ''
         -- Incremental: transcrição já fatiada com o hash atual não é refeita.
         and not exists (
           select 1 from summit_2026.knowledge_chunks c
            where c.doc_id = d.id and c.ordem = 1 and c.indice = 'principal'
              and c.metadata->>'document_hash' = d.hash)
    ), pedacos as (
      select d.id doc_id, p.ord, q.n, substr(p.txt, 1 + (q.n-1)*3000, 3000) txt
        from docs d
        cross join lateral regexp_split_to_table(d.corpo, E'\n\\s*\n') with ordinality p(txt, ord)
        cross join lateral generate_series(1, greatest(1, ceil(length(p.txt)/3000.0)::int)) q(n)
       where btrim(p.txt) <> ''
    ), acumulado as (
      select doc_id, ord, n, txt,
             coalesce(sum(length(txt)+2) over (partition by doc_id order by ord, n
                      rows between unbounded preceding and 1 preceding), 0) antes
        from pedacos
    ), grupos as (
      select doc_id, (antes / 3000)::int grp,
             string_agg(btrim(txt), E'\n\n' order by ord, n) corpo,
             (array_agg(substring(txt from '^\s*\[(\d{2}:\d{2}:\d{2})\]') order by ord, n)
                filter (where txt ~ '^\s*\[\d{2}:\d{2}:\d{2}\]'))[1] inicio,
             (array_agg(substring(txt from '^\s*\[(\d{2}:\d{2}:\d{2})\]') order by ord desc, n desc)
                filter (where txt ~ '^\s*\[\d{2}:\d{2}:\d{2}\]'))[1] fim
        from acumulado
       group by doc_id, (antes / 3000)::int
    ), trechos as (
      select g.*, dense_rank() over (partition by g.doc_id order by g.grp)::int ordem from grupos g
    ), finais as (
      select t.doc_id, t.ordem, t.inicio, t.fim, d.hash, d.titulo, d.sessao_id, d.tipo, d.palestrantes,
             case when d.tipo = 'transcricao'
               then concat_ws(' · ', 'Transcrição', d.sessao, d.palestrantes,
                      case when t.inicio is not null then
                        '[' || t.inicio || case when t.fim is distinct from t.inicio then '–' || t.fim else '' end || ']'
                      end)
               else concat_ws(' · ', 'Slides', d.sessao, d.palestrantes, 'parte ' || t.ordem)
             end || E'\n\n' || t.corpo texto
        from trechos t join docs d on d.id = t.doc_id
    ), gravados as (
      insert into summit_2026.knowledge_chunks
        (doc_id,ordem,texto,metadata,embedding,stale,embedado_em,modelo_embedding,indice)
      select f.doc_id, f.ordem, f.texto,
             jsonb_strip_nulls(jsonb_build_object(
               'document_hash', f.hash, 'titulo', f.titulo, 'tipo', f.tipo,
               'sessao_id', f.sessao_id, 'palestrantes', f.palestrantes,
               'inicio', f.inicio, 'fim', f.fim)),
             null, true, null, null, 'principal'
        from finais f
      on conflict (doc_id,ordem,indice) do update
      set texto=excluded.texto,
          metadata=excluded.metadata,
          embedding=case when summit_2026.knowledge_chunks.texto is distinct from excluded.texto
                         then null else summit_2026.knowledge_chunks.embedding end,
          stale=case when summit_2026.knowledge_chunks.texto is distinct from excluded.texto
                     then true else summit_2026.knowledge_chunks.stale end,
          embedado_em=case when summit_2026.knowledge_chunks.texto is distinct from excluded.texto
                           then null else summit_2026.knowledge_chunks.embedado_em end,
          modelo_embedding=case when summit_2026.knowledge_chunks.texto is distinct from excluded.texto
                                then null else summit_2026.knowledge_chunks.modelo_embedding end
      returning 1
    ), esvaziados as (
      update summit_2026.knowledge_chunks c
         set texto = '', embedding = null, stale = true, embedado_em = null, modelo_embedding = null,
             metadata = c.metadata || jsonb_build_object('trecho_removido', true)
        from (select doc_id, max(ordem) ultimo from finais group by doc_id) u
       where c.doc_id = u.doc_id and c.indice = 'principal' and c.ordem > u.ultimo and c.texto <> ''
      returning 1
    )
    select count(*) into v_trechos from gravados;
  end if;

  return v_count + v_trechos;
end;
$function$;

-- 3) Conversas por agente: a lista mascarava o JSON de TODAS as análises de 90 dias só para contar
--    analisadores, e passava de 8 s (57014 nos logs). A máscara agora só roda no detalhe (p_id dado)
--    e a lista corta nas 300 conversas mais recentes antes de juntar mensagens.
CREATE OR REPLACE FUNCTION public.mind_admin_read_agent_conversations(p_id text DEFAULT NULL::text)
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with conv as (
    select c.id, c.canal, c.agente, c.iniciada_em, c.ultima_atividade, c.mind_id, c.nome_contato,
           coalesce((c.variables->>'teste')::boolean, false) as teste
      from engagement.conversas c
     where (p_id is null
            and c.ultima_atividade > now() - interval '90 days'
            and c.agente in ('mindagent-chat', 'mindagent-playground', 'treble-inbound-agent'))
        or c.id::text = p_id
     order by c.ultima_atividade desc
     limit case when p_id is null then 300 else 1 end
  ),
  msgs as (
    select m.conversa_id, m.papel, m.conteudo, m.criado_em, m.blocos,
           coalesce(m.blocos->>'rota_aplicada', m.blocos->>'rota') as rota
      from engagement.mensagens m
      join conv on conv.id = m.conversa_id
     where m.papel in ('lead', 'agente')
  ),
  agg as (
    select conversa_id,
           count(*) as n,
           count(*) filter (where papel = 'agente') as n_agente,
           coalesce(array_agg(distinct rota) filter (where papel = 'agente' and rota is not null), '{}') as rotas,
           (array_agg(rota order by criado_em desc) filter (where papel = 'agente' and rota is not null))[1] as rota
      from msgs
     group by conversa_id
  ),
  skills as (
    select m.conversa_id, array_agg(distinct f->>'nome') as skills
      from msgs m,
           jsonb_array_elements(case when jsonb_typeof(m.blocos->'ferramentas') = 'array'
                                     then m.blocos->'ferramentas' else '[]'::jsonb end) f
     where m.papel = 'agente' and f->>'nome' is not null
     group by m.conversa_id
  ),
  analises as (
    select a.conversa_id,
           array_agg(distinct a.analisador) as analisadores,
           case when p_id is null then null else
             jsonb_agg(jsonb_build_object(
               'analisador', a.analisador, 'analisadoEm', a.analisado_em, 'modelo', a.modelo,
               'dados', public.mind_admin_mascarar_jsonb(a.dados))
               order by a.analisado_em desc) end as lista
      from intelligence.analise_conversa a
      join conv on conv.id = a.conversa_id
     group by a.conversa_id
  )
  select jsonb_build_object(
    'id', conv.id,
    'canal', conv.canal,
    'agente', conv.agente,
    'teste', conv.teste,
    'rota', agg.rota,
    'rotas', to_jsonb(agg.rotas),
    'primeiroNome', nullif(split_part(coalesce(p.primeiro_nome, conv.nome_contato, ''), ' ', 1), ''),
    'iniciadaEm', conv.iniciada_em,
    'ultimaAtividade', conv.ultima_atividade,
    'mensagens', agg.n,
    'skills', to_jsonb(coalesce(sk.skills, '{}')),
    'analisadores', to_jsonb(coalesce(an.analisadores, '{}')),
    'falas', case when p_id is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
               'papel', m.papel,
               'texto', public.mind_admin_mascarar_contato(m.conteudo),
               'criadoEm', m.criado_em,
               'rota', m.rota,
               'modelo', m.blocos->>'model',
               'duracaoMs', case when m.blocos->>'duration_ms' ~ '^\d+(\.\d+)?$'
                                 then (m.blocos->>'duration_ms')::numeric end,
               'ferramentas', case when jsonb_typeof(m.blocos->'ferramentas') = 'array'
                                   then m.blocos->'ferramentas' else '[]'::jsonb end)
             order by m.criado_em)
        from msgs m where m.conversa_id = conv.id), '[]'::jsonb) end,
    'analises', case when p_id is null then '[]'::jsonb else coalesce(an.lista, '[]'::jsonb) end)
  from conv
  join agg on agg.conversa_id = conv.id and agg.n_agente > 0
  left join pessoas.pessoas p on p.id = conv.mind_id
  left join skills sk on sk.conversa_id = conv.id
  left join analises an on an.conversa_id = conv.id
  order by conv.ultima_atividade desc;
$function$;
