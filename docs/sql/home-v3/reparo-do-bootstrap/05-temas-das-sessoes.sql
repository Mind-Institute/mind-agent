-- ============================================================
-- 05 · Devolve os temas às sessões
-- ============================================================
-- Projeto: mind-agent (ymnmotgglsrxmjmonwjz)
-- Depende de: nada. Independente dos outros arquivos desta pasta.
-- Gerado a partir de dados/summit.json em 2026-09-01.
--
-- POR QUE ISTO EXISTE
-- `summit_2026.sessions.topicos_aprendizado` está `[]` nas 77 sessões, e
-- `trilhas` está vazio. Sem tema não há afinidade; sem afinidade o
-- Concierge não recomenda nada — o roteiro sai vazio, "escolher
-- palestras" não devolve nada, a jornada termina em branco.
--
-- Consertar o bootstrap SEM isto deixaria o app PIOR do que está hoje:
-- ele ganharia a grade real e perderia a recomendação inteira.
--
-- DE ONDE VÊM
-- De `dados/summit.json`, o arquivo que o app serve hoje — o único lugar
-- onde a classificação ainda existe. São 49 sessões classificadas,
-- com os dez códigos que a grade sempre usou.
--
-- COMO FORAM CASADAS
-- Fora do banco, por dia + horário (tolerância de 15 minutos) e título
-- normalizado (sem acento, sem caixa, sem pontuação). Nenhuma ficou
-- ambígua e nenhuma sessão viva recebeu dois pares. O casamento já
-- resolvido é o que permite cada `update` abaixo nomear o título vivo
-- EXATO: nada aqui é aproximado na hora de rodar.
--
-- ALCANCE — leia antes de achar que resolveu
--   39 sessões recebem tema.
--   59 sessões de conteúdo existem na grade viva.
--   35 delas ficam com tema; 24 continuam sem.
--
-- Isto RECUPERA o que existia. Não é classificação nova — e classificar
-- sessão é trabalho de conteúdo, não de migração.

begin;

-- 2026-09-16 09:15 · Do benefício à transformação
-- arquivo: Do benefício à transformação: o futuro do bem-estar nas empresas
update summit_2026.sessions s
   set topicos_aprendizado = '["futuro_trabalho"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '09:15'
   and s.titulo = 'Do benefício à transformação';

-- 2026-09-16 09:40 · Como bem-estar afeta o bottom-line?
update summit_2026.sessions s
   set topicos_aprendizado = '["dados_bem_estar","cultura"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '09:40'
   and s.titulo = 'Como bem-estar afeta o bottom-line?';

-- 2026-09-16 10:30 · Quando o bem-estar entra na tese
update summit_2026.sessions s
   set topicos_aprendizado = '["dados_bem_estar"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '10:30'
   and s.titulo = 'Quando o bem-estar entra na tese';

-- 2026-09-16 11:30 · Mensurar, intervir, provar: a metodologia Oxford para wellbeing como ativo de performance
update summit_2026.sessions s
   set topicos_aprendizado = '["dados_bem_estar","performance"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '11:30'
   and s.titulo = 'Mensurar, intervir, provar: a metodologia Oxford para wellbeing como ativo de performance';

-- 2026-09-16 11:30 · Da mensuração ao PGR
-- arquivo: Da mensuração ao PGR. Como avaliar riscos psicossociais e definir prioridades de ação
update summit_2026.sessions s
   set topicos_aprendizado = '["dados_bem_estar","regulacao","performance"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '11:30'
   and s.titulo = 'Da mensuração ao PGR';

-- 2026-09-16 11:30 · O que sustenta equipes de alta performance
-- arquivo: O que sustenta equipes de alta performance. Ferramentas de inteligência relacional para líderes
update summit_2026.sessions s
   set topicos_aprendizado = '["lideranca_humana","performance"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '11:30'
   and s.titulo = 'O que sustenta equipes de alta performance';

-- 2026-09-16 11:30 · O trabalho ainda engaja?
update summit_2026.sessions s
   set topicos_aprendizado = '["dados_bem_estar","cultura"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '11:30'
   and s.titulo = 'O trabalho ainda engaja?';

-- 2026-09-16 11:30 · Produtividade sustentável
-- arquivo: Produtividade sustentável. Como manter performance sem esgotar pessoas
update summit_2026.sessions s
   set topicos_aprendizado = '["dados_bem_estar","performance"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '11:30'
   and s.titulo = 'Produtividade sustentável';

