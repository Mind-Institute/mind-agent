-- =====================================================================================
-- Funções: normalização de texto, ICP por cargo, evidências e projeção do perfil
-- =====================================================================================

-- Chave de comparação de texto livre: minúsculas, sem acento, só letras/dígitos/espaço.
-- Para empresa, também sem sufixos jurídicos e artigo/"grupo" inicial. Serve para dizer
-- "é a mesma coisa escrita de outro jeito" (Vale S.A. = VALE SA = vale).
create or replace function intelligence.texto_chave(p_texto text, p_empresa boolean default false)
returns text language plpgsql immutable as $fn$
declare s text;
begin
  if p_texto is null then return null; end if;
  s := lower(p_texto);
  s := translate(s, 'áàãâäéèêëíìîïóòõôöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn');
  s := replace(s, '&', ' e ');
  s := regexp_replace(s, '[^a-z0-9]+', ' ', 'g');
  if p_empresa then
    s := regexp_replace(s, '\y(ltda|limitada|s a|sa|me|eireli|epp|ss|cia|company|co|inc|llc|corp|corporation|group|holding|participacoes|brasil|brazil|do brasil|latam|latin america|international|internacional)\y', ' ', 'g');
    s := regexp_replace(s, '^\s*(o|a|os|as|the|grupo|group)\y', '', 'g');
    s := regexp_replace(s, '\y(e|and|do|da|de)\s*$', '', 'g');
  end if;
  s := btrim(regexp_replace(s, '\s+', ' ', 'g'));
  return nullif(s, '');
end $fn$;
comment on function intelligence.texto_chave(text, boolean) is 'Chave de comparação de texto livre (cargo, empresa): mesma chave = mesma coisa escrita de outro jeito. Com p_empresa, ignora sufixos jurídicos (Ltda, S.A.) e "Grupo/O/A" inicial.';

-- Forma de exibição de texto livre: só mexe quando a pessoa escreveu tudo em minúsculas ou
-- tudo em maiúsculas (aí vira Título, preservando siglas e preposições). Caixa mista fica como está.
create or replace function intelligence.texto_exibir(p_texto text)
returns text language plpgsql immutable as $fn$
declare
  s text; w text; partes text[] := '{}'; i int := 0;
  siglas text[] := array['rh','hr','hrbp','bp','dho','dp','ceo','cfo','coo','cto','cmo','cio','cso','cpo','chro','cho','cro','cco','cbo','cgo','vp','svp','evp','ti','it','esg','b2b','b2c','pmo','cs','cx','ux','ui','ia','ai','ehs','hse','ssma','qsma','sesmt','sst','ong','sa','s.a.','s/a','ltda','me','epp','mba','usp','ufrj','ufmg','puc','fgv','abrh','sp','rj','mg','ba','rs','pr','sc','go','df','pe','ce','eua','uk','usa','latam','br','crm','erp','pj','clt','kam','sdr','bdr','gm','md','nps','okr','kpi','p&d','r&d','m&a','fp&a','sus','inss','abnt','nr','nr-1','gro','pgr','pcmso','t&d','d&i','dei','l&d','tv','qa','bwg','bdf','mrs','bv','hcor','abc','ti/to','sgq','ti.'];
  minusculas text[] := array['de','da','do','das','dos','e','em','para','por','com','of','and','the','a','o','as','os','na','no','nas','nos','ao','aos','du','del','y','à','às'];
begin
  if p_texto is null then return null; end if;
  s := btrim(regexp_replace(p_texto, '\s+', ' ', 'g'));
  s := regexp_replace(s, '\s*/\s*', ' / ', 'g');
  s := regexp_replace(s, '[\s.,;:]+$', '', 'g');
  if s = '' then return null; end if;
  if s <> upper(s) and s <> lower(s) then return s; end if;   -- caixa mista: respeita o que a pessoa escreveu
  foreach w in array regexp_split_to_array(s, ' ') loop
    i := i + 1;
    if w = '' then continue;
    elsif lower(w) = 'phd' then partes := partes || 'PhD';
    elsif lower(w) = any(siglas) then partes := partes || upper(w);
    elsif i > 1 and lower(w) = any(minusculas) then partes := partes || lower(w);
    elsif w ~ '^[0-9]' or w = '/' or w = '-' or w = '&' then partes := partes || w;
    else partes := partes || (upper(left(w, 1)) || lower(substr(w, 2)));
    end if;
  end loop;
  return array_to_string(partes, ' ');
