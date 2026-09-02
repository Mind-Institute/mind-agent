-- ============================================================
-- 06 · A porta pública: o app lê avisos e momento
-- ============================================================
-- Projeto: mind-agent (ymnmotgglsrxmjmonwjz)
-- Depende de: 01 (avisos) e 04 (config).
--
-- POR QUE ESTA FUNÇÃO EXISTE, E NÃO UMA CHAVE NO BOOTSTRAP
-- O caminho natural seria acrescentar `avisos` e `home` ao
-- `api.mindagent_bootstrap`. Só que aquela função é da programação do
-- evento, está quebrada desde 24/08 por uma renomeação de schema, e
-- mexer nela é mexer em coisa que não é nossa.
--
-- Esta é uma porta NOVA, para conteúdo NOVO. Não duplica nada do
-- bootstrap: programação, palestrantes e temas continuam vindo de lá.
-- Aqui só existe o que a Home V3 criou.
--
-- Quando o bootstrap for consertado, dá para fundir as duas — ou não,
-- porque separar o que o painel publica do que a grade informa também é
-- uma escolha defensável.
--
-- SEM SEGREDO: é `stable security definer` com execução para `anon`,
-- como o bootstrap. Devolve só o que já é público para quem tem o link
-- do evento — nenhum dado de participante passa por aqui.
--
-- Reversível: `drop function api.mindagent_home_publico();`

create or replace function api.mindagent_home_publico(p_event_slug text default 'mind-summit-2026')
 returns jsonb
 language sql
 stable security definer
 set search_path to 'pg_catalog', 'summit_2026', 'concierge'
as $function$
with ev as (
  select e.* from summit_2026.events e where e.slug = p_event_slug and e.ativo limit 1
),
cfg as (
  select coalesce(c.valor, '{}'::jsonb) as v from concierge.config c where c.chave = 'home'
)
select jsonb_build_object(
  'geradoEm', now(),

  -- AVISOS EM CIRCULAÇÃO, mais recente em cima.
  --   no-ar     → na rua agora, independente do relógio (disparo imediato)
  --   agendado  → entra sozinho quando `disparo_em` chega
  --   rascunho, encerrado → não saem
  -- A regra é aplicada na leitura: não depende de pg_cron nem de rotina
  -- que possa não rodar às 9h do dia 16.
  'avisos', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', coalesce(a.chave, a.id::text),
      'icone', a.icone,
      'em', to_char(a.disparo_em at time zone coalesce((select fuso from ev), 'America/Sao_Paulo'),
                    'YYYY-MM-DD"T"HH24:MI'),
      'situacao', a.situacao,
      'titulo', a.titulo,
      'resumo', a.subtitulo,
      'mensagem', a.descricao,
      'verNoApp', a.ver_no_app,
      'botaoVerNoApp', a.botao_ver_no_app
    ) order by a.disparo_em desc nulls last)
    from concierge.avisos a
    where (a.situacao = 'no-ar' or (a.situacao = 'agendado' and a.disparo_em <= now()))
      and (a.event_id is null or a.event_id = (select id from ev))
  ), '[]'::jsonb),

  -- QUAL DAS QUATRO COMPOSIÇÕES está no ar. Em `programado`, vale a
  -- última troca cujo horário já passou — mesma ideia dos avisos.
  'home', coalesce((
    select jsonb_build_object(
      'momento', case
        when v->>'modo' = 'programado' then coalesce((
          select troca->>'momento'
          from jsonb_array_elements(coalesce(v->'trocas', '[]'::jsonb)) troca
          where coalesce((troca->>'arquivada')::boolean, false) is false
            and (replace(troca->>'quando', 'T', ' '))::timestamp
                at time zone coalesce((select fuso from ev), 'America/Sao_Paulo') <= now()
          order by troca->>'quando' desc
          limit 1
        ), v->>'momento', 'antes')
        else coalesce(v->>'momento', 'antes')
      end,
      'modo', coalesce(v->>'modo', 'manual')
    )
    from cfg
  ), jsonb_build_object('momento', 'antes', 'modo', 'manual'))
);
$function$;

comment on function api.mindagent_home_publico(text) is
  'Avisos em circulação e composição da home, para o app do participante. Porta nova; não toca no bootstrap.';

-- Mesma exposição do bootstrap: leitura pública, sem sessão.
grant execute on function api.mindagent_home_publico(text) to anon, authenticated, service_role;

-- ------------------------------------------------------------
-- A ponte em `public` — sem ela, nada disto é alcançável
-- ------------------------------------------------------------
-- O PostgREST só expõe `public`. Uma função em `api` existe, funciona no
-- SQL Editor e é INVISÍVEL para `/rest/v1/rpc/...` — que é por onde a
-- Edge Function chama. Por isso `api.mindagent_bootstrap` sempre teve um
-- irmão em `public` fazendo só o repasse; este aqui é o mesmo padrão.
--
-- Sem `security definer`: quem carrega a permissão é a função de `api`,
-- e repetir aqui só ampliaria superfície à toa.

create or replace function public.mindagent_home_publico(p_event_slug text default 'mind-summit-2026')
 returns jsonb
 language sql
 stable
 set search_path to 'pg_catalog', 'api'
as $function$
  select api.mindagent_home_publico(p_event_slug);
$function$;

comment on function public.mindagent_home_publico(text) is
  'Repasse para api.mindagent_home_publico. Existe porque o PostgREST só enxerga public.';

grant execute on function public.mindagent_home_publico(text) to anon, authenticated, service_role;
