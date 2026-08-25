-- A pergunta de desempate, nas palavras da Adriana: "voce ja comprou? qual
-- produto voce ja comprou no Mind?". Continua sendo o primeiro criterio
-- (ordem 1) porque comprar/nao comprar e o que a pessoa sabe de si com
-- certeza, e e o que mais separa duas fichas parecidas.
--
-- A regra de LGPD nao muda: a pergunta nomeia o CAMPO, nunca o VALOR.
-- Nao dizemos qual produto o outro cadastro comprou, nem de quem ele e.
create or replace function public.treble_pergunta_de_identidade(p_candidatos jsonb)
 returns jsonb
 language sql
 stable
as $function$
  with c as (select value p from jsonb_array_elements(coalesce(p_candidatos,'[]'::jsonb))),
  n as (select count(*) q from c),
  -- CAMPOS PERGUNTAVEIS: so o que a pessoa sabe de si.
  perguntavel(campo, ordem, pergunta) as (values
    ('comprou', 1, 'Voce ja comprou alguma coisa com a gente antes? Se sim, qual produto do Mind foi?'),
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