-- 2026-09-16 12:30 · A virada da diversidade
-- arquivo: A virada da diversidade . Estratégias de inclusão para alavancar performance, engajamento e vantagem competitiva
update summit_2026.sessions s
   set topicos_aprendizado = '["cultura","performance","diversidade"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '12:30'
   and s.titulo = 'A virada da diversidade';

-- 2026-09-16 12:30 · A nova era da alta performance
update summit_2026.sessions s
   set topicos_aprendizado = '["performance"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '12:30'
   and s.titulo = 'A nova era da alta performance';

-- 2026-09-16 13:30 · A Virada da Diversidade
-- arquivo: A Virada da Diversidade . João Yosef Torres
update summit_2026.sessions s
   set topicos_aprendizado = '["diversidade"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '13:30'
   and s.titulo = 'A Virada da Diversidade';

-- 2026-09-16 14:00 · Autógrafos com Jan-Emmanuel De Neve
update summit_2026.sessions s
   set topicos_aprendizado = '["dados_bem_estar"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '14:00'
   and s.titulo = 'Autógrafos com Jan-Emmanuel De Neve';

-- 2026-09-16 15:00 · Os três movimentos do líder que destravam aprendizagem coletiva
update summit_2026.sessions s
   set topicos_aprendizado = '["seguranca_psicologica","lideranca_humana"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '15:00'
   and s.titulo = 'Os três movimentos do líder que destravam aprendizagem coletiva';

-- 2026-09-16 15:00 · Bem-estar começa na agenda
-- arquivo: Bem-estar começa na agenda. Como transformar intenção em prioridade organizacional
update summit_2026.sessions s
   set topicos_aprendizado = '["performance","futuro_trabalho"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '15:00'
   and s.titulo = 'Bem-estar começa na agenda';

-- 2026-09-16 15:00 · A economia da distração
update summit_2026.sessions s
   set topicos_aprendizado = '["performance"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '15:00'
   and s.titulo = 'A economia da distração';

-- 2026-09-16 15:00 · Autonomia sem desorganização
-- arquivo: Autonomia sem desorganização. Como criar formas de trabalho mais flexíveis e eficientes
update summit_2026.sessions s
   set topicos_aprendizado = '["cultura"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '15:00'
   and s.titulo = 'Autonomia sem desorganização';

-- 2026-09-16 16:00 · Como a consciência da finitude transforma a forma de viver e as escolhas que fazemos
update summit_2026.sessions s
   set topicos_aprendizado = '["saude_mental"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '16:00'
   and s.titulo = 'Como a consciência da finitude transforma a forma de viver e as escolhas que fazemos';

-- 2026-09-16 18:10 · O mito do colaborador resiliente
-- arquivo: O mito do colaborador resiliente: por que burnout é um problema de desenho de trabalho, não de fraqueza individual
update summit_2026.sessions s
   set topicos_aprendizado = '["saude_mental"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '18:10'
   and s.titulo = 'O mito do colaborador resiliente';

-- 2026-09-16 19:00 · Coquetel e Autógrafos com Christina Maslach
update summit_2026.sessions s
   set topicos_aprendizado = '["saude_mental"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-16'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '19:00'
   and s.titulo = 'Coquetel e Autógrafos com Christina Maslach';

-- 2026-09-17 09:00 · Quem enxerga antes, lidera antes
update summit_2026.sessions s
   set topicos_aprendizado = '["lideranca_humana"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '09:00'
   and s.titulo = 'Quem enxerga antes, lidera antes';

-- 2026-09-17 09:30 · Por que os programas de bem-estar falham e o que a ciência diz sobre os que duram
update summit_2026.sessions s
   set topicos_aprendizado = '["seguranca_psicologica","dados_bem_estar","felicidade"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '09:30'
   and s.titulo = 'Por que os programas de bem-estar falham e o que a ciência diz sobre os que duram';

-- 2026-09-17 10:20 · Da obrigação à gestão real: como construir governança de risco psicossocial
update summit_2026.sessions s
   set topicos_aprendizado = '["regulacao","lideranca_humana"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '10:20'
   and s.titulo = 'Da obrigação à gestão real: como construir governança de risco psicossocial';

-- 2026-09-17 11:30 · Bem-estar baseado em evidência
-- arquivo: Bem-estar baseado em evidência: aprenda a desenhar intervenções que de fato funcionam.
update summit_2026.sessions s
   set topicos_aprendizado = '["dados_bem_estar","felicidade"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '11:30'
   and s.titulo = 'Bem-estar baseado em evidência';

