-- Alinha summit_2026.sessions com a planilha de programação exportada do app (schedules/bookmarks).
-- Decisão da Adriana: a planilha do app prevalece sobre o backend em título, horário e espaço.
-- Origem: export "schedules - bookmarks.xlsx" (85 linhas) confrontado com as 77 sessões vivas.

begin;

-- ---------------------------------------------------------------------------
-- 1. Casa para os IDs do app.
--    sessions.yazo_id é text UNIQUE (um id só) e alimenta o contrato do app via
--    coalesce(yazo_id, id::text); mexer nele trocaria os ids já expostos.
--    As 4 masterclasses existem duas vezes no app de propósito (turma Vale x
--    demais participantes), então o mapeamento é 1 sessão : N ids do app.
alter table summit_2026.sessions
  add column if not exists yazo_ids text[] not null default '{}';

comment on column summit_2026.sessions.yazo_ids is
  'IDs desta mesma sessão no app Yazo (export schedules/bookmarks). Mais de um id quando a sessão foi duplicada no app por turma de inscrição - caso das 4 masterclasses (Vale x demais). yazo_id segue sendo o id canônico único.';

-- ---------------------------------------------------------------------------
-- 2. Títulos: a planilha do app vence.
update summit_2026.sessions s set titulo = v.titulo, atualizado_em = now()
from (values
  ('d1-0915-beneficio-transformacao','Do benefício à estratégia de negocio: O futuro do bem-estar nas empresas'),
  ('d1-0940-bem-estar','IA, Bem-estar e Performance: Por que empresas que escolhem ampliação das capacidades humanas, em vez de automação, podem vencer no longo prazo'),
  ('d1-1030-quando-bem','Quando o bem-estar entra na tese: Como investidores, mercado e empresas estão transformando bem-estar em decisão de negócio'),
  ('d1-1230-curadoria','Como incorporar a saúde mental à gestão de equipes'),
  ('d1-1340-invisivel-equipes','O desempenho da equipe começa onde ninguém vê'),
  ('d1-1420-usa-menos','Boreout: um risco silencioso, quando o trabalho pede menos do que você pode oferecer'),
  ('d1-1440-esperanca-caminhos','Esperança: e se houver outro caminho?'),
  ('d1-1500-autonomia-desorganizacao','Como produzir sem se esgotar: Redesenhando o trabalho para culturas de bem-estar e alta performance'),
  ('d1-1600-curadoria','Saúde mental não é igual para todos: Como trazer a diversidade para a conversa'),
  ('d2-1130-curadoria','O que levamos de casa para o trabalho: Histórias e valores que moldam a maneira de liderar'),
  ('d2-1230-curadoria','Ninguém deixa os filhos no estacionamento: Parentalidade como estratégia de bem-estar e resultados'),
  ('d2-1330-autografos-carla','Autógrafos com os autores'),
  ('d2-1340-antes-cobrar','Bem-estar sob pressão: o desafio de quem lidera'),
  ('d2-1600-curadoria','Liderança feminina em um futuro do trabalho líquido'),
  ('d2-1720-estrategia-pratica','Da estratégia à prática: Casos, decisões e aprendizados da alta liderança')
) as v(site_session_id, titulo)
where s.site_session_id = v.site_session_id;

-- ---------------------------------------------------------------------------
-- 3. Horários: a planilha do app vence.
update summit_2026.sessions s
   set inicio = v.inicio, fim = v.fim,
       duracao_min = (extract(epoch from (v.fim - v.inicio)) / 60)::int,
       atualizado_em = now()
from (values
  ('d1-0900-abertura',              timestamptz '2026-09-16 09:00-03', timestamptz '2026-09-16 09:05-03'),
  ('d1-0915-beneficio-transformacao',timestamptz '2026-09-16 09:05-03', timestamptz '2026-09-16 09:30-03'),
  ('d1-0940-bem-estar',             timestamptz '2026-09-16 09:30-03', timestamptz '2026-09-16 10:20-03'),
  ('d1-1030-quando-bem',            timestamptz '2026-09-16 10:20-03', timestamptz '2026-09-16 11:10-03'),
  ('d1-1400-autografos-jan',        timestamptz '2026-09-16 13:30-03', timestamptz '2026-09-16 14:30-03'),
  ('d2-1230-curadoria',             timestamptz '2026-09-17 12:30-03', timestamptz '2026-09-17 13:30-03'),
  ('d2-1330-autografos-carla',      timestamptz '2026-09-17 13:30-03', timestamptz '2026-09-17 15:00-03'),
  ('d2-1400-autografos-sonja',      timestamptz '2026-09-17 13:30-03', timestamptz '2026-09-17 14:30-03')
) as v(site_session_id, inicio, fim)
where s.site_session_id = v.site_session_id;

