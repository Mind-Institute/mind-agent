create table tutorial_passos (
  id            uuid primary key default uuid_generate_v4(),
  chave         text unique not null,
  titulo        text not null,
  tela          text not null,
  alvo          text not null,
  onde          text not null,
  resumo        text not null,
  ordem         integer not null default 0,
  ativo         boolean not null default true
);

insert into tutorial_passos (chave, titulo, tela, alvo, onde, resumo, ordem) values
('favoritar','Salvar uma sessão','agenda','coracao','Aba Agenda','Na aba Agenda, toque no coração da sessão. Ela vai para Minha agenda.',1),
('reservar','Reservar lugar','detalhe','reservar','Dentro da sessão','Abra a sessão e toque em "Reservar lugar". A vaga é exclusiva por horário; depois é só fazer o check-in até o início.',2),
('minha_agenda','Ver a sua agenda','minha-agenda','card','Aba Minha agenda','Na aba Minha agenda ficam as sessões salvas e reservadas, por dia.',3),
('qr','Seu QR Code','qrcode','escanear','Aba QR Code','Na aba QR Code está sua credencial de entrada — e é com ela que você troca contato.',4),
('escanear','Escanear alguém','scanner','meuqr','QR Code → Escanear','Em QR Code, toque em "Escanear Qr Code" e aponte para o código da pessoa.',5),
('mapa','Mapa do evento','menu','mapa','Menu → Mapa do evento','Menu → Mapa do evento. Dá para filtrar por arenas, estandes e lounges.',6),
('rede','Área de network','menu','rede','Menu → Área de network','Menu → Área de network. Ali você encontra quem está no evento e envia convite.',7),
('palestrantes','Palestrantes','menu','palestrantes','Menu → Palestrantes','Menu → Palestrantes: todos os nomes, com bio e sessões.',8),
('chat','Onde eu fico','menu','chat','Menu → Chat','Menu → Chat. É onde você me encontra durante os dois dias.',9);

update ferramentas set ativo = false where nome in ('reservar_lugar','cancelar_reserva');

insert into ferramentas (nome, descricao, json_schema, tipo_exec, destino, escrita, requer_confirmacao) values
('mostrar_como_fazer',
 'Mostra à pessoa ONDE FICA alguma coisa no app: devolve o print da tela real com o botão destacado, mais o caminho em texto. Use sempre que a pergunta for sobre onde algo está ou como fazer algo — reservar, favoritar, escanear, achar o mapa, ver a agenda. Você não executa por ela; você mostra onde é.',
 '{"type":"object","properties":{"chave":{"type":"string","description":"favoritar | reservar | minha_agenda | qr | escanear | mapa | rede | chat"}},"required":["chave"],"additionalProperties":false}',
 'interna', 'tutorial.mostrar', false, false);

insert into config (chave, valor, descricao) values
('proativo_perfis',
 '{
    "antes":   {"maximo_dia":1, "janela_silenciosa":{"de":"21:00","ate":"08:00"}},
    "durante": {"maximo_dia":12,"janela_silenciosa":{"de":"22:30","ate":"07:00"},"intervalo_minimo_min":25},
    "depois":  {"maximo_dia":2, "janela_silenciosa":{"de":"21:00","ate":"08:30"}}
  }',
 'Intensidade do proativo por fase do evento. "durante" vale nos dias 16 e 17.');

insert into config (chave, valor, descricao) values
('proativo_regras_duras',
 '{
    "nao_durante_sessao": true,
    "nao_repetir_recusado": true,
    "respeitar_silenciar": true,
    "urgencia_ignora_limite": ["sala_alterada","cancelamento","emergencia"]
  }',
 'Nunca interromper quem está assistindo, nunca insistir no que foi recusado, e sempre respeitar "não me manda mais". Só urgência real fura o limite.');

insert into config (chave, valor, descricao) values
('identidade',
 '{
    "ordem": ["token_yazo","email_do_app","sessao_dispositivo","email_digitado","anonimo"],
    "normalizar_email": "minusculas_e_sem_espacos",
    "email_do_app_confia": true,
    "email_digitado_exige_codigo": true,
    "codigo_validade_min": 15,
    "historico_por_confianca": {
      "alta":  "completo",
      "media": "completo_com_confirmacao",
      "baixa": "conversa_nova_ate_verificar"
    }
  }',
 'Cascata de identificação e o quanto cada origem libera do histórico.');