-- 2026-09-17 11:30 · Falhar melhor
-- arquivo: Falhar melhor. Como transformar erros em aprendizagem sem reduzir a exigência
update summit_2026.sessions s
   set topicos_aprendizado = '["seguranca_psicologica","futuro_trabalho"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '11:30'
   and s.titulo = 'Falhar melhor';

-- 2026-09-17 11:30 · Riscos psicossociais sem improviso
-- arquivo: Riscos psicossociais sem improviso. Como prevenir, estruturar responsabilidades e atender às exigências legais
update summit_2026.sessions s
   set topicos_aprendizado = '["regulacao"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '11:30'
   and s.titulo = 'Riscos psicossociais sem improviso';

-- 2026-09-17 11:30 · O feedback que falta
-- arquivo: O feedback que falta. Como tornar visíveis as forças que sustentam o resultado
update summit_2026.sessions s
   set topicos_aprendizado = '["seguranca_psicologica"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '11:30'
   and s.titulo = 'O feedback que falta';

-- 2026-09-17 11:30 · Onde foi parar o seu foco
-- arquivo: Onde foi parar o seu foco: o que a neurociência mostra sobre o trabalho moderno
update summit_2026.sessions s
   set topicos_aprendizado = '["saude_mental","performance"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '11:30'
   and s.titulo = 'Onde foi parar o seu foco';

-- 2026-09-17 11:30 · Você aguenta ser líder?
update summit_2026.sessions s
   set topicos_aprendizado = '["lideranca_humana","saude_mental","performance"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '11:30'
   and s.titulo = 'Você aguenta ser líder?';

-- 2026-09-17 12:30 · Mulheres que abrem caminho
-- arquivo: Mulheres que abrem caminho. Como transformar competição em apoio real
update summit_2026.sessions s
   set topicos_aprendizado = '["diversidade","futuro_trabalho"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '12:30'
   and s.titulo = 'Mulheres que abrem caminho';

-- 2026-09-17 12:30 · Liderança emocionalmente madura
update summit_2026.sessions s
   set topicos_aprendizado = '["lideranca_humana","saude_mental","performance"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '12:30'
   and s.titulo = 'Liderança emocionalmente madura';

-- 2026-09-17 14:00 · O poder da sororidade
-- arquivo: O poder da sororidade. Um pacto de respeito e apoio que une e transforma a vida das mulheres
update summit_2026.sessions s
   set topicos_aprendizado = '["cultura","diversidade"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '14:00'
   and s.titulo = 'O poder da sororidade';

-- 2026-09-17 14:00 · Autógrafos com Sonja Lyubomirsky
update summit_2026.sessions s
   set topicos_aprendizado = '["felicidade"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '14:00'
   and s.titulo = 'Autógrafos com Sonja Lyubomirsky';

-- 2026-09-17 15:00 · Infraestrutura de Performance
-- arquivo: Infraestrutura de Performance: Desenho pessoal para Executivos sob Pressão Cronica
update summit_2026.sessions s
   set topicos_aprendizado = '["performance"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '15:00'
   and s.titulo = 'Infraestrutura de Performance';

-- 2026-09-17 15:00 · Trabalho Híbrido sem Caos
-- arquivo: Trabalho híbrido sem caos. Ferramentas para organizar, colaborar e liderar equipes
update summit_2026.sessions s
   set topicos_aprendizado = '["lideranca_humana","futuro_trabalho"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '15:00'
   and s.titulo = 'Trabalho Híbrido sem Caos';

-- 2026-09-17 15:00 · O líder como arquiteto do trabalho
-- arquivo: O líder como arquiteto do trabalho. Rotinas para dar clareza, remover obstáculos e sustentar a performance
update summit_2026.sessions s
   set topicos_aprendizado = '["lideranca_humana","performance"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '15:00'
   and s.titulo = 'O líder como arquiteto do trabalho';

-- 2026-09-17 15:00 · Sobreviver sem destruir o time
-- arquivo: Sobreviver sem destruir o time. Como liderar quando o negócio está sob pressão
update summit_2026.sessions s
   set topicos_aprendizado = '["lideranca_humana","performance"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '15:00'
   and s.titulo = 'Sobreviver sem destruir o time';

-- 2026-09-17 15:00 · Seu cérebro não foi feito para isso
update summit_2026.sessions s
   set topicos_aprendizado = '["saude_mental"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '15:00'
   and s.titulo = 'Seu cérebro não foi feito para isso';

