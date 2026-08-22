-- De onde o lead entrou. Um registro por BOTÃO de entrada, porque o botão
-- decide três coisas ao mesmo tempo (Adriana, 22/08):
--   1. o campo oculto que o formulário grava no HubSpot
--   2. a mensagem com que o bot abre a conversa
--   3. a origem que carimba os links (utm_source = site, utm_content = botão)
create table mind.origens (
  codigo text primary key,
  site text not null check (site in ('mindsummit','institute','dash','outro')),
  botao_rotulo text,
  descricao text,
  mensagem_abertura text,
  hubspot_campo text,
  hubspot_valor text,
  audiencia_sugerida text
    check (audiencia_sugerida in ('b2c','b2b','cliente_suporte','ja_comprou','desconhecido')),
  ativo boolean not null default true,
  atualizado_em timestamptz not null default now()
);
alter table mind.origens enable row level security;

comment on table mind.origens is
  'Pontos de entrada (botões) por site. Decide a mensagem de abertura do bot, o campo oculto gravado no HubSpot e a origem carimbada nos links.';
comment on column mind.origens.mensagem_abertura is
  'O que o bot fala primeiro quando a pessoa chega por este botão. Vazio = abertura padrão do playbook de descoberta.';
comment on column mind.origens.audiencia_sugerida is
  'Palpite inicial de audiência a partir do botão (ex.: botão "para minha empresa" → b2b). É palpite: a conversa pode corrigir.';

-- Link com UTM: source = site de origem, medium = canal, content = botão
create or replace function public.mind_material_link(
  p_url text, p_codigo text, p_utm_campaign text, p_canal text, p_origem text default null
) returns text
language sql stable security definer set search_path = public, mind
as $$
  select p_url
      || case when position('?' in p_url) > 0 then '&' else '?' end
      || 'utm_source=' || coalesce(
            (select o.site from mind.origens o where o.codigo = p_origem), 'mind')
      || '&utm_medium=' || case p_canal
            when 'whatsapp_treble' then 'chatbot'
            when 'site_concierge'  then 'chatbot_concierge'
            else p_canal end
      || '&utm_campaign=' || coalesce(nullif(p_utm_campaign,''), p_codigo)
      || '&utm_content=' || coalesce(nullif(p_origem,''), 'sem_origem');
$$;

create or replace function public.mind_materiais_para(
  p_canal text default 'whatsapp_treble',
  p_audiencia text default 'desconhecido',
  p_icp text default null,
  p_origem text default null
) returns jsonb
language sql security definer set search_path = public, mind
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'titulo', m.titulo, 'tipo', m.tipo,
           'sobre_o_que_e', m.conteudo_resumo,
           'quando_usar', m.quando_usar,
           'objecoes_que_quebra', m.objecoes_que_quebra,
           'link', public.mind_material_link(m.url, m.codigo, m.utm_campaign, p_canal, p_origem)
         ) order by m.ordem), '[]'::jsonb)
  from mind.materiais m
  where m.ativo
    and (coalesce(p_audiencia,'desconhecido') = any(m.audiencias))
    and (cardinality(m.icp) = 0 or p_icp is null or p_icp = any(m.icp));
$$;
revoke all on function public.mind_materiais_para(text, text, text, text) from public, anon, authenticated;

-- A conversa passa a registrar por onde a pessoa entrou
alter table treble.conversations
  add column if not exists origem_codigo text references mind.origens(codigo);
