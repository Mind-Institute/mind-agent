insert into taxonomia (tipo, codigo, rotulo, sinonimos) values
('motivo_ausencia','sala_cheia',      'Sala lotada',                 '{"não coube","lotou","fila"}'),
('motivo_ausencia','conflito_horario','Bateu com outra sessão',      '{"choque de horário","estava em outra"}'),
('motivo_ausencia','sem_vaga',        'Não consegui reservar',       '{"esgotou","sem vaga"}'),
('motivo_ausencia','atraso',          'Cheguei tarde',               '{"atrasei","perdi o começo"}'),
('motivo_ausencia','compromisso',     'Reunião ou compromisso',      '{"trabalho","call"}'),
('motivo_ausencia','cansaco',         'Precisei de uma pausa',       '{"cansei","descansar"}'),
('motivo_ausencia','mudou_de_ideia',  'Mudei de ideia',              '{"não era o que eu esperava","preferi outra"}'),
('motivo_ausencia','esqueceu',        'Esqueci',                     '{"passou","não vi a hora"}'),
('motivo_ausencia','outro',           'Outro motivo',                '{}');

create table motivos_ausencia (
  codigo            text primary key references taxonomia(codigo),
  demanda_frustrada boolean not null,
  descricao         text
);
insert into motivos_ausencia (codigo, demanda_frustrada, descricao) values
('sala_cheia',       true,  'A organização não deu conta da demanda'),
('conflito_horario', true,  'A grade criou a escolha impossível'),
('sem_vaga',         true,  'Vagas esgotaram'),
('atraso',           false, 'Logística pessoal'),
('compromisso',      false, 'Escolha da pessoa'),
('cansaco',          false, 'Escolha da pessoa — mas em volume vira sinal de ritmo do evento'),
('mudou_de_ideia',   false, 'Sinal sobre a sessão, não sobre a operação'),
('esqueceu',         false, 'Sinal sobre o lembrete, não sobre a sessão'),
('outro',            false, null);

create table jornada_eventos (
  id                uuid primary key default uuid_generate_v4(),
  participante_id   uuid not null references participantes(id) on delete cascade,
  sessao_id         uuid not null references agenda_sessoes(id) on delete cascade,
  tipo              text not null,
  origem            text not null,
  dados             jsonb not null default '{}',
  mensagem_id       uuid references mensagens(id) on delete set null,
  criado_em         timestamptz not null default now()
);
create index on jornada_eventos (participante_id, criado_em);
create index on jornada_eventos (sessao_id, tipo);

create table jornada_sessao (
  participante_id   uuid not null references participantes(id) on delete cascade,
  sessao_id         uuid not null references agenda_sessoes(id) on delete cascade,
  intencao          text,
  intencao_forca    text,
  origem_intencao   text,
  planejou          boolean not null default false,
  compareceu        boolean,
  fonte_presenca    text,
  confianca_presenca text,
  motivo_ausencia   text references taxonomia(codigo),
  atualizado_em     timestamptz not null default now(),
  primary key (participante_id, sessao_id)
);
create index on jornada_sessao (sessao_id, compareceu);
create index on jornada_sessao (participante_id, planejou);

create or replace function aplicar_evento_jornada() returns trigger
language plpgsql as $$
declare
  objetiva boolean := new.origem in ('checkin','qr','reserva_usada');
begin
  insert into jornada_sessao (participante_id, sessao_id)
  values (new.participante_id, new.sessao_id)
  on conflict (participante_id, sessao_id) do nothing;

  update jornada_sessao set
    intencao = case new.tipo
                 when 'interesse' then 'interesse'
                 when 'planejou'  then 'planejada'
                 when 'reservou'  then 'reservada'
                 when 'removeu'   then 'removida'
                 else intencao end,
    intencao_forca = coalesce(new.dados->>'forca', intencao_forca,
                       case new.tipo when 'reservou' then 'alta'
                                     when 'planejou' then 'media'
                                     when 'interesse' then 'baixa' end),
    origem_intencao = case when new.tipo in ('interesse','planejou','reservou','removeu')
                           then new.origem else origem_intencao end,
    planejou = planejou or new.tipo in ('planejou','reservou'),
    compareceu = case
        when new.tipo in ('compareceu','nao_compareceu')
             and (confianca_presenca is distinct from 'objetiva' or objetiva)
        then (new.tipo = 'compareceu')
        else compareceu end,
    fonte_presenca = case
        when new.tipo in ('compareceu','nao_compareceu')
             and (confianca_presenca is distinct from 'objetiva' or objetiva)
        then new.origem else fonte_presenca end,
    confianca_presenca = case
        when new.tipo in ('compareceu','nao_compareceu')
             and (confianca_presenca is distinct from 'objetiva' or objetiva)
        then case when objetiva then 'objetiva'
                  when new.origem = 'conversa' then 'declarada'
                  else 'fraca' end
        else confianca_presenca end,
    motivo_ausencia = coalesce(new.dados->>'motivo', motivo_ausencia),
    atualizado_em = now()
  where participante_id = new.participante_id and sessao_id = new.sessao_id;

  return null;
