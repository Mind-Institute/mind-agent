-- CUSTOMER INTELLIGENCE — ICP + JTBD no pipeline vivo.
--
-- Decisões canônicas: CUSTOMER_INTELLIGENCE_STEP2_TAXONOMY.md e
-- CUSTOMER_INTELLIGENCE_STEP3_CONTRACT.md.
--
-- Menor arquitetura:
--   conversa -> analise_concierge -> participante_memoria -> mind_customer_intelligence
--            -> Kit da rota -> Agent
--
-- Sem tabela nova. Sem Router novo. Sem Edge nova. Sem estado `job_prioritario_atual`.
-- Intelligence guarda fatos/jobs observados; Decisioning decide o que está em placa agora.

-- -----------------------------------------------------------------------------
-- 1. O pós-conversa passa a carregar a evidência exata e o ICP canônico do CRM.

create or replace function public.analise_montar_contexto(p_conversa_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','intelligence','engagement','pessoas','crm'
as $function$
declare
  c         engagement.conversas%rowtype;
  v_hub     text;
  v_vars    jsonb;
  v_cta     text;
  v_origem  jsonb;
  v_sessao  jsonb;
  v_crm_atr jsonb;
  v_atr     jsonb;
  v_ctx     jsonb;
begin
  select * into c from engagement.conversas where id = p_conversa_id;
  if not found then return null; end if;

  select hubspot_id into v_hub from pessoas.pessoas where id = c.participante_id;

  v_vars := case
    when jsonb_typeof(c.variables) = 'array' then (
      select coalesce(jsonb_object_agg(v->>'key', v->>'value')
             filter (where nullif(v->>'key','') is not null
                       and nullif(v->>'value','') is not null), '{}'::jsonb)
      from jsonb_array_elements(c.variables) v)
    when jsonb_typeof(c.variables) = 'object' then c.variables
    else '{}'::jsonb end;

  v_cta := nullif(trim(coalesce(
             v_vars->>'hubspot_opcao_selecionada_treble',
             v_vars->>'opcao_selecionada', '')), '');

  select to_jsonb(o) - 'atualizado_em' - 'hubspot' into v_origem
    from engagement.origens o where o.codigo = c.origem_codigo;

  select jsonb_strip_nulls(to_jsonb(u) - 'token' - 'criado_em' - 'usado_em') into v_sessao
    from engagement.utm_sessoes u where u.token = c.utm_token;

  select jsonb_strip_nulls(to_jsonb(x)) into v_crm_atr from (
    select utm_source, utm_medium, utm_campaign, utm_content, utm_term,
           msclkid, li_fat_id,
           hs_analytics_source, hs_analytics_source_data_1, hs_analytics_source_data_2,
           hs_analytics_first_url, hs_analytics_first_referrer, hs_analytics_first_timestamp,
           hs_latest_source, hs_latest_source_data_1, hs_latest_source_timestamp,
           hs_analytics_last_url, hs_analytics_last_referrer,
           first_conversion_event_name, first_conversion_date,
           hs_analytics_first_touch_converting_campaign,
           hs_analytics_last_touch_converting_campaign
    from crm.contato_espelho where hubspot_id = v_hub limit 1) x;

  v_atr := jsonb_strip_nulls(jsonb_build_object(
    'utm_conversa',   c.utm,
    'utm_token',      c.utm_token,
    'sessao_do_site', nullif(coalesce(v_sessao,'{}'::jsonb), '{}'::jsonb),
    'hubspot',        nullif(coalesce(v_crm_atr,'{}'::jsonb), '{}'::jsonb)
  ));

  v_ctx := jsonb_strip_nulls(jsonb_build_object(
    'canal',          c.canal,
    'agente',         c.agente,
    'origem_codigo',  c.origem_codigo,
    'origem',         v_origem,
    'produto_codigo', c.produto_codigo,
    'entry_action',   v_cta,
    'atribuicao',     nullif(coalesce(v_atr,'{}'::jsonb), '{}'::jsonb),
    'audience',       c.audience,
    'stage',          c.stage,
    'iniciada_em',    c.iniciada_em,
    'encerrada_em',   c.encerrada_em,
    'variables',      nullif(v_vars, '{}'::jsonb)
  ));

  return jsonb_build_object(
    'conversation_context', v_ctx,
    'conversa_id', p_conversa_id,
    'transcrito', coalesce((
       select jsonb_agg(jsonb_build_object(
                'mensagem_id', m.id,
                'papel', m.papel,
                'conteudo', m.conteudo,
                'criado_em', m.criado_em)
                order by m.criado_em, m.id)
       from engagement.mensagens m
       where m.conversa_id = p_conversa_id and m.conteudo is not null), '[]'::jsonb),
    'pessoa', (select to_jsonb(x) from (
       select primeiro_nome, sobrenome, email, empresa, cargo
       from pessoas.pessoas where id = c.participante_id) x),
    'crm', (select to_jsonb(y) from (
       select lead_tier, lead_icp, icp, hs_lead_status, produto_de_interesse, motivo_do_lead__perdido,
              company, total_de_ingressos_comprados_lifetime, num_associated_deals, total_revenue
       from crm.contato_espelho where hubspot_id = v_hub limit 1) y)
  );
end
$function$;

-- -----------------------------------------------------------------------------
-- 2. Projector: ICP/JTBD usam a memória que já existe, com evidência fail-closed.

create or replace function public.analise_projetar_memoria(
  p_participante uuid,
  p_analisador text,
  p_memorias jsonb,
  p_analise_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path to 'public','intelligence','engagement'
as $function$
declare
  mem jsonb;
  v_cat text; v_texto text; v_scope text; v_conf text; v_sens text;
  v_tipo text; v_chave text; v_valor jsonb; v_num numeric; v_status text;
  v_concierge boolean;
  v_code text; v_context text; v_evidence_kind text; v_action text;
  v_evidence_raw text; v_evidence uuid; v_canon_label text;
  v_exist intelligence.participante_memoria%rowtype;
  v_novo uuid; v_n int := 0;
begin
  if p_participante is null or jsonb_typeof(p_memorias) <> 'array' then return 0; end if;

  v_concierge := (p_analisador = 'analise_concierge');

  for mem in select * from jsonb_array_elements(p_memorias)
  loop
    begin
      v_cat   := lower(nullif(trim(coalesce(mem->>'category','')),''));
      v_texto := nullif(trim(coalesce(mem->>'value','')),'');
      v_scope := lower(coalesce(nullif(trim(coalesce(mem->>'scope','')),''), 'opportunity'));
      v_conf  := lower(coalesce(nullif(trim(coalesce(mem->>'confidence','')),''), 'low'));
      v_sens  := lower(btrim(coalesce(mem->>'sensitivity','')));
      v_code  := upper(nullif(btrim(coalesce(mem->>'code','')),''));
      v_context := nullif(btrim(coalesce(mem->>'context','')),'');
      v_evidence_kind := nullif(lower(btrim(coalesce(mem->>'evidence_kind',''))),'');
      v_action := lower(coalesce(nullif(btrim(coalesce(mem->>'memory_action','')),''), 'observe'));
      v_evidence_raw := nullif(btrim(coalesce(mem->>'evidence_message_id','')),'');
      v_evidence := null;
      v_canon_label := null;

      continue when v_texto is null or v_cat is null or v_cat like '%|%';

      if v_concierge then
        continue when v_sens is distinct from 'none';
        continue when v_scope = 'temporary';
      end if;

      if v_cat = 'icp' then
        continue when v_texto <> all(array[
          'CHRO / VP de Pessoas','CEO / C-Suite','Gestor / Middle Manager',
          'People Leader / Business Partner','Executivo Sênior / Alto Performer',
          'Consultor / Coach / Psicólogo'
        ]::text[]);
        v_tipo := 'icp';
        v_chave := 'icp_atual';
        v_scope := 'stable';
        v_action := 'observe';
      elsif v_cat = 'jtbd' then
        continue when v_code is null or v_code !~ '^JT(0[1-9]|1[0-5])$';
        v_canon_label := case v_code
          when 'JT01' then 'Sustentar performance e bem-estar pessoal no longo prazo'
          when 'JT02' then 'Preservar clareza e qualidade de decisão'
          when 'JT03' then 'Navegar pressão, mudança e ambiguidade com adaptabilidade'
          when 'JT04' then 'Desenvolver líderes e gestores'
          when 'JT05' then 'Conduzir conversas difíceis com accountability'
          when 'JT06' then 'Construir segurança psicológica e voz ativa'
          when 'JT07' then 'Estruturar gestão estratégica de bem-estar no trabalho e riscos psicossociais'
          when 'JT08' then 'Traduzir pessoas e bem-estar em business case, dados e influência'
          when 'JT09' then 'Fortalecer engajamento, significado e retenção'
          when 'JT10' then 'Construir cultura adaptativa e resiliência organizacional'
          when 'JT11' then 'Liderar a dimensão humana da IA e do futuro do trabalho'
          when 'JT12' then 'Acessar pares e perspectivas para melhores decisões'
          when 'JT13' then 'Estruturar e vender soluções corporativas'
          when 'JT14' then 'Construir autoridade e credibilidade baseada em ciência'
          when 'JT15' then 'Escalar expertise além do 1:1'
        end;
        continue when v_canon_label is null;
        v_texto := v_canon_label;
        v_tipo := 'jtbd';
        v_chave := 'jtbd:' || v_code;
        continue when v_action not in ('observe','reject','expire');
      else
        v_tipo := case v_cat
          when 'identity' then 'identidade'      when 'role' then 'cargo'
          when 'company' then 'empresa'          when 'goal' then 'objetivo'
          when 'interest' then 'interesse'       when 'preference' then 'preferencia'
          when 'constraint' then 'restricao'     when 'commercial_preference' then 'preferencia_comercial'
          when 'stakeholder' then 'stakeholder'  when 'delegation' then 'delegacao'
          when 'sponsorship' then 'patrocinio'   when 'logistics' then 'logistica'
          else 'outro' end;
        v_chave := case v_tipo
          when 'identidade' then 'identidade'
          when 'cargo'      then 'cargo_atual'
          when 'empresa'    then 'empresa_atual'
          else v_tipo || ':' || public.mind_slug(v_texto) end;
        v_action := 'observe';
      end if;

      if p_analise_id is not null
         and v_evidence_raw ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
        select m.id into v_evidence
        from intelligence.analise_conversa a
        join engagement.mensagens m on m.conversa_id = a.conversa_id
        where a.id = p_analise_id
          and m.id = v_evidence_raw::uuid
          and m.papel = 'lead'
        limit 1;
      end if;

      -- Analise Concierge só persiste memória com uma evidência real da própria pessoa.
      if v_concierge and v_evidence is null then
        continue;
      end if;

      v_num := case v_conf when 'high' then 0.90 when 'medium' then 0.70 else 0.50 end;
      v_status := case
        when v_concierge then
          case when v_conf = 'high' and v_scope in ('stable','opportunity') then 'ativa' else 'proposta' end
        else
          case when v_scope = 'stable' and v_conf = 'high' then 'ativa' else 'proposta' end
      end;

      if v_tipo = 'jtbd' then
        v_valor := jsonb_strip_nulls(jsonb_build_object(
          'code', v_code, 'text', v_texto, 'context', v_context, 'scope', v_scope,
          'evidence_kind', v_evidence_kind, 'sensitivity', nullif(v_sens,'')));
      else
        v_valor := jsonb_strip_nulls(jsonb_build_object(
          'text', v_texto, 'scope', v_scope, 'evidence_kind', v_evidence_kind,
          'sensitivity', nullif(v_sens,'')));
      end if;

      if v_tipo = 'jtbd' and v_action in ('reject','expire') then
        update intelligence.participante_memoria pm
           set status = case v_action when 'reject' then 'rejeitada' else 'expirada' end,
               evidencia_message_id = coalesce(v_evidence, pm.evidencia_message_id),
               analise_conversa_id = coalesce(p_analise_id, pm.analise_conversa_id),
               atualizado_em = now()
         where pm.participante_id = p_participante
           and pm.chave = v_chave
           and pm.status in ('ativa','proposta');
        if found then v_n := v_n + 1; end if;
        continue;
      end if;

      select * into v_exist from intelligence.participante_memoria pm
       where pm.participante_id = p_participante and pm.chave = v_chave
         and pm.status in ('ativa','proposta')
       order by (pm.status = 'ativa') desc, pm.atualizado_em desc nulls last
       limit 1;

      if found then
        if v_exist.valor->>'text' is not distinct from v_texto then
          update intelligence.participante_memoria
             set valor = case when v_concierge then v_valor else valor end,
                 confianca = greatest(coalesce(confianca, 0), v_num),
                 status = case when status = 'ativa' or v_status = 'ativa' then 'ativa' else status end,
                 evidencia_message_id = coalesce(v_evidence, evidencia_message_id),
                 analise_conversa_id = coalesce(p_analise_id, analise_conversa_id),
                 atualizado_em = now()
           where id = v_exist.id;
        elsif v_chave in ('identidade','cargo_atual','empresa_atual','icp_atual') then
          if v_exist.status = 'ativa' and v_status <> 'ativa' then
            null;
          elsif v_exist.status = 'ativa' and v_status = 'ativa' then
            -- O índice permite só uma ativa por chave: nova nasce proposta, antiga sai,
            -- e só então a nova é promovida.
            v_novo := gen_random_uuid();
            insert into intelligence.participante_memoria
              (id, participante_id, tipo, chave, valor, confianca, origem, status,
               evidencia_message_id, analise_conversa_id)
            values (v_novo, p_participante, v_tipo, v_chave, v_valor, v_num, p_analisador, 'proposta',
                    v_evidence, p_analise_id);
            update intelligence.participante_memoria
               set status = 'substituida', substituida_por = v_novo, atualizado_em = now()
             where id = v_exist.id;
            update intelligence.participante_memoria set status = 'ativa', atualizado_em = now()
             where id = v_novo;
            v_n := v_n + 1;
          else
            update intelligence.participante_memoria
               set tipo = v_tipo, valor = v_valor,
                   confianca = greatest(coalesce(confianca,0), v_num),
                   origem = p_analisador, status = v_status,
                   evidencia_message_id = coalesce(v_evidence, evidencia_message_id),
                   analise_conversa_id = coalesce(p_analise_id, analise_conversa_id),
                   atualizado_em = now()
             where id = v_exist.id;
          end if;
        end if;
      else
        insert into intelligence.participante_memoria
          (participante_id, tipo, chave, valor, confianca, origem, status,
           evidencia_message_id, analise_conversa_id)
        values (p_participante, v_tipo, v_chave, v_valor, v_num, p_analisador, v_status,
                v_evidence, p_analise_id);
        v_n := v_n + 1;
      end if;
    exception when others then
      raise warning 'projecao_memoria falhou p/ item: %', sqlerrm;
    end;
  end loop;

  return v_n;
end
$function$;

-- -----------------------------------------------------------------------------
-- 3. Um leitor único para qualquer competência. Ele projeta; não decide prioridade.

create or replace function public.mind_customer_intelligence(p_pessoa_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','public','pessoas','engagement','intelligence','crm'
as $function$
declare
  v_role text; v_company text; v_role_mem text; v_company_mem text; v_hubspot text;
  v_icp_mem text; v_icp_conf numeric; v_icp_updated timestamptz; v_crm_icp text;
  v_jobs jsonb := '[]'::jsonb; v_goals jsonb := '[]'::jsonb;
  v_interests jsonb := '[]'::jsonb; v_preferences jsonb := '[]'::jsonb;
  v_constraints jsonb := '[]'::jsonb; v_stakeholders jsonb := '[]'::jsonb;
  v_delegations jsonb := '[]'::jsonb; v_icp jsonb := null;
begin
  if p_pessoa_id is null then return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa'); end if;

  select p.cargo, p.empresa, p.hubspot_id into v_role, v_company, v_hubspot
  from pessoas.pessoas p where p.id = p_pessoa_id;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'pessoa_nao_encontrada'); end if;

  select pm.valor->>'text' into v_role_mem from intelligence.participante_memoria pm
  where pm.participante_id=p_pessoa_id and pm.tipo='cargo' and pm.chave='cargo_atual'
    and pm.status='ativa' and (pm.valido_ate is null or pm.valido_ate>now())
  order by pm.atualizado_em desc limit 1;

  select pm.valor->>'text' into v_company_mem from intelligence.participante_memoria pm
  where pm.participante_id=p_pessoa_id and pm.tipo='empresa' and pm.chave='empresa_atual'
    and pm.status='ativa' and (pm.valido_ate is null or pm.valido_ate>now())
  order by pm.atualizado_em desc limit 1;

  v_role := coalesce(nullif(v_role_mem,''),nullif(v_role,''));
  v_company := coalesce(nullif(v_company_mem,''),nullif(v_company,''));

  select pm.valor->>'text',pm.confianca,pm.atualizado_em into v_icp_mem,v_icp_conf,v_icp_updated
  from intelligence.participante_memoria pm
  where pm.participante_id=p_pessoa_id and pm.tipo='icp' and pm.chave='icp_atual'
    and pm.status='ativa' and (pm.valido_ate is null or pm.valido_ate>now())
    and pm.valor->>'text'=any(array[
      'CHRO / VP de Pessoas','CEO / C-Suite','Gestor / Middle Manager',
      'People Leader / Business Partner','Executivo Sênior / Alto Performer',
      'Consultor / Coach / Psicólogo']::text[])
  order by pm.atualizado_em desc limit 1;

  if v_icp_mem is null then
    select e.icp into v_crm_icp from crm.contato_espelho e
    where e.hubspot_id=coalesce(
      (select i.identificador from engagement.identidades i
       where i.pessoa_id=p_pessoa_id and i.canal='hubspot'
       order by i.atualizado_em desc nulls last limit 1),v_hubspot)
      and e.icp=any(array[
        'CHRO / VP de Pessoas','CEO / C-Suite','Gestor / Middle Manager',
        'People Leader / Business Partner','Executivo Sênior / Alto Performer',
        'Consultor / Coach / Psicólogo']::text[])
    order by e.atualizado_em desc nulls last limit 1;
  end if;

  if v_icp_mem is not null then
    v_icp:=jsonb_build_object('value',v_icp_mem,'confidence',v_icp_conf,
                              'source','memory','last_seen_at',v_icp_updated);
  elsif v_crm_icp is not null then
    -- icp_confianca histórico está em escalas incompatíveis; não normalizar por palpite.
    v_icp:=jsonb_build_object('value',v_crm_icp,'confidence',null,'source','crm');
  end if;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'code',pm.valor->>'code','label',pm.valor->>'text','context',pm.valor->>'context',
      'confidence',pm.confianca,'scope',pm.valor->>'scope','last_seen_at',pm.atualizado_em))
      order by pm.atualizado_em desc),'[]'::jsonb) into v_jobs
  from intelligence.participante_memoria pm
  where pm.participante_id=p_pessoa_id and pm.tipo='jtbd' and pm.status='ativa'
    and (pm.valido_ate is null or pm.valido_ate>now())
    and pm.valor->>'code' ~ '^JT(0[1-9]|1[0-5])$';

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value',pm.valor->>'text','confidence',pm.confianca,'scope',pm.valor->>'scope',
      'last_seen_at',pm.atualizado_em)) order by pm.atualizado_em desc),'[]'::jsonb) into v_goals
  from intelligence.participante_memoria pm where pm.participante_id=p_pessoa_id
    and pm.tipo='objetivo' and pm.status='ativa' and (pm.valido_ate is null or pm.valido_ate>now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value',pm.valor->>'text','confidence',pm.confianca,'scope',pm.valor->>'scope',
      'last_seen_at',pm.atualizado_em)) order by pm.atualizado_em desc),'[]'::jsonb) into v_interests
  from intelligence.participante_memoria pm where pm.participante_id=p_pessoa_id
    and pm.tipo='interesse' and pm.status='ativa' and (pm.valido_ate is null or pm.valido_ate>now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value',pm.valor->>'text','confidence',pm.confianca,'scope',pm.valor->>'scope',
      'last_seen_at',pm.atualizado_em)) order by pm.atualizado_em desc),'[]'::jsonb) into v_preferences
  from intelligence.participante_memoria pm where pm.participante_id=p_pessoa_id
    and pm.tipo='preferencia' and pm.status='ativa' and (pm.valido_ate is null or pm.valido_ate>now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value',pm.valor->>'text','confidence',pm.confianca,'scope',pm.valor->>'scope',
      'last_seen_at',pm.atualizado_em)) order by pm.atualizado_em desc),'[]'::jsonb) into v_constraints
  from intelligence.participante_memoria pm where pm.participante_id=p_pessoa_id
    and pm.tipo='restricao' and pm.status='ativa' and (pm.valido_ate is null or pm.valido_ate>now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value',pm.valor->>'text','confidence',pm.confianca,'scope',pm.valor->>'scope',
      'last_seen_at',pm.atualizado_em)) order by pm.atualizado_em desc),'[]'::jsonb) into v_stakeholders
  from intelligence.participante_memoria pm where pm.participante_id=p_pessoa_id
    and pm.tipo='stakeholder' and pm.status='ativa' and (pm.valido_ate is null or pm.valido_ate>now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value',pm.valor->>'text','confidence',pm.confianca,'scope',pm.valor->>'scope',
      'last_seen_at',pm.atualizado_em)) order by pm.atualizado_em desc),'[]'::jsonb) into v_delegations
  from intelligence.participante_memoria pm where pm.participante_id=p_pessoa_id
    and pm.tipo='delegacao' and pm.status='ativa' and (pm.valido_ate is null or pm.valido_ate>now());

  return jsonb_build_object(
    'ok',true,'pessoa_id',p_pessoa_id,
    'professional_context',jsonb_strip_nulls(jsonb_build_object('role',v_role,'company',v_company,'icp',v_icp)),
    'jobs_observed',v_jobs,'goals',v_goals,'interests',v_interests,
    'preferences',v_preferences,'constraints',v_constraints,
    'decision_context',jsonb_build_object('stakeholders',v_stakeholders,'delegations',v_delegations,
                                           'relevant_constraints',v_constraints));
