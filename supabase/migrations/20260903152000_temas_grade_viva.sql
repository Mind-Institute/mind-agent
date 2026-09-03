-- Recupera, na grade viva, os temas já curados no snapshot do app. A chave
-- usa evento + dia + hora local + título exato; não há casamento aproximado.

begin;

with mapa(dia,hora,titulo,temas) as (values
  ('2026-09-16'::date,'09:15'::time,'Do benefício à transformação','["futuro_trabalho"]'::jsonb),
  ('2026-09-16'::date,'09:40'::time,'Como bem-estar afeta o bottom-line?','["dados_bem_estar","cultura"]'::jsonb),
  ('2026-09-16'::date,'10:30'::time,'Quando o bem-estar entra na tese','["dados_bem_estar"]'::jsonb),
  ('2026-09-16'::date,'11:30'::time,'Mensurar, intervir, provar: a metodologia Oxford para wellbeing como ativo de performance','["dados_bem_estar","performance"]'::jsonb),
  ('2026-09-16'::date,'11:30'::time,'Da mensuração ao PGR','["dados_bem_estar","regulacao","performance"]'::jsonb),
  ('2026-09-16'::date,'11:30'::time,'O que sustenta equipes de alta performance','["lideranca_humana","performance"]'::jsonb),
  ('2026-09-16'::date,'11:30'::time,'O trabalho ainda engaja?','["dados_bem_estar","cultura"]'::jsonb),
  ('2026-09-16'::date,'11:30'::time,'Produtividade sustentável','["dados_bem_estar","performance"]'::jsonb),
  ('2026-09-16'::date,'12:30'::time,'A virada da diversidade','["cultura","performance","diversidade"]'::jsonb),
  ('2026-09-16'::date,'12:30'::time,'A nova era da alta performance','["performance"]'::jsonb),
  ('2026-09-16'::date,'13:30'::time,'A Virada da Diversidade','["diversidade"]'::jsonb),
  ('2026-09-16'::date,'14:00'::time,'Autógrafos com Jan-Emmanuel De Neve','["dados_bem_estar"]'::jsonb),
  ('2026-09-16'::date,'15:00'::time,'Os três movimentos do líder que destravam aprendizagem coletiva','["seguranca_psicologica","lideranca_humana"]'::jsonb),
  ('2026-09-16'::date,'15:00'::time,'Bem-estar começa na agenda','["performance","futuro_trabalho"]'::jsonb),
  ('2026-09-16'::date,'15:00'::time,'A economia da distração','["performance"]'::jsonb),
  ('2026-09-16'::date,'15:00'::time,'Autonomia sem desorganização','["cultura"]'::jsonb),
  ('2026-09-16'::date,'16:00'::time,'Como a consciência da finitude transforma a forma de viver e as escolhas que fazemos','["saude_mental"]'::jsonb),
  ('2026-09-16'::date,'18:10'::time,'O mito do colaborador resiliente','["saude_mental"]'::jsonb),
  ('2026-09-16'::date,'19:00'::time,'Coquetel e Autógrafos com Christina Maslach','["saude_mental"]'::jsonb),
  ('2026-09-17'::date,'09:00'::time,'Quem enxerga antes, lidera antes','["lideranca_humana"]'::jsonb),
  ('2026-09-17'::date,'09:30'::time,'Por que os programas de bem-estar falham e o que a ciência diz sobre os que duram','["seguranca_psicologica","dados_bem_estar","felicidade"]'::jsonb),
  ('2026-09-17'::date,'10:20'::time,'Da obrigação à gestão real: como construir governança de risco psicossocial','["regulacao","lideranca_humana"]'::jsonb),
  ('2026-09-17'::date,'11:30'::time,'Bem-estar baseado em evidência','["dados_bem_estar","felicidade"]'::jsonb),
  ('2026-09-17'::date,'11:30'::time,'Falhar melhor','["seguranca_psicologica","futuro_trabalho"]'::jsonb),
  ('2026-09-17'::date,'11:30'::time,'Riscos psicossociais sem improviso','["regulacao"]'::jsonb),
  ('2026-09-17'::date,'11:30'::time,'O feedback que falta','["seguranca_psicologica"]'::jsonb),
  ('2026-09-17'::date,'11:30'::time,'Onde foi parar o seu foco','["saude_mental","performance"]'::jsonb),
  ('2026-09-17'::date,'11:30'::time,'Você aguenta ser líder?','["lideranca_humana","saude_mental","performance"]'::jsonb),
  ('2026-09-17'::date,'12:30'::time,'Mulheres que abrem caminho','["diversidade","futuro_trabalho"]'::jsonb),
  ('2026-09-17'::date,'12:30'::time,'Liderança emocionalmente madura','["lideranca_humana","saude_mental","performance"]'::jsonb),
  ('2026-09-17'::date,'14:00'::time,'O poder da sororidade','["cultura","diversidade"]'::jsonb),
  ('2026-09-17'::date,'14:00'::time,'Autógrafos com Sonja Lyubomirsky','["felicidade"]'::jsonb),
  ('2026-09-17'::date,'15:00'::time,'Infraestrutura de Performance','["performance"]'::jsonb),
  ('2026-09-17'::date,'15:00'::time,'Trabalho Híbrido sem Caos','["lideranca_humana","futuro_trabalho"]'::jsonb),
  ('2026-09-17'::date,'15:00'::time,'O líder como arquiteto do trabalho','["lideranca_humana","performance"]'::jsonb),
  ('2026-09-17'::date,'15:00'::time,'Sobreviver sem destruir o time','["lideranca_humana","performance"]'::jsonb),
  ('2026-09-17'::date,'15:00'::time,'Seu cérebro não foi feito para isso','["saude_mental"]'::jsonb),
  ('2026-09-17'::date,'18:00'::time,'As melhores equipes erram diferente','["seguranca_psicologica","lideranca_humana"]'::jsonb),
  ('2026-09-17'::date,'19:00'::time,'Coquetel e Autógrafos com Amy Edmondson','["seguranca_psicologica"]'::jsonb)
)
update summit_2026.sessions s
set topicos_aprendizado=m.temas, atualizado_em=now()
from summit_2026.events e, mapa m
where e.id=s.event_id and e.slug='mind-summit-2026'
  and s.dia=m.dia and s.titulo=m.titulo
  and (s.inicio at time zone e.fuso)::time=m.hora;

commit;
