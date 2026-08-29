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

Passos **1 a 10 fechados**: ingestão e identidade universal · ponte pessoa ↔ HubSpot · fila de
resolução de conflito · coletor factual de CRM · coletor da realidade comercial · coletor factual
de Engagement · normalização de áudio · normalização determinística da pessoa · AGENT_CONTEXT
universal · contrato do AGENT_CONTEXT coberto por teste · Router universal.

O **Router** decide qual das seis competências assume a necessidade atual e está deliberadamente
**fora do runtime**: existe, é chamável e está coberto por teste, mas nada em produção depende
dele ainda — ligá-lo ao turno ao vivo é do Passo 11.

**Próximo passo: 11 — Registry de rotas + capability gate.**

Kit da rota, Decisioning e memória universal seguem como arquitetura congelada, ainda não
implementados.

```bash
psql "$DATABASE_URL" -f tests/mind_agent_context_contract.sql   # contrato do AGENT_CONTEXT
```

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
