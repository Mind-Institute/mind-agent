-- O número do lead (vindo do webhook do Treble) passa a ser guardado em
-- claro além do hash: é dado de atendimento/venda (follow-up, handoff,
-- futuro vínculo com HubSpot/Eduzz). Descadastro apaga a conversa.
alter table treble.conversations add column if not exists telefone text;

create or replace function public.treble_agent_start(
  p_session_external_id text,
  p_contact jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path = public, treble
as $$
declare
  conv treble.conversations;
  hist jsonb;
begin
  if p_session_external_id is null or length(p_session_external_id) < 3 then
    raise exception 'session_external_id inválido';
  end if;

  insert into treble.conversations (session_external_id, nome_contato, telefone, telefone_hash)
  values (
    p_session_external_id,
    nullif(trim(coalesce(p_contact->>'nome','')),''),
    nullif(trim(coalesce(p_contact->>'telefone','')),''),
    nullif(trim(coalesce(p_contact->>'telefone_hash','')),'')
  )
  on conflict (session_external_id) do update
    set ultima_atividade = now(),
        nome_contato = coalesce(treble.conversations.nome_contato, excluded.nome_contato),
        telefone = coalesce(treble.conversations.telefone, excluded.telefone),
        telefone_hash = coalesce(treble.conversations.telefone_hash, excluded.telefone_hash)
  returning * into conv;

  select coalesce(jsonb_agg(jsonb_build_object('papel', m.papel, 'conteudo', m.conteudo)
                            order by m.criado_em), '[]'::jsonb)
    into hist
  from (select papel, conteudo, criado_em
          from treble.messages
         where conversation_id = conv.id
         order by criado_em desc limit 12) m;

  return jsonb_build_object(
    'conversation_id', conv.id,
    'audience', conv.audience,
    'stage', conv.stage,
    'variables', conv.variables,
    'nome_contato', conv.nome_contato,
    'historico', hist
  );
end;
$$;
revoke all on function public.treble_agent_start(text, jsonb) from public, anon, authenticated;