end $fn$;
comment on function intelligence.texto_exibir(text) is 'Forma de exibição de cargo/empresa escrita em campo livre: Título quando veio tudo em minúsculas/maiúsculas (siglas como RH, CEO, S.A. preservadas), intacta quando já tem caixa mista.';

-- ICP a partir do cargo (e da empresa, para o concorrente). Devolve intelligence.icp.codigo.
-- A ordem das regras é a decisão: saúde > RH (consultor, BP/analista, decisor, gestor) >
-- consultor/coach > academia > fundador/sócio > C-suite > diretor > gestor > analista > outros.
create or replace function intelligence.icp_por_cargo(p_cargo text, p_empresa text default null)
returns text language plpgsql stable as $fn$
declare
  c text := intelligence.texto_chave(p_cargo);
  e text := intelligence.texto_chave(p_empresa, true);
  v_conc text;
  rh text := '\y(rh|hr|hrd|recursos humanos|human resources|people|pessoas|gente|talent|talentos|talent acquisition|dho|desenvolvimento humano|cultura|culture|people ops|hrbp|business partner|bp|chro|cho|cpo|chief people|chief happiness|dp|departamento pessoal|beneficios|benefits|remuneracao|rewards|t e d|treinamento|desenvolvimento organizacional|recrutamento|selecao|recrutador|recrutadora|recruiter|headhunter|educacao corporativa|learning|clima|bem estar|bemestar|wellbeing|well being|saude mental|saude e bem estar|saude corporativa|saude ocupacional|occupational health|qualidade de vida|employer branding|experiencia do colaborador|employee experience|onboarding|pessoas e cultura|gente e gestao|gestao de pessoas|relacoes do trabalho|labor relations|engajamento|engagement|inclusao|diversidade|ssma|qsma|sesmt|ehs|hse|seguranca do trabalho|saude e seguranca|riscos psicossociais)\y';
  bp text := '\y(business partner|bp|hrbp|analista|analyst|especialista|specialist|assistente|assistant|auxiliar|estagiario|estagiaria|trainee|generalista|tecnico|tecnica|recrutador|recrutadora|recruiter|consultor interno|consultora interna|aprendiz|professional|profissional)\y';
  fundador text := '\y(founder|co founder|cofounder|fundador|fundadora|cofundador|cofundadora|co fundador|co fundadora|idealizador|idealizadora|socio|socia|proprietario|proprietaria|dono|dona|empresario|empresaria|empreendedor|empreendedora|owner|partner|managing partner|acionista)\y';
  csuite text := '\y(ceo|cfo|coo|cto|cmo|cio|cso|cpo|chro|cho|cco|cbo|cgo|cro|chief|presidente|president|vice presidente|vp|svp|evp|diretor geral|diretora geral|diretor executivo|diretora executiva|general director|managing director|general manager|country manager|conselheiro|conselheira|board|principal|administrador|administradora|chairman|chairwoman)\y';
  diretor text := '\y(diretor|diretora|director|directora|diretoria|head|superintendente|superintendent|senior executive|gerente geral|gerente executivo|gerente executiva|dean|senior vice president|executive)\y';
  gestor text := '\y(gerente|gestor|gestora|manager|coordenador|coordenadora|coordinator|coordenacao|supervisor|supervisora|lider|lideranca|leader|lead|chefe|chefia|encarregado|encarregada|gestao|responsavel|ouvidor|ouvidora)\y';
  analista text := '\y(analista|analyst|especialista|specialist|assistente|assistant|auxiliar|estagiario|estagiaria|trainee|generalista|tecnico|tecnica|jovem aprendiz|aprendiz|assessor|assessora|colaborador|colaboradora|funcionario|funcionaria|executivo|executiva|account|vendedor|vendedora|sales|representante|secretaria|secretario|associate)\y';
  saude text := '\y(psicolog[ao]|psicologia|psychologist|psychology|psicanalista|psiquiatra|psychiatrist|medic[ao]|medicina|physician|terapeuta|therapist|psicoterapeuta|enfermeir[ao]|enfermagem|nurse|nutricionista|fisioterapeuta|fonoaudiolog[ao]|assistente social|neuropsicolog[ao]|medicina do trabalho|ergonomista|farmaceutic[ao]|dentista|dentist|odontolog[ao]|educador fisico|educadora fisica|profissional de saude|terapia|acupunturista|neurocientista|clinica|clinical|assistencial|nutrolog[ao])\y';
  consultor text := '\y(consultor|consultora|consultant|consultoria|consulting|coach|coaching|mentor|mentora|mentoria|palestrante|speaker|facilitador|facilitadora|trainer|treinador|treinadora|instrutor|instrutora|advisor|autonomo|autonoma|freelancer|prestador|prestadora|profissional liberal|escritor|escritora|autor|autora)\y';
  academia text := '\y(professor|professora|teacher|docente|pesquisador|pesquisadora|researcher|estudante|student|aluno|aluna|universitario|universitaria|mestrando|mestranda|doutorando|doutoranda|pos graduando|pos graduanda|graduando|graduanda|academico|academica|phd|educador|educadora|educator|pedagog[ao]|pedagogia|escola|school|faculdade|universidade|university)\y';
