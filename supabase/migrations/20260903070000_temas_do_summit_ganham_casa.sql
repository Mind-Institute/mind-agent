-- OS TEMAS DO SUMMIT GANHAM CASA NO BANCO — e as 77 sessões ganham etiqueta.
--
-- Desde a faxina de 22/08 (`summit` → `summit_2026`, `comum` → `ecossistema`) a taxonomia
-- `comum.taxonomy` não tinha sucessora. Ela era a fonte de DUAS coisas que o App consome
-- pelo `api.mindagent_bootstrap`: os dez temas que movem o motor de recomendação e o rótulo
-- de cada tipo de sessão. Sem casa, o bootstrap ficou apontando para um schema que não
-- existe, o App caiu no `dados/summit.json` de 28/08 (53 sessões) e o banco, com 77, tinha
-- `topicos_aprendizado` vazio em todas. Gate #26: "não consertar pela metade" — só reapontar
-- a função se o banco devolver temas sem regressão. Esta migration dá o lastro.
--
-- MENOR MUDANÇA:
--   1. `ecossistema.taxonomy` — a mesma forma da antiga (tipo, codigo, rotulo, ativo) mais
--      `ordem`. Provado que faltava casa: nenhuma tabela/view com taxonomia, tema ou tópico
--      em `ecossistema`, `summit_2026` ou `concierge`. Os dez temas são os que o App já usa
--      (conteúdo aprovado, em `dados/summit.json`); os catorze rótulos de tipo cobrem todos
--      os `tipo` que existem em `summit_2026.sessions`.
--   2. `summit_2026.speaker_profiles` — a curadoria que o App mostra por palestrante (foto,
--      destaque "Legend", credencial curta, resumo curto, temas) e que `palestrantes_
--      especialistas` não tem, porque lá mora conhecimento, não vitrine. Carregada com as 39
--      pessoas curadas do JSON; quem não tem perfil recebe credencial/resumo/temas derivados
--      na leitura, nunca inventados aqui.
--   3. `summit_2026.sessions.topicos_aprendizado` recebe os temas das 77 sessões, por
--      `site_session_id`. Onde a sessão existia no JSON de 28/08, os temas são os curados
--      lá; onde a programação mudou ou a sessão é nova (alumni talks, autógrafos,
--      lançamentos, Mind Talks), o tema vem do título/descrição e está marcado abaixo como
--      inferido — revisável no painel. Credenciamento, abertura, intervalos, almoços e
--      "em curadoria" ficam sem tema de propósito: não são conteúdo recomendável.
--
-- Idempotente: taxonomia por upsert; perfis só onde ainda não há; temas só onde ainda
-- está vazio. Falha alto se algum curado não casar com uma pessoa do banco.

-- ---------------------------------------------------------------------------
-- 1. Taxonomia
create table if not exists ecossistema.taxonomy (
  tipo          text        not null,
  codigo        text        not null,
  rotulo        text        not null,
  ordem         integer     not null default 0,
  ativo         boolean     not null default true,
  atualizado_em timestamptz not null default now(),
  primary key (tipo, codigo)
);
comment on table ecossistema.taxonomy is
  'Sucessora de comum.taxonomy: temas do Summit (tipo=tema) e rótulos de tipo de sessão (tipo=tipo_sessao). Lida por api.mindagent_bootstrap.';
alter table ecossistema.taxonomy enable row level security;
revoke all on ecossistema.taxonomy from public, anon, authenticated;

