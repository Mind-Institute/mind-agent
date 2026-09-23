-- Escritor e leitor da inteligência da pessoa passam a validar ICP e JTBD pelos catálogos
-- intelligence.icp / intelligence.jtbd em vez de listas fixas no corpo (23/09/2026).
-- Escritor (analise_projetar_memoria): aceita o rótulo atual, o legado das 6 opções antigas ou o
--   código; grava sempre o rótulo atual. JTBD aceita JT01–JT15 e os jobs "mind".
-- Leitor (mind_customer_intelligence): devolve o rótulo canônico e o code do ICP; o fallback do
--   CRM traduz o valor da propriedade icp do HubSpot pelo catálogo; jobs_observed aceita qualquer
--   código do catálogo.

CREATE OR REPLACE FUNCTION public.analise_projetar_memoria(p_participante uuid, p_analisador text, p_memorias jsonb, p_analise_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'intelligence', 'engagement'
AS $function$
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
        -- rótulo vem do catálogo intelligence.icp (o atual ou o legado das 6 opções antigas); grava sempre o atual
        select i.rotulo into v_canon_label from intelligence.icp i
         where i.ativo and (i.rotulo = v_texto or i.rotulo_legado = v_texto or i.codigo = v_texto)
         order by (i.rotulo = v_texto) desc limit 1;
        continue when v_canon_label is null;
        v_texto := v_canon_label;
        v_tipo := 'icp';
        v_chave := 'icp_atual';
        v_scope := 'stable';
        v_action := 'observe';
      elsif v_cat = 'jtbd' then
        -- código vem do catálogo intelligence.jtbd (JT01–JT15 do estudo ou um job "mind")
        continue when v_code is null;
        select j.codigo, j.rotulo into v_code, v_canon_label from intelligence.jtbd j
         where j.ativo and (j.codigo = v_code or upper(j.codigo) = v_code) limit 1;
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

      -- ICP MEDIUM OCUPA SLOT VAZIO (03/09). Sem ICP ativo, a inferência medium
      -- é o melhor que sabemos e entra ativa com a confiança exposta pelo leitor.
      -- Com ICP ativo, continua valendo a regra do Passo 4: medium não derruba.
      if v_tipo = 'icp' and v_conf = 'medium' and not exists (
           select 1 from intelligence.participante_memoria pm
            where pm.mind_id = p_participante
              and pm.chave = 'icp_atual' and pm.status = 'ativa') then
        v_status := 'ativa';
      end if;

      if v_tipo = 'jtbd' then
        v_valor := jsonb_strip_nulls(jsonb_build_object(
          'code', v_code,
          'text', v_texto,
          'context', v_context,
          'scope', v_scope,
          'evidence_kind', v_evidence_kind,
          'sensitivity', nullif(v_sens,'')));
      elsif v_tipo = 'icp' then
        v_valor := jsonb_strip_nulls(jsonb_build_object(
          'text', v_texto,
          'scope', v_scope,
          'evidence_kind', v_evidence_kind,
          'sensitivity', nullif(v_sens,'')));
      else
        v_valor := jsonb_strip_nulls(jsonb_build_object(
          'text', v_texto,
          'scope', v_scope,
          'evidence_kind', v_evidence_kind,
          'sensitivity', nullif(v_sens,'')));
      end if;

      if v_tipo = 'jtbd' and v_action in ('reject','expire') then
        update intelligence.participante_memoria pm
           set status = case v_action when 'reject' then 'rejeitada' else 'expirada' end,
               evidencia_message_id = coalesce(v_evidence, pm.evidencia_message_id),
               analise_conversa_id = coalesce(p_analise_id, pm.analise_conversa_id),
               atualizado_em = now()
         where pm.mind_id = p_participante
           and pm.chave = v_chave
           and pm.status in ('ativa','proposta');
        if found then v_n := v_n + 1; end if;
        continue;
      end if;

      select * into v_exist from intelligence.participante_memoria pm
       where pm.mind_id = p_participante and pm.chave = v_chave
         and pm.status in ('ativa','proposta')
       order by (pm.status = 'ativa') desc, pm.atualizado_em desc nulls last
       limit 1;

      if found then
        if v_exist.valor->>'text' is not distinct from v_texto then
          update intelligence.participante_memoria
             set valor               = case when v_concierge then v_valor else valor end,
                 confianca           = greatest(coalesce(confianca, 0), v_num),
                 status              = case when status = 'ativa' or v_status = 'ativa'
                                            then 'ativa' else status end,
                 evidencia_message_id = coalesce(v_evidence, evidencia_message_id),
                 analise_conversa_id = coalesce(p_analise_id, analise_conversa_id),
                 atualizado_em       = now()
           where id = v_exist.id;
        elsif v_chave in ('identidade','cargo_atual','empresa_atual','icp_atual') then
          if v_exist.status = 'ativa' and v_status <> 'ativa' then
            null;
          elsif v_exist.status = 'ativa' and v_status = 'ativa' then
            v_novo := gen_random_uuid();
            insert into intelligence.participante_memoria
              (id, mind_id, tipo, chave, valor, confianca, origem, status,
               evidencia_message_id, analise_conversa_id)
            values (v_novo, p_participante, v_tipo, v_chave, v_valor, v_num, p_analisador, 'proposta',
                    v_evidence, p_analise_id);
            update intelligence.participante_memoria
               set status = 'substituida', substituida_por = v_novo, atualizado_em = now()
             where id = v_exist.id;
            update intelligence.participante_memoria
               set status = 'ativa', atualizado_em = now()
             where id = v_novo;
            v_n := v_n + 1;
          else
            update intelligence.participante_memoria
               set tipo = v_tipo,
                   valor = v_valor,
                   confianca = greatest(coalesce(confianca,0), v_num),
                   origem = p_analisador,
                   status = v_status,
                   evidencia_message_id = coalesce(v_evidence, evidencia_message_id),
                   analise_conversa_id = coalesce(p_analise_id, analise_conversa_id),
                   atualizado_em = now()
             where id = v_exist.id;
          end if;
        end if;
      else
        insert into intelligence.participante_memoria
          (mind_id, tipo, chave, valor, confianca, origem, status,
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

CREATE OR REPLACE FUNCTION public.mind_customer_intelligence(p_pessoa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pessoas', 'engagement', 'intelligence', 'crm'
AS $function$
declare
  v_role text; v_company text; v_role_mem text; v_company_mem text; v_hubspot text;
  v_icp_mem text; v_icp_conf numeric; v_icp_updated timestamptz; v_crm_icp text; v_icp_code text;
  v_jobs jsonb := '[]'::jsonb;
  v_goals jsonb := '[]'::jsonb;
  v_interests jsonb := '[]'::jsonb;
  v_preferences jsonb := '[]'::jsonb;
  v_constraints jsonb := '[]'::jsonb;
  v_stakeholders jsonb := '[]'::jsonb;
  v_delegations jsonb := '[]'::jsonb;
  v_icp jsonb := null;
begin
  if p_pessoa_id is null then return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa'); end if;

  select p.cargo, p.empresa, p.hubspot_id into v_role, v_company, v_hubspot
  from pessoas.pessoas p where p.id = p_pessoa_id;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'pessoa_nao_encontrada'); end if;

  select pm.valor->>'text' into v_role_mem from intelligence.participante_memoria pm
  where pm.mind_id = p_pessoa_id and pm.tipo = 'cargo' and pm.chave = 'cargo_atual'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now())
  order by pm.atualizado_em desc limit 1;

  select pm.valor->>'text' into v_company_mem from intelligence.participante_memoria pm
  where pm.mind_id = p_pessoa_id and pm.tipo = 'empresa' and pm.chave = 'empresa_atual'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now())
  order by pm.atualizado_em desc limit 1;

  v_role := coalesce(nullif(v_role_mem,''), nullif(v_role,''));
  v_company := coalesce(nullif(v_company_mem,''), nullif(v_company,''));

  -- rótulo canônico vem do catálogo intelligence.icp (aceita o texto atual, o legado ou o código)
  select i.rotulo, pm.confianca, pm.atualizado_em, i.codigo into v_icp_mem, v_icp_conf, v_icp_updated, v_icp_code
  from intelligence.participante_memoria pm
  join intelligence.icp i on i.ativo and (i.rotulo = pm.valor->>'text' or i.rotulo_legado = pm.valor->>'text' or i.codigo = pm.valor->>'code')
  where pm.mind_id = p_pessoa_id and pm.tipo = 'icp' and pm.chave = 'icp_atual'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now())
  order by pm.atualizado_em desc limit 1;

  if v_icp_mem is null then
    select ic.rotulo, ic.codigo into v_crm_icp, v_icp_code from crm.contato_espelho e
    join intelligence.icp ic on ic.ativo and (ic.hubspot_valor = e.icp or ic.rotulo = e.icp)
    where e.hubspot_id = coalesce(
      (select i.identificador from engagement.identidades i
        where i.mind_id = p_pessoa_id and i.canal = 'hubspot'
        order by i.criado_em desc nulls last limit 1), v_hubspot)
    order by e.atualizado_em desc nulls last limit 1;
  end if;

  if v_icp_mem is not null then
    v_icp := jsonb_build_object('value', v_icp_mem, 'code', v_icp_code, 'confidence', v_icp_conf,
                                'source', 'memory', 'last_seen_at', v_icp_updated);
  elsif v_crm_icp is not null then
    v_icp := jsonb_build_object('value', v_crm_icp, 'code', v_icp_code, 'confidence', null, 'source', 'crm');
  end if;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'code', pm.valor->>'code', 'label', pm.valor->>'text', 'context', pm.valor->>'context',
      'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_jobs
  from intelligence.participante_memoria pm
  where pm.mind_id = p_pessoa_id and pm.tipo = 'jtbd' and pm.status = 'ativa'
    and (pm.valido_ate is null or pm.valido_ate > now())
    and exists (select 1 from intelligence.jtbd j where j.ativo and j.codigo = pm.valor->>'code');

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value', pm.valor->>'text', 'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_goals
  from intelligence.participante_memoria pm where pm.mind_id = p_pessoa_id and pm.tipo = 'objetivo'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value', pm.valor->>'text', 'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_interests
  from intelligence.participante_memoria pm where pm.mind_id = p_pessoa_id and pm.tipo = 'interesse'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value', pm.valor->>'text', 'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_preferences
  from intelligence.participante_memoria pm where pm.mind_id = p_pessoa_id and pm.tipo = 'preferencia'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value', pm.valor->>'text', 'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_constraints
  from intelligence.participante_memoria pm where pm.mind_id = p_pessoa_id and pm.tipo = 'restricao'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value', pm.valor->>'text', 'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_stakeholders
  from intelligence.participante_memoria pm where pm.mind_id = p_pessoa_id and pm.tipo = 'stakeholder'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value', pm.valor->>'text', 'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_delegations
  from intelligence.participante_memoria pm where pm.mind_id = p_pessoa_id and pm.tipo = 'delegacao'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now());

  return jsonb_build_object(
    'ok', true, 'pessoa_id', p_pessoa_id,
    'professional_context', jsonb_strip_nulls(jsonb_build_object('role', v_role, 'company', v_company, 'icp', v_icp)),
    'jobs_observed', v_jobs, 'goals', v_goals, 'interests', v_interests,
    'preferences', v_preferences, 'constraints', v_constraints,
    'decision_context', jsonb_build_object('stakeholders', v_stakeholders, 'delegations', v_delegations,
                                           'relevant_constraints', v_constraints));
end
$function$;
