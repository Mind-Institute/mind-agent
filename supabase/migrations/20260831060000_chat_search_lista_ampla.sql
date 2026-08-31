-- mindagent_chat_search: pergunta ampla de palestrantes/programação volta a listar.
--
-- O BUG, medido em produção: quem escreve COM acento recebia zero.
--
--   "quais palestrantes estarao no summit?"   → 8 palestrantes
--   "quais palestrantes estarão no Summit?"   → 0
--   "quais palestrantes vão estar no evento?" → 0
--   "speakers"                                → 0
--
-- A causa é o guarda `n_foco = 0` das duas listagens. O "andaime da pergunta"
-- (palavras que estruturam em vez de dizer o assunto) foi escrito nas formas SEM
-- acento — `estara`, `vao` — mas o stemmer devolve `estarã` e `vã` quando a pessoa
-- escreve certo. Sobrando um lexema, `n_foco` vira 1, a listagem é desligada e a
-- resposta sai vazia. O agente então diz com honestidade que não sabe, porque de
-- fato não recebeu nada.
--
-- Acrescentar `estarã` e `vã` à lista consertaria esta frase e quebraria na próxima
-- conjugação. A correção é estrutural: quando a pergunta PEDE a lista e a busca por
-- assunto não achou nada, entrega a lista.
--
-- O filtro estreito continua intacto — é o ponto: "palestrantes sobre liderança"
-- devolve 1, não 8, porque ali a busca por assunto ACHOU e não há queda.
--
-- Patch sobre a definição viva, com âncoras assertadas: se o texto base tiver
-- divergido, a migration falha em vez de aplicar em cima de outra coisa.
do $$
declare d text; d0 text;
begin
  select pg_get_functiondef(p.oid) into d0
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'mindagent_chat_search';

  if d0 is null then raise exception 'public.mindagent_chat_search nao existe'; end if;
  d := d0;

  if position('speaker_ranked as (' in d) = 0
     or position('or (p.listar_pessoas and p.n_foco = 0)' in d) = 0
     or position('session_ranked as (' in d) = 0
     or position('or ((p.listar or dp.dias is not null or fx.modo is not null) and p.n_foco = 0)' in d) = 0
  then
    raise exception 'ancora nao encontrada: a definicao base de mindagent_chat_search divergiu';
  end if;

  -- quantas sessões o assunto da pergunta realmente encontrou
  d := replace(d, 'session_ranked as (',
E'sessao_foco_n as (\n  select count(*) as n\n  from sessao_base sb\n  cross join params p\n  where (p.q_foco is not null and ts_rank_cd(sb.tsv, p.q_foco) >= p.piso)\n     or exists (select 1 from summit_2026.session_speakers ss\n                join pessoa_nomeada pn on pn.id = ss.speaker_id\n                where ss.sessao_id = sb.id)\n),\nsession_ranked as (');

  -- quantas pessoas o assunto da pergunta realmente encontrou
  d := replace(d, 'speaker_ranked as (',
E'speaker_foco_n as (\n  select count(*) as n\n  from pessoa_evento pe\n  cross join params p\n  left join pessoa_nomeada pn on pn.id = pe.id\n  where pn.id is not null\n     or (p.q_foco is not null and ts_rank_cd(pe.tsv, p.q_foco) >= p.piso)\n),\nspeaker_ranked as (');

  -- pediu a lista de pessoas e o assunto nao achou ninguem -> lista
  d := replace(d, 'or (p.listar_pessoas and p.n_foco = 0)',
                  'or (p.listar_pessoas and (p.n_foco = 0 or (select n from speaker_foco_n) = 0))');

  -- pediu a agenda e o assunto nao achou sessao -> lista
  d := replace(d, 'or ((p.listar or dp.dias is not null or fx.modo is not null) and p.n_foco = 0)',
                  'or ((p.listar or dp.dias is not null or fx.modo is not null) and (p.n_foco = 0 or (select n from sessao_foco_n) = 0))');

  execute d;
end $$;