insert into ecossistema.taxonomy (tipo, codigo, rotulo, ordem) values
  ('tema', 'seguranca_psicologica', 'Segurança psicológica',       1),
  ('tema', 'dados_bem_estar',       'Dados e ROI do bem-estar',    2),
  ('tema', 'regulacao',             'NR-1 e riscos psicossociais', 3),
  ('tema', 'lideranca_humana',      'Liderança',                   4),
  ('tema', 'cultura',               'Cultura organizacional',      5),
  ('tema', 'saude_mental',          'Saúde mental',                6),
  ('tema', 'performance',           'Performance sustentável',     7),
  ('tema', 'diversidade',           'Diversidade e inclusão',      8),
  ('tema', 'felicidade',            'Felicidade e propósito',      9),
  ('tema', 'futuro_trabalho',       'Futuro do trabalho',         10),
  ('tipo_sessao', 'credenciamento', 'Credenciamento',       1),
  ('tipo_sessao', 'abertura',       'Abertura',             2),
  ('tipo_sessao', 'palestra',       'Palestra',             3),
  ('tipo_sessao', 'painel',         'Painel',               4),
  ('tipo_sessao', 'masterclass',    'Masterclass',          5),
  ('tipo_sessao', 'workshop',       'Workshop',             6),
  ('tipo_sessao', 'experiencia',    'Experiência',          7),
  ('tipo_sessao', 'alumni-talk',    'Alumni Talk',          8),
  ('tipo_sessao', 'entrevista',     'Entrevista',           9),
  ('tipo_sessao', 'lancamento',     'Lançamento de livro', 10),
  ('tipo_sessao', 'autografos',     'Autógrafos',          11),
  ('tipo_sessao', 'em-curadoria',   'Em curadoria',        12),
  ('tipo_sessao', 'intervalo',      'Intervalo',           13),
  ('tipo_sessao', 'almoco',         'Almoço',              14)
on conflict (tipo, codigo) do update
  set rotulo = excluded.rotulo, ordem = excluded.ordem, ativo = true, atualizado_em = now();

-- ---------------------------------------------------------------------------
-- 2. Curadoria de palestrantes para o App
create table if not exists summit_2026.speaker_profiles (
  speaker_id    bigint primary key references ecossistema.palestrantes_especialistas(id) on delete cascade,
  credencial    text,
  resumo        text,
  foto          text,
  destaque      boolean     not null default false,
  temas         jsonb       not null default '[]'::jsonb,
  atualizado_em timestamptz not null default now(),
  constraint speaker_profiles_temas_array check (jsonb_typeof(temas) = 'array')
);
comment on table summit_2026.speaker_profiles is
  'Vitrine do palestrante no App do Summit (foto, destaque, credencial e resumo curtos, temas). Conhecimento continua em ecossistema.palestrantes_especialistas.';
alter table summit_2026.speaker_profiles enable row level security;
revoke all on summit_2026.speaker_profiles from public, anon, authenticated;

do $do$
declare v_sem_par text; v_duplos text;
begin
  create temp table curadoria (nome text, credencial text, resumo text, foto text, destaque boolean, temas jsonb) on commit drop;
  insert into curadoria values
