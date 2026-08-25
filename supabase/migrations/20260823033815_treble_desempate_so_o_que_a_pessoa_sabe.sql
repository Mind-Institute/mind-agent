-- O desempate so pode perguntar o que a PROPRIA PESSOA sabe sobre si.
-- Lista fechada, e fechada de proposito: se alguem adicionar um campo
-- derivado aqui, o agente comeca a perguntar coisa que so o sistema sabe
-- ("voce esta no estagio de negociacao?") e entrega inferencia como se fosse
-- fato. Nunca entram: estagio de funil, interesse inferido, memoria,
-- pontuacao, ou qualquer conclusao do sistema.
--
-- E a pergunta nunca carrega o VALOR que difere -- so o campo.

create or replace function public.treble_pergunta_de_identidade(p_candidatos jsonb)
returns jsonb
language sql stable
as $function$
  with c as (select value p from jsonb_array_elements(coalesce(p_candidatos,'[]'::jsonb))),
  n as (select count(*) q from c),
  -- CAMPOS PERGUNTAVEIS: so o que a pessoa sabe de si.
  perguntavel(campo, ordem, pergunta) as (values
    ('comprou', 1, 'So confirmando: voce ja comprou alguma coisa com a gente? Se sim, o que foi?'),
    ('empresa', 2, 'De qual empresa voce e?'),
    ('cargo',   3, 'Qual e o seu cargo?'),
    ('nome',    4, 'Me confirma seu nome completo?')
  ),
  difere as (
    select pv.campo, pv.ordem, pv.pergunta
    from perguntavel pv
    where (select count(distinct p->>pv.campo) from c) > 1
  )
  select case
    when (select q from n) = 0 then null

    when (select q from n) = 1 and (select (p->>'precisa_confirmar_nome')::boolean from c) then
      jsonb_build_object(
        'tipo','confirmar_nome_do_titular',
        'pergunta','Encontrei um cadastro com esse e-mail, mas em outro nome. '
                || 'Pode ser que voce tenha usado um apelido ou um nome diferente? '
                || 'Me diz seu nome completo que eu confirmo aqui.',
        'revela_nome_de_terceiro', false,
        'revela_que_existe_cadastro', true)

    when (select q from n) = 1 then null

    else coalesce(
      (select jsonb_build_object('tipo','desempate','campo',campo,'pergunta',pergunta,
                                 'revela_nome_de_terceiro', false,
                                 'revela_valor_que_difere', false)
         from difere order by ordem limit 1),
      jsonb_build_object('tipo','desempate','campo','nome',
        'pergunta','Me confirma seu nome completo?',
        'revela_nome_de_terceiro', false,
        'revela_valor_que_difere', false))
  end;
$function$;

revoke all on function public.treble_pergunta_de_identidade(jsonb) from public, anon, authenticated;
grant execute on function public.treble_pergunta_de_identidade(jsonb) to service_role;

comment on function public.treble_pergunta_de_identidade(jsonb) is
  'Pergunta de desempate de identidade. Lista FECHADA de campos pergunataveis: comprou, empresa, cargo, nome -- so o que a propria pessoa sabe de si. Nunca campo derivado (estagio, interesse, memoria). Nunca revela o valor que difere nem dado de terceiro.';
