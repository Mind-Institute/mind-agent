-- PROGRAMAÇÃO DO MIND SUMMIT 2026 NO PAINEL: A TABELA COMO ESTÁ NO BANCO, SÓ LEITURA.
--
-- Pedido da Adriana (26/09/2026): "em Summit quero um menu Mind Summit 2026, e dentro dele um menu com a
-- tabela de programação do Mind Summit 2026 conforme está no backend". A casa é summit_2026.sessions
-- (81 sessões); nada muda nela. A porta antiga do painel para a programação
-- (mind_admin_read_resource('sessions')) está quebrada — lê o schema summit, que virou summit_2026 — e
-- não é tocada aqui.
--
--   · mind_admin_read_summit_2026_sessoes(p_id)   todas (p_id nulo) ou uma
--
-- Cada linha é a sessão com as colunas e os nomes do banco (to_jsonb), mais duas leituras para gente:
-- `espaco` (summit_2026.locations.nome) e `palestrantes` (nomes em ecossistema.palestrantes_especialistas,
-- pela summit_2026.session_speakers). Na ordem do banco: dia, início, título. Só service_role executa;
-- quem chama é a Edge Function mindagent-summit, depois de validar a sessão e o papel.
--
-- Contrato: tests/summit_programacao_contract.sql (termina em SUMMIT_PROGRAMACAO_OK).

create or replace function public.mind_admin_read_summit_2026_sessoes(p_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $fn$
  select coalesce(jsonb_agg(x.linha order by x.dia, x.inicio, x.titulo), '[]'::jsonb)
  from (
    select s.dia, s.inicio, s.titulo,
      to_jsonb(s) || jsonb_build_object(
        'espaco', l.nome,
        'palestrantes', coalesce((
          select jsonb_agg(pe.nome order by pe.nome)
            from summit_2026.session_speakers ss
            join ecossistema.palestrantes_especialistas pe on pe.id = ss.speaker_id
           where ss.sessao_id = s.id
        ), '[]'::jsonb)
      ) as linha
    from summit_2026.sessions s
    left join summit_2026.locations l on l.id = s.espaco_id
    where p_id is null or s.id = p_id
  ) x
$fn$;

comment on function public.mind_admin_read_summit_2026_sessoes(uuid) is
  'Programação do Mind Summit 2026 para o painel: summit_2026.sessions como está no banco, mais o nome do espaço e dos palestrantes. Só leitura. Só service_role executa; quem chama é a Edge Function mindagent-summit.';

revoke all on function public.mind_admin_read_summit_2026_sessoes(uuid) from public, anon, authenticated;
grant execute on function public.mind_admin_read_summit_2026_sessoes(uuid) to service_role;
