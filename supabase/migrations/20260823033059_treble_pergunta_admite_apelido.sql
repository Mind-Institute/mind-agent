-- Meio-termo escolhido pela Adriana: dizer que EXISTE um cadastro em outro
-- nome, sem dizer qual, e abrir espaco para apelido.
--
-- O que NAO revela: nome, e-mail, empresa ou cargo de terceiro.
-- O que revela: que o e-mail que a propria pessoa digitou ja existe na base
-- e esta em outro nome. Divulgacao fraca, aceita para nao duplicar quem se
-- apresenta por apelido ("Leticia" cadastrada, se apresenta como "Fofinha").

create or replace function public.treble_pergunta_de_identidade(p_candidatos jsonb)
returns jsonb
language sql stable
as $function$
  with c as (select value p from jsonb_array_elements(coalesce(p_candidatos,'[]'::jsonb))),
  n as (select count(*) q from c)
  select case
    when (select q from n) = 0 then null

    -- Um candidato, nome destoante: admite a existencia, nunca o nome.
    when (select q from n) = 1 and (select (p->>'precisa_confirmar_nome')::boolean from c) then
      jsonb_build_object(
        'tipo','confirmar_nome_do_titular',
        'pergunta','Encontrei um cadastro com esse e-mail, mas em outro nome. '
                || 'Pode ser que voce tenha usado um apelido ou um nome diferente? '
                || 'Me diz seu nome completo que eu confirmo aqui.',
        'revela_nome_de_terceiro', false,
        'revela_que_existe_cadastro', true)

    when (select q from n) = 1 then null

    -- Varios candidatos: pergunta sobre ELA, no campo que difere entre eles.
    -- O valor que difere nunca aparece na pergunta.
    else coalesce(
      (select jsonb_build_object('tipo','desempate','campo',campo,'pergunta',pergunta,
                                 'revela_nome_de_terceiro', false)
         from (
           select 'comprou' campo, count(distinct p->>'comprou') d,
                  'So confirmando: voce ja comprou ingresso para o Summit?' pergunta from c
           union all
           select 'empresa', count(distinct p->>'empresa'),
                  'De qual empresa voce e?' from c
           union all
           select 'cargo', count(distinct p->>'cargo'),
                  'Qual e o seu cargo?' from c
           union all
           select 'nome', count(distinct p->>'nome'),
                  'Me confirma seu nome completo?' from c
         ) x where d > 1
         order by case campo when 'comprou' then 1 when 'empresa' then 2
                             when 'cargo' then 3 else 4 end limit 1),
      jsonb_build_object('tipo','desempate','campo',null,
        'pergunta','Me confirma seu nome completo?','revela_nome_de_terceiro', false))
  end;
$function$;

revoke all on function public.treble_pergunta_de_identidade(jsonb) from public, anon, authenticated;
grant execute on function public.treble_pergunta_de_identidade(jsonb) to service_role;

comment on function public.treble_pergunta_de_identidade(jsonb) is
  'Pergunta que desfaz duvida de identidade. Nunca revela nome, e-mail, empresa ou cargo de terceiro. Admite apenas que existe cadastro para o e-mail que a propria pessoa digitou, para dar chance de apelido. Decisao registrada com a Adriana em 23/08/2026.';