end $$;

create trigger t_jornada after insert on jornada_eventos
  for each row execute function aplicar_evento_jornada();

create view v_conflitos_agenda as
select j1.participante_id,
       j1.sessao_id  as sessao_a, s1.titulo as titulo_a, s1.inicio as inicio_a,
       j2.sessao_id  as sessao_b, s2.titulo as titulo_b, s2.inicio as inicio_b
from jornada_sessao j1
join jornada_sessao j2
  on j1.participante_id = j2.participante_id and j1.sessao_id < j2.sessao_id
join agenda_sessoes s1 on s1.id = j1.sessao_id
join agenda_sessoes s2 on s2.id = j2.sessao_id
where j1.planejou and j2.planejou
  and j1.intencao is distinct from 'removida'
  and j2.intencao is distinct from 'removida'
  and s1.inicio < s2.fim and s2.inicio < s1.fim;

create table nps_summit (
  id                uuid primary key default uuid_generate_v4(),
  participante_id   uuid not null references participantes(id) on delete cascade,
  nota              integer not null check (nota between 0 and 10),
  comentario        text,
  retrato           jsonb not null default '{}',
  conversa_id       uuid references conversas(id) on delete set null,
  criado_em         timestamptz not null default now(),
  unique (participante_id)
);

create view v_sessoes_jornada as
select s.id, s.titulo, s.dia, s.inicio,
       count(*) filter (where j.intencao in ('interesse','planejada','reservada'))         as quiseram,
       count(*) filter (where j.planejou)                                                 as planejaram,
       count(*) filter (where j.compareceu)                                               as compareceram,
       count(*) filter (where j.compareceu = false and m.demanda_frustrada)               as frustrados,
       count(*) filter (where j.compareceu = false and not coalesce(m.demanda_frustrada,false)) as desistiram,
       round(avg(f.nota)::numeric, 1)                                                     as nota_media,
       count(f.*) filter (where f.intencao_aplicar is not null)                           as vao_aplicar
from agenda_sessoes s
left join jornada_sessao j on j.sessao_id = s.id
left join motivos_ausencia m on m.codigo = j.motivo_ausencia
left join sessao_feedback f on f.sessao_id = s.id
group by s.id, s.titulo, s.dia, s.inicio
order by s.dia, s.inicio;

create view v_demanda_frustrada as
select s.id, s.titulo, s.dia,
       j.motivo_ausencia, t.rotulo as motivo,
       count(*) as pessoas
from jornada_sessao j
join agenda_sessoes s on s.id = j.sessao_id
join motivos_ausencia m on m.codigo = j.motivo_ausencia and m.demanda_frustrada
left join taxonomia t on t.codigo = j.motivo_ausencia and t.tipo = 'motivo_ausencia'
where j.compareceu = false
group by s.id, s.titulo, s.dia, j.motivo_ausencia, t.rotulo
order by pessoas desc;

create view v_aderencia_por_area as
select s.titulo, mem.valor #>> '{}' as area, count(*) as compareceram
from jornada_sessao j
join agenda_sessoes s on s.id = j.sessao_id
join participante_memoria mem
  on mem.participante_id = j.participante_id
 and mem.chave = 'area_profissional' and mem.status = 'ativa'
where j.compareceu
group by s.titulo, mem.valor
order by s.titulo, compareceram desc;

insert into ferramentas (nome, descricao, json_schema, tipo_exec, destino, escrita, requer_confirmacao) values
('registrar_intencao',
 'Registra que a pessoa quer ver (ou tirou da lista) uma sessão. Use quando ela contar o que colocou na agenda ou o que pretende assistir — inclusive o que ela quis e não conseguiu.',
 '{"type":"object","properties":{"sessao_id":{"type":"string"},"tipo":{"type":"string","description":"interesse | planejou | reservou | removeu"},"forca":{"type":"string"}},"required":["sessao_id","tipo"],"additionalProperties":false}',
 'interna', 'jornada.intencao', true, false),

('confirmar_presenca',
 'Grava se a pessoa conseguiu assistir a uma sessão que estava na agenda dela. Se não foi, registre o motivo pelo vocabulário. Só pergunte quando não houver check-in ou leitura de QR.',
 '{"type":"object","properties":{"sessao_id":{"type":"string"},"compareceu":{"type":"boolean"},"motivo":{"type":"string"}},"required":["sessao_id","compareceu"],"additionalProperties":false}',
 'interna', 'jornada.presenca', true, false),

('minha_jornada',
 'Devolve o retrato da jornada da pessoa até agora: o que ela planejou, assistiu, perdeu e avaliou. Use antes de recomendar, antes do NPS e no fechamento.',
 '{"type":"object","properties":{},"additionalProperties":false}',
 'interna', 'jornada.retrato', false, false),

