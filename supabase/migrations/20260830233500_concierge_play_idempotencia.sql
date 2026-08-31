-- ============================================================
-- Play — idempotência de TRANSPORTE na casa que já existe
-- ------------------------------------------------------------
-- O PROBLEMA REAL
--
--   `play-service.js` manda `client_action_id` com um contrato explícito:
--   "Rede repete; a pessoa não. A chave viaja para o runtime poder deduplicar
--   a MESMA tentativa." O `mindagent-chat` só logava esse valor.
--
--   Os writers da Lane E são idempotentes por CHAVE NATURAL — upsert por
--   (participante, sessão), UNIQUE por pessoa no NPS, (pessoa, tipo, valor,
--   contexto) no feedback tipado. A exceção é `mind_play_feedback_evento`
--   quando `p_mensagem_id` é nulo, que é exatamente como o modo ação o chama:
--   sem mensagem, cada chamada cria um relato novo — comportamento correto
--   para quem relata duas coisas diferentes, e errado para um retry de rede.
--
--   Faltava a camada de transporte. Ela não substitui a chave natural: cobre
--   o caso que nenhuma chave natural cobre.
--
-- A CASA JÁ EXISTIA
--
--   `concierge.ferramenta_chamadas` está em produção, vazia, com
--   `idempotency_key text` e o índice UNIQUE PARCIAL
--   `ferramenta_chamadas_idempotency_key_idx ... WHERE idempotency_key IS NOT NULL`.
--   Nenhuma função viva a usava. Nada de tabela, coluna, identidade ou
--   lifecycle novo: só as duas funções que faltavam para escrever nela.
--
-- POR QUE DUAS FUNÇÕES, E NÃO UMA
--
--   Reservar e concluir são dois momentos: o writer roda no runtime, ENTRE
--   eles. Reservar primeiro é o que fecha a corrida — o índice UNIQUE decide
--   quem executa, não o relógio. Checar-depois-escrever deixaria as duas
--   tentativas simultâneas passarem, que é o defeito que se está corrigindo.
--
-- POR QUE RPC EM `public`, E NÃO ACESSO DIRETO À TABELA
--
--   `concierge` não é schema exposto na API. O runtime fala RPC, como já fala
--   com todo o resto. SECURITY DEFINER com EXECUTE só para `service_role`,
--   igual às `mind_play_*`.
--
-- VOCABULÁRIO DE `status` — definido aqui porque a tabela não tem CHECK e
-- estava vazia, sem vocabulário anterior a respeitar:
--
--   em_andamento → reservada, writer ainda não respondeu
--   concluida    → writer respondeu {ok:true}
--   recusada     → writer respondeu {ok:false, motivo:...} (recusa é dado)
--   falhou       → a chamada em si falhou (erro de RPC, exception)
-- ============================================================


-- ============================================================
-- 1. mind_play_chamada_iniciar — reserva a tentativa
-- ------------------------------------------------------------
-- Sem chave, insere e devolve `nova`: o índice é parcial, então NULL nunca
-- colide, e o comportamento de quem não manda `client_action_id` fica igual
-- ao de hoje — executa.
--
-- Com chave, a reserva é o `insert ... on conflict do nothing`. Quem inseriu
-- executa; quem colidiu recebe o que a primeira tentativa já registrou.
--
-- A chave vem do NAVEGADOR. Por isso a colisão confere ferramenta e pessoa:
-- reaproveitar a chave de outra pessoa devolveria a saída dela.
-- ============================================================
create or replace function public.mind_play_chamada_iniciar(
  p_ferramenta      text,
  p_pessoa_id       uuid,
  p_idempotency_key text default null,
  p_entrada         jsonb default '{}'::jsonb,
  p_mensagem_id     uuid default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $fn$
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
    (ferramenta, participante_id, mensagem_id, entrada, status, idempotency_key)
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
     or v_antiga.participante_id is distinct from p_pessoa_id then
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
$fn$;

revoke all on function public.mind_play_chamada_iniciar(text, uuid, text, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.mind_play_chamada_iniciar(text, uuid, text, jsonb, uuid) to service_role;

comment on function public.mind_play_chamada_iniciar(text, uuid, text, jsonb, uuid) is
  'Play — reserva uma execução de ferramenta em concierge.ferramenta_chamadas usando client_action_id como idempotency_key (índice UNIQUE parcial já existente). Devolve estado=nova (pode executar), repetida (a mesma tentativa já terminou: status e saida gravados vêm junto), em_andamento (a primeira ainda não respondeu) ou recusa chave_conflitante quando a chave já pertence a outra ferramenta ou outra pessoa — a chave vem do navegador. Sem idempotency_key devolve sempre nova, preservando o comportamento de quem não manda a chave. Não substitui a idempotência por chave natural das mind_play_*: cobre o caso que ela não cobre, o retry de transporte em registrar_feedback_evento sem mensagem.';


-- ============================================================
-- 2. mind_play_chamada_concluir — fecha a tentativa
-- ------------------------------------------------------------
-- `saida` é o jsonb do writer, inclusive quando ele recusou: a recusa é dado
-- e precisa voltar igual no retry. Só fecha o que ainda está em andamento —
-- reexecutar não pode reescrever o desfecho de uma tentativa já registrada.
-- ============================================================
create or replace function public.mind_play_chamada_concluir(
  p_chamada_id  uuid,
  p_status      text,
  p_saida       jsonb default null,
  p_http_status integer default null,
  p_latencia_ms integer default null,
  p_erro        text default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_status text := nullif(btrim(coalesce(p_status, '')), '');
  v_id     uuid;
begin
  if p_chamada_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_chamada');
  end if;
  if v_status is null or v_status not in ('concluida', 'recusada', 'falhou') then
    return jsonb_build_object('ok', false, 'motivo', 'status_invalido');
  end if;

  update concierge.ferramenta_chamadas
     set status      = v_status,
         saida       = p_saida,
         http_status = p_http_status,
         latencia_ms = p_latencia_ms,
         erro        = left(nullif(btrim(coalesce(p_erro, '')), ''), 2000)
   where id = p_chamada_id
     and status = 'em_andamento'
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'chamada_nao_encontrada');
  end if;
  return jsonb_build_object('ok', true, 'chamada_id', v_id, 'status', v_status);
end;
$fn$;

revoke all on function public.mind_play_chamada_concluir(uuid, text, jsonb, integer, integer, text)
  from public, anon, authenticated;
grant execute on function public.mind_play_chamada_concluir(uuid, text, jsonb, integer, integer, text) to service_role;

comment on function public.mind_play_chamada_concluir(uuid, text, jsonb, integer, integer, text) is
  'Play — fecha uma execução reservada por mind_play_chamada_iniciar. status: concluida (writer devolveu ok:true), recusada (writer devolveu ok:false com motivo — recusa é dado e volta igual no retry) ou falhou (erro da própria chamada). Só atualiza linha em_andamento: o desfecho de uma tentativa já registrada não é reescrito.';
