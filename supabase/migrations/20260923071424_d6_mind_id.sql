-- ============================================================================
-- D6 — o ID universal da pessoa chama-se mind_id em toda tabela
-- ============================================================================
-- Pedido da Adriana, 23/09/2026: "varra todas as tabelas do banco e, nas colunas
-- onde a gente tem o universal ID, renomeie a coluna como universal MIND ID".
-- Nome escolhido: mind_id. Nas tabelas da Regra #1 (D5) as colunas companheiras
-- pessoa_criterio e pessoa_resolvido_em viram mind_id_criterio e mind_id_resolvido_em.
--
-- O que muda: o NOME das colunas (51 chaves estrangeiras para pessoas.pessoas:
-- pessoa_id em 20 tabelas, participante_id em 27, participant_id e person_id em 1
-- cada; mais duas colunas pessoa_id vazias e sem FK — crm.empenho_summit_2026 e
-- crm.pipeline_leads_inbound — que viram mind_id e ganham a FK que faltava), os
-- índices e constraints que carregam o nome antigo, e o corpo das 63 funções que
-- citam essas colunas. As 11 tabelas da Regra #1 (as 10 de D5 mais
-- controle_de_inscritos_e_presenca) têm as companheiras renomeadas.
--
-- O que NÃO é o ID universal e fica: "Check Ins Summit".participante_id,
-- "Reservas_Agenda_APP".participante_id e controle_de_inscritos_e_presenca.participante_id
-- (id do credenciamento, mapeado como credenciamento_id no trigger) e
-- yazo_envio_fila.participant_id (id de participantes, 11.404/11.404).
--
-- O que NÃO muda, de propósito: as CHAVES dos payloads devolvidos pelas funções
-- (pessoa_id, participante_id em jsonb e em "returns table") e os nomes de saída das
-- views — são contrato de API lido pelas Edge Functions (treble-inbound-agent,
-- mindagent-chat, hubspot-commercial-writeback, mindagent-avaliacao) e pelo app;
-- nenhuma Edge Function precisa de deploy por esta migration. Views e policies seguem
-- o rename sozinhas (o Postgres guarda a árvore, não o texto). Colunas de papel (de,
-- para, quem, sobre, participante_origem) e pessoas.pessoas.fundida_em não são o ID
-- universal da linha e ficam como estão.
--
-- Idempotente: cada rename só acontece se a coluna antiga ainda existir.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. As colunas
-- ----------------------------------------------------------------------------
do $$
declare r record; n int := 0;
begin
  for r in
    select * from (values
      ('checkout.compradores', 'pessoa_id'),
      ('checkout.pedidos', 'pessoa_id'),
      ('concierge.ciclo_estado', 'participante_id'),
      ('concierge.ferramenta_chamadas', 'participante_id'),
      ('concierge.integracao_logs', 'participante_id'),
      ('concierge.proativo_fila', 'participante_id'),
      ('credenciamento_summit_2026."Check Ins Summit"', 'pessoa_id'),
      ('credenciamento_summit_2026."Relatorio Yazzo Consolidado"', 'pessoa_id'),
      ('credenciamento_summit_2026."Reservas_Agenda_APP"', 'pessoa_id'),
      ('credenciamento_summit_2026.controle_de_inscritos_e_presenca', 'pessoa_id'),
      ('credenciamento_summit_2026.participantes', 'pessoa_id'),
      ('credenciamento_summit_2026.yazo_espelho', 'pessoa_id'),
      ('crm.acessos', 'pessoa_id'),
      ('crm.consents', 'participante_id'),
      ('crm.contato_espelho', 'pessoa_id'),
      ('crm.empenho_summit_2026', 'pessoa_id'),
      ('crm.leads_capturados', 'pessoa_id'),
      ('crm.pessoa_nps', 'pessoa_id'),
      ('crm.pessoa_produtos', 'pessoa_id'),
      ('crm.pessoas_interno', 'pessoa_id'),
      ('crm.pipeline_de_vendas_summit', 'pessoa_id'),
      ('crm.pipeline_leads_inbound', 'pessoa_id'),
      ('crm.vendas_historicas_mind_summit', 'pessoa_id'),
      ('ecossistema.perfis_publicos', 'pessoa_id'),
      ('eduzz.ingressos', 'pessoa_id'),
      ('eduzz.vendas', 'pessoa_id'),
      ('engagement.agent_sessions', 'participante_id'),
      ('engagement.agente_eventos', 'participante_id'),
      ('engagement.avaliacao_do_dia', 'participante_id'),
      ('engagement.avaliacao_do_evento', 'participante_id'),
      ('engagement.conversas', 'participante_id'),
      ('engagement.data_requests', 'participante_id'),
      ('engagement.evento_feedback', 'participante_id'),
      ('engagement.feedbacks', 'participante_id'),
      ('engagement.identidade_fusoes', 'participante_id'),
      ('engagement.identidades', 'pessoa_id'),
      ('engagement.jornada_eventos', 'participante_id'),
      ('engagement.jornada_sessao', 'participante_id'),
      ('engagement.mensagens', 'participante_id'),
      ('engagement.nps', 'participante_id'),
      ('engagement.pessoa_perfil', 'pessoa_id'),
      ('engagement.sessao_feedback', 'participante_id'),
      ('institute.programa_pessoas', 'pessoa_id'),
      ('intelligence.analise_conversa', 'participante_id'),
      ('intelligence.dossies', 'participante_id'),
      ('intelligence.participante_contexto', 'participante_id'),
      ('intelligence.participante_memoria', 'participante_id'),
      ('intelligence.participante_objetivos', 'participante_id'),
      ('intelligence.perguntas_feitas', 'participante_id'),
      ('intelligence.recomendacoes', 'participante_id'),
      ('intelligence.recovery_inbox', 'participant_id'),
      ('intelligence.sinais_comerciais', 'participante_id'),
      ('summit_2026.registrations', 'person_id')
    ) as v(tabela, coluna)
  loop
    if to_regclass(r.tabela) is null then
      raise notice 'mind_id: % nao existe; pulando', r.tabela; continue;
    end if;
    if exists (select 1 from pg_attribute where attrelid = to_regclass(r.tabela) and attname = r.coluna and not attisdropped) then
      execute format('alter table %s rename column %I to mind_id', r.tabela, r.coluna);
      n := n + 1;
    end if;
  end loop;
  raise notice 'mind_id: % colunas renomeadas', n;
end $$;

-- as companheiras da Regra #1
do $$
declare r record; n int := 0;
begin
  for r in
    select unnest(array[
      'crm.contato_espelho', 'crm.leads_capturados', 'eduzz.ingressos', 'eduzz.vendas',
      'credenciamento_summit_2026.participantes', 'credenciamento_summit_2026.yazo_espelho', 'checkout.pedidos',
      'credenciamento_summit_2026."Relatorio Yazzo Consolidado"', 'credenciamento_summit_2026."Reservas_Agenda_APP"',
      'credenciamento_summit_2026."Check Ins Summit"', 'credenciamento_summit_2026.controle_de_inscritos_e_presenca']) as tabela
  loop
    if to_regclass(r.tabela) is null then continue; end if;
    if exists (select 1 from pg_attribute where attrelid = to_regclass(r.tabela) and attname = 'pessoa_criterio' and not attisdropped) then
      execute format('alter table %s rename column pessoa_criterio to mind_id_criterio', r.tabela); n := n + 1;
    end if;
    if exists (select 1 from pg_attribute where attrelid = to_regclass(r.tabela) and attname = 'pessoa_resolvido_em' and not attisdropped) then
      execute format('alter table %s rename column pessoa_resolvido_em to mind_id_resolvido_em', r.tabela); n := n + 1;
    end if;
  end loop;
  raise notice 'mind_id: % colunas companheiras renomeadas', n;
end $$;

-- as duas colunas que eram pessoa_id sem FK (vazias em 23/09: 0 valores) ganham a FK que faltava
do $$
declare r record;
begin
  for r in select * from (values ('crm.empenho_summit_2026', 'empenho_summit_2026_mind_id_fkey'),
                                 ('crm.pipeline_leads_inbound', 'pipeline_leads_inbound_mind_id_fkey')) v(tabela, fk)
  loop
    if to_regclass(r.tabela) is null then continue; end if;
    if exists (select 1 from pg_attribute where attrelid = to_regclass(r.tabela) and attname = 'mind_id' and not attisdropped)
       and not exists (select 1 from pg_constraint c where c.conrelid = to_regclass(r.tabela) and c.contype = 'f' and c.confrelid = 'pessoas.pessoas'::regclass) then
      execute format('alter table %s add constraint %I foreign key (mind_id) references pessoas.pessoas(id)', r.tabela, r.fk);
    end if;
  end loop;
end $$;

-- ----------------------------------------------------------------------------
-- 2. Índices e constraints que carregam o nome antigo
-- ----------------------------------------------------------------------------
-- Só onde o nome antigo aparece como token seguido de "_" ou fim (cod_participante_idx
-- não é o ID universal e fica).
do $$
declare r record; v_novo text; n int := 0;
begin
  for r in
    select i.schemaname, i.indexname
      from pg_indexes i
     where i.schemaname not in ('pg_catalog','information_schema')
       and i.indexname ~ '(pessoa_id|participante_id|participant_id|person_id)(_|$)'
       and not exists (select 1 from pg_constraint c where c.conname = i.indexname)   -- os de constraint mudam com a constraint
  loop
    v_novo := left(regexp_replace(r.indexname, '(pessoa_id|participante_id|participant_id|person_id)(?=_|$)', 'mind_id', 'g'), 63);
    if v_novo <> r.indexname and to_regclass(format('%I.%I', r.schemaname, v_novo)) is null then
      execute format('alter index %I.%I rename to %I', r.schemaname, r.indexname, v_novo); n := n + 1;
    end if;
  end loop;
  for r in
    select c.conname, c.conrelid::regclass as tabela
      from pg_constraint c join pg_namespace ns on ns.oid = c.connamespace
     where ns.nspname not in ('pg_catalog','information_schema')
       and c.conname ~ '(pessoa_id|participante_id|participant_id|person_id)(_|$)'
  loop
    v_novo := left(regexp_replace(r.conname, '(pessoa_id|participante_id|participant_id|person_id)(?=_|$)', 'mind_id', 'g'), 63);
    if v_novo <> r.conname and not exists (select 1 from pg_constraint where conname = v_novo and conrelid = r.tabela) then
      execute format('alter table %s rename constraint %I to %I', r.tabela, r.conname, v_novo); n := n + 1;
    end if;
  end loop;
  raise notice 'mind_id: % indices/constraints renomeados', n;
end $$;

-- ----------------------------------------------------------------------------
-- 3. As funções que citavam as colunas (texto vivo de pg_get_functiondef, só com as substituições)
-- ----------------------------------------------------------------------------

-- bloco 0
-- crm.buscar_pessoa(p_email text, p_whatsapp text, p_agente text) | mudou: sim | 2 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION crm.buscar_pessoa(p_email text DEFAULT NULL::text, p_whatsapp text DEFAULT NULL::text, p_agente text DEFAULT 'desconhecido'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'crm', 'summit', 'comum', 'engagement', 'intelligence', 'mind'
AS $function$
declare
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_whats text := nullif(regexp_replace(coalesce(p_whatsapp, ''), '[^0-9]', '', 'g'), '');
  v_pessoa pessoas.pessoas%rowtype;
begin
  if v_whats is not null and length(v_whats) between 10 and 11 then
    v_whats := '55' || v_whats;
  end if;

  if v_email is null and v_whats is null then
    return jsonb_build_object('encontrado', false, 'motivo', 'sem_chave');
  end if;

  select * into v_pessoa from pessoas.pessoas
   where (v_email is not null and email = v_email)
   limit 1;

  if not found then
    select * into v_pessoa from pessoas.pessoas
     where (v_whats is not null and whatsapp = v_whats)
     limit 1;
  end if;

  if not found then
    return jsonb_build_object('encontrado', false, 'motivo', 'nao_cadastrado');
  end if;

  insert into crm.acessos (funcao, mind_id, agente)
  values ('crm.buscar_pessoa', v_pessoa.id, coalesce(p_agente, 'desconhecido'));

  return jsonb_build_object(
    'encontrado', true,
    'id', v_pessoa.id,
    'primeiro_nome', v_pessoa.primeiro_nome,
    'sobrenome', v_pessoa.sobrenome,
    'email', v_pessoa.email,
    'whatsapp', v_pessoa.whatsapp,
    'empresa', v_pessoa.empresa,
    'cargo', v_pessoa.cargo,
    'produtos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'codigo', pp.produto_codigo,
        'nome', pr.nome,
        'linha', pr.linha,
        'categoria', pp.categoria,
        'tipo_entrada', pp.tipo_entrada,
        'papel', pp.papel,
        'quantidade', pp.quantidade
      ) order by pr.comeca_em desc nulls last, pr.nome)
      from crm.pessoa_produtos pp
      join mind.produtos pr on pr.codigo = pp.produto_codigo
      where pp.mind_id = v_pessoa.id
    ), '[]'::jsonb),
    'dados_de', v_pessoa.sincronizado_em
  );
end;
$function$;

-- public.summit_status_pendentes(p_limit integer) | mudou: sim | 1 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.summit_status_pendentes(p_limit integer DEFAULT 100)
 RETURNS TABLE(contato_id text, valor text, motivo text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas', 'crm'
AS $function$
  select distinct on (p.hubspot_id) p.hubspot_id, 'Não engajou'::text,
         public.summit_motivo_exclusao(c.id)
  from engagement.conversas c
  join pessoas.pessoas p            on p.id = c.mind_id and p.hubspot_id is not null
  left join crm.contato_espelho ce  on ce.hubspot_id = p.hubspot_id
  where c.agente in ('treble','treble-inbound-agent')
    and public.summit_motivo_exclusao(c.id) is not null
    and not (string_to_array(coalesce(ce.summit__participacao_anual,''), ';') @> array['2026'])
    and coalesce(ce.status_summit_2026,'') is distinct from 'Não engajou'
    and not exists (select 1 from crm.status_summit_hs s
                     where s.hubspot_id = p.hubspot_id and s.valor = 'Não engajou')
  order by p.hubspot_id, c.ultima_atividade desc nulls last
  limit greatest(1, p_limit);
$function$;

-- public.mind_avaliacao_do_evento_respostas(p_event_slug text, p_experiencia text, p_pagina integer, p_por_pagina integer) | mudou: sim | 1 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_avaliacao_do_evento_respostas(p_event_slug text DEFAULT 'mind-summit-2026'::text, p_experiencia text DEFAULT NULL::text, p_pagina integer DEFAULT 1, p_por_pagina integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_evento summit_2026.events%rowtype;
  v_exp text := nullif(lower(btrim(coalesce(p_experiencia, ''))), '');
  v_pagina int := greatest(1, coalesce(p_pagina, 1));
  v_por int := least(500, greatest(1, coalesce(p_por_pagina, 50)));
  v_total bigint; v_itens jsonb;
begin
  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;
  if v_exp is not null and v_exp not in ('mind', 'vip', 'prime') then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:experiencia';
  end if;

  select count(*) into v_total
  from engagement.avaliacao_do_evento a
  where a.event_id = v_evento.id and (v_exp is null or a.experiencia = v_exp);

  select coalesce(jsonb_agg(x order by ordem), '[]'::jsonb) into v_itens
  from (
    select jsonb_build_object(
      'id', a.id,
      'enviadoEm', a.enviado_em,
      'origem', a.origem,
      'formularioVersao', a.formulario_versao,
      'nome', nullif(btrim(coalesce(p.primeiro_nome, '') || ' ' || coalesce(p.sobrenome, '')), ''),
      'email', p.email,
      'experiencia', a.experiencia,
      'profissao', a.profissao,
      'expectativas', a.expectativas,
      'notaRelevancia', a.nota_relevancia,
      'notaProgramacao', a.nota_programacao,
      'maisGostou', a.mais_gostou,
      'melhorar', a.melhorar,
      'comentario', a.comentario,
      'atividadesAvaliadas', (
        select count(*) from engagement.avaliacao_do_evento_atividade t
        where t.avaliacao_id = a.id)
    ) as x,
    a.enviado_em as ordem
    from engagement.avaliacao_do_evento a
    left join pessoas.pessoas p on p.id = a.mind_id
    where a.event_id = v_evento.id and (v_exp is null or a.experiencia = v_exp)
    order by a.enviado_em desc
    limit v_por offset (v_pagina - 1) * v_por
  ) pagina;

  return jsonb_build_object(
    'total', v_total, 'pagina', v_pagina, 'porPagina', v_por, 'itens', v_itens);
end;
$function$;

-- mind.esquecer_participante(p_participante uuid) | mudou: sim | 16 referências de coluna renomeadas (14 em tabelas da lista + 2 em nps_summit, relação inexistente no search_path)
-- REVISÃO (bloco 0): conferido no catálogo — nps_summit não existe em schema nenhum (só sobraram índices
--   nps_summit_pkey / nps_summit_participante_id_key em engagement.nps, que está na lista e vira mind_id;
--   logo mind_id é a escolha consistente). 'participantes' também não resolve no search_path desta função
--   (só existe em credenciamento_summit_2026), então a função já falha hoje no primeiro insert. Por ser
--   plpgsql, o CREATE OR REPLACE não valida tabelas e passa; comportamento em runtime segue idêntico ao atual.
CREATE OR REPLACE FUNCTION mind.esquecer_participante(p_participante uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'summit', 'comum', 'engagement', 'intelligence', 'mind', 'concierge', 'public'
AS $function$
declare
  v_anonimo uuid;
begin
  insert into participantes (anonimo, nome) values (true, 'Participante removido')
  returning id into v_anonimo;

  delete from participante_contexto where mind_id = p_participante;
  delete from participante_memoria  where mind_id = p_participante;
  delete from mensagens             where mind_id = p_participante;
  delete from conversas             where mind_id = p_participante;
  delete from dossies               where mind_id = p_participante;
  delete from sinais_comerciais     where mind_id = p_participante;

  update jornada_sessao   set mind_id = v_anonimo where mind_id = p_participante;
  update jornada_eventos  set mind_id = v_anonimo where mind_id = p_participante;
  update sessao_feedback  set mind_id = v_anonimo where mind_id = p_participante;
  update evento_feedback  set mind_id = v_anonimo where mind_id = p_participante;
  update nps_summit       set mind_id = v_anonimo where mind_id = p_participante;

  delete from participantes where id = p_participante;
end $function$;

-- public.silence_compra_summit_2026(p_conversa_id uuid) | mudou: sim | 1 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.silence_compra_summit_2026(p_conversa_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_hs        text;
  v_no_espelho boolean;
  v_anual     text;
begin
  select p.hubspot_id into v_hs
    from engagement.conversas c
    join pessoas.pessoas p on p.id = c.mind_id
   where c.id = p_conversa_id;

  if v_hs is null or btrim(v_hs) = '' then
    return 'unknown';           -- sem identidade nao da pra afirmar nada
  end if;

  -- 1) deal pago de 2026
  if exists (
    select 1
      from crm.negocio_contatos nc
      join crm.vendas_historicas_mind_summit nh on nh.hubspot_deal_id = nc.hubspot_deal_id
     where nc.contato_hubspot_id = v_hs
       and nh.status_de_pagamento = 'Pago'
       and nh.summit_year = '2026'
  ) then
    return 'purchased';
  end if;

  -- 2) espelho do contato: participacao anual marcada em 2026
  select true, e.summit__participacao_anual
    into v_no_espelho, v_anual
    from crm.contato_espelho e
   where e.hubspot_id = v_hs
   limit 1;

  if coalesce(v_anual,'') like '%2026%' then
    return 'purchased';
  end if;

  -- 3) o espelho conhece a pessoa e nao ha compra -> afirmacao legitima
  if coalesce(v_no_espelho, false) then
    return 'not_purchased';
  end if;

  return 'unknown';
end $function$;

-- concierge.resumo_do_dia(p_participante uuid, p_dia date) | mudou: sim | 9 referências de coluna renomeadas
-- REVISÃO (bloco 0): função JÁ MORTA em produção antes do rename — chamá-la hoje falha com
--   'relation "summit.sessions" does not exist' (schema summit não existe; sessions vive em summit_2026;
--   motivos_ausencia não existe em schema nenhum). Como é LANGUAGE sql e check_function_bodies=on (default do
--   projeto), o CREATE OR REPLACE abaixo seria validado na criação e abortaria a migration pelo mesmo erro.
--   Guarda mínima: desliga a validação de corpo SÓ para esta statement; o texto da função segue o original
--   com apenas as substituições (mind_id). Consertar summit.->summit_2026. ou dropar a função é decisão
--   fora do escopo do rename (lateral) — registrar para o supervisor.
set check_function_bodies = off;
CREATE OR REPLACE FUNCTION concierge.resumo_do_dia(p_participante uuid, p_dia date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'engagement', 'intelligence', 'summit', 'comum', 'concierge', 'mind', 'public'
AS $function$
  select jsonb_build_object(
    'objetivo', (
      select jsonb_build_object('pergunta_guia', o.pergunta_guia, 'dor', o.dor_codigo,
                                'decisao_pendente', o.decisao_pendente)
      from participante_objetivos o
      where o.mind_id = p_participante and o.status = 'ativo'
      order by o.definido_em desc limit 1),

    'contexto', (
      select jsonb_build_object('necessidades', c.necessidades,
                                'resultados_desejados', c.resultados_desejados,
                                'temas', c.temas_relevantes)
      from participante_contexto c where c.mind_id = p_participante),

    'planejadas', (
      select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'titulo', s.titulo,
                                                   'inicio', s.inicio)), '[]')
      from jornada_sessao j join summit.sessions s on s.id = j.sessao_id
      where j.mind_id = p_participante and j.planejou and s.dia = p_dia),

    'assistidas', (
      select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'titulo', s.titulo,
                                                   'fonte', j.fonte_presenca)), '[]')
      from jornada_sessao j join summit.sessions s on s.id = j.sessao_id
      where j.mind_id = p_participante and j.compareceu and s.dia = p_dia),

    'perdidas', (
      select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'titulo', s.titulo,
                                                   'motivo', j.motivo_ausencia,
                                                   'frustrada', coalesce(m.demanda_frustrada,false))), '[]')
      from jornada_sessao j
      join summit.sessions s on s.id = j.sessao_id
      left join motivos_ausencia m on m.codigo = j.motivo_ausencia
      where j.mind_id = p_participante and j.compareceu = false and s.dia = p_dia),

    'avaliacoes', (
      select coalesce(jsonb_agg(jsonb_build_object('titulo', s.titulo, 'nota', f.nota,
                                                   'insight', f.insight,
                                                   'aplicar', f.intencao_aplicar)), '[]')
      from sessao_feedback f join summit.sessions s on s.id = f.sessao_id
      where f.mind_id = p_participante and s.dia = p_dia),

    'sugestoes_ja_feitas', (
      select coalesce(jsonb_agg(distinct jsonb_build_object('titulo', s.titulo,
                                                            'porque', r.justificativa,
                                                            'estado', r.estado)), '[]')
      from recomendacoes r left join summit.sessions s on s.id = r.sessao_id
      where r.mind_id = p_participante),

    'problemas_operacionais', (
      select coalesce(jsonb_agg(jsonb_build_object('categoria', e.categoria,
                                                   'severidade', e.severidade)), '[]')
      from evento_feedback e
      where e.mind_id = p_participante and e.criado_em::date = p_dia),

    'amanha_disponiveis', (
      select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'titulo', s.titulo,
                                                   'inicio', s.inicio, 'espaco', s.espaco_id,
                                                   'topicos', s.topicos_aprendizado)), '[]')
      from summit.sessions s
      where s.dia > p_dia
        and s.id not in (select sessao_id from jornada_sessao
                         where mind_id = p_participante and compareceu))
  );
$function$;
reset check_function_bodies;


-- bloco 1
-- funcs_1.sql | rename pessoa_id/participante_id/participant_id/person_id -> mind_id | bloco 1
-- Fonte: pg_get_functiondef ao vivo em ymnmotgglsrxmjmonwjz (2026-09-23), reescrito segundo a regra de ouro:
--   MUDA  : referencia a COLUNA de tabela (inclui campo de variavel row-type, ex.: conv.participante_id -> conv.mind_id).
--   FICA  : parametro (p_pessoa_id), variavel local, chave JSON ('pessoa_id' em jsonb_build_object / ->>'pessoa_id'),
--           nome de GUC (current_setting('mind.person_id')), comentario.
-- create or replace preserva ACL/grants; security definer e set search_path mantidos como no original.

-- public.mind_inbound(p_evento jsonb) | mudou: sim | 7 referências de coluna renomeadas
-- renomeadas: conv.participante_id (x3, campo do row-type engagement.conversas), engagement.conversas.participante_id (set + where),
--             engagement.mensagens.participante_id (set + where).
-- mantidas: 'pessoa_id' em jsonb_build_object do default de v_ident, v_ident->>'pessoa_id' (saida de mind_identidade_resolver),
--           'pessoa_id' na chave de retorno (contrato lido pela Edge Function).
CREATE OR REPLACE FUNCTION public.mind_inbound(p_evento jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas', 'crm'
AS $function$
declare
  conv   engagement.conversas;
  v_msg  jsonb := jsonb_build_object('mensagem_id', null, 'duplicada', false);
  v_ident jsonb := jsonb_build_object('pessoa_id', null, 'criada', false, 'conflito', null);
  m      jsonb := coalesce(p_evento->'mensagem','{}'::jsonb);
  v_pessoa uuid;
  v_erro text := null;
  v_crm  jsonb := null;
begin
  conv := public.mind_conversa_resolver(p_evento);

  if m ? 'conteudo' or m ? 'blocos' then
    v_msg := public.mind_mensagem_registrar(
      conv.id, coalesce(m->>'papel','lead'), m->>'conteudo',
      coalesce(m->>'id_externo', m->>'client_message_id', m->>'external_message_id'),
      m->'blocos', coalesce(p_evento->>'agente', conv.canal));
  end if;

  begin
    v_ident := public.mind_identidade_resolver(
      coalesce(p_evento->'identificadores','{}'::jsonb),
      p_evento->>'nome', conv.canal, conv.mind_id);
  exception when others then
    v_erro := sqlerrm;
  end;

  v_pessoa := coalesce(conv.mind_id, nullif(v_ident->>'pessoa_id','')::uuid);

  if v_pessoa is not null then
    update engagement.conversas set mind_id = v_pessoa
     where id = conv.id and mind_id is null;
    update engagement.mensagens set mind_id = v_pessoa
     where conversa_id = conv.id and mind_id is null;
    conv.mind_id := v_pessoa;

    if coalesce((v_ident->>'criada')::boolean, false)
       or jsonb_array_length(coalesce(v_ident->'identidades','[]'::jsonb)) > 0 then
      begin
        v_crm := public.mind_crm_vincular_pessoa(v_pessoa);
      exception when others then
        v_crm := jsonb_build_object('ok', false, 'erro', sqlerrm);
      end;
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'canal', conv.canal, 'conversa_id', conv.id,
    'sessao_externa', conv.session_external_id,
    'mensagem_id', v_msg->'mensagem_id',
    'mensagem_duplicada', coalesce((v_msg->>'duplicada')::boolean, false),
    'pessoa_id', v_pessoa,
    'pessoa_criada', coalesce((v_ident->>'criada')::boolean, false),
    'pessoa_ancorada', coalesce((v_ident->>'ancorada')::boolean, false),
    'identidades_novas', v_ident->'identidades',
    'conflito_identidade', v_ident->'conflito',
    'identidade_erro', v_erro,
    'crm', v_crm,
    'origem_codigo', conv.origem_codigo, 'produto_codigo', conv.produto_codigo,
    'utm', conv.utm, 'nome_contato', conv.nome_contato,
    'audience', conv.audience, 'stage', conv.stage, 'variables', conv.variables);
end $function$;


