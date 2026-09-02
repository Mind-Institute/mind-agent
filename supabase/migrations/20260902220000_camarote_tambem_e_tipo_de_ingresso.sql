/* ============================================================
   A LISTA DE TIPOS DEIXA DE SER FECHADA
   ============================================================
   Quando `api.mindagent_participante_ingresso` foi escrita, hoje mais
   cedo, o espelho do credenciamento tinha quatro valores em
   `ticket_type`: VIP, Mind, Prime e `SEM MAPA` — este último em 378
   pessoas, com `batch` nulo, com cara de importação incompleta.

   A função foi conservadora: devolvia só os três tipos conhecidos, por
   nome. Nas horas seguintes a Adriana mapeou a base, e o espelho virou
   outro: `SEM MAPA` caiu para 3 linhas (nenhuma ativa) e apareceu
   **Camarote**, com 54 pessoas ativas. A lista fechada calou o
   cabeçalho dessas 54 sem erro nenhum na tela — que é exatamente como
   este tipo de defeito se esconde.

   INVERTEMOS A REGRA. Em vez de listar o que passa, listamos o que NÃO
   é tipo de ingresso: `SEM MAPA` é sentinela de importação, não
   categoria. Qualquer tipo real que o espelho ganhe amanhã aparece
   sozinho, sem alguém precisar lembrar de vir aqui.

   O TETO DE TAMANHO fica no lugar da lista. Vinte e quatro caracteres
   cabem em "Camarote" e em qualquer rótulo comercial plausível, e não
   cabem numa frase — o cabeçalho não vira campo de texto livre se o
   espelho um dia trouxer lixo nessa coluna. A conferência de FORMA mora
   no `data-service.js`, que é quem escreve na tela.

   O resto da função não muda, e as garantias continuam de pé: devolve
   só o tipo; `null` cobre ausente, sentinela, revogado e desacordo,
   todos iguais entre si; só `service_role` executa.
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
  if v_email = '' or position('@' in v_email) = 0 then
    return jsonb_build_object('ingresso', null);
  end if;

  select case when count(distinct btrim(ticket_type)) = 1
              then min(btrim(ticket_type)) end
    into v_tipo
  from credenciamento_summit_2026.participantes
  where lower(btrim(email)) = v_email
    and status = 'ativo'
    and revogado_em is null
    and ticket_type is not null
    /* Sentinela de importação, não categoria. */
    and upper(btrim(ticket_type)) <> 'SEM MAPA'
    and char_length(btrim(ticket_type)) between 2 and 24;

  return jsonb_build_object('ingresso', v_tipo);
end
$$;

comment on function api.mindagent_participante_ingresso(text) is
  'Tipo de ingresso de um e-mail no espelho do credenciamento. Devolve so {"ingresso": ...}; null para ausente, sentinela de importacao, revogado ou tipo em desacordo. So service_role executa.';

revoke all on function api.mindagent_participante_ingresso(text) from public;
grant execute on function api.mindagent_participante_ingresso(text) to service_role;

/* O encaminhador em `public` não muda — ele é uma linha que chama a de
   cima. Os grants dele são restabelecidos aqui mesmo assim, para que o
   arquivo que define o comportamento vigente também diga quem alcança a
   porta, em vez de deixar essa metade só na migração anterior. */
revoke all on function public.mindagent_participante_ingresso(text) from public;
grant execute on function public.mindagent_participante_ingresso(text) to service_role;
