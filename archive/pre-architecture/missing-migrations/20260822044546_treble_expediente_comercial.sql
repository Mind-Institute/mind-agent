-- O agente passa a saber se há vendedor disponível AGORA (fuso de São Paulo).
-- Fora do expediente, o playbook segura o handoff: nutre, entrega valor e
-- captura informação — e só transfere se for mesmo necessário, avisando
-- quando o time responde.
insert into treble.config (chave, valor) values
  ('expediente_dias', '1,2,3,4,5'),      -- 1=segunda ... 7=domingo
  ('expediente_inicio', '09:00'),
  ('expediente_fim', '18:00')
on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();

create or replace function public.treble_expediente() returns jsonb
language plpgsql security definer set search_path = public, treble
as $$
declare
  agora timestamptz := now() at time zone 'America/Sao_Paulo';
  dias int[];
  hora_ini time;
  hora_fim time;
  dow int;
  aberto boolean;
  proximo text;
begin
  select string_to_array(valor, ',')::int[] into dias from treble.config where chave = 'expediente_dias';
  select valor::time into hora_ini from treble.config where chave = 'expediente_inicio';
  select valor::time into hora_fim from treble.config where chave = 'expediente_fim';
  dias := coalesce(dias, array[1,2,3,4,5]);
  hora_ini := coalesce(hora_ini, '09:00'::time);
  hora_fim := coalesce(hora_fim, '18:00'::time);

  dow := extract(isodow from agora);
  aberto := dow = any(dias) and agora::time >= hora_ini and agora::time < hora_fim;

  if aberto then
    proximo := 'agora';
  elsif dow = any(dias) and agora::time < hora_ini then
    proximo := 'hoje a partir das ' || to_char(hora_ini, 'HH24"h"');
  else
    -- Próximo dia útil configurado
    proximo := case
      when (dow + 1) = any(dias) or (dow = 7 and 1 = any(dias)) then 'amanhã de manhã'
      when dow in (5,6,7) then 'na segunda de manhã'
      else 'no próximo dia útil'
    end;
  end if;

  return jsonb_build_object(
    'vendedor_disponivel_agora', aberto,
    'quando_o_time_responde', proximo,
    'horario', to_char(hora_ini,'HH24"h"') || ' às ' || to_char(hora_fim,'HH24"h"') || ', dias úteis'
  );
end;
$$;
revoke all on function public.treble_expediente() from public, anon, authenticated;
