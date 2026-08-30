-- ============================================================
-- Passo 12B.1A — foundation tables + seeds
-- ============================================================
-- Escopo congelado (issue #24, desenho fechado na #23):
-- criar SOMENTE as duas tabelas de fundação do 12B e seus seeds.
-- Sem providers, sem loader, sem Gate, sem funções.
--
--   1. summit_2026.experiencias — mirror local das três experiências
--      do Summit 2026 e do que cada uma inclui.
--   2. agentes.kit_blocos — registry textual de quais blocos cada
--      rota monta e qual provider os serve. Os providers ainda NÃO
--      existem; aqui eles são config, não dependência.
-- ============================================================

create schema if not exists summit_2026;
create schema if not exists agentes;

-- ------------------------------------------------------------
-- 1. summit_2026.experiencias
-- ------------------------------------------------------------
-- Sem `ativo`, sem preço e sem checkout: preço/lote/checkout têm dono
-- próprio na camada comercial. Aqui vive só o que a experiência é e o
-- que ela inclui.
-- ------------------------------------------------------------
create table if not exists summit_2026.experiencias (
  chave text primary key,
  nome text not null,
  ordem smallint not null,
  inclusoes jsonb not null,
  sincronizado_em timestamptz not null default now()
);

comment on table summit_2026.experiencias is
  'Experiências do Mind Summit 2026 e suas inclusões. Cadeia de verdade: design/Mind Summit 2026 VF Mobile.dc.html = SOURCE congelada; Mind-Institute/mindsummit2026/src/data/compare.json = mirror estruturado vivo; esta tabela = mirror local do mind-agent.';

comment on column summit_2026.experiencias.chave is
  'Identificador estável da experiência (mind, vip, prime).';
comment on column summit_2026.experiencias.ordem is
  'Ordem de apresentação, do mais básico ao mais completo.';
comment on column summit_2026.experiencias.inclusoes is
  'Comparativo do que a experiência inclui, em grupos de itens com valor. Copy espelhada da SOURCE; o agrupamento é estrutural.';
comment on column summit_2026.experiencias.sincronizado_em is
  'Quando este mirror local foi alinhado com a SOURCE.';

-- Seed idempotente: exatamente três linhas.
insert into summit_2026.experiencias (chave, nome, ordem, inclusoes) values
(
  'mind', 'Mind', 1,
  '{
    "grupos": [
      {
        "grupo": "acesso",
        "itens": [
          {"item": "Painéis e palestras Arena Mind", "valor": "✓"},
          {"item": "Arena Top Voice e Arena Sextante", "valor": "Limitado por agendamento"},
          {"item": "Dois dias de evento", "valor": "✓"},
          {"item": "Assento Arena Mind", "valor": "Área Mind"}
        ]
      },
      {
        "grupo": "experiencias_exclusivas",
        "itens": [
          {"item": "Workshops VIP de 2 horas", "valor": "—"},
          {"item": "Masterclasses Prime de 90 min", "valor": "—"},
          {"item": "Prime Lounge", "valor": "—"}
        ]
      },
      {
        "grupo": "autografos",
        "itens": [
          {"item": "Autógrafos com Legends internacionais", "valor": "—"},
          {"item": "Autógrafos com demais autores", "valor": "✓"}
        ]
      },
      {
        "grupo": "credenciamento",
        "itens": [
          {"item": "Credenciamento antecipado", "valor": "—"},
          {"item": "Check-in exclusivo", "valor": "—"}
        ]
      },
      {
        "grupo": "certificados",
        "itens": [
          {"item": "Certificado de participação", "valor": "✓"},
          {"item": "Certificado dos workshops VIP", "valor": "—"},
          {"item": "Certificado executivo (Legends)", "valor": "—"}
        ]
      },
      {
        "grupo": "gravacoes",
        "itens": [
          {"item": "Gravações por 90 dias", "valor": "—"}
        ]
      }
    ]
  }'::jsonb
),
(
  'vip', 'VIP', 2,
  '{
    "grupos": [
      {
        "grupo": "acesso",
        "itens": [
          {"item": "Painéis e palestras Arena Mind", "valor": "✓"},
          {"item": "Arena Top Voice e Arena Sextante", "valor": "Limitado por agendamento"},
          {"item": "Dois dias de evento", "valor": "✓"},
          {"item": "Assento Arena Mind", "valor": "Área VIP"}
        ]
      },
      {
        "grupo": "experiencias_exclusivas",
        "itens": [
          {"item": "Workshops VIP de 2 horas", "valor": "4 à sua escolha"},
          {"item": "Masterclasses Prime de 90 min", "valor": "—"},
          {"item": "Prime Lounge", "valor": "—"}
        ]
      },
      {
        "grupo": "autografos",
        "itens": [
          {"item": "Autógrafos com Legends internacionais", "valor": "—"},
          {"item": "Autógrafos com demais autores", "valor": "✓"}
        ]
      },
      {
        "grupo": "credenciamento",
        "itens": [
          {"item": "Credenciamento antecipado", "valor": "✓"},
          {"item": "Check-in exclusivo", "valor": "—"}
        ]
      },
      {
        "grupo": "certificados",
        "itens": [
          {"item": "Certificado de participação", "valor": "✓"},
          {"item": "Certificado dos workshops VIP", "valor": "✓"},
          {"item": "Certificado executivo (Legends)", "valor": "—"}
        ]
      },
      {
        "grupo": "gravacoes",
        "itens": [
          {"item": "Gravações por 90 dias", "valor": "Arenas"}
        ]
      }
    ]
  }'::jsonb
),
(
  'prime', 'Prime', 3,
  '{
    "grupos": [
      {
        "grupo": "acesso",
        "itens": [
          {"item": "Painéis e palestras Arena Mind", "valor": "✓"},
          {"item": "Arena Top Voice e Arena Sextante", "valor": "Limitado por agendamento"},
          {"item": "Dois dias de evento", "valor": "✓"},
          {"item": "Assento Arena Mind", "valor": "Primeiras filas"}
        ]
      },
      {
        "grupo": "experiencias_exclusivas",
        "itens": [
          {"item": "Workshops VIP de 2 horas", "valor": "4 à sua escolha"},
          {"item": "Masterclasses Prime de 90 min", "valor": "Até 4"},
          {"item": "Prime Lounge", "valor": "✓"}
        ]
      },
      {
        "grupo": "autografos",
        "itens": [
          {"item": "Autógrafos com Legends internacionais", "valor": "✓"},
          {"item": "Autógrafos com demais autores", "valor": "✓"}
        ]
      },
      {
        "grupo": "credenciamento",
        "itens": [
          {"item": "Credenciamento antecipado", "valor": "✓"},
          {"item": "Check-in exclusivo", "valor": "✓"}
        ]
      },
      {
        "grupo": "certificados",
        "itens": [
          {"item": "Certificado de participação", "valor": "✓"},
          {"item": "Certificado dos workshops VIP", "valor": "✓"},
          {"item": "Certificado executivo (Legends)", "valor": "✓"}
        ]
      },
      {
        "grupo": "gravacoes",
        "itens": [
          {"item": "Gravações por 90 dias", "valor": "Arenas + Prime"}
        ]
      }
    ]
  }'::jsonb
)
on conflict (chave) do update set
  nome = excluded.nome,
  ordem = excluded.ordem,
  inclusoes = excluded.inclusoes,
  sincronizado_em = now();

