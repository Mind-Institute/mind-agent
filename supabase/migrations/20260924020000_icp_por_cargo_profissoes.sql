-- ICP por cargo: profissões viram "Analista / Especialista / Contribuidor individual (não RH)"
-- (Adriana, 24/09/2026). "Outros" fica para quem está fora do mercado ou não escreveu um cargo.
-- Psicopedagoga, educação física, psicodinamista e aplicadora ABA vão para psicólogo/saúde.
-- Consultor ganha as traduções "author" e "facilitator". As profissões são checadas antes da
-- correção de digitação: "engenheiro" está a 2 letras de "enfermeiro".

CREATE OR REPLACE FUNCTION intelligence.icp_por_cargo(p_cargo text, p_empresa text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  c text := intelligence.texto_chave(p_cargo);
  e text := intelligence.texto_chave(p_empresa, true);
  v_conc text;
  v_corrigido text;
  rh text := '\y(rh|hr|hrd|recursos humanos|human resources?|people|pessoas|gente|talent|talentos|talent acquisition|talent management|gestao de talentos|capital humano|human capital|desenvolvimento de pessoas|people partner|dho|desenvolvimento humano|cultura|culture|people ops|hrbp|business partner|bp|chro|cho|cpo|chief people|chief happiness|dp|departamento pessoal|beneficios|benefits|remuneracao|rewards|c e b|comp e ben|compensation|total rewards|t e d|l e d|treinamento|desenvolvimento organizacional|recrutamento|selecao|recrutador|recrutadora|recruiter|headhunter|head hunter|educacao corporativa|learning|clima|bem estar|bemestar|wellbeing|well being|saude mental|saude e bem estar|saude corporativa|saude ocupacional|occupational health|qualidade de vida|felicidade corporativa|happiness|employer branding|experiencia do colaborador|employee experience|onboarding|pessoas e cultura|gente e gestao|gestao de pessoas|relacoes do trabalho|labor relations|engajamento|engagement|inclusao|diversidade|diversity|inclusion|d e i|de e i|dei|ssma|qsma|sesmt|sst|ehs|hse|seguranca do trabalho|saude e seguranca|saude e seguranca do trabalho|riscos psicossociais|nr ?0?1)\y';
  bp text := '\y(business partner|bp|hrbp|analista|analyst|especialista|specialist|assistente|assistant|auxiliar|estagiario|estagiaria|trainee|generalista|tecnico|tecnica|recrutador|recrutadora|recruiter|consultor interno|consultora interna|aprendiz|professional|profissional)\y';
  fundador text := '\y(fou?nder|co fou?nder|cofou?nder|fundador|fundadora|cofundador|cofundadora|co fundador|co fundadora|idealizador|idealizadora|socio|socia|proprietario|proprietaria|dono|dona|empresario|empresaria|empreendedor|empreendedora|owner|(?<!business )partner|managing partner|acionista)\y';
  csuite text := '\y(ceo|cfo|coo|cto|cmo|cio|cso|cpo|chro|cho|cco|cbo|cgo|cro|chief|presidente|president|vice presidente|vp|svp|evp|diretor geral|diretora geral|diretor executivo|diretora executiva|general director|managing director|general manager|country manager|conselheiro|conselheira|board|administrador|administradora|chairma[nm]|chairwoman|c level|secretari[ao] (de estado|municipal|estadual|de governo|nacional)|subsecretari[ao]|prefeit[ao]|vice prefeit[ao]|ministr[ao]|governador|governadora|deputad[ao]|senador|senadora)\y';
  diretor text := '\y(diretor|diretora|director|directora|diretoria|direcao|dir|head|superintendente|superintendent|supte|superintendencia|senior executive|gerente geral|gerente executivo|gerente executiva|dean|senior vice president|executive)\y';
  gestor text := '\y(gerente|gestor|gestora|manager|coordenador|coordenadora|coordinator|coordenacao|coord|ger|gte|gerencia|supervisor|supervisora|sup|lider|lideranca|leader|lead|chefe|chefia|encarregado|encarregada|gestao|responsavel|ouvidor|ouvidora)\y';
  analista text := '\y(analista|analyst|especialista|specialist|assistente|assistant|auxiliar|estagiario|estagiaria|trainee|generalista|tecnico|tecnica|jovem aprendiz|aprendiz|assessor|assessora|colaborador|colaboradora|funcionario|funcionaria|executivo|executiva|account|vendedor|vendedora|sales|representante|secretaria|secretario|associate)\y';
  saude text := '\y(psicolog[ao]|psicologia|psychologist|psychology|psicanalista|psiquiatra|psychiatrist|medic[ao]|medicina|physician|terapeuta|therapist|psicoterapeuta|enfermeir[ao]|enfermagem|nurse|nutricionista|fisioterapeuta|fonoaudiolog[ao]|assistente social|neuropsicolog[ao]|medicina do trabalho|ergonomista|farmaceutic[ao]|dentista|dentist|odontolog[ao]|educador fisico|educadora fisica|educador[a]? respiratori[ao]|profissional de saude|terapia|acupunturista|neurocientista|clinica|clinical|assistencial|nutrolog[ao])\y';
  consultor text := '\y(consultor|consultora|consultant|consultoria|consulting|coach|coaching|mentor|mentora|mentoria|palestrante|speaker|facilitador|facilitadora|trainer|treinador|treinadora|instrutor|instrutora|advisor|autonomo|autonoma|freelancer|prestador|prestadora|profissional liberal|escritor|escritora|autor|autora|author|facilitator)\y';
  academia text := '\y(professor|professora|teacher|docente|pesquisador|pesquisadora|researcher|estudante|student|aluno|aluna|universitario|universitaria|mestrando|mestranda|doutorando|doutoranda|pos graduando|pos graduanda|graduando|graduanda|academico|academica|phd|educador|educadora|educator|pedagog[ao]|pedagogia|escola|school|faculdade|universidade|university)\y';
  -- profissões e áreas de atuação sem nível de gestão: contribuidor individual (Adriana, 24/09)
  profissao text := '\y(advogad[ao]|lawyer|attorney|counsel|jornalista|journalist|reporter|colunista|redator|redatora|editor|editora|publisher|arquitet[ao]|architect|economista|economist|engenheir[ao]|engineer|eng|designer|marketing|compliance|data protection officer|auditor|auditora|fiscal|juiz|juiza|delegad[ao]|policial|sgt|sargento|militar|pmo|csm|customer suc+ess|customer service|comercial|commercial|comunicacao|relacoes publicas|relacoes institucionais|influenciador|influenciadora|videomaker|curador|curadora|administrativ[ao]|agente de administracao|administrator|qa|inspetor|inspetora|comprador|compradora|banker|merchant|confeiteir[ao]|confectioner|chef|biller|monitor|tec|projeto|projetos|esg|ombudsman|product development|go to market|finance operations|politicas publicas)\y';
  -- profissões de saúde e desenvolvimento que a regra de saúde não pegava
  profissao_saude text := '\y(psicopedagog[ao]|educacao fisica|psicodinamista|aba)\y';
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

  -- profissões antes da correção de digitação ("engenheiro" não pode virar "enfermeiro")
  if c ~ profissao_saude then return 'psicologo_saude'; end if;
  if c ~ profissao then return 'analista_nao_rh'; end if;

  -- nada reconhecido: tenta de novo com a digitação corrigida (uma vez; o texto corrigido não muda mais)
  v_corrigido := intelligence.cargo_corrigir_digitacao(c);
  if v_corrigido is distinct from c then
    return intelligence.icp_por_cargo(v_corrigido, null);
  end if;
  return 'outros';
end $function$;
