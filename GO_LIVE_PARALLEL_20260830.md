# Go-live — execução paralela Vendedor + Concierge

> Documento operacional de ownership. Para o ponto exato de retomada, leia primeiro **`CHECKPOINT_ATUAL.md`**.
>
> Regra central: **ordem de deploy não é ordem de trabalho**. Uma lane pode adiantar o que é independente, mas continua dona da capacidade até E2E ou gate real.

## Lanes vigentes

### Lane A — Core / DB / Gate — CONCLUÍDA

Entregou speakers canônicos, Kit Loader, Capability Gate e a correção #49 do `mind_kit_evento`.

Não reabrir Lane A salvo regressão real.

### Lane B — Vendedor Summit / Treble — issue #40

Dona até uma conversa real do Treble/WhatsApp atravessar:

```text
identidade/contexto → Router → Gate → Kit → Decisioning/Agent → resposta/handoff
```

Inclui B2C/B2B, regra comercial, guardrail de preço e entrega real no WhatsApp.

PR atual: #47. Consulte `CHECKPOINT_ATUAL.md` para HEAD e última correção pendente.

### Lane C — Concierge Summit — issue #41

Dona até o app real responder E2E usando:

- `concierge_summit` com playbook e Kit;
- `mindagent_chat_search` e fontes canônicas de programação/speakers;
- `mindagent-chat` como runtime único do chat e executor server-side das ações Play;
- `sensitivity` nos interests;
- sem Router no app dedicado, mas com Gate;
- sem backend/identidade/session lifecycle paralelo.

PR atual: #50.

### Lane D — pós-turno / memória / write-back / Silence — issue #42

Dona da capacidade completa, não só do coletor.

Escopo:

- memória segura e leitura no runtime;
- análise pós-turno do Concierge;
- write-back/dispatch necessário, respeitando gate de source-of-truth/CRM;
- continuidade/Silence sem ligar outbound sem autorização.

PRs atuais: #46 e #51.

### Lane E — Play / experiência — issue #43

Dona até NPS/feedback/insight realmente funcionarem na superfície do app para pessoa identificada e chegarem às casas canônicas.

Reusa o executor da Lane C. Não cria backend próprio.

PR atual: #48.

---

## Ownership de componentes durante o paralelo

| componente | dona |
|---|---|
| `treble-inbound-agent` e guardrail comercial | B |
| `mindagent-chat`, retrieval/Kit/playbook Concierge, executor actions | C |
| política/writers de memória segura, coletor, pós-turno, Silence | D |
| Play UI + writers `mind_play_*` | E |
| Router/Gate/Kit Core já integrados | A/Core, somente regressão |

Mudança em componente de outra lane exige coordenação na issue, não fork silencioso.

---

## Ordem de migrations / integração

Versão alvo atual:

```text
B #47   20260830210000
A #49   20260830220000  [live]
C #50   20260830223000
C #50   20260830233000
D #46   20260830234000  [rename pendente]
D #51   20260830234500
E #48   20260830235000  [rename pendente]
```

Não criar migration extra só para corrigir timestamp de migration que nunca chegou a produção.

Integração/deploy:

```text
B → C → D → E → E2E transversal
```

A exceção de compatibilidade já fechada é `sensitivity`: a Edge C pode começar a enviar a chave antes da #51 estar live; a RPC antiga ignora o campo JSON extra. Isso evita ligar o writer fail-closed antes do produtor.

---

## Definition of Done por lane

**B / Vendedor**

- B2C e B2B pelo Core canônico;
- fatos/preços/regras corretos;
- handoff correto;
- resposta chega no WhatsApp real;
- E2E falho é corrigido, não mascarado por HTTP 200.

**C / Concierge**

- programação/horário/local/palestrante/tema/dia/minuto corretos;
- recomendação só com evidência;
- sem invenção em pergunta sem fonte;
- runtime Gate→Kit vivo no app;
- Edge versionada e publicada do commit aprovado;
- Play action mode no mesmo runtime/session lifecycle;
- E2E real do app.

**D / pós-turno**

- memória bloqueada não persiste/expoe;
- memória segura pode voltar ao runtime sem expor legado não validado;
- pós-turno do Concierge entra no circuito correto;
- write-back só no contrato permitido;
- continuidade preparada; outbound permanece desligado até gate.

**E / Play**

- pessoa identificada, sem conversa prévia, consegue usar Play;
- NPS/feedback/insight chegam às casas canônicas;
- sem pessoa = sem coleta;
- fontes inexistentes ficam explicitamente bloqueadas;
- UI nunca afirma persistência quando não houve persistência.

---

## Regras anti-conflito

1. Um componente tem uma dona durante o paralelo.
2. PR é chunk; issue/lane é dona da capacidade.
3. Nenhuma lane mergeia por conta própria.
4. Antes do teste/deploy final, sincronizar com `main`.
5. Testar só o afetado e regressões diretamente atingidas.
6. Não abrir hardening/refactor lateral.
7. Divergência material ou decisão de negócio não congelada volta para supervisão/Adriana.
8. Espera técnica/CI não encerra lane.
9. GitHub é o barramento: coordenação cross-lane vai direto à issue dona.
10. Não usar Adriana como mensageira quando comentário no GitHub resolve.

---

## Boundary de deploy

- merge em `main` pode publicar app Cloudflare e aplicar migrations Supabase;
- `supabase/functions/*` **não deve ser tratado como auto-publicado** neste repo sem `supabase/config.toml`;
- `treble-inbound-agent` e `mindagent-chat` exigem comparação com a versão viva + deploy manual controlado no momento atual;
- preço/regra comercial, dados destrutivos, identidade/security/auth, source-of-truth, outbound e write-back material continuam gates sensíveis.

---

## Retomada rápida

Se a execução for interrompida, não use a checklist histórica de `GO_LIVE_VENDEDOR_CONCIERGE_20260830.md` como estado atual. Ela preserva o plano inicial.

Use:

1. `CHECKPOINT_ATUAL.md`;
2. HEAD atual das PRs #47/#50/#46/#51/#48;
3. issue dona #40/#41/#42/#43;
4. produção real;
5. primeiro item pendente da lane.
