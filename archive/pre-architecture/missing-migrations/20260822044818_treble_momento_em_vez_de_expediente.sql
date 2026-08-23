-- Correção (Adriana): expediente NÃO é regra dura. Vendedores trabalham
-- à noite e no fim de semana; o que decide o handoff é a NECESSIDADE, não
-- o relógio. Esta função vira só um sinal de contexto — o agente usa para
-- calibrar a expectativa que comunica, nunca para recusar transferência.
delete from treble.config where chave in ('expediente_dias','expediente_inicio','expediente_fim');

drop function if exists public.treble_expediente();

create or replace function public.treble_momento() returns jsonb
language sql security definer set search_path = public
as $$
  select jsonb_build_object(
    'agora', to_char(now() at time zone 'America/Sao_Paulo', 'TMDay, DD/MM HH24:MI'),
    'fim_de_semana', extract(isodow from now() at time zone 'America/Sao_Paulo') in (6,7),
    'fora_do_horario_comum', (
      extract(isodow from now() at time zone 'America/Sao_Paulo') in (6,7)
      or (now() at time zone 'America/Sao_Paulo')::time < '09:00'
      or (now() at time zone 'America/Sao_Paulo')::time >= '19:00'
    ),
    'nota', 'Sinal de contexto, não regra: o time às vezes atende à noite e no fim de semana. Transfira pela necessidade, nunca pelo horário. Se transferir em momento de resposta mais lenta, seja honesto sobre isso sem prometer prazo.'
  );
$$;
revoke all on function public.treble_momento() from public, anon, authenticated;

comment on function public.treble_momento() is
  'Sinal de contexto temporal para o agente calibrar expectativa no handoff. Nunca deve ser usado como portão para bloquear transferência.';
