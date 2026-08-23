# MIND INTELLIGENCE — PRODUCT & COMMERCIAL MODEL

## Purpose

Preservar a diferença entre identidade do produto, execução concreta, oferta comercial e direito de acesso.

## Product families

- Summit
- Institute
- Events
- Dash

Não criar família Consulting. Consultoria pertence a Dash.

## Canonical products

### Summit
- Mind Summit

### Institute
- Formação Estratégica em Bem-Estar no Trabalho e Liderança Positiva
- Significado no Trabalho
- Segurança Psicológica
- Mind Journey
- On Demand

### Events
- Oxford no Conselho
- futuros eventos

### Dash
- Mind Dash
- outros produtos/serviços de consultoria

## Product runs

`catalog.product_runs` representa edição/turma/entrega/version concreta.

Exemplos:
- Mind Summit 2025
- Mind Summit 2026
- Mind Summit 2027
- Formação A / turma 2025
- Formação B / turma 2025
- Formação C / turma 2025
- Journey / entrega 2025

Campos conceituais:
- product_id
- run_type: edition | cohort | delivery | version
- name
- year
- sales_start_at / sales_end_at
- delivery_start_at / delivery_end_at
- status

## Summit facet

`summit.editions` é extensão 1:1 do `product_run_id` do Summit.

Summit-specific data:
- venue/spaces
- sessions
- speakers/roles
- materials
- reservations
- attendance
- feedback

Não duplicar identidade do run dentro do schema Summit.

## Offers

Oferta comercial não é produto.

Para Mind Summit 2026, exemplos de offers:
- MIND
- VIP
- PRIME
- Corporate / Delegação Corporativa

Offer pode conter:
- name/code
- product_run_id
- audience/eligibility
- status
- valid dates
- checkout destination

## Pricing periods

Lote é janela de preço, não nova offer.

`pricing_periods` deve modelar lotes/periods com validade.

`offer_prices` liga:
- offer
- pricing_period
- currency
- amount
- valid dates/status

## Discount rules

Desconto precisa ser uma política comercial estruturada, não comportamento do prompt.

Tipos possíveis:
- volume
- coupon
- corporate condition
- manual approval threshold

A implementação atual de volume e guardrail de preço é considerada comportamento valioso a preservar durante migração.

## Offer inclusions

Benefícios/acessos devem ser estruturados.

Exemplos Summit:
- acesso aos 2 dias
- workshops
- masterclasses
- lounge
- assento/setor
- materiais

Evitar depender apenas de texto descritivo para saber entitlement.

## Orders and people

Um pedido pode envolver pessoas diferentes.

`order_people.role` deve permitir:
- buyer
- payer
- participant
- beneficiary

Isso evita assumir comprador = participante.

## Access rights

Direitos efetivos pertencem a `commercial.access_rights` (ou camada equivalente definida na implementação final), derivados de compra, convite, cortesia, upgrade etc.

Concierge deve consultar access rights para saber o que a pessoa pode reservar/acessar.

## Product content

`catalog.product_content` guarda conteúdo comercial/editorial reutilizável:
- description
- audience
- value_proposition
- differentiator
- outcome
- feature
- proof_point
- faq
- case
- use_case

Pode ser product-level ou run-level e ter validade/locale/priority.

## Scientific evidence is separate

Não armazenar evidência científica como simples proof point comercial sem fonte.

`knowledge.claims` + `sources` guardam evidência.
`product_content` pode referenciar/conectar claims quando necessário, mas cada domínio mantém sua responsabilidade.

## Calendar / lifecycle

Sales behavior pode variar conforme o lifecycle do product run:
- pre-sales
- sales open
- close to event
- event live
- post-event

Essa lógica deve vir de datas/status/policies, não de texto fixo em prompt.

## Cross-sell

Porque product identity e relacionamento são compartilhados, um agent pode detectar fit com outro produto sem duplicar CRM.

Exemplo:
Sales Summit percebe demanda corporativa → pode recomendar Delegação/Corporate.
Concierge percebe interesse duradouro em formação → pode criar opportunity/handoff para Institute.
Support resolve acesso → pode identificar oportunidade relevante.

Recomendação cross-sell nunca deve esconder o motivo operacional ou violar action scope.

## Current migration implications

No protótipo atual:
- `catalogo.produtos` mistura produto e run;
- Summit 2026 está cadastrado como produto;
- `summit.offers` contém oferta/preço;
- regras comerciais estão parcialmente no schema Summit e RPCs públicas.

Target:
- normalizar canonical product + product_run;
- mover commercial truth para schema compartilhado `commercial`;
- manter compatibility layer temporária enquanto Sales/Concierge migram;
- remover legacy somente após consumidores terem sido migrados/testados.

## Non-negotiable examples

Errado:
`catalog.products` row “Mind Summit 2026”.

Certo:
`catalog.products`: Mind Summit
`catalog.product_runs`: Mind Summit 2026

Errado:
criar offer “VIP Lote 6”.

Certo:
Offer VIP + pricing period Lote 6 + offer price correspondente.

Errado:
colocar “desconto de grupo de 10 pessoas = X%” apenas no prompt.

Certo:
`commercial.discount_rules` / função de pricing; prompt recebe resultado autorizado.