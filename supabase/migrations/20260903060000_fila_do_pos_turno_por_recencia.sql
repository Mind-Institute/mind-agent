-- A FILA DO PÓS-TURNO ESTAVA ENVENENADA. `analise_pendentes` é a fila que o cron
-- `analise_conversas` (job 12) consome de 15 em 15 minutos, dez conversas por vez,
-- e ela ordenava por `conv.id` — um uuid, ou seja, ordem aleatória mas FIXA.
--
-- O `analisar-conversa` pula, sem gravar nada, a conversa em que o lead nunca
-- escreveu texto (áudio/mídia) e a conversa cujo classificador escolhe um analisador
-- de prompt vazio (`analise_atendimento`, caso de "Descadastrar", "Sair", "Obrigada").
-- Pulada sem marca, a conversa volta para a fila no ciclo seguinte — e, como a ordem
-- é fixa, volta para a MESMA posição. Medido em 03/09 05:30 UTC: as dez menores
-- uuids pendentes eram todas desse tipo; 123 pendentes, 77 substantivas, todas atrás
-- da décima cabeça; das 31 análises feitas desde 02/09 20:00, 30 tinham uuid menor
-- que a cabeça. Só era analisada conversa nova que, por sorteio de uuid, caísse antes
-- das dez envenenadas. Dez conversas do App e 67 do WhatsApp estavam presas.
--
-- A MENOR MUDANÇA SÃO DUAS LINHAS:
--   1. ordenar por recência da última mensagem: o que acabou de acontecer é analisado
--      primeiro, o backlog drena atrás e o veneno vai para o fim da fila, onde só é
--      tentado de novo quando não há nada novo — custa um classificador por ciclo,
--      não a fila inteira;
--   2. exigir que a fala do lead tenha TEXTO, que é exatamente o filtro que
--      `analise_montar_contexto` já aplica ao montar o transcrito. Conversa que o
--      pipeline não consegue analisar não entra na fila.
--
-- O marcador durável de "pulada" pertence ao `analisar-conversa`, que não está
-- versionado neste repositório; fica registrado no BACKLOG.
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
      and exists (select 1 from engagement.mensagens m2
                   where m2.conversa_id = c.id and m2.papel = 'lead' and m2.conteudo is not null)
  )
  select conv.id
  from conv
  where not exists (
    select 1 from intelligence.analise_conversa a
    where a.conversa_id = conv.id
      and a.conversa_atualizada_ate >= conv.ult_msg)
  order by conv.ult_msg desc, conv.id
  limit greatest(1, p_limite);
$function$;

revoke all on function public.analise_pendentes(integer) from public, anon, authenticated;
grant execute on function public.analise_pendentes(integer) to service_role;
