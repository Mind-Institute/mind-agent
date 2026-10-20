# Auditoria do agente de vendas no WhatsApp — 20/10/2026

Revisão somente leitura: repositório, banco e funções de leitura do banco.
Nada foi publicado, aplicado, escrito ou alterado. O único arquivo criado é este.

---

## Veredito

O agente existe, está publicado, responde saudável e o código vivo é
byte a byte igual ao da `main`. E está **fora de operação desde 10/09**.

Duas coisas distintas, e as duas são verdade:

1. **ele não recebe turno há 40 dias** — a Treble deixou de chamá-lo;
2. **se recebesse um turno hoje, 100% terminaria em transferência para humano** —
   por construção, não por falha.

O segundo ponto é o que importa: mesmo religando a Treble, não há venda. As duas
rotas que este runtime sabe executar estão fechadas no Gate, e as três rotas que o
Router pode emitir no WhatsApp hoje não são executadas por ele. A interseção é vazia.

---

## Como foi apurado

| o quê | método |
|---|---|
| repositório | `origin/main` em `fc2b0f5` — a `dev` local está **86 commits atrás** |
| função viva | baixada pela API e comparada arquivo a arquivo com a `main` |
| banco | apenas `SELECT` e funções `STABLE` (`mind_rota_capacidade`, `mind_kit_meta`, `mind_canal_rotas`, `mind_kit_ofertas*`) |
| endpoint | um `GET /health` |
| testes | rodados em worktree descartável da `main`, já removido |

Nenhuma função `VOLATILE` foi chamada. Nenhum `apply_migration`, nenhum deploy.

---

## 1. O que está publicado

| campo | valor |
|---|---|
| função | `treble-inbound-agent` |
| versão Supabase | **63** |
| runtime | **1.10.4** |
| status | `ACTIVE`, `verify_jwt=false` |
| publicada em | **06/09/2026** |
| `/health` | HTTP 200, `{"ok":true,"version":"1.10.4"}` |

`index.ts` e `guardrail-preco.ts` vivos são **idênticos** à `main` — zero linhas de
diferença. Entre os compartilhados há só ruído de bundler (escapes Unicode,
anotação de tipo, um traço de comentário), com uma exceção real:

- `_shared/agent-intelligence.ts` vivo **não tem** `ORCAMENTO_TURNO_COMPLEXO_MS`
  (45 s). O constante entrou depois, junto com `mindagent-chat` (publicada 16/09).
  **Não afeta este agente**: ele não referencia a constante, e o `/health`
  respondendo 200 prova que o módulo carrega.

**O `CHECKPOINT_ATUAL.md` está desatualizado neste ponto:** registra v41 / `1.10.2`.
A realidade é v63 / `1.10.4`.

---

## 2. O agente não recebe tráfego — e o canal recebe muito

Histórico completo de `agente='treble-inbound-agent'`:

- **21 conversas**, entre 31/08 e **09/09/2026**;
- **58 falas de lead** no total — a maioria conversas de um turno só;
- 7 terminaram em `needs_human=true`, 4 com `checkout_sent=true`;
- `rota_ativa` gravada em apenas 3 delas (todas `summit_b2c`, em 05/09).

Nas últimas 24 horas: **zero invocações** da função.

Enquanto isso, o WhatsApp está entre os canais mais movimentados do sistema:

- `treble-webhook`: **1.941 chamadas** em 24 h;
- 30 dias: **22.368 mensagens de agente** e **2.746 de lead**;
- hoje (20/10): 329 conversas; em 19/10, 5.878.

**Tudo isso é `agente='treble'`, nunca `treble-inbound-agent'`.** É o fluxo da
plataforma Treble, não este agente. E `treble-webhook` é só registrador — o
próprio cabeçalho diz: "Nao roda IA: so registra".

Quem decide chamar o agente é a configuração da Treble, que fica fora deste
repositório e fora deste banco. **A auditoria não consegue dizer por que parou em
10/09, nem se foi decisão ou silêncio.** É a primeira coisa a confirmar.

---

## 3. O achado principal: hoje não há caminho de venda

### O Gate, consultado agora

```
summit_b2c  → pode_executar: false · reason: missing_kit          · needs_human: true
summit_b2b  → pode_executar: false · reason: canal_incompativel   · needs_human: true
```

