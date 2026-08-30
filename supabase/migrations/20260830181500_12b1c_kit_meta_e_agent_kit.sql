-- ============================================================
-- Passo 12B.1C — semântica de disponibilidade + mind_kit_meta + mind_agent_kit
-- ------------------------------------------------------------
-- SEMÂNTICA UNIVERSAL DO PROVIDER (decisão congelada)
--
--   O provider retorna SQL NULL quando NÃO consegue entregar a verdade
--   mínima prometida pelo bloco. Payload JSON não-nulo = bloco disponível.
--
--   NULL não significa "o fato é false". Fato negativo é fato válido: se o
--   produto existe com `vende=false`, o bloco `evento` continua disponível e
--   o payload carrega `vende=false`. Isso não é bloco ausente.
--
--   A disponibilidade não pode depender de `p_conversa_id` nem de
--   `p_necessidade`. É por isso que `mind_kit_meta` pode avaliá-la chamando
--   os providers com (null, null) e ainda assim descrever o Kit que
--   `mind_agent_kit` vai montar com os argumentos reais.
--
--   Nada é acrescentado ao payload: sem `ok`, sem `disponivel`, sem
--   metadado. A ausência é expressa pelo próprio NULL, e o conhecimento de
--   "qual é a minha fonte essencial" continua dentro do provider — o único
--   componente que já o tem.
-- ============================================================


-- ============================================================
-- 1. Providers — mesma assinatura, mesmo payload, agora com a guarda de
--    disponibilidade. Quando disponível, o payload é byte a byte o de antes.
-- ============================================================

-- ------------------------------------------------------------
-- 1.1 mind_kit_evento
-- Verdade mínima: existe um evento ativo E existe o produto correspondente.
-- `ativo`/`vende` do produto NÃO entram na condição: são fatos que o agente
-- precisa enxergar, inclusive quando negativos.
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
  select case
    when not exists (select 1 from evento)  then null::jsonb
    when not exists (select 1 from produto) then null::jsonb
    else jsonb_build_object(
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
    )
  end;
$fn$;

comment on function public.mind_kit_evento(uuid, jsonb) is
  'Bloco factual do Kit: o que o evento é (summit_2026.events) e se o produto é vendável agora (catalogo.produtos.ativo/vende). NULL só quando não há evento ativo ou não há produto correspondente — vende=false é fato disponível, não ausência. Sem LLM, sem escrita, sem orientação de comportamento.';

-- ------------------------------------------------------------
-- 1.2 mind_kit_ofertas
-- Verdade mínima: existe ao menos uma oferta vigente pelo mesmo predicado
-- que o provider já usa. Conversa não participa da disponibilidade — ela só
-- assina o checkout.
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
  select case
    when not exists (select 1 from vigentes) then null::jsonb
    else jsonb_build_object(
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
    )
  end;
$fn$;

comment on function public.mind_kit_ofertas(uuid, jsonb) is
  'Bloco factual do Kit: ofertas Summit ativas, públicas e vigentes, com preço, moeda, condições, janela/lote, procura, elegibilidade/categoria e checkout assinado por mind_checkout_url. NULL só quando não há oferta vigente. Conversa nula não impede a resposta nem afeta a disponibilidade.';

-- ------------------------------------------------------------
-- 1.3 mind_kit_regras_comerciais
-- Verdade mínima: existe ao menos uma commercial_rule ativa.
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
  select case
    when not exists (select 1 from summit_2026.commercial_rules r where r.ativo) then null::jsonb
    else jsonb_build_object(
      'bloco', 'regras_comerciais',
      'regras', coalesce((
        select jsonb_agg(jsonb_build_object(
          'chave', r.chave,
          'descricao', r.descricao,
          'config', r.config) order by r.chave)
        from summit_2026.commercial_rules r
        where r.ativo), '[]'::jsonb)
    )
  end;
$fn$;

