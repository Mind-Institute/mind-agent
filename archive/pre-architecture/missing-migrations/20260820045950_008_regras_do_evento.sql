create table regras_evento (
  chave         text primary key,
  titulo        text not null,
  texto         text not null,
  aplica_em     text[] not null default '{}',
  prioridade    integer not null default 5,
  ativo         boolean not null default true,
  atualizado_em timestamptz not null default now()
);

insert into regras_evento (chave, titulo, texto, aplica_em, prioridade) values
('reserva_expira',
 'A reserva cai 5 minutos antes',
 'Todas as reservas caem 5 minutos antes do conteúdo começar, para dar lugar à fila de espera. Chegue com alguma folga.',
 '{reservar,minha_agenda,proxima_sessao}', 1),

('fila_de_espera',
 'Fila de espera',
 'Se você quiser ir a um conteúdo sem vagas, dá para esperar na fila de espera e ocupar os assentos remanescentes.',
 '{reservar,sem_vaga}', 2),

('vagas_limitadas',
 'Onde a vaga é limitada',
 'Arena Sextante, Arena LinkedIn, Workshops e Masterclasses têm vagas limitadas. Nesses casos, o agendamento prévio é recomendado.',
 '{reservar,favoritar,recomendacao}', 1);

alter table tutorial_passos add column if not exists aviso_chave text references regras_evento(chave);
update tutorial_passos set aviso_chave = 'reserva_expira' where chave = 'reservar';
update tutorial_passos set aviso_chave = 'vagas_limitadas' where chave = 'favoritar';

update ferramentas
   set descricao = 'Mostra à pessoa ONDE FICA alguma coisa no app: devolve o print da tela real com o botão destacado, o caminho em texto e, quando houver, a regra do evento que precisa ser dita junto (por exemplo: reservas caem 5 minutos antes). Use sempre que a pergunta for sobre onde algo está ou como fazer algo. Você não executa por ela; você mostra onde é e explica a regra.'
 where nome = 'mostrar_como_fazer';

insert into taxonomia (tipo, codigo, rotulo, sinonimos) values
('motivo_ausencia','fila_nao_entrou','Esperei na fila e não entrei','{"fila de espera","não coube"}'),
('motivo_ausencia','reserva_expirou','Cheguei depois e a reserva caiu','{"perdi a reserva","cheguei 5 min antes"}');

insert into motivos_ausencia (codigo, demanda_frustrada, descricao) values
('fila_nao_entrou', true,  'Quis, esperou e não coube — demanda reprimida do jeito mais claro'),
('reserva_expirou', false, 'A reserva caiu por atraso; em volume, sinal de que o aviso não chegou a tempo');

insert into templates (chave, texto, variaveis) values
('regra.reserva_expira_agora',
 'Sua reserva de "{{titulo}}" cai em 5 minutos, quando abre a fila de espera. Se estiver a caminho, é agora. 🏃',
 '{titulo}'),
('regra.fila_liberou',
 'Liberaram assentos em "{{titulo}}" — a fila de espera está entrando agora, no {{espaco}}.',
 '{titulo,espaco}'),
('regra.sem_vaga',
 'Essa sessão já está sem vaga. Dá para entrar na fila de espera e pegar assento remanescente — as reservas caem 5 minutos antes do início, então costuma sobrar lugar.',
 '{}');

insert into regras_proativas (nome, gatilho, template_chave, antecedencia_min, canal, prioridade, cooldown_horas, limite_dia, condicao, publico) values
('reserva_vai_cair', 'reserva_proxima', 'regra.reserva_expira_agora', 8,  'push', 1, 0, 4, '{"estado":"confirmada","sem_checkin":true}', '{}'),
('fila_liberou',     'assentos_livres', 'regra.fila_liberou',         null,'app',  2, 0, 3, '{"na_fila":true}',                          '{}');

insert into config (chave, valor, descricao) values
('vagas_limitadas',
 '{
    "espacos": ["Arena Sextante", "Arena LinkedIn", "Workshops", "Masterclasses"],
    "avisar_ao_recomendar": true,
    "reserva_expira_min": 5,
    "tem_fila_de_espera": true
  }',
 'Onde a vaga é limitada e como a regra de expiração funciona. Editar aqui muda a fala do agente.');
