-- perfil_projetar só grava (e só carimba atualizado_em) quando valor, confiança ou status mudam.
-- Motivo: mind_hubspot_perfil_plano(p_desde) usa atualizado_em das memórias icp/jtbd/cargo/empresa
-- para achar quem mudou; a versão anterior carimbava todas as memórias a cada rodada, e o recorte
-- "desde" do cron horário trazia todo mundo. Nada mais muda nas regras.
create or replace function intelligence.perfil_projetar(p_mind uuid, p_gravar boolean default true)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'intelligence', 'engagement', 'pessoas', 'crm', 'credenciamento_summit_2026'
as $function$
declare
  v_cargo text; v_empresa text; v_fonte text;
  v_icp text; v_familia text; v_rotulo text; v_manual text; v_icp_acao text := 'nada';
  v_exist intelligence.participante_memoria%rowtype;
  v_valor jsonb; v_status text; v_jtbd jsonb := '[]'::jsonb; v_novas int := 0; v_alteradas int := 0;
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

  -- 2. ICP pelo cargo (concorrente pela empresa)
  v_icp := intelligence.icp_por_cargo(v_cargo, v_empresa);
  select i.familia, i.rotulo into v_familia, v_rotulo from intelligence.icp i where i.codigo = v_icp;
  select nullif(e.icp, '') into v_manual from crm.contato_espelho e
   where e.mind_id = p_mind and nullif(e.icp, '') is not null order by e.atualizado_em desc nulls last limit 1;

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
      values (p_mind, 'icp', 'icp_atual', v_valor, 0.70, 'regra_perfil', 'ativa');
      v_icp_acao := 'criada'; v_novas := v_novas + 1;
    elsif v_exist.origem = 'regra_perfil' then
      if v_exist.valor is distinct from v_valor or v_exist.confianca is distinct from 0.70::numeric then
        update intelligence.participante_memoria set valor = v_valor, confianca = 0.70, atualizado_em = now() where id = v_exist.id;
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
        values (p_mind, 'icp', 'icp_atual', v_valor, 0.70, 'regra_perfil', 'proposta');
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
  for r in
    with ev as (select * from intelligence.perfil_evidencias(p_mind, v_familia)),
    agg as (
      select ev.codigo, least(0.90, max(ev.confianca) + 0.05 * (count(*) - 1)) as conf,
             jsonb_agg(ev.evidencia order by ev.confianca desc) as evidencias, count(*) as n
        from ev group by ev.codigo)
    select a.codigo, a.conf, a.evidencias, a.n, j.rotulo
      from agg a join intelligence.jtbd j on j.codigo = a.codigo and j.ativo
     order by a.conf desc, j.ordem
  loop
    v_status := case when r.conf >= 0.70 then 'ativa' else 'proposta' end;
    v_valor := jsonb_build_object('code', r.codigo, 'text', r.rotulo, 'scope', 'stable', 'evidence_kind', 'regra_perfil', 'evidencias', r.evidencias);
    v_jtbd := v_jtbd || jsonb_build_object('code', r.codigo, 'confianca', r.conf, 'status', v_status, 'evidencias', r.n);
    if p_gravar then
      select * into v_exist from intelligence.participante_memoria pm
       where pm.mind_id = p_mind and pm.chave = 'jtbd:' || r.codigo and pm.status in ('ativa', 'proposta')
       order by (pm.status = 'ativa') desc, pm.atualizado_em desc limit 1;
      if not found then
        insert into intelligence.participante_memoria (mind_id, tipo, chave, valor, confianca, origem, status)
        values (p_mind, 'jtbd', 'jtbd:' || r.codigo, v_valor, r.conf, 'regra_perfil', v_status);
        v_novas := v_novas + 1;
      elsif v_exist.origem = 'regra_perfil' then
        if v_status = 'ativa' and v_exist.status <> 'ativa'
           and exists (select 1 from intelligence.participante_memoria pm where pm.mind_id = p_mind and pm.chave = 'jtbd:' || r.codigo and pm.status = 'ativa') then
          v_status := 'proposta';   -- já existe uma ativa de outra origem
        end if;
        v_status := case when v_exist.status = 'ativa' then 'ativa' else v_status end;   -- ativa não regride
        if v_exist.valor is distinct from v_valor or v_exist.confianca is distinct from r.conf or v_exist.status is distinct from v_status then
          update intelligence.participante_memoria
             set valor = v_valor, confianca = r.conf, status = v_status, atualizado_em = now()
           where id = v_exist.id;
          v_alteradas := v_alteradas + 1;
        end if;
      end if;   -- memória de conversa (analise_*): fica como está
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'mind_id', p_mind, 'cargo', v_cargo, 'empresa', v_empresa, 'fonte_cargo', v_fonte,
                            'icp', v_icp, 'icp_acao', v_icp_acao, 'icp_manual_hubspot', v_manual,
                            'jtbd', v_jtbd, 'memorias_novas', v_novas, 'memorias_alteradas', v_alteradas, 'gravou', p_gravar);
end $function$;
comment on function intelligence.perfil_projetar(uuid, boolean) is 'Projeta ICP (pelo cargo), cargo/empresa (do credenciamento) e JTBD (pelas evidências) nas memórias da pessoa, origem regra_perfil. Só grava o que mudou — atualizado_em é o sinal que o write-back horário do HubSpot usa. Nunca sobrescreve memória de conversa nem ICP manual do HubSpot.';
