-- =====================================================================================
-- Revisão da regra de perfil (ICP/JTBD) depois da crítica de 23/09/2026 (docs/PERFIL_ICP_JTBD.md §6):
--  1. evidência: check-in pesa pelo tamanho da sala (workshop 0,70 · 150+ 0,65 · 300+ 0,55) e reserva
--     vale 0,50 e nunca sozinha faz job ativo; memória de texto conta uma vez por job;
--  2. agregação: reservas não empilham (+0,05 no máximo), job organizacional fora dos ICPs típicos
--     do catálogo fica em hipótese (≤ 0,65) salvo fala em conversa; a regra pode rebaixar o que ela
--     mesma promoveu e rebaixa job cuja evidência sumiu;
--  3. cargo: RH em inglês/siglas (C&B, D&I, L&D, NR-1, SST…), abreviações de nível (coord, ger, dir,
--     supte), RH com nível antes de saúde, executivos públicos, "executive assistant"/"product owner"
--     não são executivos, "dona de casa" é outros;
--  4. ICP manual do HubSpot: só é manual se não for o que o próprio Mind escreveu por último;
--  5. confiança do ICP 0,55 quando o cargo é só um nível ("Gerente", "Diretora");
--  6. texto_exibir: em caixa mista, siglas conhecidas em maiúsculas e inicial maiúscula.
-- =====================================================================================

-- 0. tokens largos fora dos regex de memória (pergunta sobre certificação não é job de autoridade)
update intelligence.jtbd set atualizado_em = now(), sinais = jsonb_set(sinais, '{memoria_regex}', to_jsonb(
  'autoridade|me diferenciar|me posicionar|escalar (minha|meu|a minha|o meu)|al[ée]m do 1:1|dar palestras|ser palestrante|palestrar|posicionamento profissional|me tornar refer[êe]ncia|refer[êe]ncia no mercado|atender empresas'::text))
 where codigo = 'autoridade_escala';
update intelligence.jtbd set atualizado_em = now(), sinais = jsonb_set(sinais, '{memoria_regex}', to_jsonb(
  '\yroi\y|retorno (do|sobre o?) (investimento|bem-?estar)|business case|dados de (pessoas|bem-?estar|sa[úu]de)|convencer (a )?(diretoria|o board|o cfo|a lideran[çc]a)|people analytics|mostrar (resultado|valor)|indicadores de (bem-?estar|sa[úu]de|pessoas|rh)|m[ée]tricas de (bem-?estar|sa[úu]de|pessoas|rh)'::text))
 where codigo = 'provar_retorno';

