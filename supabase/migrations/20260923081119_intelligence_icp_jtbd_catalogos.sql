-- =====================================================================================
-- Catálogos de ICP e JTBD no schema intelligence + perfil profissional por regra
-- 23/09/2026 — pedido da Adriana:
--   "pode fazer essas mudanças em JTBD na base e colocar todas as pessoas que foram no
--    summit para passar por essa classificação" · "coloque também uma tabela com ICP" ·
--   "estes dois devem ser criados no schema intelligence e updated/created em propriedades
--    do hubspot" · "usar o que as pessoas escreveram de empresa e cargo para fazer update
--    em cargo no hubspot, empresa no hubspot (sempre checando por ser campo livre...)".
--
-- O que nasce aqui (tabela nova = D2, aprovada por ela nas frases acima):
--   intelligence.icp   — os perfis (ICP), separando RH, com o rótulo antigo do HubSpot quando
--                        existe (a opção do HubSpot é renomeada, o valor interno não muda);
--   intelligence.jtbd  — os jobs to be done: 13 jobs "mind" (linguagem comercial dela, ligados aos
--                        produtos no ar, vão para o HubSpot) + os 15 jobs-raiz JT01–JT15 do estudo
--                        (vocabulário do analisador de conversas), com a tradução raiz → mind;
--   summit_2026.sessions.jtbd — que jobs cada sessão ajuda a resolver (evidência de quem reservou
--                        ou fez check-in).
-- Onde fica a inteligência de cada pessoa: continua em intelligence.participante_memoria
-- (tipo icp / jtbd / cargo / empresa), lida por mind_customer_intelligence. Nada de casa nova
-- para pessoa. O escritor analise_projetar_memoria e o leitor passam a validar pelos catálogos
-- em vez de listas fixas no corpo.
-- =====================================================================================

create table if not exists intelligence.icp (
  codigo            text primary key,
  rotulo            text not null unique,
  rotulo_legado     text unique,
  hubspot_valor     text unique,
  hubspot_opcao     boolean not null default true,
  familia           text not null check (familia in ('rh', 'lideranca', 'especialista', 'mercado', 'outro')),
  rh                boolean not null default false,
  compra_patrocinio boolean not null default false,
  descricao         text,
  exemplos          text[] not null default '{}',
  regex_empresa     text,
  ordem             smallint not null,
  ativo             boolean not null default true,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now()
);
comment on table intelligence.icp is 'Catálogo dos perfis de cliente ideal (ICP) do Mind — de que lugar profissional a pessoa fala. Fonte única do vocabulário: a propriedade icp do HubSpot é espelho deste catálogo (rotulo = label da opção; hubspot_valor = valor interno, que não muda). A classificação de cada pessoa fica em intelligence.participante_memoria (tipo icp, chave icp_atual). Regra de cargo: intelligence.icp_por_cargo().';
comment on column intelligence.icp.codigo is 'Identificador estável do perfil (slug). É o code guardado em participante_memoria.valor.';
comment on column intelligence.icp.rotulo is 'Nome do perfil como aparece no HubSpot (label da opção) e para o Agent.';
comment on column intelligence.icp.rotulo_legado is 'Texto da opção antiga da propriedade icp do HubSpot (as 6 de 02/09/2026) que este perfil substitui pelo significado; o escritor aceita os dois e grava o novo.';
comment on column intelligence.icp.hubspot_valor is 'Valor interno da opção na propriedade icp do HubSpot (o que a API escreve). Nulo = não vai para o HubSpot.';
comment on column intelligence.icp.hubspot_opcao is 'Se este perfil é uma opção da propriedade icp do HubSpot (o concorrente não é).';
comment on column intelligence.icp.familia is 'Agrupamento para regras de contexto: rh, lideranca (fora do RH), especialista (consultor/saúde), mercado (marketing/comunicação/ESG), outro.';
comment on column intelligence.icp.rh is 'A pessoa é do RH da própria empresa (decisor ou executor interno de pessoas/bem-estar).';
comment on column intelligence.icp.compra_patrocinio is 'Perfil que costuma decidir patrocínio/ativação no Mind Summit (RH decisor, CEO, fundador, diretor).';
comment on column intelligence.icp.exemplos is 'Cargos reais que caem neste perfil, para leitura humana e teste.';
comment on column intelligence.icp.regex_empresa is 'Só para perfis definidos pela empresa (concorrente): expressão regular aplicada ao nome normalizado da empresa (intelligence.texto_chave). Adriana acrescenta concorrentes aqui.';