-- 2026-09-17 18:00 · As melhores equipes erram diferente
update summit_2026.sessions s
   set topicos_aprendizado = '["seguranca_psicologica","lideranca_humana"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '18:00'
   and s.titulo = 'As melhores equipes erram diferente';

-- 2026-09-17 19:00 · Coquetel e Autógrafos com Amy Edmondson
update summit_2026.sessions s
   set topicos_aprendizado = '["seguranca_psicologica"]'::jsonb
  from summit_2026.events e
 where e.id = s.event_id and e.slug = 'mind-summit-2026'
   and s.dia = '2026-09-17'::date
   and to_char(s.inicio at time zone e.fuso, 'HH24:MI') = '19:00'
   and s.titulo = 'Coquetel e Autógrafos com Amy Edmondson';

-- ------------------------------------------------------------
-- Conferência
-- ------------------------------------------------------------
-- Esperado depois do commit: com_tema = 39
select count(*) filter (where jsonb_array_length(coalesce(s.topicos_aprendizado,'[]'::jsonb)) > 0) as com_tema,
       count(*) as total
from summit_2026.sessions s
join summit_2026.events e on e.id = s.event_id and e.slug = 'mind-summit-2026';

commit;

-- ============================================================
-- O QUE FICOU DE FORA
-- ============================================================
--
-- 10 sessões classificadas no arquivo não existem na grade viva
-- (título e horário sem correspondente). Não são perda: são sessões que
-- só existiam no arquivo local.
--   2026-09-16 11:30  Decidir sob pressão . Como manter clareza em contextos de alta exigência
--   2026-09-16 11:30  Entre o riso e o resultado .  Como o humor afeta a performance
--   2026-09-16 15:00  Redesenhar o trabalho para performar melhor. Ferramentas de job crafting para líderes
--   2026-09-16 15:00  O que precisa ser dito. Ferramentas para conversas difíceis na liderança
--   2026-09-16 15:00  Quando mudar deixa de ser uma escolha. Como preservar agência, confiança e capacidade de adaptação
--   2026-09-16 16:00  A conversa que a liderança evita. O custo cultural e humano de não enfrentar problemas
--   2026-09-16 17:20  Alta performance começa por dentro. Autorregulação, pausa e autocompaixão na liderança
--   2026-09-17 15:00  Masterclass: Os 6 desalinhamentos do burnout: como ler e redesenhar o trabalho do seu time
--   2026-09-17 16:00  Bem-estar é gestão. Como as decisões de liderança constroem o clima das equipes
--   2026-09-17 17:20  Felicidade como parte da estratégia. Casos e aprendizados
--
-- 24 sessões de conteúdo da grade viva continuam sem tema.
-- Estas SÃO perda de alcance: o Concierge não vai recomendá-las, porque
-- não tem como saber do que falam.
--   2026-09-16 09:00  Abertura
--   2026-09-16 11:30  Conversas difíceis, times que crescem
--   2026-09-16 11:30  O que emoções positivas têm a ver com performance?
--   2026-09-16 13:40  O invisível que move as equipes
--   2026-09-16 14:00  O trabalho também pode proteger
--   2026-09-16 14:20  Quando o trabalho usa menos do que as pessoas têm para oferecer
--   2026-09-16 14:30  Modo Ativar
--   2026-09-16 14:40  Esperança não é esperar: caminhos para construir o futuro que desejamos
--   2026-09-16 15:00  Liderança engajadora
--   2026-09-16 15:00  O seu emprego vai existir daqui a 5 anos?
--   2026-09-16 15:00  Resiliência em tempo real
--   2026-09-16 15:30  Trabalho S/A
--   2026-09-16 16:00  Relações que sustentam
--   2026-09-16 17:20  Liderança Consciente
--   2026-09-17 13:40  Antes de cobrar segurança psicológica, desenvolva quem lidera
--   2026-09-17 14:00  O custo de caber: por que as pessoas adoecem quando todos precisam pensar igual
--   2026-09-17 14:20  O fim do líder super-herói
--   2026-09-17 14:40  O que uma segunda-feira comum revela sobre a sua liderança?
--   2026-09-17 15:00  Cultura emocional: entre o engajamento e o burnout
--   2026-09-17 15:00  Os 6 desalinhamentos do burnout
--   2026-09-17 16:00  Conversas Corajosas, Times Fortes
--   2026-09-17 16:00  Quem está no controle?
--   2026-09-17 16:40  Florescendo em tempos de incerteza
--   2026-09-17 17:20  Mind Talks
