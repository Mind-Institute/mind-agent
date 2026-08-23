-- A resolucao de identidade nao e do vendedor do Treble. O Concierge, o CS e o
-- Suporte vao precisar exatamente das mesmas perguntas: e regra do Mind
-- Intelligence, nao de um agente. Decisao da Adriana em 23/08/2026.
--
--   treble_pergunta_de_identidade  -> mind_pergunta_de_identidade
--   treble_candidatos_identidade   -> mind_candidatos_identidade
--   treble_agent_identificar       -> mind_identificar_pessoa
--
-- Os nomes antigos ficam como APELIDO (wrapper) para nada quebrar enquanto a
-- Edge Function no ar ainda os chama. Caem numa migration proria depois que a
-- v0.9 estiver estavel.
--
-- treble_agent_start e treble_resolver_por_whatsapp continuam com o nome atual:
-- o start e mesmo do runtime do Treble, e o resolver e chamado por ele.

alter function public.treble_pergunta_de_identidade(jsonb)
  rename to mind_pergunta_de_identidade;

alter function public.treble_candidatos_identidade(text,text,text,text)
  rename to mind_candidatos_identidade;

alter function public.treble_agent_identificar(text,text,text,text,boolean)
  rename to mind_identificar_pessoa;

-- Texto aprovado pela Adriana em 23/08/2026. Saiu "um apelido ou" -- basta
-- dizer "um nome diferente", que ja cobre apelido sem sugerir a palavra.
create or replace function public.mind_pergunta_de_identidade(p_candidatos jsonb)
 returns jsonb
 language sql
 stable
as $function$
  with c as (select value p from jsonb_array_elements(coalesce(p_candidatos,'[]'::jsonb))),
  n as (select count(*) q from c),
  -- CAMPOS PERGUNTAVEIS: so o que a pessoa sabe de si.
  -- cargo fica na lista, mas o valor dele e principalmente para o CRM:
  -- raramente e ele que desempata.
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
                || 'Pode ser que você tenha usado um nome diferente? '
                || 'Me diz seu nome completo, que eu confirmo por aqui.',
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

-- APELIDOS: mantem o que ja esta no ar funcionando durante a transicao.
create or replace function public.treble_pergunta_de_identidade(p_candidatos jsonb)
returns jsonb language sql stable as $$
  select public.mind_pergunta_de_identidade(p_candidatos);
$$;

create or replace function public.treble_candidatos_identidade(
  p_nome text default null, p_sobrenome text default null,
  p_email text default null, p_whatsapp text default null)
returns jsonb language sql stable as $$
  select public.mind_candidatos_identidade(p_nome, p_sobrenome, p_email, p_whatsapp);
$$;

create or replace function public.treble_agent_identificar(
  p_session_external_id text, p_email text default null,
  p_nome text default null, p_sobrenome text default null,
  p_mesma_pessoa boolean default null)
returns jsonb language sql as $$
  select public.mind_identificar_pessoa(p_session_external_id, p_email,
                                        p_nome, p_sobrenome, p_mesma_pessoa);
$$;

comment on function public.treble_pergunta_de_identidade(jsonb) is
  'APELIDO de mind_pergunta_de_identidade. Existe so para nao quebrar o que ja esta no ar. Nao usar em codigo novo.';
comment on function public.treble_candidatos_identidade(text,text,text,text) is
  'APELIDO de mind_candidatos_identidade. Existe so para nao quebrar o que ja esta no ar. Nao usar em codigo novo.';
comment on function public.treble_agent_identificar(text,text,text,text,boolean) is
  'APELIDO de mind_identificar_pessoa. Existe so para nao quebrar o que ja esta no ar. Nao usar em codigo novo.';

revoke all on function public.mind_pergunta_de_identidade(jsonb) from public, anon, authenticated;
revoke all on function public.mind_candidatos_identidade(text,text,text,text) from public, anon, authenticated;
revoke all on function public.mind_identificar_pessoa(text,text,text,text,boolean) from public, anon, authenticated;
revoke all on function public.treble_pergunta_de_identidade(jsonb) from public, anon, authenticated;
revoke all on function public.treble_candidatos_identidade(text,text,text,text) from public, anon, authenticated;
revoke all on function public.treble_agent_identificar(text,text,text,text,boolean) from public, anon, authenticated;

grant execute on function public.mind_pergunta_de_identidade(jsonb) to service_role;
grant execute on function public.mind_candidatos_identidade(text,text,text,text) to service_role;
grant execute on function public.mind_identificar_pessoa(text,text,text,text,boolean) to service_role;
grant execute on function public.treble_pergunta_de_identidade(jsonb) to service_role;
grant execute on function public.treble_candidatos_identidade(text,text,text,text) to service_role;
grant execute on function public.treble_agent_identificar(text,text,text,text,boolean) to service_role;
