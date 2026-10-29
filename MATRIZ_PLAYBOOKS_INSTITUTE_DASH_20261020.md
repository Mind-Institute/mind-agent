# Matriz de pré-lançamento — playbooks Institute e Dash

20/10/2026 · branch `claude/vendedor-institute-dash-whatsapp` · nada publicado.

Revisão dos playbooks ativos no banco contra o backlog de pré-lançamento
(`BACKLOG.md` §17) e contra as regras comerciais congeladas de 26/09/2026 em
`CLAUDE.md`. Fonte: `agentes.prompts` e `mind_agent_kit`, lidos em 20/10.

**O que a matriz separa, de propósito:** implementação concluída não é teste técnico
aprovado, e teste técnico aprovado não é homologação comercial. Nenhuma linha abaixo
diz "pronto" sem dizer até onde.

---

## 1. Bloqueador de lançamento encontrado na revisão

### `vendas_institute` carrega preço escrito, e ele diverge do catálogo

O playbook que chega ao modelo não é uma peça só: `mind_agent_kit` monta
`base` + `tom_de_voz` + `playbook_institute` + o decisioning `vendas_institute`.
Medido no texto ativo:

| componente | preços escritos | datas escritas |
|---|---|---|
| `playbook_institute` v2 | **0** | 1 |
| `playbook_dash` v1 | **0** | 0 |
| `base`, `tom_de_voz`, `objecoes`, `product_decisioning`, `decisioning_vendas_universal` | 0 | 0 |
| **`vendas_institute` v2** | **39** | **15** |

Isso contraria a regra de 26/09 diretamente: *"agente nunca tem preço, oferta, cupom
ou prazo escrito no playbook ou no prompt: sempre aponta para onde estão os preços e
as ofertas atuais"*.

**E não é só formal — 11 dos 17 valores distintos não existem no catálogo vivo:**

| escrito no prompt | existe em `api.ofertas` vigente? |
|---|---|
| 4.997 · 2.497 · 1.997 · 1.497 · 697 · 497 | sim |
| 7.491 · 5.997 · 5.991 · 5.004 · 1.697 · 1.494 · 994 · 500 | **não** |
| **417 · 209 · 167** | **não** — o catálogo tem 416,42 · 208,08 · 166,42 |

As três parcelas são o caso perigoso, porque são a frase mais comum de uma venda. O
prompt arredonda para cima; o catálogo (e portanto o Kit) trunca para baixo. O
guardrail de preço só autoriza o que veio em `DADOS_OFICIAIS` — **o prompt não é
fonte de preço, e nunca foi**. Rodado contra o Kit real:

```
passa                       "...R$ 4.997 à vista ou 12x de R$ 416."   ← catálogo
BARRA → handoff  (R$ 417)   "...R$ 4.997 à vista ou 12x de R$ 417."   ← vendas_institute
BARRA → handoff  (R$ 167)   "O Mind Journey é 12x de R$ 167."         ← vendas_institute
passa                       "O Mind Journey é 12x de R$ 166."         ← catálogo
```

Ou seja: **se o modelo obedecer ao decisioning, a venda vira transferência.** O
guardrail está certo e o prompt está velho.

**Isto é conteúdo comercial e não foi tocado.** Corrigir `vendas_institute` é
reescrever playbook comercial — fora do que me foi autorizado. Vai como decisão.

---

## 2. Matriz por item do backlog §17

§17 lista seis itens a validar "para cada produto/oferta, na fonte oficial", antes de
vender.

| # | item do backlog | Institute | Dash | estado |
|---|---|---|---|---|
| 1 | código, nome, preço, parcelamento, vigência | 6 programas, 9 ofertas vigentes em `api.ofertas`, com à vista e parcelado | não se aplica — Dash não vende | **coberto** (Institute) |
| 2 | regras comerciais e elegibilidade | bloco `condicoes` do catálogo: garantia de 7 dias, contratação anual, o que cada formação inclui | `playbook_dash` proíbe condição comercial | **coberto** |
| 3 | `checkout_url` Eduzz oficial e cupom | **não se aplica** — o Institute vende por página própria em `joinmind.com.br`; `api.ofertas` tem 0 `checkout_url`; `catalogo.cupons` tem 0 cupom ativo | não se aplica | **requisito superado** (ver §4) |
| 4 | campanha / `utm_id` | **não existe** — a página oficial vai sem rastreio, por decisão de 20/10 | não se aplica | **decisão tomada, sem atribuição** |
| 5 | bloco do Kit e playbook/rota que podem oferecer | `institute_catalogo` + `playbook_institute`, rota `institute`, Gate aberto no WhatsApp | `product_intelligence` + `playbook_dash`, rota `dash`, Gate aberto | **coberto** |
| 6 | E2E com compra controlada e retorno do pedido pago | **não feito** | não se aplica | **pendente** |

