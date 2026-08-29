# Mind Intelligence

Repositório do **Core Universal do Mind** — o núcleo compartilhado que serve todos os agentes
(vendas, atendimento, concierge) e todos os canais (WhatsApp/Treble, app do Summit, site).

Canal é adapter, não arquitetura. Agente novo **não** reimplementa identidade, contexto, memória
ou histórico: ele consome o Core.

## Documentação canônica

**[`docs/CORE_UNIVERSAL.md`](docs/CORE_UNIVERSAL.md)** — comece por aqui. Descreve o sistema como
ele é hoje, verificado contra o Supabase real: identidade canônica, fontes da verdade comerciais,
catálogo, o que já está implementado e o que é roadmap.

Se algum documento divergir do banco, **o banco vence**.

## Estado atual

Passos **1 a 6 fechados**: ingestão e identidade universal · ponte pessoa ↔ HubSpot · fila de
resolução de conflito · coletor factual de CRM · coletor da realidade comercial · coletor factual
de Engagement.

**Próximo passo: 6B — transcrição/normalização de áudio na ingestão**, para que uma mensagem
de voz chegue ao agente já com texto, sem virar arquitetura de áudio à parte.

AGENT_CONTEXT, Router, Decisioning e memória universal são arquitetura congelada, ainda não
implementados.

## O que mais vive aqui

| | onde | o que é |
|---|---|---|
| **Chat público** | raiz (`index.html`, `app.js`, …) | o Mind Agent do Summit — ver [`docs/MIND_AGENT_FRONTEND.md`](docs/MIND_AGENT_FRONTEND.md) |
| **Painel admin** | `admin/` | manutenção do conteúdo que o chat usa — ver [`admin/README.md`](admin/README.md) |
| **Contratos compartilhados** | [`shared/CONTRATOS.md`](shared/CONTRATOS.md) | o que liga chat, admin e Edge Functions — leitura obrigatória antes de mexer no banco ou nas functions |

## Trabalhando aqui

[`CLAUDE.md`](CLAUDE.md) tem as regras de trabalho e a ordem de autoridade.
[`BACKLOG.md`](BACKLOG.md) tem as decisões de negócio pendentes e a dívida conhecida.

```bash
npx serve .          # chat público em http://localhost:3000
npm run dev:admin    # painel admin na porta 5174
npm run build        # monta dist/ (chat na raiz, admin em /admin)
```

Supabase: projeto `mind-agent` (`ymnmotgglsrxmjmonwjz`).
