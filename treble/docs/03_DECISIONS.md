# Registro de decisões

Formato: **D-n — decisão** · por quê · o que descarta. Decisões são
revisáveis, mas só com registro aqui.

---

**D-1 — O cérebro fica fora do Treble, numa Edge Function (`treble-inbound-agent`), plugada via webhook.**
Por quê: o agente nativo do Treble não reconsulta API a cada mensagem — o
teste de 2026-08-20 (`treble-find-location`) provou o limite. O Treble
suporta oficialmente "Integrate Your Own AI" via webhook de resposta +
`[REQUEST_TRIGGER]` + `POST /session/{id}/update`.
Descarta: agente nativo do Treble como cérebro; base de conhecimento
estática como fonte primária.

**D-2 — Tools são funções internas da Edge Function, não endpoints HTTP.**
Por quê: um endpoint por pergunta (modelo do teste de ontem e do plano
original: `get_ticket_info()` etc. como API) multiplica latência, custo e
pontos de falha, e deixa ao agente do Treble a decisão de quando chamar.
Dentro do processo, a consulta ao banco é direta e obrigatória.
Descarta: "Mind Intelligence API" como camada HTTP na V1 — ela volta no
backlog como camada pública quando outras superfícies (AI Coach, app)
precisarem da mesma inteligência.

**D-3 — Regras comerciais são código, não prompt.**
Por quê: "pode mencionar cupom?" não pode depender de obediência do LLM.
`get_commercial_rule()`/`check_coupon()` respondem determinística e
auditavelmente a partir de `commercial_rules`/`coupons`. Preço e checkout
só saem de tool call. Elimina por construção o erro P1 mais grave
(desconto indevido, preço inventado).

**D-4 — Sem máquina de estados rígida; estado é histórico + variáveis.**
Por quê: os 9 estados do plano original compensavam a falta de memória do
builder. Com o transcript em `conversations`, o LLM navega contexto melhor
que um grafo. Mantemos `stage` gravado por turno para métricas e follow-up,
não como trilho.
Descarta: fluxo ramificado extenso no Conversation Builder.

**D-5 — Mesmo repositório (`mind-agent`, pasta `treble/`) e mesmo projeto Supabase (`ymnmotgglsrxmjmonwjz`).**
Por quê: a fonte da verdade é uma só — agenda/palestrantes já vivem nesse
projeto, e o padrão de Edge Function com IA (`mindagent-chat`) também.
Repositório novo separaria o código da inteligência que ele consome.
Descarta: repo `treble-inbound-sales-agent` e projeto Supabase novo
(itens 1 e 27 da ordem original). Revisável se o produto crescer.

**D-6 — PDF/base de conhecimento nativa vira fallback, nunca caminho crítico.**
Por quê: conhecimento congelado desatualiza; mas se a Edge Function cair,
o bot não pode ficar mudo. `knowledge/` guarda um documento **gerado por
script** a partir do Supabase para o agente nativo de contingência.
Descarta: alimentação manual de PDF como plano principal.

**D-7 — Um único agente inbound na V1.**
Por quê: mesma conclusão do plano original — especializar
(abandono, outbound, pós-compra) só com razão funcional, depois da v0.1.

**D-8 — Testes rodam contra a Edge Function, sem WhatsApp no meio.**
Por quê: os 13 casos de `04_TESTS.md` viram script executável
(`tests/`); regressão é um comando, não uma tarde de conversas manuais.
O teste end-to-end via WhatsApp valida só a integração, não o comportamento.

**D-9 — Venda pela Eduzz; um link de checkout por categoria.** (2026-08-21)
`tickets.checkout_url` guarda o link por categoria; verificação de compra
e abandono via API/webhooks Eduzz (fase 2 da construção).

**D-10 — Handoff para os vendedores no inbox do Treble.** (2026-08-21)
O fluxo do Treble tem rota fixa de transferência; o agente prepara resumo
da conversa nas variáveis de sessão antes de transferir.

**D-11 — O "master router" é função, não frota.** (2026-08-21)
O desenho antigo previa um agente roteador no Treble triando B2C / B2B /
cliente-suporte antes de passar a agentes separados. Na arquitetura nova o
roteamento acontece em três camadas: (1) entrada determinística no fluxo do
Treble (origem da campanha/link pré-preenche `audience`); (2) classificação
a cada turno como primeiro passo do cérebro único, que troca de playbook
(prompt + tools) sem trocar de agente — o lead que muda de assunto no meio
não perde contexto; (3) handoff para a fila humana certa (vendedor B2C,
time B2B, suporte). Playbook vira agente separado só quando os dados de
`treble.conversations.audience` justificarem.
Descarta: agente roteador dedicado e frota de agentes na V1 (coerente com D-7).

**D-12 — Reusar o schema `mind`; criar só o que falta.** (2026-08-21)
A inspeção do banco mostrou que a Fase 1 planejada já existia em grande
parte: `mind.offers` é a tabela de ingressos (código, valor, lote,
checkout_url, elegibilidade — vazia, aguardando dados), `mind.policies` e
`mind.event_rules` cobrem políticas e regras textuais, `mind.organization_content`
recebe o FAQ, e `mind.knowledge_documents/chunks` já é a base RAG.
Criados apenas: schema `treble` (conversations + messages, RLS sem policies
— só service role), `mind.coupons` e `mind.commercial_rules`
(migration `20260821_treble_inbound_mvp.sql`, aplicada em 2026-08-21).
Guardrails nascem seguros: sem regra ativa liberando, desconto e menção a
cupom são proibidos por default.
Descarta: as tabelas `tickets`, `faq` e `event_info` previstas nos docs —
substituídas pelos equivalentes que já existiam.