comment on function public.mind_kit_regras_comerciais(uuid, jsonb) is
  'Bloco factual do Kit: regras comerciais ativas do Summit, como estão em summit_2026.commercial_rules. NULL só quando não há nenhuma regra ativa. Sem regra inventada e sem tradução para comportamento do agente.';

-- ------------------------------------------------------------
-- 1.4 mind_kit_inclusoes
-- Verdade mínima: existe ao menos uma linha em summit_2026.experiencias.
-- A disponibilidade NÃO depende de existir oferta: sellability é do bloco
-- `ofertas`. Uma experiência sem oferta vigente continua sendo o fato "isto
-- é o que a experiência inclui", com `ofertas_vigentes` vazio.
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
  select case
    when not exists (select 1 from summit_2026.experiencias) then null::jsonb
    else jsonb_build_object(
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
    )
  end;
$fn$;

comment on function public.mind_kit_inclusoes(uuid, jsonb) is
  'Bloco factual do Kit: o que cada experiência do Summit inclui (summit_2026.experiencias), alinhado com as ofertas vigentes da mesma categoria (offers.elegibilidade->>categoria). NULL só quando não há nenhuma experiência — a existência de oferta não decide este bloco. Oferta de grupo não cria tier novo.';

-- ------------------------------------------------------------
-- 1.4b Volatilidade de public.mind_precos_por_volume()
-- O wrapper do bloco é STABLE e o cálculo é uma leitura pura; a função estava
-- marcada VOLATILE apenas por omissão do default. Só a volatilidade muda —
-- o corpo não é reescrito.
-- ------------------------------------------------------------
alter function public.mind_precos_por_volume() stable;


-- ------------------------------------------------------------
-- 1.5 mind_kit_precos_por_volume
-- Verdade mínima: `public.mind_precos_por_volume()` produz um array com ao
-- menos uma linha. A função devolve `[]` quando não há tier ativo ou não há
-- oferta com valor — nesse caso não há cálculo, e o bloco é ausente.
-- O cálculo continua tendo um dono só: não se reimplementa nada aqui.
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
  with calculo as (
    select public.mind_precos_por_volume() as v
  )
  select case
    when (select v from calculo) is null                            then null::jsonb
    when jsonb_typeof((select v from calculo)) <> 'array'           then null::jsonb
    when jsonb_array_length((select v from calculo)) = 0            then null::jsonb
    else jsonb_build_object(
      'bloco', 'precos_por_volume',
      'precos_por_volume', (select v from calculo))
  end;
$fn$;

comment on function public.mind_kit_precos_por_volume(uuid, jsonb) is
  'Bloco factual do Kit: wrapper de public.mind_precos_por_volume() com a assinatura do Kit. NULL só quando o cálculo não produz nenhuma linha. O cálculo continua tendo um dono só.';