As duas rotas do vendedor estão fechadas. E o runtime força `needs_human` quando o
Gate fecha — é determinístico, não fica a cargo do modelo.

### O Router, no WhatsApp

`mind_canal_rotas('whatsapp')` devolve: **`cliente_suporte`, `dash`, `institute`**.

O enum do JSON Schema é montado a partir dessa lista, então o Router **não
consegue emitir** `summit_b2c` nem `summit_b2b` neste canal.

### O runtime

```
supabase/functions/treble-inbound-agent/index.ts:191
const ROTAS_DO_VENDEDOR = new Set(["summit_b2c", "summit_b2b"]);
```

Fora dessas duas, o turno encerra com transferência.

### A conta

| | |
|---|---|
| o Router pode emitir | `cliente_suporte`, `dash`, `institute` |
| o runtime sabe executar | `summit_b2c`, `summit_b2b` |
| interseção | **vazia** |

**100% dos turnos viram handoff.** Inclusive `cliente_suporte`, que é a única rota
que o Gate libera no WhatsApp (`pode_executar: true`) — o runtime a recusa mesmo
assim, porque não está em `ROTAS_DO_VENDEDOR`.

### Por que ficou assim

Em **24/09/2026** a `agentes.canal_competencia` foi mexida, com observação escrita:

- `whatsapp/summit_b2c` e `whatsapp/summit_b2b` → `ativo=false`,
  *"Desligada em 24/09/2026: Summit 2026 encerrado e fora de venda."*
- `whatsapp/institute` e `whatsapp/dash` → `ativo=true`,
  *"Ligada em 24/09/2026 (Adriana): Institute/Dash reconhecidos no WhatsApp;
  **o runtime do Treble ainda não executa**, então transfere ao time com a necessidade."*

No mesmo dia subiram `playbook_institute` v2, `vendas_institute` v2 e
`router_universal` v5. Os blocos de Kit de `institute` e `dash` estão completos.

**O banco virou de Summit para Institute em 24/09. O runtime do WhatsApp parou em
06/09 e não virou.** A observação da Adriana já antecipava exatamente isso — o
comportamento atual é o previsto, não um defeito surpresa. O que a auditoria
acrescenta é que ele nunca chega a ser exercido, porque a Treble também parou de
chamar.

---

## 4. Catálogo

- `mind-summit-2026`: `vende=false`, `vende_ate=2026-09-18`;
- **todas as 14 ofertas** do catálogo estão `ativo=false`;
- `mind_kit_ofertas_b2b` devolve `ofertas: []` e `pode_vender: false` — **nenhum
  preço de evento encerrado vaza**;
- o Institute tem 5 formações + Mind Journey com `vende=true`, mas **zero ofertas e
  zero preços** em `catalogo.ofertas`. Não há o que cotar ainda;
- `treble.config.produto_padrao` continua `mind-summit-2026`.

---

## 5. Divergências e riscos

### a) O Gate diz "kit disponível" sobre um kit vazio (B2B)

Os dois provedores se comportam diferente quando não há nada para vender:

| provedor | retorno hoje | efeito no `mind_kit_meta` |
|---|---|---|
| `mind_kit_ofertas` (B2C) | `NULL` | bloco ausente → `kit_disponivel: false` |
| `mind_kit_ofertas_b2b` | objeto com `ofertas: []` | bloco **presente** → `kit_disponivel: true` |

Por isso o B2C reprova em `missing_kit` e o B2B passa pelo Kit e só é barrado no
`canal_incompativel`. **Hoje o único freio do B2B é o flag de canal.**

Se alguém reativar `whatsapp/summit_b2b`, o Gate responde `pode_executar: true` e o
agente roda um turno de venda com lista de ofertas vazia. O guardrail de preço
impede preço inventado (payload monetário vazio ⇒ nenhum valor autorizado), então
degrada para resposta sem preço — não para preço errado. Ainda assim, um Gate que
afirma "kit disponível" sobre um kit sem oferta é uma garantia que não garante.

### b) Uma trava de regressão parou de travar

`tests/vendedor_resposta_nao_truncada.mjs` passa **13 de 16**. As 3 que falham:

```
- existe a linha que lê turn.answer
- turn.answer é lido sem .slice()
- turn.answer é lido sem substring/substr
```

