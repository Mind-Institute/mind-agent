# Instruções para coding agents

Este arquivo é um **ponteiro**, não uma segunda constituição.

Se você entrou no projeto sem contexto, leia **nesta ordem**:

1. **[`CHECKPOINT_ATUAL.md`](CHECKPOINT_ATUAL.md)** — ponto exato de retomada: lanes, PRs, HEADs, dependências, renames pendentes e próxima ação.
2. **[`PROJECT_STATE.md`](PROJECT_STATE.md)** — arquitetura congelada, ordem do runtime, gates e decisões que não devem ser reabertas.
3. **[`GO_LIVE_PARALLEL_20260830.md`](GO_LIVE_PARALLEL_20260830.md)** — ownership das lanes e ordem de integração/deploy.
4. **[`BACKLOG.md`](BACKLOG.md)** — investigações/fragilidades deferidas que não devem ser refeitas do zero. Leia só a frente relevante.
5. **[`docs/CORE_UNIVERSAL.md`](docs/CORE_UNIVERSAL.md)** — estado real e contratos que já estão implementados/vivos.
6. **Investigue o sistema real** (Supabase, código, migrations aplicadas, Edge Functions publicadas) antes de alterar qualquer coisa. Documentação descreve o sistema; não substitui verificá-lo.

Regras:

- documentação antiga não é autoridade; se contradiz sistema/decisão vigente, reconcilie;
- decisão congelada nova não pode ficar só em conversa;
- o mesmo conceito mantém a mesma taxonomia;
- não crie tabela/função/camada sem consumidor concreto;
- não reabra decisão fechada sem fato novo material;
- teste só o afetado;
- uma lane continua dona da capacidade até E2E ou gate real — não termina porque abriu um PR;
- GitHub é o barramento entre lanes; poste coordenação/checkpoint na issue dona em vez de usar Adriana como mensageira;
- siga a menor mudança correta.
