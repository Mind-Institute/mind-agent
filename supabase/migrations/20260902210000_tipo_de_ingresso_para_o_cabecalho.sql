/* ============================================================
   O TIPO DE INGRESSO CHEGA AO CABEÇALHO
   ============================================================
   O cabeçalho do app passa a dizer "EXPERIÊNCIA VIP" e a mostrar a
   pílula do ingresso. Isso é o único caminho por onde essa informação
   sai do banco para o navegador.

   DE ONDE VEM
   `credenciamento_summit_2026.participantes` — o espelho do cadastro da
   Yazo dentro do backend do agente. É a origem autoritativa do ingresso;
   nada aqui decide, classifica ou completa nada: só lê.

   O QUE ELA DEVOLVE, E SÓ
   `{"ingresso": "VIP" | "Mind" | "Prime" | null}`. Nome, cargo, empresa,
   lote, patrocínio, número do ingresso: nada disso passa por aqui. Quem
   precisa de perfil já tem o `mindagent_chat_get_context`.

   `null` COBRE TUDO O QUE NÃO É CERTEZA — e cobre de propósito:

     · e-mail que não está no espelho;
     · `SEM MAPA` (378 pessoas hoje: ingresso pago, tipo nunca mapeado);
     · ingresso revogado;
     · e-mail com mais de um tipo ativo em desacordo.

   Os quatro respondem a mesma coisa. Não dá para separar "não está na
   lista" de "está e não tem tipo" — e é isso que impede que esta porta
   vire uma forma de descobrir quem tem ingresso. O que ela confirma é
   só o tipo de quem tem um tipo mapeado e ativo.

   O DESACORDO É `null`, NÃO UM DESEMPATE. Catorze e-mails aparecem em
   mais de uma linha, e alguns com tipos diferentes (`Prime | VIP`).
   Desempatar exigiria uma hierarquia comercial entre VIP, Mind e Prime,
   que não é decisão desta lane. Hoje, depois de filtrar revogados, os
   811 e-mails com tipo têm um tipo só — o desacordo custa zero e
   continua protegendo se o espelho mudar.

   QUEM PODE CHAMAR: só `service_role`, isto é, só a Edge Function
   `mindagent-home`. Sem grant para `anon` nem `authenticated`, o
   PostgREST não a alcança com a chave publicável.
   ============================================================ */

create or replace function api.mindagent_participante_ingresso(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_tipo  text;
begin
  /* Nem toca no espelho sem algo com cara de e-mail. */
  if v_email = '' or position('@' in v_email) = 0 then
    return jsonb_build_object('ingresso', null);
  end if;

  /* Um tipo só, ou nada: `count(distinct)` = 1 é a condição inteira. */
  select case when count(distinct ticket_type) = 1 then min(ticket_type) end
    into v_tipo
  from credenciamento_summit_2026.participantes
  where lower(btrim(email)) = v_email
    and status = 'ativo'
    and revogado_em is null
    and ticket_type in ('VIP', 'Mind', 'Prime');

  return jsonb_build_object('ingresso', v_tipo);
end
$$;

comment on function api.mindagent_participante_ingresso(text) is
  'Tipo de ingresso de um e-mail no espelho do credenciamento. Devolve só {"ingresso": ...}; null para ausente, SEM MAPA, revogado ou tipo em desacordo. Só service_role executa.';

revoke all on function api.mindagent_participante_ingresso(text) from public;
grant execute on function api.mindagent_participante_ingresso(text) to service_role;

/* ------------------------------------------------------------
   O ESPELHO EM `public`, porque é lá que o PostgREST procura
   ------------------------------------------------------------
   A Edge Function chama `rpc("mindagent_participante_ingresso")` pelo
   supabase-js, e o cliente resolve RPC no schema exposto — `public`. É
   o mesmo par que `mindagent_home_publico` e `mindagent_bootstrap` já
   têm: a função de verdade em `api`, um encaminhador de uma linha em
   `public`.

   A diferença está nos grants. Os dois encaminhadores existentes são
   abertos para `anon` — o conteúdo deles é público. Este não: fica só
   com `service_role`, para que a chave publicável do navegador não
   alcance a porta por fora da Edge Function. O `security invoker` aqui
   é o que faz isso valer — o encaminhador não empresta privilégio
   nenhum a quem o chama.
   ------------------------------------------------------------ */

create or replace function public.mindagent_participante_ingresso(p_email text)
returns jsonb
language sql
stable
set search_path = pg_catalog, api
as $$ select api.mindagent_participante_ingresso(p_email); $$;

revoke all on function public.mindagent_participante_ingresso(text) from public;
grant execute on function public.mindagent_participante_ingresso(text) to service_role;