-- 1. evidências
create or replace function intelligence.perfil_evidencias(p_mind uuid, p_familia text default null)
returns table (codigo text, confianca numeric, evidencia jsonb)
language sql stable
set search_path to 'pg_catalog', 'public', 'intelligence', 'engagement', 'summit_2026', 'credenciamento_summit_2026'
as $fn$
  with base as (
    -- check-in: sala pequena informa muito; plenária de 300+ informa pouco
    select * from (
      select distinct on (ci.sessao_id, x.c) x.c as codigo,
             (case when pub.pessoas >= 300 then 0.55 when pub.pessoas >= 150 then 0.65 else 0.70 end)::numeric as conf,
             jsonb_build_object('tipo', 'checkin', 'sessao', se.titulo, 'publico', pub.pessoas) as ev
        from credenciamento_summit_2026."Check Ins Summit" ci
        join summit_2026.sessions se on se.id = ci.sessao_id
        join (select c2.sessao_id, count(distinct c2.mind_id) as pessoas from credenciamento_summit_2026."Check Ins Summit" c2 group by 1) pub on pub.sessao_id = se.id
        cross join lateral unnest(se.jtbd) as x(c)
       where ci.mind_id = p_mind
       order by ci.sessao_id, x.c) a
    union all
    -- reserva sem check-in: intenção fraca (61% reservaram a mesma plenária); nunca faz job ativo sozinha
    select * from (
      select distinct on (r.sessao_id, x.c) x.c, 0.50::numeric, jsonb_build_object('tipo', 'reserva', 'sessao', se.titulo)
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
    -- o que a pessoa disse em conversa (memórias de texto e campos da análise): uma evidência por job
    select * from (
      select distinct on (t.codigo) t.codigo, 0.60::numeric, t.ev from (
        select j.codigo, jsonb_build_object('tipo', 'memoria_texto', 'memoria', pm.tipo, 'texto', left(pm.valor->>'text', 100)) as ev,
               pm.confianca as prio, pm.atualizado_em as quando
          from intelligence.participante_memoria pm
          join intelligence.jtbd j on j.nivel = 'mind' and j.ativo and (j.sinais->>'memoria_regex') is not null
         where pm.mind_id = p_mind and pm.status in ('ativa', 'proposta')
           and pm.tipo in ('interesse', 'objetivo', 'preferencia_comercial', 'delegacao', 'patrocinio', 'outro')
           and coalesce(pm.valor->>'text', '') ~* (j.sinais->>'memoria_regex')
        union all
        select j.codigo, jsonb_build_object('tipo', 'memoria_texto', 'memoria', 'analise', 'texto', left(t2.txt, 100)),
               0.50, ac.analisado_em
          from intelligence.analise_conversa ac
          cross join lateral (select concat_ws(' · ', ac.dados->>'objective', ac.dados->>'buyer_objective', ac.dados->>'use_case',
                                                case when jsonb_typeof(ac.dados->'interests') = 'array' then (select string_agg(x #>> '{}', ' · ') from jsonb_array_elements(ac.dados->'interests') x) else ac.dados->>'interests' end) as txt) t2
          join intelligence.jtbd j on j.nivel = 'mind' and j.ativo and (j.sinais->>'memoria_regex') is not null
         where ac.mind_id = p_mind and t2.txt ~* (j.sinais->>'memoria_regex')
      ) t
      order by t.codigo, t.prio desc nulls last, t.quando desc nulls last) h
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
comment on function intelligence.perfil_evidencias(uuid, text) is 'Uma linha por evidência de JTBD da pessoa: check-in (peso pelo tamanho da sala: 0,70 / 0,65 a partir de 150 / 0,55 a partir de 300), reserva (0,50), interesse da jornada, job-raiz de conversa traduzido, texto de memórias/análises por regex (uma por job, 0,60), patrocínio, produto preferido, contexto por família de ICP. Só leitura; quem grava é perfil_projetar.';

-- 3. cargo
create or replace function intelligence.icp_por_cargo(p_cargo text, p_empresa text default null)
returns text language plpgsql stable as $fn$
declare
  c text := intelligence.texto_chave(p_cargo);
  e text := intelligence.texto_chave(p_empresa, true);
  v_conc text;
  rh text := '\y(rh|hr|hrd|recursos humanos|human resources?|people|pessoas|gente|talent|talentos|talent acquisition|talent management|gestao de talentos|capital humano|human capital|desenvolvimento de pessoas|people partner|dho|desenvolvimento humano|cultura|culture|people ops|hrbp|business partner|bp|chro|cho|cpo|chief people|chief happiness|dp|departamento pessoal|beneficios|benefits|remuneracao|rewards|c e b|comp e ben|compensation|total rewards|t e d|l e d|treinamento|desenvolvimento organizacional|recrutamento|selecao|recrutador|recrutadora|recruiter|headhunter|head hunter|educacao corporativa|learning|clima|bem estar|bemestar|wellbeing|well being|saude mental|saude e bem estar|saude corporativa|saude ocupacional|occupational health|qualidade de vida|felicidade corporativa|happiness|employer branding|experiencia do colaborador|employee experience|onboarding|pessoas e cultura|gente e gestao|gestao de pessoas|relacoes do trabalho|labor relations|engajamento|engagement|inclusao|diversidade|diversity|inclusion|d e i|de e i|dei|ssma|qsma|sesmt|sst|ehs|hse|seguranca do trabalho|saude e seguranca|saude e seguranca do trabalho|riscos psicossociais|nr ?0?1)\y';
  bp text := '\y(business partner|bp|hrbp|analista|analyst|especialista|specialist|assistente|assistant|auxiliar|estagiario|estagiaria|trainee|generalista|tecnico|tecnica|recrutador|recrutadora|recruiter|consultor interno|consultora interna|aprendiz|professional|profissional)\y';
  fundador text := '\y(fou?nder|co fou?nder|cofou?nder|fundador|fundadora|cofundador|cofundadora|co fundador|co fundadora|idealizador|idealizadora|socio|socia|proprietario|proprietaria|dono|dona|empresario|empresaria|empreendedor|empreendedora|owner|(?<!business )partner|managing partner|acionista)\y';
  csuite text := '\y(ceo|cfo|coo|cto|cmo|cio|cso|cpo|chro|cho|cco|cbo|cgo|cro|chief|presidente|president|vice presidente|vp|svp|evp|diretor geral|diretora geral|diretor executivo|diretora executiva|general director|managing director|general manager|country manager|conselheiro|conselheira|board|administrador|administradora|chairma[nm]|chairwoman|c level|secretari[ao] (de estado|municipal|estadual|de governo|nacional)|subsecretari[ao]|prefeit[ao]|vice prefeit[ao]|ministr[ao]|governador|governadora|deputad[ao]|senador|senadora)\y';
  diretor text := '\y(diretor|diretora|director|directora|diretoria|dir|head|superintendente|superintendent|supte|superintendencia|senior executive|gerente geral|gerente executivo|gerente executiva|dean|senior vice president|executive)\y';
  gestor text := '\y(gerente|gestor|gestora|manager|coordenador|coordenadora|coordinator|coordenacao|coord|ger|gte|gerencia|supervisor|supervisora|sup|lider|lideranca|leader|lead|chefe|chefia|encarregado|encarregada|gestao|responsavel|ouvidor|ouvidora)\y';
  analista text := '\y(analista|analyst|especialista|specialist|assistente|assistant|auxiliar|estagiario|estagiaria|trainee|generalista|tecnico|tecnica|jovem aprendiz|aprendiz|assessor|assessora|colaborador|colaboradora|funcionario|funcionaria|executivo|executiva|account|vendedor|vendedora|sales|representante|secretaria|secretario|associate)\y';
  saude text := '\y(psicolog[ao]|psicologia|psychologist|psychology|psicanalista|psiquiatra|psychiatrist|medic[ao]|medicina|physician|terapeuta|therapist|psicoterapeuta|enfermeir[ao]|enfermagem|nurse|nutricionista|fisioterapeuta|fonoaudiolog[ao]|assistente social|neuropsicolog[ao]|medicina do trabalho|ergonomista|farmaceutic[ao]|dentista|dentist|odontolog[ao]|educador fisico|educadora fisica|educador[a]? respiratori[ao]|profissional de saude|terapia|acupunturista|neurocientista|clinica|clinical|assistencial|nutrolog[ao])\y';
  consultor text := '\y(consultor|consultora|consultant|consultoria|consulting|coach|coaching|mentor|mentora|mentoria|palestrante|speaker|facilitador|facilitadora|trainer|treinador|treinadora|instrutor|instrutora|advisor|autonomo|autonoma|freelancer|prestador|prestadora|profissional liberal|escritor|escritora|autor|autora)\y';
  academia text := '\y(professor|professora|teacher|docente|pesquisador|pesquisadora|researcher|estudante|student|aluno|aluna|universitario|universitaria|mestrando|mestranda|doutorando|doutoranda|pos graduando|pos graduanda|graduando|graduanda|academico|academica|phd|educador|educadora|educator|pedagog[ao]|pedagogia|escola|school|faculdade|universidade|university)\y';
  nao_executivo text := '\y(executive assistant|assistente executiv[ao]|secretari[ao] executiv[ao]|account executive|sales executive|executiv[ao] de (contas|vendas|negocios|atendimento)|product owner|scrum master|head ?hunter)\y';
begin
  -- concorrente é pela empresa, seja qual for o cargo
  if e is not null then
    select i.codigo into v_conc from intelligence.icp i
     where i.ativo and i.regex_empresa is not null and e ~ i.regex_empresa
     order by i.ordem limit 1;
    if v_conc is not null then return v_conc; end if;
  end if;
  if c is null or c in ('x', 'n a', 'na', 'nao', 'nenhum', 'nenhuma', 'outro', 'outros', 'sem cargo') then return null; end if;

  -- quem não está no mercado de trabalho corporativo
  if c ~ '\y(dona de casa|do lar|aposentad[ao])\y' then return 'outros'; end if;
  -- "executive"/"owner"/"head" que não são executivos
  if c ~ nao_executivo then
    return case when c ~ rh then 'analista_bp_rh' else 'analista_nao_rh' end;
  end if;

  -- RH com nível decide antes de saúde ("Gerente Médica Saúde Corporativa" compra para a empresa)
  if c ~ rh and c !~ consultor and (c ~ csuite or c ~ diretor or c ~ gestor) then
    if c ~ csuite or c ~ diretor then return 'chro_vp_diretor_rh'; end if;
    return 'gestor_rh';
  end if;
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
comment on function intelligence.icp_por_cargo(text, text) is 'ICP (intelligence.icp.codigo) a partir do cargo escrito em campo livre e da empresa (concorrente). Ordem: concorrente pela empresa → fora do mercado (outros) → "executive"/owner que não é executivo → RH com nível → saúde → RH (consultor, BP/analista, decisor, gestor) → consultor/coach → academia → fundador/sócio → C-suite/executivo público → diretor → gestor → analista → outros. Aceita siglas e abreviações (C&B, D&I, L&D, NR-1, SST, coord, ger, dir, supte).';

-- 6. texto_exibir
create or replace function intelligence.texto_exibir(p_texto text)
returns text language plpgsql immutable as $fn$
declare
  s text; w text; partes text[] := '{}'; i int := 0;
  siglas text[] := array['rh','hr','hrbp','bp','dho','dp','ceo','cfo','coo','cto','cmo','cio','cso','cpo','chro','cho','cro','cco','cbo','cgo','vp','svp','evp','ti','it','esg','b2b','b2c','pmo','cs','cx','ux','ui','ia','ai','ehs','hse','ssma','qsma','sesmt','sst','ong','sa','s.a.','s/a','ltda','me','epp','mba','usp','ufrj','ufmg','puc','fgv','abrh','sp','rj','mg','ba','rs','pr','sc','go','df','pe','ce','eua','uk','usa','latam','br','crm','erp','pj','clt','kam','sdr','bdr','gm','md','nps','okr','kpi','p&d','r&d','m&a','fp&a','sus','inss','abnt','nr','nr-1','gro','pgr','pcmso','t&d','d&i','dei','l&d','tv','qa','bwg','bdf','mrs','bv','hcor','abc','ti/to','sgq','ti.'];
  -- em caixa mista só se corrigem siglas inequívocas (nada de "me", "sa", siglas de estado)
  siglas_mistas text[] := array['rh','hr','hrbp','bp','dho','dp','ceo','cfo','coo','cto','cmo','cio','cso','cpo','chro','cho','cro','cco','cbo','cgo','vp','svp','evp','ti','esg','b2b','b2c','pmo','cs','cx','ux','ui','ia','ehs','hse','ssma','qsma','sesmt','sst','ong','ltda','mba','crm','erp','pj','clt','kam','sdr','bdr','nps','okr','kpi','sus','inss','nr','nr-1','gro','pgr','pcmso','dei','qa','latam'];
  minusculas text[] := array['de','da','do','das','dos','e','em','para','por','com','of','and','the','a','o','as','os','na','no','nas','nos','ao','aos','du','del','y','à','às'];
begin
  if p_texto is null then return null; end if;
  s := btrim(regexp_replace(p_texto, '\s+', ' ', 'g'));
  s := regexp_replace(s, '\s*/\s*', ' / ', 'g');
  s := regexp_replace(s, '[\s.,;:]+$', '', 'g');
  if s = '' then return null; end if;
  if s <> upper(s) and s <> lower(s) then
    -- caixa mista: respeita o que a pessoa escreveu, só levanta siglas ("gerente Rh" → "gerente RH") e a inicial
    s := (select string_agg(case when lower(t.w) = any(siglas_mistas) then upper(t.w) else t.w end, ' ' order by t.ord)
            from regexp_split_to_table(s, ' ') with ordinality t(w, ord));
    return upper(left(s, 1)) || substr(s, 2);
  end if;
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
comment on function intelligence.texto_exibir(text) is 'Forma de exibição de cargo/empresa escrita em campo livre: Título quando veio tudo em minúsculas/maiúsculas (siglas como RH, CEO, S.A. preservadas); em caixa mista mantém o texto, levantando só siglas inequívocas e a inicial.';

-- 2, 4 e 5. projeção
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
      select * into v_exist from intelligence.participante_memoria pm
       where pm.mind_id = p_mind and pm.chave = 'jtbd:' || r.codigo and pm.status in ('ativa', 'proposta')
       order by (pm.status = 'ativa') desc, pm.atualizado_em desc limit 1;
      if not found then
        insert into intelligence.participante_memoria (mind_id, tipo, chave, valor, confianca, origem, status)
        values (p_mind, 'jtbd', 'jtbd:' || r.codigo, v_valor, r.conf, 'regra_perfil', v_status);
        v_novas := v_novas + 1;
      elsif v_exist.origem = 'regra_perfil' then
        if v_status = 'ativa' and exists (select 1 from intelligence.participante_memoria pm
             where pm.mind_id = p_mind and pm.chave = 'jtbd:' || r.codigo and pm.status = 'ativa' and pm.id <> v_exist.id) then
          v_status := 'proposta';   -- já existe uma ativa de outra origem
        end if;
        -- a regra segue o recálculo: pode rebaixar o que ela mesma promoveu
        if v_exist.valor is distinct from v_valor or v_exist.confianca is distinct from r.conf or v_exist.status is distinct from v_status then
          update intelligence.participante_memoria
             set valor = v_valor, confianca = r.conf, status = v_status, atualizado_em = now()
           where id = v_exist.id;
          v_alteradas := v_alteradas + 1;
        end if;
      end if;   -- memória de conversa (analise_*): fica como está
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