-- ============================================================
-- 2. public.mind_kit_meta(p_rota) — a ÚNICA verdade de completude do Kit
-- ------------------------------------------------------------
-- Conhece registry + contrato universal do provider. NÃO conhece ofertas,
-- evento, regras, inclusões, preços, nem o schema físico de fonte alguma.
--
-- `pode_executar` não mora aqui: pertence ao Capability Gate
-- (public.mind_rota_capacidade), que lê esta verdade em vez de re-derivá-la.
--
-- EXECUÇÃO DINÂMICA SEGURA
--   O registry guarda texto (`public.mind_kit_ofertas`). Esse texto participa
--   APENAS da resolução por catálogo:
--     1. guarda de forma  — regex de identificador simples com um ponto. Sem
--        ela, `to_regprocedure` levanta 42601 em nome com pontos demais
--        ('a.b.c.d') e um registro malformado abortaria o Kit inteiro em vez
--        de virar bloco ausente. O CASE garante a avaliação preguiçosa.
--     2. to_regprocedure(...(uuid,jsonb)) — resolve pelo catálogo, fixa o
--        overload e devolve NULL para nome inexistente.
--     3. validação do contrato em pg_proc antes de qualquer execução.
--   O que é executado são schema e nome vindos de pg_catalog, nunca o texto
--   armazenado, e os argumentos vão por parâmetro com cast explícito.
-- ============================================================
create or replace function public.mind_kit_meta(p_rota text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, agentes
as $fn$
declare
  v_rota         text    := nullif(btrim(p_rota), '');
  v_configurado  boolean;
  v_obrigatorios text[]  := array[]::text[];
  v_ausentes     text[]  := array[]::text[];
  v_payload      jsonb;
  r              record;
begin
  -- Taxonomia canônica do Router. Fechada. Mesmo formato de erro de
  -- public.mind_rota_capacidade — nenhuma taxonomia nova.
  if v_rota is null or v_rota not in (
       'summit_b2c','summit_b2b','institute','dash','cliente_suporte','concierge_summit') then
    return jsonb_build_object('ok', false, 'motivo', 'rota_invalida');
  end if;

  select exists (select 1 from agentes.kit_blocos k where k.rota = v_rota and k.ativo)
    into v_configurado;

  for r in
    select k.bloco, n.nspname as sch, p.proname as fn
    from agentes.kit_blocos k
    left join pg_proc p
      on p.oid = to_regprocedure(
           case when k.provider ~ '^[a-z_][a-z0-9_$]*\.[a-z_][a-z0-9_$]*$'
                then k.provider || '(uuid,jsonb)'
           end)
     and p.prokind          = 'f'
     and p.pronargs         = 2
     and p.proargtypes[0]   = 'uuid'::regtype
     and p.proargtypes[1]   = 'jsonb'::regtype
     and p.prorettype       = 'jsonb'::regtype
     and not p.proretset
     and p.provolatile      = 's'
     and p.prosecdef
    left join pg_namespace n
      on n.oid = p.pronamespace and n.nspname = 'public'
    where k.rota = v_rota and k.ativo and k.obrigatorio
    order by k.bloco
  loop
    v_obrigatorios := v_obrigatorios || r.bloco;

    if r.sch is null or r.fn is null then
      -- provider não resolve ou viola o contrato (uuid,jsonb)->jsonb STABLE SECDEF
      v_ausentes := v_ausentes || r.bloco;
    else
      -- disponibilidade não depende de conversa/necessidade: (null, null)
      execute format('select %I.%I($1::uuid, $2::jsonb)', r.sch, r.fn)
        into v_payload
        using null::uuid, null::jsonb;

      if v_payload is null then
        v_ausentes := v_ausentes || r.bloco;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'ok',                  true,
    'rota',                v_rota,
    'kit_configurado',     v_configurado,
    'kit_disponivel',      v_configurado and cardinality(v_ausentes) = 0,
    'blocos_obrigatorios', to_jsonb(v_obrigatorios),
    'blocos_ausentes',     to_jsonb(v_ausentes));
end;
$fn$;

revoke all on function public.mind_kit_meta(text)
  from public, anon, authenticated;
grant execute on function public.mind_kit_meta(text) to service_role;

comment on function public.mind_kit_meta(text) is
  'Única verdade de completude do Kit de uma rota: kit_configurado, kit_disponivel, blocos_obrigatorios e blocos_ausentes. Um bloco obrigatório é ausente quando o provider não resolve/viola o contrato ou quando retorna SQL NULL. Conhece só o registry (agentes.kit_blocos) e o contrato universal do provider — nenhuma fonte factual. pode_executar pertence ao Capability Gate.';


