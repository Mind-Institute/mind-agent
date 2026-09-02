-- PASSO 5 — MEMÓRIA RÁPIDA. O writer volta a ser o que o nome diz: interesse da SESSÃO.
--
-- O que sai, e por quê:
--   * rejeitar payload > 5 e teto de 12 por sessão: tetos artificiais. Um turno pode
--     revelar seis interesses legítimos, e recusar o payload inteiro por causa do sexto
--     descartava também os cinco válidos.
--   * promoção para `intelligence.participante_memoria` e escrita em
--     `participante_contexto`: memória durável agora tem uma dona só — o pós-conversa
--     (`analise_concierge` + `analise_projetar_memoria`). Duas políticas concorrentes de
--     memória permanente é como elas divergem.
--   * `confirmed`: existia só para decidir a promoção acima. Sem promoção, não tem função.
--
-- O que ENTRA, e é a correção mais importante:
--   o runtime afirmava em comentário que este writer aplicava política de sensibilidade
--   fail-closed. Ele não lia o campo. Agora lê — e é fail-closed de verdade: só `none`
--   grava. Ausente, desconhecido ou qualquer outro valor é descartado, e o descarte de um
--   item não derruba os demais.
--
--   Não consulto `intelligence.memoria_bloqueios` aqui de propósito: a regra é "só none
--   passa", que é mais restritiva que qualquer lista e não quebra se a tabela ganhar
--   chave nova. Lista de bloqueio falha aberto para o valor que ela ainda não conhece.

create or replace function public.mindagent_chat_save_interests(
  p_auth_user_id uuid, p_session_id uuid, p_token_hash text,
  p_interests jsonb, p_evidence_message_id uuid default null::uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','engagement','intelligence','summit','comum','concierge'
as $function$
declare
  v_item jsonb;
  v_saved int := 0;
  v_blocked int := 0;
  v_skipped int := 0;
  v_key text; v_label text; v_confidence numeric; v_sensitivity text;
begin
  perform 1
  from engagement.agent_sessions s
  where s.id = p_session_id
    and s.auth_user_id = p_auth_user_id
    and s.token_hash = p_token_hash
    and s.expira_em > now();

  if not found then
    raise exception using errcode = '28000', message = 'invalid_chat_session';
  end if;

  if p_interests is null or jsonb_typeof(p_interests) <> 'array' then
    return jsonb_build_object('saved', 0, 'blocked', 0, 'skipped', 0, 'promoted', 0);
  end if;

  for v_item in select value from jsonb_array_elements(p_interests)
  loop
    v_key   := left(lower(regexp_replace(coalesce(v_item->>'key', ''), '[^a-z0-9_\-]+', '_', 'g')), 80);
    v_label := left(btrim(coalesce(v_item->>'label', '')), 120);
    v_confidence := least(1, greatest(0, coalesce((v_item->>'confidence')::numeric, 0.7)));
    v_sensitivity := lower(btrim(coalesce(v_item->>'sensitivity', '')));

    -- FAIL-CLOSED. Só `none` passa; o resto é descartado sem derrubar o payload.
    if v_sensitivity is distinct from 'none' then
      v_blocked := v_blocked + 1;
      continue;
    end if;

    if length(v_key) < 2 or length(v_label) < 2 or v_confidence < 0.70 then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    insert into engagement.session_interests (
      agent_session_id, chave, rotulo, confianca,
      evidencia_message_id, ocorrencias, primeira_em, ultima_em
    ) values (
      p_session_id, v_key, v_label, v_confidence,
      p_evidence_message_id, 1, now(), now()
    )
    on conflict (agent_session_id, chave) do update
      set rotulo = excluded.rotulo,
          confianca = greatest(engagement.session_interests.confianca, excluded.confianca),
          evidencia_message_id = coalesce(excluded.evidencia_message_id,
                                          engagement.session_interests.evidencia_message_id),
          ocorrencias = engagement.session_interests.ocorrencias + 1,
          ultima_em = now();

    v_saved := v_saved + 1;
  end loop;

  -- `promoted` fica em 0 para não quebrar quem lê o contrato antigo. Este writer não
  -- promove mais nada: memória durável é do pós-conversa.
  return jsonb_build_object('saved', v_saved, 'blocked', v_blocked,
                            'skipped', v_skipped, 'promoted', 0);
exception
  when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid_interest_confidence';
end;
$function$;

do $g$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='mindagent_chat_save_interests';

  if v_def ~ 'too_many_interests' then
    raise exception 'o teto de 5 do payload continua na funcao'; end if;
  if v_def ~ 'v_interest_count < 12' or v_def ~ 'v_interest_count < 8' then
    raise exception 'os tetos de 12/8 continuam na funcao'; end if;
  if v_def ~ 'participante_memoria' or v_def ~ 'participante_contexto' then
    raise exception 'o writer rapido ainda escreve memoria duravel'; end if;
  if v_def !~ 'sensitivity' then
    raise exception 'o writer continua sem ler sensitivity'; end if;
  if v_def !~ 'session_interests' then
    raise exception 'o writer perdeu a casa dele'; end if;
end $g$;
