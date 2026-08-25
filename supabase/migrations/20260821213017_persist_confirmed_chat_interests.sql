
create or replace function public.mindagent_chat_save_interests(
  p_auth_user_id uuid,
  p_session_id uuid,
  p_token_hash text,
  p_interests jsonb,
  p_evidence_message_id uuid default null::uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'concierge'
as $function$
declare
  v_item jsonb;
  v_count integer := 0;
  v_promoted integer := 0;
  v_key text;
  v_label text;
  v_confidence numeric;
  v_confirmed boolean;
  v_participant_id uuid;
  v_profile_item jsonb;
begin
  select s.participante_id
    into v_participant_id
  from concierge.agent_sessions s
  where s.id = p_session_id
    and s.auth_user_id = p_auth_user_id
    and s.token_hash = p_token_hash
    and s.expira_em > now();

  if not found then
    raise exception using errcode = '28000', message = 'invalid_chat_session';
  end if;

  if p_interests is null or jsonb_typeof(p_interests) <> 'array' then
    return jsonb_build_object('saved', 0, 'promoted', 0);
  end if;
  if jsonb_array_length(p_interests) > 5 then
    raise exception using errcode = '22023', message = 'too_many_interests';
  end if;

  for v_item in select value from jsonb_array_elements(p_interests)
  loop
    v_key := left(lower(regexp_replace(coalesce(v_item->>'key', ''), '[^a-z0-9_\-]+', '_', 'g')), 80);
    v_label := left(btrim(coalesce(v_item->>'label', '')), 120);
    v_confidence := least(1, greatest(0, coalesce((v_item->>'confidence')::numeric, 0.7)));
    v_confirmed := lower(coalesce(v_item->>'confirmed', 'false')) in ('true', '1', 'yes');

    if length(v_key) >= 2 and length(v_label) >= 2 and v_confidence >= 0.65 then
      insert into concierge.session_interests (
        agent_session_id, chave, rotulo, confianca,
        evidencia_message_id, ocorrencias, primeira_em, ultima_em
      ) values (
        p_session_id, v_key, v_label, v_confidence,
        p_evidence_message_id, 1, now(), now()
      )
      on conflict (agent_session_id, chave) do update
        set rotulo = excluded.rotulo,
            confianca = greatest(concierge.session_interests.confianca, excluded.confianca),
            evidencia_message_id = coalesce(excluded.evidencia_message_id, concierge.session_interests.evidencia_message_id),
            ocorrencias = concierge.session_interests.ocorrencias + 1,
            ultima_em = now();

      v_count := v_count + 1;

      if v_confirmed and v_participant_id is not null then
        v_profile_item := jsonb_build_object(
          'key', v_key,
          'label', v_label,
          'source', 'confirmado_pelo_usuario',
          'confirmed', true,
          'confidence', v_confidence
        );

        insert into concierge.participante_memoria (
          participante_id, tipo, chave, valor, confianca, origem,
          evidencia_message_id, status, importancia, criado_em, atualizado_em
        ) values (
          v_participant_id, 'interesse', v_key,
          jsonb_build_object('label', v_label, 'confirmed', true),
          v_confidence, 'confirmado_pelo_usuario',
          p_evidence_message_id, 'ativa', v_confidence, now(), now()
        )
        on conflict (participante_id, chave) where status = 'ativa' do update
          set tipo = 'interesse',
              valor = excluded.valor,
              confianca = greatest(concierge.participante_memoria.confianca, excluded.confianca),
              origem = 'confirmado_pelo_usuario',
              evidencia_message_id = coalesce(excluded.evidencia_message_id, concierge.participante_memoria.evidencia_message_id),
              importancia = greatest(coalesce(concierge.participante_memoria.importancia, 0), excluded.importancia),
              atualizado_em = now();

        insert into concierge.participante_contexto as pc (
          participante_id, temas_relevantes, versao, atualizado_em
        ) values (
          v_participant_id, jsonb_build_array(v_profile_item), 1, now()
        )
        on conflict (participante_id) do update
          set temas_relevantes =
            coalesce(
              (
                select jsonb_agg(existing_item)
                from jsonb_array_elements(
                  case
                    when jsonb_typeof(pc.temas_relevantes) = 'array' then pc.temas_relevantes
                    else '[]'::jsonb
                  end
                ) as existing(existing_item)
                where existing_item->>'key' <> v_key
              ),
              '[]'::jsonb
            ) || jsonb_build_array(v_profile_item),
            versao = pc.versao + 1,
            atualizado_em = now();

        v_promoted := v_promoted + 1;
      end if;
    end if;
  end loop;

  return jsonb_build_object('saved', v_count, 'promoted', v_promoted);
exception
  when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid_interest_confidence';
end;
$function$;

revoke execute on function public.mindagent_chat_save_interests(uuid, uuid, text, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.mindagent_chat_save_interests(uuid, uuid, text, jsonb, uuid)
  to service_role;