-- ---------------------------------------------------------------------------
-- 4. Espaço: a planilha do app vence. "Falhar melhor" passa da Sala Workshop 2
--    para a Sala Workshop 1.
update summit_2026.sessions s
   set espaco_id = l.id, atualizado_em = now()
from summit_2026.locations l
where s.site_session_id = 'd1-1500-falhar-melhor'
  and l.nome = 'Sala Workshop 1';

-- ---------------------------------------------------------------------------
-- 5. Sessões que existem no app e faltavam no backend (todas na Livraria da Vila).
insert into summit_2026.sessions
  (id, titulo, dia, inicio, fim, duracao_min, espaco_id, tipo, trilhas, ingressos,
   precisa_reserva, reserva_recomendada, lugares_limitados, topicos_aprendizado,
   resultados, event_id, site_session_id, atualizado_em)
select gen_random_uuid(), v.titulo, v.dia, v.inicio, v.fim,
       (extract(epoch from (v.fim - v.inicio)) / 60)::int,
       (select id from summit_2026.locations where nome = 'Livraria da Vila'),
       'autografos', '{}'::text[], '{mind,vip,prime,camarote}'::text[],
       false, false, false, '[]'::jsonb, '[]'::jsonb,
       (select id from summit_2026.events limit 1),
       v.site_session_id, now()
from (values
  ('d1-1330-autografos-autores','Autógrafos com os autores', date '2026-09-16',
     timestamptz '2026-09-16 13:30-03', timestamptz '2026-09-16 15:00-03'),
  ('d1-1700-autografos-autores','Autógrafos com os autores', date '2026-09-16',
     timestamptz '2026-09-16 17:00-03', timestamptz '2026-09-16 17:20-03'),
  ('d2-1700-autografo-ana-vazquez','Autógrafo Ana Vazquez', date '2026-09-17',
     timestamptz '2026-09-17 17:00-03', timestamptz '2026-09-17 17:20-03'),
  ('d2-1700-autografos-autores','Autógrafos com os autores', date '2026-09-17',
     timestamptz '2026-09-17 17:00-03', timestamptz '2026-09-17 17:20-03')
) as v(site_session_id, titulo, dia, inicio, fim)
where not exists (
  select 1 from summit_2026.sessions x where x.site_session_id = v.site_session_id
);