create table verificacoes_email (
  id                uuid primary key default uuid_generate_v4(),
  email             text not null,
  dispositivo_id    uuid references dispositivos(id) on delete cascade,
  codigo_hash       text not null,
  tentativas        integer not null default 0,
  expira_em         timestamptz not null,
  verificado_em     timestamptz,
  criado_em         timestamptz not null default now()
);
create index on verificacoes_email (email, criado_em desc);

create table politicas (
  id            uuid primary key default uuid_generate_v4(),
  chave         text not null,
  versao        integer not null,
  titulo        text not null,
  texto         text not null,
  ativo         boolean not null default false,
  criado_em     timestamptz not null default now(),
  unique (chave, versao)
);
create unique index on politicas (chave) where ativo;

create table consentimentos (
  id                uuid primary key default uuid_generate_v4(),
  participante_id   uuid not null references participantes(id) on delete cascade,
  finalidade        text not null,
  concedido         boolean not null,
  politica_chave    text not null,
  politica_versao   integer not null,
  texto_exibido     text not null,
  origem            text not null,
  mensagem_id       uuid references mensagens(id) on delete set null,
  criado_em         timestamptz not null default now(),
  revogado_em       timestamptz
);
create index on consentimentos (participante_id, finalidade, criado_em desc);

create table memoria_bloqueios (
  chave             text primary key,
  sujeito           text not null,
  motivo            text not null,
  exemplo_bloqueado text,
  exemplo_liberado  text,
  ativo             boolean not null default true
);
insert into memoria_bloqueios (chave, sujeito, motivo, exemplo_bloqueado, exemplo_liberado) values
('saude_do_titular',      'titular','Dado de saúde do próprio titular — art. 11 da LGPD',
  'Estou em burnout; não durmo há semanas',
  'Minha equipe está exausta; queremos atacar burnout na empresa'),
('diagnostico_titular',   'titular','Dado de saúde',
  'Tenho depressão diagnosticada', 'Vejo muitos casos de depressão no meu time'),
('medicacao_titular',     'titular','Dado de saúde',
  'Tomo antidepressivo', 'Nossa cobertura de saúde inclui psiquiatria'),
('afastamento_titular',   'titular','Dado de saúde do titular',
  'Me afastei ano passado', 'Nosso índice de afastamento subiu 30%'),
('orientacao_sexual',     'titular','Dado sensível', null, null),
('religiao',              'titular','Dado sensível', null, null),
('opiniao_politica',      'titular','Dado sensível', null, null),
('filiacao_sindical',     'titular','Dado sensível', null, null),
('origem_racial',         'titular','Dado sensível', null,
  'Temos meta de representatividade racial na liderança'),
('saude_de_pessoa_citada','terceiro_identificado','Saúde de alguém identificável que não é o titular',
  'Meu diretor João está afastado por depressão',
  'Parte da liderança está sobrecarregada');

create table solicitacoes_titular (
  id                uuid primary key default uuid_generate_v4(),
  participante_id   uuid not null references participantes(id) on delete cascade,
  tipo              text not null,
  detalhe           text,
  estado            text not null default 'aberta',
  criado_em         timestamptz not null default now(),
  atendido_em       timestamptz,
  observacao        text
);
create index on solicitacoes_titular (estado, criado_em);

insert into config (chave, valor, descricao) values
('lgpd',
 '{
    "controlador": "Mind Institute",
    "encarregado_email": "privacidade@joinmind.com.br",
    "bases_legais": {
      "operar_agente": "execucao_de_contrato",
      "recomendar_conteudo": "legitimo_interesse",
      "melhorar_evento": "legitimo_interesse",
      "contato_comercial": "consentimento",
      "whatsapp": "consentimento",
      "uso_pos_evento": "consentimento"
    },
    "retencao_dias": {"conversas": 180, "logs_tecnicos": 30, "sinais_comerciais": 365},
    "subprocessadores": ["Anthropic (modelo)", "Supabase (banco)", "Cloudflare (aplicação)"],
    "transferencia_internacional": true,
    "nao_enviar_ao_modelo": ["telefone", "documento", "endereco"]
  }',
 'Bases legais por finalidade, prazos e quem processa o quê. Toda mudança aqui exige revisar o aviso exibido.');

insert into ferramentas (nome, descricao, json_schema, tipo_exec, destino, escrita, requer_confirmacao) values
('registrar_consentimento',
 'Registra que a pessoa aceitou (ou recusou) uma finalidade específica: contato comercial, WhatsApp ou uso pós-evento. Só chame depois de mostrar o texto e ela responder claramente.',
 '{"type":"object","properties":{"finalidade":{"type":"string"},"concedido":{"type":"boolean"}},"required":["finalidade","concedido"],"additionalProperties":false}',
 'interna', 'lgpd.consentimento', true, false),

