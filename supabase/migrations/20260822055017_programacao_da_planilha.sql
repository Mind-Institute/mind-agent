-- Programacao reescrita a partir de programacaomindsummit2026.xlsx
-- (Adriana, 2026-08-22). As colunas passam a espelhar as da planilha:
-- dia, horario (inicio/fim), ingressos, local, conteudo (titulo/descricao),
-- palestrantes e duracao.
--
-- Estrutura mantida de proposito: palestrante continua em mind.speakers,
-- ligado por mind.session_speakers. Os 42 palestrantes aparecem em 67
-- sessoes com muita repeticao (Amy Edmondson em 3, Carla Tieppo em 3) e a
-- bio precisa existir uma vez so. O PAPEL e da ligacao, nao da pessoa:
-- Denize Savi media um painel e palestra em outro.
--
-- 'ingressos' e coluna nova e e o que faltava para o agente responder
-- "esse workshop e VIP e Prime" sem deduzir do nome da sala.
-- mind.session_reservations esta vazia: nao ha reserva de participante a
-- preservar na reescrita.
--
-- O payload veio antes para mind._import_programacao (execute_sql).

alter table mind.sessions
  add column if not exists ingressos text[] not null default '{}',
  add column if not exists duracao_min integer;

comment on column mind.sessions.ingressos is
  'Quais experiencias dao acesso a esta sessao. E o que permite ao agente dizer "esse workshop e VIP e Prime".';

alter table mind.session_speakers
  add column if not exists papel text not null default 'palestrante'
    check (papel in ('palestrante','mediacao','apresentacao','convidado'));

comment on column mind.session_speakers.papel is
  'Papel nesta sessao especifica. Quem media um painel palestra em outro.';

delete from mind.session_speakers;
delete from mind.sessions;

insert into mind.sessions
  (event_id, titulo, descricao, dia, inicio, fim, espaco_id, tipo,
   ingressos, duracao_min, precisa_reserva, atualizado_em)
select (select id from mind.events limit 1),
       e->>'t',
       e->>'d',
       (left(e->>'i', 10))::date,
       (e->>'i')::timestamp at time zone 'America/Sao_Paulo',
       (e->>'f')::timestamp at time zone 'America/Sao_Paulo',
       (select l.id from mind.locations l where l.nome = e->>'l'),
       e->>'tp',
       (select coalesce(array_agg(x), '{}') from jsonb_array_elements_text(e->'ing') x),
       (e->>'du')::int,
       (e->>'r')::boolean,
       now()
from mind._import_programacao t
cross join lateral jsonb_array_elements(t.j) e;

insert into mind.session_speakers (sessao_id, palestrante_id, papel)
select s.id, sp.id, p->>1
from mind._import_programacao t
cross join lateral jsonb_array_elements(t.j) e
cross join lateral jsonb_array_elements(coalesce(e->'p', '[]'::jsonb)) p
join mind.sessions s
  on s.titulo = e->>'t'
 and s.inicio = (e->>'i')::timestamp at time zone 'America/Sao_Paulo'
join mind.speakers sp on sp.nome = p->>0;

drop table mind._import_programacao;

-- Copia duplicada das bios: sai, para nao existirem duas verdades sobre a
-- mesma pessoa. O agente ja le palestrante de mind.speakers, via
-- mindagent_chat_search.
delete from mind.knowledge_chunks
 where doc_id in (select id from mind.knowledge_documents where tipo_conteudo = 'palestrante');
delete from mind.knowledge_documents where tipo_conteudo = 'palestrante';
