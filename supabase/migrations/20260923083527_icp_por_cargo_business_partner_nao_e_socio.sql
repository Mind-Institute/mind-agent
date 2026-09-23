-- icp_por_cargo: "Senior People Business Partner" caía em CHRO porque "partner" casava com a
-- regra de sócio. "business partner" é RH (BP); só "partner" solto é sócio.
create or replace function intelligence.icp_por_cargo(p_cargo text, p_empresa text default null)
returns text language plpgsql stable as $fn$
declare
  c text := intelligence.texto_chave(p_cargo);
  e text := intelligence.texto_chave(p_empresa, true);
  v_conc text;
  rh text := '\y(rh|hr|hrd|recursos humanos|human resources|people|pessoas|gente|talent|talentos|talent acquisition|dho|desenvolvimento humano|cultura|culture|people ops|hrbp|business partner|bp|chro|cho|cpo|chief people|chief happiness|dp|departamento pessoal|beneficios|benefits|remuneracao|rewards|t e d|treinamento|desenvolvimento organizacional|recrutamento|selecao|recrutador|recrutadora|recruiter|headhunter|educacao corporativa|learning|clima|bem estar|bemestar|wellbeing|well being|saude mental|saude e bem estar|saude corporativa|saude ocupacional|occupational health|qualidade de vida|employer branding|experiencia do colaborador|employee experience|onboarding|pessoas e cultura|gente e gestao|gestao de pessoas|relacoes do trabalho|labor relations|engajamento|engagement|inclusao|diversidade|ssma|qsma|sesmt|ehs|hse|seguranca do trabalho|saude e seguranca|riscos psicossociais)\y';
  bp text := '\y(business partner|bp|hrbp|analista|analyst|especialista|specialist|assistente|assistant|auxiliar|estagiario|estagiaria|trainee|generalista|tecnico|tecnica|recrutador|recrutadora|recruiter|consultor interno|consultora interna|aprendiz|professional|profissional)\y';
  fundador text := '\y(founder|co founder|cofounder|fundador|fundadora|cofundador|cofundadora|co fundador|co fundadora|idealizador|idealizadora|socio|socia|proprietario|proprietaria|dono|dona|empresario|empresaria|empreendedor|empreendedora|owner|(?<!business )partner|managing partner|acionista)\y';
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