('meus_dados',
 'Mostra à pessoa o que está guardado sobre ela: perfil, objetivo, memória ativa e feedbacks.',
 '{"type":"object","properties":{},"additionalProperties":false}',
 'interna', 'lgpd.exportar', false, false),

('apagar_meus_dados',
 'Abre pedido de exclusão dos dados da pessoa. Sempre confirmar antes: a conversa e a memória somem.',
 '{"type":"object","properties":{"detalhe":{"type":"string"}},"additionalProperties":false}',
 'interna', 'lgpd.excluir', true, true);

insert into politicas (chave, versao, titulo, texto, ativo) values
('aviso_agente', 1, 'Como eu uso o que você me conta',
$$Eu guardo o que ajuda a te ajudar melhor: seu perfil do ingresso, o que você me contar sobre seus objetivos e interesses, o que você salvou na agenda e o que achou das sessões. Uso isso só para recomendar conteúdo e melhorar a sua experiência no Summit.

Uma coisa eu não guardo: informação sobre a sua própria saúde. Se você me contar algo pessoal, a gente conversa — mas não fica registrado. O que você me contar sobre a sua empresa e a sua equipe, sim: é disso que este evento trata.

Suas conversas ficam por 180 dias. A qualquer momento você pode me pedir para mostrar ou apagar tudo o que tenho sobre você.$$, true),

('contato_comercial', 1, 'Falar com alguém do Mind',
$$Se você quiser, alguém do time do Mind entra em contato para conversar sobre levar esse trabalho para a sua empresa. Vou compartilhar seu nome, e-mail e o assunto do seu interesse com o time comercial — nada da sua conversa vai junto.

Você pode mudar de ideia quando quiser, é só me dizer.$$, true),

('whatsapp', 1, 'Receber por WhatsApp',
$$Para mandar lembretes e materiais por WhatsApp, preciso do seu OK. Você pode cancelar a qualquer momento respondendo "parar" ou me pedindo aqui.$$, true);

insert into templates (chave, texto, variaveis) values
('lgpd.aviso_inicial',
 'Antes de começarmos: eu guardo o que você me contar para recomendar melhor, e nada sobre sua saúde fica registrado. Você pode me pedir para mostrar ou apagar tudo quando quiser.',
 '{}'),
('lgpd.exclusao_confirmar',
 'Só confirmando: eu apago seu perfil, nossa conversa e o que aprendi sobre você. Isso não cancela seu ingresso nem sua reserva no app. Posso seguir?',
 '{}'),
('lgpd.exclusao_feita',
 'Pronto, apaguei. Se quiser recomeçar, é só me chamar — vai ser como a primeira vez.',
 '{}'),
('agente.ensina_caminho',
 '{{resumo}} Te mostro exatamente onde fica:',
 '{resumo}');

insert into feature_flags (chave, ativo, publico, descricao) values
('agente_agenda_por_voce', false, '{}', 'DESLIGADA por decisão: o agente ensina o caminho, não reserva. Só ligar se a Yazo abrir escrita e alguém assumir o conflito de vaga.'),
('verificacao_email',      false, '{}', 'Código por e-mail quando a identificação não vem da Yazo'),
('aviso_privacidade',      true,  '{}', 'Mostrar o aviso curto na primeira conversa');

update prompts set ativo = false where nome = 'sistema';

insert into prompts (nome, versao, conteudo, ativo, notas)
select 'sistema', 3, conteudo || $$

Sobre saúde e o que você registra:
Este é um evento sobre bem-estar no trabalho. Falar de burnout, estresse crônico, afastamento, sobrecarga e riscos psicossociais é o assunto — não é tema proibido. O que decide se você registra não é o tema, é de quem se está falando.

- Sujeito é a empresa, a equipe, o mercado ou um cenário ("minha equipe está exausta", "temos alto índice de afastamento", "quero reduzir burnout na organização"): é contexto profissional. Registre normalmente — é o que permite recomendar bem.
- Sujeito é a própria pessoa e o assunto é a saúde dela ("eu estou em burnout", "tomo antidepressivo", "me afastei ano passado"): acolha e converse com naturalidade, mas não registre nada disso — nem como interesse, nem como sinal comercial.
- O mesmo vale para a saúde de alguém que ela cite pelo nome ou pelo cargo.

Na dúvida sobre de quem se está falando, não registre. E nunca devolva à pessoa, dias depois, algo pessoal que ela te contou num momento difícil.$$,
       true, 'v3: separa tema (bem-estar, permitido) de sujeito (saúde do titular, não registra).'
from prompts where nome = 'sistema' and versao = 2;