begin
  -- concorrente é pela empresa, seja qual for o cargo
  if e is not null then
    select i.codigo into v_conc from intelligence.icp i
     where i.ativo and i.regex_empresa is not null and e ~ i.regex_empresa
     order by i.ordem limit 1;
    if v_conc is not null then return v_conc; end if;
  end if;
  if c is null or c in ('x', 'n a', 'na', 'nao', 'nenhum', 'nenhuma', 'outro', 'outros', 'sem cargo') then return null; end if;

  if c ~ saude then return 'psicologo_saude'; end if;
  if c ~ rh then
    if c ~ consultor then return 'consultor_rh'; end if;
    if c ~ bp and c !~ csuite and c !~ diretor and c !~ fundador then return 'analista_bp_rh'; end if;
    if c ~ csuite or c ~ diretor or c ~ fundador then return 'chro_vp_diretor_rh'; end if;
    if c ~ gestor then return 'gestor_rh'; end if;
    return 'analista_bp_rh';
  end if;
  if c ~ consultor then return 'consultor_coach'; end if;
  if c ~ academia then return 'professor_pesquisador_estudante'; end if;
  if c ~ fundador then return 'fundador_socio'; end if;
  if c ~ csuite then return 'ceo_csuite'; end if;
  if c ~ diretor then return 'diretor_vp_nao_rh'; end if;
  if c ~ gestor then return 'gestor_nao_rh'; end if;
  if c ~ analista then return 'analista_nao_rh'; end if;
  return 'outros';
end $fn$;
comment on function intelligence.icp_por_cargo(text, text) is 'Classifica um cargo escrito em campo livre num intelligence.icp.codigo (concorrente pela empresa). Regra determinística, sem IA: a ordem das checagens é a decisão.';