-- ---------------------------------------------------------------------------
-- 6. Mapeamento sessão -> ids do app. As 4 masterclasses carregam dois ids.
update summit_2026.sessions s set yazo_ids = v.ids
from (values
  ('d1-0730-credenciamento','{968}'::text[]),
  ('d1-0900-abertura','{969}'),
  ('d1-0915-beneficio-transformacao','{970}'),
  ('d1-0940-bem-estar','{971}'),
  ('d1-1030-quando-bem','{972}'),
  ('d1-1110-intervalo','{973}'),
  ('d1-1130-mensurar-intervir','{974,1057}'),
  ('d1-1130-mensuracao-pgr','{975}'),
  ('d1-1130-sustenta-equipes','{976}'),
  ('d1-1130-conversas-dificeis','{977}'),
  ('d1-1130-emocoes-positivas','{978}'),
  ('d1-1130-trabalho-ainda','{979}'),
  ('d1-1130-produtividade-sustentavel','{980}'),
  ('d1-1230-virada-diversidade','{981}'),
  ('d1-1230-nova-era','{982}'),
  ('d1-1230-curadoria','{983}'),
  ('d1-1330-almoco-experiencias','{984}'),
  ('d1-1430-virada-diversidade','{985}'),
  ('d1-1340-invisivel-equipes','{986}'),
  ('d1-1400-autografos-jan','{987}'),
  ('d1-1400-trabalho-proteger','{988}'),
  ('d1-1420-usa-menos','{989}'),
  ('d1-1430-modo-ativar','{990}'),
  ('d1-1440-esperanca-caminhos','{991}'),
  ('d1-1500-tres-movimentos','{992,1058}'),
  ('d1-1500-resiliencia-tempo','{993}'),
  ('d1-1500-lideranca-engajadora','{995}'),
  ('d1-1500-seu-emprego','{996}'),
  ('d1-1500-economia-distracao','{997}'),
  ('d1-1500-autonomia-desorganizacao','{998}'),
  ('d1-1500-falhar-melhor','{1013}'),
  ('d1-1530-trabalho-anos','{999}'),
  ('d1-1600-relacoes-sustentam','{1000}'),
  ('d1-1600-consciencia-finitude','{1001}'),
  ('d1-1600-curadoria','{1002}'),
  ('d1-1700-intervalo','{1003}'),
  ('d1-1720-lideranca-consciente','{1004}'),
  ('d1-1810-mito-colaborador','{1005}'),
  ('d1-1900-coquetel-autografos','{1006}'),
  ('d1-1330-autografos-autores','{1090}'),
  ('d1-1700-autografos-autores','{1091}'),
  ('d2-0730-credenciamento','{1007}'),
  ('d2-0900-quem-enxerga','{1008}'),
  ('d2-0930-programas-bem','{1009}'),
  ('d2-1020-obrigacao-gestao','{1010}'),
  ('d2-1110-intervalo','{1011}'),
  ('d2-1130-bem-estar','{1012,1059}'),
  ('d2-1130-voce-aguenta','{1017}'),
  ('d2-1130-riscos-psicossociais','{1014}'),
  ('d2-1130-onde-foi','{1016}'),
  ('d2-1130-comeca-agenda','{994}'),
  ('d2-1130-feedback-falta','{1015}'),
  ('d2-1130-curadoria','{1018}'),
  ('d2-1230-mulheres-abrem','{1019}'),
  ('d2-1230-curadoria','{1021}'),
  ('d2-1230-lideranca-emocionalmente','{1020}'),
  ('d2-1330-autografos-carla','{1023}'),
  ('d2-1330-almoco-experiencias','{1022}'),
  ('d2-1340-antes-cobrar','{1024}'),
  ('d2-1400-poder-sororidade','{1061}'),
  ('d2-1400-custo-caber','{1026}'),
  ('d2-1400-autografos-sonja','{1025}'),
  ('d2-1420-lider-super-heroi','{1027}'),
  ('d2-1440-segunda-feira','{1028}'),
  ('d2-1500-trabalho-hibrido','{1031}'),
  ('d2-1500-cultura-emocional','{1033}'),
  ('d2-1500-sobreviver-destruir','{1035}'),
  ('d2-1500-infraestrutura-performance','{1030}'),
  ('d2-1500-seu-cerebro','{1034}'),
  ('d2-1500-desalinhamentos-burnout','{1029,1060}'),
  ('d2-1500-lider-arquiteto','{1032}'),
  ('d2-1600-curadoria','{1038}'),
  ('d2-1600-quem-esta','{1037}'),
  ('d2-1600-conversas-corajosas','{1036}'),
  ('d2-1640-florescendo-tempos','{1039}'),
  ('d2-1700-intervalo','{1040}'),
  ('d2-1720-estrategia-pratica','{1041}'),
  ('d2-1800-melhores-equipes','{1042}'),
  ('d2-1900-coquetel-autografos','{1043}'),
  ('d2-1700-autografo-ana-vazquez','{1062}'),
  ('d2-1700-autografos-autores','{1092}')
) as v(site_session_id, ids)
where s.site_session_id = v.site_session_id;

commit;

-- ---------------------------------------------------------------------------
-- 7. Checkins e agendamentos do credenciamento vão chegar com o id do Yazo e
--    precisam achar a sessão por ele: sessions where yazo_ids @> array['1057'].
create index if not exists sessions_yazo_ids_idx
  on summit_2026.sessions using gin (yazo_ids);
