-- O APP ESTAVA FORA DO PÓS-TURNO. `analise_pendentes` é a fila que o cron
-- `analise_conversas` (job 12) consome de 15 em 15 minutos, e ela filtrava
--
--     where c.agente in ('treble','treble-inbound-agent')
--
-- ou seja: só WhatsApp. Medido em 02/09 — TODAS as análises desde 05:00 vieram de
-- `agente='treble'`, nenhuma do App. O Passo 5 ligou o contrato de memória durável do
-- Concierge (`analise_concierge` + o ramo novo em `analise_projetar_memoria`), mas para
-- uma conversa do App esse contrato nunca era exercido: ninguém enfileirava o App.
--
-- A MENOR MUDANÇA É UMA PALAVRA. Nada mais do corpo muda: mesma janela por
-- `conversa_atualizada_ate`, mesma exigência de fala de `lead`, mesma ordenação, mesmo
-- limite. Só o universo cresce.
--
-- QUEM ESCOLHE O ANALISADOR CONTINUA SENDO O `analise_classificador`. Ele já é
-- canal-agnóstico por construção ("uma conversa ocorrida em QUALQUER canal do ecossistema
-- Mind") e já tem `analise_concierge` entre os permitidos. Por isso NÃO se hardcoda
-- analisador por canal aqui, e `analise_concierge` NÃO vira exclusivo do App: uma conversa
-- comercial de WhatsApp continua escolhendo vendas, e pode acumular o concierge quando
-- houver contexto pessoal útil — que é exatamente a Customer Intelligence compartilhada
-- entre canais e produtos.
--
-- Volume conferido antes de aplicar: 58 conversas do App entram pendentes, 52 delas das
-- últimas 24h. A 20 por ciclo de 15 minutos, a fila drena em ~45 minutos. Não é
-- avalanche e não precisa de janela especial.

create or replace function public.analise_pendentes(p_limite integer default 20)
returns table(conversa_id uuid)
language sql
stable security definer
set search_path to 'public', 'intelligence', 'engagement'
as $function$
  with conv as (
    select c.id,
           (select max(m.criado_em) from engagement.mensagens m where m.conversa_id = c.id) as ult_msg
    from engagement.conversas c
    where c.agente in ('treble','treble-inbound-agent','mindagent-chat')
      and exists (select 1 from engagement.mensagens m2 where m2.conversa_id = c.id and m2.papel = 'lead')
  )
  select conv.id
  from conv
  where not exists (
    select 1 from intelligence.analise_conversa a
    where a.conversa_id = conv.id
      and a.conversa_atualizada_ate >= conv.ult_msg)
  order by conv.id
  limit greatest(1, p_limite);
$function$;

do $g$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'analise_pendentes';

  if position('''mindagent-chat''' in d) = 0 then
    raise exception 'o App nao entrou no universo de analise_pendentes';
  end if;
  -- O WhatsApp não pode ter saído junto: a fila cresce, não troca de dono.
  if position('''treble''' in d) = 0 or position('''treble-inbound-agent''' in d) = 0 then
    raise exception 'o WhatsApp saiu do universo de analise_pendentes';
  end if;
  -- E o resto do corpo continua o mesmo: janela, fala de lead e limite.
  if position('conversa_atualizada_ate >= conv.ult_msg' in d) = 0 then
    raise exception 'a janela por conversa_atualizada_ate se perdeu';
  end if;
  if position('m2.papel = ''lead''' in d) = 0 then
    raise exception 'a exigencia de fala de lead se perdeu';
  end if;
end $g$;
