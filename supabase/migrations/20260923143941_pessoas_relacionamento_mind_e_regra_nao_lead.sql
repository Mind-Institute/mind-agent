-- =====================================================================================
-- Relacionamento da pessoa com o Mind e a regra "quem não é lead não tem ICP nem JTBD"
-- (pedido da Adriana, 23/09/2026: "Limpa ICP e JTBD de staff e palestrante do HubSpot e backend e
-- escrever regra: se é professor ou parceiro de venda não é lead e portanto não coletamos JTBD e ICP.
-- Pode ver se é professor na tabela onde eles estão listados (ecossistema) e guardar em pessoas.pessoas
-- uma coluna com o tipo de relacionamento com o Mind.")
--
-- 1. pessoas.pessoas.relacionamento_mind text[]: {lead} por padrão; staff, palestrante, professor e
--    parceiro_venda quando não é lead — pode ter mais de um (a professora que também palestra).
-- 2. pessoas.relacionamento_derivado(): de onde vem cada tipo, só por vínculo determinístico (mind_id):
--    staff       = credenciamento (staff_mind), e-mail @joinmind.com.br, seguranca.equipe, mind_admin_users;
--    palestrante = credenciamento (palestrante), ecossistema.perfis_publicos ligado a palestrantes_especialistas;
--    professor   = institute.programa_pessoas (formadora, curadoria, convidado) — o time do Institute que o
--                  site publica pelo schema ecossistema;
--    parceiro_venda = sem fonte no banco hoje: marca-se à mão na coluna.
-- 3. pessoas.relacionamento_atualizar(): só acrescenta tipos (nunca tira o que alguém marcou); "lead" sai
--    quando entra outro tipo. Roda de hora em hora no começo de intelligence.perfil_projetar_todos.
-- 4. A regra: perfil_projetar apaga a própria classificação e rejeita a de conversa; o escritor de conversa
--    ignora icp/jtbd; o plano do HubSpot manda limpar icp, icp_confianca, jtbd e o resumo (nao_lead);
--    o leitor do Agent não devolve ICP nem jobs.
-- =====================================================================================

set local lock_timeout = '5s';

-- 1. coluna
alter table pessoas.pessoas add column if not exists relacionamento_mind text[] not null default '{lead}'::text[];
alter table pessoas.pessoas drop constraint if exists pessoas_relacionamento_mind_valido;
alter table pessoas.pessoas add constraint pessoas_relacionamento_mind_valido check (
  cardinality(relacionamento_mind) >= 1
  and relacionamento_mind <@ array['lead', 'staff', 'palestrante', 'professor', 'parceiro_venda']::text[]
  and (cardinality(relacionamento_mind) = 1 or not ('lead' = any(relacionamento_mind))));
comment on column pessoas.pessoas.relacionamento_mind is 'Tipo de relacionamento da pessoa com o Mind: {lead} (padrão) ou um ou mais de staff, palestrante, professor, parceiro_venda. Quem não é lead não tem ICP nem JTBD coletados (regra da Adriana, 23/09/2026). Mantida por pessoas.relacionamento_atualizar() a partir das fontes (só acrescenta); parceiro_venda e correções se marcam à mão aqui.';

-- 2. helpers
create or replace function pessoas.e_lead(p_mind uuid)
returns boolean language sql stable security definer
set search_path to 'pg_catalog', 'public'
as $fn$
  select coalesce((select 'lead' = any(p.relacionamento_mind) from pessoas.pessoas p where p.id = p_mind), true);
$fn$;
revoke execute on function pessoas.e_lead(uuid) from public, anon, authenticated;
comment on function pessoas.e_lead(uuid) is 'true quando a pessoa é lead (pessoas.relacionamento_mind contém lead) ou não existe; false para staff, palestrante, professor e parceiro de venda — que não têm ICP nem JTBD.';

create or replace function pessoas.relacionamento_derivado()
returns table (mind_id uuid, tipo text, fonte text)
language sql stable security definer
set search_path to 'pg_catalog', 'public'
as $fn$
  select c.mind_id, 'staff'::text, 'credenciamento_summit_2026.controle_de_inscritos_e_presenca.staff_mind'::text
    from credenciamento_summit_2026.controle_de_inscritos_e_presenca c where c.staff_mind and c.mind_id is not null
  union
  select i.mind_id, 'staff', 'engagement.identidades: e-mail @joinmind.com.br'
    from engagement.identidades i where i.canal = 'email' and lower(i.identificador) like '%@joinmind.com.br'
  union
  select i.mind_id, 'staff', 'seguranca.equipe'
    from seguranca.equipe e join engagement.identidades i on i.canal = 'auth_user' and i.identificador = e.user_id::text
  union
  select i.mind_id, 'staff', 'public.mind_admin_users'
    from public.mind_admin_users u join engagement.identidades i on i.canal = 'auth_user' and i.identificador = u.user_id::text
   where u.active
  union
  select c.mind_id, 'palestrante', 'credenciamento_summit_2026.controle_de_inscritos_e_presenca.palestrante'
    from credenciamento_summit_2026.controle_de_inscritos_e_presenca c where c.palestrante and c.mind_id is not null
  union
  select pf.mind_id, 'palestrante', 'ecossistema.perfis_publicos → palestrantes_especialistas'
    from ecossistema.perfis_publicos pf where pf.mind_id is not null and pf.palestrante_especialista_id is not null
  union
  select pp.mind_id, 'professor', 'institute.programa_pessoas (' || coalesce(pp.papel, '?') || ')'
    from institute.programa_pessoas pp where pp.mind_id is not null
$fn$;
revoke execute on function pessoas.relacionamento_derivado() from public, anon, authenticated;
comment on function pessoas.relacionamento_derivado() is 'De onde vem cada tipo de relacionamento com o Mind (só vínculos por mind_id, nunca por nome): staff (credenciamento staff_mind, e-mail @joinmind.com.br, seguranca.equipe, mind_admin_users), palestrante (credenciamento palestrante, ecossistema.perfis_publicos de palestrantes_especialistas), professor (institute.programa_pessoas). Parceiro de venda não tem fonte no banco: marca-se à mão em pessoas.pessoas.relacionamento_mind.';

create or replace function pessoas.relacionamento_atualizar(p_gravar boolean default true)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public'
as $fn$
declare v_alteradas int := 0;
begin
  if p_gravar then
    with der as (
      select d.mind_id, array_agg(distinct d.tipo) as tipos from pessoas.relacionamento_derivado() d group by d.mind_id),
    base as (
      select p.id,
             array(select distinct t from unnest(array_remove(p.relacionamento_mind, 'lead') || coalesce(der.tipos, '{}'::text[])) t order by t) as nao_lead
        from pessoas.pessoas p left join der on der.mind_id = p.id
       where p.fundida_em is null and (der.mind_id is not null or p.relacionamento_mind <> '{lead}'::text[])),
    alvo as (select id, case when cardinality(nao_lead) = 0 then '{lead}'::text[] else nao_lead end as novo from base)
    update pessoas.pessoas p set relacionamento_mind = a.novo, atualizado_em = now()
      from alvo a where a.id = p.id and p.relacionamento_mind is distinct from a.novo;
    get diagnostics v_alteradas = row_count;
  else
    with der as (
      select d.mind_id, array_agg(distinct d.tipo) as tipos from pessoas.relacionamento_derivado() d group by d.mind_id),
    base as (
      select p.id, p.relacionamento_mind as atual,
             array(select distinct t from unnest(array_remove(p.relacionamento_mind, 'lead') || coalesce(der.tipos, '{}'::text[])) t order by t) as nao_lead
        from pessoas.pessoas p left join der on der.mind_id = p.id
       where p.fundida_em is null and (der.mind_id is not null or p.relacionamento_mind <> '{lead}'::text[]))
    select count(*) into v_alteradas from base
     where atual is distinct from (case when cardinality(nao_lead) = 0 then '{lead}'::text[] else nao_lead end);
  end if;
  return jsonb_build_object('alteradas', v_alteradas, 'gravou', p_gravar,
    'por_tipo', (select jsonb_object_agg(t, n) from (select t, count(*) as n from pessoas.pessoas p, unnest(p.relacionamento_mind) t
                                                      where p.fundida_em is null group by t) x));
end $fn$;
revoke execute on function pessoas.relacionamento_atualizar(boolean) from public, anon, authenticated;
comment on function pessoas.relacionamento_atualizar(boolean) is 'Acrescenta a pessoas.relacionamento_mind os tipos que as fontes indicam (pessoas.relacionamento_derivado) e tira "lead" de quem ganhou outro tipo. Nunca remove um tipo: correção e parceiro_venda se fazem à mão na coluna. Roda de hora em hora dentro de intelligence.perfil_projetar_todos.';

-- 3. a regra nas funções do perfil
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
  v_nao_lead boolean;
  v_achou boolean;
begin
  if p_participante is null or jsonb_typeof(p_memorias) <> 'array' then return 0; end if;

  v_concierge := (p_analisador = 'analise_concierge');
  -- quem não é lead (staff, palestrante, professor, parceiro de venda) não tem ICP nem JTBD coletados (23/09)
  v_nao_lead := not pessoas.e_lead(p_participante);

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
      continue when v_nao_lead and v_cat in ('icp', 'jtbd');

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
      v_achou := found;   -- guardado antes do update abaixo, que sobrescreve FOUND (corrige 095020)
      if v_tipo = 'jtbd' and v_status = 'ativa' then
        update intelligence.participante_memoria
           set status = 'proposta', atualizado_em = now()
         where mind_id = p_participante and chave = v_chave and status = 'ativa' and origem = 'regra_perfil';
      end if;

      if v_achou then
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
  v_rel text[]; v_apagadas int := 0; v_rejeitadas int := 0;
  r record;
begin
  if p_mind is null then return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa'); end if;
  if not exists (select 1 from pessoas.pessoas where id = p_mind and fundida_em is null) then
    return jsonb_build_object('ok', false, 'motivo', 'pessoa_inexistente_ou_fundida');
  end if;

  -- 0. quem não é lead (staff, palestrante, professor, parceiro de venda) não tem ICP nem JTBD — regra da
  --    Adriana, 23/09/2026: a classificação da regra é apagada e a de conversa vira rejeitada; cargo e
  --    empresa ficam como estão (são fato, não classificação)
  select p.relacionamento_mind into v_rel from pessoas.pessoas p where p.id = p_mind;
  if not ('lead' = any(v_rel)) then
    if p_gravar then
      update intelligence.participante_memoria pm set substituida_por = null
       where pm.substituida_por in (select x.id from intelligence.participante_memoria x
                                     where x.mind_id = p_mind and x.tipo in ('icp', 'jtbd') and x.origem = 'regra_perfil');
      delete from intelligence.participante_memoria pm
       where pm.mind_id = p_mind and pm.tipo in ('icp', 'jtbd') and pm.origem = 'regra_perfil';
      get diagnostics v_apagadas = row_count;
      update intelligence.participante_memoria pm set status = 'rejeitada', atualizado_em = now()
       where pm.mind_id = p_mind and pm.tipo in ('icp', 'jtbd') and pm.status in ('ativa', 'proposta');
      get diagnostics v_rejeitadas = row_count;
    end if;
    return jsonb_build_object('ok', true, 'mind_id', p_mind, 'nao_e_lead', true, 'relacionamento', to_jsonb(v_rel),
                              'icp', null, 'jtbd', '[]'::jsonb, 'memorias_apagadas', v_apagadas,
                              'memorias_rejeitadas', v_rejeitadas, 'gravou', p_gravar);
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
comment on function intelligence.perfil_projetar(uuid, boolean) is 'Projeta ICP (pelo cargo; 0,55 quando o cargo é só um nível), cargo/empresa (do credenciamento) e JTBD (pelas evidências, com veto por ICP típico e rebaixamento do que perdeu evidência) nas memórias da pessoa, origem regra_perfil. Quem não é lead (pessoas.relacionamento_mind sem lead: staff, palestrante, professor, parceiro de venda) não tem ICP nem JTBD: a classificação da regra é apagada e a de conversa rejeitada. Só grava o que mudou — atualizado_em é o sinal do write-back horário. Nunca sobrescreve memória de conversa de lead; ICP manual do HubSpot vence, mas o que o próprio Mind escreveu lá não é manual.';

create or replace function intelligence.perfil_projetar_todos(p_gravar boolean default true)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'intelligence'
as $fn$
declare v jsonb := '[]'::jsonb; p text; r jsonb; v_pessoas int := 0; v_ini timestamptz := clock_timestamp(); v_rel jsonb;
begin
  -- primeiro o relacionamento com o Mind: quem deixou de ser lead não recebe ICP/JTBD nesta rodada
  v_rel := pessoas.relacionamento_atualizar(p_gravar);
  foreach p in array array['0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'] loop
    r := intelligence.perfil_projetar_lote(p, p_gravar);
    v := v || r;
    v_pessoas := v_pessoas + coalesce((r->>'pessoas')::int, 0);
  end loop;
  return jsonb_build_object('pessoas', v_pessoas, 'gravou', p_gravar, 'relacionamento', v_rel,
                            'segundos', round(extract(epoch from clock_timestamp() - v_ini)::numeric, 1), 'fatias', v);
end $fn$;
revoke execute on function intelligence.perfil_projetar_todos(boolean) from public, anon, authenticated;
comment on function intelligence.perfil_projetar_todos(boolean) is 'Atualiza pessoas.relacionamento_mind e reprojeta o perfil (ICP, cargo/empresa, JTBD) de todas as pessoas com evidência, nas 16 fatias de perfil_projetar_lote. Só toca memória que mudou. Roda no cron horário (hh:36) antes do write-back do HubSpot (hh:41).';

drop function if exists public.mind_hubspot_perfil_plano(timestamptz);
create or replace function public.mind_hubspot_perfil_plano(p_desde timestamptz default null)
returns table (mind_id uuid, hubspot_id text, email text, jobtitle text, company text, icp text, icp_confianca numeric, jtbd text[], resumo text, ultimo_escrito jsonb, fontes jsonb, nao_lead boolean)
language sql stable security definer
set search_path to 'pg_catalog', 'public'
as $fn$
  with yazo as (
    select r.mind_id, max(nullif(btrim(r."Cargo / Profissão"), '')) as cargo, max(nullif(btrim(r."Empresa"), '')) as empresa
      from credenciamento_summit_2026."Relatorio Yazzo Consolidado" r where r.mind_id is not null group by r.mind_id),
  emp as (
    select intelligence.texto_chave(empresa, true) as chave, mode() within group (order by intelligence.texto_exibir(empresa)) as exibir
      from yazo where empresa is not null group by 1),
  icp as (
    select distinct on (pm.mind_id) pm.mind_id, i.hubspot_valor, i.rotulo, pm.confianca
      from intelligence.participante_memoria pm
      join intelligence.icp i on i.ativo and i.hubspot_opcao and i.hubspot_valor is not null
       and (i.rotulo = pm.valor->>'text' or i.rotulo_legado = pm.valor->>'text' or i.codigo = pm.valor->>'code')
     where pm.tipo = 'icp' and pm.chave = 'icp_atual' and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now())
     order by pm.mind_id, pm.atualizado_em desc),
  jt as (
    select pm.mind_id, array_agg(distinct j.hubspot_valor) as valores
      from intelligence.participante_memoria pm
      join intelligence.jtbd j on j.ativo and j.hubspot_opcao and j.hubspot_valor is not null and j.codigo = pm.valor->>'code'
     where pm.tipo = 'jtbd' and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now())
     group by pm.mind_id),
  nl as (
    -- quem não é lead (staff, palestrante, professor, parceiro de venda — pessoas.relacionamento_mind): cargo e
    -- empresa vão; ICP, JTBD e resumo não, e o que estiver no HubSpot a função limpa (nao_lead = true)
    select p.id as mind_id, p.relacionamento_mind from pessoas.pessoas p
     where p.fundida_em is null and not ('lead' = any(p.relacionamento_mind))),
  universo as (select mind_id from yazo union select mind_id from icp union select mind_id from jt union select mind_id from nl),
  mudou as (
    select distinct pm.mind_id from intelligence.participante_memoria pm
     where p_desde is not null and pm.tipo in ('icp', 'jtbd', 'cargo', 'empresa') and pm.atualizado_em >= p_desde
    union
    select p.id from pessoas.pessoas p
     where p_desde is not null and p.atualizado_em >= p_desde and not ('lead' = any(p.relacionamento_mind))),
  contato as (
    select distinct on (c.mind_id) c.mind_id, c.hubspot_id, lower(btrim(c.email)) as email
      from crm.contato_espelho c where c.mind_id is not null order by c.mind_id, c.atualizado_em desc nulls last),
  ult as (
    select distinct on (a.record_id) a.record_id as hubspot_id, a.after_data->'propriedades' as props
      from public.mind_admin_audit a where a.resource = 'hubspot_contato'
     order by a.record_id, a.occurred_at desc)
  select u.mind_id, ct.hubspot_id,
         coalesce(ct.email,
                  (select i.identificador from engagement.identidades i where i.mind_id = u.mind_id and i.canal = 'email' order by i.criado_em limit 1),
                  lower(p.email)) as email,
         intelligence.texto_exibir(y.cargo) as jobtitle,
         e.exibir as company,
         case when nl.mind_id is null then icp.hubspot_valor end as icp,
         case when nl.mind_id is null and icp.confianca is not null then round(icp.confianca * 10) end as icp_confianca,
         case when nl.mind_id is null then coalesce(jt.valores, '{}'::text[]) else '{}'::text[] end as jtbd,
         case when nl.mind_id is null then intelligence.perfil_resumo(u.mind_id) end as resumo,
         ult.props as ultimo_escrito,
         jsonb_strip_nulls(jsonb_build_object('cargo_yazo', y.cargo, 'empresa_yazo', y.empresa, 'icp_rotulo', case when nl.mind_id is null then icp.rotulo end,
                                              'relacionamento', case when nl.mind_id is not null then to_jsonb(nl.relacionamento_mind) end)) as fontes,
         nl.mind_id is not null as nao_lead
    from universo u
    join pessoas.pessoas p on p.id = u.mind_id and p.fundida_em is null
    left join yazo y on y.mind_id = u.mind_id
    left join emp e on e.chave = intelligence.texto_chave(y.empresa, true)
    left join icp on icp.mind_id = u.mind_id
    left join jt on jt.mind_id = u.mind_id
    left join nl on nl.mind_id = u.mind_id
    left join contato ct on ct.mind_id = u.mind_id
    left join ult on ult.hubspot_id = ct.hubspot_id
   where p_desde is null or exists (select 1 from mudou m where m.mind_id = u.mind_id)
   order by u.mind_id;
