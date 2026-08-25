-- Quando o Treble for ligado no agente, a PRIMEIRA conversa precisa contar o que
-- ele manda: se vem o nome do HubSpot, se vem a opcao do botao, se vem o id do
-- contato. Hoje ninguem sabe, e adivinhar isso e como a gente perde tempo.
--
-- Guarda so no primeiro turno da conversa -- depois disso o payload se repete e
-- nao ensina mais nada. E nunca guarda o token: ele identifica o chamador, nao a
-- conversa.
create or replace function public.mind_conversa_payload(p_conversation_id uuid, p_payload jsonb)
returns void
language sql
security definer
set search_path to 'public', 'treble'
as $function$
  update treble.conversations
     set variables = (p_payload - 'token' - 'authorization' - 'secret')
   where id = p_conversation_id
     and (variables is null or variables = '{}'::jsonb);
$function$;

comment on function public.mind_conversa_payload(uuid, jsonb) is
  'Guarda o payload cru do primeiro turno em treble.conversations.variables, sem token. Serve para descobrir o que o Treble realmente manda, em vez de supor.';

revoke all on function public.mind_conversa_payload(uuid, jsonb) from public, anon, authenticated;