('Amy Edmondson', 'Harvard · Segurança psicológica', 'Harvard. Eleita duas vezes pensadora nº 1 do mundo em gestão. Suas pesquisas guiam Google, hospitais e governos.', 'palestrantes/amy.webp', true, '["seguranca_psicologica","dados_bem_estar","lideranca_humana","performance"]'::jsonb),
('Christina Maslach', 'Berkeley · Burnout', 'UC Berkeley. Criou o instrumento que mede burnout no mundo inteiro — base do reconhecimento pela OMS.', 'palestrantes/christina.webp', true, '["dados_bem_estar","saude_mental"]'::jsonb),
('Jan-Emmanuel De Neve', 'Oxford · Economia do bem-estar', 'Oxford. Provou com 30 milhões de colaboradores que bem-estar é causa mensurável de resultado econômico.', 'palestrantes/deneve.webp', true, '["dados_bem_estar","lideranca_humana"]'::jsonb),
('Sonja Lyubomirsky', 'UC Riverside · Felicidade', 'UC Riverside. 70 mil citações. Transformou a felicidade em um campo sólido de evidências — e de prática.', 'palestrantes/sonja.webp', true, '["dados_bem_estar","performance","felicidade","futuro_trabalho"]'::jsonb),
('Adriana Drulla', 'Curadora e CEO do Mind', 'Psicóloga e Mestre em Psicologia Positiva pela University of Pennsylvania, onde estudou com Martin Seligman. Regional Lead, Latin America – Oxford Research & Development, ao lado de Jan-Emmanuel De Neve.', 'palestrantes/adriana.webp', false, '["dados_bem_estar"]'::jsonb),
('Carla Tieppo', 'Neurociência aplicada · USP', 'Doutora em Ciências pela USP e pioneira em neurociência aplicada. Há mais de 30 anos transforma conhecimento sobre o cérebro em estratégias de comportamento, performance e bem-estar.', 'palestrantes/carla.webp', false, '["dados_bem_estar","saude_mental","performance"]'::jsonb),
('Ana Claudia Quintana Arantes', 'Finitude e significado', 'Médica formada pela USP, pós-graduada em Psicologia e referência internacional em cuidados paliativos. Mostra por que compreender a finitude aproxima de uma vida com mais significado.', 'palestrantes/ana-claudia.webp', false, '["saude_mental","felicidade"]'::jsonb),
('Márcio Atalla', 'Corpo e alta performance', 'Professor de Educação Física e um dos maiores especialistas brasileiros em qualidade de vida e mudança de hábitos. Há mais de 30 anos desenvolve projetos de bem-estar, movimento e longevidade.', 'palestrantes/marcio.webp', false, '["performance","futuro_trabalho"]'::jsonb),
('Arthur Guerra', 'Psiquiatria e performance', 'Médico psiquiatra, fundador da Clínica Arthur Guerra e do GREA-USP. Discute uma das questões mais urgentes da liderança: é possível ter alta performance sem sacrificar a saúde mental?', 'palestrantes/arthur.webp', false, '["lideranca_humana","saude_mental","performance"]'::jsonb),
('Daniel de Barros', 'Psiquiatria · USP', 'Médico do Instituto de Psiquiatria do Hospital das Clínicas e professor colaborador da Faculdade de Medicina da USP. Autor de Sofrimento não é doença.', 'palestrantes/daniel.webp', false, '["saude_mental"]'::jsonb),
('Izabella Camargo', 'Produtividade sustentável', 'Jornalista e criadora da Produtividade Sustentável. Transformou sua experiência com burnout em uma agenda pública sobre limites e saúde mental no trabalho', 'palestrantes/izabella.webp', false, '["dados_bem_estar","saude_mental","performance"]'::jsonb),
('Renata Rivetti', 'Felicidade no trabalho', 'Pesquisadora em ciência da felicidade, TEDx Speaker e LinkedIn Top Voice. Autora de O Poder do Bem-Estar: um guia para redesenhar o futuro do trabalho.', 'palestrantes/renata.webp', false, '["dados_bem_estar","felicidade","futuro_trabalho"]'::jsonb),
('Tamara Myles', 'Trabalho significativo · UPenn', 'Pesquisadora da University of Pennsylvania e professora do Boston College. Autora do best-seller Meaningful Work, apoia empresas como Google, Microsoft e KPMG.', 'palestrantes/tamara.webp', false, '["dados_bem_estar"]'::jsonb),
('Deepika Chopra', 'The Optimism Doctor®', 'Psicóloga clínica e doutora em Psicologia da Saúde, conhecida como The Optimism Doctor®. Mostra por que o otimismo segue sendo uma das competências mais importantes em tempos de incerteza.', 'palestrantes/deepika.webp', false, '["performance"]'::jsonb),
('Paul Goldsmith', 'Neurociência · Imperial College', 'Neurocientista evolucionista, neurologista e professor visitante do Imperial College London. Mostra por que nosso cérebro não evoluiu para lidar com tantos estímulos.', 'palestrantes/paul.webp', false, '["saude_mental"]'::jsonb),
('Michael E. Long', 'Dopamina · Georgetown', 'Escritor e professor de escrita na Universidade de Georgetown. Autor de Como Domar a Dopamina, explica como a dopamina influencia hábitos, consumo e produtividade.', 'palestrantes/michael.webp', false, '["dados_bem_estar","performance"]'::jsonb),
('Oscar de Bos', 'Economia da distração · Focus Academy', 'Cofundador da Focus Academy, na Holanda, e um dos principais pesquisadores da economia da distração. Mostra por que proteger a atenção é uma competência do século XXI.', 'palestrantes/oscar.webp', false, '["dados_bem_estar"]'::jsonb),
('Gustavo Locatelli', 'Consultor e Médico do Trabalho', 'Médico do Trabalho pela USP e mestre em Saúde Pública pela University of Sydney. Foi Head Global de Saúde da Heineken, liderando estratégias em mais de 80 países.', 'palestrantes/gustavo.webp', false, '["lideranca_humana"]'::jsonb),
('Ana Bógus', 'Presidente · Beiersdorf Brasil', 'Presidente da Beiersdorf Brasil, casa de NIVEA e Eucerin. Referência de liderança feminina no país, acredita em liderança facilitadora e engajamento com propósito.', 'palestrantes/ana-bogus.webp', false, '["lideranca_humana","cultura"]'::jsonb),
('Mauro Muller', 'NR-1 · Ministério do Trabalho', 'Auditor Fiscal do Trabalho do MTE. Coordenou os grupos tripartites da revisão da NR-1 (GRO/PGR) e da NR-17, que orientam a gestão de riscos psicossociais.', 'palestrantes/mauro.webp', false, '["regulacao","lideranca_humana"]'::jsonb),
('Cirlene Zimmermann', 'Procuradora · MPT', 'Procuradora do MPT. Lidera o projeto nacional que orienta como o Ministério Público do Trabalho atua em saúde mental no trabalho', 'palestrantes/cirlene.webp', false, '["lideranca_humana","saude_mental"]'::jsonb),
('Igor Menezes', 'People Analytics · Hull', 'Psicometrista e professor de People Analytics na Hull University Business School, com dois pós-doutorados em Cambridge. Conselheiro Científico do Mind na mensuração da NR-1.', 'palestrantes/igor.webp', false, '["dados_bem_estar","regulacao"]'::jsonb),
('Veruska Galvão', 'Segurança psicológica e cultura', 'Psicóloga organizacional e mentora executiva, precursora em segurança psicológica e cultura organizacional no Brasil. Autora do livro Cultura Organizacional e fundadora da AKTO.', 'palestrantes/veruska.webp', false, '["seguranca_psicologica","cultura"]'::jsonb),
('Edna Goldoni', 'Protagonismo e longevidade · IVG', 'Presidente do IVG e empreendedora social. Referência em protagonismo feminino e longevidade no trabalho, com iniciativas que impactaram mais de 50 mil pessoas.', 'palestrantes/edna.webp', false, '["performance"]'::jsonb),
('João Yosef Torres', 'Diversidade e felicidade corporativa', 'CEO e sócio-fundador da Mais Diversidade e da Happiness360. Referência brasileira em diversidade, inclusão e cultura, assessorou Itaú, Gerdau, BASF e Santander.', 'palestrantes/joao.webp', false, '["cultura","diversidade","felicidade"]'::jsonb),
('Alana Anijar', 'Inteligência emocional', 'Psicóloga pela UFSC e especialista em Terapia Cognitivo-Comportamental. Criadora do Psicologia na Prática, um dos podcasts de saúde mental mais ouvidos do Brasil.', 'palestrantes/alana.webp', false, '["saude_mental"]'::jsonb),
('Yuri Trafane', 'Engajamento · Ynner', 'Fundador da Ynner Treinamentos. Apresenta os resultados da maior pesquisa global sobre engajamento no trabalho e o que eles revelam sobre propósito e pertencimento.', 'palestrantes/yuri.webp', false, '["dados_bem_estar","cultura"]'::jsonb),
('Fernanda Catena', 'Longevidade e saúde feminina', 'Médica ortopedista e especialista em longevidade, com formação em Lifestyle Medicine e menopausa por Harvard. À frente do programa de longevidade do Instituto D’Or.', 'palestrantes/fernanda.webp', false, '["performance"]'::jsonb),
('Maryanna com Y', 'Inteligência HUMORcional', 'Palestrante TEDx e precursora da Inteligência HUMORcional, Maryanna com Y já impactou mais de 1 milhão de pessoas com experiências no Brasil e no exterior. Pós-graduada em Neurociências pela PUC-RS, estudou felicidade, inteligência emocional e bem-estar em formações como Chief Happiness Officer, Action for Happiness e Search Inside Yourself, do Google', 'palestrantes/maryanna.webp', false, '["saude_mental","felicidade"]'::jsonb),
('Irene Reis', 'Educação e saúde mental', 'Graduada em Letras pela USP, Irene Reis é professora há mais de vinte anos, conciliando educação escolar e corporativa. Especialista em neurociência e comportamento pela PUC, mestre em Ciências da Educação e doutoranda em Saúde Mental no Desenvolvimento Profissional, reúne formações em comunicação não violenta, inteligência emocional, desenvolvimento humano e burnout docente', 'palestrantes/irene.webp', false, '["dados_bem_estar","saude_mental"]'::jsonb),
('Lailson Lima', 'Segurança do trabalho · ConCuidado', 'Engenheiro de Segurança do Trabalho e Meio Ambiente, Lailson Lima atua há anos na interseção entre segurança, saúde ocupacional e educação. É sócio-fundador e CEO da ConCuidado, vice-presidente da Assessoria Reinventando a Educação, bombeiro civil e possui formação em gestão escolar pela USP, hotelaria hospitalar pelo São Camilo e burnout docente pela PUC', 'palestrantes/lailson.webp', false, '["regulacao","lideranca_humana","saude_mental"]'::jsonb),
('Michelle Schneider', 'IA e futuro do trabalho', 'Sócia da Signal & Cipher, consultoria americana de inteligência artificial, Michelle Schneider é autora do best-seller O Profissional do Futuro e professora convidada na Singularity University e na Hebrew University of Jerusalem. Com 20 anos de carreira executiva em big techs como Google, LinkedIn e TikTok, atua na interseção entre IA, liderança e transformação do trabalho', 'palestrantes/michelle.webp', false, '["lideranca_humana","futuro_trabalho"]'::jsonb),
('Daiana Garbin', 'Saúde mental e autocompaixão', 'Jornalista, escritora e criadora de conteúdo, é uma das vozes mais reconhecidas no debate sobre saúde mental, transtornos alimentares e as pressões da vida contemporânea. Autora de Fazendo as Pazes com o Corpo e A Vida Perfeita Não Existe, transforma experiências pessoais e informação qualificada em conversas que ajudam a romper tabus.', 'palestrantes/daiana.webp', false, '["saude_mental"]'::jsonb),
('Ana Mocny', 'Sócia Capital humano · Deloitte', 'Sócia de Capital Humano da Deloitte, Ana Mocny atua há mais de 25 anos assessorando empresas em gestão de pessoas, diversidade, equidade e inclusão, liderança e transformação organizacional. Lidera no Brasil as práticas de DE&I, Liderança e Transformação Organizacional da Deloitte, apoiando organizações na construção de culturas mais inclusivas e sustentáveis', 'palestrantes/ana-mocny.webp', false, '["lideranca_humana","cultura","performance","diversidade","futuro_trabalho"]'::jsonb),
('Esabela Cruz', 'Cultura e gestão de pessoas', 'Psicóloga com MBA em Gestão Empresarial pela FGV e especializações em Recursos Humanos e Administração pela FIA/USP, Esabela Cruz é sócia da NR-1 Brasil e professora de MBA na FIA. Com mais de 20 anos de experiência em cultura organizacional, clima, liderança e desenvolvimento humano, atua na interseção entre psicologia, gestão e transformação de ambientes de trabalho', 'palestrantes/esabela.webp', false, '["regulacao","lideranca_humana","cultura","saude_mental","performance","futuro_trabalho"]'::jsonb),
('Ivana Moreira', 'Cofundadora do Mind Summit', 'Jornalista, empreendedora e cofundadora do Mind Summit. Atua há mais de uma década na criação e curadoria de projetos de conteúdo e grandes eventos, conectando especialistas, empresas e ideias capazes de transformar pessoas e organizações.', 'palestrantes/ivana.webp', false, '["futuro_trabalho"]'::jsonb),
('Maurício Giamellaro', 'CEO · HEINEKEN Brasil', 'CEO do Grupo HEINEKEN no Brasil, hoje o maior mercado da marca Heineken no mundo. Lidera uma das principais operações da companhia global, combinando crescimento, transformação cultural e uma agenda de impacto e sustentabilidade.', 'palestrantes/mauricio.webp', false, '["lideranca_humana","cultura","performance","futuro_trabalho"]'::jsonb),
('Paula Benevides', 'VP de Pessoas, Cultura e Organização da Natura', '', 'palestrantes/paula.webp', false, '["cultura"]'::jsonb),
('Caito Maia', 'Fundador e CEO · Chilli Beans', 'Fundador e CEO da Chilli Beans, uma das maiores redes de acessórios de moda do país, com mais de 1.400 pontos de venda. Empreendedor reconhecido por transformar cultura, marca e experiência em motores de crescimento.', 'palestrantes/caito.webp', false, '["cultura","futuro_trabalho"]'::jsonb);

  -- Casamento por nome normalizado, pelo alias registrado ("Apresentado ... como X") ou por
  -- grafia conhecida. "Maryanna com Y" no JSON é "Maryana com Y" no banco.
  create temp table casamento on commit drop as
  with n as (
    select c.*, lower(translate(case when c.nome = 'Maryanna com Y' then 'Maryana com Y' else c.nome end,
      'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')) as chave
    from curadoria c),
  p as (
    select id, nome, lower(translate(nome,
      'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')) as chave,
      lower(coalesce(aliases, '')) as aliases
    from ecossistema.palestrantes_especialistas)
  select n.nome as nome_json, p.id as speaker_id, p.nome as nome_banco,
         n.credencial, n.resumo, n.foto, n.destaque, n.temas
  from n
  left join p on p.chave = n.chave or p.aliases like '%como ' || n.chave || '%';

  select string_agg(nome_json, ', ') into v_sem_par from casamento where speaker_id is null;
  if v_sem_par is not null then
    raise exception 'speaker_profiles: curados sem par no banco: %', v_sem_par;
  end if;
  select string_agg(nome_json, ', ') into v_duplos
  from (select nome_json from casamento group by nome_json having count(*) > 1) d;
  if v_duplos is not null then
    raise exception 'speaker_profiles: curados com mais de um par no banco: %', v_duplos;
  end if;

  insert into summit_2026.speaker_profiles (speaker_id, credencial, resumo, foto, destaque, temas)
  select speaker_id, nullif(credencial, ''), nullif(resumo, ''), nullif(foto, ''), destaque, temas
  from casamento
  on conflict (speaker_id) do nothing;