-- Evidências de JTBD de uma pessoa: uma linha por sinal (check-in, reserva, interesse da jornada
-- no app, job-raiz observado em conversa, patrocínio, produto preferido, contexto por ICP).
create or replace function intelligence.perfil_evidencias(p_mind uuid, p_familia text default null)
returns table (codigo text, confianca numeric, evidencia jsonb)
language sql stable
set search_path to 'pg_catalog', 'public', 'intelligence', 'engagement', 'summit_2026', 'credenciamento_summit_2026'
as $fn$
  with base as (
    -- check-in numa sessão marcada (evidência mais forte: a pessoa foi)
    select * from (
      select distinct on (ci.sessao_id, x.c) x.c as codigo, 0.70::numeric as conf, jsonb_build_object('tipo', 'checkin', 'sessao', se.titulo) as ev
        from credenciamento_summit_2026."Check Ins Summit" ci
        join summit_2026.sessions se on se.id = ci.sessao_id
        cross join lateral unnest(se.jtbd) as x(c)
       where ci.mind_id = p_mind
       order by ci.sessao_id, x.c) a
    union all
    -- reserva sem check-in (intenção)
    select * from (
      select distinct on (r.sessao_id, x.c) x.c, 0.60::numeric, jsonb_build_object('tipo', 'reserva', 'sessao', se.titulo)
        from credenciamento_summit_2026."Reservas_Agenda_APP" r
        join summit_2026.sessions se on se.id = r.sessao_id
        cross join lateral unnest(se.jtbd) as x(c)
       where r.mind_id = p_mind
         and not exists (select 1 from credenciamento_summit_2026."Check Ins Summit" ci where ci.mind_id = p_mind and ci.sessao_id = r.sessao_id)
       order by r.sessao_id, x.c) b
    union all
    -- interesses declarados na jornada do app
    select * from (
      select distinct on (j.codigo, si.chave) j.codigo, (j.sinais->'interesses'->>si.chave)::numeric, jsonb_build_object('tipo', 'interesse', 'chave', si.chave)
        from engagement.agent_sessions ag
        join engagement.session_interests si on si.agent_session_id = ag.id
        join intelligence.jtbd j on j.nivel = 'mind' and j.ativo and (j.sinais->'interesses') ? si.chave
       where ag.mind_id = p_mind
         and (j.sinais->'interesses_familias' is null
              or p_familia in (select jsonb_array_elements_text(j.sinais->'interesses_familias')))
       order by j.codigo, si.chave) c
    union all
    -- jobs-raiz (JT01–JT15) observados em conversa, traduzidos
    select * from (
      select distinct on (j.codigo, pm.valor->>'code') j.codigo, pm.confianca,
             jsonb_build_object('tipo', 'conversa', 'jt', pm.valor->>'code', 'contexto', left(pm.valor->>'context', 120))
        from intelligence.participante_memoria pm
        join intelligence.jtbd j on j.nivel = 'mind' and j.ativo and (pm.valor->>'code') = any(j.jt_raiz)
        cross join lateral (select j.sinais->'jt_filtro'->(pm.valor->>'code') as f) x
       where pm.mind_id = p_mind and pm.tipo = 'jtbd' and pm.status in ('ativa', 'proposta') and pm.origem <> 'regra_perfil'
         and (x.f->>'contexto_regex' is null or coalesce(pm.valor->>'context', '') ~* (x.f->>'contexto_regex'))
         and (x.f->>'contexto_regex_excluir' is null or coalesce(pm.valor->>'context', '') !~* (x.f->>'contexto_regex_excluir'))
         and (x.f->'familias' is null or p_familia in (select jsonb_array_elements_text(x.f->'familias')))
       order by j.codigo, pm.valor->>'code', pm.confianca desc) d
    union all
    -- patrocínio: memória de patrocínio ou análise de conversa com empresa patrocinadora
    select * from (
      select j.codigo, 0.60::numeric, jsonb_build_object('tipo', 'memoria_patrocinio', 'texto', left(pm.valor->>'text', 120))
        from intelligence.participante_memoria pm
        join intelligence.jtbd j on j.nivel = 'mind' and j.ativo and (j.sinais->>'patrocinio')::boolean
       where pm.mind_id = p_mind and pm.tipo = 'patrocinio' and pm.status in ('ativa', 'proposta')
       order by pm.atualizado_em desc limit 1) e
    union all
    select * from (
      select j.codigo, 0.70::numeric, jsonb_build_object('tipo', 'analise_patrocinio', 'empresa', ac.dados->'sponsorship'->>'company')
        from intelligence.analise_conversa ac
        join intelligence.jtbd j on j.nivel = 'mind' and j.ativo and (j.sinais->>'patrocinio')::boolean
       where ac.mind_id = p_mind and nullif(ac.dados->'sponsorship'->>'company', '') is not null
       order by ac.analisado_em desc nulls last limit 1) f
    union all
    -- produto preferido em conversa (ex.: Dash → escolher consultoria)
    select * from (
      select distinct on (j.codigo) j.codigo, 0.70::numeric, jsonb_build_object('tipo', 'analise_produto', 'produto', left(ac.dados->>'preferred_product_or_offer', 60))
        from intelligence.analise_conversa ac
        join intelligence.jtbd j on j.nivel = 'mind' and j.ativo and (j.sinais->'conversa'->>'preferred_product_regex') is not null
       where ac.mind_id = p_mind and coalesce(ac.dados->>'preferred_product_or_offer', '') ~* (j.sinais->'conversa'->>'preferred_product_regex')
       order by j.codigo, ac.analisado_em desc nulls last) g
  ),
  ctx as (
    -- job derivado de outro job + família do ICP (ex.: RH interessado em liderança → contratar treinamento)
    select distinct on (j.codigo) j.codigo, (j.sinais->'contextual'->>'confianca')::numeric as conf,
           jsonb_build_object('tipo', 'contexto', 'de', b.codigo, 'familia', p_familia) as ev
      from intelligence.jtbd j
      join base b on b.conf >= 0.60 and b.codigo in (select jsonb_array_elements_text(j.sinais->'contextual'->'de'))
     where j.nivel = 'mind' and j.ativo and j.sinais ? 'contextual'
       and p_familia in (select jsonb_array_elements_text(j.sinais->'contextual'->'familias'))
     order by j.codigo, b.conf desc
  )
  select codigo, conf, ev from base
  union all
  select codigo, conf, ev from ctx;
