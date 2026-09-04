# Mind Agent / Mind Intelligence

Repositório do **Core Universal do Mind** e das superfícies que o consomem: vendedor Summit via Treble/WhatsApp, Concierge/Play do Summit no app e futuros agentes.

Canal é adapter, não arquitetura. Agente novo não reimplementa identidade, histórico, memória, Router, Gate ou Intelligence.

## Comece aqui

Se você está entrando sem contexto:

1. **[`CHECKPOINT_ATUAL.md`](CHECKPOINT_ATUAL.md)** — ponto exato onde o go-live está agora.
2. **[`PROJECT_STATE.md`](PROJECT_STATE.md)** — arquitetura/gates/decisões congeladas.
3. **[`MAPA_DO_SISTEMA.md`](MAPA_DO_SISTEMA.md)** — componentes e fluxo que estão vivos.
4. **[`IMPLEMENTATION_STATUS.md`](IMPLEMENTATION_STATUS.md)** — entrega consolidada e gates externos.
5. **[`BACKLOG.md`](BACKLOG.md)** — investigação deferida; leia só a frente relevante.
6. **[`docs/CORE_UNIVERSAL.md`](docs/CORE_UNIVERSAL.md)** — contratos e componentes já vivos.

Se documentação divergir do sistema real, verifique o sistema e reconcilie a documentação. **HEAD de PR ativo é mais fresco que qualquer checkpoint escrito.**

## Estado atual resumido

Estado verificado em **04/09/2026**, com `main` em
`44d831018772b39a764dd311b9cc839a9e2d1c43`:

- Core compartilhado integrado para Vendedor B2C/B2B e Concierge/App;
- `mindagent-chat` v39 e `treble-inbound-agent` v38 ativos;
- identidade, Router, Gate, Kit, Intelligence, checkout e pós-turno vivos;
- memória segura e inbox de recuperação ativos, com outbound ainda fechado;
- write-back HubSpot publicado em modo seguro, com `apply` condicionado;
- programação Summit com 77 sessões e 81 vínculos sessão–palestrante.

Detalhe e próximo movimento seguro: **[`CHECKPOINT_ATUAL.md`](CHECKPOINT_ATUAL.md)**.

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
