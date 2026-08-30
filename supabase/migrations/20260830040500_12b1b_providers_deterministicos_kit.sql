-- ============================================================
-- Passo 12B.1B — providers determinísticos do primeiro Kit
-- ============================================================
-- Escopo congelado (issue #29, desenho fechado na #23):
-- criar SOMENTE os cinco providers já declarados como config em
-- `agentes.kit_blocos` (migration 20260830024500).
--
--   public.mind_kit_evento
--   public.mind_kit_ofertas
--   public.mind_kit_regras_comerciais
--   public.mind_kit_inclusoes
--   public.mind_kit_precos_por_volume
--
-- Contrato comum, igual nos cinco:
--   (p_conversa_id uuid, p_necessidade jsonb) → jsonb
--   sem LLM · sem escrita · determinístico · STABLE · SECURITY DEFINER
--   com search_path explícito e EXECUTE só para service_role.
--
-- `p_necessidade` entra na assinatura e ainda não é lida: o planner de
-- retrieval é decisão posterior e não se inventa aqui. Ter o parâmetro
-- desde já mantém a assinatura estável quando ele passar a valer.
--
-- Nada aqui traduz fato em comportamento do agente: estes providers são
-- Intelligence factual. Decisioning é outra camada e outro passo — por
-- isso o evento não reaproveita a orientação prescritiva de
-- `mind_calendario.o_que_fazer`, e as regras comerciais saem como estão
-- na fonte.
-- ============================================================

-- ------------------------------------------------------------
-- 1. mind_kit_evento
-- ------------------------------------------------------------
-- Duas verdades factuais e nada além: o que o evento É
-- (`summit_2026.events`) e se o produto correspondente é vendável hoje
-- (`catalogo.produtos.ativo` / `vende`). O produto é alcançado por
-- `schema_dados`, que é exatamente o campo que liga produto ao schema
-- onde vive a Intelligence dele.
-- ------------------------------------------------------------
create or replace function public.mind_kit_evento(
  p_conversa_id uuid default null,
  p_necessidade jsonb default null
) returns jsonb
language sql
stable
security definer
set search_path = public, summit_2026, catalogo
as $fn$
  with evento as (
    select e.*
    from summit_2026.events e
    where e.ativo
    order by e.slug
    limit 1
  ), produto as (
    select p.*
    from catalogo.produtos p
    where p.schema_dados = 'summit_2026'
    order by p.codigo
    limit 1
  )
  select jsonb_build_object(
    'bloco', 'evento',
    'evento', (select to_jsonb(e) - 'id' from evento e),
    'produto', (
      select jsonb_build_object(
        'codigo', p.codigo,
        'nome', p.nome,
        'tipo', p.tipo,
        'vertical', p.vertical,
        'ativo', p.ativo,
        'vende', p.vende)
      from produto p)
  );
$fn$;

revoke all on function public.mind_kit_evento(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.mind_kit_evento(uuid, jsonb) to service_role;

comment on function public.mind_kit_evento(uuid, jsonb) is
  'Bloco factual do Kit: o que o evento é (summit_2026.events) e se o produto é vendável agora (catalogo.produtos.ativo/vende). Sem LLM, sem escrita, sem orientação de comportamento.';

-- ------------------------------------------------------------
-- 2. mind_kit_ofertas
-- ------------------------------------------------------------
-- Realidade comercial corrente: oferta ativa, pública e dentro da
-- janela de validade — o mesmo predicado de vigência que os leitores
-- vivos já aplicam.
--
-- O checkout sai assinado por `public.mind_checkout_url`, a função que
-- já monta a atribuição do sistema. Com conversa, a assinatura leva a
-- UTM e a origem daquela conversa; sem conversa, a função devolve a
-- atribuição padrão dela e o bloco continua respondendo a realidade das
-- ofertas. Conversa não é exigência para saber o preço.
-- ------------------------------------------------------------
create or replace function public.mind_kit_ofertas(
  p_conversa_id uuid default null,
  p_necessidade jsonb default null
) returns jsonb
language sql
stable
security definer
set search_path = public, summit_2026, engagement
as $fn$
  with conversa as (
    select c.id, c.origem_codigo, c.utm
    from engagement.conversas c
    where p_conversa_id is not null
      and c.id = p_conversa_id
  ), evento as (
    select e.id from summit_2026.events e where e.ativo
  ), vigentes as (
    select o.*
    from summit_2026.offers o
    where o.ativo
      and o.publico
      and (o.event_id is null or o.event_id in (select id from evento))
      and (o.inicia_em is null or o.inicia_em <= now())
      and (o.encerra_em is null or o.encerra_em > now())
  )
  select jsonb_build_object(
    'bloco', 'ofertas',
    'conversa_id', p_conversa_id,
    'atribuicao_da_conversa', exists (select 1 from conversa),
    'ofertas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'codigo', v.codigo,
        'nome', v.nome,
        'descricao', v.descricao,
        'moeda', v.moeda,
        'valor', v.valor,
        'condicoes_pagamento', v.condicoes_pagamento,
        'janela', jsonb_build_object(
          'inicia_em', v.inicia_em,
          'lote_termina_em', v.encerra_em),
        'procura', v.procura,
        'procura_nota', v.procura_nota,
        'elegibilidade', v.elegibilidade,
        'categoria', v.elegibilidade->>'categoria',
        'grupo', v.elegibilidade ? 'grupo',
        'checkout_url', public.mind_checkout_url(
          v.checkout_url,
          (select c.utm from conversa c),
          (select c.origem_codigo from conversa c),
          (select c.id::text from conversa c))
      ) order by v.valor nulls last, v.codigo)
      from vigentes v), '[]'::jsonb)
  );
