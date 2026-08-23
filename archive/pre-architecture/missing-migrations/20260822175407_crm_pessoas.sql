-- ============================================================
-- crm.pessoas — espelho de pessoas do HubSpot para todos os bots
-- ============================================================
-- Camada de PESSOA (dado individual), distinta dos clusters de
-- conhecimento (conteúdo editorial). Todos os agentes usam: concierge
-- para saber quem chegou, vendas para qualificar, pós-venda para
-- atender. O HubSpot é a fonte da verdade; aqui é espelho de leitura.
--
-- Campos escolhidos por taxa de preenchimento real (11.536 contatos):
-- firstname 99,1% · lastname 95,3% · email 92,2% · whatsapp 58,3% ·
-- cargo 47,3% · empresa 40,6%. Descartados: mobilephone (5,6%),
-- produto_de_interesse (0%), eduzz_buyer_id (0,2%) e o lifetime de
-- ingressos (incoerente na origem — calculamos do nosso lado).
--
-- Campos sensíveis (UTM, NPS, score, dono do negócio) NÃO entram aqui:
-- vão para crm.pessoas_interno, para que a função que serve bots
-- voltados ao cliente não tenha como alcançá-los.

create schema if not exists crm;

create table if not exists crm.pessoas (
  id uuid primary key default gen_random_uuid(),

  -- Identificação. E-mail é a chave preferida (o Yazo entrega e-mail ao
  -- concierge), mas 7,8% dos contatos não têm — daí WhatsApp como chave
  -- alternativa, que é por onde o Treble conhece a pessoa.
  email text unique,
  whatsapp text,

  primeiro_nome text,
  sobrenome text,
  empresa text,
  cargo text,

  -- Estágio no funil: 100% preenchido na origem. Orienta o tom do bot
  -- (lead x cliente); não é para ser recitado ao usuário.
  estagio text,

  -- Rastreabilidade do espelho.
  hubspot_id text unique,
  origem text not null default 'hubspot'
    check (origem in ('hubspot', 'bot', 'manual')),
  sincronizado_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),

  -- Sem e-mail e sem WhatsApp não há como reencontrar a pessoa:
  -- registro assim é ruído, não cadastro.
  constraint pessoas_tem_chave check (email is not null or whatsapp is not null)
);

comment on table crm.pessoas is
  'Espelho de leitura das pessoas do HubSpot, para todos os agentes. Fonte da verdade é o HubSpot; escrita local só pelo sincronizador. Campos internos ficam em crm.pessoas_interno.';
comment on column crm.pessoas.email is 'Chave principal, sempre normalizada em minúsculas pelo gatilho.';
comment on column crm.pessoas.whatsapp is 'Chave alternativa em E.164 (só dígitos com DDI). Cobre quem não tem e-mail no CRM.';
comment on column crm.pessoas.estagio is 'Estágio do funil no HubSpot (lead, customer...). Orienta o comportamento do bot; não é conteúdo para o usuário.';

create index if not exists pessoas_whatsapp_idx on crm.pessoas (whatsapp) where whatsapp is not null;
create index if not exists pessoas_empresa_idx on crm.pessoas (lower(empresa)) where empresa is not null;

-- ------------------------------------------------------------
-- Normalização na entrada: e-mail minúsculo/aparado e WhatsApp só
-- dígitos. Sem isso, "Maria@X.com" e "maria@x.com" viram duas pessoas.
-- ------------------------------------------------------------
create or replace function crm.normalizar_pessoa()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'crm'
as $$
begin
  new.email := nullif(lower(btrim(coalesce(new.email, ''))), '');
  new.whatsapp := nullif(regexp_replace(coalesce(new.whatsapp, ''), '[^0-9]', '', 'g'), '');
  -- Número brasileiro digitado sem DDI: 11 dígitos (DDD + 9 + número).
  if new.whatsapp is not null and length(new.whatsapp) between 10 and 11 then
    new.whatsapp := '55' || new.whatsapp;
  end if;
  new.atualizado_em := now();
  return new;
end;
$$;

drop trigger if exists pessoas_normalizar on crm.pessoas;
create trigger pessoas_normalizar
  before insert or update on crm.pessoas
  for each row execute function crm.normalizar_pessoa();

-- ------------------------------------------------------------
-- Produtos adquiridos — tabela própria, não colunas por produto.
-- Hoje só o Summit tem dado real na origem (Journey, Institute,
-- Formações e Certificação estão 100% vazios no HubSpot); a estrutura
-- já aceita os outros sem migração quando começarem a ser preenchidos.
-- ------------------------------------------------------------
create table if not exists crm.pessoa_produtos (
  id uuid primary key default gen_random_uuid(),
  pessoa_id uuid not null references crm.pessoas(id) on delete cascade,

  produto text not null,          -- 'summit', 'journey', 'institute', 'formacao', 'certificacao'
  edicao text,                    -- '2026', '2025'... quando o produto tem edições
  categoria text,                 -- Mind, VIP, Prime (categoria do ingresso)
  tipo_entrada text,              -- pago, cortesia, bônus, patrocínio
  papel text,                     -- pagante, participante (podem coexistir)
  quantidade integer check (quantidade is null or quantidade >= 0),

  sincronizado_em timestamptz,
  criado_em timestamptz not null default now(),

  unique (pessoa_id, produto, edicao)
);

comment on table crm.pessoa_produtos is
  'O que cada pessoa já adquiriu, um registro por produto/edição. Conversável: a pessoa pode perguntar sobre a própria compra.';

create index if not exists pessoa_produtos_pessoa_idx on crm.pessoa_produtos (pessoa_id);
create index if not exists pessoa_produtos_produto_idx on crm.pessoa_produtos (produto, edicao);

-- ------------------------------------------------------------
-- Caixa de saída: lead que o bot conheceu e o CRM ainda não.
-- O bot nunca escreve direto em crm.pessoas — evita duas verdades.
-- O ciclo é HubSpot -> espelho -> bots -> caixa de saída -> HubSpot.
-- ------------------------------------------------------------
create table if not exists crm.leads_capturados (
  id uuid primary key default gen_random_uuid(),
  email text,
  whatsapp text,
  primeiro_nome text,
  sobrenome text,
  empresa text,
  cargo text,

  agente text not null,           -- quem coletou: concierge, treble, vendas
  contexto jsonb not null default '{}'::jsonb,

  estado text not null default 'pendente'
    check (estado in ('pendente', 'enviado', 'erro', 'descartado')),
  enviado_em timestamptz,
  erro text,
  criado_em timestamptz not null default now(),

  constraint leads_tem_chave check (email is not null or whatsapp is not null)
);

comment on table crm.leads_capturados is
  'Fila de leads coletados pelos bots, a caminho do HubSpot. Escrita dos bots para aqui; nunca direto no espelho.';

create index if not exists leads_pendentes_idx on crm.leads_capturados (criado_em) where estado = 'pendente';

-- ------------------------------------------------------------
-- Fechado por padrão: nenhum papel do PostgREST enxerga estas tabelas.
-- O acesso é só por função SECURITY DEFINER, que audita quem viu o quê.
-- ------------------------------------------------------------
alter table crm.pessoas enable row level security;
alter table crm.pessoa_produtos enable row level security;
alter table crm.leads_capturados enable row level security;

revoke all on all tables in schema crm from anon, authenticated;
