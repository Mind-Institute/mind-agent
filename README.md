# Mind Agent / Mind Intelligence

Repositório do **Core Universal do Mind** e das superfícies que o consomem: vendedor Summit via Treble/WhatsApp, Concierge/Play do Summit no app e futuros agentes.

Canal é adapter, não arquitetura. Agente novo não reimplementa identidade, histórico, memória, Router, Gate ou Intelligence.

## Comece aqui

Se você está entrando sem contexto:

1. **[`CHECKPOINT_ATUAL.md`](CHECKPOINT_ATUAL.md)** — ponto exato onde o go-live está agora.
2. **[`PROJECT_STATE.md`](PROJECT_STATE.md)** — arquitetura/gates/decisões congeladas.
3. **[`GO_LIVE_PARALLEL_20260830.md`](GO_LIVE_PARALLEL_20260830.md)** — lanes e ordem de integração.
4. **[`BACKLOG.md`](BACKLOG.md)** — investigação deferida; leia só a frente relevante.
5. **[`docs/CORE_UNIVERSAL.md`](docs/CORE_UNIVERSAL.md)** — contratos e componentes já vivos.

Se documentação divergir do sistema real, verifique o sistema e reconcilie a documentação. **HEAD de PR ativo é mais fresco que qualquer checkpoint escrito.**

## Estado atual resumido

Core já em `main`/produção:

- ingestão/identidade/CRM/Engagement e `AGENT_CONTEXT` universal;
- Router universal com seis rotas;
- Capability Gate;
- Kit Loader mínimo;
- speakers/session links canônicos completos (81/81);
- `mind_kit_evento` corrigido para produto correspondente (#49, main `a226e288...`).

Go-live em lanes:

- **B / #47** — Vendedor Summit: runtime/guardrail preparados; falta correção operacional final do telefone de smoke, depois merge + deploy manual + flag + E2E WhatsApp.
- **C / #50** — Concierge: retrieval/Kit/playbook + `mindagent-chat` versionado/wired; SQL 17 contratos, Edge 19/19; falta review/merge, deploy manual da Edge e E2E app.
- **D / #46 + #51** — memória segura/Silence: código preparado e desligado; faltam renames de migration, integração depois de C e gates de write-back/outbound.
- **E / #48** — Play: writers/UI preparados, person-bound; falta rename de migration, integrar ao executor C e E2E real.

Detalhe, HEADs e ordem exata: **[`CHECKPOINT_ATUAL.md`](CHECKPOINT_ATUAL.md)**.

## Arquitetura em uma linha

```text
CANAL → INGESTÃO → IDENTIDADE → AGENT_CONTEXT → ROUTER? → GATE → KIT → DECISIONING → AGENT → AÇÃO → PÓS-TURNO/MEMÓRIA → WRITE-BACK → SILENCE
```

Camadas:

- **INTELLIGENCE** = verdade atual;
- **PLAYBOOK** = como pensar/atuar bem;
- **DECISIONING** = estratégia do turno;
- **AGENT** = execução.

## Superfícies

| superfície | onde |
|---|---|
| app/Concierge/Play | raiz (`index.html`, `app.js`, `chat-service.js`, etc.) |
| painel admin | `admin/` |
| Edge Functions versionadas | `supabase/functions/` |
| migrations/testes SQL | `supabase/migrations/`, `tests/` |
| contratos do Core | `docs/CORE_UNIVERSAL.md` |

Supabase: projeto `ymnmotgglsrxmjmonwjz`.

## Deploy

`main` é boundary de deploy. Cloudflare/root e migrations Supabase podem reagir ao merge.

**Não presuma que Edge Function versionada é publicada automaticamente:** neste repo não há `supabase/config.toml`; as funções críticas do go-live têm publicação manual controlada após merge.

Antes de mergear, confira a lane e os gates em `CHECKPOINT_ATUAL.md`.