-- ------------------------------------------------------------
-- 2. agentes.kit_blocos
-- ------------------------------------------------------------
-- Registry declarativo: qual rota monta qual bloco, servido por qual
-- provider, em qual seção do kit. `provider` é config textual — as
-- funções ainda não existem neste passo, então não há FK nem
-- dependência de criação.
-- ------------------------------------------------------------
create table if not exists agentes.kit_blocos (
  rota text not null,
  bloco text not null,
  provider text not null,
  secao text not null,
  obrigatorio boolean not null default false,
  ativo boolean not null default true,

  primary key (rota, bloco),

  constraint kit_blocos_rota_canonica check (
    rota in (
      'summit_b2c',
      'summit_b2b',
      'institute',
      'dash',
      'cliente_suporte',
      'concierge_summit'
    )
  ),
  constraint kit_blocos_secao_valida check (
    secao in ('structured', 'knowledge', 'tools')
  )
);

comment on table agentes.kit_blocos is
  'Registry de composição do kit por rota: qual bloco entra, qual provider o serve e em que seção. Provider é config textual, resolvida em runtime; a tabela não depende da existência da função.';
comment on column agentes.kit_blocos.rota is
  'Uma das seis rotas canônicas do router universal.';
comment on column agentes.kit_blocos.bloco is
  'Nome do bloco dentro da seção do kit.';
comment on column agentes.kit_blocos.provider is
  'Nome qualificado da função que serve o bloco. Config textual — pode ainda não existir.';
comment on column agentes.kit_blocos.obrigatorio is
  'Bloco obrigatório: sua ausência é falha de montagem do kit, não omissão silenciosa.';

-- Superfície fechada: nenhum papel do PostgREST enxerga a tabela.
-- Acesso só server-side, no padrão atual do projeto.
alter table agentes.kit_blocos enable row level security;
revoke all on table agentes.kit_blocos from anon, authenticated;

-- Seed idempotente do registry.
insert into agentes.kit_blocos (rota, bloco, provider, secao, obrigatorio, ativo) values
  ('summit_b2c', 'evento',            'public.mind_kit_evento',            'structured', true, true),
  ('summit_b2c', 'ofertas',           'public.mind_kit_ofertas',           'structured', true, true),
  ('summit_b2c', 'regras_comerciais', 'public.mind_kit_regras_comerciais', 'structured', true, true),
  ('summit_b2c', 'inclusoes',         'public.mind_kit_inclusoes',         'structured', true, true),

  ('summit_b2b', 'evento',            'public.mind_kit_evento',             'structured', true, true),
  ('summit_b2b', 'ofertas',           'public.mind_kit_ofertas',            'structured', true, true),
  ('summit_b2b', 'regras_comerciais', 'public.mind_kit_regras_comerciais',  'structured', true, true),
  ('summit_b2b', 'inclusoes',         'public.mind_kit_inclusoes',          'structured', true, true),
  ('summit_b2b', 'precos_por_volume', 'public.mind_kit_precos_por_volume',  'structured', true, true)
on conflict (rota, bloco) do update set
  provider = excluded.provider,
  secao = excluded.secao,
  obrigatorio = excluded.obrigatorio,
  ativo = excluded.ativo;
