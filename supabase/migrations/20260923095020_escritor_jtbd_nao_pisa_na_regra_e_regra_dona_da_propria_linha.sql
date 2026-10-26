-- Escritor da inteligência (analise_projetar_memoria): a memória de JTBD da regra de perfil (origem
-- regra_perfil) não é a casa da conversa. Antes, quando a regra já tinha "jtbd:<code>" para a pessoa,
-- a análise de conversa com o mesmo job atualizava a linha da regra (confiança, status) e a próxima
-- rodada de perfil_projetar apagava a contribuição da conversa. Agora a conversa grava a própria linha
-- (origem analise_*) e, se entra ativa, a linha da regra cede para proposta — perfil_projetar já
-- respeita "existe uma ativa de outra origem". Achado pelo teste tests/perfil_icp_jtbd_contract.sql
-- na revisão de 23/09/2026. Nada mais muda no escritor.

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

      -- a memória da regra de perfil (origem regra_perfil) não é a casa da conversa: para JTBD a
      -- conversa grava a própria linha; a da regra, se estiver ativa, cede (vira proposta) — a regra
      -- respeita "já existe uma ativa de outra origem" e não a promove de novo
      select * into v_exist from intelligence.participante_memoria pm
       where pm.mind_id = p_participante and pm.chave = v_chave
         and pm.status in ('ativa','proposta')
         and (v_tipo <> 'jtbd' or pm.origem <> 'regra_perfil')
       order by (pm.status = 'ativa') desc, pm.atualizado_em desc nulls last
       limit 1;
      if v_tipo = 'jtbd' and v_status = 'ativa' then
        update intelligence.participante_memoria
           set status = 'proposta', atualizado_em = now()
         where mind_id = p_participante and chave = v_chave and status = 'ativa' and origem = 'regra_perfil';
      end if;

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

-- perfil_projetar: a linha da regra é sempre a própria (origem regra_perfil); conversa ativa do mesmo job
-- rebaixa a da regra para proposta em vez de disputar o índice único de ativa.
create or replace function intelligence.perfil_projetar(p_mind uuid, p_gravar boolean default true)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'intelligence', 'engagement', 'pessoas', 'crm', 'credenciamento_summit_2026'
as $function$
declare
  v_cargo text; v_empresa text; v_fonte text;
  v_icp text; v_familia text; v_rotulo text; v_manual text; v_icp_acao text := 'nada'; v_icp_conf numeric := 0.70;
  v_exist intelligence.participante_memoria%rowtype;
  v_valor jsonb; v_status text; v_jtbd jsonb := '[]'::jsonb; v_novas int := 0; v_alteradas int := 0; v_rebaixadas int := 0;
  r record;