---

## 3. O que cada playbook manda, e o runtime consegue executar

| instrução do playbook | runtime executa? | evidência |
|---|---|---|
| Institute: recomendar pelo nome oficial do catálogo | sim | `institute_catalogo` no Kit, 6 programas |
| Institute: dizer preço à vista e parcelado do catálogo | **sim, agora** | guardrail passou a ler `a_vista`/`parcelado`; 12 fatos extraídos do Kit real |
| Institute: mandar a página oficial para inscrição | **sim, agora** | `escolherLinkOficial`, validação por igualdade exata |
| Institute: cair no botão de checkout (`#`) | **sim, pendente de migration** | âncoras lidas das páginas reais; `20261020151000` escrita, não aplicada |
| Institute: passar o WhatsApp do time fora do catálogo | sim | `contato_time_institute` no Kit |
| Institute/Dash: `next_route=…` para trocar de competência | **sim, agora** | `next_route` no schema, Gate valida, `rota_ativa` persiste; 20 verificações no harness |
| `cliente_suporte`: `next_route=concierge_summit` | **não, e está certo** | `concierge_summit` não está na política do WhatsApp, então nem entra no enum |
| Dash: não inventar preço/proposta | sim, com trava dupla | playbook proíbe **e** o Kit do Dash não tem bloco de oferta, então o guardrail barra qualquer valor |
| Dash: "não prometa reunião, contato ou retorno que o runtime não executa" | **parcialmente** | o runtime não agenda nem dispara nada; depende do modelo obedecer — é item de leitura na homologação |
| Institute: "não fale de estrutura interna (JSON, bloco, banco)" | não verificável por código | item de leitura na homologação |

---

## 4. Requisitos antigos que o sistema superou

| requisito | onde está escrito | por que não vale mais |
|---|---|---|
| "a Adriana ainda vai fornecer os dados comerciais do Institute" | BACKLOG §17 | os dados existem desde 24/09: `institute_catalogo` com 6 programas, preço, prazo, página e FAQ |
| "`checkout_url` Eduzz oficial e eventual cupom" | BACKLOG §17 item 3 | o Institute não vende por Eduzz. 0 `checkout_url` em `api.ofertas`, 0 cupom ativo. A premissa de carrinho é do Summit |
| "Até lá, o Agent deve falar apenas com o contexto factual e nunca construir preço, condição ou link" | BACKLOG §17 | continua valendo como princípio, mas "construir" ≠ "citar do catálogo". O agente cita; o guardrail confere |

---

## 5. Divergência de arquitetura, para a Adriana (D2/D10)

**Oferta do Institute não mora em `catalogo`.** A regra de 26/09 diz que "preço,
oferta, order bump e cupom moram no schema `catalogo`, e o painel `admin/` é o
controle dele". Hoje:

- `catalogo.ofertas` tem 14 ofertas, **todas do Summit e todas inativas**;
- as ofertas vivas do Institute estão em `institute.*`, expostas pela view
  `api.ofertas`, e é de lá que `mind_kit_institute_catalogo` lê.

Portanto o painel de catálogo não controla o que o agente vai vender. Não toquei
nisso: unificar as duas casas é mudança estrutural e de proveniência — **D2**, e a
aprovação é da Adriana.

---

## 6. Dívida que a abertura de tráfego acende

- **`analise_vendas_institute` e `analise_vendas_dash` têm prompt vazio e estão
  inativos.** O cron `analise_conversas` roda a cada 15 min; conversas dessas rotas
  serão classificadas para analisadores de casca vazia e **não gerarão análise
  nenhuma**. Lane D (#42), item 18.3 do BACKLOG.
- **Sem atribuição no Institute.** Como o link vai sem rastreio e sem evento de
  checkout, não há como medir conversão do agente para o Institute. Foi decisão
  consciente de 20/10; vira pergunta de negócio no dia em que alguém pedir o número.

---

## 7. Resumo do que falta para lançar

| bloqueio | de quem é | tipo |
|---|---|---|
| `vendas_institute` com preço escrito e divergente | Adriana | conteúdo comercial |
| aprovação D7 das funções alteradas | Adriana | gate de arquitetura |
| a Treble não encaminha ao agente desde 09/09 | Vinicius / painel Treble | integração |
| homologação das conversas com modelo real | Vinicius | leitura humana |
| E2E com entrega no aparelho | Vinicius | teste controlado |
