-- Texto da pergunta de desempate escrito pela Adriana em 23/08/2026.
-- Substitui o meu, que perguntava "voce ja comprou alguma coisa com a gente".
-- O dela e melhor por dois motivos: nomeia os produtos que a pessoa reconhece
-- (Summit, formacoes do Institute) em vez de "alguma coisa", e pede o ANO ou a
-- formacao, que e o que realmente separa duas fichas parecidas.
--
-- Unica alteracao minha no texto dela: "Fromacao" -> "Formacao" (erro de
-- digitacao evidente, e o texto vai para cliente).
--
-- A regra de LGPD nao muda: a pergunta nomeia o CAMPO, nunca o VALOR. Nao
-- dizemos qual produto o outro cadastro comprou, nem de quem ele e.
create or replace function public.treble_pergunta_de_identidade(p_candidatos jsonb)
 returns jsonb
 language sql
 stable
as $function$
  with c as (select value p from jsonb_array_elements(coalesce(p_candidatos,'[]'::jsonb))),
  n as (select count(*) q from c),
  -- CAMPOS PERGUNTAVEIS: so o que a pessoa sabe de si.
  perguntavel(campo, ordem, pergunta) as (values
    ('comprou', 1, 'Você já participou do Summit, ou das formações do Institute? Se sim, me diga qual ano do Summit ou Formação do Institute para que eu possa te identificar e te ajudar melhor.'),
    ('empresa', 2, 'De qual empresa você é?'),
    ('cargo',   3, 'Qual é o seu cargo?'),
    ('nome',    4, 'Me confirma seu nome completo?')
  ),
  difere as (
    select pv.campo, pv.ordem, pv.pergunta
    from perguntavel pv
    where (select count(*) from (select distinct p->>pv.campo as v from c) t) > 1
  )
  select case
    when (select q from n) = 0 then null

    when (select q from n) = 1 and (select (p->>'precisa_confirmar_nome')::boolean from c) then
      jsonb_build_object(
        'tipo','confirmar_nome_do_titular',
        'pergunta','Encontrei um cadastro com esse e-mail, mas em outro nome. '
                || 'Pode ser que você tenha usado um apelido ou um nome diferente? '
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
