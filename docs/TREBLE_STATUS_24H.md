# Treble → status de 24h → HubSpot

Como o Mind sabe, por número de WhatsApp, se a **conversa está aberta ou fechada** (janela de
24h) e reflete isso no HubSpot — pra **não disparar campanha em cima de conversa aberta** (que
falha com "Active session").

## A regra (é da Adriana, não do Treble)
- **Aberta** = a pessoa respondeu nas **últimas 24h**.
- **Fechada** = passou **24h desde a última resposta dela**.
- O `finished_at`/`session.close` do Treble **NÃO** é a janela de 24h (o Treble deixa sessão
  pendurada sem fim). Quem decide é o **tempo desde a última resposta**.

## Onde mora
- **`treble.polls`** — catálogo dos fluxos (poll) do Treble: `poll_id`, `nome`, `tipo`
  (inbound/outbound), `sincronizado_em` (rodízio do re-pull).
- **`treble.status_da_conversa`** — a lista: por `telefone` (E.164 com DDI), `status`
  (aberta|fechada), `momento` (última atividade conhecida), `aberta_em`, `fechada_em`.
  `status` é **derivado** de `momento` vs 24h (recalculado, não cru).
- **`treble.status_hs_leads` / `treble.status_hs_contatos`** — trava de idempotência: último
  valor escrito em cada Lead/Contato no HubSpot (só reescreve quando muda).
- Conversa/transcript continua em `engagement.conversas` + `engagement.mensagens`
  (marcado `agente`). Eventos crus do webhook em `engagement.treble_eventos`.

## De onde vem o `momento` (última atividade)
1. **Ao vivo (inbound):** `treble_agent_start` — a cada mensagem que chega ao agente, marca
   **aberta agora** (`treble_status_marcar`). Tempo real pros fluxos que passam pelo agente.
2. **Fechamento (todos os fluxos):** webhook **`session.close`** → `treble-webhook` →
   `treble_sessao_encerrada_gravar`: grava o **transcript** em `engagement` e usa a **última
   mensagem do cliente** como `momento`.
3. **Re-pull das campanhas:** `treble-sessoes-sync` lê a API de sessões por poll
   (`GET main.treble.ai/devapi/poll/{id}/sessions`) → `momento = coalesce(finished_at, created_at)`.
   Cobre respostas dentro das **campanhas outbound** (a API não dá a hora da última msg, então é
   a melhor aproximação; a **recência** em `treble_status_marcar` nunca sobrescreve dado mais fresco).

## Recalcular + escrever (o ciclo)
`treble_status_ciclo()`:
1. re-pull de **todas** as campanhas (rodízio: as com `sincronizado_em` mais antigo primeiro,
   dentro do orçamento de tempo por corrida);
2. `treble_status_recompute()` — reavalia todos pela regra das 24h (aberta→fechada quando passa);
3. `treble-status-hubspot` — escreve as mudanças no HubSpot (só o que mudou):
   - **Lead** `status_conversa` = `conversa_aberta` | `conversa_fechada`;
   - **Contato** `status_conversa_treble` = `treble_aberta` | `treble_fechada`.

**Cron (horário de São Paulo, UTC−3):**
- `treble_status_dia` — 08:00–20:30, a cada 30 min.
- `treble_status_noite` — 21:00–07:00, a cada 2h.

## Como usar no disparo
Filtra a campanha no HubSpot por **`status_conversa_treble` = Fechada** (contato) ou
`status_conversa` (lead) → exclui quem está com conversa aberta.

## Limites honestos
- Não existe webhook de **"mensagem recebida"** na conta (só HSM Status, Close Session,
  Deployment Failure). Então o "abre" em **tempo real** só vale pro que passa pelo **agente
  inbound**. Resposta de campanha é pega no **`session.close`** (com a hora certa) ou no
  **re-pull** (aproximado por `created_at`, conservador). O ideal, se um dia existir, é apontar
  um webhook de Message Response pra `treble-webhook`.
- Telefone é normalizado pra E.164 com DDI (prepend `55` em número BR de 10–11 dígitos), pra
  ao-vivo e backfill casarem na mesma linha.

## Escopos do HubSpot (token do sync)
`crm.objects.contacts.read/write`, `crm.objects.deals.read`, `crm.objects.leads.read/write`.

## Funções/edge (referência)
- Edge: `treble-webhook` (recebe eventos), `treble-sessoes-sync` (re-pull), `treble-status-hubspot`
  (write-back), `treble-inbound-agent` (agente).
- RPC: `treble_status_marcar`, `treble_status_recompute`, `treble_status_ciclo`,
  `treble_sessao_encerrada_gravar`, `treble_sessao_backfill`, `treble_evento_gravar`,
  `treble_status_pendentes(_contato)`, `treble_status_confirmar(_contato)`, `treble_poll_sincronizado`.