-- public.mind_crm_comercial(p_pessoa_id uuid) | mudou: sim | 1 referência de coluna renomeada
-- renomeada: engagement.identidades.pessoa_id (i.pessoa_id -> i.mind_id).
-- mantidas: parametro p_pessoa_id; 'pessoa_id' como chave nos dois jsonb_build_object de retorno (contrato); mencao em comentario.
-- SQL dinamico (format ... from crm.%I t): nao referencia coluna de pessoa; to_jsonb(t) e consumido so por chaves de deal — sem mudanca.
CREATE OR REPLACE FUNCTION public.mind_crm_comercial(p_pessoa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'crm', 'catalogo', 'engagement', 'pessoas'
AS $function$
declare
  v_contatos    text[];
  v_consolidado jsonb := '[]'::jsonb;
  v_produtos    jsonb := '[]'::jsonb;
  v_sem_mapping integer := 0;
  v_codigos     text[] := array[]::text[];
  v_lead        jsonb := '[]'::jsonb;
  v_negociacoes jsonb := '[]'::jsonb;
  v_sem_espelho jsonb := '[]'::jsonb;
  v_fontes      text[] := array['crm.contato_espelho','crm.pipeline_leads_inbound',
                                'crm.vendas_historicas_mind_summit']::text[];
  v_relevantes  jsonb := '[]'::jsonb;
  v_superados   jsonb := '[]'::jsonb;
  v_refunds     jsonb := '[]'::jsonb;
  v_sync        jsonb;
  r             record;
  v_linhas      jsonb;
begin
  -- IDENTIDADE: so por engagement.identidades. Nunca pessoas.hubspot_id, nunca o pessoa_id
  -- legado das tabelas de CRM -- foi por ali que veio o overmerge por telefone corporativo.
  select array_agg(distinct i.identificador) into v_contatos
    from engagement.identidades i
   where i.mind_id = p_pessoa_id and i.canal = 'hubspot'
     and nullif(btrim(i.identificador), '') is not null;
  v_contatos := coalesce(v_contatos, array[]::text[]);

  v_sync := public.mind_crm_sync_frescor();

  if array_length(v_contatos, 1) is null then
    return jsonb_build_object('ok', true, 'pessoa_id', p_pessoa_id,
      'contato_consolidado','[]'::jsonb,'produtos','[]'::jsonb,
      'lead_atual','[]'::jsonb,'negociacoes','[]'::jsonb,
      'sinais_transacionais', jsonb_build_object(
        'relevantes','[]'::jsonb,'superados','[]'::jsonb,'refunds','[]'::jsonb),
      'meta', jsonb_build_object(
        'contatos_hubspot_considerados','[]'::jsonb,'sem_contato_hubspot',true,
        'fontes_lidas','[]'::jsonb,'pipelines_sem_espelho','[]'::jsonb,
        'evidencias_sem_mapping',0,'sync',v_sync));
  end if;

  -- 1. A REALIDADE DO CONTATO primeiro. Familia de propriedade comercial por nome --
  --    nao por mapa_produtos (que nao pode filtrar o que existe) e nao dump das ~170.
  -- 2. mapa_produtos so ENRIQUECE com o codigo canonico; sem mapping o fato continua la.
  with bruto as (
    select e.hubspot_id, kv.key as propriedade, btrim(tok) as valor
      from crm.contato_espelho e
      cross join lateral jsonb_each_text(coalesce(e.propriedades,'{}'::jsonb)) kv
      cross join lateral unnest(string_to_array(kv.value,';')) tok
     where e.hubspot_id = any(v_contatos)
       and btrim(coalesce(kv.value,'')) <> '' and btrim(tok) <> ''
       and (kv.key ~ '^(summit__|summit_papel|ingressos_comprados__|formacao__|certificacao_|journey__)'
            or kv.key in ('total_de_ingressos_comprados_lifetime','total_de_formacoes_no_instituto'))
  ),
  com_produto as (
    select b.hubspot_id, b.propriedade, b.valor,
           (select m.produto_codigo from crm.mapa_produtos m
             where m.propriedade = b.propriedade
               and (m.valor_origem = '*' or lower(m.valor_origem) = lower(b.valor))
             limit 1) as produto_codigo
      from bruto b
  )
  select coalesce(jsonb_agg(distinct jsonb_strip_nulls(jsonb_build_object(
           'hubspot_contact_id', c.hubspot_id,'propriedade', c.propriedade,
           'valor', c.valor,'produto_codigo', c.produto_codigo))),'[]'::jsonb),
         count(*) filter (where c.produto_codigo is null)
    into v_consolidado, v_sem_mapping from com_produto c;

  select coalesce(jsonb_agg(x.item order by x.produto_codigo),'[]'::jsonb),
         coalesce(array_agg(x.produto_codigo), array[]::text[])
    into v_produtos, v_codigos
    from (select ev.produto_codigo,
                 jsonb_build_object('produto_codigo', ev.produto_codigo,'nome', p.nome,
                   'vertical', p.vertical,
                   'evidencias', jsonb_agg(jsonb_build_object(
                     'hubspot_contact_id', ev.item ->> 'hubspot_contact_id',
                     'propriedade', ev.item ->> 'propriedade',
                     'valor', ev.item ->> 'valor'))) as item
            from (select el as item, el ->> 'produto_codigo' as produto_codigo
                    from jsonb_array_elements(v_consolidado) el
                   where el ->> 'produto_codigo' is not null) ev
            left join catalogo.produtos p on p.codigo = ev.produto_codigo
           group by ev.produto_codigo, p.nome, p.vertical) x;

  -- Lead Inbound: universal, sempre consultado, por hs_primary_contact_id
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'hubspot_lead_id', l.hubspot_lead_id,'hs_pipeline', l.hs_pipeline,
           'hs_pipeline_stage', l.hs_pipeline_stage,'hs_lead_label', l.hs_lead_label,
           'hs_lead_type', l.hs_lead_type,'hs_lead_source', l.hs_lead_source,
           'hs_primary_contact_id', l.hs_primary_contact_id,
           'hs_primary_company_id', l.hs_primary_company_id,
           'hs_associated_company_name', l.hs_associated_company_name,
           'nome_da_empresa', l.nome_da_empresa,'hubspot_owner_id', l.hubspot_owner_id,
           'hs_lead_associated_deals_count', l.hs_lead_associated_deals_count,
           'hs_lead_pipeline_value', l.hs_lead_pipeline_value,
           'hs_lead_closed_won_deals_amount', l.hs_lead_closed_won_deals_amount,
           'motivo_de_lead_perdido', l.motivo_de_lead_perdido,
           'hs_lead_disqualification_reason', l.hs_lead_disqualification_reason,
           'hs_lead_disqualification_note', l.hs_lead_disqualification_note,
           'hs_lead_is_open', coalesce(l.propriedades ->> 'hs_lead_is_open',
                                       l.propriedades ->> 'hs_lead_is_open_v2'),
           'hs_v2_date_entered_current_stage', l.hs_v2_date_entered_current_stage,
           'hs_createdate', l.hs_createdate,'hs_lastmodifieddate', l.hs_lastmodifieddate))
         order by l.hs_lastmodifieddate desc nulls last),'[]'::jsonb)
    into v_lead from crm.pipeline_leads_inbound l
   where l.hs_primary_contact_id = any(v_contatos);

  -- Negociacoes: produto -> pipelines_hubspot -> crm.sync_estado -> tabela. Sem hardcode.
  -- O identificador do SQL dinamico vem SEMPRE de crm.sync_estado, quotado com %I.
  for r in
    select p.codigo, p.vertical, pl.pipeline_id, s.tabela_destino, s.pipeline_nome
      from catalogo.produtos p
      cross join lateral unnest(coalesce(p.pipelines_hubspot, array[]::text[])) pl(pipeline_id)
      left join crm.sync_estado s on s.pipeline_id = pl.pipeline_id
     where p.ativo and p.vende order by p.codigo, pl.pipeline_id
  loop
    if r.tabela_destino is null then
      v_sem_espelho := v_sem_espelho || jsonb_build_object(
        'produto_codigo', r.codigo,'pipeline_id', r.pipeline_id,
        'motivo','sem linha em crm.sync_estado');
      continue;
    end if;

    execute format(
      'select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from crm.%I t
        where exists (select 1 from jsonb_array_elements_text(
                        coalesce(t.propriedades -> ''_contatos'', ''[]''::jsonb)) c(hid)
                       where c.hid = any($1))', r.tabela_destino)
      into v_linhas using v_contatos;

    v_fontes := array_append(v_fontes, 'crm.' || r.tabela_destino);

    select v_negociacoes || coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'produto_codigo', r.codigo,'vertical', r.vertical,
             'pipeline_id', r.pipeline_id,'pipeline_nome', r.pipeline_nome,
             'hubspot_deal_id', d ->> 'hubspot_deal_id','dealname', d ->> 'dealname',
             'dealstage', d ->> 'dealstage','hs_is_closed', d ->> 'hs_is_closed',
             'hs_is_closed_lost', d ->> 'hs_is_closed_lost','amount', d ->> 'amount',
             'quantidade_ingressos', d ->> 'quantidade_ingressos','produto', d ->> 'produto',
             'temperatura', d ->> 'temperatura','lead_b2c_ou_b2b', d ->> 'lead_b2c_ou_b2b',
             'origem_do_lead', d ->> 'origem_do_lead','hubspot_owner_id', d ->> 'hubspot_owner_id',
             'createdate', d ->> 'createdate',
             'entrou_no_estagio_em', d ->> 'hs_v2_date_entered_current_stage',
             'hs_lastmodifieddate', d ->> 'hs_lastmodifieddate',
             'contatos_hubspot', d -> 'propriedades' -> '_contatos'))),'[]'::jsonb)
      into v_negociacoes from jsonb_array_elements(v_linhas) d;
  end loop;

  -- Sinais transacionais. Papel LIMITADO: nao reconstroi historico de compra (isso e do
  -- contato). superado_por_conversao usa o consolidado do CONTATO como juiz.
  with hist as (
    select distinct on (h.hubspot_deal_id)
           h.hubspot_deal_id, h.dealname, h.situacao, h.summit_year, h.produto_codigo,
           h.amount_in_home_currency, h.status_de_pagamento, h.data_da_compra, h.cupom_utilizado
      from crm.vendas_historicas_mind_summit h
      join lateral jsonb_array_elements_text(
             coalesce(h.propriedades -> '_contatos','[]'::jsonb)) c(hid) on true
     where c.hid = any(v_contatos)
  ),
  f as (
    select hist.*,
           case hist.situacao
             when 'carrinho_abandonado'  then 'carrinho_abandonado'
             when 'aberto'               then 'fatura_aberta'
             when 'aberto_status_aberto' then 'fatura_aberta'
             when 'pendente_a_confirmar' then 'pendencia' end as tipo,
           (hist.produto_codigo is not null and hist.produto_codigo = any(v_codigos)) as superado
      from hist
  )
  select
    coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'tipo', f.tipo,'produto_codigo', f.produto_codigo,
      'hubspot_deal_id', f.hubspot_deal_id,'dealname', f.dealname,
      'situacao_origem', f.situacao,'summit_year', f.summit_year,
      'valor_total_da_venda', f.amount_in_home_currency,
      'status_de_pagamento', f.status_de_pagamento,'data_da_compra', f.data_da_compra,
      'cupom_utilizado', f.cupom_utilizado,
      'superado_por_conversao', false))) filter (where f.tipo is not null and not f.superado),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'tipo', f.tipo,'produto_codigo', f.produto_codigo,
      'hubspot_deal_id', f.hubspot_deal_id,'dealname', f.dealname,
      'situacao_origem', f.situacao,'summit_year', f.summit_year,
      'superado_por_conversao', true,
      'superado_por','consolidado do contato ja registra este produto')))
      filter (where f.tipo is not null and f.superado),'[]'::jsonb)
    into v_relevantes, v_superados from f;

  -- Refund: evidencia transacional que NAO pode ser ignorada so porque o contato ainda mostra
  -- o produto -- ha refunds que ainda nao atualizam as propriedades consolidadas.
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'hubspot_deal_id', h.hubspot_deal_id,'dealname', h.dealname,
           'produto_codigo', h.produto_codigo,'summit_year', h.summit_year,
           'valor_reembolsado', h.valor_reembolsado,'data_reembolso', h.data_reembolso,
           'situacao_origem', h.situacao,
           'aviso','refund pode nao ter sido refletido nas propriedades consolidadas do contato'))),'[]'::jsonb)
    into v_refunds
    from (select distinct on (h.hubspot_deal_id)
                 h.hubspot_deal_id, h.dealname, h.produto_codigo, h.summit_year,
                 h.valor_reembolsado, h.data_reembolso, h.situacao
            from crm.vendas_historicas_mind_summit h
            join lateral jsonb_array_elements_text(
                   coalesce(h.propriedades -> '_contatos','[]'::jsonb)) c(hid) on true
           where c.hid = any(v_contatos)
             and lower(coalesce(h.houve_reembolso,'')) in ('sim','true','yes')) h;

  return jsonb_build_object(
    'ok', true,'pessoa_id', p_pessoa_id,
    'contato_consolidado', v_consolidado,'produtos', v_produtos,
    'lead_atual', v_lead,'negociacoes', v_negociacoes,
    'sinais_transacionais', jsonb_build_object(
      'relevantes', v_relevantes,'superados', v_superados,'refunds', v_refunds),
    'meta', jsonb_build_object(
      'contatos_hubspot_considerados', to_jsonb(v_contatos),
      'sem_contato_hubspot', false,'fontes_lidas', to_jsonb(v_fontes),
      'pipelines_sem_espelho', v_sem_espelho,
      'evidencias_sem_mapping', v_sem_mapping,'sync', v_sync));
end $function$;


-- mind.pessoa_atual() | mudou: não | 0 referências de coluna renomeadas
-- 'mind.person_id' e nome de GUC (current_setting), nao coluna: contrato com quem faz set_config; fica.
-- Reproduzido identico ao vivo, apenas para completude do bloco.
CREATE OR REPLACE FUNCTION mind.pessoa_atual()
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select nullif(current_setting('mind.person_id', true), '')::uuid;
$function$;


-- api.me(p_token text) | mudou: sim | 1 referência de coluna renomeada
-- renomeada: registrations.person_id (r.person_id -> r.mind_id).
-- ATENCAO / DIVERGENCIA MATERIAL: a versao viva le "summit.registrations", mas o schema "summit" NAO existe no banco
-- (so "summit_2026"; summit_2026.registrations tem exatamente person_id, ticket_category, criado_em). Hoje api.me
-- falha em runtime com 42P01 relation "summit.registrations" does not exist (verificado com token inexistente).
-- Como e LANGUAGE sql, um create or replace com "summit." tambem falharia na validacao do corpo. Por isso este
-- statement qualifica summit_2026.registrations — unica mudanca fora do rename estrito; decisao do supervisor:
-- para manter literal, trocar "summit_2026.registrations" de volta para "summit.registrations" (o script entao falha aqui).
-- search_path mantido como no original ('summit' inexistente e ignorado pelo Postgres).
-- mantidas: nenhuma chave de saida usa pessoa_id/person_id; engagement.v_pessoa.id nao muda.
CREATE OR REPLACE FUNCTION api.me(p_token text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'summit', 'comum', 'engagement', 'intelligence', 'mind', 'concierge', 'public'
AS $function$
  select jsonb_build_object(
    'nome', p.nome, 'empresa', p.empresa, 'cargo', p.cargo, 'idioma', p.idioma,
    'ingresso', (select r.ticket_category from summit_2026.registrations r
                 where r.mind_id = p.id order by r.criado_em desc limit 1))
  from engagement.v_pessoa p
  where p.id = api.quem_sou(p_token);
$function$;


-- api.quem_sou(p_token text) | mudou: sim | 2 referências de coluna renomeadas
-- renomeadas: engagement.agent_sessions.participante_id (select s.participante_id; s.participante_id is not null).
-- returns uuid: nao ha nome de coluna de saida a preservar.
CREATE OR REPLACE FUNCTION api.quem_sou(p_token text)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'engagement', 'intelligence', 'summit', 'comum', 'concierge', 'mind', 'extensions', 'public'
AS $function$
  select s.mind_id
  from engagement.agent_sessions s
  where s.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and s.expira_em > now()
    and s.mind_id is not null;
$function$;


-- public.mind_mensagem_registrar(p_conversa_id uuid, p_papel text, p_conteudo text, p_id_externo text, p_blocos jsonb, p_origem text) | mudou: sim | 2 referências de coluna renomeadas
-- renomeadas: engagement.conversas.participante_id (select ... into v_pes), engagement.mensagens.participante_id (lista de colunas do insert).
-- mantidas: nenhuma (retorno jsonb nao expoe pessoa).
CREATE OR REPLACE FUNCTION public.mind_mensagem_registrar(p_conversa_id uuid, p_papel text, p_conteudo text, p_id_externo text DEFAULT NULL::text, p_blocos jsonb DEFAULT NULL::jsonb, p_origem text DEFAULT 'conversa'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement'
AS $function$
declare
  v_papel text := case lower(btrim(coalesce(p_papel,'lead')))
                    when 'user' then 'lead' when 'assistant' then 'agente'
                    when 'system' then 'sistema' else lower(btrim(coalesce(p_papel,'lead'))) end;
  v_txt   text := nullif(btrim(coalesce(p_conteudo,'')),'');
  v_ext   text := nullif(left(btrim(coalesce(p_id_externo,'')),160),'');
  v_pes   uuid;
  v_id    uuid;
  v_dup   boolean := false;
begin
  if v_papel not in ('lead','agente','sistema') then
    raise exception using errcode='22023', message='papel_invalido';
  end if;
  if v_txt is null and p_blocos is null then
    return jsonb_build_object('mensagem_id', null, 'duplicada', false, 'vazia', true);
  end if;

  select mind_id into v_pes from engagement.conversas where id = p_conversa_id;

  insert into engagement.mensagens
    (conversa_id, mind_id, papel, conteudo, blocos, client_msg_id, origem)
  values (p_conversa_id, v_pes, v_papel, left(v_txt, 8000), p_blocos, v_ext,
          coalesce(p_origem,'conversa'))
  on conflict (conversa_id, client_msg_id) where client_msg_id is not null do nothing
  returning id into v_id;

  if v_id is null and v_ext is not null then
    select m.id into v_id from engagement.mensagens m
     where m.conversa_id = p_conversa_id and m.client_msg_id = v_ext;
    v_dup := v_id is not null;
  end if;

  update engagement.conversas set ultima_atividade = now() where id = p_conversa_id;
  return jsonb_build_object('mensagem_id', v_id, 'duplicada', v_dup, 'papel', v_papel);
end $function$;


-- bloco 2
-- public.mind_engagement_fatos(p_pessoa_id uuid) | mudou: sim | 1 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_engagement_fatos(p_pessoa_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
  with conversa as (
    select c.id, c.canal, c.agente, c.origem_codigo, c.produto_codigo,
           c.iniciada_em, c.ultima_atividade, c.encerrada_em
      from engagement.conversas c
     where c.mind_id = p_pessoa_id
  ),
  mensagem as (
    select m.conversa_id, m.id, m.papel, m.conteudo, m.blocos, m.origem, m.criado_em
      from engagement.mensagens m
     where m.conversa_id in (select id from conversa)
  ),
  conversa_com_mensagens as (
    select cv.*,
           coalesce((
             select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                      'mensagem_id', ms.id,
                      'papel',       ms.papel,
                      'conteudo',    ms.conteudo,
                      'blocos',      ms.blocos,
                      'origem',      ms.origem,
                      'criado_em',   ms.criado_em))
                    order by ms.criado_em, ms.id)
               from mensagem ms where ms.conversa_id = cv.id), '[]'::jsonb) as mensagens
      from conversa cv
  )
  select jsonb_build_object(
    'ok', true,
    'pessoa_id', p_pessoa_id,
    'resumo', jsonb_build_object(
      'conversas_total',       (select count(*) from conversa),
      'mensagens_total',       (select count(*) from mensagem),
      'canais',                coalesce((select jsonb_agg(distinct canal) from conversa
                                          where canal is not null), '[]'::jsonb),
      'primeira_interacao_em', (select min(x) from (
                                  select min(iniciada_em) x from conversa
                                  union all select min(criado_em) from mensagem) a),
      'ultima_interacao_em',   (select max(x) from (
                                  select max(greatest(iniciada_em, ultima_atividade, encerrada_em)) x
                                    from conversa
                                  union all select max(criado_em) from mensagem) b)),
    'conversas', coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
               'conversa_id',      cm.id,
               'canal',            cm.canal,
               'agente',           cm.agente,
               'origem_codigo',    cm.origem_codigo,
               'produto_codigo',   cm.produto_codigo,
               'iniciada_em',      cm.iniciada_em,
               'ultima_atividade', cm.ultima_atividade,
               'encerrada_em',     cm.encerrada_em,
               'mensagens',        cm.mensagens))
             order by cm.iniciada_em nulls last, cm.id)
        from conversa_com_mensagens cm), '[]'::jsonb),
    'meta', jsonb_build_object(
      'autoria_individual_treble_disponivel', false));
$function$
;

