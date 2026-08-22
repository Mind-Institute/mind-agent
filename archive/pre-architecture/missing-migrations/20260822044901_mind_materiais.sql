-- Materiais que o agente pode enviar no WhatsApp (vídeos, depoimentos,
-- páginas). Link em vez de arquivo: abre com preview, é leve para o lead
-- e permite medir clique. O agente escolhe pelo contexto — 'quando_usar'
-- é a instrução em linguagem natural que ele lê.
create table mind.materiais (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  titulo text not null,
  descricao text,
  tipo text not null default 'video'
    check (tipo in ('video','depoimento','pagina','pdf','outro')),
  url text not null,
  quando_usar text not null,
  audiencias text[] not null default array['b2c','b2b','desconhecido'],
  ativo boolean not null default true,
  ordem integer not null default 100,
  atualizado_em timestamptz not null default now()
);
alter table mind.materiais enable row level security;

comment on table mind.materiais is
  'Vídeos, depoimentos e páginas que o agente pode oferecer na conversa. quando_usar descreve o momento certo (ex.: "quando a pessoa está em dúvida se vale a pena"); audiencias limita a quem cabe.';
comment on column mind.materiais.quando_usar is
  'Instrução em linguagem natural lida pelo agente. Seja específica: "objeção de preço", "não sabe qual ingresso escolher", "empresa avaliando levar time".';

-- Entram no contexto de toda conversa (lista curta, o agente escolhe)
create or replace function public.treble_materiais(p_audience text default 'desconhecido')
returns jsonb
language sql security definer set search_path = public, mind
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'titulo', m.titulo, 'tipo', m.tipo, 'url', m.url,
           'quando_usar', m.quando_usar) order by m.ordem), '[]'::jsonb)
  from mind.materiais m
  where m.ativo
    and (coalesce(p_audience,'desconhecido') = any(m.audiencias));
$$;
revoke all on function public.treble_materiais(text) from public, anon, authenticated;