$fn$;
revoke execute on function public.mind_hubspot_perfil_plano(timestamptz) from public, anon, authenticated;
grant execute on function public.mind_hubspot_perfil_plano(timestamptz) to service_role;
comment on function public.mind_hubspot_perfil_plano(timestamptz) is 'Plano do write-back de perfil para o HubSpot (jobtitle, company, icp + icp_confianca, jtbd, resumo) com ultimo_escrito (o que o Mind escreveu por último no contato) e recorte por data (p_desde: quem teve memória alterada, ou deixou de ser lead). Quem não é lead (pessoas.relacionamento_mind) vem com nao_lead = true: cargo/empresa vão, e icp, icp_confianca, jtbd e resumo são limpos no HubSpot. Lido por hubspot-perfil-writeback com service_role.';

create or replace function public.mind_customer_intelligence(p_pessoa_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path to 'pg_catalog', 'public', 'pessoas', 'engagement', 'intelligence', 'crm'
as $function$
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
  v_nao_lead boolean;
begin
  if p_pessoa_id is null then return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa'); end if;

  select p.cargo, p.empresa, p.hubspot_id into v_role, v_company, v_hubspot
  from pessoas.pessoas p where p.id = p_pessoa_id;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'pessoa_nao_encontrada'); end if;
  v_nao_lead := not pessoas.e_lead(p_pessoa_id);

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

  -- rótulo canônico vem do catálogo intelligence.icp (aceita o texto atual, o legado ou o código);
  -- "Outros" não é classificação positiva: para o Agent, equivale a não classificado
  select i.rotulo, pm.confianca, pm.atualizado_em, i.codigo into v_icp_mem, v_icp_conf, v_icp_updated, v_icp_code
  from intelligence.participante_memoria pm
  join intelligence.icp i on i.ativo and i.codigo <> 'outros' and (i.rotulo = pm.valor->>'text' or i.rotulo_legado = pm.valor->>'text' or i.codigo = pm.valor->>'code')
  where pm.mind_id = p_pessoa_id and pm.tipo = 'icp' and pm.chave = 'icp_atual'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now())
  order by pm.atualizado_em desc limit 1;

  if v_icp_mem is null then
    select ic.rotulo, ic.codigo into v_crm_icp, v_icp_code from crm.contato_espelho e
    join intelligence.icp ic on ic.ativo and ic.codigo <> 'outros' and (ic.hubspot_valor = e.icp or ic.rotulo = e.icp)
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

  -- jobs: os 5 mais fortes, com a fonte (regra × conversa) e os tipos de evidência, para o Agent
  -- distinguir "disse em conversa" de "sentou numa sessão"
  select coalesce(jsonb_agg(t.obj order by t.conf desc, t.quando desc), '[]'::jsonb) into v_jobs from (
    select jsonb_strip_nulls(jsonb_build_object(
        'code', pm.valor->>'code', 'label', pm.valor->>'text', 'context', pm.valor->>'context',
        'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em,
        'source', case when pm.origem = 'regra_perfil' then 'rule' else 'conversation' end,
        'evidence', (select string_agg(distinct e->>'tipo', ',')
                       from jsonb_array_elements(case when jsonb_typeof(pm.valor->'evidencias') = 'array' then pm.valor->'evidencias' else '[]'::jsonb end) e))) as obj,
        pm.confianca as conf, pm.atualizado_em as quando
    from intelligence.participante_memoria pm
    where pm.mind_id = p_pessoa_id and pm.tipo = 'jtbd' and pm.status = 'ativa'
      and (pm.valido_ate is null or pm.valido_ate > now())
      and exists (select 1 from intelligence.jtbd j where j.ativo and j.codigo = pm.valor->>'code')
    order by pm.confianca desc, pm.atualizado_em desc limit 5) t;

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

  -- quem não é lead não tem ICP nem JTBD (nem o que ainda estiver no espelho do HubSpot)
  if v_nao_lead then v_icp := null; v_jobs := '[]'::jsonb; end if;

  return jsonb_build_object(
    'ok', true, 'pessoa_id', p_pessoa_id,
    'professional_context', jsonb_strip_nulls(jsonb_build_object('role', v_role, 'company', v_company, 'icp', v_icp)),
    'jobs_observed', v_jobs, 'goals', v_goals, 'interests', v_interests,
    'preferences', v_preferences, 'constraints', v_constraints,
    'decision_context', jsonb_build_object('stakeholders', v_stakeholders, 'delegations', v_delegations,
                                           'relevant_constraints', v_constraints));
end
$function$;
comment on function public.mind_customer_intelligence(uuid) is 'O que o Agent sabe da pessoa: contexto profissional (cargo, empresa, ICP canônico do catálogo — "Outros" conta como não classificado), até 5 jobs ativos por confiança com fonte (rule/conversation) e tipos de evidência, objetivos, interesses, preferências, restrições e contexto de decisão. Quem não é lead (pessoas.relacionamento_mind) não tem ICP nem jobs. Só leitura.';

-- 4. agora: tipos a partir das fontes e limpeza de ICP/JTBD de quem não é lead (pela própria regra)
select pessoas.relacionamento_atualizar(true);
select count(*) from (
  select intelligence.perfil_projetar(p.id, true)
    from pessoas.pessoas p where p.fundida_em is null and not ('lead' = any(p.relacionamento_mind))) x;
