-- Materiais: prateleira compartilhada por TODOS os agentes (bot do
-- WhatsApp, concierge do site, futuros). Cada agente pega o link já com
-- o UTM do seu canal, para medir separado.
alter table mind.materiais
  add column if not exists conteudo_resumo text,      -- do que trata, em 2-3 linhas (vai no contexto do agente)
  add column if not exists transcricao text,          -- transcrição completa (para busca/RAG, não vai no contexto)
  add column if not exists objecoes_que_quebra text[] default '{}',
  add column if not exists icp text[] default '{}',   -- códigos de mind.taxonomy (rh, lideranca, c_level, saude_ocupacional, dei, financeiro); vazio = serve a todos
  add column if not exists duracao_segundos integer,
  add column if not exists utm_campaign text;

comment on column mind.materiais.conteudo_resumo is 'Do que o material trata, em 2-3 linhas. É isto que o agente lê para decidir se cabe.';
comment on column mind.materiais.transcricao is 'Transcrição completa. Fica fora do contexto do agente (tamanho); serve para busca e para virar documento de conhecimento.';
comment on column mind.materiais.objecoes_que_quebra is 'Objeções que este material ajuda a derrubar: preco, vale_a_pena, timing, empresa_paga, ceticismo, comparacao.';
comment on column mind.materiais.icp is 'Perfis a quem serve (códigos de mind.taxonomy). Vazio = serve a todos.';
comment on column mind.materiais.utm_campaign is 'Campanha para o UTM. Se vazio, usa o código do material.';

-- Link com UTM do canal que está entregando (o mesmo material rende
-- links diferentes no WhatsApp e no site — dá para medir separado).
create or replace function public.mind_material_link(
  p_url text, p_codigo text, p_utm_campaign text, p_canal text
) returns text
language sql immutable
as $$
  select p_url
      || case when position('?' in p_url) > 0 then '&' else '?' end
      || 'utm_source=' || case p_canal
            when 'whatsapp_treble' then 'whatsapp'
            when 'site_concierge'  then 'site'
            else 'mind' end
      || '&utm_medium=' || case p_canal
            when 'whatsapp_treble' then 'chatbot_whatsapp'
            when 'site_concierge'  then 'chatbot_site'
            else p_canal end
      || '&utm_campaign=' || coalesce(nullif(p_utm_campaign,''), p_codigo)
      || '&utm_content=agente';
$$;

-- Seleção para um agente: filtra por audiência e (opcionalmente) ICP,
-- devolve resumo, objeções e o link já carimbado com o UTM do canal.
create or replace function public.mind_materiais_para(
  p_canal text default 'whatsapp_treble',
  p_audiencia text default 'desconhecido',
  p_icp text default null
) returns jsonb
language sql security definer set search_path = public, mind
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'titulo', m.titulo,
           'tipo', m.tipo,
           'sobre_o_que_e', m.conteudo_resumo,
           'quando_usar', m.quando_usar,
           'objecoes_que_quebra', m.objecoes_que_quebra,
           'link', public.mind_material_link(m.url, m.codigo, m.utm_campaign, p_canal)
         ) order by m.ordem), '[]'::jsonb)
  from mind.materiais m
  where m.ativo
    and (coalesce(p_audiencia,'desconhecido') = any(m.audiencias))
    and (cardinality(m.icp) = 0 or p_icp is null or p_icp = any(m.icp));
$$;
revoke all on function public.mind_materiais_para(text, text, text) from public, anon, authenticated;

-- O agente do WhatsApp passa a usar a seleção com UTM do seu canal
create or replace function public.treble_materiais(p_audience text default 'desconhecido')
returns jsonb
language sql security definer set search_path = public, mind
as $$ select public.mind_materiais_para('whatsapp_treble', p_audience, null) $$;