$fn$;

revoke all on function public.mind_kit_ofertas(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.mind_kit_ofertas(uuid, jsonb) to service_role;

comment on function public.mind_kit_ofertas(uuid, jsonb) is
  'Bloco factual do Kit: ofertas Summit ativas, públicas e vigentes, com preço, moeda, condições, janela/lote, procura, elegibilidade/categoria e checkout assinado por mind_checkout_url. Conversa nula não impede a resposta.';

-- ------------------------------------------------------------
-- 3. mind_kit_regras_comerciais
-- ------------------------------------------------------------
-- As regras saem como estão em `summit_2026.commercial_rules`. Nenhuma
-- regra inventada, nenhuma tradução para o que o agente deve fazer com
-- ela — isso é Decisioning.
-- ------------------------------------------------------------
create or replace function public.mind_kit_regras_comerciais(
  p_conversa_id uuid default null,
  p_necessidade jsonb default null
) returns jsonb
language sql
stable
security definer
set search_path = public, summit_2026
as $fn$
  select jsonb_build_object(
    'bloco', 'regras_comerciais',
    'regras', coalesce((
      select jsonb_agg(jsonb_build_object(
        'chave', r.chave,
        'descricao', r.descricao,
        'config', r.config) order by r.chave)
      from summit_2026.commercial_rules r
      where r.ativo), '[]'::jsonb)
  );
$fn$;

revoke all on function public.mind_kit_regras_comerciais(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.mind_kit_regras_comerciais(uuid, jsonb) to service_role;

comment on function public.mind_kit_regras_comerciais(uuid, jsonb) is
  'Bloco factual do Kit: regras comerciais ativas do Summit, como estão em summit_2026.commercial_rules. Sem regra inventada e sem tradução para comportamento do agente.';

-- ------------------------------------------------------------
-- 4. mind_kit_inclusoes
-- ------------------------------------------------------------
-- O que cada experiência inclui (`summit_2026.experiencias`, criada no
-- 12B.1A) alinhado com a oferta vigente da mesma categoria — o vínculo
-- é a categoria que já existe em `offers.elegibilidade->>'categoria'`
-- (`mind|vip|prime`). Nenhuma chave nova de correspondência é criada.
--
-- Oferta de grupo fica fora do alinhamento: ela é condição comercial de
-- volume sobre uma categoria existente, não uma quarta experiência.
-- ------------------------------------------------------------
create or replace function public.mind_kit_inclusoes(
  p_conversa_id uuid default null,
  p_necessidade jsonb default null
) returns jsonb
language sql
stable
security definer
set search_path = public, summit_2026
as $fn$
  with evento as (
    select e.id from summit_2026.events e where e.ativo
  ), vigentes as (
    select o.*
    from summit_2026.offers o
    where o.ativo
      and o.publico
      and (o.event_id is null or o.event_id in (select id from evento))
      and (o.inicia_em is null or o.inicia_em <= now())
      and (o.encerra_em is null or o.encerra_em > now())
      and not (o.elegibilidade ? 'grupo')
  )
  select jsonb_build_object(
    'bloco', 'inclusoes',
    'experiencias', coalesce((
      select jsonb_agg(jsonb_build_object(
        'chave', x.chave,
        'nome', x.nome,
        'ordem', x.ordem,
        'inclusoes', x.inclusoes,
        'ofertas_vigentes', coalesce((
          select jsonb_agg(jsonb_build_object(
            'codigo', v.codigo,
            'nome', v.nome,
            'moeda', v.moeda,
            'valor', v.valor,
            'lote_termina_em', v.encerra_em) order by v.valor nulls last, v.codigo)
          from vigentes v
          where v.elegibilidade->>'categoria' = x.chave), '[]'::jsonb)
      ) order by x.ordem)
      from summit_2026.experiencias x), '[]'::jsonb)
  );
$fn$;

revoke all on function public.mind_kit_inclusoes(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.mind_kit_inclusoes(uuid, jsonb) to service_role;

comment on function public.mind_kit_inclusoes(uuid, jsonb) is
  'Bloco factual do Kit: o que cada experiência do Summit inclui (summit_2026.experiencias), alinhado com as ofertas vigentes da mesma categoria (offers.elegibilidade->>categoria). Oferta de grupo não cria tier novo.';

-- ------------------------------------------------------------
-- 5. mind_kit_precos_por_volume
-- ------------------------------------------------------------
-- Wrapper. O cálculo já existe em `public.mind_precos_por_volume()` e
-- não se reimplementa aqui: haveria duas contas de desconto por volume
-- no sistema, e a segunda seria a errada no dia em que a primeira
-- mudasse. Este provider só dá ao cálculo a assinatura do Kit.
-- ------------------------------------------------------------
create or replace function public.mind_kit_precos_por_volume(
  p_conversa_id uuid default null,
  p_necessidade jsonb default null
) returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
  select jsonb_build_object(
    'bloco', 'precos_por_volume',
    'precos_por_volume', public.mind_precos_por_volume()
  );
$fn$;

revoke all on function public.mind_kit_precos_por_volume(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.mind_kit_precos_por_volume(uuid, jsonb) to service_role;

comment on function public.mind_kit_precos_por_volume(uuid, jsonb) is
  'Bloco factual do Kit: wrapper de public.mind_precos_por_volume() com a assinatura do Kit. O cálculo continua tendo um dono só.';