end
$function$;

revoke all on function public.mind_customer_intelligence(uuid) from public, anon, authenticated;
grant execute on function public.mind_customer_intelligence(uuid) to service_role;

-- Provider no contrato padrão do Kit Loader.
create or replace function public.mind_kit_customer_intelligence(p_conversa_id uuid, p_necessidade jsonb)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','public','engagement'
as $function$
declare v_pessoa uuid; v_ci jsonb;
begin
  if p_conversa_id is null then return null; end if;
  select c.participante_id into v_pessoa from engagement.conversas c where c.id=p_conversa_id;
  if v_pessoa is null then return null; end if;
  v_ci:=public.mind_customer_intelligence(v_pessoa);
  if coalesce((v_ci->>'ok')::boolean,false) is not true then return null; end if;
  return v_ci-'ok'-'pessoa_id';
end
$function$;

revoke all on function public.mind_kit_customer_intelligence(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.mind_kit_customer_intelligence(uuid,jsonb) to service_role;

-- Bloco opcional: ausência de identidade nunca derruba um Kit.
insert into agentes.kit_blocos(rota,bloco,provider,secao,obrigatorio,ativo)
select r,'customer_intelligence','public.mind_kit_customer_intelligence','structured',false,true
from unnest(array['concierge_summit','cliente_suporte','summit_b2c','summit_b2b']::text[]) r
on conflict(rota,bloco) do update set
  provider=excluded.provider,secao=excluded.secao,obrigatorio=false,ativo=true;

-- -----------------------------------------------------------------------------
-- 4. O perfil rápido do App continua sendo só interesse. Os tipos ricos chegam no Kit.
-- A migration anterior (Passo 5) já criou a função; aqui alteramos só o predicado da
-- memória durável, com guarda para a cadeia falhar se a forma esperada tiver mudado.

do $do$
declare v_def text; v_old text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mindagent_chat_get_context'
    and pg_get_function_identity_arguments(p.oid)='p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text';

  if v_def is null then raise exception 'mindagent_chat_get_context_ausente'; end if;
  if position('and pm.tipo = ''interesse''' in v_def)>0 then return; end if;

  v_old := '    where pm.participante_id = v_session.participante_id' || E'\n' ||
           '      and pm.status = ''ativa''';
  v_new := '    where pm.participante_id = v_session.participante_id' || E'\n' ||
           '      and pm.tipo = ''interesse''' || E'\n' ||
           '      and pm.status = ''ativa''';
  if position(v_old in v_def)=0 then raise exception 'mindagent_chat_get_context_forma_inesperada'; end if;
  execute replace(v_def,v_old,v_new);
end
$do$;

-- -----------------------------------------------------------------------------
-- 5. Analise Concierge aprende a pessoa. ICP gera contexto; nunca gera dor/job sozinho.

update agentes.prompts
set conteudo=$prompt$
ANÁLISE PÓS-CONVERSA — CUSTOMER INTELLIGENCE MIND

FUNÇÃO
Você recebe a conversa completa e seu contexto. Seu trabalho é extrair fatos úteis e não sensíveis para que qualquer agente Mind conheça melhor a mesma pessoa em interações futuras.

Você NÃO responde ao cliente.
Você NÃO escreve follow-up.
Você NÃO decide a próxima mensagem.
Você NÃO decide estratégia comercial.
Você NÃO escolhe produto.
Você NÃO inventa fatos para preencher memória.

EXTRAIA TUDO QUE FOR ÚTIL — SEM TETO ARTIFICIAL
Não limite a dois, cinco ou qualquer número fixo. Extraia todos os fatos úteis realmente sustentados pela conversa, deduplicando conceitos equivalentes.

Priorize:
- identidade quando explicitamente fornecida;
- cargo/função e empresa;
- ICP quando a conversa realmente trouxer evidência profissional suficiente;
- jobs-to-be-done realmente expressos;
- objetivos e resultados desejados;
- interesses de conteúdo;
- problemas/desafios profissionais que quer avançar;
- preferências de formato ou abordagem;
- escolhas, recusas e preferências que ela comunicou;
- conteúdos/palestrantes/experiências que explicitamente quer ver;
- conteúdo que disse ter assistido, perdido ou não conseguido ver;
- restrições práticas relevantes;
- necessidades operacionais não sensíveis;
- stakeholder, delegação ou contexto profissional útil.

FATO, NÃO PSICOLOGIA
Registre fatos observáveis e interpretações semânticas diretamente sustentadas. Não registre julgamento de personalidade, intenção psicológica ou estereótipo de cargo.

Bom:
"sou HRBP"
"preciso desenvolver os gestores que apoio"
"meu time evita conversas difíceis"
"prefiro workshops práticos"

Ruim:
"é insegura"
"CHROs normalmente precisam provar ROI, então este deve ser o job dela"
"perguntou sobre Amy, então o job é segurança psicológica"

EVIDÊNCIA — O VÍNCULO É OBRIGATÓRIO
Cada item do `transcrito` contém `mensagem_id`, `papel` e `conteudo`.
- Todo item emitido em `customer_memory` deve apontar `evidence_message_id` para UMA mensagem de `papel=lead` que sustenta diretamente o fato.
- Nunca use mensagem do agente/sistema como evidência.
- Nunca invente UUID.
- Se não houver mensagem do lead que sustente o item, NÃO emita o item.
- `evidence_kind`: `self_declared`, `explicit_statement`, `role_inference`, `converging_evidence` ou `concrete_choice`.

CRM / CONTEXTO ESTRUTURADO
O contexto pode trazer `crm.icp` e `crm.lead_icp`.
- `crm.icp` usa a taxonomia canônica atual e pode ajudar a interpretar a conversa.
- NÃO emita memória `icp` apenas para copiar o CRM; o leitor já consulta essa fonte.
- `lead_icp` é legado e NÃO participa da classificação de ICP/JTBD.
- Evidência atual da conversa pode confirmar, atualizar ou contradizer o contexto profissional.

ICP — CONTEXTO PROFISSIONAL, NÃO DOR
Use EXATAMENTE um destes valores:
- CHRO / VP de Pessoas
- CEO / C-Suite
- Gestor / Middle Manager
- People Leader / Business Partner
- Executivo Sênior / Alto Performer
- Consultor / Coach / Psicólogo

Pode emitir `category=icp` quando a pessoa se autoidentifica inequivocamente ou cargo/função declarados tornam um dos seis perfis suficientemente claros.

EXEMPLOS DE CARGO/FUNÇÃO INEQUÍVOCOS — CLASSIFIQUE, NÃO DEIXE SÓ COMO `role`:
- HRBP / Human Resources Business Partner / People Business Partner / Business Partner de RH → `People Leader / Business Partner`.
- CHRO / Chief Human Resources Officer / VP de Pessoas / VP de RH → `CHRO / VP de Pessoas`.
- CEO / Chief Executive Officer → `CEO / C-Suite`.
- consultor(a) organizacional/corporativo(a), coach executivo(a) ou psicólogo(a) corporativo(a), quando a pessoa se identifica assim → `Consultor / Coach / Psicólogo`.

Títulos genéricos como "gerente", "diretor", "head", "líder" ou "executivo" podem pertencer a mais de um ICP. Não force classificação sem contexto suficiente.
Quando um cargo inequívoco acima for explicitamente declarado, emita TANTO `role` quanto `icp`.
Use `confidence=high` quando inequívoco; `medium` quando ainda admite ambiguidade.
Para ICP use `scope=stable`, `code=null`, `memory_action=observe`.
NUNCA deduza JTBD porque a pessoa pertence a um ICP.

JTBD — O QUE A PESSOA ESTÁ TENTANDO RESOLVER/REALIZAR
Uma pessoa pode ter vários jobs. Só emita quando a conversa revelar o problema, progresso ou resultado que ela tenta alcançar.

- JT01 — Sustentar performance e bem-estar pessoal no longo prazo: manter alta performance de forma sustentável, com energia/recuperação/longevidade profissional.
- JT02 — Preservar clareza e qualidade de decisão: proteger atenção, nitidez e capacidade cognitiva para decisões relevantes.
- JT03 — Navegar pressão, mudança e ambiguidade com adaptabilidade: permanecer eficaz em incerteza e mudança contínuas.
- JT04 — Desenvolver líderes e gestores: aumentar capacidade real de quem lidera pessoas.
- JT05 — Conduzir conversas difíceis com accountability: cobrar, dar feedback e enfrentar problemas sem evitar conflito nem destruir confiança.
- JT06 — Construir segurança psicológica e voz ativa: criar condições para discordância, pergunta, erro, aprendizagem e verdade organizacional.
- JT07 — Estruturar gestão estratégica de bem-estar no trabalho e riscos psicossociais: transformar bem-estar, NR-1 e riscos psicossociais em gestão real, desenho do trabalho, prevenção e acompanhamento.
- JT08 — Traduzir pessoas e bem-estar em business case, dados e influência: usar evidência, ROI, KPIs e linguagem de negócio para influenciar decisões.
- JT09 — Fortalecer engajamento, significado e retenção: aumentar conexão, contribuição, pertencimento, motivação e permanência.
- JT10 — Construir cultura adaptativa e resiliência organizacional: fazer cultura e sistema de gestão sustentarem estratégia, mudança e performance.
- JT11 — Liderar a dimensão humana da IA e do futuro do trabalho: capturar valor de IA/novas formas de trabalho preservando pessoas, cultura e qualidade de liderança.
- JT12 — Acessar pares e perspectivas para melhores decisões: reduzir isolamento e ampliar perspectiva com pares/benchmark qualificados.
- JT13 — Estruturar e vender soluções corporativas: transformar expertise em solução que empresas entendam, comprem e implementem.
- JT14 — Construir autoridade e credibilidade baseada em ciência: diferenciar-se por profundidade, evidência, curadoria e pensamento próprio.
- JT15 — Escalar expertise além do 1:1: multiplicar impacto/receita por programas, treinamentos, produtos ou outras formas de escala.

Para `category=jtbd`:
- `code` = JT01..JT15;
- `value` = nome canônico;
- `context` = frase curta dizendo COMO o job aparece para esta pessoa, baseada na fala dela;
- `scope` normalmente `opportunity`; `stable` só quando a conversa sustentar desafio profissional durável;
- `confidence=high` quando explícito/inequívoco; `medium` quando hipótese factual útil mas ainda ambígua.

NÃO É EVIDÊNCIA SUFICIENTE PARA JTBD:
- ICP ou cargo isoladamente;
- campanha/origem/página;
- produto comprado no passado;
- tema que apareceu só porque o agente falou;
- recomendação sem adesão;
- pergunta informacional isolada;
- interesse temático isolado.

"Quero muito ver a Amy Edmondson" → interesse em Amy; NÃO basta para JT06.
"Meu time evita trazer problemas e discordar; quero mudar isso" → JT06.
"Tem formação de segurança psicológica?" → interesse/comercial; só é JT06 se a necessidade real aparecer.

CORREÇÃO DE MEMÓRIA JTBD
`memory_action`:
- `observe`: registra/fortalece o job.
- `reject`: somente quando a pessoa corrige explicitamente que o job não a descreve/foi entendido errado.
- `expire`: quando a pessoa diz claramente que era uma necessidade anterior e deixou de valer.
Para `reject`/`expire`, emita o código corrigido e a mensagem do lead que faz a correção. Não use por mera mudança de assunto.

INTERESSE NÃO É JTBD
Interesse diz tema/conteúdo que atrai. JTBD diz o progresso/problema que quer resolver. Preserve ambos quando existirem; nunca promova interesse a job sem evidência.

RECÊNCIA E CONTINUIDADE
- Use a conversa inteira.
- Informação declarada antes continua sendo evidência; não exija repetição.
- Repetição, escolha concreta ou declaração explícita podem elevar confiança.
- Quando um fato muda, priorize o mais recente e explícito.
- Não transforme sugestão do AGENTE em preferência/job se a pessoa não aderiu/escolheu/afirmou.

AGENDA/JORNADA
Não existe fonte sistêmica da Minha Agenda disponível ao Concierge. Extraia apenas escolhas/reservas/presença que a própria pessoa relatou. Nunca inferir porque o agente recomendou.

SENSIBILIDADE — NÃO EMITA COMO CUSTOMER_MEMORY
Nunca registre como memória de personalização saúde pessoal do titular, diagnóstico, medicação, afastamento, saúde de terceiro identificável, religião, opinião política, orientação sexual, origem racial/étnica, filiação sindical, CPF/documento/código de verificação, credenciais de pagamento ou segredos.
Contexto profissional sobre equipe/empresa/mercado não é automaticamente saúde pessoal.
JT01 exige cuidado: meta profissional de sustentabilidade de performance pode ser não sensível; diagnóstico/tratamento/medicação/afastamento/condição de saúde pessoal nunca é memória durável.
Quando acessibilidade puder revelar condição sensível, registre só preferência operacional estritamente necessária se puder ser descrita sem diagnóstico; senão não persista.

CATEGORIAS
identity | role | company | icp | jtbd | goal | interest | preference | constraint | commercial_preference | stakeholder | delegation | sponsorship | logistics | other

SCOPE
stable | opportunity | temporary. `temporary` não vira memória durável.

CONFIDENCE
high = explícito/inequívoco; medium = inferência factual útil e bem sustentada; low = evidência fraca, não force.

SENSITIVITY
none | afastamento_titular | diagnostico_titular | filiacao_sindical | medicacao_titular | opiniao_politica | orientacao_sexual | origem_racial | religiao | saude_de_pessoa_citada | saude_do_titular
Somente `none` pode virar memória durável. Na dúvida, classifique para o lado bloqueado.

OUTPUT — SOMENTE JSON VÁLIDO
{
  "customer_memory": [
    {
      "category": "identity | role | company | icp | jtbd | goal | interest | preference | constraint | commercial_preference | stakeholder | delegation | sponsorship | logistics | other",
      "value": "fato observado ou label canônico",
      "code": "JT01..JT15 ou null",
      "context": "contexto específico da pessoa ou null",
      "evidence_kind": "self_declared | explicit_statement | role_inference | converging_evidence | concrete_choice",
      "evidence_message_id": "UUID exato de uma mensagem do lead",
      "memory_action": "observe | reject | expire",
      "scope": "stable | opportunity | temporary",
      "confidence": "high | medium | low",
      "sensitivity": "none | afastamento_titular | diagnostico_titular | filiacao_sindical | medicacao_titular | opiniao_politica | orientacao_sexual | origem_racial | religiao | saude_de_pessoa_citada | saude_do_titular"
    }
  ]
}
Para categorias não-JTBD: `code=null`; `context` pode ser null; `memory_action=observe`.
Sem fato útil, permitido e sustentado por mensagem do lead: {"customer_memory": []}
$prompt$,
versao=3,
atualizado_em=now()
where chave='analise_concierge' and ativo;

-- -----------------------------------------------------------------------------
-- 6. Regra transversal de consumo: memória não vira prioridade nem intenção de compra.

update agentes.prompts
set conteudo = case
  when conteudo like '%CUSTOMER INTELLIGENCE%' then conteudo
  else conteudo || $base$

CUSTOMER INTELLIGENCE
- Quando o Kit trouxer `customer_intelligence`, use esse bloco como contexto histórico confiável da mesma pessoa para evitar perguntas que ela já respondeu e tornar a conversa mais relevante.
- A fala atual da pessoa sempre vence uma memória anterior em caso de conflito.
- Memória ativa significa contexto confiável, NÃO prioridade atual. Não diga que algo "é a prioridade" da pessoa apenas porque aparece em `jobs_observed`.
- ICP descreve contexto profissional; nunca use ICP para presumir dor, objetivo ou necessidade.
- `jobs_observed` contém problemas/resultados que a pessoa realmente revelou; isso não prova intenção de compra.
- Nunca fale em códigos internos como JT01/JT02 nem exponha a classificação ICP como rótulo técnico para a pessoa. Use o significado para conversar naturalmente.
$base$ end,
versao=greatest(versao,2),
atualizado_em=now()
where chave='base' and ativo;

-- -----------------------------------------------------------------------------
-- 7. A cadeia de pós-conversa é interna. Fecha exposição antiga de SECURITY DEFINER.

revoke all on function public.analise_config() from public, anon, authenticated;
grant execute on function public.analise_config() to service_role;
revoke all on function public.analise_prompt(text) from public, anon, authenticated;
grant execute on function public.analise_prompt(text) to service_role;
revoke all on function public.analise_pendentes(integer) from public, anon, authenticated;
grant execute on function public.analise_pendentes(integer) to service_role;
revoke all on function public.analise_montar_contexto(uuid) from public, anon, authenticated;
grant execute on function public.analise_montar_contexto(uuid) to service_role;
revoke all on function public.analise_gravar(uuid,text,text,text,jsonb,text,integer) from public, anon, authenticated;
grant execute on function public.analise_gravar(uuid,text,text,text,jsonb,text,integer) to service_role;
revoke all on function public.analise_projetar_memoria(uuid,text,jsonb,uuid) from public, anon, authenticated;
grant execute on function public.analise_projetar_memoria(uuid,text,jsonb,uuid) to service_role;

comment on function public.mind_customer_intelligence(uuid) is
'Projecao compartilhada de Customer Intelligence. Le fatos atuais + memoria ativa; nao decide prioridade, produto ou estado comercial.';
comment on function public.mind_kit_customer_intelligence(uuid,jsonb) is
'Provider opcional do Kit Loader para Customer Intelligence da propria pessoa da conversa.';
