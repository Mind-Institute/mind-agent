# Correspondência de preços e lotes → `mind.offers`

> Carga em 2026-08-21, corrigida no mesmo dia após a Adriana apontar a
> fonte da verdade: projeto Supabase **mind-summit-propostas**
> (`rwqdperfphubzteckyqd`) — tabelas `lotes`, `lote_precos`,
> `ticket_categories` (com os checkouts) e `pricing_tiers`. É a mesma
> fonte que alimenta o site via Edge Function `pricing`.
> O catálogo `eduzz_products` do vendas-dashboard serviu de validação
> cruzada (preços batem; o calendário de lá estava desatualizado).

## O mapeamento

| Origem (mind-summit-propostas) | Destino (`mind.offers`) |
|---|---|
| `ticket_categories.slug` (mind/vip/prime) | `codigo` = `{categoria}-lote-{n}` · `elegibilidade.categoria` |
| `lotes.numero` + `inicio`/`fim` | sufixo do `codigo` · `inicia_em`/`encerra_em` |
| `lote_precos.preco` | `valor` (BRL) |
| `lote_precos.parcela` (12x) | `condicoes_pagamento` = "12x de R$ N" |
| `ticket_categories.checkout_url` | `checkout_url` (link fixo por categoria — a Eduzz vira o lote no mesmo link) |

Checkouts: Mind `sun.eduzz.com/89AQDKYGWD` · VIP `sun.eduzz.com/40Q3EKPK0B`
· Prime `sun.eduzz.com/E05XKB2KWX`.

## Lote vigente e calendário (reestruturado em 19/08)

Regra da fonte: vigente = primeiro lote cujo `fim > now()`.
**Hoje: Lote 5** (14/08 → **28/08**) — Mind **R$ 1.597** (12x 133) ·
VIP **R$ 2.597** (12x 216) · Prime **R$ 6.297** (12x 525).
Depois: Lote 6 (28/08 → 04/09, Mind 1.697 · VIP 2.697) e Lote 7
(04/09 → 17/09). Argumento de urgência verdadeiro: **28/08 os preços sobem**.

## Grupos e volume

- `pricing_tiers` (global, no carrinho): 5–9 → 10% · 10–14 → 20% ·
  15–19 → 30% · 20+ → 35%. Gravado em
  `mind.commercial_rules.desconto_por_volume` com `acao: handoff_vendedor`.
- Produtos Eduzz "Grupo VIP" (5–9: R$250 off · 10+: R$500 off por pessoa)
  também existem e estão em `mind.offers` (`publico=false`, sem checkout —
  grupo fecha com vendedor).

## Pendências na fonte (para a Adriana confirmar)

1. **Lote 7 com preços aparentemente trocados** em `lote_precos`:
   Mind = R$ 2.797 e VIP = R$ 1.797 — o inverso da progressão de todos os
   lotes anteriores (Mind sempre ~R$ 1.000 mais barato). Provável troca de
   digitação. **Não carreguei o Lote 7 no `mind.offers`** até corrigirem
   na fonte.
2. **Dois mecanismos de desconto de grupo convivem** (tiers percentuais ×
   produtos "Grupo VIP" com valor fixo). Qual o bot deve citar?
3. `settings.event_date` diz `2026-09-01`, mas o evento é 16–17/09 —
   conferir o que esse campo significa para o site.

## Sincronização contínua (próximo passo, não construído)

A carga atual é manual. Para a virada de 28/08 não depender de ninguém:
um workflow n8n (ou `pg_cron`) lendo `lotes`/`lote_precos` do
mind-summit-propostas e fazendo upsert em `mind.offers` — preço e lote
nunca mais divergem entre site, dashboard e bot.