create table if not exists intelligence.jtbd (
  codigo        text primary key,
  rotulo        text not null unique,
  pergunta      text,
  nivel         text not null check (nivel in ('mind', 'raiz')),
  produtos      text[] not null default '{}',
  icps_tipicos  text[] not null default '{}',
  jt_raiz       text[] not null default '{}',
  sinais        jsonb not null default '{}'::jsonb,
  hubspot_valor text unique,
  hubspot_opcao boolean not null default false,
  descricao     text,
  ordem         smallint not null,
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
comment on table intelligence.jtbd is 'Catálogo dos jobs to be done (o que a pessoa está tentando realizar). Dois níveis: mind = os 13 jobs na linguagem comercial da Adriana, ligados aos produtos no ar (catalogo.produtos.codigo) e espelhados na propriedade jtbd do HubSpot; raiz = os 15 jobs-raiz JT01–JT15 do estudo, vocabulário do analisador de conversas, traduzidos para o nível mind por jt_raiz. A observação por pessoa fica em intelligence.participante_memoria (tipo jtbd, chave jtbd:<codigo>). Regras de evidência: intelligence.perfil_projetar().';
comment on column intelligence.jtbd.codigo is 'Identificador estável (slug para o nível mind; JT01–JT15 para o nível raiz). É o code em participante_memoria.valor e a chave jtbd:<codigo>.';
comment on column intelligence.jtbd.pergunta is 'A pergunta que a pessoa está tentando responder quando tem este job.';
comment on column intelligence.jtbd.nivel is 'mind (comercial, vai para o HubSpot) ou raiz (JT01–JT15 do estudo, vocabulário do analisador).';
comment on column intelligence.jtbd.produtos is 'catalogo.produtos.codigo dos produtos no ar que resolvem este job.';
comment on column intelligence.jtbd.icps_tipicos is 'intelligence.icp.codigo dos perfis em que este job costuma aparecer. Contexto, nunca inferência: ICP não vira JTBD sozinho.';
comment on column intelligence.jtbd.jt_raiz is 'Para o nível mind: quais jobs-raiz (JT01–JT15) observados em conversa se traduzem neste job. Filtros por raiz em sinais.jt_filtro.';
comment on column intelligence.jtbd.sinais is 'Regras de evidência lidas por intelligence.perfil_projetar(): interesses {chave da jornada do app: confiança}; jt_filtro {JTxx: {contexto_regex, contexto_regex_excluir, familias}}; contextual {de: [jobs], familias: [...], confianca}; conversa {preferred_product_regex}; patrocinio true.';
comment on column intelligence.jtbd.hubspot_valor is 'Valor interno da opção na propriedade jtbd (multi-seleção) do HubSpot. Nulo = não vai para o HubSpot.';
comment on column intelligence.jtbd.hubspot_opcao is 'Se este job é uma opção da propriedade jtbd do HubSpot (só o nível mind).';

alter table summit_2026.sessions add column if not exists jtbd text[] not null default '{}';
comment on column summit_2026.sessions.jtbd is 'intelligence.jtbd.codigo (nível mind) que esta sessão ajuda a resolver. Reservar ou fazer check-in nela é evidência desses jobs para a pessoa (intelligence.perfil_projetar). Vazio = sessão sem conteúdo (credenciamento, intervalo, autógrafos) ou ainda não classificada.';

-- ---------------------------------------------------------------------------------------
-- ICP — as 13 opções que a Adriana deixou na propriedade icp do HubSpot em 23/09 (rotulo = label,
-- hubspot_valor = valor interno; ela reaproveitou 3 valores antigos com significado novo) + o marcador
-- de concorrente. rotulo_legado traduz o TEXTO antigo pelo significado (memórias já gravadas).
-- ---------------------------------------------------------------------------------------
insert into intelligence.icp (codigo, rotulo, rotulo_legado, hubspot_valor, hubspot_opcao, familia, rh, compra_patrocinio, descricao, exemplos, regex_empresa, ordem) values
('chro_vp_diretor_rh', 'CHRO / VP / Diretor(a) de RH ou Pessoas', 'CHRO / VP de Pessoas', 'CHRO / VP de Pessoas', true, 'rh', true, true,
 'Quem decide a agenda de pessoas e bem-estar da empresa: CHRO, VP, diretor(a) ou head de RH / Pessoas / Gente e Gestão / DHO, inclusive saúde, segurança e bem-estar corporativo (SSMA, SESMT).',
 array['Diretora de RH', 'CHRO', 'Head of People and Talent', 'VP de Benefícios', 'Chief Happiness Officer'], null, 1),
('ceo_csuite', 'CEO / C-Suite', 'CEO / C-Suite', 'CEO / C-Suite', true, 'lideranca', false, true,
 'Quem dirige a empresa como executivo: CEO, presidente, diretor(a) executivo(a), C-level fora do RH (CFO, COO, CTO, CMO…), conselheiro(a).',
 array['CEO', 'COO', 'Presidente', 'Diretora Executiva', 'CMO'], null, 2),
('fundador_socio', 'Fundador / Sócio / Empreendedor', null, 'Fundadot / Sócio / Empreendedor', true, 'lideranca', false, true,
 'Quem é dono(a) do negócio: fundador(a), cofundador(a), sócio(a), proprietário(a), empresário(a), empreendedor(a) — mesmo quando também se diz CEO. (Opção criada pela Adriana no HubSpot com o valor interno "Fundadot"; corrigir só o rótulo lá.)',
 array['Founder', 'Fundadora', 'Sócia', 'CEO e Fundadora', 'Empresária'], null, 3),
('diretor_vp_nao_rh', 'Diretor(a) / VP / Executivo(a) sênior (não RH)', 'Executivo Sênior / Alto Performer', 'Gestor / Middle Manager', true, 'lideranca', false, false,
 'Diretor(a), VP, head ou superintendente de uma área que não é RH (o "executivo sênior" da taxonomia antiga). No HubSpot a opção reaproveita o valor interno antigo "Gestor / Middle Manager".',
 array['Diretora Comercial', 'Diretor de Operações', 'Head', 'Superintendente'], null, 4),
('gestor_nao_rh', 'Gestor(a) / Middle Management (não RH)', 'Gestor / Middle Manager', 'People Leader / Business Partner', true, 'lideranca', false, false,
 'Gerente, coordenador(a), supervisor(a) ou líder de equipe fora do RH. No HubSpot a opção reaproveita o valor interno antigo "People Leader / Business Partner".',
 array['Gerente de Projetos', 'Coordenador', 'Supervisor', 'Gerente Comercial', 'Gerente de Marketing'], null, 5),
('analista_nao_rh', 'Analista / Especialista / Contribuidor individual (não RH)', null, 'Executivo Sênior / Alto Performer', true, 'outro', false, false,
 'Analista, especialista, assistente, assessor(a) ou estagiário(a) fora do RH. No HubSpot a opção reaproveita o valor interno antigo "Executivo Sênior / Alto Performer".',
 array['Analista', 'Assessora', 'Estagiário', 'Executivo Comercial', 'Analista de Marketing'], null, 6),
('consultor_coach', 'Consultor / Coach / Psicólogo', 'Consultor / Coach / Psicólogo', 'Consultor / Coach / Psicólogo', true, 'especialista', false, false,
 'Consultor(a), coach, mentor(a), palestrante, facilitador(a) ou profissional autônomo(a) fora da saúde e do RH (o rótulo antigo do HubSpot ficou; psicólogos têm perfil próprio).',
 array['Consultora', 'Coach', 'Palestrante', 'Mentora', 'Advisor'], null, 7),
('professor_pesquisador_estudante', 'Professor(a) / Pesquisador(a) / Estudante', null, 'Professor(a) / Pesquisador(a) / Estudante', true, 'outro', false, false,
 'Docentes, pesquisadores, educadores e estudantes (estudantes de psicologia ficam com os psicólogos).',
 array['Professora Universitária', 'Estudante', 'Pesquisador', 'Educadora Parental'], null, 8),
('psicologo_saude', 'Psicólogo(a) / Profissional de saúde e bem-estar', null, 'Psicólogo(a) / Profissional de saúde e bem-estar', true, 'especialista', false, false,
 'Psicólogo(a), psicanalista, terapeuta, médico(a), enfermeiro(a), nutricionista e outros profissionais de saúde e bem-estar (inclusive quem ainda estuda psicologia).',
 array['Psicóloga', 'Psicóloga Organizacional', 'Médica do Trabalho', 'Terapeuta', 'Nutricionista'], null, 9),
('outros', 'Outros', null, 'Outros', true, 'outro', false, false,
 'Cargo informado que não cabe nos perfis acima (advogado, jornalista, engenheiro, servidor público…).',
 array['Advogada', 'Jornalista', 'Economista', 'Delegada de Polícia'], null, 10),
('gestor_rh', 'Gestor(a) de RH (gerente / coordenador)', null, 'Gestor(a) de RH (gerente / coordenador)', true, 'rh', true, false,
 'Gerente, coordenador(a) ou supervisor(a) de RH / Pessoas / DHO / Cultura / T&D / saúde e bem-estar corporativo.',
 array['Gerente de RH', 'Coordenadora de RH', 'Gerente de Saúde e Bem-Estar', 'Gerente de DHO'], null, 11),
('analista_bp_rh', 'Analista / BP / Especialista de RH', 'People Leader / Business Partner', 'Analista / BP / Especialista de RH', true, 'rh', true, false,
 'Analista, especialista, business partner (HRBP) ou generalista de RH; quem escreve só "RH" cai aqui.',
 array['Analista de RH', 'HR Business Partner', 'HRBP', 'Especialista RH'], null, 12),
('consultor_rh', 'Consultor(a) de RH e cultura', null, 'Consultor(a) de RH e cultura', true, 'especialista', false, false,
 'Consultor(a) externo(a) de RH, cultura organizacional, bem-estar corporativo ou desenvolvimento humano.',
 array['Consultora de RH', 'Consultora em Cultura Organizacional', 'Consultor em Bem-Estar, Saúde e Benefícios'], null, 13),
('concorrente', 'Concorrente (não é ICP)', null, null, false, 'outro', false, false,
 'Pessoa de empresa concorrente do Mind: não é cliente potencial, seja qual for o cargo ("Vittude competidor, fecha nada" — Adriana, 23/09). Lista de empresas em regex_empresa, aplicada ao nome normalizado (intelligence.texto_chave).',
 array['qualquer cargo na Vittude'], '\yvittude\y', 99)
on conflict (codigo) do update set
  rotulo = excluded.rotulo, rotulo_legado = excluded.rotulo_legado, hubspot_valor = excluded.hubspot_valor,
  hubspot_opcao = excluded.hubspot_opcao, familia = excluded.familia, rh = excluded.rh,
  compra_patrocinio = excluded.compra_patrocinio, descricao = excluded.descricao, exemplos = excluded.exemplos,
  regex_empresa = excluded.regex_empresa, ordem = excluded.ordem, atualizado_em = now();

-- ---------------------------------------------------------------------------------------
-- JTBD nível mind — os 13 jobs da Adriana (7 dela + 6 derivados dos jobs-raiz do estudo),
-- cada um ligado aos produtos no ar. Vão para a propriedade jtbd do HubSpot.
-- ---------------------------------------------------------------------------------------
insert into intelligence.jtbd (codigo, rotulo, pergunta, nivel, produtos, icps_tipicos, jt_raiz, sinais, hubspot_valor, hubspot_opcao, descricao, ordem) values
('boa_empregadora', 'Posicionar a empresa como boa empregadora',
 'Como mostrar ao mercado e aos talentos que a minha empresa cuida de quem trabalha nela?', 'mind',
 array['mind-summit-2026'], array['chro_vp_diretor_rh', 'ceo_csuite', 'fundador_socio', 'diretor_vp_nao_rh'], '{}',
 '{"interesses": {"jornada_temas_diversidade_e_inclusao": 0.5}}'::jsonb, 'Posicionar a empresa como boa empregadora', true,
 'Job de quem patrocina ou ativa marca empregadora no Summit (employer branding, D&I, marca).', 1),
('investidora_bem_estar', 'Posicionar a empresa como investidora em bem-estar',
 'Como posicionar a minha empresa como quem investe de verdade em bem-estar, saúde mental e liderança?', 'mind',
 array['mind-summit-2026'], array['chro_vp_diretor_rh', 'ceo_csuite', 'fundador_socio', 'diretor_vp_nao_rh'], '{}',
 '{"patrocinio": true}'::jsonb, 'Posicionar a empresa como investidora em bem-estar', true,
 'Job de quem fecha patrocínio ou parceria com o Mind; evidência vem de conversas com sinal de patrocínio.', 2),
('vender_para_rh', 'Vender minha solução para decisores de RH',
 'Como chegar aos decisores de RH e transformar minha expertise em algo que as empresas compram?', 'mind',
 array['mind-summit-2026'], array['consultor_coach', 'consultor_rh', 'psicologo_saude'], array['JT13'],
 '{"contextual": {"de": ["escolher_programas", "nr1_mensuracao", "provar_retorno"], "familias": ["especialista"], "confianca": 0.5}}'::jsonb, 'Vender minha solução para decisores de RH', true,
 'Fornecedores e consultores que querem acesso ao comprador de RH (expositor, patrocínio, networking qualificado).', 3),
('liderar_melhor', 'Aprender a liderar melhor (eu, como líder)',
 'Como liderar meu time com mais segurança psicológica, conversas difíceis bem conduzidas e engajamento real?', 'mind',
 array['mind-institute-lideranca-consciente-2027', 'mind-institute-seguranca-psicologica-2027', 'mind-institute-certificacao-lideranca-positiva-2027', 'mind-summit-2026'],
 array['gestor_nao_rh', 'diretor_vp_nao_rh', 'ceo_csuite', 'fundador_socio', 'gestor_rh'], array['JT04', 'JT05', 'JT06'],
 '{"interesses": {"jornada_objetivos_repensar_minha_forma_de_liderar": 0.7, "jornada_objetivos_levar_ideias_praticas_para_minha_equipe": 0.6, "jornada_temas_lideranca": 0.6, "jornada_temas_seguranca_psicologica": 0.5, "lideranca": 0.6, "lideranca_consciente": 0.6, "seguranca_psicologica": 0.5, "desenvolvimento_de_liderancas": 0.5}}'::jsonb, 'Aprender a liderar melhor (eu, como líder)', true,
 'Desenvolvimento do próprio líder (pessoa/equipe). Quando a pessoa é do RH, vira também "treinar_liderancas" (contexto).', 4),
('minha_saude_performance', 'Cuidar da minha saúde mental e performance',
 'Como sustentar minha performance, foco e energia sem me esgotar?', 'mind',
 array['mind-institute-lideranca-consciente-2027', 'mind-journey-2027', 'mind-summit-2026'],
 array['diretor_vp_nao_rh', 'ceo_csuite', 'fundador_socio', 'gestor_nao_rh'], array['JT01', 'JT02', 'JT03'],
 '{"interesses": {"jornada_temas_performance_sustentavel": 0.6, "burnout": 0.5}}'::jsonb, 'Cuidar da minha saúde mental e performance', true,
 'Job pessoal (não organizacional). Nunca persiste diagnóstico ou condição de saúde — só o objetivo profissional.', 5),
('escolher_programas', 'Escolher programas estratégicos de bem-estar para a empresa',
 'Quais programas de bem-estar e saúde mental fazem sentido para a minha empresa, e como escolher com critério?', 'mind',
 array['mind-institute-certificacao-gestao-estrategica-2027', 'mind-dash', 'mind-summit-2026'],
 array['chro_vp_diretor_rh', 'gestor_rh', 'analista_bp_rh', 'ceo_csuite', 'fundador_socio'], array['JT07', 'JT10'],
 '{"interesses": {"jornada_objetivos_estruturar_melhor_saude_mental_e_bem_estar": 0.7, "jornada_temas_saude_mental": 0.5, "gestao_estrategica_bem_estar": 0.7, "saude_mental": 0.5, "saude_mental_no_trabalho": 0.5}, "jt_filtro": {"JT07": {"contexto_regex_excluir": "nr.?1|psicossoc|pgr"}}}'::jsonb, 'Escolher programas estratégicos de bem-estar para a empresa', true,
 'Gestão estratégica de bem-estar no trabalho (o eixo 1 do Institute). JT07 sem menção a NR-1 cai aqui.', 6),
('escolher_consultoria', 'Escolher a consultoria que vai promover bem-estar na empresa',
 'Que parceiro externo pode diagnosticar, desenhar e implementar bem-estar na minha empresa?', 'mind',
 array['mind-dash'], array['chro_vp_diretor_rh', 'ceo_csuite', 'fundador_socio', 'gestor_rh'], '{}',
 '{"conversa": {"preferred_product_regex": "dash|consultoria"}}'::jsonb, 'Escolher a consultoria que vai promover bem-estar na empresa', true,
 'Job organizacional que pede diagnóstico e implementação: é o fit do Mind Dash.', 7),
('treinar_liderancas', 'Contratar treinamento de liderança para a empresa',
 'Como desenvolver os líderes e gestores da minha empresa de forma estruturada?', 'mind',
 array['mind-dash', 'mind-institute-certificacao-lideranca-positiva-2027'],
 array['chro_vp_diretor_rh', 'gestor_rh', 'analista_bp_rh'], array['JT04'],
 '{"interesses": {"desenvolvimento_de_liderancas": 0.6}, "jt_filtro": {"JT04": {"familias": ["rh"]}}, "contextual": {"de": ["liderar_melhor"], "familias": ["rh"], "confianca": 0.6}}'::jsonb, 'Contratar treinamento de liderança para a empresa', true,
 'Job B2B: só aparece quando quem mostra interesse em liderança é do RH (contexto), nunca por cargo sozinho.', 8),
('nr1_mensuracao', 'Cumprir a NR-1 e gerir riscos psicossociais com dados',
 'Como mensurar riscos psicossociais e transformar a NR-1 em gestão real, não só compliance?', 'mind',
 array['mind-dash', 'mind-institute-certificacao-gestao-estrategica-2027'],
 array['chro_vp_diretor_rh', 'gestor_rh', 'analista_bp_rh', 'consultor_rh'], array['JT07'],
 '{"interesses": {"jornada_temas_nr_1_e_riscos_psicossociais": 0.6, "nr_1": 0.6}, "jt_filtro": {"JT07": {"contexto_regex": "nr.?1|psicossoc|pgr"}}}'::jsonb, 'Cumprir a NR-1 e gerir riscos psicossociais com dados', true,
 'Mensuração de riscos psicossociais / NR-1 (produto Dash). JT07 com menção a NR-1, psicossocial ou PGR cai aqui.', 9),
('provar_retorno', 'Provar à diretoria o retorno de bem-estar (business case)',
 'Como mostrar ao board, com dados, que investir em bem-estar e liderança gera resultado?', 'mind',
 array['mind-dash', 'mind-institute-certificacao-gestao-estrategica-2027'],
 array['chro_vp_diretor_rh', 'analista_bp_rh', 'consultor_rh'], array['JT08'],
 '{"interesses": {"jornada_temas_dados_e_roi_do_bem_estar": 0.6}}'::jsonb, 'Provar à diretoria o retorno de bem-estar (business case)', true,
 'Business case, ROI, indicadores e influência (JT08).', 10),
('engajar_reter', 'Engajar e reter talentos',
 'Como criar condições para que as pessoas se conectem, contribuam e queiram ficar?', 'mind',
 array['mind-institute-significado-trabalho-2027', 'mind-dash'],
 array['chro_vp_diretor_rh', 'gestor_rh', 'ceo_csuite', 'fundador_socio', 'gestor_nao_rh'], array['JT09', 'JT10'],
 '{"interesses": {"jornada_temas_cultura_organizacional": 0.6, "jornada_temas_felicidade_e_proposito": 0.5, "proposito_no_trabalho": 0.5}}'::jsonb, 'Engajar e reter talentos', true,
 'Engajamento, significado, cultura e retenção (eixo 3 do Institute).', 11),
('autoridade_escala', 'Construir autoridade e escalar minha atuação como profissional de bem-estar',
 'Como me diferenciar com ciência e multiplicar meu impacto além do atendimento 1:1?', 'mind',
 array['mind-institute-certificacao-lideranca-positiva-2027', 'mind-institute-certificacao-gestao-estrategica-2027', 'mind-journey-2027'],
 array['consultor_coach', 'consultor_rh', 'psicologo_saude'], array['JT14', 'JT15'],
 '{"interesses": {"jornada_objetivos_conhecer_pesquisas_e_tendencias": 0.5}, "interesses_familias": ["especialista"], "contextual": {"de": ["escolher_programas", "nr1_mensuracao", "provar_retorno"], "familias": ["especialista"], "confianca": 0.6}}'::jsonb, 'Construir autoridade e escalar minha atuação como profissional de bem-estar', true,
 'Job de consultores, coaches e psicólogos que compram formação para ganhar autoridade e escala.', 12),
('encontrar_pares', 'Encontrar pares e trocar experiência',
 'Onde encontro pessoas que entendem a complexidade do meu papel para trocar e decidir melhor?', 'mind',
 array['mind-journey-2027', 'mind-summit-2026'], array['ceo_csuite', 'fundador_socio', 'diretor_vp_nao_rh', 'chro_vp_diretor_rh'], array['JT12'],
 '{"interesses": {"jornada_objetivos_fazer_conexoes_relevantes": 0.7}}'::jsonb, 'Encontrar pares e trocar experiência', true,
 'Networking qualificado e comunidade (Journey, Summit).', 13),
-- -------------------------------------------------------------------------------------
-- JTBD nível raiz — os 15 jobs do estudo (CUSTOMER_INTELLIGENCE_STEP2_TAXONOMY.md), que o
-- analisador de conversas continua emitindo. Não vão para o HubSpot; traduzem-se por jt_raiz.
-- -------------------------------------------------------------------------------------
('JT01', 'Sustentar performance e bem-estar pessoal no longo prazo', 'Como continuar performando sem consumir minha capacidade física, emocional e profissional?', 'raiz', '{}', '{}', '{}', '{}'::jsonb, null, false, 'Job-raiz do estudo. Traduz para minha_saude_performance.', 101),
('JT02', 'Preservar clareza e qualidade de decisão', 'Como proteger atenção, nitidez e capacidade cognitiva para as decisões que realmente importam?', 'raiz', '{}', '{}', '{}', '{}'::jsonb, null, false, 'Job-raiz do estudo. Traduz para minha_saude_performance.', 102),
('JT03', 'Navegar pressão, mudança e ambiguidade com adaptabilidade', 'Como permanecer eficaz e adaptável quando mudança e incerteza são permanentes?', 'raiz', '{}', '{}', '{}', '{}'::jsonb, null, false, 'Job-raiz do estudo. Traduz para minha_saude_performance.', 103),
('JT04', 'Desenvolver líderes e gestores', 'Como aumentar a capacidade real de quem lidera pessoas?', 'raiz', '{}', '{}', '{}', '{}'::jsonb, null, false, 'Job-raiz do estudo. Traduz para liderar_melhor; para quem é do RH, também treinar_liderancas.', 104),
('JT05', 'Conduzir conversas difíceis com accountability', 'Como cobrar, dar feedback e enfrentar problemas sem destruir confiança ou evitar o conflito?', 'raiz', '{}', '{}', '{}', '{}'::jsonb, null, false, 'Job-raiz do estudo. Traduz para liderar_melhor.', 105),
('JT06', 'Construir segurança psicológica e voz ativa', 'Como criar condições para que pessoas tragam problemas, discordem, perguntem, aprendam e assumam riscos interpessoais?', 'raiz', '{}', '{}', '{}', '{}'::jsonb, null, false, 'Job-raiz do estudo. Traduz para liderar_melhor.', 106),
('JT07', 'Estruturar gestão estratégica de bem-estar no trabalho e riscos psicossociais', 'Como transformar bem-estar, saúde mental no trabalho e riscos psicossociais em gestão real, e não ações isoladas ou compliance?', 'raiz', '{}', '{}', '{}', '{}'::jsonb, null, false, 'Job-raiz do estudo. Traduz para nr1_mensuracao quando o contexto fala de NR-1/psicossocial/PGR; senão, escolher_programas.', 107),
('JT08', 'Traduzir pessoas e bem-estar em business case, dados e influência', 'Como transformar evidência de pessoas/bem-estar em argumento que influencia decisões de negócio?', 'raiz', '{}', '{}', '{}', '{}'::jsonb, null, false, 'Job-raiz do estudo. Traduz para provar_retorno.', 108),
('JT09', 'Fortalecer engajamento, significado e retenção', 'Como criar condições para que as pessoas se conectem, contribuam, encontrem significado e queiram ficar?', 'raiz', '{}', '{}', '{}', '{}'::jsonb, null, false, 'Job-raiz do estudo. Traduz para engajar_reter.', 109),
('JT10', 'Construir cultura adaptativa e resiliência organizacional', 'Como fazer cultura e sistema de gestão sustentarem estratégia, mudança e performance em vez de bloqueá-las?', 'raiz', '{}', '{}', '{}', '{}'::jsonb, null, false, 'Job-raiz do estudo. Traduz para engajar_reter e escolher_programas.', 110),
('JT11', 'Liderar a dimensão humana da IA e do futuro do trabalho', 'Como capturar o valor da IA e das novas formas de trabalho sem perder pessoas, cultura, relevância ou qualidade da liderança?', 'raiz', '{}', '{}', '{}', '{}'::jsonb, null, false, 'Job-raiz do estudo. Ainda sem tradução comercial (nenhum produto no ar o resolve diretamente).', 111),
('JT12', 'Acessar pares e perspectivas para melhores decisões', 'Como sair do isolamento e ampliar perspectiva com pares que entendem a complexidade do meu papel?', 'raiz', '{}', '{}', '{}', '{}'::jsonb, null, false, 'Job-raiz do estudo. Traduz para encontrar_pares.', 112),
('JT13', 'Estruturar e vender soluções corporativas', 'Como transformar minha expertise em uma solução que empresas entendam, comprem e implementem?', 'raiz', '{}', '{}', '{}', '{}'::jsonb, null, false, 'Job-raiz do estudo. Traduz para vender_para_rh.', 113),
('JT14', 'Construir autoridade e credibilidade baseada em ciência', 'Como me diferenciar por profundidade, evidência e pensamento próprio em um mercado saturado?', 'raiz', '{}', '{}', '{}', '{}'::jsonb, null, false, 'Job-raiz do estudo. Traduz para autoridade_escala.', 114),
('JT15', 'Escalar expertise além do 1:1', 'Como multiplicar impacto e receita sem multiplicar horas na mesma proporção?', 'raiz', '{}', '{}', '{}', '{}'::jsonb, null, false, 'Job-raiz do estudo. Traduz para autoridade_escala.', 115)
on conflict (codigo) do update set
  rotulo = excluded.rotulo, pergunta = excluded.pergunta, nivel = excluded.nivel, produtos = excluded.produtos,
  icps_tipicos = excluded.icps_tipicos, jt_raiz = excluded.jt_raiz, sinais = excluded.sinais,
  hubspot_valor = excluded.hubspot_valor, hubspot_opcao = excluded.hubspot_opcao, descricao = excluded.descricao,
  ordem = excluded.ordem, atualizado_em = now();
