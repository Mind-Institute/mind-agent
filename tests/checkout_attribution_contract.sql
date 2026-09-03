-- Rodar contra mind-agent. Tudo acontece em transação e termina em ROLLBACK.
begin;

do $contract$
declare
  v_conversa uuid;
  v_evento uuid := 'aaaaaaaa-aaaa-5aaa-8aaa-aaaaaaaaaaaa';
  v_linha integer;
  v_saida jsonb;
  v_count integer;
begin
  select id into v_conversa
  from engagement.conversas
  order by ultima_atividade desc
  limit 1;

  select linha_origem into v_linha
  from eduzz.vendas
  order by linha_origem desc
  limit 1;

  if v_conversa is null or v_linha is null then
    raise exception 'fixture real ausente';
  end if;

  v_saida := public.mind_checkout_envio_registrar(
    v_evento,
    v_conversa,
    'https://sun.eduzz.com/CONTRATO',
    'app',
    'mindagent-chat',
    'summit_b2c',
    'checkout_prime_preco_regular',
    'contract-test'
  );

  if v_saida->>'event_id' <> v_evento::text then
    raise exception 'evento nao retornou o id esperado: %', v_saida;
  end if;

  -- Retry da mesma tentativa não duplica.
  perform public.mind_checkout_envio_registrar(
    v_evento,
    v_conversa,
    'https://sun.eduzz.com/CONTRATO',
    'app',
    'mindagent-chat',
    'summit_b2c',
    'checkout_prime_preco_regular',
    'contract-test'
  );

  select count(*) into v_count
  from engagement.agente_eventos
  where id = v_evento;
  if v_count <> 1 then
    raise exception 'retry criou % eventos', v_count;
  end if;

  update eduzz.vendas
  set utm_content = 'checkout_prime_preco_regular__ae_aaaaaaaaaaaa5aaa8aaaaaaaaaaaaaaa'
  where linha_origem = v_linha;

  select count(*) into v_count
  from intelligence.v_conversoes_agente
  where event_id = v_evento
    and conversation_id = v_conversa
    and channel = 'app'
    and agent_id = 'mindagent-chat'
    and checkout_reason = 'checkout_prime_preco_regular';
  if v_count <> 1 then
    raise exception 'view nao fechou venda para evento e conversa';
  end if;

  if not exists (
    select 1 from agentes.canal_competencia
    where canal = 'mindagent-web' and rota = 'summit_b2c' and ativo
  ) then
    raise exception 'summit_b2c nao esta disponivel no app';
  end if;
end
$contract$;

rollback;
