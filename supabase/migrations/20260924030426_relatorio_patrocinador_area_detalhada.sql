-- Relatório de valor para o patrocinador: "quebrar outras áreas de negócio" (Adriana, 24/09/2026).
-- "Outras áreas de negócio" tinha 382 presentes. Olhando os cargos, eram três coisas misturadas:
--   1. cargos de áreas que já existiam, mas escritos de outro jeito (jornalista, gerente jurídica,
--      gerente de suprimentos, head de e-commerce, training manager...) → voltam para a área certa;
--   2. funções que não tinham casa (SMS/segurança/ESG, serviço público, administrativo, relações
--      institucionais) → áreas novas;
--   3. só o nível, sem a área ("diretora", "gerente", "coordenador") → "Liderança sem área informada".
-- O que sobra vira "Outras funções". Mesma assinatura; a view já chama esta função, nada mais muda.

create or replace function intelligence.area_por_cargo(p_cargo text, p_icp text)
 returns text language sql immutable as $$
  select case
    when p_icp in ('chro_vp_diretor_rh', 'gestor_rh', 'analista_bp_rh', 'consultor_rh')
      or c ~ '\m(rh|recursos humanos?|pessoas|oessoas|people|talent|talentos|gente|cultura|dho|treinamento|treinamebto|training|t d|business partner|hrbp|hr|remuneracao|rem ben|beneficios|departamento pessoal|dp|endomarketing|clima|employee|relacoes trabalhistas|engajamento|engajamenro|aprendizagem|soft skills|desen comportamental|pagamento de pessoal)\M' then 'RH / Pessoas'
    when c ~ '\m(saude|medic[oa]|psicolog[oa]|enfermeir[oa]|enfermagem|bem estar|wellness|welness|wellbeing|ergonomia|nutricionista|fisioterapeuta|terapeuta|musicoterapeuta|psicanalista|psiquiatra|seguranca do trabalho|segurnaca do trabalho|sst|biopsicossocial|acolhimento|assistencial)\M'
      or p_icp = 'psicologo_saude' then 'Saúde e bem-estar'
    when p_icp in ('ceo_csuite', 'fundador_socio') then 'Gestão geral / C-level'
    when c ~ '\m(marketing|mkt|comunicacao|comunicacoes|communications|comunicativa|brand|marca|marcas|conteudo|content|eventos|relacoes publicas|pr|social media|jornalista|editora|editorial|colunista|criacao|criativa|videomaker|community|comunidade|imprensa)\M' then 'Marketing / Comunicação'
    when c ~ '\m(comercial|vendas|sales|negocios|negocio|key account|account|customer success|customer sucess|cs|csm|atendimento|relacionamento|relacionamentos|parcerias|expansao|ecommerce|ecomm|trade|executiv[oa] de contas|prospeccao|patrocinios|cx|cliente|clientes|crm|pos venda|otc)\M' then 'Comercial / Vendas'
    when c ~ '\m(estrategia|strategy|planejamento|inovacao|innovation|transformacao|projetos|projeto|project|program|pmo|processos|melhoria continua|excelencia operacional|otimizacao|inteligencia de mercado)\M' then 'Estratégia / Projetos'
    when p_icp = 'consultor_coach' or c ~ '\m(consultor|consultora|coach|mentor|mentora|facilitador|facilitadora)\M' then 'Consultoria / Coaching'
    when c ~ '\m(policia|policial|pmdf|pcdf|pm|delegad[oa]|servidor|servidora|fazendari[oa]|judiciari[oa]|trt\d*|ouvidor[a]?|sgt|tribunal|militar|defensor[a]?|promotor[a]?|procurador[a]?|prefeitura|politicas publicas|patrimonio da uniao|secretari[oa] de (educacao|governo|governk|estado|saude|fazenda))\M' then 'Serviço público'
    when p_icp = 'professor_pesquisador_estudante' or c ~ '\m(professor|professora|pesquisador|pesquisadora|pesquisas|estudante|educador|educadora|pedagog[oa]|pedagogico|educacao|educacional|educacionais|escolar|escola|ensino|senac)\M' then 'Educação / Academia'
    when c ~ '\m(financeiro|financeira|financas|finance|contabil|contabilidade|controladoria|fiscal|tax|tesouraria|economista|rentabilidade|rentabildade|riscos|patrimonial|regulatorio|juridico|juridica|advogad[oa]|compliance|auditoria)\M' then 'Finanças / Jurídico'
    when c ~ '\m(tecnologia|ti|dados|data|software|desenvolvedor|engenheiro de software|produto|product|ux|sistemas|analytics|digital)\M' then 'Tecnologia / Produto'
    when c ~ '\m(operacoes|operacao|operacional|operations|op|gop|logistica|producao|industrial|manutencao|manut|qualidade|engenharia|engineering|engenheir[oa]|supply|suprimentos|compras|tecnic[oa]|geotecnia|mineracao|obras|inspecao|inspetor|processamento|laboratorio|elevacao|escoamento|comercio exterior)\M' then 'Operações / Engenharia'
    when c ~ '\m(sms|ssmac|hesq|hse|qsms|seguranca|sustentabilidade|sustainability|esg|meio ambiente|ambiental)\M' then 'SMS, segurança e ESG'
    when c ~ '\m(administrativ[oa]|administracao|assessor|assessora|assistente|auxiliar|secretaria|secretario|apoio|backoffice|recepcionista|escritorio)\M' then 'Administrativo / Secretariado'
    when c ~ '\m(relacoes institucionais|institucional|desenvolvimento institucional|assuntos corporativos)\M' then 'Relações institucionais'
    when c ~ '^(diretor|diretora|director|diretoria|direcao|diretor a|dirrtor de departamento|diretor superintendente|gerente|gerente senior|gerente sr|gerente geral|gerente executiva|gerente executivo|senior manager|senior director|coordenador|coordenadora|coordenacao|coodenador|gestor|gestora|gestora geral|gestor geral|supervisor|supervisora|superintendente|superintendente senior|superintendente substituto ceara|lider|lider de time|lider de setor|lider de nucleo|lider de equipe|head|executivo|executiva|socio|socia|presidente|vice presidente|vp|responsavel)$'
      or (c is null and p_icp in ('gestor_nao_rh', 'diretor_vp_nao_rh')) then 'Liderança sem área informada'
    when c is null or c ~ '^(nenhum|nenhuma|outros|outro|mind|dodao)$' then 'Não informado'
    else 'Outras funções'
  end
  from (select intelligence.texto_chave(p_cargo) c) x
$$;