-- public.treble_agent_start(p_session_external_id text, p_contact jsonb, p_origem text, p_utm_token text, p_mensagem jsonb) | mudou: não | 0 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.treble_agent_start(p_session_external_id text, p_contact jsonb DEFAULT '{}'::jsonb, p_origem text DEFAULT NULL::text, p_utm_token text DEFAULT NULL::text, p_mensagem jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas', 'treble'
AS $function$
declare
  v_in    jsonb;
  v_out   jsonb;
  v_est   jsonb;
  v_conv  engagement.conversas;
begin
  if p_session_external_id is null or length(p_session_external_id) < 3 then
    raise exception using errcode='22023', message='session_external_id invalido';
  end if;

  v_in := jsonb_build_object(
    'canal','whatsapp',
    'agente','treble-inbound-agent',
    'sessao_externa', p_session_external_id,
    'nome', p_contact->>'nome',
    'identificadores', jsonb_strip_nulls(jsonb_build_object(
      'whatsapp',      coalesce(p_contact->>'whatsapp', p_contact->>'telefone'),
      'email',         p_contact->>'email',
      'telefone_hash', p_contact->>'telefone_hash')),
    'origem', jsonb_strip_nulls(jsonb_build_object(
      'origem_codigo', p_origem, 'utm_token', p_utm_token)),
    'mensagem', p_mensagem);

  v_out := public.mind_inbound(v_in);
  select * into v_conv from engagement.conversas where id = (v_out->>'conversa_id')::uuid;

  -- particularidade REAL do canal: o cliente falou => janela de 24h reaberta
  if v_conv.telefone is not null then
    perform public.treble_status_marcar(v_conv.telefone, 'aberta', now(), v_conv.session_external_id);
  end if;

  v_est := public.mind_conversa_estado(v_conv.id);

  return v_out || v_est || jsonb_build_object(
    'conversation_id',  v_conv.id,
    'pessoa_encontrada',(v_out->>'pessoa_id') is not null,
    'participante_id',  v_out->'pessoa_id',
    'needs_human',      coalesce((v_conv.variables->>'needs_human')::boolean, false));
end $function$
;

-- public.mind_pessoa_fatos(p_pessoa_id uuid) | mudou: sim | 3 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_pessoa_fatos(p_pessoa_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pessoas', 'engagement', 'crm'
AS $function$
with
alvo as (
  select p.id, p.primeiro_nome, p.sobrenome, p.empresa, p.cargo
    from pessoas.pessoas p
   where p.id = p_pessoa_id
),

-- Identidades HubSpot da pessoa. distinct porque o mesmo hubspot_id pode ter
-- mais de uma linha de identidade; um contato conta uma vez.
ident_hs as (
  select distinct i.identificador as hubspot_id
    from engagement.identidades i
   where i.mind_id = p_pessoa_id
     and i.canal = 'hubspot'
),
crm_contatos as (
  select c.hubspot_id, c.firstname, c.lastname, c.company, c.jobtitle
    from ident_hs h
    join crm.contato_espelho c on c.hubspot_id = h.hubspot_id
),

campos(campo) as (values ('primeiro_nome'), ('sobrenome'), ('empresa'), ('cargo')),

-- Valores brutos com proveniencia. ord_fonte 0 = pessoas.pessoas, 1 = CRM.
bruto as (
  select 'primeiro_nome'::text as campo, a.primeiro_nome as valor, 0 as ord_fonte, null::text as hubspot_id from alvo a
  union all select 'sobrenome',     a.sobrenome, 0, null::text from alvo a
  union all select 'empresa',       a.empresa,   0, null::text from alvo a
  union all select 'cargo',         a.cargo,     0, null::text from alvo a
  union all select 'primeiro_nome', c.firstname, 1, c.hubspot_id from crm_contatos c
  union all select 'sobrenome',     c.lastname,  1, c.hubspot_id from crm_contatos c
  union all select 'empresa',       c.company,   1, c.hubspot_id from crm_contatos c
  union all select 'cargo',         c.jobtitle,  1, c.hubspot_id from crm_contatos c
),

-- Normalizacao. `valor` e a representacao devolvida (preserva o case da fonte,
-- limpa espaco); `chave` e a forma de COMPARACAO: trim + espacos consecutivos +
-- case. Nada de acento, similaridade ou semantica.
limpo as (
  select b.campo,
         btrim(regexp_replace(b.valor, '\s+', ' ', 'g'))        as valor,
         lower(btrim(regexp_replace(b.valor, '\s+', ' ', 'g'))) as chave,
         b.ord_fonte, b.hubspot_id
    from bruto b
   where nullif(btrim(coalesce(b.valor, '')), '') is not null
),

-- Um grupo por fato distinto. A grafia devolvida prefere pessoas.pessoas quando
-- ela pertence ao grupo; senao, o contato CRM de menor hubspot_id. E so
-- representacao textual: nao significa precedencia factual.
grupos as (
  select l.campo, l.chave,
         (array_agg(l.valor order by l.ord_fonte, l.hubspot_id, l.valor))[1] as representacao
    from limpo l
   group by l.campo, l.chave
),

fontes_dedup as (
  select distinct l.campo, l.chave, l.ord_fonte, l.hubspot_id from limpo l
),
fontes_json as (
  select f.campo, f.chave,
         jsonb_agg(
           case when f.ord_fonte = 0
                then jsonb_build_object('tipo', 'pessoa')
                else jsonb_build_object('tipo', 'crm', 'hubspot_id', f.hubspot_id)
           end
           order by f.ord_fonte, f.hubspot_id) as fontes
    from fontes_dedup f
   group by f.campo, f.chave
),

perfil as (
  select jsonb_object_agg(
           k.campo,
           case when (select count(*) from grupos g where g.campo = k.campo) = 1
                then to_jsonb((select g.representacao from grupos g where g.campo = k.campo))
                else 'null'::jsonb
           end) as j
    from campos k
),

valores_json as (
  select g.campo,
         jsonb_agg(jsonb_build_object('valor', g.representacao, 'fontes', fj.fontes)
                   order by g.chave) as valores
    from grupos g
    join fontes_json fj on fj.campo = g.campo and fj.chave = g.chave
   group by g.campo
),
conflitos as (
  select coalesce(
           jsonb_agg(jsonb_build_object('campo', v.campo, 'valores', v.valores) order by v.campo),
           '[]'::jsonb) as j
    from valores_json v
   where (select count(*) from grupos g where g.campo = v.campo) >= 2
),

identificadores as (
  select coalesce(
           jsonb_agg(jsonb_build_object(
             'canal',         i.canal,
             'identificador', i.identificador,
             'verificado',    i.verificado,
             'confianca',     i.confianca)
           order by i.canal, i.identificador),
           '[]'::jsonb) as j
    from engagement.identidades i
   where i.mind_id = p_pessoa_id
),

-- Pendencia e FATO, nao efeito: nao remove dado, nao troca pessoa_id, nao funde
-- e nao desempata perfil. Fica registrada para quem consome depois.
pendencia as (
  select count(*) > 0 as aberta,
         coalesce(jsonb_agg(distinct f.tipo order by f.tipo), '[]'::jsonb) as tipos
    from engagement.identidade_fusoes f
   where f.status = 'pendente'
     and (f.mind_id = p_pessoa_id or f.participante_origem = p_pessoa_id)
),

meta as (
  select jsonb_build_object(
    'pendencia_identidade', jsonb_build_object('aberta', pd.aberta, 'tipos', pd.tipos),
    'contatos_hubspot_considerados', (select count(*) from crm_contatos),
    -- identidade hubspot que nao tem espelho nao e silenciada nem inventada:
    -- vira contagem, e nunca conflito de perfil.
    'identidades_hubspot_sem_espelho', (
      select count(*) from ident_hs h
       where not exists (select 1 from crm.contato_espelho c where c.hubspot_id = h.hubspot_id))
  ) as j
  from pendencia pd
)

select case
  when p_pessoa_id is null then
    jsonb_build_object('ok', false, 'motivo', 'sem_pessoa')
  when not exists (select 1 from alvo) then
    jsonb_build_object('ok', false, 'motivo', 'pessoa_nao_encontrada', 'pessoa_id', p_pessoa_id)
  else
    jsonb_build_object(
      'ok',               true,
      'pessoa_id',        p_pessoa_id,
      'perfil',           (select j from perfil),
      'identificadores',  (select j from identificadores),
      'conflitos_perfil', (select j from conflitos),
      'meta',             (select j from meta))
end
$function$
;

-- public.mind_agent_context(p_conversa_id uuid) | mudou: sim | 3 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_agent_context(p_conversa_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
with
conversa as (
  select c.id, c.mind_id, c.canal, c.origem_codigo, c.produto_codigo, c.variables
    from engagement.conversas c
   where c.id = p_conversa_id
),
pessoa as (
  select cv.mind_id as pessoa_id from conversa cv where cv.mind_id is not null
),

-- Cada coletor uma vez.
coletores as (
  select p.pessoa_id,
         public.mind_pessoa_fatos(p.pessoa_id)     as person,
         public.mind_crm_fatos(p.pessoa_id)        as crm,
         public.mind_crm_comercial(p.pessoa_id)       as commercial,
         public.mind_credenciamento_fatos(p.pessoa_id) as credenciamento,
         public.mind_engagement_fatos(p.pessoa_id)     as engajamento
    from pessoa p
),

-- ENTRY. So fato da entrada atual. `variables` nunca sai cru: dele se extrai apenas a CTA.
-- A normalizacao das duas formas possiveis (array de {key,value} vindo do session.close,
-- objeto quando o agente escreve) e a mesma ja provada em analise_montar_contexto.
vars as (
  select case
           when jsonb_typeof(cv.variables) = 'array' then (
             select coalesce(jsonb_object_agg(v->>'key', v->>'value')
                      filter (where nullif(v->>'key','') is not null
                                and nullif(v->>'value','') is not null),
                    '{}'::jsonb)
               from jsonb_array_elements(cv.variables) v)
           when jsonb_typeof(cv.variables) = 'object' then cv.variables
           else '{}'::jsonb
         end as j
    from conversa cv
),
entrada as (
  select jsonb_build_object(
           'canal',          cv.canal,
           'origem_codigo',  cv.origem_codigo,
           'origem',         (select jsonb_build_object(
                                       'site',         o.site,
                                       'botao_rotulo', o.botao_rotulo,
                                       'descricao',    o.descricao)
                                from engagement.origens o
                               where o.codigo = cv.origem_codigo),
           'produto_codigo', cv.produto_codigo,
           'entry_action',   nullif(btrim(coalesce(
                               (select j->>'hubspot_opcao_selecionada_treble' from vars),
                               (select j->>'opcao_selecionada'                from vars),
                               '')), '')
         ) as j
    from conversa cv
),

-- A conversa atual sai de dentro do proprio coletor, na linguagem dele. As demais mantem
-- a ordem deterministica do coletor (iniciada_em, id) — WITH ORDINALITY preserva o array.
conversas_do_coletor as (
  select c.valor, c.ord
    from coletores k,
         lateral jsonb_array_elements(k.engajamento->'conversas') with ordinality c(valor, ord)
),
atual as (
  select c.valor as j from conversas_do_coletor c
   where (c.valor->>'conversa_id')::uuid = p_conversa_id
   limit 1
),
anteriores as (
  select coalesce(jsonb_agg(c.valor order by c.ord), '[]'::jsonb) as j
    from conversas_do_coletor c
   where (c.valor->>'conversa_id')::uuid is distinct from p_conversa_id
)

select case
  when p_conversa_id is null then
    jsonb_build_object('ok', false, 'motivo', 'sem_conversa')
  when not exists (select 1 from conversa) then
    jsonb_build_object('ok', false, 'motivo', 'conversa_nao_encontrada', 'conversa_id', p_conversa_id)
  when not exists (select 1 from pessoa) then
    jsonb_build_object('ok', false, 'motivo', 'conversa_sem_pessoa', 'conversa_id', p_conversa_id)
  else
    jsonb_build_object(
      'ok',           true,
      'pessoa_id',    (select pessoa_id from coletores),
      'conversa_id',  p_conversa_id,
      'person',       (select person     from coletores),
      'crm',          (select crm        from coletores),
      'commercial',      (select commercial      from coletores),
      'credenciamento',   (select credenciamento  from coletores),
      'entry',        (select j from entrada),
      'conversation', (select j from atual),
      -- historico factual pessoa-wide inteiro, nao contador: as outras conversas vem
      -- completas, com suas mensagens. Engagement factual nao e Memory.
      'engagement',   jsonb_build_object(
                        'resumo',               (select engajamento->'resumo' from coletores),
                        'conversas_anteriores', (select j from anteriores),
                        'meta',                 (select engajamento->'meta'   from coletores)))
end
$function$
;

-- concierge.aplicar_evento_jornada() | mudou: sim | 5 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION concierge.aplicar_evento_jornada()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'engagement', 'intelligence', 'summit', 'comum', 'concierge', 'mind', 'public'
AS $function$
declare
  objetiva boolean := new.origem in ('checkin','qr','reserva_usada');
begin
  insert into jornada_sessao (mind_id, sessao_id)
  values (new.mind_id, new.sessao_id)
  on conflict (mind_id, sessao_id) do nothing;

  update jornada_sessao set
    intencao = case new.tipo
                 when 'interesse' then 'interesse'
                 when 'planejou'  then 'planejada'
                 when 'reservou'  then 'reservada'
                 when 'removeu'   then 'removida'
                 else intencao end,
    intencao_forca = coalesce(new.dados->>'forca', intencao_forca,
                       case new.tipo when 'reservou' then 'alta'
                                     when 'planejou' then 'media'
                                     when 'interesse' then 'baixa' end),
    origem_intencao = case when new.tipo in ('interesse','planejou','reservou','removeu')
                           then new.origem else origem_intencao end,
    planejou = planejou or new.tipo in ('planejou','reservou'),
    compareceu = case
        when new.tipo in ('compareceu','nao_compareceu')
             and (confianca_presenca is distinct from 'objetiva' or objetiva)
        then (new.tipo = 'compareceu')
        else compareceu end,
    fonte_presenca = case
        when new.tipo in ('compareceu','nao_compareceu')
             and (confianca_presenca is distinct from 'objetiva' or objetiva)
        then new.origem else fonte_presenca end,
    confianca_presenca = case
        when new.tipo in ('compareceu','nao_compareceu')
             and (confianca_presenca is distinct from 'objetiva' or objetiva)
        then case when objetiva then 'objetiva'
                  when new.origem = 'conversa' then 'declarada'
                  else 'fraca' end
        else confianca_presenca end,
    motivo_ausencia = coalesce(new.dados->>'motivo', motivo_ausencia),
    atualizado_em = now()
  where mind_id = new.mind_id and sessao_id = new.sessao_id;

  return null;
end $function$
;

-- public.mind_pessoa_completar(p_pessoa_id uuid, p_sobrenome text, p_empresa text, p_cargo text) | mudou: não | 0 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_pessoa_completar(p_pessoa_id uuid, p_sobrenome text DEFAULT NULL::text, p_empresa text DEFAULT NULL::text, p_cargo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pessoas'
AS $function$
begin
  if p_pessoa_id is null then return null; end if;

  update pessoas.pessoas set
    sobrenome     = coalesce(sobrenome, nullif(left(trim(coalesce(p_sobrenome,'')),120),'')),
    empresa       = coalesce(empresa,   nullif(left(trim(coalesce(p_empresa,'')),160),'')),
    cargo         = coalesce(cargo,     nullif(left(trim(coalesce(p_cargo,'')),120),'')),
    atualizado_em = now()
  where id = p_pessoa_id;

  return (select jsonb_build_object('perfil', jsonb_strip_nulls(jsonb_build_object(
            'pessoa_id', p.id, 'primeiro_nome', p.primeiro_nome, 'sobrenome', p.sobrenome,
            'email', p.email, 'whatsapp', p.whatsapp, 'empresa', p.empresa, 'cargo', p.cargo)))
          from pessoas.pessoas p where p.id = p_pessoa_id);
end $function$
;


-- bloco 3
-- public.treble_agent_identificar | mudou: sim | 6 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.treble_agent_identificar(p_session_external_id text, p_email text DEFAULT NULL::text, p_nome text DEFAULT NULL::text, p_sobrenome text DEFAULT NULL::text, p_mesma_pessoa boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
declare
  v_conv engagement.conversas;
  v_res  jsonb;
  v_pessoa uuid;
begin
  select * into v_conv from engagement.conversas
   where canal='whatsapp' and session_external_id = btrim(p_session_external_id);
  if not found then
    return jsonb_build_object('pessoa_encontrada', false, 'motivo','conversa_inexistente');
  end if;

  v_res := public.mind_identidade_resolver(
    jsonb_strip_nulls(jsonb_build_object('email', p_email, 'whatsapp', v_conv.telefone)),
    coalesce(p_nome, v_conv.nome_contato), 'whatsapp', v_conv.mind_id);

  v_pessoa := coalesce(v_conv.mind_id, nullif(v_res->>'pessoa_id','')::uuid);
  if v_pessoa is not null then
    update engagement.conversas set mind_id = v_pessoa
     where id = v_conv.id and mind_id is null;
    update engagement.mensagens set mind_id = v_pessoa
     where conversa_id = v_conv.id and mind_id is null;
  end if;

  return v_res || public.mind_conversa_estado(v_conv.id) || jsonb_build_object(
    'pessoa_id',         v_pessoa,
    'pessoa_encontrada', v_pessoa is not null,
    'participante_id',   v_pessoa,
    'criou',             coalesce((v_res->>'criada')::boolean,false),
    'precisa_fundir',    (v_res->'conflito') is not null and v_res->>'conflito' <> 'null');
end $function$;


-- public.treble_sessao_encerrada_gravar | mudou: sim | 6 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.treble_sessao_encerrada_gravar(p_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
declare
  v_ext    text := p_payload#>>'{session,external_id}';
  v_tel    text := nullif(regexp_replace(
      coalesce(p_payload#>>'{user,country_code}','') || coalesce(p_payload#>>'{user,cellphone}',''),
      '\D','','g'), '');
  v_fechou timestamptz := nullif(p_payload#>>'{session,closed_at}','')::timestamptz;
  v_ultima_user timestamptz := (
      select max(nullif(x->>'created_at','')::timestamptz)
        from jsonb_array_elements(coalesce(p_payload->'messages','[]'::jsonb)) x
       where x->>'sender' = 'user');
  v_keys jsonb := coalesce(p_payload->'user_session_keys','[]'::jsonb);
  v_nome   text := (select e->>'value' from jsonb_array_elements(v_keys) e
                     where lower(e->>'key') in ('name','nome','first_name','primeiro_nome') limit 1);
  v_cta    text := (select e->>'value' from jsonb_array_elements(v_keys) e
                     where e->>'key' in ('hubspot_opcao_selecionada_treble','opcao_selecionada') limit 1);
  v_origem text := public.treble_origem_da_cta(v_cta);
  v_prod   text := (select o.produto_codigo from engagement.origens o where o.codigo = v_origem);
  v_conv uuid; v_ancora uuid;
  r record;
  v_papel text; v_tipo text; v_texto text; v_blocos jsonb; v_criado timestamptz; v_cid text;
  v_res jsonb; v_pessoa uuid;
begin
  if v_ext is null then return null; end if;

  insert into engagement.conversas
    (canal, agente, session_external_id, nome_contato, telefone, variables, encerrada_em,
     ultima_atividade, origem_codigo, produto_codigo)
  values ('whatsapp', 'treble', v_ext, nullif(trim(coalesce(v_nome,'')),''), v_tel,
          v_keys, v_fechou, coalesce(v_ultima_user, v_fechou, now()), v_origem, v_prod)
  on conflict (canal, session_external_id) where session_external_id is not null do update
    set encerrada_em     = coalesce(conversas.encerrada_em, excluded.encerrada_em),
        nome_contato     = coalesce(conversas.nome_contato, excluded.nome_contato),
        telefone         = coalesce(conversas.telefone, excluded.telefone),
        variables        = coalesce(conversas.variables, excluded.variables),
        origem_codigo    = coalesce(conversas.origem_codigo, excluded.origem_codigo),
        produto_codigo   = coalesce(conversas.produto_codigo, excluded.produto_codigo),
        ultima_atividade = greatest(conversas.ultima_atividade, excluded.ultima_atividade)
  returning id, mind_id into v_conv, v_ancora;

  for r in
    select m as msg, ord
      from jsonb_array_elements(coalesce(p_payload->'messages','[]'::jsonb)) with ordinality t(m, ord)
  loop
    v_papel  := case when r.msg->>'sender' = 'user' then 'lead' else 'agente' end;
    v_tipo   := r.msg->>'type';
    v_criado := coalesce(nullif(r.msg->>'created_at','')::timestamptz, now());
    v_cid    := 'treble-close:' || r.ord;

    if v_tipo = 'hsm' then
      v_texto  := nullif(btrim(r.msg#>>'{hsm,message}'), '');
      v_blocos := jsonb_build_object('tipo', 'hsm');
    elsif v_tipo in ('image','audio','document','video') then
      v_texto  := nullif(btrim(r.msg->v_tipo->>'caption'), '');
      v_blocos := jsonb_strip_nulls(jsonb_build_object(
                    'tipo', v_tipo, 'url', nullif(btrim(r.msg->v_tipo->>'url'), '')));
    elsif v_tipo = 'text' then
      v_texto  := nullif(btrim(r.msg#>>'{text,message}'), '');
      v_blocos := null;
    else
      -- tipo que ainda nao vimos: preserva o rotulo em vez de descartar a mensagem
      v_texto  := nullif(btrim(r.msg#>>'{text,message}'), '');
      v_blocos := jsonb_build_object('tipo', coalesce(v_tipo, 'desconhecido'));
    end if;

    -- 1) esta posicao deste close ja foi importada
    if exists (select 1 from engagement.mensagens x
                where x.conversa_id = v_conv and x.client_msg_id = v_cid) then
      continue;
    end if;

    -- 2) a mesma mensagem ja foi capturada AO VIVO pelo runtime (linha que nao veio deste close).
    --    So vale quando ha texto para comparar; mensagens deste mesmo payload sao excluidas da
    --    comparacao para que nunca suprimam umas as outras.
    if v_texto is not null and exists (
      select 1 from engagement.mensagens x
       where x.conversa_id = v_conv
         and coalesce(x.client_msg_id, '') not like 'treble-close:%'
         and x.papel = v_papel
         and x.conteudo is not distinct from v_texto
         and x.criado_em between v_criado - interval '15 minutes'
                             and v_criado + interval '15 minutes')
    then
      continue;
    end if;

    -- 2b) MESMO ARQUIVO ja capturado AO VIVO. O item de audio do close nao tem texto, entao
    --     a regra (2) nunca o alcanca. Aqui a identidade e o proprio arquivo: igualdade exata
    --     de URL, sem janela de tempo.
    if v_tipo = 'audio' and v_blocos->>'url' is not null and exists (
      select 1 from engagement.mensagens x
       where x.conversa_id = v_conv
         and coalesce(x.client_msg_id, '') not like 'treble-close:%'
         and x.papel = v_papel
         and x.blocos->>'tipo' = 'audio'
         and x.blocos->>'url'  = v_blocos->>'url')
    then
      continue;
    end if;

    insert into engagement.mensagens
      (conversa_id, mind_id, papel, conteudo, blocos, origem, client_msg_id, criado_em)
    values (v_conv, v_ancora, v_papel, v_texto, v_blocos, 'treble', v_cid, v_criado)
    on conflict (conversa_id, client_msg_id) where client_msg_id is not null do nothing;
  end loop;

  if v_tel is not null then
    perform public.treble_status_marcar(v_tel, 'x', coalesce(v_ultima_user, v_fechou), v_ext);
    v_res := public.mind_identidade_resolver(
      jsonb_build_object('whatsapp', v_tel), v_nome, 'whatsapp', v_ancora);
    v_pessoa := coalesce(v_ancora, nullif(v_res->>'pessoa_id','')::uuid);
    update engagement.conversas set mind_id = v_pessoa
     where id = v_conv and mind_id is null;
    update engagement.mensagens set mind_id = v_pessoa
     where conversa_id = v_conv and mind_id is null;
  end if;

  return v_conv;
end $function$;


-- public.mind_play_chamada_iniciar | mudou: sim | 2 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_play_chamada_iniciar(p_ferramenta text, p_pessoa_id uuid, p_idempotency_key text DEFAULT NULL::text, p_entrada jsonb DEFAULT '{}'::jsonb, p_mensagem_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ferramenta text := nullif(btrim(coalesce(p_ferramenta, '')), '');
  v_chave      text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_id         uuid;
  v_antiga     concierge.ferramenta_chamadas%rowtype;
begin
  if v_ferramenta is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_ferramenta');
  end if;
  if p_pessoa_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa');
  end if;

  insert into concierge.ferramenta_chamadas
    (ferramenta, mind_id, mensagem_id, entrada, status, idempotency_key)
  values
    (v_ferramenta, p_pessoa_id, p_mensagem_id,
     coalesce(p_entrada, '{}'::jsonb), 'em_andamento', v_chave)
  on conflict (idempotency_key) where idempotency_key is not null
  do nothing
  returning id into v_id;

  if v_id is not null then
    return jsonb_build_object('ok', true, 'estado', 'nova', 'chamada_id', v_id);
  end if;

  -- Colidiu: a MESMA tentativa de transporte já está registrada.
  select * into v_antiga
    from concierge.ferramenta_chamadas
   where idempotency_key = v_chave;

  if v_antiga.id is null then
    -- Só acontece se a linha sumiu entre o conflito e a leitura.
    return jsonb_build_object('ok', false, 'motivo', 'reserva_perdida');
  end if;

  if v_antiga.ferramenta is distinct from v_ferramenta
     or v_antiga.mind_id is distinct from p_pessoa_id then
    return jsonb_build_object('ok', false, 'motivo', 'chave_conflitante');
  end if;

  if v_antiga.status = 'em_andamento' then
    return jsonb_build_object('ok', true, 'estado', 'em_andamento', 'chamada_id', v_antiga.id);
  end if;

  return jsonb_build_object(
    'ok',          true,
    'estado',      'repetida',
    'chamada_id',  v_antiga.id,
    'status',      v_antiga.status,
    'saida',       v_antiga.saida,
    'http_status', v_antiga.http_status);
end;
$function$;


-- public.analise_gravar | mudou: sim | 4 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.analise_gravar(p_conversa_id uuid, p_analisador text, p_funcao text, p_vertical text, p_dados jsonb, p_modelo text DEFAULT NULL::text, p_prompt_versao integer DEFAULT 1)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'intelligence', 'engagement', 'pessoas'
AS $function$
declare v_part uuid; v_ult_id uuid; v_ult_ts timestamptz; v_analise uuid;
begin
  select mind_id into v_part from engagement.conversas where id = p_conversa_id;
  select id, criado_em into v_ult_id, v_ult_ts
    from engagement.mensagens where conversa_id = p_conversa_id
    order by criado_em desc, id desc limit 1;

  insert into intelligence.analise_conversa
    (conversa_id, mind_id, analisador, funcao, vertical, dados, modelo, prompt_versao,
     ultima_mensagem_analisada_id, conversa_atualizada_ate, analisado_em, atualizado_em)
  values (p_conversa_id, v_part, p_analisador, p_funcao, nullif(p_vertical,''),
          coalesce(p_dados,'{}'::jsonb), nullif(p_modelo,''), coalesce(p_prompt_versao,1),
          v_ult_id, v_ult_ts, now(), now())
  on conflict (conversa_id, analisador) do update set
    mind_id                      = excluded.mind_id,
    funcao                       = excluded.funcao,
    vertical                     = excluded.vertical,
    dados                        = excluded.dados,
    modelo                       = excluded.modelo,
    prompt_versao                = excluded.prompt_versao,
    ultima_mensagem_analisada_id = excluded.ultima_mensagem_analisada_id,
    conversa_atualizada_ate      = excluded.conversa_atualizada_ate,
    analisado_em                 = now(),
    atualizado_em                = now()
  returning id into v_analise;

  begin
    perform public.analise_projetar_memoria(
      v_part, p_analisador, p_dados->'customer_memory', v_analise);
  exception when others then
    raise warning 'projecao_memoria falhou: %', sqlerrm;
  end;

  -- continuidade comercial (Silence Engine): nunca derruba a gravacao da analise
  begin
    perform public.silence_sync_from_analysis(v_analise);
  exception when others then
    raise warning 'silence_sync falhou: %', sqlerrm;
  end;
end $function$;


-- public.mind_crm_vincular_pessoa | mudou: sim | 13 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_crm_vincular_pessoa(p_pessoa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas', 'crm'
AS $function$
declare
  v_hub    text[];
  v_mail   text[];
  v_tel10  text[];
  v_tel_ok text[] := array[]::text[];
  t        text;
  v_n      int;
  v_hubs   text[];
  v_amb    jsonb := '[]'::jsonb;
  c        record;
  v_r      jsonb;
  v_vinc   int := 0;
  v_ja     int := 0;
  v_conf   int := 0;
  v_ident  int := 0;
  v_recus  int := 0;
  v_lista  jsonb := '[]'::jsonb;
  v_nome_pessoa text;
begin
  if p_pessoa_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa');
  end if;

  select array_agg(i.identificador) filter (where i.canal = 'hubspot'),
         array_agg(i.identificador) filter (where i.canal = 'email'),
         array_agg(right(i.identificador, 10)) filter
           (where i.canal in ('whatsapp','telefone') and length(i.identificador) >= 10)
    into v_hub, v_mail, v_tel10
  from engagement.identidades i
  where i.mind_id = p_pessoa_id;
  select concat_ws(' ', p.primeiro_nome, p.sobrenome),
         case when p.email is not null and not (lower(p.email) = any(coalesce(v_mail, '{}'))) then coalesce(v_mail, '{}') || lower(p.email) else v_mail end
    into v_nome_pessoa, v_mail
    from pessoas.pessoas p where p.id = p_pessoa_id;

  if v_tel10 is not null then
    foreach t in array v_tel10 loop
      select count(*), array_agg(e.hubspot_id)
        into v_n, v_hubs
        from crm.contato_espelho e
       where (length(regexp_replace(coalesce(e.phone,''), '\D','','g')) >= 10
              and right(regexp_replace(coalesce(e.phone,''), '\D','','g'), 10) = t)
          or (length(regexp_replace(coalesce(e.hs_whatsapp_phone_number,''), '\D','','g')) >= 10
              and right(regexp_replace(coalesce(e.hs_whatsapp_phone_number,''), '\D','','g'), 10) = t);

      if v_n = 1 then
        v_tel_ok := v_tel_ok || t;
      elsif v_n > 1 then
        v_amb := v_amb || jsonb_build_array(jsonb_build_object(
          'telefone', t, 'contatos', v_n, 'hubspot_ids', to_jsonb(v_hubs)));
      end if;
    end loop;

    if jsonb_array_length(v_amb) > 0 then
      perform public.mind_conflito_registrar(
        p_pessoa_id, 'suspeita_sobre_merge',
        'telefone compartilhado por varios contatos do CRM; nao vincula por telefone',
        null,
        jsonb_build_object('telefones_ambiguos', v_amb));
    end if;
  end if;

  if v_hub is null and v_mail is null and coalesce(array_length(v_tel_ok,1),0) = 0 then
    return jsonb_build_object('ok', true, 'motivo', 'sem_identificador_utilizavel',
      'telefones_ambiguos', v_amb, 'contatos', '[]'::jsonb);
  end if;

  for c in
    select e.id, e.hubspot_id, e.mind_id, e.email, e.phone, e.hs_whatsapp_phone_number, e.firstname, e.lastname,
           case
             when v_hub  is not null and e.hubspot_id = any(v_hub) then 'hubspot_id'
             when v_mail is not null and lower(btrim(coalesce(e.email,''))) = any(v_mail) then 'email'
             else 'telefone'
           end as via
      from crm.contato_espelho e
     where (v_hub  is not null and e.hubspot_id = any(v_hub))
        or (v_mail is not null and lower(btrim(coalesce(e.email,''))) = any(v_mail))
        or (coalesce(array_length(v_tel_ok,1),0) > 0
            and ((length(regexp_replace(coalesce(e.phone,''), '\D','','g')) >= 10
                  and right(regexp_replace(coalesce(e.phone,''), '\D','','g'), 10) = any(v_tel_ok))
              or (length(regexp_replace(coalesce(e.hs_whatsapp_phone_number,''), '\D','','g')) >= 10
                  and right(regexp_replace(coalesce(e.hs_whatsapp_phone_number,''), '\D','','g'), 10) = any(v_tel_ok))))
  loop
    -- Regra do nome/e-mail (Adriana, 23/09): por e-mail ou telefone, o nome do contato nao pode
    -- contradizer o da pessoa; por telefone, o e-mail do contato nao pode ser outro.
    if c.via <> 'hubspot_id' and not public.mind_nomes_compativeis(v_nome_pessoa, concat_ws(' ', c.firstname, c.lastname)) then
      v_recus := v_recus + 1;
      v_lista := v_lista || jsonb_build_array(jsonb_build_object(
        'hubspot_id', c.hubspot_id, 'via', c.via,
        'situacao', case when c.mind_id = p_pessoa_id then 'ja_ligado_nome_divergente' else 'nao_vinculado_nome_divergente' end,
        'nome_contato', concat_ws(' ', c.firstname, c.lastname)));
      continue;
    end if;
    if c.via = 'telefone' and nullif(btrim(coalesce(c.email,'')),'') is not null and v_mail is not null
       and not (lower(btrim(c.email)) = any(v_mail)) then
      v_recus := v_recus + 1;
      v_lista := v_lista || jsonb_build_array(jsonb_build_object(
        'hubspot_id', c.hubspot_id, 'via', c.via,
        'situacao', case when c.mind_id = p_pessoa_id then 'ja_ligado_email_divergente' else 'nao_vinculado_email_divergente' end,
        'email_contato', lower(btrim(c.email))));
      if c.mind_id is null or c.mind_id = p_pessoa_id then continue; end if;
    end if;

    if c.mind_id = p_pessoa_id then
      v_ja := v_ja + 1;

    elsif c.mind_id is null then
      update crm.contato_espelho set mind_id = p_pessoa_id, atualizado_em = now()
       where id = c.id;
      v_vinc := v_vinc + 1;

    else
      perform public.mind_conflito_registrar(
        p_pessoa_id, 'contato_crm_de_outra_pessoa',
        'contato do CRM ja pertence a outra pessoa', c.mind_id,
        jsonb_build_object('hubspot_id', c.hubspot_id, 'contato_espelho_id', c.id, 'via', c.via));
      perform public.mind_fusao_propor(p_pessoa_id, c.mind_id, case c.via when 'hubspot_id' then 'hubspot' when 'telefone' then 'whatsapp' else c.via end);
      v_conf := v_conf + 1;
      v_lista := v_lista || jsonb_build_array(jsonb_build_object(
        'hubspot_id', c.hubspot_id, 'situacao', 'conflito', 'via', c.via, 'dono', c.mind_id));
      continue;
    end if;

    -- D5 (causa-raiz das 586): o contato inteiro vira identidade da pessoa, ancorado.
    if nullif(btrim(coalesce(c.hubspot_id,'')),'') is not null then
      v_r := public.mind_identidade_resolver(
        jsonb_build_object(
          'hubspot_id', c.hubspot_id,
          'emails', jsonb_build_array(coalesce(c.email,'')),
          'telefones', jsonb_build_array(coalesce(c.phone,''), coalesce(c.hs_whatsapp_phone_number,''))),
        nullif(btrim(concat_ws(' ', c.firstname, c.lastname)), ''),
        'hubspot', p_pessoa_id);
      if jsonb_array_length(coalesce(v_r->'identidades','[]'::jsonb)) > 0 then
        v_ident := v_ident + 1;
      end if;
    end if;

    v_lista := v_lista || jsonb_build_array(jsonb_build_object(
      'hubspot_id', c.hubspot_id, 'via', c.via,
      'situacao', case when c.mind_id is null then 'vinculado' else 'ja_ligado' end));
  end loop;

  return jsonb_build_object(
    'ok', true, 'pessoa_id', p_pessoa_id,
    'contatos_vinculados', v_vinc, 'contatos_ja_ligados', v_ja,
    'conflitos', v_conf, 'identidades_hubspot_novas', v_ident, 'recusados_pela_regra_do_nome', v_recus,
    'telefones_ambiguos', v_amb, 'contatos', v_lista);
end $function$;


-- public.analise_projetar_memoria | mudou: sim | 5 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.analise_projetar_memoria(p_participante uuid, p_analisador text, p_memorias jsonb, p_analise_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'intelligence', 'engagement'
AS $function$
declare
  mem jsonb;
  v_cat text; v_texto text; v_scope text; v_conf text; v_sens text;
  v_tipo text; v_chave text; v_valor jsonb; v_num numeric; v_status text;
  v_concierge boolean;
  v_code text; v_context text; v_evidence_kind text; v_action text;
  v_evidence_raw text; v_evidence uuid; v_canon_label text;
  v_exist intelligence.participante_memoria%rowtype;
  v_novo uuid; v_n int := 0;
begin
  if p_participante is null or jsonb_typeof(p_memorias) <> 'array' then return 0; end if;

  v_concierge := (p_analisador = 'analise_concierge');

  for mem in select * from jsonb_array_elements(p_memorias)
  loop
    begin
      v_cat   := lower(nullif(trim(coalesce(mem->>'category','')),''));
      v_texto := nullif(trim(coalesce(mem->>'value','')),'');
      v_scope := lower(coalesce(nullif(trim(coalesce(mem->>'scope','')),''), 'opportunity'));
      v_conf  := lower(coalesce(nullif(trim(coalesce(mem->>'confidence','')),''), 'low'));
      v_sens  := lower(btrim(coalesce(mem->>'sensitivity','')));
      v_code  := upper(nullif(btrim(coalesce(mem->>'code','')),''));
      v_context := nullif(btrim(coalesce(mem->>'context','')),'');
      v_evidence_kind := nullif(lower(btrim(coalesce(mem->>'evidence_kind',''))),'');
      v_action := lower(coalesce(nullif(btrim(coalesce(mem->>'memory_action','')),''), 'observe'));
      v_evidence_raw := nullif(btrim(coalesce(mem->>'evidence_message_id','')),'');
      v_evidence := null;
      v_canon_label := null;

      continue when v_texto is null or v_cat is null or v_cat like '%|%';

      if v_concierge then
        continue when v_sens is distinct from 'none';
        continue when v_scope = 'temporary';
      end if;

      if v_cat = 'icp' then
        continue when v_texto <> all(array[
          'CHRO / VP de Pessoas','CEO / C-Suite','Gestor / Middle Manager',
          'People Leader / Business Partner','Executivo Sênior / Alto Performer',
          'Consultor / Coach / Psicólogo'
        ]::text[]);
        v_tipo := 'icp';
        v_chave := 'icp_atual';
        v_scope := 'stable';
        v_action := 'observe';
      elsif v_cat = 'jtbd' then
        continue when v_code is null or v_code !~ '^JT(0[1-9]|1[0-5])$';
        v_canon_label := case v_code
          when 'JT01' then 'Sustentar performance e bem-estar pessoal no longo prazo'
          when 'JT02' then 'Preservar clareza e qualidade de decisão'
          when 'JT03' then 'Navegar pressão, mudança e ambiguidade com adaptabilidade'
          when 'JT04' then 'Desenvolver líderes e gestores'
          when 'JT05' then 'Conduzir conversas difíceis com accountability'
          when 'JT06' then 'Construir segurança psicológica e voz ativa'
          when 'JT07' then 'Estruturar gestão estratégica de bem-estar no trabalho e riscos psicossociais'
          when 'JT08' then 'Traduzir pessoas e bem-estar em business case, dados e influência'
          when 'JT09' then 'Fortalecer engajamento, significado e retenção'
          when 'JT10' then 'Construir cultura adaptativa e resiliência organizacional'
          when 'JT11' then 'Liderar a dimensão humana da IA e do futuro do trabalho'
          when 'JT12' then 'Acessar pares e perspectivas para melhores decisões'
          when 'JT13' then 'Estruturar e vender soluções corporativas'
          when 'JT14' then 'Construir autoridade e credibilidade baseada em ciência'
          when 'JT15' then 'Escalar expertise além do 1:1'
        end;
        continue when v_canon_label is null;
        v_texto := v_canon_label;
        v_tipo := 'jtbd';
        v_chave := 'jtbd:' || v_code;
        continue when v_action not in ('observe','reject','expire');
      else
        v_tipo := case v_cat
          when 'identity' then 'identidade'      when 'role' then 'cargo'
          when 'company' then 'empresa'          when 'goal' then 'objetivo'
          when 'interest' then 'interesse'       when 'preference' then 'preferencia'
          when 'constraint' then 'restricao'     when 'commercial_preference' then 'preferencia_comercial'
          when 'stakeholder' then 'stakeholder'  when 'delegation' then 'delegacao'
          when 'sponsorship' then 'patrocinio'   when 'logistics' then 'logistica'
          else 'outro' end;
        v_chave := case v_tipo
          when 'identidade' then 'identidade'
          when 'cargo'      then 'cargo_atual'
          when 'empresa'    then 'empresa_atual'
          else v_tipo || ':' || public.mind_slug(v_texto) end;
        v_action := 'observe';
      end if;

      if p_analise_id is not null
         and v_evidence_raw ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
        select m.id into v_evidence
        from intelligence.analise_conversa a
        join engagement.mensagens m on m.conversa_id = a.conversa_id
        where a.id = p_analise_id
          and m.id = v_evidence_raw::uuid
          and m.papel = 'lead'
        limit 1;
      end if;

      if v_concierge and v_evidence is null then
        continue;
      end if;

      v_num := case v_conf when 'high' then 0.90 when 'medium' then 0.70 else 0.50 end;
      v_status := case
        when v_concierge then
          case when v_conf = 'high' and v_scope in ('stable','opportunity') then 'ativa' else 'proposta' end
        else
          case when v_scope = 'stable' and v_conf = 'high' then 'ativa' else 'proposta' end
      end;

      -- ICP MEDIUM OCUPA SLOT VAZIO (03/09). Sem ICP ativo, a inferência medium
      -- é o melhor que sabemos e entra ativa com a confiança exposta pelo leitor.
      -- Com ICP ativo, continua valendo a regra do Passo 4: medium não derruba.
      if v_tipo = 'icp' and v_conf = 'medium' and not exists (
           select 1 from intelligence.participante_memoria pm
            where pm.mind_id = p_participante
              and pm.chave = 'icp_atual' and pm.status = 'ativa') then
        v_status := 'ativa';
      end if;

      if v_tipo = 'jtbd' then
        v_valor := jsonb_strip_nulls(jsonb_build_object(
          'code', v_code,
          'text', v_texto,
          'context', v_context,
          'scope', v_scope,
          'evidence_kind', v_evidence_kind,
          'sensitivity', nullif(v_sens,'')));
      elsif v_tipo = 'icp' then
        v_valor := jsonb_strip_nulls(jsonb_build_object(
          'text', v_texto,
          'scope', v_scope,
          'evidence_kind', v_evidence_kind,
          'sensitivity', nullif(v_sens,'')));
      else
        v_valor := jsonb_strip_nulls(jsonb_build_object(
          'text', v_texto,
          'scope', v_scope,
          'evidence_kind', v_evidence_kind,
          'sensitivity', nullif(v_sens,'')));
      end if;

      if v_tipo = 'jtbd' and v_action in ('reject','expire') then
        update intelligence.participante_memoria pm
           set status = case v_action when 'reject' then 'rejeitada' else 'expirada' end,
               evidencia_message_id = coalesce(v_evidence, pm.evidencia_message_id),
               analise_conversa_id = coalesce(p_analise_id, pm.analise_conversa_id),
               atualizado_em = now()
         where pm.mind_id = p_participante
           and pm.chave = v_chave
           and pm.status in ('ativa','proposta');
        if found then v_n := v_n + 1; end if;
        continue;
      end if;

      select * into v_exist from intelligence.participante_memoria pm
       where pm.mind_id = p_participante and pm.chave = v_chave
         and pm.status in ('ativa','proposta')
       order by (pm.status = 'ativa') desc, pm.atualizado_em desc nulls last
       limit 1;

      if found then
        if v_exist.valor->>'text' is not distinct from v_texto then
          update intelligence.participante_memoria
             set valor               = case when v_concierge then v_valor else valor end,
                 confianca           = greatest(coalesce(confianca, 0), v_num),
                 status              = case when status = 'ativa' or v_status = 'ativa'
                                            then 'ativa' else status end,
                 evidencia_message_id = coalesce(v_evidence, evidencia_message_id),
                 analise_conversa_id = coalesce(p_analise_id, analise_conversa_id),
                 atualizado_em       = now()
           where id = v_exist.id;
        elsif v_chave in ('identidade','cargo_atual','empresa_atual','icp_atual') then
          if v_exist.status = 'ativa' and v_status <> 'ativa' then
            null;
          elsif v_exist.status = 'ativa' and v_status = 'ativa' then
            v_novo := gen_random_uuid();
            insert into intelligence.participante_memoria
              (id, mind_id, tipo, chave, valor, confianca, origem, status,
               evidencia_message_id, analise_conversa_id)
            values (v_novo, p_participante, v_tipo, v_chave, v_valor, v_num, p_analisador, 'proposta',
                    v_evidence, p_analise_id);
            update intelligence.participante_memoria
               set status = 'substituida', substituida_por = v_novo, atualizado_em = now()
             where id = v_exist.id;
            update intelligence.participante_memoria
               set status = 'ativa', atualizado_em = now()
             where id = v_novo;
            v_n := v_n + 1;
          else
            update intelligence.participante_memoria
               set tipo = v_tipo,
                   valor = v_valor,
                   confianca = greatest(coalesce(confianca,0), v_num),
                   origem = p_analisador,
                   status = v_status,
                   evidencia_message_id = coalesce(v_evidence, evidencia_message_id),
                   analise_conversa_id = coalesce(p_analise_id, analise_conversa_id),
                   atualizado_em = now()
             where id = v_exist.id;
          end if;
        end if;
      else
        insert into intelligence.participante_memoria
          (mind_id, tipo, chave, valor, confianca, origem, status,
           evidencia_message_id, analise_conversa_id)
        values (p_participante, v_tipo, v_chave, v_valor, v_num, p_analisador, v_status,
                v_evidence, p_analise_id);
        v_n := v_n + 1;
      end if;
    exception when others then
      raise warning 'projecao_memoria falhou p/ item: %', sqlerrm;
    end;
  end loop;

  return v_n;
end
$function$;


-- bloco 4
-- public.mind_customer_intelligence(p_pessoa_id uuid) | mudou: sim | 11 referências de coluna renomeadas
-- (10x intelligence.participante_memoria.participante_id -> mind_id; 1x engagement.identidades.pessoa_id -> mind_id;
--  parâmetro p_pessoa_id e a chave JSON 'pessoa_id' da saída ficam)
CREATE OR REPLACE FUNCTION public.mind_customer_intelligence(p_pessoa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pessoas', 'engagement', 'intelligence', 'crm'
AS $function$
declare
  v_role text; v_company text; v_role_mem text; v_company_mem text; v_hubspot text;
  v_icp_mem text; v_icp_conf numeric; v_icp_updated timestamptz; v_crm_icp text;
  v_jobs jsonb := '[]'::jsonb;
  v_goals jsonb := '[]'::jsonb;
  v_interests jsonb := '[]'::jsonb;
  v_preferences jsonb := '[]'::jsonb;
  v_constraints jsonb := '[]'::jsonb;
  v_stakeholders jsonb := '[]'::jsonb;
  v_delegations jsonb := '[]'::jsonb;
  v_icp jsonb := null;
begin
  if p_pessoa_id is null then return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa'); end if;

  select p.cargo, p.empresa, p.hubspot_id into v_role, v_company, v_hubspot
  from pessoas.pessoas p where p.id = p_pessoa_id;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'pessoa_nao_encontrada'); end if;

  select pm.valor->>'text' into v_role_mem from intelligence.participante_memoria pm
  where pm.mind_id = p_pessoa_id and pm.tipo = 'cargo' and pm.chave = 'cargo_atual'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now())
  order by pm.atualizado_em desc limit 1;

  select pm.valor->>'text' into v_company_mem from intelligence.participante_memoria pm
  where pm.mind_id = p_pessoa_id and pm.tipo = 'empresa' and pm.chave = 'empresa_atual'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now())
  order by pm.atualizado_em desc limit 1;

  v_role := coalesce(nullif(v_role_mem,''), nullif(v_role,''));
  v_company := coalesce(nullif(v_company_mem,''), nullif(v_company,''));

  select pm.valor->>'text', pm.confianca, pm.atualizado_em into v_icp_mem, v_icp_conf, v_icp_updated
  from intelligence.participante_memoria pm
  where pm.mind_id = p_pessoa_id and pm.tipo = 'icp' and pm.chave = 'icp_atual'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now())
    and pm.valor->>'text' = any(array[
      'CHRO / VP de Pessoas','CEO / C-Suite','Gestor / Middle Manager',
      'People Leader / Business Partner','Executivo Sênior / Alto Performer',
      'Consultor / Coach / Psicólogo']::text[])
  order by pm.atualizado_em desc limit 1;

  if v_icp_mem is null then
    select e.icp into v_crm_icp from crm.contato_espelho e
    where e.hubspot_id = coalesce(
      (select i.identificador from engagement.identidades i
        where i.mind_id = p_pessoa_id and i.canal = 'hubspot'
        order by i.criado_em desc nulls last limit 1), v_hubspot)
      and e.icp = any(array[
        'CHRO / VP de Pessoas','CEO / C-Suite','Gestor / Middle Manager',
        'People Leader / Business Partner','Executivo Sênior / Alto Performer',
        'Consultor / Coach / Psicólogo']::text[])
    order by e.atualizado_em desc nulls last limit 1;
  end if;

  if v_icp_mem is not null then
    v_icp := jsonb_build_object('value', v_icp_mem, 'confidence', v_icp_conf,
                                'source', 'memory', 'last_seen_at', v_icp_updated);
  elsif v_crm_icp is not null then
    v_icp := jsonb_build_object('value', v_crm_icp, 'confidence', null, 'source', 'crm');
  end if;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'code', pm.valor->>'code', 'label', pm.valor->>'text', 'context', pm.valor->>'context',
      'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_jobs
  from intelligence.participante_memoria pm
  where pm.mind_id = p_pessoa_id and pm.tipo = 'jtbd' and pm.status = 'ativa'
    and (pm.valido_ate is null or pm.valido_ate > now())
    and pm.valor->>'code' ~ '^JT(0[1-9]|1[0-5])$';

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value', pm.valor->>'text', 'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_goals
  from intelligence.participante_memoria pm where pm.mind_id = p_pessoa_id and pm.tipo = 'objetivo'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value', pm.valor->>'text', 'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_interests
  from intelligence.participante_memoria pm where pm.mind_id = p_pessoa_id and pm.tipo = 'interesse'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value', pm.valor->>'text', 'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_preferences
  from intelligence.participante_memoria pm where pm.mind_id = p_pessoa_id and pm.tipo = 'preferencia'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value', pm.valor->>'text', 'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_constraints
  from intelligence.participante_memoria pm where pm.mind_id = p_pessoa_id and pm.tipo = 'restricao'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value', pm.valor->>'text', 'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_stakeholders
  from intelligence.participante_memoria pm where pm.mind_id = p_pessoa_id and pm.tipo = 'stakeholder'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value', pm.valor->>'text', 'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_delegations
  from intelligence.participante_memoria pm where pm.mind_id = p_pessoa_id and pm.tipo = 'delegacao'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now());

  return jsonb_build_object(
    'ok', true, 'pessoa_id', p_pessoa_id,
    'professional_context', jsonb_strip_nulls(jsonb_build_object('role', v_role, 'company', v_company, 'icp', v_icp)),
    'jobs_observed', v_jobs, 'goals', v_goals, 'interests', v_interests,
    'preferences', v_preferences, 'constraints', v_constraints,
    'decision_context', jsonb_build_object('stakeholders', v_stakeholders, 'delegations', v_delegations,
                                           'relevant_constraints', v_constraints));
end
$function$;


-- public.mind_kit_customer_intelligence(p_conversa_id uuid, p_necessidade jsonb) | mudou: sim | 1 referências de coluna renomeadas
-- (engagement.conversas.participante_id -> mind_id; a chave JSON 'pessoa_id' removida da saída fica)
CREATE OR REPLACE FUNCTION public.mind_kit_customer_intelligence(p_conversa_id uuid, p_necessidade jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'engagement'
AS $function$
declare v_pessoa uuid; v_ci jsonb;
begin
  if p_conversa_id is null then return null; end if;
  select c.mind_id into v_pessoa from engagement.conversas c where c.id = p_conversa_id;
  if v_pessoa is null then return null; end if;
  v_ci := public.mind_customer_intelligence(v_pessoa);
  if coalesce((v_ci->>'ok')::boolean, false) is not true then return null; end if;
  return v_ci - 'ok' - 'pessoa_id';
end
$function$;


-- crm.contexto_comercial(p_email text, p_whatsapp text, p_agente text) | mudou: sim | 3 referências de coluna renomeadas
-- (crm.pessoas_interno.pessoa_id, crm.acessos.pessoa_id, crm.pessoa_nps.pessoa_id -> mind_id)
CREATE OR REPLACE FUNCTION crm.contexto_comercial(p_email text DEFAULT NULL::text, p_whatsapp text DEFAULT NULL::text, p_agente text DEFAULT 'vendas'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'crm', 'catalogo'
AS $function$
declare
  v_base jsonb;
  v_id uuid;
  v_int crm.pessoas_interno%rowtype;
begin
  v_base := crm.buscar_pessoa(p_email, p_whatsapp, p_agente);
  if coalesce((v_base->>'encontrado')::boolean, false) is not true then
    return v_base;
  end if;

  v_id := (v_base->>'id')::uuid;
  select * into v_int from crm.pessoas_interno where mind_id = v_id;

  insert into crm.acessos (funcao, mind_id, agente)
  values ('crm.contexto_comercial', v_id, coalesce(p_agente, 'vendas'));

  return v_base || jsonb_build_object(
    'interno', jsonb_build_object(
      'origem_primeira', v_int.origem_primeira,
      'origem_ultima', v_int.origem_ultima,
      'utm', jsonb_strip_nulls(jsonb_build_object(
        'source', v_int.utm_source, 'medium', v_int.utm_medium,
        'campaign', v_int.utm_campaign, 'content', v_int.utm_content,
        'term', v_int.utm_term)),
      'dono', jsonb_strip_nulls(jsonb_build_object(
        'id', v_int.dono_id, 'nome', v_int.dono_nome)),
      'status_lead', v_int.status_lead,
      'negocios_associados', v_int.negocios_associados,
      'ultimo_contato_em', v_int.ultimo_contato_em,
      'perfil_cliente', v_int.perfil_cliente,
      'descadastrado_email', coalesce(v_int.descadastrado_email, false),
      'nps', coalesce((
        select jsonb_agg(jsonb_build_object(
          'produto', n.produto_codigo, 'nota', n.nota,
          'comentario', n.comentario, 'em', n.respondido_em))
        from crm.pessoa_nps n where n.mind_id = v_id
      ), '[]'::jsonb)
    ),
    'uso_interno', 'Estes sinais orientam tom e argumento. Nunca os repita ao usuario, nem confirme que existem.'
  );
end;
$function$;


-- public.mind_espelho_gravar(p_fonte text, p_registros jsonb) | mudou: sim | 1 referências de coluna renomeadas
-- (SQL dinâmico: a lista de colunas protegidas ganha 'mind_id' — é ela que impede o lote de sobrescrever a identidade
--  dos 5 destinos vivos de crm.sync_estado (contato_espelho, pipeline_leads_inbound, pipeline_de_vendas_summit,
--  empenho_summit_2026, vendas_historicas_mind_summit), todos renomeados pessoa_id -> mind_id no cabeçalho desta
--  migration. 'pessoa_id' fica na lista só por inércia: depois do rename nenhuma tabela crm.* tem essa coluna, então
--  o item é inócuo. Os demais nomes de coluna vêm do payload ∩ information_schema.columns e seguem o rename sozinhos;
--  chave_destino de todas as fontes é hubspot_id / hubspot_lead_id / hubspot_deal_id, nunca a coluna renomeada.)
CREATE OR REPLACE FUNCTION public.mind_espelho_gravar(p_fonte text, p_registros jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'crm'
AS $function$
declare
  v_tabela text;
  v_chave  text;
  v_cols   text[];
  v_lista  text;
  v_sets   text;
  v_n      int;
begin
  if jsonb_typeof(p_registros) <> 'array' then
    raise exception 'p_registros precisa ser array';
  end if;
  v_n := jsonb_array_length(p_registros);
  if v_n = 0 then
    return jsonb_build_object('gravados', 0);
  end if;

  select tabela_destino, chave_destino into v_tabela, v_chave
    from crm.sync_estado where fonte = p_fonte;

  if v_tabela is null then
    raise exception 'fonte sem tabela_destino em crm.sync_estado: %', p_fonte;
  end if;

  -- So as colunas que EXISTEM na tabela E vieram no lote. O que nao veio fica
  -- como esta: sincronizacao nao apaga o que ela nao viu.
  select array_agg(distinct k order by k) into v_cols
  from jsonb_array_elements(p_registros) r,
       jsonb_object_keys(r) k
  where k in (
    select column_name from information_schema.columns
     where table_schema = 'crm' and table_name = v_tabela
       and column_name not in ('id', 'pessoa_id', 'mind_id', 'produto_codigo', 'criado_em')
  );

  if v_cols is null or array_length(v_cols, 1) is null then
    raise exception 'lote nao trouxe nenhuma coluna conhecida de crm.%', v_tabela;
  end if;
  if not (v_chave = any(v_cols)) then
    raise exception 'lote sem a chave %', v_chave;
  end if;

  select string_agg(quote_ident(c), ', ' order by c) into v_lista from unnest(v_cols) c;
  select string_agg(format('%I = excluded.%I', c, c), ', ' order by c) into v_sets
    from unnest(v_cols) c where c <> v_chave;

  execute format(
    'insert into crm.%I (%s) select %s from jsonb_populate_recordset(null::crm.%I, $1)
      on conflict (%I) do update set %s, sincronizado_em = now(), atualizado_em = now()',
    v_tabela, v_lista, v_lista, v_tabela, v_chave, v_sets
  ) using p_registros;

  return jsonb_build_object('gravados', v_n, 'tabela', v_tabela, 'colunas', array_length(v_cols, 1));
end;
$function$;


-- public.mind_conflito_registrar(p_pessoa uuid, p_tipo text, p_motivo text, p_outra uuid, p_evidencia jsonb) | mudou: sim | 1 referências de coluna renomeadas
-- (engagement.identidade_fusoes.participante_id -> mind_id; participante_origem é coluna de papel e fica)
CREATE OR REPLACE FUNCTION public.mind_conflito_registrar(p_pessoa uuid, p_tipo text, p_motivo text, p_outra uuid DEFAULT NULL::uuid, p_evidencia jsonb DEFAULT NULL::jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement'
AS $function$
begin
  if p_pessoa is null then return false; end if;
  if p_outra is not null and p_outra = p_pessoa then return false; end if;
  if p_tipo not in ('conflito_identidade','contato_crm_de_outra_pessoa','suspeita_sobre_merge') then
    raise exception using errcode='22023', message='tipo_de_pendencia_invalido';
  end if;

  insert into engagement.identidade_fusoes
    (mind_id, participante_origem, tipo, motivo, status, identificador)
  values (p_pessoa, p_outra, p_tipo, p_motivo, 'pendente', p_evidencia)
  on conflict do nothing;
  return true;
end $function$;


-- public.mind_pendencias_listar(p_status text, p_tipo text, p_limite integer, p_offset integer) | mudou: sim | 2 referências de coluna renomeadas
-- (engagement.identidade_fusoes.participante_id -> mind_id no select e no join; a saída RETURNS TABLE(... pessoa_id uuid ...)
--  é contrato do app e fica; alias "as pessoa_id" explicita a preservação; participante_origem é coluna de papel e fica)
CREATE OR REPLACE FUNCTION public.mind_pendencias_listar(p_status text DEFAULT 'pendente'::text, p_tipo text DEFAULT NULL::text, p_limite integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, tipo text, status text, motivo text, pessoa_id uuid, pessoa text, pessoa_origem_id uuid, pessoa_origem text, evidencia jsonb, criado_em timestamp with time zone, resolvido_em timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
  select f.id, f.tipo, f.status, f.motivo,
         f.mind_id as pessoa_id,
         nullif(btrim(coalesce(a.primeiro_nome,'')||' '||coalesce(a.sobrenome,'')),''),
         f.participante_origem,
         nullif(btrim(coalesce(b.primeiro_nome,'')||' '||coalesce(b.sobrenome,'')),''),
         f.identificador, f.criado_em, f.resolvido_em
    from engagement.identidade_fusoes f
    left join pessoas.pessoas a on a.id = f.mind_id
    left join pessoas.pessoas b on b.id = f.participante_origem
   where (p_status is null or f.status = p_status)
     and (p_tipo   is null or f.tipo   = p_tipo)
   order by f.criado_em desc
   limit greatest(coalesce(p_limite,50), 1) offset greatest(coalesce(p_offset,0), 0);
$function$;


-- bloco 5
-- api.my_context(p_token text) | mudou: sim | 1 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION api.my_context(p_token text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'engagement', 'intelligence', 'summit', 'comum', 'concierge', 'mind', 'public'
AS $function$
  select jsonb_build_object(
    'necessidades', c.necessidades,
    'resultados_desejados', c.resultados_desejados,
    'temas', c.temas_relevantes,
    'resumo', c.resumo_conversa)
  from intelligence.participante_contexto c
  where c.mind_id = api.quem_sou(p_token);
$function$;


-- api.my_data(p_token text) | mudou: sim | 4 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION api.my_data(p_token text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'engagement', 'intelligence', 'summit', 'comum', 'concierge', 'mind', 'crm', 'public'
AS $function$
  with eu as (select api.quem_sou(p_token) as id)
  select jsonb_build_object(
    'perfil',    (select jsonb_build_object('nome', p.nome, 'email', p.email,
                          'empresa', p.empresa, 'cargo', p.cargo)
                  from engagement.v_pessoa p, eu where p.id = eu.id),
    'memoria',   (select coalesce(jsonb_agg(jsonb_build_object(
                          'chave', m.chave, 'valor', m.valor, 'origem', m.origem)), '[]')
                  from intelligence.participante_memoria m, eu
                  where m.mind_id = eu.id and m.status = 'ativa'),
    'objetivos', (select coalesce(jsonb_agg(o.pergunta_guia), '[]')
                  from intelligence.participante_objetivos o, eu where o.mind_id = eu.id),
    'insights',  (select coalesce(jsonb_agg(f.insight), '[]')
                  from engagement.sessao_feedback f, eu
                  where f.mind_id = eu.id and f.insight is not null),
    'consentimentos', (select coalesce(jsonb_agg(jsonb_build_object(
                          'finalidade', k.finalidade, 'concedido', k.concedido,
                          'em', k.criado_em)), '[]')
                  from crm.consents k, eu where k.mind_id = eu.id));
$function$;


-- public.mind_espelho_ligar() | mudou: sim | 11 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_espelho_ligar()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'crm', 'pessoas', 'engagement', 'catalogo'
AS $function$
declare
  v_contatos int := 0; v_conflitos int := 0;
  v_neg int := 0; v_hist int := 0; v_prod int := 0; v_tmp int := 0;
  r record; v_res jsonb;
begin
  for r in
    select distinct i.mind_id as pessoa_id from engagement.identidades i
     where i.canal in ('hubspot','email','whatsapp','telefone')
  loop
    v_res := public.mind_crm_vincular_pessoa(r.pessoa_id);
    v_contatos  := v_contatos  + coalesce((v_res->>'contatos_vinculados')::int, 0);
    v_conflitos := v_conflitos + coalesce((v_res->>'conflitos')::int, 0);
  end loop;

  -- legado conhecido, preservado como estava (nao e escopo desta correcao)
  with casado as (
    select n.id as neg_id, min(e.mind_id::text)::uuid as pessoa_id
    from crm.pipeline_de_vendas_summit n
    join lateral jsonb_array_elements_text(coalesce(n.propriedades->'_contatos', '[]'::jsonb)) c(hid) on true
    join crm.contato_espelho e on e.hubspot_id = c.hid and e.mind_id is not null
    where n.mind_id is null
    group by n.id having count(distinct e.mind_id) = 1
  )
  update crm.pipeline_de_vendas_summit n set mind_id = c.pessoa_id, atualizado_em = now()
  from casado c where n.id = c.neg_id;
  get diagnostics v_neg = row_count;

  with casado as (
    select n.id as neg_id, min(e.mind_id::text)::uuid as pessoa_id
    from crm.vendas_historicas_mind_summit n
    join lateral jsonb_array_elements_text(coalesce(n.propriedades->'_contatos', '[]'::jsonb)) c(hid) on true
    join crm.contato_espelho e on e.hubspot_id = c.hid and e.mind_id is not null
    where n.mind_id is null
    group by n.id having count(distinct e.mind_id) = 1
  )
  update crm.vendas_historicas_mind_summit n set mind_id = c.pessoa_id, atualizado_em = now()
  from casado c where n.id = c.neg_id;
  get diagnostics v_hist = row_count;

  -- (o bloco que ligava crm.empenho_summit_2026.pessoa_id foi removido de proposito --
  --  identidade do Empenho se resolve por engagement.identidades, no momento da leitura)

  -- produto por pipeline: logica nova, preservada. Vale qualquer pipeline do array do catalogo.
  update crm.pipeline_de_vendas_summit n
     set produto_codigo = p.codigo, atualizado_em = now()
    from catalogo.produtos p
   where n.produto_codigo is null and n.pipeline = any(p.pipelines_hubspot);
  get diagnostics v_prod = row_count;

  update crm.empenho_summit_2026 n
     set produto_codigo = p.codigo, atualizado_em = now()
    from catalogo.produtos p
   where n.produto_codigo is null and n.pipeline = any(p.pipelines_hubspot);
  get diagnostics v_tmp = row_count;
  v_prod := v_prod + v_tmp;

  update crm.vendas_historicas_mind_summit n
     set produto_codigo = p.codigo, atualizado_em = now()
    from catalogo.produtos p
   where n.produto_codigo is null
     and p.codigo = 'mind-summit-' || regexp_replace(coalesce(n.summit_year, ''), '\D', '', 'g');
  get diagnostics v_tmp = row_count;
  v_prod := v_prod + v_tmp;

  -- contrato anterior restaurado: sem `empenho_ligados`
  return jsonb_build_object(
    'contatos_ligados', v_contatos, 'contatos_em_conflito', v_conflitos,
    'negocios_ligados', v_neg, 'historicos_ligados', v_hist, 'produtos_ligados', v_prod);
end $function$;


-- public.mind_crm_fatos(p_pessoa_id uuid) | mudou: sim | 2 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_crm_fatos(p_pessoa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas', 'crm'
AS $function$
declare
  v_contatos jsonb := '[]'::jsonb;
  v_sync     jsonb;
  v_pend     jsonb;
  v_espelho  timestamptz;
  v_n        int := 0;
begin
  if p_pessoa_id is null then
    return jsonb_build_object('ok', false, 'motivo','sem_pessoa');
  end if;

  select coalesce(jsonb_agg(c.fato order by c.ordem desc nulls last), '[]'::jsonb), count(*)
    into v_contatos, v_n
  from (
    select
      e.atualizado_em as ordem,
      jsonb_strip_nulls(jsonb_build_object(
        'hubspot_id', e.hubspot_id,
        'nome',       nullif(btrim(coalesce(e.firstname,'')||' '||coalesce(e.lastname,'')),''),
        'primeiro_nome', nullif(btrim(coalesce(e.firstname,'')),''),
        'sobrenome',  nullif(btrim(coalesce(e.lastname,'')),''),
        'email',      nullif(btrim(coalesce(e.email,'')),''),
        'telefones',  nullif(jsonb_strip_nulls(jsonb_build_object(
                        'phone',    nullif(btrim(coalesce(e.phone,'')),''),
                        'whatsapp', nullif(btrim(coalesce(e.hs_whatsapp_phone_number,'')),''))), '{}'::jsonb),
        'cargo',      nullif(btrim(coalesce(e.jobtitle,'')),''),
        'empresa',    nullif(btrim(coalesce(e.company,'')),''),
        'linkedin',   nullif(btrim(coalesce(e.hs_linkedin_url,'')),''),
        'dominio_email', nullif(btrim(coalesce(e.hs_email_domain,'')),''),

        'qualificacao', nullif(jsonb_strip_nulls(jsonb_build_object(
          'lead_icp',       nullif(btrim(coalesce(e.lead_icp,'')),''),
          'lead_tier',      nullif(btrim(coalesce(e.lead_tier,'')),''),
          'icp',            nullif(btrim(coalesce(e.icp,'')),''),
          'icp_confianca',  e.icp_confianca,
          'lifecyclestage', nullif(btrim(coalesce(e.lifecyclestage,'')),''),
          'hs_lead_status', nullif(btrim(coalesce(e.hs_lead_status,'')),''),
          'etapa_do_lead',  nullif(btrim(coalesce(e.etapa_do_lead__atualizar,'')),''),
          'motivo_lead_perdido', nullif(btrim(coalesce(e.motivo_do_lead__perdido,'')),''),
          'origem_do_lead', nullif(btrim(coalesce(e.origem_do_lead,'')),''),
          'owner_hubspot_id', nullif(btrim(coalesce(e.hubspot_owner_id,'')),''))), '{}'::jsonb),

        'summit', nullif(jsonb_strip_nulls(jsonb_build_object(
          'participacao_anual',        nullif(btrim(coalesce(e.summit__participacao_anual,'')),''),
          'total_de_summits',          e.total_de_summits_participados,
          'participou_de_mais_de_um',  nullif(btrim(coalesce(e.participou_de_mais_de_um_summit,'')),''),
          'categoria_do_ingresso',     nullif(btrim(coalesce(e.summit__categoria_do_ingresso,'')),''),
          'categoria_2025',            nullif(btrim(coalesce(e.summit__categoria_2025,'')),''),
          'categoria_2026',            nullif(btrim(coalesce(e.summit__categoria_2026,'')),''),
          'tipo_entrada',              nullif(btrim(coalesce(e.tipo_de_entrada,'')),''),
          'tipo_entrada_2025',         nullif(btrim(coalesce(e.summit__tipo_entrada_2025,'')),''),
          'tipo_entrada_2026',         nullif(btrim(coalesce(e.summit__tipo_entrada_2026,'')),''),
          'papel_2025',                nullif(btrim(coalesce(e.summit_papel_2025,'')),''),
          'papel_2026',                nullif(btrim(coalesce(e.summit__papel_2026,'')),''),
          'cortesia_anos',             nullif(btrim(coalesce(e.summit__cortesia_anos,'')),''),
          'patrocinio_anos',           nullif(btrim(coalesce(e.summit__patrocinio_anos,'')),''),
          'status_summit_2026',        nullif(btrim(coalesce(e.status_summit_2026,'')),''))), '{}'::jsonb),

        'atribuicao', nullif(jsonb_strip_nulls(jsonb_build_object(
          'utm_source',   nullif(btrim(coalesce(e.utm_source,'')),''),
          'utm_medium',   nullif(btrim(coalesce(e.utm_medium,'')),''),
          'utm_campaign', nullif(btrim(coalesce(e.utm_campaign,'')),''),
          'utm_content',  nullif(btrim(coalesce(e.utm_content,'')),''),
          'utm_term',     nullif(btrim(coalesce(e.utm_term,'')),''),
          'origem_primeira',        nullif(btrim(coalesce(e.hs_analytics_source,'')),''),
          'origem_primeira_detalhe',nullif(btrim(coalesce(e.hs_analytics_source_data_1,'')),''),
          'origem_ultima',          nullif(btrim(coalesce(e.hs_latest_source,'')),''),
          'origem_ultima_detalhe',  nullif(btrim(coalesce(e.hs_latest_source_data_1,'')),''),
          'origem_ultima_em',       e.hs_latest_source_timestamp,
          'primeira_url',           nullif(btrim(coalesce(e.hs_analytics_first_url,'')),''),
          'primeiro_referrer',      nullif(btrim(coalesce(e.hs_analytics_first_referrer,'')),''),
          'primeira_visita_em',     e.hs_analytics_first_timestamp,
          'ultima_url',             nullif(btrim(coalesce(e.hs_analytics_last_url,'')),''),
          'primeira_conversao',     nullif(btrim(coalesce(e.first_conversion_event_name,'')),''),
          'primeira_conversao_em',  e.first_conversion_date)), '{}'::jsonb),

        'atualizado_em',   e.atualizado_em,
        'sincronizado_em', e.sincronizado_em
      )) as fato
    from engagement.identidades i
    join crm.contato_espelho e on e.hubspot_id = i.identificador
    where i.mind_id = p_pessoa_id and i.canal = 'hubspot'
  ) c;

  select jsonb_strip_nulls(jsonb_build_object(
           'fonte', s.fonte, 'status', s.status,
           'concluido_em', s.concluido_em, 'carga_completa_em', s.carga_completa_em,
           'registros_gravados', s.registros_gravados))
    into v_sync
  from crm.sync_estado s where s.fonte = 'hubspot_contatos';

  select max(e.sincronizado_em) into v_espelho from crm.contato_espelho e;

  select jsonb_build_object(
           'aberta', count(*) > 0,
           'tipos', coalesce(jsonb_agg(distinct f.tipo), '[]'::jsonb))
    into v_pend
  from engagement.identidade_fusoes f
  where f.status = 'pendente'
    and (f.mind_id = p_pessoa_id or f.participante_origem = p_pessoa_id);

  return jsonb_build_object(
    'ok', true,
    'pessoa_id', p_pessoa_id,
    'contatos', v_contatos,
    'meta', jsonb_build_object(
      'contatos_encontrados', v_n,
      'pendencia_identidade', v_pend,
      'sync_hubspot_contatos', v_sync,
      'espelho_ultimo_sincronizado_em', v_espelho));
end $function$;


-- public.analise_montar_contexto(p_conversa_id uuid) | mudou: sim | 2 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.analise_montar_contexto(p_conversa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'intelligence', 'engagement', 'pessoas', 'crm'
AS $function$
declare
  c         engagement.conversas%rowtype;
  v_hub     text;
  v_vars    jsonb;
  v_cta     text;
  v_origem  jsonb;
  v_sessao  jsonb;
  v_crm_atr jsonb;
  v_atr     jsonb;
  v_ctx     jsonb;
begin
  select * into c from engagement.conversas where id = p_conversa_id;
  if not found then return null; end if;

  select hubspot_id into v_hub from pessoas.pessoas where id = c.mind_id;

  v_vars := case
    when jsonb_typeof(c.variables) = 'array' then (
      select coalesce(jsonb_object_agg(v->>'key', v->>'value')
             filter (where nullif(v->>'key','') is not null
                       and nullif(v->>'value','') is not null), '{}'::jsonb)
      from jsonb_array_elements(c.variables) v)
    when jsonb_typeof(c.variables) = 'object' then c.variables
    else '{}'::jsonb end;

  v_cta := nullif(trim(coalesce(
             v_vars->>'hubspot_opcao_selecionada_treble',
             v_vars->>'opcao_selecionada', '')), '');

  select to_jsonb(o) - 'atualizado_em' - 'hubspot' into v_origem
    from engagement.origens o where o.codigo = c.origem_codigo;

  select jsonb_strip_nulls(to_jsonb(u) - 'token' - 'criado_em' - 'usado_em') into v_sessao
    from engagement.utm_sessoes u where u.token = c.utm_token;

  select jsonb_strip_nulls(to_jsonb(x)) into v_crm_atr from (
    select utm_source, utm_medium, utm_campaign, utm_content, utm_term,
           msclkid, li_fat_id,
           hs_analytics_source, hs_analytics_source_data_1, hs_analytics_source_data_2,
           hs_analytics_first_url, hs_analytics_first_referrer, hs_analytics_first_timestamp,
           hs_latest_source, hs_latest_source_data_1, hs_latest_source_timestamp,
           hs_analytics_last_url, hs_analytics_last_referrer,
           first_conversion_event_name, first_conversion_date,
           hs_analytics_first_touch_converting_campaign,
           hs_analytics_last_touch_converting_campaign
    from crm.contato_espelho where hubspot_id = v_hub limit 1) x;

  v_atr := jsonb_strip_nulls(jsonb_build_object(
    'utm_conversa',   c.utm,
    'utm_token',      c.utm_token,
    'sessao_do_site', nullif(coalesce(v_sessao,'{}'::jsonb), '{}'::jsonb),
    'hubspot',        nullif(coalesce(v_crm_atr,'{}'::jsonb), '{}'::jsonb)
  ));

  v_ctx := jsonb_strip_nulls(jsonb_build_object(
    'canal',          c.canal,
    'agente',         c.agente,
    'origem_codigo',  c.origem_codigo,
    'origem',         v_origem,
    'produto_codigo', c.produto_codigo,
    'entry_action',   v_cta,
    'atribuicao',     nullif(coalesce(v_atr,'{}'::jsonb), '{}'::jsonb),
    'audience',       c.audience,
    'stage',          c.stage,
    'iniciada_em',    c.iniciada_em,
    'encerrada_em',   c.encerrada_em,
    'variables',      nullif(v_vars, '{}'::jsonb)
  ));

  return jsonb_build_object(
    'conversation_context', v_ctx,
    'conversa_id', p_conversa_id,
    'transcrito', coalesce((
       select jsonb_agg(jsonb_build_object(
                'mensagem_id', m.id,
                'papel', m.papel,
                'conteudo', m.conteudo,
                'criado_em', m.criado_em)
                order by m.criado_em, m.id)
       from engagement.mensagens m
       where m.conversa_id = p_conversa_id and m.conteudo is not null), '[]'::jsonb),
    'pessoa', (select to_jsonb(x) from (
       select primeiro_nome, sobrenome, email, empresa, cargo
       from pessoas.pessoas where id = c.mind_id) x),
    'crm', (select to_jsonb(y) from (
       select lead_tier, lead_icp, icp, hs_lead_status, produto_de_interesse, motivo_do_lead__perdido,
              company, total_de_ingressos_comprados_lifetime, num_associated_deals, total_revenue
       from crm.contato_espelho where hubspot_id = v_hub limit 1) y)
  );
end
$function$;


-- public.summit_contato_criar_pendentes(p_limit integer) | mudou: sim | 1 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.summit_contato_criar_pendentes(p_limit integer DEFAULT 50)
 RETURNS TABLE(pessoa_id uuid, telefone text, primeiro_nome text, sobrenome text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
  select distinct on (p.id) p.id, p.whatsapp,
         coalesce(nullif(trim(p.primeiro_nome),''), nullif(trim(c.nome_contato),'')),
         nullif(trim(p.sobrenome),'')
  from engagement.conversas c
  join pessoas.pessoas p on p.id = c.mind_id
  where c.agente in ('treble','treble-inbound-agent')
    and public.summit_motivo_exclusao(c.id) is not null
    and p.hubspot_id is null
    and p.whatsapp is not null
  order by p.id, c.ultima_atividade desc nulls last
  limit greatest(1, p_limit);
$function$;


-- bloco 6
-- public.mind_recovery_refresh(p_limit integer) | mudou: sim | 5 referências de coluna renomeadas
-- (intelligence.analise_conversa.participante_id -> mind_id x2; intelligence.recovery_inbox.participant_id -> mind_id x3:
--  lista do insert, alvo do set e excluded.*. O alias interno "participant_id" da CTE latest fica: é alias, não coluna.)
CREATE OR REPLACE FUNCTION public.mind_recovery_refresh(p_limit integer DEFAULT 2000)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_count integer; v_now timestamptz:=now();
begin
  with agent_paid as materialized (
    select distinct v.conversation_id
    from intelligence.v_conversoes_agente v where v.paid
  ), crm_paid as materialized (
    select distinct nc.contato_hubspot_id hubspot_id
    from crm.negocio_contatos nc
    join crm.vendas_historicas_mind_summit vh on vh.hubspot_deal_id=nc.hubspot_deal_id
    where vh.status_de_pagamento='Pago' and vh.summit_year='2026'
  ), optout_message as materialized (
    select distinct m.conversa_id conversation_id
    from engagement.mensagens m where m.papel='lead'
      and lower(trim(coalesce(m.conteudo,''))) in ('sair','descadastrar')
  ), latest as materialized (
    select distinct on (a.conversa_id)
      a.id analysis_id,a.conversa_id conversation_id,a.mind_id participant_id,a.dados,a.atualizado_em,
      c.canal,c.audience,c.variables,c.nome_contato,c.ultima_atividade,
      cc.continuation_status,cc.next_review_at,
      case when ap.conversation_id is not null or cp.hubspot_id is not null
              or coalesce(ce.summit__participacao_anual,'') like '%2026%' then 'purchased'
           when ce.hubspot_id is not null then 'not_purchased' else 'unknown' end purchase_status,
      case
        when om.conversation_id is not null then 'opt_out_message'
        when lower(coalesce(cta.value,''))='descadastrar' then 'opt_out_cta'
        when lower(coalesce(cta.value,''))='já comprei meu ingresso' then 'declared_purchase'
        else null end exclusion_reason,
      lm.last_lead_at,lm.last_agent_at
    from intelligence.analise_conversa a
    join engagement.conversas c on c.id=a.conversa_id
    left join pessoas.pessoas p on p.id=a.mind_id
    left join crm.contato_espelho ce on ce.hubspot_id=p.hubspot_id
    left join crm_paid cp on cp.hubspot_id=p.hubspot_id
    left join agent_paid ap on ap.conversation_id=a.conversa_id
    left join optout_message om on om.conversation_id=a.conversa_id
    left join intelligence.continuidade_comercial cc on cc.conversa_id=a.conversa_id
    left join lateral (
      select case
        when jsonb_typeof(c.variables)='object' then coalesce(
          c.variables->>'hubspot_opcao_selecionada_treble',c.variables->>'opcao_selecionada')
        when jsonb_typeof(c.variables)='array' then (
          select v->>'value' from jsonb_array_elements(c.variables) v
          where v->>'key' in ('hubspot_opcao_selecionada_treble','opcao_selecionada')
          order by (v->>'key'='hubspot_opcao_selecionada_treble') desc limit 1)
        else null end value
    ) cta on true
    left join lateral (
      select max(m.criado_em) filter(where m.papel='lead') last_lead_at,
             max(m.criado_em) filter(where m.papel<>'lead') last_agent_at
      from engagement.mensagens m where m.conversa_id=a.conversa_id
    ) lm on true
    where a.funcao='comercial' and c.canal in ('whatsapp','mindagent-web')
    order by a.conversa_id,a.atualizado_em desc,a.id desc
    limit greatest(1,least(coalesce(p_limit,2000),10000))
  ), normalized as materialized (
    select l.*,
      coalesce(nullif(l.variables->>'rota_ativa',''),nullif(l.dados->>'motion','')) route,
      case lower(coalesce(l.dados->>'purchase_intent',''))
        when 'very_high' then 'very_hot' when 'high' then 'hot'
        when 'medium' then 'warm' else 'cold' end heat,
      lower(coalesce(nullif(l.dados->>'primary_barrier',''),'unclear')) objection,
      case
        when lower(coalesce(l.dados->>'primary_barrier','')) in ('price','personal_budget','company_budget','value') then 'price'
        when lower(coalesce(l.dados->>'primary_barrier','')) in ('schedule','availability','travel_logistics','format') then 'availability_logistics'
        when lower(coalesce(l.dados->>'primary_barrier','')) in ('payment','technical','transaction') then 'payment_technical'
        when lower(coalesce(l.dados->>'primary_barrier',''))='approval' then 'internal_approval'
        when lower(coalesce(l.dados->>'continuation_status',''))='commitment_pending'
          or l.dados#>>'{commitment,due}' is not null then 'promised_to_return'
        when lower(coalesce(l.dados->>'purchase_intent','')) in ('high','very_high') then 'interested_not_bought'
        when lower(coalesce(l.dados->>'continuation_status','')) in ('silence','active') then 'stopped_replying'
        else 'other' end objection_group,
      case when l.canal='whatsapp' and l.last_lead_at is not null
           then l.last_lead_at+interval '24 hours' end window_expiry,
      greatest(coalesce(l.next_review_at,'-infinity'::timestamptz),
               coalesce(l.last_lead_at+interval '12 hours','-infinity'::timestamptz)) raw_due
    from latest l
  ), classified as materialized (
    select n.*,
      public.mind_recovery_delivery_slot(n.raw_due,n.window_expiry,n.canal) slot,
      case
        when n.purchase_status='purchased' then 'excluded_purchased'
        when n.exclusion_reason in ('opt_out_message','opt_out_cta') then 'blocked_optout'
        when n.exclusion_reason='declared_purchase' then 'purchase_check_required'
        when lower(coalesce(n.dados#>>'{ownership,handoff_status}','')) in ('done','accepted','assigned','in_progress')
          or nullif(btrim(coalesce(n.dados#>>'{ownership,human_owner}','')),'') is not null then 'blocked_human_owned'
        when n.purchase_status='unknown' then 'purchase_check_required'
        when n.canal='mindagent-web' then 'app_inbox'
        when n.last_lead_at is null then 'insufficient_evidence'
        when v_now>=n.window_expiry then 'needs_hsm'
        when public.mind_recovery_delivery_slot(n.raw_due,n.window_expiry,n.canal) is null then 'needs_hsm'
        when public.mind_recovery_delivery_slot(n.raw_due,n.window_expiry,n.canal)<=v_now then 'freeform_ready'
        else 'waiting_window' end inbox_state
    from normalized n
  ), written as (
    insert into intelligence.recovery_inbox as r (
      conversation_id,analysis_id,mind_id,channel,audience,route,contact_name,
      last_lead_at,last_agent_at,last_activity_at,whatsapp_window_expires_at,next_send_at,
      purchase_status,inbox_state,heat,objection,objection_group,summary,learned,
      recommended_action,followup_anchor,response_target,source_analysis_updated_at,refreshed_at,updated_at
    )
    select conversation_id,analysis_id,participant_id,canal,audience,route,nome_contato,
      last_lead_at,last_agent_at,greatest(last_lead_at,last_agent_at,ultima_atividade),window_expiry,slot,
      purchase_status,inbox_state,heat,objection,objection_group,
      nullif(btrim(dados->>'conversation_summary'),''),
      jsonb_strip_nulls(jsonb_build_object(
        'customer_memory',dados->'customer_memory','agent_learning',dados->'agent_learning',
        'buyer_objective',dados->>'buyer_objective','commercial_signals',dados->'commercial_signals'
      )),
      nullif(btrim(dados->>'next_best_move'),''),nullif(btrim(dados->>'followup_anchor'),''),
      nullif(btrim(dados->>'response_target'),''),atualizado_em,v_now,v_now
    from classified
    on conflict (conversation_id) do update set
      analysis_id=excluded.analysis_id,mind_id=excluded.mind_id,channel=excluded.channel,
      audience=excluded.audience,route=excluded.route,contact_name=excluded.contact_name,
      last_lead_at=excluded.last_lead_at,last_agent_at=excluded.last_agent_at,
      last_activity_at=excluded.last_activity_at,
      whatsapp_window_expires_at=excluded.whatsapp_window_expires_at,next_send_at=excluded.next_send_at,
      purchase_status=excluded.purchase_status,inbox_state=excluded.inbox_state,heat=excluded.heat,
      objection=excluded.objection,objection_group=excluded.objection_group,summary=excluded.summary,
      learned=excluded.learned,recommended_action=excluded.recommended_action,
      followup_anchor=excluded.followup_anchor,response_target=excluded.response_target,
      draft_status=case when r.source_analysis_updated_at<>excluded.source_analysis_updated_at then 'stale' else r.draft_status end,
      source_analysis_updated_at=excluded.source_analysis_updated_at,refreshed_at=v_now,updated_at=v_now
    returning 1
  ) select count(*) into v_count from written;

  update engagement.recovery_dispatch_queue q set status='canceled',updated_at=v_now,
    error_code='conversation_no_longer_eligible'
  from intelligence.recovery_inbox r
  where q.conversation_id=r.conversation_id and q.status not in ('sent','canceled')
    and r.inbox_state in ('excluded_purchased','blocked_optout','blocked_human_owned','purchase_check_required');

  return jsonb_build_object('ok',true,'refreshed',v_count,'at',v_now,
    'dispatcher_enabled',false);
end
$function$;


-- public.mindagent_chat_bind_identity(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text, p_email text, p_nome text) | mudou: sim | 6 referências de coluna renomeadas
-- (engagement.conversas.participante_id x3, engagement.agent_sessions.participante_id x1, engagement.mensagens.participante_id x2.
--  Chaves JSON 'pessoa_id' (entrada de mind_identidade_resolver e saída lida pela Edge Function mindagent-chat) ficam.)
CREATE OR REPLACE FUNCTION public.mindagent_chat_bind_identity(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text, p_email text, p_nome text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
declare v_sess engagement.agent_sessions%rowtype; v_res jsonb; v_pessoa uuid; v_ancora uuid;
begin
  select * into v_sess from engagement.agent_sessions
   where id = p_session_id and auth_user_id = p_auth_user_id
     and token_hash = p_token_hash and expira_em > now() for update;
  if not found then raise exception using errcode='28000', message='invalid_chat_session'; end if;

  select mind_id into v_ancora from engagement.conversas
   where id = p_conversation_id and dispositivo_id = v_sess.dispositivo_id;

  v_res := public.mind_identidade_resolver(
    jsonb_build_object('email', p_email, 'auth_user_id', p_auth_user_id::text),
    nullif(btrim(coalesce(p_nome, '')), ''), 'mindagent-web', v_ancora);

  v_pessoa := coalesce(v_ancora, nullif(v_res->>'pessoa_id','')::uuid);
  if v_pessoa is not null then
    update engagement.agent_sessions set mind_id = v_pessoa, ultima_atividade = now()
     where id = v_sess.id;
    update engagement.conversas set mind_id = coalesce(mind_id, v_pessoa),
           ultima_atividade = now()
     where id = p_conversation_id and dispositivo_id = v_sess.dispositivo_id;
    update engagement.mensagens set mind_id = v_pessoa
     where conversa_id = p_conversation_id and mind_id is null;
  end if;

  return v_res || jsonb_build_object(
    'pessoa_id', v_pessoa,
    'found', v_pessoa is not null,
    'conflict', (v_res->'conflito') is not null and v_res->>'conflito' <> 'null',
    'profile', coalesce((public.mind_conversa_estado(p_conversation_id))->'perfil','{}'::jsonb));
end $function$;


-- public.mindagent_chat_start(p_auth_user_id uuid, p_device_key text, p_user_agent text, p_token_hash text, p_origem_codigo text) | mudou: sim | 1 referência de coluna renomeada
-- (engagement.agent_sessions.participante_id na lista do insert -> mind_id. Chave JSON 'pessoa_id' lida de mind_inbound e
--  chave de saída 'participant_id' lida pela Edge Function mindagent-chat ficam.)
CREATE OR REPLACE FUNCTION public.mindagent_chat_start(p_auth_user_id uuid, p_device_key text, p_user_agent text DEFAULT NULL::text, p_token_hash text DEFAULT NULL::text, p_origem_codigo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas', 'auth'
AS $function$
declare
  v_session uuid; v_out jsonb; v_disp uuid; v_conversa uuid;
  v_origem text := nullif(btrim(coalesce(p_origem_codigo, '')), '');
  v_expira timestamptz := now() + interval '24 hours';
begin
  if p_auth_user_id is null or not exists (select 1 from auth.users where id = p_auth_user_id) then
    raise exception using errcode='28000', message='invalid_auth_user';
  end if;
  if p_device_key is null or length(btrim(p_device_key)) < 8 or length(p_device_key) > 160 then
    raise exception using errcode='22023', message='invalid_device_key';
  end if;
  if p_token_hash is null or p_token_hash !~ '^[a-f0-9]{64}$' then
    raise exception using errcode='22023', message='invalid_token_hash';
  end if;
  -- Codigo de origem e identificador, nao texto livre.
  if v_origem is not null and v_origem !~ '^[a-z][a-z0-9_]{1,59}$' then
    raise exception using errcode='22023', message='invalid_origem_codigo';
  end if;

  -- o core resolve conversa + identidade (auth_user e a evidencia mais forte)
  v_out := public.mind_inbound(jsonb_build_object(
    'canal','mindagent-web', 'agente','mindagent-chat',
    'user_agent', p_user_agent,
    'identificadores', jsonb_build_object(
      'auth_user_id', p_auth_user_id::text, 'dispositivo', btrim(p_device_key))));

  v_conversa := (v_out->>'conversa_id')::uuid;
  select dispositivo_id into v_disp from engagement.conversas where id = v_conversa;

  -- Primeira entrada manda. Turno posterior nao reescreve a porta de entrada.
  if v_origem is not null then
    update engagement.conversas
       set origem_codigo = v_origem
     where id = v_conversa and origem_codigo is null;
  end if;

  insert into engagement.agent_sessions
    (dispositivo_id, mind_id, auth_user_id, token_hash, origem_identidade,
     confianca, expira_em)
  values (v_disp, nullif(v_out->>'pessoa_id','')::uuid, p_auth_user_id, p_token_hash,
          'supabase_auth', 'alta', v_expira)
  returning id into v_session;

  return jsonb_build_object(
    'session_id', v_session,
    'conversation_id', v_out->'conversa_id',
    'participant_id',  v_out->'pessoa_id',
    'origem_codigo', (select origem_codigo from engagement.conversas where id = v_conversa),
    'expires_at', v_expira,
    'identity_verified', true);
end $function$;


-- public.mind_checkout_click_registrar(p_event_id uuid, p_request_id uuid) | mudou: sim | 1 referência de coluna renomeada
-- (v_event é engagement.agente_eventos%rowtype: v_event.participante_id -> v_event.mind_id, o campo do rowtype segue a coluna.
--  engagement.checkout_clicks.participant_id NÃO está na lista e fica. Atenção: engagement.checkout_clicks não existe hoje
--  no banco vivo — ver riscos.)
-- engagement.checkout_clicks nao existe mais (BACKLOG secao 20): criar sem validar o corpo, como a versao viva
set check_function_bodies = off;
CREATE OR REPLACE FUNCTION public.mind_checkout_click_registrar(p_event_id uuid, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_event engagement.agente_eventos%rowtype; v_click engagement.checkout_clicks%rowtype;
begin
  if p_event_id is null or p_request_id is null then
    raise exception 'checkout_click_invalid' using errcode='22023';
  end if;
  select e.* into v_event from engagement.agente_eventos e
  where e.id=p_event_id and e.tipo='checkout_link_enviado';
  if not found then return jsonb_build_object('ok',false,'reason','not_found'); end if;
  if coalesce(v_event.dados->>'checkout_url_original','') !~* '^https://([a-z0-9-]+\.)*eduzz\.com/' then
    raise exception 'checkout_destination_invalid' using errcode='22023';
  end if;
  insert into engagement.checkout_clicks(event_id,conversation_id,participant_id,request_id)
  values(v_event.id,v_event.conversa_id,v_event.mind_id,p_request_id)
  on conflict(request_id) do nothing;
  select c.* into v_click from engagement.checkout_clicks c where c.request_id=p_request_id;
  if v_click.event_id is distinct from p_event_id then
    raise exception 'checkout_click_request_conflict' using errcode='23505';
  end if;
  return jsonb_build_object(
    'ok',true,'event_id',v_event.id,'conversation_id',v_event.conversa_id,
    'checkout_url',v_event.dados->>'checkout_url_original',
    'channel',v_event.dados->>'canal','agent_id',v_event.dados->>'agente',
    'route',v_event.dados->>'rota','reason',v_event.dados->>'motivo',
    'clicked_at',v_click.clicked_at
  );
end
$function$;
set check_function_bodies = on;


-- public.mind_checkout_envio_registrar(p_evento_id uuid, p_conversa_id uuid, p_checkout_url text, p_canal text, p_agente text, p_rota text, p_motivo text, p_request_id text) | mudou: sim | 2 referências de coluna renomeadas
-- (engagement.conversas.participante_id -> mind_id no select; engagement.agente_eventos.participante_id -> mind_id na lista do insert.
--  Variável local v_participante_id fica.)
CREATE OR REPLACE FUNCTION public.mind_checkout_envio_registrar(p_evento_id uuid, p_conversa_id uuid, p_checkout_url text, p_canal text, p_agente text, p_rota text, p_motivo text, p_request_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
declare
  v_participante_id uuid;
  v_existente engagement.agente_eventos%rowtype;
begin
  if p_evento_id is null or p_conversa_id is null then
    raise exception 'evento_e_conversa_obrigatorios' using errcode = '22023';
  end if;

  if p_canal not in ('whatsapp', 'app') then
    raise exception 'canal_invalido' using errcode = '22023';
  end if;

  if p_checkout_url is null
     or p_checkout_url !~* '^https://([a-z0-9-]+\.)*eduzz\.com/' then
    raise exception 'checkout_nao_oficial' using errcode = '22023';
  end if;

  if coalesce(p_agente, '') !~ '^[a-z][a-z0-9_-]{1,79}$'
     or coalesce(p_rota, '') !~ '^[a-z][a-z0-9_]{1,59}$'
     or coalesce(p_motivo, '') !~ '^[a-z][a-z0-9_]{1,159}$' then
    raise exception 'metadado_invalido' using errcode = '22023';
  end if;

  select c.mind_id
    into v_participante_id
  from engagement.conversas c
  where c.id = p_conversa_id;

  if not found then
    raise exception 'conversa_inexistente' using errcode = '22023';
  end if;

  insert into engagement.agente_eventos (
    id, mind_id, conversa_id, tipo, intencao, dados
  ) values (
    p_evento_id,
    v_participante_id,
    p_conversa_id,
    'checkout_link_enviado',
    'compra',
    jsonb_build_object(
      'canal', p_canal,
      'agente', p_agente,
      'rota', p_rota,
      'motivo', p_motivo,
      'checkout_url_original', p_checkout_url,
      'request_id', nullif(p_request_id, ''),
      'estado', 'emitido_pelo_runtime'
    )
  )
  on conflict (id) do nothing;

  select e.* into v_existente
  from engagement.agente_eventos e
  where e.id = p_evento_id;

  if v_existente.conversa_id is distinct from p_conversa_id
     or v_existente.tipo is distinct from 'checkout_link_enviado'
     or v_existente.dados->>'checkout_url_original' is distinct from p_checkout_url then
    raise exception 'evento_id_em_conflito' using errcode = '23505';
  end if;

  return jsonb_build_object(
    'ok', true,
    'event_id', v_existente.id,
    'conversation_id', v_existente.conversa_id,
    'channel', v_existente.dados->>'canal',
    'agent_id', v_existente.dados->>'agente',
    'reason', v_existente.dados->>'motivo',
    'sent_at', v_existente.criado_em
  );
end
$function$;


-- public.mind_checkout_event_purchase_status(p_event_id uuid) | mudou: sim | 2 referências de coluna renomeadas
-- (engagement.agente_eventos.participante_id -> mind_id no select e no group by. Variável v_participant, view
--  intelligence.v_conversoes_agente (colunas event_id/paid) e eduzz.vendas (só colunas de cliente/status) ficam.
--  Atenção: engagement.checkout_clicks não existe hoje no banco vivo — ver riscos.)
CREATE OR REPLACE FUNCTION public.mind_checkout_event_purchase_status(p_event_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_conversation uuid;
  v_participant uuid;
  v_clicked_at timestamptz;
  v_email text;
  v_phone text;
  v_last_sync timestamptz;
  v_sync_ok boolean;
begin
  select e.conversa_id,e.mind_id,min(c.clicked_at)
    into v_conversation,v_participant,v_clicked_at
  from engagement.agente_eventos e
  join engagement.checkout_clicks c on c.event_id=e.id
  where e.id=p_event_id and e.tipo='checkout_link_enviado'
  group by e.conversa_id,e.mind_id;
  if v_conversation is null then return 'unknown'; end if;

  if exists(select 1 from intelligence.v_conversoes_agente v where v.event_id=p_event_id and v.paid)
     or public.mind_recovery_purchase_status(v_conversation)='purchased' then
    return 'purchased';
  end if;

  select lower(nullif(btrim(p.email),'')),right(regexp_replace(coalesce(p.whatsapp,''),'\D','','g'),11)
    into v_email,v_phone from pessoas.pessoas p where p.id=v_participant;
  if v_email is null and length(coalesce(v_phone,''))<10 then return 'unknown'; end if;

  -- A conclusão da varredura completa é a evidência de ausência. O maior
  -- `sincronizado_em` de uma venda isolada não prova que as outras vendas já
  -- foram lidas.
  select e.concluido_em,
    e.status='ok' and e.registros_lidos=e.total_na_origem
      and e.registros_gravados=e.total_na_origem
    into v_last_sync,v_sync_ok
  from public.espelho_estado e
  where e.fonte='vendas' and e.destino='eduzz.vendas';
  if not coalesce(v_sync_ok,false) or v_last_sync is null or v_clicked_at is null
     or v_last_sync<v_clicked_at then return 'unknown'; end if;

  if exists (
    select 1 from eduzz.vendas v
    where lower(coalesce(v.status,'')) in ('paga','paid','aprovada','approved')
      and (
        (v_email is not null and lower(btrim(coalesce(v.cliente_email,'')))=v_email)
        or (length(coalesce(v_phone,''))>=10
          and right(regexp_replace(coalesce(v.cliente_telefone_norm,v.cliente_fones,''),'\D','','g'),11)=v_phone)
      )
  ) then return 'purchased'; end if;
  return 'not_purchased';
end
$function$;


-- bloco 7
-- public.mind_checkout_abandonment_refresh() | mudou: sim | 3 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_checkout_abandonment_refresh()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_count integer;
begin
  insert into intelligence.analise_conversa as a (
    conversa_id,mind_id,analisador,funcao,vertical,dados,modelo,prompt_versao,
    conversa_atualizada_ate,analisado_em,criado_em,atualizado_em
  )
  select x.conversation_id,x.participante_id,'checkout_abandonment_v1','comercial',
    coalesce(nullif(e.dados->>'rota',''),'summit_b2c'),
    jsonb_build_object(
      'motion',coalesce(nullif(e.dados->>'rota',''),'summit_b2c'),
      'purchase_intent','very_high',
      'primary_barrier','checkout_abandonment',
      'continuation_status','silence',
      'conversation_summary','Abriu o checkout oficial e o pagamento não foi confirmado após 12 horas.',
      'next_best_move','Retomar o checkout sem reabrir uma decisão já tomada.',
      'followup_anchor','checkout aberto e pagamento ainda não confirmado',
      'response_target','Concluir a compra ou informar se surgiu algum impedimento.',
      'evidence',jsonb_build_object('type','checkout_click','event_id',x.event_id,'clicked_at',x.last_clicked_at)
    ),null,1,x.last_clicked_at,now(),now(),now()
  from intelligence.v_checkout_abandonment x
  join engagement.agente_eventos e on e.id=x.event_id
  where x.abandonment_state<>'monitoring'
  on conflict (conversa_id,analisador) do update set
    mind_id=excluded.mind_id,vertical=excluded.vertical,dados=excluded.dados,
    conversa_atualizada_ate=excluded.conversa_atualizada_ate,
    analisado_em=excluded.analisado_em,atualizado_em=excluded.atualizado_em
  where a.conversa_atualizada_ate is distinct from excluded.conversa_atualizada_ate
     or a.dados is distinct from excluded.dados;

  -- Materializa também as conversas que ainda não tinham passado pelo
  -- analisador geral. O dispatcher continua desligado e a fila continua vazia.
  perform public.mind_recovery_refresh(10000);

  with latest as materialized (
    select distinct on (a.conversation_id) a.*
    from intelligence.v_checkout_abandonment a
    where a.abandonment_state<>'monitoring'
    order by a.conversation_id,a.last_clicked_at desc,a.event_id
  ), updated as (
    update intelligence.recovery_inbox r set
      checkout_event_id=a.event_id,checkout_clicked_at=a.last_clicked_at,
      purchase_status='not_purchased',
      heat='very_hot',objection='checkout_abandonment',objection_group='checkout_abandonment',
      recommended_action='retomar_checkout_sem_reabrir_a_decisao',
      followup_anchor='checkout aberto e pagamento ainda não confirmado',
      inbox_state=case when a.abandonment_state='needs_hsm' then 'needs_hsm'
                       when a.channel in ('mindagent-web','app') then 'app_inbox'
                       else 'freeform_ready' end,
      next_send_at=case when a.channel='whatsapp' then public.mind_recovery_delivery_slot(
        a.abandonment_due_at,a.whatsapp_window_expires_at,'whatsapp') else greatest(a.abandonment_due_at,now()) end,
      draft_status=case when r.checkout_event_id is distinct from a.event_id then 'stale' else r.draft_status end,
      refreshed_at=now(),updated_at=now()
    from latest a where r.conversation_id=a.conversation_id
      and r.inbox_state not in ('excluded_purchased','blocked_optout','blocked_human_owned')
    returning 1
  ) select count(*) into v_count from updated;

  return jsonb_build_object('ok',true,'abandonments_marked',v_count,'dispatcher_enabled',false);
end
$function$;

-- public.mind_conversa_estado(p_conversa_id uuid) | mudou: sim | 2 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_conversa_estado(p_conversa_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
  select jsonb_build_object(
    'historico', coalesce((
      select jsonb_agg(jsonb_build_object('papel', m.papel, 'conteudo', m.conteudo)
                       order by m.criado_em)
      from (select papel, conteudo, criado_em from engagement.mensagens
             where conversa_id = p_conversa_id order by criado_em desc limit 12) m), '[]'::jsonb),
    'turnos_do_agente', (select count(*) from engagement.mensagens
                          where conversa_id = p_conversa_id and papel = 'agente'),
    'credenciamento', (select public.mind_credenciamento_fatos(c.mind_id)
                         from engagement.conversas c where c.id = p_conversa_id),
    'perfil', (select jsonb_strip_nulls(jsonb_build_object(
                 'pessoa_id', p.id, 'primeiro_nome', p.primeiro_nome, 'sobrenome', p.sobrenome,
                 'email', p.email, 'whatsapp', p.whatsapp, 'empresa', p.empresa, 'cargo', p.cargo))
               from engagement.conversas c join pessoas.pessoas p on p.id = c.mind_id
              where c.id = p_conversa_id),
    'rota_ativa', (select case when jsonb_typeof(c.variables) = 'object'
                          then nullif(btrim(coalesce(c.variables->>'rota_ativa', '')), '')
                        end
                    from engagement.conversas c where c.id = p_conversa_id));
$function$;

-- public.mind_kit_programacao_filtrada(p_conversa_id uuid, p_necessidade jsonb) | mudou: sim | 1 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_kit_programacao_filtrada(p_conversa_id uuid DEFAULT NULL::uuid, p_necessidade jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_base jsonb;
  v_pessoa uuid;
  v_cred jsonb;
  v_categorias text[] := '{}'::text[];
  v_sessoes jsonb := '[]'::jsonb;
begin
  v_base := public.mind_kit_programacao(p_conversa_id,p_necessidade);
  if v_base is null then return null; end if;

  select c.mind_id into v_pessoa
  from engagement.conversas c where c.id=p_conversa_id;

  if v_pessoa is null then
    return v_base || jsonb_build_object('ingresso',jsonb_build_object(
      'identificado',false,'recomendacoes_filtradas',false));
  end if;

  v_cred := public.mind_credenciamento_fatos(v_pessoa);
  -- mind_credenciamento_fatos já é a casa que decide categoria válida (ativo,
  -- não revogado, sem a sentinela "SEM MAPA"). Só normaliza para minúsculas
  -- aqui; não reaplica um segundo allowlist que fica esquecido no próximo
  -- tipo de ingresso novo.
  select coalesce(array_agg(lower(x)), '{}'::text[])
    into v_categorias
  from jsonb_array_elements_text(coalesce(v_cred->'categorias','[]'::jsonb)) x;

  if coalesce((v_cred->>'tem_ingresso_ativo')::boolean,false)
     and cardinality(v_categorias)>0 then
    select coalesce(jsonb_agg(item order by ord),'[]'::jsonb)
      into v_sessoes
    from jsonb_array_elements(coalesce(v_base->'sessions','[]'::jsonb))
           with ordinality j(item,ord)
    join summit_2026.sessions s on s.id=(j.item->>'id')::uuid
    where coalesce(s.ingressos,'{}'::text[]) && v_categorias;
  end if;

  v_base := jsonb_set(v_base,'{sessions}',v_sessoes,true);
  v_base := jsonb_set(v_base,'{sessions_total}',to_jsonb(jsonb_array_length(v_sessoes)),true);
  return v_base || jsonb_build_object('ingresso',jsonb_build_object(
    'identificado',true,
    'tem_ingresso_ativo',coalesce((v_cred->>'tem_ingresso_ativo')::boolean,false),
    'categorias',coalesce(v_cred->'categorias','[]'::jsonb),
    'categorias_aplicadas',to_jsonb(v_categorias),
    'recomendacoes_filtradas',true,
    'motivo_sem_sessoes',case
      when not coalesce((v_cred->>'tem_ingresso_ativo')::boolean,false) then 'sem_ingresso_ativo'
      when cardinality(v_categorias)=0 then 'categoria_sem_regra_de_acesso'
      when jsonb_array_length(v_sessoes)=0 then 'nenhuma_sessao_compativel_na_busca'
      else null end));
end
$function$;

-- public.hubspot_commercial_candidates(p_limit integer, p_after timestamp with time zone) | mudou: sim | 7 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.hubspot_commercial_candidates(p_limit integer, p_after timestamp with time zone)
 RETURNS TABLE(analysis_id uuid, conversation_id uuid, participant_id uuid, contact_id text, contact_count bigint, contact_mirror_missing_count bigint, identity_pending boolean, existing_lead_id text, lead_count bigint, lead_name text, pipeline_id text, pipeline_config_count bigint, current_stage text, analysis jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  with pipeline_config as materialized (
    select nullif(btrim(i.config ->> 'pipeline_leads_inbound'), '') as pipeline_id
      from platform.integracoes i
     where i.codigo = 'hubspot'
       and i.ativo
  ), pipeline as materialized (
    select
      case when count(*) = 1 then min(pipeline_id)
      end as pipeline_id,
      count(*)::bigint as config_count
    from pipeline_config
  ), latest_per_conversation as materialized (
    select distinct on (a.conversa_id)
      a.id,
      a.conversa_id,
      a.mind_id,
      a.dados,
      a.analisado_em
    from intelligence.analise_conversa a
    join engagement.conversas c on c.id = a.conversa_id
    where c.agente = 'treble-inbound-agent'
      and a.analisador = 'analise_vendas_summit'
      and a.analisado_em >= p_after
    order by a.conversa_id, a.analisado_em desc, a.id desc
  ), latest_per_participant as materialized (
    select distinct on (a.mind_id)
      a.*
    from latest_per_conversation a
    where a.mind_id is not null
    order by a.mind_id, a.analisado_em desc, a.id desc
  ), eligible as materialized (
    select a.*
      from latest_per_participant a
     where not exists (
       select 1
         from crm.hubspot_commercial_writeback w
        where w.analysis_id = a.id
          and (
            w.status = 'sent'
            or (
              w.status = 'reserved'
              and (
                w.action = 'create'
                or w.attempt_count >= 3
                or w.reserved_at > now() - interval '15 minutes'
              )
            )
            or (
              w.status = 'failed'
              and (
                not w.retryable
                or w.action = 'create'
                or w.attempt_count >= 3
                or w.next_retry_at is null
                or w.next_retry_at > now()
              )
            )
          )
     )
  ), selected as materialized (
    select l.*
      from eligible l
     order by l.analisado_em, l.id
     limit greatest(1, least(coalesce(p_limit, 25), 50))
  ), facts as materialized (
    select
      s.*,
      public.mind_crm_comercial(s.mind_id) as commercial,
      public.mind_pessoa_fatos(s.mind_id) as person
    from selected s
  )
  select
    f.id as analysis_id,
    f.conversa_id as conversation_id,
    f.mind_id as participant_id,
    case
      when coalesce(leads.lead_count, 0) = 1 then leads.primary_contact_id
      when coalesce(leads.lead_count, 0) = 0 and coalesce(contacts.contact_count, 0) = 1
        then contacts.contact_ids[1]
    end as contact_id,
    coalesce(contacts.contact_count, 0)::bigint as contact_count,
    coalesce((f.person #>> '{meta,identidades_hubspot_sem_espelho}')::bigint, 0)
      as contact_mirror_missing_count,
    coalesce((f.person #>> '{meta,pendencia_identidade,aberta}')::boolean, false)
      as identity_pending,
    case when coalesce(leads.lead_count, 0) = 1 then leads.lead_id end as existing_lead_id,
    coalesce(leads.lead_count, 0)::bigint as lead_count,
    coalesce(
      nullif(btrim(concat_ws(' ',
        f.person #>> '{perfil,primeiro_nome}',
        f.person #>> '{perfil,sobrenome}'
      )), ''),
      nullif(btrim(c.nome_contato), ''),
      'Lead WhatsApp'
    ) || case
      when nullif(btrim(f.person #>> '{perfil,empresa}'), '') is not null
        then ' - ' || btrim(f.person #>> '{perfil,empresa}')
      else ''
    end as lead_name,
    p.pipeline_id,
    p.config_count as pipeline_config_count,
    case when coalesce(leads.lead_count, 0) = 1 then leads.current_stage end as current_stage,
    f.dados as analysis
  from facts f
  join engagement.conversas c on c.id = f.conversa_id
  cross join pipeline p
  left join lateral (
    select
      array_agg(distinct x.contact_id order by x.contact_id) as contact_ids,
      count(distinct x.contact_id)::bigint as contact_count
    from jsonb_array_elements_text(
      case
        when jsonb_typeof(f.commercial #> '{meta,contatos_hubspot_considerados}') = 'array'
          then f.commercial #> '{meta,contatos_hubspot_considerados}'
        else '[]'::jsonb
      end
    ) x(contact_id)
    where nullif(btrim(x.contact_id), '') is not null
  ) contacts on true
  left join lateral (
    select
      count(distinct x.item ->> 'hubspot_lead_id')::bigint as lead_count,
      min(x.item ->> 'hubspot_lead_id') as lead_id,
      min(x.item ->> 'hs_pipeline_stage') as current_stage,
      min(x.item ->> 'hs_primary_contact_id') as primary_contact_id
    from jsonb_array_elements(
      case
        when jsonb_typeof(f.commercial -> 'lead_atual') = 'array'
          then f.commercial -> 'lead_atual'
        else '[]'::jsonb
      end
    ) x(item)
    where p.pipeline_id is not null
      and x.item ->> 'hs_pipeline' = p.pipeline_id
      and nullif(btrim(x.item ->> 'hubspot_lead_id'), '') is not null
      and nullif(btrim(x.item ->> 'hs_primary_contact_id'), '') is not null
  ) leads on true
  order by f.analisado_em, f.id;
$function$;

-- public.mind_identidade_resolver(p_identificadores jsonb, p_nome text, p_canal text, p_pessoa_ancora uuid, p_criar boolean) | mudou: sim | 6 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_identidade_resolver(p_identificadores jsonb, p_nome text DEFAULT NULL::text, p_canal text DEFAULT NULL::text, p_pessoa_ancora uuid DEFAULT NULL::uuid, p_criar boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
declare
  v_ids       jsonb := public.mind_identificadores_normalizar(p_identificadores);
  v_item      jsonb;
  v_achados   jsonb := '[]'::jsonb;
  v_recusados jsonb := '[]'::jsonb;
  v_cand      record;
  v_pessoa    uuid;
  v_outro     uuid;
  v_criada    boolean := false;
  v_conflito  jsonb := null;
  v_nome      text := nullif(left(btrim(coalesce(p_nome,'')),160),'');
  v_nome_pessoa text;
  v_primeiro  text;
  v_sobrenome text;
  v_tel       text;
  v_mail      text;
  v_dono      uuid;
  v_vinculadas jsonb := '[]'::jsonb;
  v_origem    text;
  v_canal_conf text;
  v_tem_email_entrada boolean;
  v_casou_por text[];
  v_nome_divergente boolean := false;
  v_r         jsonb;
begin
  if jsonb_array_length(v_ids) = 0 then
    return jsonb_build_object('pessoa_id', p_pessoa_ancora, 'criada', false,
      'motivo','sem_identificador_deterministico', 'conflito', null,
      'ancorada', p_pessoa_ancora is not null, 'identidades', '[]'::jsonb, 'casou_por', '[]'::jsonb, 'recusados', '[]'::jsonb);
  end if;

  -- Serializa somente entradas que compartilham o mesmo identificador.
  for v_item in
    select x.value from jsonb_array_elements(v_ids) as x(value)
     order by x.value->>'canal', x.value->>'identificador'
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('mind_identidade:' || (v_item->>'canal') || ':' || (v_item->>'identificador'), 0));
  end loop;

  v_tem_email_entrada := exists (select 1 from jsonb_array_elements(v_ids) x where x->>'canal' = 'email');

  -- Procura em identidades e, faltando ali, nas colunas da propria pessoas.pessoas
  -- (Adriana, 23/09: "antes de criar, sempre bater com a tabela pessoas.pessoas").
  for v_item in select * from jsonb_array_elements(v_ids) loop
    select i.mind_id into v_outro
      from engagement.identidades i
     where i.canal = v_item->>'canal' and i.identificador = v_item->>'identificador'
     limit 1;
    if v_outro is null then
      select p.id into v_outro from pessoas.pessoas p
       where p.fundida_em is null
         and ((v_item->>'canal' = 'email'    and lower(p.email) = v_item->>'identificador')
           or (v_item->>'canal' = 'whatsapp' and p.whatsapp = v_item->>'identificador')
           or (v_item->>'canal' = 'hubspot'  and p.hubspot_id = v_item->>'identificador'))
       limit 1;
    end if;
    if v_outro is not null then
      v_outro := coalesce(public.mind_pessoa_canonica(v_outro), v_outro);
      v_achados := v_achados || jsonb_build_array(jsonb_build_object(
        'pessoa_id', v_outro, 'forca', (v_item->>'forca')::int, 'canal', v_item->>'canal', 'identificador', v_item->>'identificador'));
    end if;
  end loop;

  -- A regra da Adriana (23/09), so quando a entrada nao vem ancorada numa pessoa:
  --   * achada so por telefone/CPF/CNPJ com nome que contradiz o da entrada -> outra pessoa (inscrita por terceiro);
  --   * achada so por telefone, com e-mail dos dois lados e nenhum em comum -> outra pessoa
  --     (se os nomes forem compativeis, vira suspeita: proposta media);
  --   * achada por e-mail com nome claramente diferente -> nao se liga (e-mail de comprador/porta-voz): proposta baixa;
  --   * login e ids de terceiro identificam o registro naquele sistema: ligam sempre; nome divergente fica marcado.
  if p_pessoa_ancora is null then
    for v_cand in
      select a.pessoa_id,
             min(public.mind_identidade_precedencia(a.canal)) as prec,
             array_agg(distinct a.canal) as canais,
             bool_or(a.forca >= 2) as forte
        from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text, identificador text)
       group by a.pessoa_id
    loop
      if not v_cand.forte or v_cand.prec <= 2 then continue; end if;   -- apoio (CPF/CNPJ) ou id deterministico: nada a recusar
      select concat_ws(' ', p.primeiro_nome, p.sobrenome) into v_nome_pessoa from pessoas.pessoas p where p.id = v_cand.pessoa_id;
      if v_nome is not null and not public.mind_nomes_compativeis(v_nome, v_nome_pessoa) then
        v_recusados := v_recusados || jsonb_build_array(jsonb_build_object(
          'pessoa_id', v_cand.pessoa_id, 'canais', to_jsonb(v_cand.canais), 'canal', v_cand.canais[1],
          'motivo', case when v_cand.prec = 3 then 'email_igual_nome_diferente'
                         when v_tem_email_entrada and exists (select 1 from engagement.identidades i where i.mind_id = v_cand.pessoa_id and i.canal = 'email')
                              then 'nome_e_email_diferentes' else 'nome_diferente' end,
          'nome_pessoa', v_nome_pessoa));
      elsif v_cand.prec = 4 and v_tem_email_entrada
            and exists (select 1 from engagement.identidades i where i.mind_id = v_cand.pessoa_id and i.canal = 'email') then
        v_recusados := v_recusados || jsonb_build_array(jsonb_build_object(
          'pessoa_id', v_cand.pessoa_id, 'canais', to_jsonb(v_cand.canais), 'canal', 'whatsapp',
          'motivo', 'email_diferente', 'nome_pessoa', v_nome_pessoa));
      end if;
    end loop;
    if jsonb_array_length(v_recusados) > 0 then
      select coalesce(jsonb_agg(a), '[]'::jsonb) into v_achados
        from jsonb_array_elements(v_achados) a
       where not exists (select 1 from jsonb_array_elements(v_recusados) r where r->>'pessoa_id' = a->>'pessoa_id');
    end if;
  end if;

  -- Escolha: a ancora manda; sem ancora, a precedencia decide entre evidencias fortes (forca >= 2).
  if p_pessoa_ancora is not null then
    v_pessoa := p_pessoa_ancora;
  else
    select a.pessoa_id into v_pessoa
      from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text, identificador text)
      join pessoas.pessoas p on p.id = a.pessoa_id
     where a.forca >= 2
     order by public.mind_identidade_precedencia(a.canal), (a.canal = p_canal) desc, p.criado_em asc
     limit 1;
  end if;

  if exists (select 1 from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text, identificador text)
              where v_pessoa is not null and a.pessoa_id <> v_pessoa and a.forca >= 2) then
    v_conflito := jsonb_build_object('pessoa_escolhida', v_pessoa,
                                     'ancorada', p_pessoa_ancora is not null,
                                     'evidencias', v_achados);
    for v_outro in
      select distinct a.pessoa_id
        from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text, identificador text)
       where a.pessoa_id <> v_pessoa and a.forca >= 2
    loop
      perform public.mind_conflito_registrar(
        v_pessoa, 'conflito_identidade',
        case when p_pessoa_ancora is not null
             then 'evidencia nova aponta para outra pessoa; conversa ancorada permanece'
             else 'identificadores da mesma entrada apontam para pessoas diferentes' end,
        v_outro, v_ids);
      select a.canal into v_canal_conf
        from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text, identificador text)
       where a.pessoa_id = v_outro and a.forca >= 2
       order by public.mind_identidade_precedencia(a.canal) limit 1;
      perform public.mind_fusao_propor(v_pessoa, v_outro, v_canal_conf);
    end loop;
  end if;

  if v_pessoa is null then
    -- D5: sem identificador forte (força >= 2) não se cria pessoa
    if not exists (select 1 from jsonb_array_elements(v_ids) x where (x->>'forca')::int >= 2) then
      return jsonb_build_object('pessoa_id', null, 'criada', false,
        'motivo','sem_identificador_forte', 'conflito', null,
        'ancorada', false, 'identidades', '[]'::jsonb, 'casou_por', '[]'::jsonb, 'recusados', v_recusados);
    end if;
    -- Todos os identificadores fortes ja sao de pessoas recusadas pela regra do nome/e-mail:
    -- nao ha o que criar (a pessoa nova nasceria sem identificador proprio). Fica para decisao.
    if not exists (select 1 from jsonb_array_elements(v_ids) x
                    where (x->>'forca')::int >= 2
                      and not exists (select 1 from jsonb_array_elements(v_recusados) r
                                       join jsonb_array_elements(v_ids) y on y->>'canal' = x->>'canal' and y->>'identificador' = x->>'identificador'
                                      where (r->'canais') ? (x->>'canal')
                                        and exists (select 1 from engagement.identidades i where i.mind_id = (r->>'pessoa_id')::uuid
                                                       and i.canal = x->>'canal' and i.identificador = x->>'identificador'))) then
      return jsonb_build_object('pessoa_id', null, 'criada', false,
        'motivo','identificador_forte_de_outra_pessoa', 'conflito', null,
        'ancorada', false, 'identidades', '[]'::jsonb, 'casou_por', '[]'::jsonb, 'recusados', v_recusados);
    end if;
    -- D5: quem chamou pediu para ligar sem criar (fase A ainda não terminou)
    if not p_criar then
      return jsonb_build_object('pessoa_id', null, 'criada', false,
        'motivo','criacao_desligada', 'conflito', null,
        'ancorada', false, 'identidades', '[]'::jsonb, 'casou_por', '[]'::jsonb, 'recusados', v_recusados);
    end if;

    v_primeiro  := nullif(split_part(coalesce(v_nome,''), ' ', 1), '');
    v_sobrenome := nullif(btrim(substr(coalesce(v_nome,''), coalesce(length(v_primeiro),0) + 2)), '');
    v_tel  := (select x->>'identificador' from jsonb_array_elements(v_ids) x where x->>'canal'='whatsapp' limit 1);
    v_mail := (select x->>'identificador' from jsonb_array_elements(v_ids) x where x->>'canal'='email'    limit 1);

    if v_mail is not null and (exists (select 1 from pessoas.pessoas p where lower(p.email) = v_mail)
                               or exists (select 1 from engagement.identidades i where i.canal = 'email' and i.identificador = v_mail))
      then v_mail := null; end if;
    if v_tel is not null and (exists (select 1 from pessoas.pessoas p where p.whatsapp = v_tel)
                              or exists (select 1 from engagement.identidades i where i.canal = 'whatsapp' and i.identificador = v_tel))
      then v_tel := null; end if;

    v_origem := case
      when p_canal in ('contato_espelho','hubspot') then 'hubspot'
      when p_canal in ('pedidos','compradores','checkout') then 'checkout'
      when p_canal in ('participantes','yazo_espelho','credenciamento') or p_canal ilike 'relatorio%' or p_canal ilike 'yazo%' then 'credenciamento'
      when p_canal in ('ingressos','vendas','eduzz') then 'eduzz'
      when p_canal in ('leads_capturados','site') then 'site'
      else 'bot' end;

    insert into pessoas.pessoas (primeiro_nome, sobrenome, whatsapp, email, origem, enriquecida_em)
    values (v_primeiro, v_sobrenome, v_tel, v_mail, v_origem, now())
    returning id into v_pessoa;
    v_criada := true;
  elsif v_nome is not null then
    select concat_ws(' ', p.primeiro_nome, p.sobrenome) into v_nome_pessoa from pessoas.pessoas p where p.id = v_pessoa;
    v_nome_divergente := not public.mind_nomes_compativeis(v_nome, v_nome_pessoa);
    if not v_nome_divergente then
      v_primeiro  := nullif(split_part(v_nome, ' ', 1), '');
      v_sobrenome := nullif(btrim(substr(v_nome, coalesce(length(v_primeiro),0) + 2)), '');
      update pessoas.pessoas
         set primeiro_nome = coalesce(primeiro_nome, v_primeiro),
             sobrenome     = coalesce(sobrenome, v_sobrenome),
             atualizado_em = now()
       where id = v_pessoa and (primeiro_nome is null or sobrenome is null);
    end if;
  end if;

  -- por onde a pessoa foi encontrada (antes de acrescentar o que faltava)
  select coalesce(array_agg(distinct a.canal order by a.canal), '{}') into v_casou_por
    from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text, identificador text)
   where a.pessoa_id = v_pessoa;

  for v_item in select * from jsonb_array_elements(v_ids) loop
    select i.mind_id into v_dono
      from engagement.identidades i
     where i.canal = v_item->>'canal' and i.identificador = v_item->>'identificador';
    if v_dono is null then
      insert into engagement.identidades (mind_id, canal, identificador, verificado, confianca)
      values (v_pessoa, v_item->>'canal', v_item->>'identificador',
              (v_item->>'verificado')::boolean, v_item->>'confianca')
      on conflict (canal, identificador) do nothing;
      v_vinculadas := v_vinculadas || jsonb_build_array(v_item);

      if v_item->>'canal' = 'email' then
        update pessoas.pessoas p set email = v_item->>'identificador', atualizado_em = now()
         where p.id = v_pessoa and p.email is null
           and not exists (select 1 from pessoas.pessoas q where lower(q.email) = v_item->>'identificador');
      elsif v_item->>'canal' = 'whatsapp' then
        update pessoas.pessoas p set whatsapp = v_item->>'identificador', atualizado_em = now()
         where p.id = v_pessoa and p.whatsapp is null
           and not exists (select 1 from pessoas.pessoas q where q.whatsapp = v_item->>'identificador');
      elsif v_item->>'canal' = 'hubspot' then
        update pessoas.pessoas p set hubspot_id = v_item->>'identificador', atualizado_em = now()
         where p.id = v_pessoa and p.hubspot_id is null
           and not exists (select 1 from pessoas.pessoas q where q.hubspot_id = v_item->>'identificador');
      end if;
    end if;
  end loop;

  -- Recusados que ainda merecem um olhar da Adriana: nome igual com e-mail diferente (suspeita, media)
  -- e e-mail igual com nome diferente (comprador/porta-voz?, baixa). Nome E e-mail diferentes sao,
  -- por decisao dela, pessoas diferentes inscritas por terceiro: nao viram proposta.
  for v_r in select r from jsonb_array_elements(v_recusados) r
              where r->>'motivo' in ('email_diferente', 'email_igual_nome_diferente')
  loop
    if (v_r->>'pessoa_id')::uuid <> v_pessoa then
      perform public.mind_conflito_registrar(
        v_pessoa, 'conflito_identidade',
        case v_r->>'motivo'
          when 'email_diferente' then 'mesmo telefone, nomes compatíveis, e-mails diferentes: suspeita de mesma pessoa'
          else 'mesmo e-mail com nomes claramente diferentes: e-mail de comprador ou porta-voz?' end,
        (v_r->>'pessoa_id')::uuid, v_ids);
      perform public.mind_fusao_propor(v_pessoa, (v_r->>'pessoa_id')::uuid, v_r->>'canal');
    end if;
  end loop;

  return jsonb_build_object(
    'pessoa_id', v_pessoa, 'criada', v_criada, 'conflito', v_conflito,
    'ancorada', p_pessoa_ancora is not null, 'identidades', v_vinculadas,
    'casou_por', to_jsonb(v_casou_por), 'nome_divergente', v_nome_divergente, 'recusados', v_recusados);
end $function$;

-- public.mind_fusao_propor(p_a uuid, p_b uuid, p_canal_conflito text) | mudou: sim | 10 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_fusao_propor(p_a uuid, p_b uuid, p_canal_conflito text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
declare
  ca text[]; cb text[]; nome_a text; nome_b text; n_a int; n_b int; c_a timestamptz; c_b timestamptz;
  v_padrao text; v_sob uuid; v_abs uuid; v_conf text; v_motivo text; v_tel_pessoas int := 0;
  v_prop jsonb; cpf_a text; cpf_b text; v_nota text := ''; v_nomes_ok boolean; v_nome_igual boolean;
  v_existente jsonb; v_canal text := p_canal_conflito; v_canais text[];
begin
  if p_a is null or p_b is null or p_a = p_b then return null; end if;
  -- CPF/CNPJ nunca abrem proposta sozinhos (Adriana, 23/09)
  if p_canal_conflito in ('cpf','cnpj') then return null; end if;

  -- o que o par ja compartilhava, segundo a proposta pendente: a evidencia mais forte vence
  select f.proposta into v_existente
    from engagement.identidade_fusoes f
   where f.status = 'pendente' and f.participante_origem is not null and f.proposta is not null
     and least(f.mind_id, f.participante_origem) = least(p_a, p_b)
     and greatest(f.mind_id, f.participante_origem) = greatest(p_a, p_b)
   order by f.criado_em limit 1;
  select coalesce(array_agg(distinct c), '{}') into v_canais
    from (select jsonb_array_elements_text(coalesce(v_existente->'canais', '[]'::jsonb)) c
          union select v_existente->>'canal' where v_existente->>'canal' is not null
          union select p_canal_conflito where p_canal_conflito is not null) s;
  select c into v_canal from unnest(v_canais) c order by public.mind_identidade_precedencia(c) limit 1;

  select coalesce(array_agg(distinct canal), '{}'), count(*) into ca, n_a from engagement.identidades where mind_id = p_a;
  select coalesce(array_agg(distinct canal), '{}'), count(*) into cb, n_b from engagement.identidades where mind_id = p_b;
  select concat_ws(' ', primeiro_nome, sobrenome), criado_em into nome_a, c_a from pessoas.pessoas where id = p_a;
  select concat_ws(' ', primeiro_nome, sobrenome), criado_em into nome_b, c_b from pessoas.pessoas where id = p_b;
  select identificador into cpf_a from engagement.identidades where mind_id = p_a and canal = 'cpf' limit 1;
  select identificador into cpf_b from engagement.identidades where mind_id = p_b and canal = 'cpf' limit 1;
  v_nomes_ok   := public.mind_nomes_compativeis(nome_a, nome_b);
  v_nome_igual := cardinality(public.mind_nome_tokens(nome_a)) > 0 and cardinality(public.mind_nome_tokens(nome_b)) > 0 and v_nomes_ok;

  if 'whatsapp' = any(v_canais) then
    select count(distinct i.mind_id) into v_tel_pessoas
      from engagement.identidades i
     where i.canal = 'whatsapp'
       and i.identificador in (select identificador from engagement.identidades where mind_id in (p_a, p_b) and canal = 'whatsapp');
  end if;

  v_padrao := case
    when not v_nomes_ok and v_canal = 'email' then 'mesmo_email_nomes_diferentes'
    when not v_nomes_ok then 'nomes_divergentes'
    when v_canal = 'email'
         and (('hubspot' = any(ca) and not 'auth_user' = any(ca) and 'auth_user' = any(cb))
           or ('hubspot' = any(cb) and not 'auth_user' = any(cb) and 'auth_user' = any(ca))) then 'mesmo_email_hubspot_x_login'
    when v_canal = 'email' and 'hubspot' = any(ca) and 'hubspot' = any(cb) then 'mesmo_email_dois_hubspot'
    when v_canal = 'email' then 'mesmo_email'
    when v_canal = 'whatsapp' and v_tel_pessoas > 2 then 'telefone_compartilhado'
    when v_canal = 'whatsapp' then 'mesmo_telefone_emails_diferentes'
    when v_canal in ('hubspot','yazo','credenciamento','eduzz','learnworlds','auth_user') then 'mesmo_id_de_terceiro'
    else 'outro' end;

  if 'auth_user' = any(ca) and not 'auth_user' = any(cb) then v_sob := p_a;
  elsif 'auth_user' = any(cb) and not 'auth_user' = any(ca) then v_sob := p_b;
  elsif n_a > n_b then v_sob := p_a;
  elsif n_b > n_a then v_sob := p_b;
  elsif c_a <= c_b then v_sob := p_a;
  else v_sob := p_b; end if;
  v_abs := case when v_sob = p_a then p_b else p_a end;

  v_conf := case v_padrao
    when 'mesmo_email_hubspot_x_login' then 'alta'
    when 'mesmo_email_dois_hubspot' then 'alta'
    when 'mesmo_email' then 'alta'
    when 'mesmo_id_de_terceiro' then 'alta'
    when 'mesmo_telefone_emails_diferentes' then 'media'
    else 'baixa' end;
  v_motivo := case v_padrao
    when 'mesmo_email_hubspot_x_login' then 'mesmo e-mail: uma pessoa nasceu do WhatsApp/HubSpot sem e-mail registrado, a outra do login no app; sobrevive quem tem login'
    when 'mesmo_email_dois_hubspot' then 'mesmo e-mail em duas pessoas, ambas ligadas ao HubSpot (dois contatos para a mesma pessoa)'
    when 'mesmo_email' then 'mesmo e-mail em duas pessoas, nomes compatíveis'
    when 'mesmo_id_de_terceiro' then 'o mesmo registro de um sistema de terceiro (HubSpot, Yazo, credenciamento, Eduzz, login) aponta para as duas pessoas'
    when 'mesmo_email_nomes_diferentes' then 'mesmo e-mail com nomes claramente diferentes: e-mail de comprador ou porta-voz? decidir linha a linha'
    when 'mesmo_telefone_emails_diferentes' then 'mesmo telefone, nomes compatíveis, e-mails diferentes: suspeita de mesma pessoa com dois e-mails — caso a caso'
    when 'telefone_compartilhado' then 'telefone em mais de duas pessoas (central/empresa/comprador): nunca aprovar em bloco'
    when 'nomes_divergentes' then 'mesmo telefone com nomes diferentes: provavelmente inscrição por terceiro — decidir linha a linha'
    else 'identificador em comum sem padrão conhecido' end;

  if cpf_a is not null and cpf_b is not null and cpf_a <> cpf_b then
    v_conf := 'baixa'; v_nota := v_nota || '; CPFs diferentes nas duas pessoas: conferir';
  elsif cpf_a is not null and cpf_a = cpf_b then
    v_nota := v_nota || '; mesmo CPF nas duas';
  end if;
  if v_nome_igual then v_nota := v_nota || '; nomes compatíveis'; end if;
  if cardinality(v_canais) > 1 then v_nota := v_nota || '; em comum: ' || array_to_string(v_canais, ', '); end if;
  v_motivo := v_motivo || v_nota;

  v_prop := jsonb_build_object('sobrevive', v_sob, 'absorvida', v_abs, 'padrao', v_padrao,
                               'motivo', v_motivo, 'confianca', v_conf, 'canal', v_canal, 'canais', to_jsonb(v_canais),
                               'cpf_igual', (cpf_a is not null and cpf_a = cpf_b), 'nome_igual', v_nome_igual,
                               'nomes', jsonb_build_array(nome_a, nome_b));

  update engagement.identidade_fusoes f
     set padrao = v_padrao, proposta = v_prop
   where f.status = 'pendente'
     and f.participante_origem is not null
     and least(f.mind_id, f.participante_origem) = least(p_a, p_b)
     and greatest(f.mind_id, f.participante_origem) = greatest(p_a, p_b);
  return v_prop;
end $function$;


-- bloco 8
-- public.mind_pessoa_antes_de_escrever() | mudou: sim | 8 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_pessoa_antes_de_escrever()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
declare
  v_map   jsonb := coalesce(nullif(TG_ARGV[0], '')::jsonb, '{}'::jsonb);
  v_new   jsonb := to_jsonb(NEW);
  v_old   jsonb := case when TG_OP = 'UPDATE' then to_jsonb(OLD) else null end;
  v_ids   jsonb := '{}'::jsonb;
  v_nome  text;
  v_r     jsonb;
  v_k     text;
  v_cols  jsonb;
  v_col   text;
  v_val   text;
  v_vals  jsonb;
  v_mudou boolean := (TG_OP = 'INSERT');
  v_criar boolean;
  v_comprador text;
  v_terceiro boolean := false;
  v_crit  text;
  v_acresc text;
  v_flags text := '';
begin
  -- chave de manutencao: reconstrucoes e cargas controladas passam sem a porta
  if coalesce(current_setting('mind.d5_pular_trigger', true), '') = '1' then
    return NEW;
  end if;

  for v_k, v_cols in select key, value from jsonb_each(v_map) loop
    if jsonb_typeof(v_cols) <> 'array' then v_cols := jsonb_build_array(v_cols); end if;
    v_vals := '[]'::jsonb;
    for v_col in select x #>> '{}' from jsonb_array_elements(v_cols) x loop
      v_val := public.mind_pessoa_ler_valor(v_new, v_col);
      if v_val is not null and btrim(v_val) <> '' then v_vals := v_vals || jsonb_build_array(v_val); end if;
      if v_old is not null and v_val is distinct from public.mind_pessoa_ler_valor(v_old, v_col) then v_mudou := true; end if;
    end loop;
    if jsonb_array_length(v_vals) = 0 then continue; end if;
    if v_k = 'nome' then
      select string_agg(x #>> '{}', ' ') into v_nome from jsonb_array_elements(v_vals) x;
    elsif v_k = 'comprador_email' then
      v_comprador := lower(btrim(v_vals->>0));
    elsif v_k in ('emails','telefones','hubspot_ids','yazo_ids') then
      v_ids := v_ids || jsonb_build_object(v_k, v_vals);
    else
      v_ids := v_ids || jsonb_build_object(v_k, v_vals->>0);
    end if;
  end loop;

  if not v_mudou and NEW.mind_id is not null then
    return NEW;
  end if;

  -- Inscricao feita por terceiro (Adriana, 23/09): o e-mail do participante e outro que o do
  -- comprador -> telefone e CPF da linha sao do comprador, nao da pessoa. Ficam de fora.
  if v_comprador is not null and jsonb_typeof(v_ids->'emails') = 'array'
     and not exists (select 1 from jsonb_array_elements_text(v_ids->'emails') e where lower(btrim(e)) = v_comprador) then
    v_terceiro := true;
    v_ids := v_ids - array['telefones','whatsapp','telefone','phone','cpf','documento','cnpj','eduzz_comprador'];
  end if;

  begin
    v_criar := not exists (select 1 from pessoas.pessoas where enriquecida_em is null and fundida_em is null);
    v_r := public.mind_identidade_resolver(v_ids, v_nome, TG_TABLE_NAME::text, null, v_criar);
    NEW.mind_id := (v_r->>'pessoa_id')::uuid;
    NEW.mind_id_resolvido_em := now();
    if v_terceiro then v_flags := v_flags || ' (inscrito por terceiro: telefone/CPF ignorados)'; end if;
    if jsonb_array_length(coalesce(v_r->'recusados', '[]'::jsonb)) > 0 then
      select ' (recusou: ' || string_agg((r->>'canal') || ' de outra pessoa, ' ||
               case r->>'motivo' when 'nome_e_email_diferentes' then 'nome e e-mail distintos'
                                 when 'nome_diferente' then 'nome distinto'
                                 when 'email_diferente' then 'e-mail distinto'
                                 else 'nome distinto para o mesmo e-mail' end, '; ') || ')'
        into v_acresc from jsonb_array_elements(v_r->'recusados') r;
      v_flags := v_flags || coalesce(v_acresc, '');
    end if;
    if NEW.mind_id is null then
      NEW.mind_id_criterio := (case when v_r->>'motivo' = 'criacao_desligada' then 'aguardando_fase_a' else coalesce(v_r->>'motivo', 'sem_pessoa') end) || v_flags;
    else
      select string_agg(x, ',' order by x) into v_acresc from (select distinct (y->>'canal') x from jsonb_array_elements(coalesce(v_r->'identidades','[]'::jsonb)) y) s;
      if (v_r->>'criada')::boolean then
        v_crit := 'criada: ' || coalesce(v_acresc, 'sem identificador');
      else
        select string_agg(x, ',' order by x) into v_crit from jsonb_array_elements_text(coalesce(v_r->'casou_por','[]'::jsonb)) x;
        v_crit := coalesce(v_crit, 'ancora');
        if v_acresc is not null then v_crit := v_crit || ' +' || v_acresc; end if;
      end if;
      if v_r->'conflito' is not null and jsonb_typeof(v_r->'conflito') <> 'null' then v_flags := ' (conflito)' || v_flags; end if;
      if (v_r->>'nome_divergente')::boolean then v_flags := ' (nome divergente)' || v_flags; end if;
      NEW.mind_id_criterio := v_crit || v_flags;
    end if;
  exception when others then
    NEW.mind_id_criterio := 'erro: ' || left(sqlerrm, 200);
    NEW.mind_id_resolvido_em := now();
  end;
  return NEW;
end $function$;


-- public.mind_pessoa_ligar_tabela(p_tabela regclass, p_mapa jsonb) | mudou: sim | 10 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_pessoa_ligar_tabela(p_tabela regclass, p_mapa jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_sch text; v_tab text; v_q text;
begin
  select n.nspname, c.relname into v_sch, v_tab
    from pg_class c join pg_namespace n on n.oid = c.relnamespace where c.oid = p_tabela;
  v_q := format('%I.%I', v_sch, v_tab);
  execute format('alter table %s add column if not exists mind_id uuid references pessoas.pessoas(id)', v_q);
  execute format('alter table %s add column if not exists mind_id_criterio text', v_q);
  execute format('alter table %s add column if not exists mind_id_resolvido_em timestamptz', v_q);
  execute format('create index if not exists %I on %s (mind_id) where mind_id is not null',
                 left(v_tab, 40) || '_mind_id_idx', v_q);
  execute format('comment on column %s.mind_id is %L', v_q,
    'D5: a pessoa desta linha, resolvida ou criada pela porta única (mind_identidade_resolver) antes da escrita. Nulo = sem identificador forte ou erro; ver mind_id_criterio.');
  execute format('comment on column %s.mind_id_criterio is %L', v_q,
    'Como a pessoa foi encontrada: canais que casaram (email, whatsapp, cpf, hubspot…), "(criada)" quando nasceu nesta linha, "(conflito)" quando havia mais de uma candidata, ou o motivo de não ter pessoa.');
  execute format('comment on column %s.mind_id_resolvido_em is %L', v_q, 'Quando a porta única resolveu esta linha pela última vez.');
  execute format('drop trigger if exists zz_d5_pessoa_antes_de_escrever on %s', v_q);
  execute format('create trigger zz_d5_pessoa_antes_de_escrever before insert or update on %s for each row execute function public.mind_pessoa_antes_de_escrever(%L)',
                 v_q, p_mapa::text);
  return v_q;
end $function$;


-- public.mind_pessoa_enriquecer(p_pessoa_id uuid) | mudou: sim | 17 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_pessoa_enriquecer(p_pessoa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
declare
  v_emails text[]; v_tels text[]; v_hubs text[]; v_docs text[]; v_yazo text[]; v_cred text[]; v_edz text[]; v_lw text[];
  v_nome text; v_ids jsonb := '{}'::jsonb; v_r jsonb; v_antes int; v_depois int; v_ignoradas int; v_usadas int;
  v_nome_pessoa text;
  a_emails text[]; a_tels text[]; a_hubs text[]; a_cred uuid[]; a_yazo bigint[]; a_edz text[];
begin
  if p_pessoa_id is null then return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa'); end if;
  if exists (select 1 from pessoas.pessoas where id = p_pessoa_id and fundida_em is not null) then
    return jsonb_build_object('ok', false, 'motivo', 'pessoa_fundida');
  end if;

  select count(*) into v_antes from engagement.identidades where mind_id = p_pessoa_id;
  select concat_ws(' ', primeiro_nome, sobrenome) into v_nome_pessoa from pessoas.pessoas where id = p_pessoa_id;

  -- identificadores atuais da pessoa, em arrays: cada fonte e procurada por indice
  with atual as (
    select canal, identificador from engagement.identidades where mind_id = p_pessoa_id
    union select 'email', lower(email) from pessoas.pessoas where id = p_pessoa_id and email is not null
    union select 'whatsapp', whatsapp from pessoas.pessoas where id = p_pessoa_id and whatsapp is not null
    union select 'hubspot', hubspot_id from pessoas.pessoas where id = p_pessoa_id and hubspot_id is not null
  )
  select coalesce(array_agg(identificador) filter (where canal = 'email'), '{}'),
         coalesce(array_agg(identificador) filter (where canal = 'whatsapp'), '{}'),
         coalesce(array_agg(identificador) filter (where canal = 'hubspot'), '{}'),
         coalesce(array_agg(case when canal = 'credenciamento' and identificador ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then identificador::uuid end)
                  filter (where canal = 'credenciamento' and identificador ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'), '{}'),
         coalesce(array_agg(case when canal = 'yazo' and identificador ~ '^[0-9]{1,18}$' then identificador::bigint end)
                  filter (where canal = 'yazo' and identificador ~ '^[0-9]{1,18}$'), '{}'),
         coalesce(array_agg(identificador) filter (where canal = 'eduzz'), '{}')
    into a_emails, a_tels, a_hubs, a_cred, a_yazo, a_edz
    from atual;

  create temp table if not exists d5_fontes_tmp (
    fonte text, email text, tel text, doc text, id_canal text, id_valor text, nome text,
    via_forte boolean, terceiro boolean, tel_ambiguo boolean) on commit drop;
  delete from d5_fontes_tmp;

  -- HubSpot
  insert into d5_fontes_tmp
  select 'hubspot', lower(btrim(c.email)), t.tel, null, 'hubspot', c.hubspot_id,
         nullif(btrim(concat_ws(' ', c.firstname, c.lastname)), ''),
         (c.mind_id = p_pessoa_id or c.hubspot_id = any(a_hubs) or lower(btrim(c.email)) = any(a_emails)),
         false,
         (t.tel is not null and (select count(*) > 1 from crm.contato_espelho d
            where public.telefone_normalizar(d.phone) = t.tel or public.telefone_normalizar(d.hs_whatsapp_phone_number) = t.tel))
    from crm.contato_espelho c
    join (select id from crm.contato_espelho where mind_id = p_pessoa_id
          union select id from crm.contato_espelho where hubspot_id = any(a_hubs)
          union select id from crm.contato_espelho where lower(btrim(email)) = any(a_emails)
          union select id from crm.contato_espelho where public.telefone_normalizar(phone) = any(a_tels)
          union select id from crm.contato_espelho where public.telefone_normalizar(hs_whatsapp_phone_number) = any(a_tels)) alvo on alvo.id = c.id
    cross join lateral (select coalesce(public.telefone_normalizar(c.hs_whatsapp_phone_number), public.telefone_normalizar(c.phone)) as tel) t;

  -- credenciamento (o CPF da linha e o do comprador: fora)
  insert into d5_fontes_tmp
  select 'credenciamento', lower(btrim(p.email)), p.telefone_norm, null, 'credenciamento', p.id::text, p.name,
         (p.mind_id = p_pessoa_id or lower(btrim(p.email)) = any(a_emails) or p.id = any(a_cred) or p.yazo_user_id = any(a_yazo)),
         (p.buyer_email is not null and lower(btrim(p.buyer_email)) <> lower(btrim(coalesce(p.email,'')))),
         (p.telefone_norm is not null and (select count(distinct lower(btrim(q.email))) > 1
            from credenciamento_summit_2026.participantes q where q.telefone_norm = p.telefone_norm))
    from credenciamento_summit_2026.participantes p
    join (select id from credenciamento_summit_2026.participantes where mind_id = p_pessoa_id
          union select id from credenciamento_summit_2026.participantes where lower(btrim(email)) = any(a_emails)
          union select id from credenciamento_summit_2026.participantes where telefone_norm = any(a_tels)
          union select id from credenciamento_summit_2026.participantes where id = any(a_cred)
          union select id from credenciamento_summit_2026.participantes where yazo_user_id = any(a_yazo)) alvo on alvo.id = p.id;

  -- Yazo
  insert into d5_fontes_tmp
  select 'yazo', lower(btrim(y.email)), t.tel, null, 'yazo', y.yazo_id::text, y.name,
         (y.mind_id = p_pessoa_id or lower(btrim(y.email)) = any(a_emails) or y.yazo_id = any(a_yazo)),
         (y.attributes->>'text_40' is not null and lower(btrim(y.attributes->>'text_40')) <> lower(btrim(coalesce(y.email,'')))),
         (t.tel is not null and (select count(distinct lower(btrim(z.email))) > 1 from credenciamento_summit_2026.yazo_espelho z
            where public.telefone_normalizar(case when jsonb_typeof(z.attributes->'cellphone') = 'object' then z.attributes->'cellphone'->>'value' else z.attributes->>'cellphone' end) = t.tel))
    from credenciamento_summit_2026.yazo_espelho y
    join (select yazo_id from credenciamento_summit_2026.yazo_espelho where mind_id = p_pessoa_id
          union select yazo_id from credenciamento_summit_2026.yazo_espelho where lower(btrim(email)) = any(a_emails)
          union select yazo_id from credenciamento_summit_2026.yazo_espelho where yazo_id = any(a_yazo)
          union select yazo_id from credenciamento_summit_2026.yazo_espelho
                 where public.telefone_normalizar(case when jsonb_typeof(attributes->'cellphone') = 'object' then attributes->'cellphone'->>'value' else attributes->>'cellphone' end) = any(a_tels)) alvo on alvo.yazo_id = y.yazo_id
    cross join lateral (select public.telefone_normalizar(case when jsonb_typeof(y.attributes->'cellphone') = 'object' then y.attributes->'cellphone'->>'value' else y.attributes->>'cellphone' end) as tel) t;

  -- Eduzz: ingressos (participante)
  insert into d5_fontes_tmp
  select 'eduzz', lower(btrim(i.email)), i.telefone_norm, i.cpf_cnpj, 'eduzz', i.cod_participante, i.participante,
         (i.mind_id = p_pessoa_id or lower(btrim(i.email)) = any(a_emails) or i.cod_participante = any(a_edz)),
         (i.email_comprador is not null and lower(btrim(i.email_comprador)) <> lower(btrim(coalesce(i.email,'')))),
         (i.telefone_norm is not null and (select count(distinct lower(btrim(j.email))) > 1 from eduzz.ingressos j where j.telefone_norm = i.telefone_norm))
    from eduzz.ingressos i
    join (select uuid from eduzz.ingressos where mind_id = p_pessoa_id
          union select uuid from eduzz.ingressos where lower(btrim(email)) = any(a_emails)
          union select uuid from eduzz.ingressos where telefone_norm = any(a_tels)
          union select uuid from eduzz.ingressos where cod_participante = any(a_edz)) alvo on alvo.uuid = i.uuid;

  -- Eduzz: vendas (comprador)
  insert into d5_fontes_tmp
  select 'eduzz_vendas', lower(btrim(v.cliente_email)), v.cliente_telefone_norm, v.cliente_documento, null, null, v.cliente_nome,
         (v.mind_id = p_pessoa_id or lower(btrim(v.cliente_email)) = any(a_emails)),
         false,
         (v.cliente_telefone_norm is not null and (select count(distinct lower(btrim(w.cliente_email))) > 1 from eduzz.vendas w where w.cliente_telefone_norm = v.cliente_telefone_norm))
    from eduzz.vendas v
    join (select linha_origem from eduzz.vendas where mind_id = p_pessoa_id
          union select linha_origem from eduzz.vendas where lower(btrim(cliente_email)) = any(a_emails)
          union select linha_origem from eduzz.vendas where cliente_telefone_norm = any(a_tels)) alvo on alvo.linha_origem = v.linha_origem;

  -- LearnWorlds (pelo comprador do checkout)
  insert into d5_fontes_tmp
  select 'learnworlds', lower(btrim(k.email)), null, null, 'learnworlds', a.destino_user_id, k.nome, true, false, false
    from learnworlds.acessos a
    join checkout.compradores k on k.id = a.comprador_id
   where a.destino_user_id is not null
     and (k.mind_id = p_pessoa_id or lower(btrim(coalesce(k.email,''))) = any(a_emails));

  -- a regra (D5.2): nome compativel sempre; por telefone so quando nada contradiz
  with ok as (
    select * from d5_fontes_tmp f
     where public.mind_nomes_compativeis(v_nome_pessoa, f.nome)
       and (f.via_forte
            or (not f.terceiro and not f.tel_ambiguo
                and (f.email is null or f.email = ''
                     or f.email = any(a_emails)
                     or cardinality(a_emails) = 0)))
  )
  select
    (select array_agg(distinct email) from ok where email is not null and email <> ''),
    (select array_agg(distinct tel) from ok where tel is not null and tel <> '' and not terceiro),
    (select array_agg(distinct id_valor) from ok where id_canal = 'hubspot' and id_valor is not null),
    (select array_agg(distinct doc) from ok where doc is not null and doc <> '' and not terceiro),
    (select array_agg(distinct id_valor) from ok where id_canal = 'yazo' and id_valor is not null),
    (select array_agg(distinct id_valor) from ok where id_canal = 'credenciamento' and id_valor is not null),
    (select array_agg(distinct id_valor) from ok where id_canal = 'eduzz' and id_valor is not null and id_valor <> ''),
    (select array_agg(distinct id_valor) from ok where id_canal = 'learnworlds' and id_valor is not null),
    (select nome from ok where nome is not null and btrim(nome) <> ''
      order by case fonte when 'hubspot' then 1 when 'credenciamento' then 2 when 'yazo' then 3 when 'eduzz' then 4 else 5 end limit 1),
    (select count(*) from ok),
    (select count(*) from d5_fontes_tmp) - (select count(*) from ok)
  into v_emails, v_tels, v_hubs, v_docs, v_yazo, v_cred, v_edz, v_lw, v_nome, v_usadas, v_ignoradas;

  v_ids := jsonb_strip_nulls(jsonb_build_object(
    'emails', to_jsonb(coalesce(v_emails, '{}')),
    'telefones', to_jsonb(coalesce(v_tels, '{}')),
    'hubspot_ids', to_jsonb(coalesce(v_hubs, '{}')),
    'yazo_ids', to_jsonb(coalesce(v_yazo, '{}')),
    'documento', v_docs[1],
    'credenciamento_id', v_cred[1],
    'eduzz_participante', v_edz[1],
    'learnworlds_user_id', v_lw[1]));

  v_r := public.mind_identidade_resolver(v_ids, v_nome, 'enriquecimento', p_pessoa_id);

  update pessoas.pessoas p
     set email = coalesce(p.email, (select i.identificador from engagement.identidades i where i.mind_id = p.id and i.canal = 'email'
                                    and not exists (select 1 from pessoas.pessoas q where lower(q.email) = i.identificador) order by i.criado_em limit 1)),
         whatsapp = coalesce(p.whatsapp, (select i.identificador from engagement.identidades i where i.mind_id = p.id and i.canal = 'whatsapp'
                                    and not exists (select 1 from pessoas.pessoas q where q.whatsapp = i.identificador) order by i.criado_em limit 1)),
         hubspot_id = coalesce(p.hubspot_id, (select i.identificador from engagement.identidades i where i.mind_id = p.id and i.canal = 'hubspot'
                                    and not exists (select 1 from pessoas.pessoas q where q.hubspot_id = i.identificador) order by i.criado_em limit 1)),
         enriquecida_em = now()
   where p.id = p_pessoa_id;

  select count(*) into v_depois from engagement.identidades where mind_id = p_pessoa_id;

  return jsonb_build_object('ok', true, 'pessoa_id', p_pessoa_id,
    'identidades_antes', v_antes, 'identidades_depois', v_depois,
    'novas', coalesce(v_r->'identidades', '[]'::jsonb),
    'conflito', v_r->'conflito',
    'linhas_usadas', v_usadas, 'linhas_ignoradas_pela_regra', v_ignoradas,
    'fontes', jsonb_build_object('hubspot', coalesce(array_length(v_hubs,1),0), 'credenciamento', coalesce(array_length(v_cred,1),0),
                                 'yazo', coalesce(array_length(v_yazo,1),0), 'eduzz', coalesce(array_length(v_edz,1),0), 'learnworlds', coalesce(array_length(v_lw,1),0)));
end $function$;


-- public.mind_pessoa_fundir(p_sobrevive uuid, p_absorvida uuid, p_motivo text) | mudou: sim | 2 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_pessoa_fundir(p_sobrevive uuid, p_absorvida uuid, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
declare
  fk record; v_sql text; v_movidas int; v_descartadas int; v_total_movidas int := 0; v_total_descartadas int := 0;
  v_detalhe jsonb := '[]'::jsonb; rid record; v_abs pessoas.pessoas%rowtype; v_sob pessoas.pessoas%rowtype;
begin
  if current_setting('mind.fusao_autorizada', true) is distinct from p_absorvida::text then
    raise exception using errcode = '42501', message = 'fusao_exige_decisao: use mind_fusao_decidir';
  end if;
  if p_sobrevive is null or p_absorvida is null or p_sobrevive = p_absorvida then
    raise exception using errcode = '22023', message = 'par_invalido';
  end if;
  select * into v_sob from pessoas.pessoas where id = p_sobrevive for update;
  select * into v_abs from pessoas.pessoas where id = p_absorvida for update;
  if v_sob.id is null or v_abs.id is null then raise exception using errcode = '22023', message = 'pessoa_inexistente'; end if;
  if v_sob.fundida_em is not null then raise exception using errcode = '22023', message = 'sobrevivente_ja_fundida'; end if;
  if v_abs.fundida_em is not null then return jsonb_build_object('ok', true, 'motivo', 'ja_fundida', 'em', v_abs.fundida_em); end if;

  update pessoas.pessoas set email = null, whatsapp = null, hubspot_id = null where id = p_absorvida;

  for fk in
    select con.conrelid::regclass as tab, a.attname as col
      from pg_constraint con
      join pg_attribute a on a.attrelid = con.conrelid and a.attnum = any(con.conkey)
     where con.contype = 'f' and con.confrelid = 'pessoas.pessoas'::regclass
       and con.conrelid <> 'pessoas.pessoas'::regclass
     order by 1, 2
  loop
    v_descartadas := 0;
    begin
      execute format('update %s set %I = $1 where %I = $2', fk.tab, fk.col, fk.col) using p_sobrevive, p_absorvida;
      get diagnostics v_movidas = row_count;
    exception when unique_violation then
      v_movidas := 0;
      for rid in execute format('select ctid as t from %s where %I = $1', fk.tab, fk.col) using p_absorvida loop
        begin
          execute format('update %s set %I = $1 where ctid = $2', fk.tab, fk.col) using p_sobrevive, rid.t;
          v_movidas := v_movidas + 1;
        exception when unique_violation then
          execute format('delete from %s where ctid = $1', fk.tab) using rid.t;
          v_descartadas := v_descartadas + 1;
        end;
      end loop;
    end;
    if v_movidas > 0 or v_descartadas > 0 then
      v_detalhe := v_detalhe || jsonb_build_array(jsonb_build_object('tabela', fk.tab::text, 'coluna', fk.col, 'movidas', v_movidas, 'descartadas', v_descartadas));
    end if;
    v_total_movidas := v_total_movidas + v_movidas;
    v_total_descartadas := v_total_descartadas + v_descartadas;
  end loop;

  update pessoas.pessoas s
     set primeiro_nome = coalesce(s.primeiro_nome, v_abs.primeiro_nome),
         sobrenome     = coalesce(s.sobrenome, v_abs.sobrenome),
         empresa       = coalesce(s.empresa, v_abs.empresa),
         cargo         = coalesce(s.cargo, v_abs.cargo),
         email         = coalesce(s.email, case when not exists (select 1 from pessoas.pessoas q where lower(q.email) = lower(v_abs.email)) then v_abs.email end),
         whatsapp      = coalesce(s.whatsapp, case when not exists (select 1 from pessoas.pessoas q where q.whatsapp = v_abs.whatsapp) then v_abs.whatsapp end),
         hubspot_id    = coalesce(s.hubspot_id, case when not exists (select 1 from pessoas.pessoas q where q.hubspot_id = v_abs.hubspot_id) then v_abs.hubspot_id end),
         atualizado_em = now()
   where s.id = p_sobrevive;

  update pessoas.pessoas set fundida_em = p_sobrevive, fundida_quando = now(), atualizado_em = now() where id = p_absorvida;

  update engagement.identidade_fusoes f
     set status = 'fundido', resolvido_em = now(),
         decisao = coalesce(f.decisao, '{}'::jsonb) || jsonb_build_object('fundida_por_par', true)
   where f.status = 'pendente' and f.participante_origem is not null
     and least(f.mind_id, f.participante_origem) = least(p_sobrevive, p_absorvida)
     and greatest(f.mind_id, f.participante_origem) = greatest(p_sobrevive, p_absorvida);

  -- o CHECK de mind_admin_audit so aceita criar/atualizar/publicar/arquivar/reindexar/login:
  -- a fusao e um 'atualizar' da pessoa, com o rotulo dizendo o que foi
  insert into public.mind_admin_audit (actor_user_id, action, resource, record_id, record_label, before_data, after_data, request_id)
  values (auth.uid(), 'atualizar', 'pessoa', p_absorvida::text,
          'fundir: ' || coalesce(p_motivo, 'fusao D5'),
          jsonb_build_object('absorvida', to_jsonb(v_abs)),
          jsonb_build_object('operacao', 'fundir', 'sobrevive', p_sobrevive, 'linhas_movidas', v_total_movidas, 'linhas_descartadas', v_total_descartadas, 'detalhe', v_detalhe),
          gen_random_uuid());

  return jsonb_build_object('ok', true, 'sobrevive', p_sobrevive, 'absorvida', p_absorvida,
                            'linhas_movidas', v_total_movidas, 'linhas_descartadas', v_total_descartadas, 'detalhe', v_detalhe);
end $function$;


-- public.mind_identidade_criar_faltantes(p_fonte regclass, p_lote integer, p_simular boolean) | mudou: sim | 18 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_identidade_criar_faltantes(p_fonte regclass, p_lote integer DEFAULT 2000, p_simular boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
declare
  v_sch text; v_tab text; v_q text; v_n int; v_antes int; v_depois int; v_restantes int;
  v_ligadas int; v_criadas int; v_sem int; v_resumo jsonb; v_motivos jsonb;
begin
  if exists (select 1 from pessoas.pessoas where enriquecida_em is null and fundida_em is null) then
    raise exception using errcode = 'P0001', message = 'fase_a_incompleta: rode 11_enriquecer_aplicar.sql ate restantes_nesta_rodada = 0 antes de criar pessoas';
  end if;
  select n.nspname, c.relname into v_sch, v_tab from pg_class c join pg_namespace n on n.oid = c.relnamespace where c.oid = p_fonte;
  v_q := format('%I.%I', v_sch, v_tab);
  if not exists (select 1 from pg_trigger t where t.tgrelid = p_fonte and t.tgname = 'zz_d5_pessoa_antes_de_escrever' and t.tgenabled <> 'D') then
    raise exception using errcode = 'P0001', message = 'fonte sem o trigger D5 ligado: ' || v_q || ' — use mind_pessoa_ligar_tabela primeiro';
  end if;

  select count(*) into v_antes from pessoas.pessoas;
  execute format('update %s set mind_id_resolvido_em = now() where ctid in (select ctid from %s where mind_id is null and (mind_id_resolvido_em is null or mind_id_criterio like %L) limit %s)',
                 v_q, v_q, 'aguardando_fase_a%', p_lote);
  get diagnostics v_n = row_count;
  select count(*) into v_depois from pessoas.pessoas;
  execute format('select count(*) filter (where mind_id is not null and mind_id_criterio not like %L),
                         count(*) filter (where mind_id_criterio like %L),
                         count(*) filter (where mind_id is null),
                         coalesce(jsonb_object_agg(m, n) filter (where m is not null), %L::jsonb)
                    from (select mind_id, mind_id_criterio, case when mind_id is null then split_part(mind_id_criterio, '' ('', 1) end m,
                                 count(*) over (partition by case when mind_id is null then split_part(mind_id_criterio, '' ('', 1) end) n
                            from %s where mind_id_resolvido_em = now()) s',
                 'criada:%', 'criada:%', '{}', v_q)
    into v_ligadas, v_criadas, v_sem, v_motivos;
  execute format('select count(*) from %s where mind_id is null and (mind_id_resolvido_em is null or mind_id_criterio like %L)', v_q, 'aguardando_fase_a%') into v_restantes;

  v_resumo := jsonb_build_object('fase', 'C_criar', 'fonte', v_q, 'simulacao', p_simular,
    'linhas_processadas', v_n, 'ligadas_a_pessoa_existente', v_ligadas, 'pessoas_criadas', v_criadas,
    'pessoas_criadas_conferencia', v_depois - v_antes, 'sem_pessoa', v_sem, 'motivos_sem_pessoa', v_motivos,
    'restantes_nesta_fonte', v_restantes);
  if p_simular then
    raise exception using errcode = 'P0001', message = 'SIMULACAO — nada gravado. ' || v_resumo::text;
  end if;
  return v_resumo;
end $function$;


-- public.mind_avaliacao_do_dia_estado(p_auth_user_id uuid, p_event_slug text, p_dia date) | mudou: sim | 3 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_avaliacao_do_dia_estado(p_auth_user_id uuid, p_event_slug text DEFAULT 'mind-summit-2026'::text, p_dia date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_ativo boolean;
  v_evento summit_2026.events%rowtype;
  v_dia date;
  v_participante_id uuid;
  v_resposta engagement.avaliacao_do_dia%rowtype;
  v_atividades jsonb;
  v_sugerida text;
begin
  select coalesce((c.valor->>'ativo')::boolean, false) into v_ativo
  from concierge.config c where c.chave = 'avaliacao_do_dia';
  v_ativo := coalesce(v_ativo, false);

  select i.mind_id into v_participante_id
  from engagement.identidades i
  where i.canal = 'auth_user' and i.identificador = p_auth_user_id::text
  order by i.criado_em desc limit 1;

  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;

  v_dia := coalesce(p_dia, (now() at time zone v_evento.fuso)::date);
  if not (v_dia = any (v_evento.dias)) then
    return jsonb_build_object(
      'ativo', false,
      'motivo', 'fora_do_evento',
      'identificado', v_participante_id is not null,
      'evento', jsonb_build_object('slug', v_evento.slug, 'nome', v_evento.nome,
                                   'fuso', v_evento.fuso, 'dias', to_jsonb(v_evento.dias)),
      'dia', v_dia,
      'formularioVersao', 1,
      'enviado', false,
      'atividades', '[]'::jsonb
    );
  end if;

  if v_participante_id is not null then
    select * into v_resposta from engagement.avaliacao_do_dia a
    where a.mind_id = v_participante_id and a.event_id = v_evento.id and a.dia = v_dia;

    select case lower(r.ticket_category)
             when 'mind' then 'mind' when 'vip' then 'vip' when 'prime' then 'prime'
           end into v_sugerida
    from summit_2026.registrations r
    where r.mind_id = v_participante_id and r.event_id = v_evento.id and r.status = 'ativa'
    order by r.criado_em desc limit 1;
  end if;

  select coalesce(jsonb_agg(x order by x->>'inicio', x->>'titulo'), '[]'::jsonb)
    into v_atividades
  from (
    select jsonb_build_object(
      'id', s.id,
      'titulo', s.titulo,
      'inicio', to_char(s.inicio at time zone v_evento.fuso, 'HH24:MI'),
      'fim', case when s.fim is null then null
                  else to_char(s.fim at time zone v_evento.fuso, 'HH24:MI') end,
      'espaco', l.nome,
      'tipo', s.tipo,
      'ingressos', to_jsonb(s.ingressos),
      'operacional', s.tipo in ('credenciamento', 'intervalo', 'almoco'),
      'palestrantes', coalesce((
        select jsonb_agg(pe.nome order by pe.nome)
        from summit_2026.session_speakers ss
        join ecossistema.palestrantes_especialistas pe on pe.id = ss.speaker_id
        where ss.sessao_id = s.id
      ), '[]'::jsonb)
    ) as x
    from summit_2026.sessions s
    left join summit_2026.locations l on l.id = s.espaco_id
    where s.event_id = v_evento.id and s.dia = v_dia
  ) grade;

  return jsonb_build_object(
    'ativo', v_ativo,
    'identificado', v_participante_id is not null,
    'evento', jsonb_build_object('slug', v_evento.slug, 'nome', v_evento.nome,
                                 'fuso', v_evento.fuso, 'dias', to_jsonb(v_evento.dias)),
    'dia', v_dia,
    'formularioVersao', 1,
    'enviado', v_resposta.id is not null,
    'enviadoEm', v_resposta.enviado_em,
    'experienciaSugerida', v_sugerida,
    'atividades', v_atividades
  );
end;
$function$;


-- bloco 9
-- public.mind_avaliacao_do_dia_registrar(p_auth_user_id uuid, p_event_slug text, p_dia date, p_payload jsonb) | mudou: sim | 3 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_avaliacao_do_dia_registrar(p_auth_user_id uuid, p_event_slug text, p_dia date, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_ativo boolean;
  v_evento summit_2026.events%rowtype;
  v_participante_id uuid;
  v_existente engagement.avaliacao_do_dia%rowtype;
  v_id uuid;
  v_experiencia text;
  v_profissao text;
  v_expectativas text;
  v_nota_rel smallint;
  v_nota_prog smallint;
  v_mais_gostou text;
  v_melhorar text;
  v_comentario text;
  v_atividades jsonb;
  v_iguais boolean;
  v_invalidas int;
begin
  select coalesce((c.valor->>'ativo')::boolean, false) into v_ativo
  from concierge.config c where c.chave = 'avaliacao_do_dia';
  if coalesce(v_ativo, false) is false then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:pesquisa_desligada';
  end if;

  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;
  if p_dia is null or not (p_dia = any (v_evento.dias)) then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:dia_fora_do_evento';
  end if;

  select i.mind_id into v_participante_id
  from engagement.identidades i
  where i.canal = 'auth_user' and i.identificador = p_auth_user_id::text
  order by i.criado_em desc limit 1;
  if v_participante_id is null then
    raise exception using errcode = '28000', message = 'avaliacao_sem_identidade';
  end if;

  v_experiencia  := lower(btrim(coalesce(p_payload->>'experiencia', '')));
  v_profissao    := btrim(coalesce(p_payload->>'profissao', ''));
  v_expectativas := btrim(coalesce(p_payload->>'expectativas', ''));
  v_mais_gostou  := nullif(btrim(coalesce(p_payload->>'maisGostou', '')), '');
  v_melhorar     := nullif(btrim(coalesce(p_payload->>'melhorar', '')), '');
  v_comentario   := nullif(btrim(coalesce(p_payload->>'comentario', '')), '');

  if v_experiencia not in ('mind', 'vip', 'prime') then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:experiencia';
  end if;
  if char_length(v_profissao) < 1 or char_length(v_profissao) > 120 then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:profissao';
  end if;
  if char_length(v_expectativas) < 1 or char_length(v_expectativas) > 1000 then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:expectativas';
  end if;
  if coalesce(char_length(v_mais_gostou), 0) > 1000
     or coalesce(char_length(v_melhorar), 0) > 1000
     or coalesce(char_length(v_comentario), 0) > 1000 then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:texto_longo';
  end if;

  if jsonb_typeof(p_payload->'notaRelevancia') <> 'number'
     or jsonb_typeof(p_payload->'notaProgramacao') <> 'number' then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:nota_obrigatoria';
  end if;
  v_nota_rel  := (p_payload->>'notaRelevancia')::numeric;
  v_nota_prog := (p_payload->>'notaProgramacao')::numeric;
  if v_nota_rel not between 0 and 5 or v_nota_prog not between 0 and 5
     or (p_payload->>'notaRelevancia')::numeric <> v_nota_rel
     or (p_payload->>'notaProgramacao')::numeric <> v_nota_prog then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:nota_fora_da_faixa';
  end if;

  v_atividades := coalesce(p_payload->'atividades', '[]'::jsonb);
  if jsonb_typeof(v_atividades) <> 'array' then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:atividades';
  end if;

  select count(*) into v_invalidas
  from jsonb_array_elements(v_atividades) a
  where jsonb_typeof(a->'nota') <> 'number'
     or (a->>'nota')::numeric not between 0 and 5
     or (a->>'nota')::numeric <> floor((a->>'nota')::numeric)
     or not exists (
       select 1 from summit_2026.sessions s
       where s.id = nullif(a->>'sessaoId', '')::uuid
         and s.event_id = v_evento.id and s.dia = p_dia
         and s.tipo is distinct from 'credenciamento'
         and s.tipo is distinct from 'intervalo'
         and s.tipo is distinct from 'almoco'
     );
  if v_invalidas > 0 then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:sessao_invalida';
  end if;

  if (select count(*) from jsonb_array_elements(v_atividades) a)
     <> (select count(distinct a->>'sessaoId') from jsonb_array_elements(v_atividades) a) then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:sessao_repetida';
  end if;

  perform pg_advisory_xact_lock(
    hashtext('avaliacao_do_dia'),
    hashtext(v_participante_id::text || v_evento.id::text || p_dia::text)
  );

  select * into v_existente from engagement.avaliacao_do_dia a
  where a.mind_id = v_participante_id and a.event_id = v_evento.id and a.dia = p_dia;

  if found then
    v_iguais :=
      v_existente.experiencia = v_experiencia
      and v_existente.profissao = v_profissao
      and v_existente.expectativas = v_expectativas
      and v_existente.nota_relevancia = v_nota_rel
      and v_existente.nota_programacao = v_nota_prog
      and v_existente.mais_gostou is not distinct from v_mais_gostou
      and v_existente.melhorar is not distinct from v_melhorar
      and v_existente.comentario is not distinct from v_comentario
      and (
        select coalesce(jsonb_object_agg(at.sessao_id::text, at.nota), '{}'::jsonb)
        from engagement.avaliacao_do_dia_atividade at
        where at.avaliacao_id = v_existente.id
      ) = (
        select coalesce(jsonb_object_agg(novo.sid::text, novo.nota), '{}'::jsonb)
        from (
          select nullif(a->>'sessaoId', '')::uuid as sid, (a->>'nota')::smallint as nota
          from jsonb_array_elements(v_atividades) a
        ) novo
      );

    if v_iguais then
      return jsonb_build_object('id', v_existente.id, 'jaRegistrado', true,
                                'enviadoEm', v_existente.enviado_em, 'dia', v_existente.dia);
    end if;
    raise exception using errcode = '23505', message = 'avaliacao_ja_enviada';
  end if;

  insert into engagement.avaliacao_do_dia (
    mind_id, event_id, dia, formulario_versao, experiencia, profissao,
    expectativas, nota_relevancia, nota_programacao, mais_gostou, melhorar, comentario
  ) values (
    v_participante_id, v_evento.id, p_dia, 1, v_experiencia, v_profissao,
    v_expectativas, v_nota_rel, v_nota_prog, v_mais_gostou, v_melhorar, v_comentario
  ) returning id into v_id;

  insert into engagement.avaliacao_do_dia_atividade (avaliacao_id, sessao_id, nota)
  select v_id, nullif(a->>'sessaoId','')::uuid, (a->>'nota')::smallint
  from jsonb_array_elements(v_atividades) a
  on conflict (avaliacao_id, sessao_id) do nothing;

  return jsonb_build_object('id', v_id, 'jaRegistrado', false, 'dia', p_dia,
                            'enviadoEm', (select enviado_em from engagement.avaliacao_do_dia where id = v_id));
end;
$function$;


-- public.mind_avaliacao_do_dia_respostas(p_event_slug text, p_dia date, p_experiencia text, p_sessao_id uuid, p_pagina integer, p_por_pagina integer) | mudou: sim | 1 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_avaliacao_do_dia_respostas(p_event_slug text DEFAULT 'mind-summit-2026'::text, p_dia date DEFAULT NULL::date, p_experiencia text DEFAULT NULL::text, p_sessao_id uuid DEFAULT NULL::uuid, p_pagina integer DEFAULT 1, p_por_pagina integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_evento summit_2026.events%rowtype;
  v_exp text := nullif(lower(btrim(coalesce(p_experiencia, ''))), '');
  v_pagina int := greatest(1, coalesce(p_pagina, 1));
  v_por int := least(500, greatest(1, coalesce(p_por_pagina, 50)));
  v_total bigint;
  v_itens jsonb;
begin
  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;
  if v_exp is not null and v_exp not in ('mind', 'vip', 'prime') then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:experiencia';
  end if;

  select count(*) into v_total
  from engagement.avaliacao_do_dia a
  where a.event_id = v_evento.id
    and (p_dia is null or a.dia = p_dia)
    and (v_exp is null or a.experiencia = v_exp)
    and (p_sessao_id is null or exists (
      select 1 from engagement.avaliacao_do_dia_atividade at
      where at.avaliacao_id = a.id and at.sessao_id = p_sessao_id));

  select coalesce(jsonb_agg(x order by ordem), '[]'::jsonb) into v_itens
  from (
    select jsonb_build_object(
      'id', a.id,
      'dia', a.dia,
      'enviadoEm', a.enviado_em,
      'email', p.email,
      'nome', nullif(btrim(coalesce(p.primeiro_nome, '') || ' ' || coalesce(p.sobrenome, '')), ''),
      'experiencia', a.experiencia,
      'profissao', a.profissao,
      'expectativas', a.expectativas,
      'notaRelevancia', a.nota_relevancia,
      'notaProgramacao', a.nota_programacao,
      'maisGostou', a.mais_gostou,
      'melhorar', a.melhorar,
      'comentario', a.comentario,
      'atividadesAvaliadas', (
        select count(*) from engagement.avaliacao_do_dia_atividade at
        where at.avaliacao_id = a.id)
    ) as x,
    row_number() over (order by a.enviado_em desc, a.id) as ordem
    from engagement.avaliacao_do_dia a
    left join pessoas.pessoas p on p.id = a.mind_id
    where a.event_id = v_evento.id
      and (p_dia is null or a.dia = p_dia)
      and (v_exp is null or a.experiencia = v_exp)
      and (p_sessao_id is null or exists (
        select 1 from engagement.avaliacao_do_dia_atividade at
        where at.avaliacao_id = a.id and at.sessao_id = p_sessao_id))
    order by a.enviado_em desc, a.id
    offset (v_pagina - 1) * v_por
    limit v_por
  ) pagina;

  return jsonb_build_object('total', v_total, 'pagina', v_pagina,
                            'porPagina', v_por, 'itens', v_itens);
end;
$function$;


-- public.mind_identificador_declarado_registrar(p_pessoa_id uuid, p_canal text, p_valor text) | mudou: sim | 3 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_identificador_declarado_registrar(p_pessoa_id uuid, p_canal text, p_valor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_canal text := lower(btrim(coalesce(p_canal, '')));
  v_normalizado text;
  v_dono uuid;
  v_inseridos integer := 0;
begin
  if p_pessoa_id is null
     or not exists (select 1 from pessoas.pessoas p where p.id = p_pessoa_id) then
    return jsonb_build_object('ok', false, 'motivo', 'pessoa_invalida');
  end if;

  if coalesce((public.mind_identificador_validar(v_canal, p_valor)->>'valido')::boolean, false)
     is not true then
    return jsonb_build_object('ok', false, 'canal', v_canal, 'motivo', 'formato_invalido');
  end if;

  if v_canal = 'whatsapp' then
    v_normalizado := public.telefone_normalizar(p_valor);
  elsif v_canal = 'email' then
    v_normalizado := lower(btrim(p_valor));
  else
    return jsonb_build_object('ok', false, 'canal', v_canal, 'motivo', 'canal_invalido');
  end if;

  select i.mind_id into v_dono
  from engagement.identidades i
  where i.canal = v_canal and i.identificador = v_normalizado
  limit 1;

  if v_dono is not null and v_dono <> p_pessoa_id then
    perform public.mind_conflito_registrar(
      p_pessoa_id,
      'conflito_identidade',
      'identificador declarado aponta para outra pessoa; conversa ancorada permanece',
      v_dono,
      jsonb_build_object('canal', v_canal)
    );
    return jsonb_build_object('ok', false, 'canal', v_canal, 'motivo', 'conflito_identidade');
  end if;

  if v_dono is null then
    insert into engagement.identidades
      (mind_id, canal, identificador, verificado, confianca)
    values
      (p_pessoa_id, v_canal, v_normalizado, false, 'media')
    on conflict (canal, identificador) do nothing;
    get diagnostics v_inseridos = row_count;

    select i.mind_id into v_dono
    from engagement.identidades i
    where i.canal = v_canal and i.identificador = v_normalizado
    limit 1;

    if v_dono is distinct from p_pessoa_id then
      perform public.mind_conflito_registrar(
        p_pessoa_id,
        'conflito_identidade',
        'concorrencia ao registrar identificador declarado; conversa ancorada permanece',
        v_dono,
        jsonb_build_object('canal', v_canal)
      );
      return jsonb_build_object('ok', false, 'canal', v_canal, 'motivo', 'conflito_identidade');
    end if;
  end if;

  if v_canal = 'whatsapp' then
    update pessoas.pessoas p
       set whatsapp = v_normalizado, atualizado_em = now()
     where p.id = p_pessoa_id and p.whatsapp is null
       and not exists (
         select 1 from pessoas.pessoas q
         where q.id <> p.id and q.whatsapp = v_normalizado
       );
  elsif v_canal = 'email' then
    update pessoas.pessoas p
       set email = v_normalizado, atualizado_em = now()
     where p.id = p_pessoa_id and p.email is null
       and not exists (
         select 1 from pessoas.pessoas q
         where q.id <> p.id and lower(q.email) = v_normalizado
       );
  end if;

  return jsonb_build_object(
    'ok', true,
    'canal', v_canal,
    'status', case when v_inseridos = 1 then 'registrado' else 'conhecido' end,
    'verificado', false,
    'confianca', 'media'
  );
end
$function$;


-- public.mind_credenciamento_fatos(p_pessoa_id uuid) | mudou: não | 0 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_credenciamento_fatos(p_pessoa_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
with registros_ativos as (
  select
    nullif(btrim(v.name), '') as nome,
    nullif(lower(btrim(v.email)), '') as email,
    public.telefone_normalizar(coalesce(v.telefone_norm, v.cellphone)) as whatsapp,
    coalesce(nullif(btrim(v.ticket_name), ''), nullif(btrim(v.ticket_type), '')) as categoria,
    v.sincronizado_em
  from credenciamento_summit_2026.v_participantes v
  where v.pessoa_id = p_pessoa_id
    and lower(coalesce(v.status, '')) = 'ativo'
    and v.revogado_em is null
),
ingressos_ativos as (
  select r.*
  from registros_ativos r
  where r.categoria is not null
    and upper(r.categoria) <> 'SEM MAPA'
),
categorias as (
  select i.categoria, count(*)::integer as quantidade
  from ingressos_ativos i
  group by i.categoria
),
cadastro as (
  select jsonb_strip_nulls(jsonb_build_object(
    'nome', case
      when count(distinct lower(r.nome)) filter (where r.nome is not null) = 1
      then min(r.nome) filter (where r.nome is not null)
      else null
    end,
    'email', case
      when count(distinct r.email) filter (where r.email is not null) = 1
      then min(r.email) filter (where r.email is not null)
      else null
    end,
    'whatsapp', case
      when count(distinct r.whatsapp) filter (where r.whatsapp is not null) = 1
      then min(r.whatsapp) filter (where r.whatsapp is not null)
      else null
    end
  )) as j,
  max(r.sincronizado_em) as sincronizado_em
  from registros_ativos r
),
stats as (
  select
    count(*)::integer as ingressos_total,
    count(distinct i.categoria)::integer as categorias_total,
    min(i.categoria) as categoria_unica
  from ingressos_ativos i
)
select case
  when p_pessoa_id is null then
    jsonb_build_object('ok', false, 'motivo', 'sem_pessoa')
  else
    jsonb_build_object(
      'ok', true,
      'pessoa_id', p_pessoa_id,
      'evento_codigo', 'mind-summit-2026',
      'participante', (select j from cadastro),
      'tem_ingresso_ativo', (select ingressos_total > 0 from stats),
      'categoria_unica', (
        select case when categorias_total = 1 then categoria_unica else null end from stats
      ),
      'categorias', coalesce((
        select jsonb_agg(c.categoria order by c.categoria) from categorias c
      ), '[]'::jsonb),
      'ingressos', coalesce((
        select jsonb_agg(
          jsonb_build_object('categoria', c.categoria, 'quantidade', c.quantidade)
          order by c.categoria
        )
        from categorias c
      ), '[]'::jsonb),
      'meta', jsonb_build_object(
        'fonte', 'credenciamento_oficial',
        'sincronizado_em', (select sincronizado_em from cadastro),
        'dados_comprador_omitidos', true
      )
    )
end
$function$;


-- public.mindagent_chat_get_context(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text) | mudou: sim | 6 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mindagent_chat_get_context(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'summit', 'comum', 'mind', 'engagement', 'intelligence', 'concierge'
AS $function$
declare
  v_session engagement.agent_sessions%rowtype;
  v_conversation engagement.conversas%rowtype;
  v_history jsonb := '[]'::jsonb;
  v_interests jsonb := '[]'::jsonb;
  v_memories jsonb := '[]'::jsonb;
  v_profile jsonb := null;
  v_credenciamento jsonb := null;
  v_rota_ativa text := null;
begin
  select * into v_session from engagement.agent_sessions
  where id=p_session_id and auth_user_id=p_auth_user_id and token_hash=p_token_hash and expira_em>now();
  if not found then raise exception using errcode='28000', message='invalid_chat_session'; end if;

  select * into v_conversation from engagement.conversas
  where id=p_conversation_id and dispositivo_id=v_session.dispositivo_id and encerrada_em is null;
  if not found then raise exception using errcode='28000', message='invalid_chat_conversation'; end if;

  update engagement.agent_sessions set ultima_atividade=now() where id=v_session.id;
  update engagement.dispositivos set ultimo_acesso=now() where id=v_session.dispositivo_id;
  update engagement.conversas set ultima_atividade=now() where id=v_conversation.id;

  select coalesce(jsonb_agg(jsonb_build_object('role',case h.papel when 'lead' then 'user' else 'assistant' end,
                                               'content',h.conteudo) order by h.criado_em),'[]'::jsonb)
    into v_history
  from (select papel,conteudo,criado_em from engagement.mensagens
        where conversa_id=v_conversation.id and papel in ('lead','agente') and conteudo is not null
        order by criado_em desc limit 12) h;

  select coalesce(jsonb_agg(jsonb_build_object('key',i.chave,'label',i.rotulo,'confidence',i.confianca,
                                               'occurrences',i.ocorrencias) order by i.ultima_em desc),'[]'::jsonb)
    into v_interests
  from engagement.session_interests i where i.agent_session_id=v_session.id;

  if v_session.mind_id is not null then
    v_credenciamento := public.mind_credenciamento_fatos(v_session.mind_id);

    select jsonb_build_object('participant_id',p.id,'name',p.nome,'role',p.cargo,'company',p.empresa,
                              'language',p.idioma,'interests',coalesce(pc.temas_relevantes,'[]'::jsonb))
      into v_profile
    from engagement.v_pessoa p
    left join intelligence.participante_contexto pc on pc.mind_id=p.id
    where p.id=v_session.mind_id;

    select coalesce(jsonb_agg(jsonb_build_object('type',pm.tipo,'key',pm.chave,
      'value',coalesce(pm.valor->>'text',pm.valor->>'label'),'scope',pm.valor->>'scope','confidence',pm.confianca)
      order by pm.confianca desc nulls last,pm.atualizado_em desc nulls last),'[]'::jsonb)
      into v_memories
    from intelligence.participante_memoria pm
    where pm.mind_id=v_session.mind_id and pm.tipo='interesse' and pm.status='ativa'
      and (pm.valido_ate is null or pm.valido_ate>now())
      and coalesce(pm.valor->>'text',pm.valor->>'label') is not null;
  end if;

  if jsonb_typeof(v_conversation.variables)='object' then
    v_rota_ativa:=nullif(btrim(coalesce(v_conversation.variables->>'rota_ativa','')),'');
  end if;

  return jsonb_build_object('identity_verified',false,'identity_source',v_session.origem_identidade,
    'identity_confidence',v_session.confianca,'participant_profile',v_profile,
    'credenciamento',v_credenciamento,'history',v_history,
    'interests',v_interests,'memories',v_memories,'origem_codigo',v_conversation.origem_codigo,
    'rota_ativa',v_rota_ativa,'expires_at',v_session.expira_em);
end
$function$;


-- public.mind_avaliacao_do_evento_registrar(p_auth_user_id uuid, p_event_slug text, p_payload jsonb) | mudou: sim | 3 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_avaliacao_do_evento_registrar(p_auth_user_id uuid, p_event_slug text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_config jsonb; v_ativo boolean; v_abre date; v_fecha date; v_hoje date;
  v_evento summit_2026.events%rowtype; v_participante_id uuid;
  v_existente engagement.avaliacao_do_evento%rowtype; v_id uuid;
  v_experiencia text; v_profissao text; v_expectativas text;
  v_nota_rel smallint; v_nota_prog smallint;
  v_mais_gostou text; v_melhorar text; v_comentario text;
  v_atividades jsonb; v_invalidas int; v_iguais boolean;
begin
  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;

  select c.valor into v_config from concierge.config c where c.chave = 'avaliacao_do_evento';
  v_ativo := coalesce((v_config->>'ativo')::boolean, false);
  v_abre  := nullif(v_config->>'abre', '')::date;
  v_fecha := nullif(v_config->>'fecha', '')::date;
  v_hoje  := (now() at time zone v_evento.fuso)::date;

  if not v_ativo then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:pesquisa_desligada';
  end if;
  if v_abre is not null and v_hoje < v_abre then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:ainda_nao_abriu';
  end if;
  if v_fecha is not null and v_hoje > v_fecha then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:ja_fechou';
  end if;

  select i.mind_id into v_participante_id
  from engagement.identidades i
  where i.canal = 'auth_user' and i.identificador = p_auth_user_id::text
  order by i.criado_em desc limit 1;
  if v_participante_id is null then
    raise exception using errcode = '28000', message = 'avaliacao_sem_identidade';
  end if;

  v_experiencia  := lower(btrim(coalesce(p_payload->>'experiencia', '')));
  v_profissao    := btrim(coalesce(p_payload->>'profissao', ''));
  v_expectativas := btrim(coalesce(p_payload->>'expectativas', ''));
  v_mais_gostou  := nullif(btrim(coalesce(p_payload->>'maisGostou', '')), '');
  v_melhorar     := nullif(btrim(coalesce(p_payload->>'melhorar', '')), '');
  v_comentario   := nullif(btrim(coalesce(p_payload->>'comentario', '')), '');

  if v_experiencia not in ('mind', 'vip', 'prime') then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:experiencia';
  end if;
  if char_length(v_profissao) < 1 or char_length(v_profissao) > 120 then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:profissao';
  end if;
  if char_length(v_expectativas) < 1 or char_length(v_expectativas) > 1000 then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:expectativas';
  end if;
  if coalesce(char_length(v_mais_gostou), 0) > 1000
     or coalesce(char_length(v_melhorar), 0) > 1000
     or coalesce(char_length(v_comentario), 0) > 1000 then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:texto_longo';
  end if;

  if jsonb_typeof(p_payload->'notaRelevancia') <> 'number'
     or jsonb_typeof(p_payload->'notaProgramacao') <> 'number' then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:nota_obrigatoria';
  end if;
  v_nota_rel  := (p_payload->>'notaRelevancia')::numeric;
  v_nota_prog := (p_payload->>'notaProgramacao')::numeric;
  if v_nota_rel not between 0 and 5 or v_nota_prog not between 0 and 5
     or (p_payload->>'notaRelevancia')::numeric <> v_nota_rel
     or (p_payload->>'notaProgramacao')::numeric <> v_nota_prog then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:nota_fora_da_faixa';
  end if;

  v_atividades := coalesce(p_payload->'atividades', '[]'::jsonb);
  if jsonb_typeof(v_atividades) <> 'array' then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:atividades';
  end if;

  -- CADA SESSÃO ENVIADA PRECISA SER DESTE EVENTO. Diferente da pesquisa
  -- do dia, aqui NÃO se exige um dia: a grade é a dos dois. Bloco de
  -- operação continua fora — credenciamento e intervalo não se avalia.
  select count(*) into v_invalidas
  from jsonb_array_elements(v_atividades) a
  where jsonb_typeof(a->'nota') <> 'number'
     or (a->>'nota')::numeric not between 0 and 5
     or (a->>'nota')::numeric <> floor((a->>'nota')::numeric)
     or not exists (
       select 1 from summit_2026.sessions s
       where s.id = nullif(a->>'sessaoId', '')::uuid
         and s.event_id = v_evento.id
         and s.tipo is distinct from 'credenciamento'
         and s.tipo is distinct from 'intervalo'
         and s.tipo is distinct from 'almoco'
     );
  if v_invalidas > 0 then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:sessao_invalida';
  end if;

  if (select count(*) from jsonb_array_elements(v_atividades) a)
     <> (select count(distinct a->>'sessaoId') from jsonb_array_elements(v_atividades) a) then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:sessao_repetida';
  end if;

  perform pg_advisory_xact_lock(
    hashtext('avaliacao_do_evento'),
    hashtext(v_participante_id::text || v_evento.id::text)
  );

  select * into v_existente from engagement.avaliacao_do_evento a
  where a.mind_id = v_participante_id and a.event_id = v_evento.id;

  if found then
    v_iguais :=
      v_existente.experiencia = v_experiencia
      and v_existente.profissao = v_profissao
      and v_existente.expectativas = v_expectativas
      and v_existente.nota_relevancia = v_nota_rel
      and v_existente.nota_programacao = v_nota_prog
      and v_existente.mais_gostou is not distinct from v_mais_gostou
      and v_existente.melhorar is not distinct from v_melhorar
      and v_existente.comentario is not distinct from v_comentario
      and (
        select coalesce(jsonb_object_agg(at.sessao_id::text, at.nota), '{}'::jsonb)
        from engagement.avaliacao_do_evento_atividade at
        where at.avaliacao_id = v_existente.id
      ) = (
        select coalesce(jsonb_object_agg(novo.sid::text, novo.nota), '{}'::jsonb)
        from (
          select nullif(a->>'sessaoId', '')::uuid as sid, (a->>'nota')::smallint as nota
          from jsonb_array_elements(v_atividades) a
        ) novo
      );

    if v_iguais then
      return jsonb_build_object('id', v_existente.id, 'jaRegistrado', true,
                                'enviadoEm', v_existente.enviado_em);
    end if;
    raise exception using errcode = '23505', message = 'avaliacao_ja_enviada';
  end if;

  insert into engagement.avaliacao_do_evento (
    mind_id, event_id, formulario_versao, experiencia, profissao,
    expectativas, nota_relevancia, nota_programacao, mais_gostou, melhorar,
    comentario, origem
  ) values (
    v_participante_id, v_evento.id, 2, v_experiencia, v_profissao,
    v_expectativas, v_nota_rel, v_nota_prog, v_mais_gostou, v_melhorar,
    v_comentario, 'app'
  ) returning id into v_id;

  insert into engagement.avaliacao_do_evento_atividade (avaliacao_id, sessao_id, nota)
  select v_id, nullif(a->>'sessaoId','')::uuid, (a->>'nota')::smallint
  from jsonb_array_elements(v_atividades) a
  on conflict (avaliacao_id, sessao_id) do nothing;

  return jsonb_build_object('id', v_id, 'jaRegistrado', false,
    'enviadoEm', (select enviado_em from engagement.avaliacao_do_evento where id = v_id));
end;
$function$;


-- bloco 10
-- public.mind_avaliacao_do_evento_estado(p_auth_user_id uuid, p_event_slug text) | mudou: sim | 3 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_avaliacao_do_evento_estado(p_auth_user_id uuid, p_event_slug text DEFAULT 'mind-summit-2026'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_config jsonb; v_ativo boolean; v_abre date; v_fecha date; v_hoje date; v_motivo text;
  v_evento summit_2026.events%rowtype; v_participante_id uuid;
  v_resposta engagement.avaliacao_do_evento%rowtype; v_sugerida text; v_atividades jsonb;
begin
  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;

  select c.valor into v_config from concierge.config c where c.chave = 'avaliacao_do_evento';
  v_ativo := coalesce((v_config->>'ativo')::boolean, false);
  v_abre  := nullif(v_config->>'abre', '')::date;
  v_fecha := nullif(v_config->>'fecha', '')::date;
  v_hoje  := (now() at time zone v_evento.fuso)::date;

  v_motivo := case
    when not v_ativo then 'desligada'
    when v_abre is not null and v_hoje < v_abre then 'ainda_nao_abriu'
    when v_fecha is not null and v_hoje > v_fecha then 'ja_fechou'
    else null
  end;

  select i.mind_id into v_participante_id
  from engagement.identidades i
  where i.canal = 'auth_user' and i.identificador = p_auth_user_id::text
  order by i.criado_em desc limit 1;

  if v_participante_id is not null then
    select * into v_resposta from engagement.avaliacao_do_evento a
    where a.mind_id = v_participante_id and a.event_id = v_evento.id;

    select case lower(r.ticket_category)
             when 'mind' then 'mind' when 'vip' then 'vip' when 'prime' then 'prime'
           end into v_sugerida
    from summit_2026.registrations r
    where r.mind_id = v_participante_id and r.event_id = v_evento.id and r.status = 'ativa'
    order by r.criado_em desc limit 1;
  end if;

  -- A GRADE DOS DOIS DIAS, ordenada como o evento aconteceu. `dia` vem
  -- junto porque a tela agrupa por ele: "11:30" aparece duas vezes numa
  -- lista de dois dias e não quer dizer a mesma coisa.
  select coalesce(jsonb_agg(x order by x->>'dia', x->>'inicio', x->>'titulo'), '[]'::jsonb)
    into v_atividades
  from (
    select jsonb_build_object(
      'id', s.id,
      'titulo', s.titulo,
      'dia', s.dia,
      'inicio', to_char(s.inicio at time zone v_evento.fuso, 'HH24:MI'),
      'fim', case when s.fim is null then null
                  else to_char(s.fim at time zone v_evento.fuso, 'HH24:MI') end,
      'espaco', l.nome,
      'tipo', s.tipo,
      'ingressos', to_jsonb(s.ingressos),
      'operacional', s.tipo in ('credenciamento', 'intervalo', 'almoco'),
      'palestrantes', coalesce((
        select jsonb_agg(pe.nome order by pe.nome)
        from summit_2026.session_speakers ss
        join ecossistema.palestrantes_especialistas pe on pe.id = ss.speaker_id
        where ss.sessao_id = s.id
      ), '[]'::jsonb)
    ) as x
    from summit_2026.sessions s
    left join summit_2026.locations l on l.id = s.espaco_id
    where s.event_id = v_evento.id
  ) grade;

  return jsonb_build_object(
    'ativo', v_motivo is null,
    'motivo', v_motivo,
    'identificado', v_participante_id is not null,
    'evento', jsonb_build_object('slug', v_evento.slug, 'nome', v_evento.nome,
                                 'fuso', v_evento.fuso, 'dias', to_jsonb(v_evento.dias)),
    'janela', jsonb_build_object('abre', v_abre, 'fecha', v_fecha),
    'formularioVersao', 2,
    'enviado', v_resposta.id is not null,
    'enviadoEm', v_resposta.enviado_em,
    'experienciaSugerida', v_sugerida,
    'atividades', v_atividades
  );
end;
$function$;


-- public.mind_fusao_decidir(p_alvo text, p_decisao text, p_quem text) | mudou: não | 0 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_fusao_decidir(p_alvo text, p_decisao text, p_quem text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
declare
  v_role text; v_quem text; f record; v_r jsonb; v_ok int := 0; v_rej int := 0; v_erro int := 0; v_lista jsonb := '[]'::jsonb; v_id uuid;
begin
  if p_decisao not in ('aprovar','rejeitar') then
    raise exception using errcode = '22023', message = 'decisao_invalida: aprovar ou rejeitar';
  end if;
  if session_user <> 'postgres' then
    select role into v_role from public.mind_admin_users where user_id = auth.uid() and active;
    if v_role is null or v_role not in ('administrador','aprovador') then
      raise exception using errcode = '42501', message = 'admin_forbidden';
    end if;
    select display_name into v_quem from public.mind_admin_users where user_id = auth.uid();
  end if;
  v_quem := coalesce(p_quem, v_quem, session_user::text);

  begin v_id := p_alvo::uuid; exception when others then v_id := null; end;
  if v_id is null and p_alvo in ('telefone_compartilhado','nomes_divergentes','mesmo_email_nomes_diferentes') and p_decisao = 'aprovar' then
    raise exception using errcode = '22023', message = 'padrao_so_linha_a_linha: ' || p_alvo;
  end if;

  for f in
    select * from engagement.identidade_fusoes
     where status = 'pendente' and proposta is not null
       and ((v_id is not null and id = v_id)
         or (v_id is null and padrao = p_alvo and (p_decisao = 'rejeitar' or proposta->>'confianca' = 'alta')))
     order by criado_em
  loop
    if p_decisao = 'rejeitar' then
      update engagement.identidade_fusoes set status = 'descartado', resolvido_em = now(), resolvido_por = v_quem,
             decisao = jsonb_build_object('decisao', 'rejeitar', 'quem', v_quem, 'quando', now())
       where id = f.id;
      v_rej := v_rej + 1;
      continue;
    end if;
    begin
      perform set_config('mind.fusao_autorizada', (f.proposta->>'absorvida'), true);
      v_r := public.mind_pessoa_fundir((f.proposta->>'sobrevive')::uuid, (f.proposta->>'absorvida')::uuid,
                                        'decisao de ' || v_quem || ' sobre ' || coalesce(f.padrao,'?'));
      perform set_config('mind.fusao_autorizada', '', true);
      update engagement.identidade_fusoes set status = 'fundido', resolvido_em = now(), resolvido_por = v_quem,
             decisao = jsonb_build_object('decisao', 'aprovar', 'quem', v_quem, 'quando', now(), 'resultado', v_r)
       where id = f.id;
      v_ok := v_ok + 1;
    exception when others then
      perform set_config('mind.fusao_autorizada', '', true);
      v_erro := v_erro + 1;
      v_lista := v_lista || jsonb_build_array(jsonb_build_object('pendencia', f.id, 'erro', sqlerrm));
    end;
  end loop;

  return jsonb_build_object('alvo', p_alvo, 'decisao', p_decisao, 'quem', v_quem,
                            'fundidas', v_ok, 'rejeitadas', v_rej, 'erros', v_erro, 'detalhe_erros', v_lista,
                            'ficaram_para_linha_a_linha', (select count(*) from engagement.identidade_fusoes
                                                            where status = 'pendente' and v_id is null and padrao = p_alvo));
end $function$;


-- public.mind_identidade_enriquecer_todas(p_lote integer, p_simular boolean) | mudou: não | 0 referências de coluna renomeadas
CREATE OR REPLACE FUNCTION public.mind_identidade_enriquecer_todas(p_lote integer DEFAULT 1500, p_simular boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
declare
  r record; v_r jsonb; v_n int := 0; v_com_novas int := 0; v_conflitos int := 0;
  v_por_canal jsonb := '{}'::jsonb; v_x jsonb; v_restantes int; v_resumo jsonb;
  v_pessoas_antes int; v_pessoas_depois int;
begin
  select count(*) into v_pessoas_antes from pessoas.pessoas;
  for r in
    select id from pessoas.pessoas
     where enriquecida_em is null and fundida_em is null
     order by criado_em
     limit p_lote
  loop
    v_r := public.mind_pessoa_enriquecer(r.id);
    v_n := v_n + 1;
    if jsonb_array_length(coalesce(v_r->'novas','[]'::jsonb)) > 0 then v_com_novas := v_com_novas + 1; end if;
    if v_r->'conflito' is not null and jsonb_typeof(v_r->'conflito') <> 'null' then v_conflitos := v_conflitos + 1; end if;
    for v_x in select x from jsonb_array_elements(coalesce(v_r->'novas','[]'::jsonb)) x loop
      v_por_canal := jsonb_set(v_por_canal, array[v_x->>'canal'],
                       to_jsonb(coalesce((v_por_canal->>(v_x->>'canal'))::int, 0) + 1));
    end loop;
  end loop;
  select count(*) into v_restantes from pessoas.pessoas where enriquecida_em is null and fundida_em is null;
  select count(*) into v_pessoas_depois from pessoas.pessoas;

  v_resumo := jsonb_build_object(
    'fase', 'A_enriquecer', 'simulacao', p_simular,
    'pessoas_processadas', v_n, 'pessoas_com_identificador_novo', v_com_novas,
    'identificadores_novos_por_canal', v_por_canal,
    'pessoas_com_conflito', v_conflitos,
    'pessoas_criadas', v_pessoas_depois - v_pessoas_antes,   -- tem que ser 0
    'restantes_nesta_rodada', v_restantes,
    'propostas_pendentes_por_padrao', (select coalesce(jsonb_object_agg(padrao, n), '{}'::jsonb)
                                       from (select coalesce(padrao,'(sem padrao)') padrao, count(*) n from engagement.identidade_fusoes where status = 'pendente' group by 1) s));
  if p_simular then
    raise exception using errcode = 'P0001', message = 'SIMULACAO — nada gravado. ' || v_resumo::text;
  end if;
  return v_resumo;
end $function$;

-- ----------------------------------------------------------------------------
-- 4. A pessoa com todos os ids, numa linha — agora com mind_id na saída
-- ----------------------------------------------------------------------------
-- E a unica view cuja saida muda de nome: e a tabela de leitura da Adriana, nao
-- contrato de API. As views api.* e as demais seguem o rename por dentro e mantem
-- os nomes de saida antigos.
drop view if exists pessoas.v_pessoa_360;
create view pessoas.v_pessoa_360 as
select p.id as mind_id,
       p.primeiro_nome, p.sobrenome,
       p.email,
       x.outros_emails,
       p.whatsapp,
       x.outros_whatsapps,
       x.cpf, x.cnpjs,
       x.hubspot_ids, x.yazo_ids, x.credenciamento_ids, x.eduzz_codigos, x.learnworlds_user_id, x.auth_user_id,
       p.empresa, p.cargo, p.origem,
       x.canais,
       p.criado_em, p.atualizado_em, p.enriquecida_em,
       p.fundida_em, p.fundida_quando
  from pessoas.pessoas p
  left join lateral (
    select array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'email' and i.identificador <> coalesce(lower(p.email),'')) as outros_emails,
           array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'whatsapp' and i.identificador <> coalesce(p.whatsapp,'')) as outros_whatsapps,
           (array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'cpf'))[1] as cpf,
           array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'cnpj') as cnpjs,
           array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'hubspot') as hubspot_ids,
           array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'yazo') as yazo_ids,
           array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'credenciamento') as credenciamento_ids,
           array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'eduzz') as eduzz_codigos,
           (array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'learnworlds'))[1] as learnworlds_user_id,
           (array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'auth_user'))[1] as auth_user_id,
           array_agg(distinct i.canal) as canais
      from engagement.identidades i
     where i.mind_id = p.id
  ) x on true;

comment on view pessoas.v_pessoa_360 is
  'A pessoa com todos os ids que a identificam, numa linha (D5): mind_id (o ID universal), nome, e-mail principal e outros, WhatsApp principal e outros, CPF, CNPJs, ids do HubSpot, da Yazo, do credenciamento, da Eduzz, do LearnWorlds e do login. Pivô de engagement.identidades; a casa continua normalizada. Uma pessoa fundida aparece com fundida_em preenchido.';

comment on column pessoas.pessoas.id is
  'O Mind ID: o identificador universal e persistente da pessoa no sistema (D5/D6). Toda tabela que fala de pessoa carrega este valor na coluna mind_id.';

-- ----------------------------------------------------------------------------
-- 5. Prova
-- ----------------------------------------------------------------------------
do $$
declare n int; v_resto text;
begin
  select count(*) into n from pg_attribute a
   where a.attname = 'mind_id' and not a.attisdropped
     and a.attrelid in (select conrelid from pg_constraint where contype = 'f' and confrelid = 'pessoas.pessoas'::regclass);
  if n < 50 then raise exception 'mind_id: esperava mind_id em pelo menos 50 tabelas com FK para pessoas, achei %', n; end if;
  -- nenhuma FK para pessoas.pessoas continua com o nome antigo (colunas de papel ficam de fora)
  select string_agg(con.conrelid::regclass::text || '.' || a.attname, ', ') into v_resto
    from pg_constraint con join pg_attribute a on a.attrelid = con.conrelid and a.attnum = any(con.conkey)
   where con.contype = 'f' and con.confrelid = 'pessoas.pessoas'::regclass
     and a.attname in ('pessoa_id','participante_id','participant_id','person_id');
  if v_resto is not null then raise exception 'mind_id: ainda com nome antigo: %', v_resto; end if;
  if not exists (select 1 from pg_views where schemaname = 'pessoas' and viewname = 'v_pessoa_360') then
    raise exception 'mind_id: v_pessoa_360 ausente';
  end if;
end $$;
