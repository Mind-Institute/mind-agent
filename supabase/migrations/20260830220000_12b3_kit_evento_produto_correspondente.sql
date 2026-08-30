-- ============================================================
-- Correção pontual — public.mind_kit_evento resolve o produto por
-- correspondência com evento.produto_codigo
-- ------------------------------------------------------------
-- CONTRATO CONGELADO (inalterado)
--   O bloco `evento` só é disponível quando existe evento ativo E o produto
--   CORRESPONDENTE a esse evento. `ativo`/`vende` do produto NÃO entram na
--   condição: são fatos que o agente precisa enxergar, inclusive negativos.
--
-- A DIVERGÊNCIA
--   A implementação escolhia o produto por um proxy — `schema_dados =
--   'summit_2026'` com `order by codigo limit 1` — e nunca relacionava
--   `evento.produto_codigo` a `produtos.codigo`. Produção está correta hoje
--   só porque existe um único produto com esse schema_dados e ele por acaso
--   corresponde (`mind-summit-2026`). Bastaria um segundo produto summit_2026
--   com código anterior no alfabeto para o bloco passar a descrever o produto
--   errado — silenciosamente, com payload válido.
--
-- A CORREÇÃO
--   O seletor por proxy vira a correspondência real. `catalogo.produtos.codigo`
--   é PRIMARY KEY, então o join devolve no máximo uma linha e `order by`/
--   `limit 1` deixam de ter função. `evento.produto_codigo` nulo ou sem produto
--   correspondente passa a não resolver produto — e o CASE já existente devolve
--   SQL NULL, que é exatamente o que o contrato manda.
--
--   `schema_dados` sai junto porque era o próprio proxy que está sendo
--   substituído: mantê-lo acrescentaria à disponibilidade uma condição que o
--   contrato não tem, capaz de produzir NULL mesmo havendo produto
--   correspondente.
--
-- PRESERVADO BYTE A BYTE
--   Assinatura, STABLE, SECURITY DEFINER, search_path, o CASE de
--   disponibilidade, o payload (`bloco`, `evento` com `to_jsonb(e) - 'id'`,
--   `produto` com os seis campos), a semântica de SQL NULL e a ACL.
-- ============================================================

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
    -- Correspondência explícita: o produto DO evento, não "um produto do
    -- schema". `codigo` e PRIMARY KEY, entao no maximo uma linha.
    select p.*
    from catalogo.produtos p
    join evento e on p.codigo = e.produto_codigo
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

-- ACL preservada (create or replace nao a altera; explicito e idempotente).
revoke all on function public.mind_kit_evento(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.mind_kit_evento(uuid, jsonb) to service_role;

comment on function public.mind_kit_evento(uuid, jsonb) is
  'Bloco factual do Kit: evento ativo + o produto correspondente, resolvido por evento.produto_codigo = catalogo.produtos.codigo. NULL quando nao ha evento ativo ou nao ha produto correspondente. ativo/vende do produto sao fatos do payload, nunca condicao de disponibilidade.';