$fn$;
comment on function intelligence.perfil_evidencias(uuid, text) is 'Uma linha por evidência de JTBD da pessoa (check-in, reserva, interesse da jornada, job-raiz de conversa traduzido, patrocínio, produto preferido, contexto por família de ICP). Só leitura; quem grava é perfil_projetar.';

-- Projeção do perfil de uma pessoa em intelligence.participante_memoria:
--   icp_atual (tipo icp) pelo cargo; cargo_atual/empresa_atual pelo credenciamento quando o slot
--   está vazio; jtbd:<codigo> (tipo jtbd) pelas evidências. Nunca derruba memória de conversa
--   (origem analise_*): quando diverge, entra como proposta. Idempotente: a origem regra_perfil
--   atualiza o que ela mesma gravou.
create or replace function intelligence.perfil_projetar(p_mind uuid, p_gravar boolean default true)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'intelligence', 'engagement', 'pessoas', 'crm', 'credenciamento_summit_2026'
as $fn$
declare
  v_cargo text; v_empresa text; v_fonte text;
  v_icp text; v_familia text; v_rotulo text; v_manual text; v_icp_acao text := 'nada';
  v_exist intelligence.participante_memoria%rowtype;
  v_valor jsonb; v_status text; v_jtbd jsonb := '[]'::jsonb; v_novas int := 0;
  r record;
begin
  if p_mind is null then return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa'); end if;
  if not exists (select 1 from pessoas.pessoas where id = p_mind and fundida_em is null) then
    return jsonb_build_object('ok', false, 'motivo', 'pessoa_inexistente_ou_fundida');
  end if;

  -- 1. cargo e empresa por prioridade: credenciamento (Yazo) > conversa > espelho HubSpot > pessoa
  select s.cargo, s.empresa, s.fonte into v_cargo, v_empresa, v_fonte from (
    select nullif(btrim(r."Cargo / Profissão"), '') as cargo, nullif(btrim(r."Empresa"), '') as empresa, 'credenciamento_yazo' as fonte, 1 as prio
      from credenciamento_summit_2026."Relatorio Yazzo Consolidado" r where r.mind_id = p_mind
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
      select nullif(btrim(r."Empresa"), '') as empresa, 1 as prio from credenciamento_summit_2026."Relatorio Yazzo Consolidado" r where r.mind_id = p_mind
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
      update intelligence.participante_memoria set valor = v_valor, confianca = 0.70, atualizado_em = now() where id = v_exist.id;
      v_icp_acao := 'atualizada';
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
        update intelligence.participante_memoria
           set valor = v_valor, confianca = r.conf,
               status = case when v_exist.status = 'ativa' then 'ativa' else v_status end,
               atualizado_em = now()
         where id = v_exist.id;
      end if;   -- memória de conversa (analise_*): fica como está
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'mind_id', p_mind, 'cargo', v_cargo, 'empresa', v_empresa, 'fonte_cargo', v_fonte,
                            'icp', v_icp, 'icp_acao', v_icp_acao, 'icp_manual_hubspot', v_manual,
                            'jtbd', v_jtbd, 'memorias_novas', v_novas, 'gravou', p_gravar);
end $fn$;
comment on function intelligence.perfil_projetar(uuid, boolean) is 'Escreve em participante_memoria o perfil por regra de uma pessoa: icp_atual pelo cargo (memória de conversa e ICP manual do HubSpot vencem), cargo_atual/empresa_atual do credenciamento em slot vazio, jtbd:<codigo> pelas evidências (perfil_evidencias). p_gravar=false só calcula.';

