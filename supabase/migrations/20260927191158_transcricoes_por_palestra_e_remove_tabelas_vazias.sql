-- Adriana (27/09/2026), duas decisões numa migration só:
--
-- A. Transcrições das palestras do Summit 2026 vão para a base de conhecimento
--    do Summit (summit_2026.knowledge_documents), uma linha por palestra. A
--    coluna nova sessao_id liga o documento à palestra (summit_2026.sessions.id);
--    os palestrantes vêm pela sessão (summit_2026.session_speakers) e não são
--    repetidos no documento. Documentos que não são de palestra ficam com a
--    coluna vazia.
--
-- B. Saem quatro tabelas criadas para a jornada/avaliação dentro do evento e
--    que nunca receberam uma linha (0 linhas em 27/09):
--      engagement.sessao_feedback, engagement.jornada_eventos,
--      engagement.jornada_sessao, intelligence.recomendacoes.
--    Junto saem o que só existia para elas: três visões do concierge sem uso
--    (v_funil_valor, v_sessoes_avaliadas, v_aderencia_por_area) e a função do
--    gatilho da jornada (concierge.aplicar_evento_jornada).
--    Três funções deixam de ler essas tabelas; o resto delas fica como estava:
--      mind.esquecer_participante — tira os três UPDATEs de anonimização;
--      api.my_data                — tira a chave 'insights' (vinha de sessao_feedback);
--      concierge.resumo_do_dia    — tira planejadas, assistidas, perdidas,
--        avaliacoes e sugestoes_ja_feitas; amanha_disponiveis perde o filtro
--        "já assistidas" e passa a ler summit_2026.sessions, porque
--        summit.sessions não existe mais e o banco recusa recriar a função
--        apontando para ela.

-- ---------- B. visões que só existiam sobre as tabelas que saem ----------
drop view concierge.v_funil_valor;
drop view concierge.v_sessoes_avaliadas;
drop view concierge.v_aderencia_por_area;

-- ---------- B. funções que deixam de ler as tabelas que saem ----------
create or replace function mind.esquecer_participante(p_participante uuid)
 returns void
 language plpgsql
 security definer
 set search_path to 'summit', 'comum', 'engagement', 'intelligence', 'mind', 'concierge', 'public'
as $function$
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

  update evento_feedback  set mind_id = v_anonimo where mind_id = p_participante;
  update nps_summit       set mind_id = v_anonimo where mind_id = p_participante;

  delete from participantes where id = p_participante;
end $function$;

create or replace function api.my_data(p_token text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'engagement', 'intelligence', 'summit', 'comum', 'concierge', 'mind', 'crm', 'public'
as $function$
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
    'consentimentos', (select coalesce(jsonb_agg(jsonb_build_object(
                          'finalidade', k.finalidade, 'concedido', k.concedido,
                          'em', k.criado_em)), '[]')
                  from crm.consents k, eu where k.mind_id = eu.id));
$function$;

create or replace function concierge.resumo_do_dia(p_participante uuid, p_dia date)
 returns jsonb
 language sql
 stable
 set search_path to 'engagement', 'intelligence', 'summit', 'comum', 'concierge', 'mind', 'public'
as $function$
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

    'problemas_operacionais', (
      select coalesce(jsonb_agg(jsonb_build_object('categoria', e.categoria,
                                                   'severidade', e.severidade)), '[]')
      from evento_feedback e
      where e.mind_id = p_participante and e.criado_em::date = p_dia),

    'amanha_disponiveis', (
      select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'titulo', s.titulo,
                                                   'inicio', s.inicio, 'espaco', s.espaco_id,
                                                   'topicos', s.topicos_aprendizado)), '[]')
      from summit_2026.sessions s
      where s.dia > p_dia)
  );
$function$;

-- ---------- B. as quatro tabelas vazias (o gatilho t_jornada sai junto) ----------
drop table engagement.jornada_eventos;
drop table engagement.jornada_sessao;
drop table engagement.sessao_feedback;
drop table intelligence.recomendacoes;

drop function concierge.aplicar_evento_jornada();

-- ---------- A. transcrição ligada à palestra ----------
alter table summit_2026.knowledge_documents
  add column sessao_id uuid
  constraint knowledge_documents_sessao_fk references summit_2026.sessions(id) on delete restrict;

create index knowledge_documents_sessao_idx
  on summit_2026.knowledge_documents (sessao_id)
  where sessao_id is not null;

comment on column summit_2026.knowledge_documents.sessao_id is
  'Palestra do Summit de que este documento trata (ex.: a transcrição da palestra), pelo id de summit_2026.sessions. Vazio para documentos que não são de uma palestra. Os palestrantes vêm pela sessão (summit_2026.session_speakers) e não são repetidos aqui. Adriana, 27/09/2026.';