O teste procura `/const answer\s*=/`. O runtime usa `let answer = ...`
(`index.ts:1016`). Não acha a linha, e as três asserções caem juntas.

**O corte não voltou** — conferido, não há `.slice()` na leitura. Mas as três
asserções que existem justamente para impedir o retorno do truncamento em 700
caracteres (o defeito da v1.5.1, que entregou uma mensagem partida no meio de
"Mind") estão cegas desde que `const` virou `let`. É um falso negativo que ninguém
vê, porque o teste já falha por outro motivo.

### c) Configuração morta

`treble.config.core_rota_kit = true`, atualizada em 31/08. A v1.5.0 removeu a flag
do runtime: *"a flag `core_rota_kit` deixou de existir aqui"*. O valor no banco não
tem leitor.

### d) Prompt de fallback datado

`PROMPT_FALLBACK` ainda abre com *"Você atende o WhatsApp oficial do Mind Summit
2026"* — evento encerrado em 17/09.

### e) Segredo do webhook

`treble.config.webhook_token` é um segredo estático, em texto claro no banco, **sem
rotação desde 21/08**. É o mesmo valor para `treble-webhook` e
`treble-inbound-agent`, as duas com `verify_jwt=false`, e viaja em query string
(`?token=`). Não encontrei o token nos logs de função (o campo `url` não é
capturado nessa visão), então **não há evidência de vazamento** — é risco de
desenho, não incidente observado.

---

## 6. O que está sólido

- **Superfície de banco fechada.** As 13 RPCs que o agente usa são `SECURITY
  DEFINER` com `EXECUTE` apenas para `service_role`; `anon` e `authenticated`
  negados em todas. A migration `20260925201217_funcoes_internas_so_service_role`
  cumpriu o que prometia.
- **Guardrail de preço: 88/88** contratos.
- **Runtime B2B: 16/16.** **Falha sem silêncio: 16/16.** **Rota comercial +
  intelligence + model routing: 29/29.**
- **Smoke não toca produção sem env**: sai com código 2, zero requisições.
- **Outbound continua desligado**, como manda o gate: cron `silence_reavaliar`
  inativo, `engagement.recovery_dispatch_queue` vazia, nenhum cron de disparo
  ativo. Os crons ativos são espelho de HubSpot, análise de conversa e sync de
  catálogo — leitura e write-back já aprovados, nada de disparo para lead.
- **Suíte geral da `main`: 464 de 475.** As 11 falhas são de
  `arquitetura_decisoes`, `home_handoff` e `mindagent_chat_wiring` — lane do
  Concierge/painel. **Nenhuma do vendedor**, fora a trava cega do item 5b.

---

## 7. O que esta auditoria não responde

1. **Por que a Treble parou de chamar o agente em 10/09.** A configuração do
   webhook fica no painel da Treble, fora do repositório e do banco.
2. **Se a parada foi decidida ou silenciosa.** Não há registro de decisão em
   nenhum dos arquivos de estado.
3. **O que o WhatsApp deve vender agora.** `institute` e `dash` foram reconhecidos
   no canal em 24/09, mas o Institute ainda não tem oferta nem preço no catálogo.
   É decisão de produto, não de engenharia.

---

## 8. Gates da Adriana que aparecem no caminho

Nada abaixo foi feito; está listado porque qualquer retomada esbarra nisso.

- **reativar rota comercial no WhatsApp** — é regra comercial e `canal_competencia`
  é a casa da decisão de 24/09;
- **ensinar o runtime a executar `institute`/`dash`** — muda o escopo do agente,
  que hoje é vendedor de Summit;
- **publicar qualquer versão nova** da `treble-inbound-agent` — este repo não tem
  `supabase/config.toml`, então publicação é manual e comparada com a viva;
- **rotacionar o `webhook_token`** — derruba a integração da Treble até o painel
  dela ser atualizado com o valor novo; é janela coordenada, não troca unilateral.

---

## Resumo em uma linha

O vendedor do WhatsApp está publicado, saudável e correto no que sabe fazer —
e aponta para um evento que acabou, em um canal que deixou de chamá-lo, com as
duas rotas que ele executa desligadas desde 24/09. Religar a Treble sem virar o
runtime só troca silêncio por transferência.