-- Lote por prefixo do uuid (16 fatias: '0'..'f'), sobre quem tem alguma evidência ou cargo.
create or replace function intelligence.perfil_projetar_lote(p_prefixo text default '', p_gravar boolean default true)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'intelligence', 'engagement', 'pessoas', 'crm', 'credenciamento_summit_2026'
as $fn$
declare r record; v_res jsonb; v_n int := 0; v_icp int := 0; v_jt int := 0; v_ini timestamptz := clock_timestamp();
begin
  for r in
    select u.mind_id from (
      select mind_id from credenciamento_summit_2026.controle_de_inscritos_e_presenca where mind_id is not null
      union select mind_id from credenciamento_summit_2026."Relatorio Yazzo Consolidado" where mind_id is not null and nullif(btrim("Cargo / Profissão"), '') is not null
      union select mind_id from intelligence.analise_conversa where mind_id is not null
      union select ag.mind_id from engagement.agent_sessions ag where ag.mind_id is not null and exists (select 1 from engagement.session_interests si where si.agent_session_id = ag.id)
      union select mind_id from intelligence.participante_memoria where tipo in ('jtbd', 'cargo', 'patrocinio') and status in ('ativa', 'proposta')
    ) u
    where u.mind_id::text like p_prefixo || '%'
      and exists (select 1 from pessoas.pessoas p where p.id = u.mind_id and p.fundida_em is null)
  loop
    v_res := intelligence.perfil_projetar(r.mind_id, p_gravar);
    v_n := v_n + 1;
    if v_res->>'icp' is not null then v_icp := v_icp + 1; end if;
    if jsonb_array_length(coalesce(v_res->'jtbd', '[]'::jsonb)) > 0 then v_jt := v_jt + 1; end if;
  end loop;
  return jsonb_build_object('prefixo', p_prefixo, 'pessoas', v_n, 'com_icp', v_icp, 'com_jtbd', v_jt,
                            'segundos', round(extract(epoch from clock_timestamp() - v_ini)::numeric, 1), 'gravou', p_gravar);
end $fn$;
comment on function intelligence.perfil_projetar_lote(text, boolean) is 'Roda perfil_projetar para todo mundo com evidência (presentes do Summit, quem informou cargo, quem conversou com o Mind, quem respondeu a jornada do app). p_prefixo fatia por início do uuid.';

-- O que a pessoa escreveu no credenciamento vai para pessoas.pessoas (cargo, empresa), na forma de
-- exibição; empresa com a grafia mais frequente entre as pessoas da mesma empresa.
create or replace function intelligence.perfil_gravar_pessoas(p_gravar boolean default true)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'intelligence', 'pessoas', 'credenciamento_summit_2026'
as $fn$
declare v_cargo int := 0; v_empresa int := 0;
begin
  create temp table perfil_yazo_tmp on commit drop as
    with yazo as (
      select r.mind_id, max(nullif(btrim(r."Cargo / Profissão"), '')) as cargo, max(nullif(btrim(r."Empresa"), '')) as empresa
        from credenciamento_summit_2026."Relatorio Yazzo Consolidado" r where r.mind_id is not null group by r.mind_id),
    emp as (
      select intelligence.texto_chave(empresa, true) as chave, mode() within group (order by intelligence.texto_exibir(empresa)) as exibir
        from yazo where empresa is not null group by 1)
    select y.mind_id, intelligence.texto_exibir(y.cargo) as cargo, e.exibir as empresa
      from yazo y left join emp e on e.chave = intelligence.texto_chave(y.empresa, true);
  if p_gravar then
    update pessoas.pessoas p set cargo = t.cargo, atualizado_em = now()
      from perfil_yazo_tmp t where t.mind_id = p.id and t.cargo is not null
       and intelligence.texto_chave(p.cargo) is distinct from intelligence.texto_chave(t.cargo);
    get diagnostics v_cargo = row_count;
    update pessoas.pessoas p set empresa = t.empresa, atualizado_em = now()
      from perfil_yazo_tmp t where t.mind_id = p.id and t.empresa is not null
       and intelligence.texto_chave(p.empresa, true) is distinct from intelligence.texto_chave(t.empresa, true);
    get diagnostics v_empresa = row_count;
  else
    select count(*) filter (where t.cargo is not null and intelligence.texto_chave(p.cargo) is distinct from intelligence.texto_chave(t.cargo)),
           count(*) filter (where t.empresa is not null and intelligence.texto_chave(p.empresa, true) is distinct from intelligence.texto_chave(t.empresa, true))
      into v_cargo, v_empresa from perfil_yazo_tmp t join pessoas.pessoas p on p.id = t.mind_id;
  end if;
  return jsonb_build_object('cargos_gravados', v_cargo, 'empresas_gravadas', v_empresa, 'gravou', p_gravar);