begin
  if p_mind is null then return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa'); end if;
  if not exists (select 1 from pessoas.pessoas where id = p_mind and fundida_em is null) then
    return jsonb_build_object('ok', false, 'motivo', 'pessoa_inexistente_ou_fundida');
  end if;

  -- 1. cargo e empresa por prioridade: credenciamento (Yazo) > conversa > espelho HubSpot > pessoa
  select s.cargo, s.empresa, s.fonte into v_cargo, v_empresa, v_fonte from (
    select nullif(btrim(ry."Cargo / Profissão"), '') as cargo, nullif(btrim(ry."Empresa"), '') as empresa, 'credenciamento_yazo' as fonte, 1 as prio
      from credenciamento_summit_2026."Relatorio Yazzo Consolidado" ry where ry.mind_id = p_mind
    union all
    select pm.valor->>'text',
           (select pe.valor->>'text' from intelligence.participante_memoria pe
             where pe.mind_id = p_mind and pe.chave = 'empresa_atual' and pe.status = 'ativa' order by pe.atualizado_em desc limit 1),
           'conversa', 2
      from intelligence.participante_memoria pm
     where pm.mind_id = p_mind and pm.chave = 'cargo_atual' and pm.status = 'ativa' and pm.origem <> 'regra_perfil'
    union all
    select nullif(btrim(c.jobtitle), ''), nullif(btrim(c.company), ''), 'hubspot', 3 from crm.contato_espelho c where c.mind_id = p_mind
    union all
    select nullif(btrim(p.cargo), ''), nullif(btrim(p.empresa), ''), 'pessoa', 4 from pessoas.pessoas p where p.id = p_mind
  ) s where s.cargo is not null order by s.prio limit 1;

  if v_empresa is null then
    select s.empresa into v_empresa from (
      select nullif(btrim(ry."Empresa"), '') as empresa, 1 as prio from credenciamento_summit_2026."Relatorio Yazzo Consolidado" ry where ry.mind_id = p_mind
      union all
      select pe.valor->>'text', 2 from intelligence.participante_memoria pe where pe.mind_id = p_mind and pe.chave = 'empresa_atual' and pe.status = 'ativa'
      union all
      select nullif(btrim(c.company), ''), 3 from crm.contato_espelho c where c.mind_id = p_mind
      union all
      select nullif(btrim(p.empresa), ''), 4 from pessoas.pessoas p where p.id = p_mind
    ) s where s.empresa is not null order by s.prio limit 1;
  end if;

  -- 2. ICP pelo cargo (concorrente pela empresa); cargo que é só um nível ("Gerente") vale menos
  v_icp := intelligence.icp_por_cargo(v_cargo, v_empresa);
  select i.familia, i.rotulo into v_familia, v_rotulo from intelligence.icp i where i.codigo = v_icp;
  if intelligence.texto_chave(v_cargo) ~ '^(gerente|diretor|diretora|coordenador|coordenadora|analista|gestor|gestora|head|lider|socio|socia|consultor|consultora|executivo|executiva|especialista|supervisor|supervisora|empresario|empresaria)$' then
    v_icp_conf := 0.55;
  end if;
  select nullif(e.icp, '') into v_manual from crm.contato_espelho e
   where e.mind_id = p_mind and nullif(e.icp, '') is not null order by e.atualizado_em desc nulls last limit 1;
  -- só é manual o que o Mind não escreveu: o espelho diário devolve o que o próprio write-back gravou
  if v_manual is not null then
    if lower(v_manual) = lower(coalesce((select i.hubspot_valor from intelligence.icp i where i.codigo = v_icp), ''))
       or lower(v_manual) = lower(coalesce((
            select a.after_data->'propriedades'->>'icp'
              from crm.contato_espelho e
              join public.mind_admin_audit a on a.resource = 'hubspot_contato' and a.record_id = e.hubspot_id::text
             where e.mind_id = p_mind and a.after_data->'propriedades' ? 'icp'
             order by a.occurred_at desc limit 1), '')) then
      v_manual := null;
    end if;
  end if;

  if v_icp is not null and p_gravar then
    v_valor := jsonb_strip_nulls(jsonb_build_object('text', v_rotulo, 'code', v_icp, 'scope', 'stable',
                 'evidence_kind', 'cargo_' || v_fonte, 'cargo', v_cargo, 'empresa', v_empresa));
    select * into v_exist from intelligence.participante_memoria pm
     where pm.mind_id = p_mind and pm.chave = 'icp_atual' and pm.status in ('ativa', 'proposta')
     order by (pm.status = 'ativa') desc, pm.atualizado_em desc limit 1;
    if v_manual is not null then
      v_icp_acao := 'hubspot_manual_vence';          -- ICP marcado à mão no HubSpot: a regra não escreve
    elsif not found then
      insert into intelligence.participante_memoria (mind_id, tipo, chave, valor, confianca, origem, status)
      values (p_mind, 'icp', 'icp_atual', v_valor, v_icp_conf, 'regra_perfil', 'ativa');
      v_icp_acao := 'criada'; v_novas := v_novas + 1;
    elsif v_exist.origem = 'regra_perfil' then
      if v_exist.valor is distinct from v_valor or v_exist.confianca is distinct from v_icp_conf then
        update intelligence.participante_memoria set valor = v_valor, confianca = v_icp_conf, atualizado_em = now() where id = v_exist.id;
        v_icp_acao := 'atualizada'; v_alteradas := v_alteradas + 1;
      else
        v_icp_acao := 'inalterada';                  -- igual ao que já está: não carimba atualizado_em
      end if;
    elsif coalesce((select i.codigo from intelligence.icp i where i.rotulo = v_exist.valor->>'text' or i.rotulo_legado = v_exist.valor->>'text' limit 1), '') = v_icp then
      v_icp_acao := 'confirmada_pela_conversa';
    else
      -- a conversa disse outra coisa: a conversa fica ativa; a regra entra como proposta, visível
      if not exists (select 1 from intelligence.participante_memoria pm where pm.mind_id = p_mind and pm.chave = 'icp_atual' and pm.origem = 'regra_perfil') then
        insert into intelligence.participante_memoria (mind_id, tipo, chave, valor, confianca, origem, status)
        values (p_mind, 'icp', 'icp_atual', v_valor, v_icp_conf, 'regra_perfil', 'proposta');
        v_novas := v_novas + 1;
      end if;
      v_icp_acao := 'divergente_da_conversa';
    end if;
  end if;

  -- 3. cargo e empresa do credenciamento viram memória quando o slot está vazio
  if p_gravar and v_fonte = 'credenciamento_yazo' then
    if not exists (select 1 from intelligence.participante_memoria pm where pm.mind_id = p_mind and pm.chave = 'cargo_atual' and pm.status = 'ativa') then
      insert into intelligence.participante_memoria (mind_id, tipo, chave, valor, confianca, origem, status)
      values (p_mind, 'cargo', 'cargo_atual',
              jsonb_build_object('text', intelligence.texto_exibir(v_cargo), 'scope', 'stable', 'evidence_kind', 'credenciamento_yazo'),
              0.80, 'regra_perfil', 'ativa');
      v_novas := v_novas + 1;
    end if;
    if v_empresa is not null and not exists (select 1 from intelligence.participante_memoria pm where pm.mind_id = p_mind and pm.chave = 'empresa_atual' and pm.status = 'ativa') then
      insert into intelligence.participante_memoria (mind_id, tipo, chave, valor, confianca, origem, status)
      values (p_mind, 'empresa', 'empresa_atual',
              jsonb_build_object('text', intelligence.texto_exibir(v_empresa), 'scope', 'stable', 'evidence_kind', 'credenciamento_yazo'),
              0.80, 'regra_perfil', 'ativa');
      v_novas := v_novas + 1;
    end if;
  end if;

  -- 4. JTBD pelas evidências
  --    conf = maior evidência + 0,05 por evidência extra que não seja reserva/contexto (+0,05 no total se houver reserva), teto 0,90;
  --    job organizacional fora dos ICPs típicos do catálogo fica em hipótese (≤ 0,65), salvo fala em conversa.
  for r in
    with ev as (select * from intelligence.perfil_evidencias(p_mind, v_familia)),
    agg as (
      select ev.codigo,
             least(0.90, max(ev.confianca)
                         + 0.05 * greatest(0, (count(*) filter (where ev.evidencia->>'tipo' not in ('reserva', 'contexto'))) - 1)
                         + case when bool_or(ev.evidencia->>'tipo' = 'reserva') then 0.05 else 0 end) as conf,
             bool_or(ev.evidencia->>'tipo' in ('conversa', 'memoria_texto', 'analise_produto', 'analise_patrocinio', 'memoria_patrocinio')) as tem_fala,
             jsonb_agg(ev.evidencia order by ev.confianca desc) as evidencias, count(*) as n
        from ev group by ev.codigo)
    select a.codigo, a.evidencias, a.n, j.rotulo,
           case when j.codigo not in ('liderar_melhor', 'minha_saude_performance', 'encontrar_pares')
                     and v_icp is not null and cardinality(j.icps_tipicos) > 0
                     and not (v_icp = any(j.icps_tipicos)) and not a.tem_fala
                then least(a.conf, 0.65) else a.conf end as conf
      from agg a join intelligence.jtbd j on j.codigo = a.codigo and j.ativo
     order by 5 desc, j.ordem
  loop
    v_status := case when r.conf >= 0.70 then 'ativa' else 'proposta' end;
    v_valor := jsonb_build_object('code', r.codigo, 'text', r.rotulo, 'scope', 'stable', 'evidence_kind', 'regra_perfil', 'evidencias', r.evidencias);
    v_jtbd := v_jtbd || jsonb_build_object('code', r.codigo, 'confianca', r.conf, 'status', v_status, 'evidencias', r.n);
    if p_gravar then
      -- a linha da regra é a própria (origem regra_perfil); memória de conversa do mesmo job é outra linha e,
      -- se estiver ativa, vence: a da regra fica como proposta
      select * into v_exist from intelligence.participante_memoria pm
       where pm.mind_id = p_mind and pm.chave = 'jtbd:' || r.codigo and pm.status in ('ativa', 'proposta') and pm.origem = 'regra_perfil'
       order by (pm.status = 'ativa') desc, pm.atualizado_em desc limit 1;
      if v_status = 'ativa' and exists (select 1 from intelligence.participante_memoria pm
           where pm.mind_id = p_mind and pm.chave = 'jtbd:' || r.codigo and pm.status = 'ativa' and pm.origem <> 'regra_perfil') then
        v_status := 'proposta';   -- já existe uma ativa de outra origem (conversa)
      end if;
      if not found then
        insert into intelligence.participante_memoria (mind_id, tipo, chave, valor, confianca, origem, status)
        values (p_mind, 'jtbd', 'jtbd:' || r.codigo, v_valor, r.conf, 'regra_perfil', v_status);
        v_novas := v_novas + 1;
      else
        -- a regra segue o recálculo: pode rebaixar o que ela mesma promoveu
        if v_exist.valor is distinct from v_valor or v_exist.confianca is distinct from r.conf or v_exist.status is distinct from v_status then
          update intelligence.participante_memoria
             set valor = v_valor, confianca = r.conf, status = v_status, atualizado_em = now()
           where id = v_exist.id;
          v_alteradas := v_alteradas + 1;
        end if;
      end if;
    end if;
  end loop;

  -- evidência que sumiu (sessão remarcada, regra apertada): ativa da regra sem evidência atual vira hipótese
  if p_gravar then
    update intelligence.participante_memoria pm set status = 'proposta', atualizado_em = now()
     where pm.mind_id = p_mind and pm.tipo = 'jtbd' and pm.origem = 'regra_perfil' and pm.status = 'ativa'
       and not exists (select 1 from jsonb_array_elements(v_jtbd) j where 'jtbd:' || (j->>'code') = pm.chave);
    get diagnostics v_rebaixadas = row_count;
  end if;

  return jsonb_build_object('ok', true, 'mind_id', p_mind, 'cargo', v_cargo, 'empresa', v_empresa, 'fonte_cargo', v_fonte,
                            'icp', v_icp, 'icp_confianca', v_icp_conf, 'icp_acao', v_icp_acao, 'icp_manual_hubspot', v_manual,
                            'jtbd', v_jtbd, 'memorias_novas', v_novas, 'memorias_alteradas', v_alteradas, 'memorias_rebaixadas', v_rebaixadas, 'gravou', p_gravar);
end $function$;
comment on function intelligence.perfil_projetar(uuid, boolean) is 'Projeta ICP (pelo cargo; 0,55 quando o cargo é só um nível), cargo/empresa (do credenciamento) e JTBD (pelas evidências, com veto por ICP típico e rebaixamento do que perdeu evidência) nas memórias da pessoa, origem regra_perfil. Só grava o que mudou — atualizado_em é o sinal do write-back horário. Nunca sobrescreve memória de conversa; ICP manual do HubSpot vence, mas o que o próprio Mind escreveu lá não é manual.';