('registrar_nps',
 'Guarda a nota de recomendação do Summit junto com o retrato da jornada da pessoa naquele momento.',
 '{"type":"object","properties":{"nota":{"type":"integer"},"comentario":{"type":"string"}},"required":["nota"],"additionalProperties":false}',
 'interna', 'jornada.nps', true, false);

insert into config (chave, valor, descricao) values
('jornada',
 '{
    "nao_perguntar_se_ha_checkin": true,
    "perguntar_presenca_apos_min": 20,
    "so_perguntar_se_planejou": true,
    "abrir_pela_agenda": true,
    "nps_exige_jornada_minima": {"sessoes_assistidas": 1},
    "nps_janela": "ultimo_dia_tarde"
  }',
 'Quando perguntar sobre presença e NPS. Nunca perguntar o que já se sabe por dado objetivo.');

insert into templates (chave, texto, variaveis) values
('jornada.abertura_agenda',
 'Me conta: o que você já colocou na sua agenda? Pelas escolhas eu já consigo sugerir o que combina.',
 '{}'),
('jornada.confirmar_tema',
 'Pelo que você escolheu, parece que o seu tema é {{tema}}. É por aí, ou tem outra coisa te puxando?',
 '{tema}'),
('jornada.perguntar_presenca',
 'Você tinha colocado "{{titulo}}" na agenda. Conseguiu assistir?',
 '{titulo}'),
('jornada.motivo_ausencia',
 'Entendi. Foi por quê — sala cheia, bateu com outra sessão, ou mudou de ideia?',
 '{}'),
('jornada.conflito',
 '"{{titulo_a}}" e "{{titulo_b}}" acontecem no mesmo horário. Quer que eu te ajude a escolher pelo que você está querendo resolver?',
 '{titulo_a,titulo_b}'),
('jornada.nps',
 'Última pergunta, e ela vale muito: de 0 a 10, quanto você recomendaria o Mind Summit para alguém como você?',
 '{}'),
('jornada.fechamento',
 'Fecha assim o seu Summit: você veio querendo {{pergunta_guia}}, assistiu {{assistidas}} sessões e disse que vai aplicar {{aplicacoes}}. O que ficou pendente eu te mando por aqui.',
 '{pergunta_guia,assistidas,aplicacoes}');

insert into regras_proativas (nome, gatilho, template_chave, antecedencia_min, canal, prioridade, cooldown_horas, limite_dia, condicao, publico) values
('presenca_pos_sessao', 'sessao_terminou',  'jornada.perguntar_presenca', -20, 'app', 5, 1, 4, '{"planejou":true,"sem_checkin":true}', '{}'),
('conflito_agenda',     'conflito_detectado','jornada.conflito',          null, 'app', 3, 6, 2, '{}',                                   '{}'),
('nps_final',           'fim_do_evento',    'jornada.nps',               null, 'app', 2, 24,1, '{"assistiu_ao_menos":1}',              '{}'),
('fechamento',          'fim_do_evento',    'jornada.fechamento',        null, 'app', 1, 24,1, '{"tem_objetivo":true}',                '{}');

update prompts set ativo = false where nome = 'sistema';

insert into prompts (nome, versao, conteudo, ativo, notas)
select 'sistema', 4, conteudo || $$

Sobre a agenda da pessoa:
Você acompanha a jornada dela, não só o perfil. Isso muda três coisas na conversa.

- Comece pela agenda quando não souber nada: "o que você já colocou na sua agenda?" é mais leve que qualquer pergunta sobre cargo ou objetivo, e diz muito. Pelas escolhas, proponha o tema em vez de afirmá-lo: "parece que o seu tema é X — é por aí?".
- Registre o que ela quis ver, inclusive o que não conseguiu. Sessão perdida por sala cheia ou choque de horário é informação valiosa; sessão que ela tirou da lista também.
- Depois de uma sessão que estava na agenda dela, pergunte se conseguiu ir — mas só se você não souber por check-in ou leitura de QR. Nunca pergunte o que o sistema já sabe.

Se ela foi, aí sim pergunte o que achou: primeiro em aberto, depois a nota, depois o que pretende aplicar. Se não foi, pergunte o motivo com opções concretas em vez de deixar em aberto.

No fim do evento, antes de pedir a nota do Summit, olhe a jornada: quem quis ver quatro sessões e conseguiu uma tem um motivo para a nota, e você deve reconhecê-lo em vez de ignorá-lo.$$,
       true, 'v4: jornada da agenda — intenção, presença, motivo e NPS com contexto.'
from prompts where nome = 'sistema' and versao = 3;

alter table jornada_eventos enable row level security;
alter table jornada_sessao  enable row level security;
alter table nps_summit      enable row level security;