end
$do$;

-- ---------------------------------------------------------------------------
-- 3. Temas das 77 sessões, por site_session_id. "(i)" = inferido do título/descrição.
do $do$
declare v_vazias int; v_fora text; v_sem_sessao text;
begin
  create temp table temas_sessao (site_session_id text, temas jsonb) on commit drop;
  insert into temas_sessao values
  -- dia 1
  ('d1-0730-credenciamento',            '[]'),
  ('d1-0900-abertura',                  '[]'),
  ('d1-0915-beneficio-transformacao',   '["futuro_trabalho"]'),
  ('d1-0940-bem-estar',                 '["dados_bem_estar","cultura"]'),
  ('d1-1030-quando-bem',                '["dados_bem_estar"]'),
  ('d1-1110-intervalo',                 '[]'),
  ('d1-1130-conversas-dificeis',        '["lideranca_humana","seguranca_psicologica"]'),        -- (i)
  ('d1-1130-mensuracao-pgr',            '["dados_bem_estar","regulacao","performance"]'),
  ('d1-1130-mensurar-intervir',         '["dados_bem_estar","performance"]'),
  ('d1-1130-emocoes-positivas',         '["felicidade","performance"]'),                        -- (i)
  ('d1-1130-sustenta-equipes',          '["lideranca_humana","performance"]'),
  ('d1-1130-trabalho-ainda',            '["dados_bem_estar","cultura"]'),
  ('d1-1130-produtividade-sustentavel', '["dados_bem_estar","performance"]'),
  ('d1-1230-nova-era',                  '["performance"]'),
  ('d1-1230-virada-diversidade',        '["cultura","performance","diversidade"]'),
  ('d1-1230-curadoria',                 '[]'),
  ('d1-1330-almoco-experiencias',       '[]'),
  ('d1-1340-invisivel-equipes',         '["cultura","lideranca_humana"]'),                      -- (i)
  ('d1-1400-autografos-jan',            '["dados_bem_estar"]'),
  ('d1-1400-trabalho-proteger',         '["saude_mental"]'),                                    -- (i)
  ('d1-1420-usa-menos',                 '["performance","cultura"]'),                           -- (i)
  ('d1-1430-virada-diversidade',        '["diversidade"]'),
  ('d1-1430-modo-ativar',               '["saude_mental","performance"]'),                      -- (i)
  ('d1-1440-esperanca-caminhos',        '["felicidade","futuro_trabalho"]'),                    -- (i)
  ('d1-1500-economia-distracao',        '["performance"]'),
  ('d1-1500-autonomia-desorganizacao',  '["cultura"]'),
  ('d1-1500-falhar-melhor',             '["seguranca_psicologica","futuro_trabalho"]'),
  ('d1-1500-lideranca-engajadora',      '["lideranca_humana","cultura"]'),                      -- (i)
  ('d1-1500-seu-emprego',               '["futuro_trabalho","performance"]'),                   -- (i)
  ('d1-1500-tres-movimentos',           '["seguranca_psicologica","lideranca_humana"]'),
  ('d1-1500-resiliencia-tempo',         '["performance","saude_mental"]'),                      -- (i)
  ('d1-1530-trabalho-anos',             '["lideranca_humana","futuro_trabalho"]'),              -- (i)
  ('d1-1600-consciencia-finitude',      '["saude_mental"]'),
  ('d1-1600-curadoria',                 '[]'),
  ('d1-1600-relacoes-sustentam',        '["saude_mental","felicidade"]'),                       -- (i)
  ('d1-1700-intervalo',                 '[]'),
  ('d1-1720-lideranca-consciente',      '["lideranca_humana","performance"]'),
  ('d1-1810-mito-colaborador',          '["saude_mental"]'),
  ('d1-1900-coquetel-autografos',       '["saude_mental"]'),
  -- dia 2
  ('d2-0730-credenciamento',            '[]'),
  ('d2-0900-quem-enxerga',              '["lideranca_humana"]'),
  ('d2-0930-programas-bem',             '["seguranca_psicologica","dados_bem_estar","felicidade"]'),
  ('d2-1020-obrigacao-gestao',          '["regulacao","lideranca_humana"]'),
  ('d2-1110-intervalo',                 '[]'),
  ('d2-1130-bem-estar',                 '["dados_bem_estar","felicidade"]'),
  ('d2-1130-comeca-agenda',             '["performance","futuro_trabalho"]'),
  ('d2-1130-curadoria',                 '[]'),
  ('d2-1130-feedback-falta',            '["seguranca_psicologica"]'),
  ('d2-1130-onde-foi',                  '["saude_mental","performance"]'),
  ('d2-1130-riscos-psicossociais',      '["regulacao"]'),
  ('d2-1130-voce-aguenta',              '["lideranca_humana","saude_mental","performance"]'),
  ('d2-1230-curadoria',                 '[]'),
  ('d2-1230-lideranca-emocionalmente',  '["lideranca_humana","saude_mental","performance"]'),
  ('d2-1230-mulheres-abrem',            '["diversidade","futuro_trabalho"]'),
  ('d2-1330-almoco-experiencias',       '[]'),
  ('d2-1330-autografos-carla',          '["saude_mental","performance"]'),                      -- (i)
  ('d2-1340-antes-cobrar',              '["seguranca_psicologica","lideranca_humana"]'),        -- (i)
  ('d2-1400-autografos-sonja',          '["felicidade"]'),
  ('d2-1400-custo-caber',               '["diversidade","saude_mental"]'),                      -- (i)
  ('d2-1400-poder-sororidade',          '["cultura","diversidade"]'),
  ('d2-1420-lider-super-heroi',         '["lideranca_humana"]'),                                -- (i)
  ('d2-1440-segunda-feira',             '["lideranca_humana","cultura"]'),                      -- (i)
  ('d2-1500-cultura-emocional',         '["cultura","saude_mental","felicidade"]'),             -- (i)
  ('d2-1500-infraestrutura-performance','["performance"]'),
  ('d2-1500-lider-arquiteto',           '["lideranca_humana","performance"]'),
  ('d2-1500-desalinhamentos-burnout',   '["lideranca_humana","saude_mental"]'),
  ('d2-1500-seu-cerebro',               '["saude_mental"]'),
  ('d2-1500-sobreviver-destruir',       '["lideranca_humana","performance"]'),
  ('d2-1500-trabalho-hibrido',          '["lideranca_humana","futuro_trabalho"]'),
  ('d2-1600-conversas-corajosas',       '["seguranca_psicologica","lideranca_humana","performance"]'), -- (i)
  ('d2-1600-curadoria',                 '[]'),
  ('d2-1600-quem-esta',                 '["saude_mental","performance"]'),                      -- (i)
  ('d2-1640-florescendo-tempos',        '["felicidade","performance"]'),                        -- (i)
  ('d2-1700-intervalo',                 '[]'),
  ('d2-1720-estrategia-pratica',        '["lideranca_humana","cultura"]'),                      -- (i)
  ('d2-1800-melhores-equipes',          '["seguranca_psicologica","lideranca_humana"]'),
  ('d2-1900-coquetel-autografos',       '["seguranca_psicologica"]');

  -- Todo código precisa existir na taxonomia; toda linha precisa achar a sessão.
  select string_agg(distinct t, ', ') into v_fora
  from temas_sessao ts, jsonb_array_elements_text(ts.temas) t
  where not exists (select 1 from ecossistema.taxonomy x where x.tipo = 'tema' and x.codigo = t and x.ativo);
  if v_fora is not null then raise exception 'temas fora da taxonomia: %', v_fora; end if;

  select string_agg(ts.site_session_id, ', ') into v_sem_sessao
  from temas_sessao ts
  where not exists (select 1 from summit_2026.sessions s join summit_2026.events e on e.id = s.event_id
                     where e.slug = 'mind-summit-2026' and s.site_session_id = ts.site_session_id);
  if v_sem_sessao is not null then raise exception 'site_session_id sem sessão no banco: %', v_sem_sessao; end if;

  update summit_2026.sessions s
     set topicos_aprendizado = ts.temas
    from temas_sessao ts, summit_2026.events e
   where e.slug = 'mind-summit-2026' and s.event_id = e.id
     and s.site_session_id = ts.site_session_id
     and coalesce(s.topicos_aprendizado, '[]'::jsonb) = '[]'::jsonb;

  -- Depois da carga, só as sessões operacionais podem seguir sem tema.
  select count(*) into v_vazias
  from summit_2026.sessions s join summit_2026.events e on e.id = s.event_id
  where e.slug = 'mind-summit-2026'
    and coalesce(s.topicos_aprendizado, '[]'::jsonb) = '[]'::jsonb
    and s.tipo not in ('credenciamento', 'abertura', 'intervalo', 'almoco', 'em-curadoria');
  if v_vazias > 0 then raise exception 'sessões de conteúdo ainda sem tema: %', v_vazias; end if;
end
$do$;
