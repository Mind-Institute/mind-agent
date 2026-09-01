-- ============================================================
-- 01 · concierge.avisos — a casa dos avisos da home
-- ============================================================
-- Projeto: mind-agent (ymnmotgglsrxmjmonwjz)
-- Aplicar em: SQL Editor do Supabase, ou `apply_migration`.
-- Reversível: `drop table concierge.avisos;` desfaz tudo deste arquivo.
--
-- POR QUE AQUI
-- Antes disto os avisos eram quatro objetos escritos à mão em
-- `home/estado.js`: trocar um exigia deploy do app. O painel
-- administrativo (Home V3 › Avisos) precisa escrever, e o app precisa
-- ler — falta uma casa e é esta.
--
-- Fica em `concierge` porque é o schema da experiência do participante:
-- `concierge.tutorial_passos` já apontava para cá pela coluna
-- `aviso_chave`, que nunca teve tabela do outro lado.
--
-- SEGURANÇA
-- RLS ligada e nenhuma política, exatamente como as outras treze tabelas
-- de `concierge`. Quem lê e escreve é função SECURITY DEFINER ou
-- service_role. Não abre superfície nova para anon nem authenticated.

create table if not exists concierge.avisos (
  id uuid primary key default gen_random_uuid(),

  -- Identificador estável para o app. Os quatro avisos que vieram do
  -- código têm chave ('sala', 'ingresso'…); aviso criado no painel não
  -- tem, e o app usa o uuid. Os dois convivem.
  chave text unique,

  icone text not null default 'megafone',
  titulo text not null,
  subtitulo text not null default '',
  descricao text not null default '',

  -- Disparo imediato ignora o horário: é o caminho do dia do evento.
  imediato boolean not null default false,
  disparo_em timestamptz,

  situacao text not null default 'rascunho',

  -- Alguns avisos ensinam onde a coisa fica no app. Guardam o roteiro do
  -- tutorial e o texto do botão. Nulo na maioria.
  ver_no_app text,
  botao_ver_no_app text,

  event_id uuid,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,

  constraint avisos_icone_valido check (
    icone in ('megafone','lugar','relogio','sino','ingresso','fone','agenda','alerta','estrela')
  ),
  constraint avisos_situacao_valida check (
    situacao in ('rascunho','agendado','no-ar','encerrado')
  ),
  -- Agendado sem horário não sai nunca: é erro de cadastro, não estado.
  constraint avisos_agendado_tem_horario check (
    situacao <> 'agendado' or disparo_em is not null
  )
);

comment on table concierge.avisos is
  'Avisos da home do participante (Home V3). Escrita pelo painel admin, leitura pelo bootstrap do app.';
comment on column concierge.avisos.situacao is
  'rascunho: não sai. agendado: entra quando disparo_em chega. no-ar: em circulação agora. encerrado: saiu.';

create index if not exists avisos_circulacao
  on concierge.avisos (situacao, disparo_em desc);

alter table concierge.avisos enable row level security;

-- ------------------------------------------------------------
-- Os quatro avisos que estavam no código do app
-- ------------------------------------------------------------
-- Mesmo texto, mesmo horário, mesma chave: a migração não muda o que a
-- pessoa vê — muda de onde vem.
--
-- A situação de cada um segue o que o app já mostrava: os dois de
-- preparação estão no ar; os dois do dia do evento ficam agendados e
-- entram sozinhos quando o horário chegar.

insert into concierge.avisos (chave, icone, titulo, subtitulo, descricao, disparo_em, situacao)
values
  ('traducao', 'fone', 'Tradução simultânea',
   'Leve um documento físico para retirar o fone',
   'As sessões em inglês têm tradução simultânea. O fone é retirado no balcão da arena, e fica um documento físico com foto como garantia — RG ou CNH. Cartão do celular não vale. Devolvendo o fone, você pega o documento de volta.',
   ('2026-09-15 18:00')::timestamp at time zone 'America/Sao_Paulo', 'no-ar'),

  ('sala', 'lugar', 'Masterclass mudou de sala',
   'Amy Edmondson, agora na Sala Estratégica.',
   'A masterclass de Amy Edmondson saiu da Arena Mind e passou para a Sala Estratégica. O horário não mudou. Se você tinha reserva, ela continua válida — é só ir para a sala nova.',
   ('2026-09-16 09:02')::timestamp at time zone 'America/Sao_Paulo', 'agendado'),

  ('abertura', 'sino', 'Abertura às 9h',
   'Chegue às 8h30 para entrar sem pressa.',
   'O segundo dia abre às 9h, na Arena Mind. O credenciamento começa às 8h; chegando às 8h30 você entra sem fila e ainda pega lugar.',
   ('2026-09-16 20:00')::timestamp at time zone 'America/Sao_Paulo', 'agendado')
on conflict (chave) do nothing;

-- Este tem tutorial do outro lado: o botão abre o roteiro do ingresso.
insert into concierge.avisos
  (chave, icone, titulo, subtitulo, descricao, disparo_em, situacao, ver_no_app, botao_ver_no_app)
values
  ('ingresso', 'ingresso', 'Seu ingresso está aqui',
   'Acesse agora e evite procurar na entrada',
   'Seu ingresso é o QR Code do app. Ele fica na aba <b>QR Code</b>, na barra de baixo — abra antes de chegar na fila e apresente na entrada. O mesmo código serve para trocar contato com quem você conhecer.',
   ('2026-09-15 17:30')::timestamp at time zone 'America/Sao_Paulo', 'no-ar',
   'ingresso', 'Ver onde fica no app')
on conflict (chave) do nothing;