end $fn$;
comment on function intelligence.perfil_gravar_pessoas(boolean) is 'Leva cargo e empresa escritos no credenciamento (Relatório Yazzo) para pessoas.pessoas, só quando a chave de comparação difere (não troca grafia equivalente). Empresa com a grafia mais frequente da mesma chave.';

-- Plano para o HubSpot: uma linha por pessoa com algo a escrever (jobtitle, company, icp, jtbd).
-- Lido pela Edge Function hubspot-perfil-writeback via RPC (por isso em public). Só service_role.
create or replace function public.mind_hubspot_perfil_plano()
returns table (mind_id uuid, hubspot_id text, email text, jobtitle text, company text, icp text, icp_confianca numeric, jtbd text[], fontes jsonb)
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
  universo as (select mind_id from yazo union select mind_id from icp union select mind_id from jt),
  contato as (
    select distinct on (c.mind_id) c.mind_id, c.hubspot_id, lower(btrim(c.email)) as email
      from crm.contato_espelho c where c.mind_id is not null order by c.mind_id, c.atualizado_em desc nulls last)
  select u.mind_id, ct.hubspot_id,
         coalesce(ct.email,
                  (select i.identificador from engagement.identidades i where i.mind_id = u.mind_id and i.canal = 'email' order by i.criado_em limit 1),
                  lower(p.email)) as email,
         intelligence.texto_exibir(y.cargo) as jobtitle,
         e.exibir as company,
         icp.hubspot_valor as icp,
         case when icp.confianca is not null then round(icp.confianca * 10) end as icp_confianca,
         coalesce(jt.valores, '{}'::text[]) as jtbd,
         jsonb_strip_nulls(jsonb_build_object('cargo_yazo', y.cargo, 'empresa_yazo', y.empresa, 'icp_rotulo', icp.rotulo)) as fontes
    from universo u
    join pessoas.pessoas p on p.id = u.mind_id and p.fundida_em is null
    left join yazo y on y.mind_id = u.mind_id
    left join emp e on e.chave = intelligence.texto_chave(y.empresa, true)
    left join icp on icp.mind_id = u.mind_id
    left join jt on jt.mind_id = u.mind_id
    left join contato ct on ct.mind_id = u.mind_id
   order by u.mind_id;
$fn$;
revoke execute on function public.mind_hubspot_perfil_plano() from public, anon, authenticated;
grant execute on function public.mind_hubspot_perfil_plano() to service_role;
comment on function public.mind_hubspot_perfil_plano() is 'Plano do write-back de perfil para o HubSpot (jobtitle, company, icp + icp_confianca, jtbd), uma linha por pessoa com algo a escrever. Lido por hubspot-perfil-writeback com service_role; anon/authenticated não executam.';

create or replace function public.mind_hubspot_perfil_definicoes()
returns jsonb language sql stable security definer
set search_path to 'pg_catalog', 'public'
as $fn$
  select jsonb_build_object(
    'icp', (select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'rotulo', rotulo, 'hubspot_valor', hubspot_valor, 'ordem', ordem, 'descricao', descricao) order by ordem), '[]'::jsonb)
              from intelligence.icp where ativo and hubspot_opcao and hubspot_valor is not null),
    'jtbd', (select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'rotulo', rotulo, 'hubspot_valor', hubspot_valor, 'ordem', ordem, 'descricao', descricao) order by ordem), '[]'::jsonb)
              from intelligence.jtbd where ativo and hubspot_opcao and hubspot_valor is not null));
$fn$;
revoke execute on function public.mind_hubspot_perfil_definicoes() from public, anon, authenticated;
grant execute on function public.mind_hubspot_perfil_definicoes() to service_role;
comment on function public.mind_hubspot_perfil_definicoes() is 'Opções das propriedades icp e jtbd do HubSpot segundo os catálogos intelligence.icp / intelligence.jtbd (para conferência e sincronização pela Edge Function).';