-- ============================================================
-- 3. public.mind_agent_kit(p_rota, p_conversa_id, p_necessidade)
-- ------------------------------------------------------------
-- Monta o Kit da rota. `meta` é chamada literal a mind_kit_meta: nenhuma
-- segunda lógica de completude existe neste sistema.
--
-- Conversa: repassada aos providers, não validada aqui. Os providers já a
-- tratam — `mind_kit_ofertas` reporta `atribuicao_da_conversa` como fato —
-- e validá-la exigiria trazer `engagement` para o search_path desta função
-- sem que ela leia nada de lá. Rota inválida devolve o erro de
-- mind_kit_meta, verbatim.
-- ============================================================
create or replace function public.mind_agent_kit(
  p_rota text,
  p_conversa_id uuid,
  p_necessidade jsonb default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, agentes
as $fn$
declare
  v_rota       text  := nullif(btrim(p_rota), '');
  v_meta       jsonb;
  v_structured jsonb := '{}'::jsonb;
  v_playbook   text;
  v_payload    jsonb;
  r            record;
begin
  v_meta := public.mind_kit_meta(v_rota);

  -- rota inválida: devolve exatamente o erro já fechado, sem taxonomia nova
  if not coalesce((v_meta->>'ok')::boolean, false) then
    return v_meta;
  end if;

  -- conversa: taxonomia já congelada em public.mind_agent_context, reproduzida
  -- literalmente. `engagement` NÃO entra no search_path — a referência é
  -- schema-qualified e a função é SECURITY DEFINER.
  -- Precedência: rota_invalida > sem_conversa > conversa_nao_encontrada > kit.
  if p_conversa_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_conversa');
  end if;

  if not exists (
    select 1 from engagement.conversas c where c.id = p_conversa_id
  ) then
    return jsonb_build_object(
      'ok',          false,
      'motivo',      'conversa_nao_encontrada',
      'conversa_id', p_conversa_id);
  end if;

  -- playbook vem só do sistema, nunca de kit_blocos
  select pr.conteudo
    into v_playbook
    from agentes.prompts pr
   where pr.chave = 'playbook_' || v_rota
     and pr.ativo
   limit 1;

  for r in
    select k.bloco, n.nspname as sch, p.proname as fn
    from agentes.kit_blocos k
    left join pg_proc p
      on p.oid = to_regprocedure(
           case when k.provider ~ '^[a-z_][a-z0-9_$]*\.[a-z_][a-z0-9_$]*$'
                then k.provider || '(uuid,jsonb)'
           end)
     and p.prokind          = 'f'
     and p.pronargs         = 2
     and p.proargtypes[0]   = 'uuid'::regtype
     and p.proargtypes[1]   = 'jsonb'::regtype
     and p.prorettype       = 'jsonb'::regtype
     and not p.proretset
     and p.provolatile      = 's'
     and p.prosecdef
    left join pg_namespace n
      on n.oid = p.pronamespace and n.nspname = 'public'
    where k.rota = v_rota and k.ativo and k.secao = 'structured'
    order by k.bloco
  loop
    continue when r.sch is null or r.fn is null;

    execute format('select %I.%I($1::uuid, $2::jsonb)', r.sch, r.fn)
      into v_payload
      using p_conversa_id, p_necessidade;

    -- só payload não-nulo entra: NULL é bloco indisponível
    if v_payload is not null then
      v_structured := v_structured || jsonb_build_object(r.bloco, v_payload);
    end if;
  end loop;

  return jsonb_build_object(
    'playbook',   v_playbook,
    'structured', v_structured,
    'knowledge',  '[]'::jsonb,
    'tools',      '[]'::jsonb,
    'meta',       v_meta);
end;
$fn$;

revoke all on function public.mind_agent_kit(text, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.mind_agent_kit(text, uuid, jsonb) to service_role;

comment on function public.mind_agent_kit(text, uuid, jsonb) is
  'Kit da rota para o agente. Erros na precedência congelada: rota_invalida (de mind_kit_meta) > sem_conversa > conversa_nao_encontrada (taxonomia de mind_agent_context). Em sucesso: playbook (agentes.prompts), structured (bloco -> payload dos providers ativos de secao=structured com payload não-nulo), knowledge=[], tools=[] e meta (chamada literal a mind_kit_meta). Sem canal, sem histórico, sem blob de conversa, sem gerado_em.';
