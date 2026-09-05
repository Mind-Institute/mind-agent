-- Treble: a competencia comercial escolhida vira estado da conversa.
--
-- A casa ja existe: engagement.conversas.variables.rota_ativa. Esta migration
-- apenas conecta o adapter do Treble ao mesmo contrato usado pelo App:
--   * mind_conversa_estado devolve a rota ao runtime;
--   * mind_turno_registrar valida a rota no Capability Gate e a persiste na
--     mesma transacao que grava a resposta.
-- Prompt, Intelligence, preco, checkout e fluxo visual do Treble nao mudam.

create or replace function public.mind_conversa_estado(p_conversa_id uuid)
returns jsonb
language sql
stable security definer
set search_path to 'public', 'engagement', 'pessoas'
as $function$
  select jsonb_build_object(
    'historico', coalesce((
      select jsonb_agg(jsonb_build_object('papel', m.papel, 'conteudo', m.conteudo)
                       order by m.criado_em)
      from (select papel, conteudo, criado_em from engagement.mensagens
             where conversa_id = p_conversa_id order by criado_em desc limit 12) m), '[]'::jsonb),
    'turnos_do_agente', (select count(*) from engagement.mensagens
                          where conversa_id = p_conversa_id and papel = 'agente'),
    'credenciamento', (select public.mind_credenciamento_fatos(c.participante_id)
                         from engagement.conversas c where c.id = p_conversa_id),
    'perfil', (select jsonb_strip_nulls(jsonb_build_object(
                 'pessoa_id', p.id, 'primeiro_nome', p.primeiro_nome, 'sobrenome', p.sobrenome,
                 'email', p.email, 'whatsapp', p.whatsapp, 'empresa', p.empresa, 'cargo', p.cargo))
               from engagement.conversas c join pessoas.pessoas p on p.id = c.participante_id
              where c.id = p_conversa_id),
    'rota_ativa', (select case when jsonb_typeof(c.variables) = 'object'
                          then nullif(btrim(coalesce(c.variables->>'rota_ativa', '')), '')
                        end
                    from engagement.conversas c where c.id = p_conversa_id));
$function$;

create or replace function public.mind_turno_registrar(
  p_conversa_id uuid,
  p_resposta text,
  p_estado jsonb default '{}'::jsonb,
  p_meta jsonb default null::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'engagement'
as $function$
declare
  v_msg jsonb;
  v_conv engagement.conversas%rowtype;
  v_rota text;
  v_gate jsonb;
begin
  select * into v_conv
  from engagement.conversas
  where id = p_conversa_id;

  if not found then
    raise exception using errcode = '22023', message = 'conversa_inexistente';
  end if;

  v_rota := nullif(btrim(coalesce(p_estado->>'rota_ativa', '')), '');
  if v_rota is not null then
    v_gate := public.mind_rota_capacidade(v_rota, v_conv.canal);
    if not (coalesce(v_gate->>'ok', 'false')::boolean
            and coalesce(v_gate->>'pode_executar', 'false')::boolean) then
      v_rota := null;
    end if;
  end if;

  v_msg := public.mind_mensagem_registrar(p_conversa_id, 'agente', p_resposta,
             p_meta->>'request_id', p_meta, 'agente');

  update engagement.conversas set
    audience  = coalesce(nullif(p_estado->>'audience',''), audience),
    stage     = coalesce(nullif(p_estado->>'stage',''), stage),
    variables = (case when jsonb_typeof(variables) = 'object'
                      then variables else '{}'::jsonb end)
                || jsonb_strip_nulls(jsonb_build_object(
      'intent',          nullif(p_estado->>'intent',''),
      'ticket_interest', nullif(p_estado->>'ticket_interest',''),
      'objection',       nullif(p_estado->>'objection',''),
      'needs_human',     (p_estado->>'needs_human')::boolean,
      'checkout_sent',   (coalesce((variables->>'checkout_sent')::boolean,false)
                          or coalesce((p_estado->>'checkout_sent')::boolean,false)),
      'desfecho',        nullif(p_estado->>'desfecho',''),
      'rota_ativa',      v_rota)),
    encerrada_em = case when nullif(p_estado->>'desfecho','') is not null then now() else encerrada_em end,
    ultima_atividade = now()
  where id = p_conversa_id;

  return v_msg;
end $function$;

do $checks$
declare
  d_estado text;
  d_writer text;
begin
  select pg_get_functiondef(p.oid) into d_estado
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'mind_conversa_estado';

  select pg_get_functiondef(p.oid) into d_writer
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'mind_turno_registrar';

  if d_estado !~ 'rota_ativa' then
    raise exception 'Treble read path nao devolve rota_ativa';
  end if;
  if d_writer !~ 'mind_rota_capacidade' or d_writer !~ 'rota_ativa' then
    raise exception 'Treble writer nao valida/persiste rota_ativa';
  end if;
  if d_writer !~ 'mind_mensagem_registrar' then
    raise exception 'Treble writer perdeu gravacao da mensagem';
  end if;
end $checks$;

