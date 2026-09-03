-- Concierge: jornada persistente, recomendação compatível com ingresso e ICP
-- inferido apenas como hipótese de baixa confiança a partir do cargo.

begin;

create or replace function public.mind_kit_programacao_filtrada(
  p_conversa_id uuid default null,
  p_necessidade jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_pessoa uuid;
  v_cred jsonb;
  v_categorias text[] := '{}'::text[];
  v_sessoes jsonb := '[]'::jsonb;
begin
  v_base := public.mind_kit_programacao(p_conversa_id,p_necessidade);
  if v_base is null then return null; end if;

  select c.participante_id into v_pessoa
  from engagement.conversas c where c.id=p_conversa_id;

  if v_pessoa is null then
    return v_base || jsonb_build_object('ingresso',jsonb_build_object(
      'identificado',false,'recomendacoes_filtradas',false));
  end if;

  v_cred := public.mind_credenciamento_fatos(v_pessoa);
  select coalesce(array_agg(lower(x)) filter(where lower(x)=any(array['mind','vip','prime'])),
                  '{}'::text[])
    into v_categorias
  from jsonb_array_elements_text(coalesce(v_cred->'categorias','[]'::jsonb)) x;

  if coalesce((v_cred->>'tem_ingresso_ativo')::boolean,false)
     and cardinality(v_categorias)>0 then
    select coalesce(jsonb_agg(item order by ord),'[]'::jsonb)
      into v_sessoes
    from jsonb_array_elements(coalesce(v_base->'sessions','[]'::jsonb))
           with ordinality j(item,ord)
    join summit_2026.sessions s on s.id=(j.item->>'id')::uuid
    where coalesce(s.ingressos,'{}'::text[]) && v_categorias;
  end if;

  v_base := jsonb_set(v_base,'{sessions}',v_sessoes,true);
  v_base := jsonb_set(v_base,'{sessions_total}',to_jsonb(jsonb_array_length(v_sessoes)),true);
  return v_base || jsonb_build_object('ingresso',jsonb_build_object(
    'identificado',true,
    'tem_ingresso_ativo',coalesce((v_cred->>'tem_ingresso_ativo')::boolean,false),
    'categorias',coalesce(v_cred->'categorias','[]'::jsonb),
    'categorias_aplicadas',to_jsonb(v_categorias),
    'recomendacoes_filtradas',true,
    'motivo_sem_sessoes',case
      when not coalesce((v_cred->>'tem_ingresso_ativo')::boolean,false) then 'sem_ingresso_ativo'
      when cardinality(v_categorias)=0 then 'categoria_sem_regra_de_acesso'
      when jsonb_array_length(v_sessoes)=0 then 'nenhuma_sessao_compativel_na_busca'
      else null end));
end
$function$;

revoke all on function public.mind_kit_programacao_filtrada(uuid,jsonb)
  from public,anon,authenticated;
grant execute on function public.mind_kit_programacao_filtrada(uuid,jsonb)
  to service_role;

update agentes.kit_blocos
set provider='public.mind_kit_programacao_filtrada',obrigatorio=true,ativo=true
where rota='concierge_summit' and bloco='programacao';

create or replace function public.mind_kit_customer_intelligence_contextual(
  p_conversa_id uuid,
  p_necessidade jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_ci jsonb;
  v_cargo text;
  v_icp text;
begin
  v_ci:=public.mind_kit_customer_intelligence(p_conversa_id,p_necessidade);
  if v_ci is null or v_ci#>'{professional_context,icp}' is not null then return v_ci; end if;
  v_cargo:=lower(coalesce(v_ci#>>'{professional_context,role}',''));
  if v_cargo='' then return v_ci; end if;

  v_icp:=case
    when v_cargo ~ '(chro|chief human|vp.*pessoa|vice.*pessoa|diretor.*(rh|recursos humanos|pessoas))'
      then 'CHRO / VP de Pessoas'
    when v_cargo ~ '(ceo|chief executive|fundador|fundadora|presidente|c.?suite)'
      then 'CEO / C-Suite'
    when v_cargo ~ '(hrbp|business partner|people partner|lider de pessoas|líder de pessoas)'
      then 'People Leader / Business Partner'
    when v_cargo ~ '(consultor|consultora|coach|psicolog|psicólog)'
      then 'Consultor / Coach / Psicólogo'
    when v_cargo ~ '(gerente|coordenador|coordenadora|supervisor|supervisora|gestor|gestora|head)'
      then 'Gestor / Middle Manager'
    when v_cargo ~ '(executivo|executiva|diretor|diretora|vice-presidente|\mvp\M)'
      then 'Executivo Sênior / Alto Performer'
    else null end;

  if v_icp is null then return v_ci; end if;
  return jsonb_set(v_ci,'{professional_context,icp}',jsonb_build_object(
    'value',v_icp,'confidence',0.55,'source','role_inference',
    'evidence',jsonb_build_object('role',v_ci#>>'{professional_context,role}')),true);
end
$function$;

revoke all on function public.mind_kit_customer_intelligence_contextual(uuid,jsonb)
  from public,anon,authenticated;
grant execute on function public.mind_kit_customer_intelligence_contextual(uuid,jsonb)
  to service_role;

update agentes.kit_blocos
set provider='public.mind_kit_customer_intelligence_contextual',obrigatorio=false,ativo=true
where rota in ('concierge_summit','cliente_suporte','summit_b2c','summit_b2b')
  and bloco='customer_intelligence';

update agentes.prompts
set conteudo=conteudo || $regra$

CONTEXTO TEMPORAL, INGRESSO E DESCOBERTA
Use current_time e as datas oficiais do evento para saber se a pessoa está antes, durante ou depois do Summit. Durante o evento, priorize orientação imediata e Concierge. Venda ou upgrade só entra quando houver intenção compatível e oferta oficial no Kit; nunca invente preço, regra ou checkout.

Em recomendação de conteúdo, use somente as sessões devolvidas em programacao.sessions: elas já estão filtradas pelos acessos do ingresso quando a pessoa foi identificada. Diga de forma natural que a sugestão considera o tipo de ingresso. Se programacao.ingresso.motivo_sem_sessoes estiver preenchido, explique que não consegue confirmar uma opção compatível em vez de recomendar algo inacessível.

Use cargo, empresa e ICP apenas para personalizar linguagem e formular uma hipótese, nunca para presumir dor, interesse ou compra. Quando o job ainda não estiver claro, faça uma pergunta sutil de alto valor por vez, preferencialmente oferecendo duas alternativas concretas. Guarde escolhas da jornada como evidência; não repita o que a pessoa já respondeu.
$regra$,
    atualizado_em=now()
where chave='playbook_concierge_summit'
  and conteudo not like '%CONTEXTO TEMPORAL, INGRESSO E DESCOBERTA%';

do $guard$
declare v_programacao jsonb; v_prompt text;
begin
  if not exists(select 1 from agentes.kit_blocos where rota='concierge_summit'
    and bloco='programacao' and provider='public.mind_kit_programacao_filtrada' and obrigatorio and ativo) then
    raise exception 'provider de programação filtrada não foi ligado';
  end if;
  if (select count(*) from agentes.kit_blocos where bloco='customer_intelligence'
      and provider='public.mind_kit_customer_intelligence_contextual' and ativo)<>4 then
    raise exception 'ICP contextual não chegou às quatro rotas';
  end if;
  select conteudo into v_prompt from agentes.prompts where chave='playbook_concierge_summit';
  if v_prompt not like '%CONTEXTO TEMPORAL, INGRESSO E DESCOBERTA%'
     or v_prompt not like '%use somente as sessões devolvidas em programacao.sessions%' then
    raise exception 'playbook não recebeu regra temporal/de ingresso';
  end if;
end
$guard$;

commit;
