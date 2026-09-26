# Mind — regras para Claude Code / agentes de execução

## Antes de trabalhar

Leia, nesta ordem:

0. **`READ_ME_FIRST.md`** — a Regra #1: toda linha sobre uma pessoa nasce com `mind_id` (D5/D6).
1. **`CHECKPOINT_ATUAL.md`** — onde estamos exatamente agora.
2. **`PROJECT_STATE.md`** — arquitetura, gates e decisões congeladas.
3. **`GO_LIVE_PARALLEL_20260830.md`** — ownership da sua lane e ordem de integração.
4. **`BACKLOG.md`** — somente o trecho relevante para não repetir investigação.
5. **`docs/CORE_UNIVERSAL.md`** — o que já está vivo.
6. Depois, **investigue o sistema real** diretamente relacionado ao seu chunk.

Uma IA nova deve conseguir retomar o projeto sem conversa anterior lendo esses arquivos e conferindo os HEADs das PRs citadas no checkpoint.

## Ritual obrigatório

```text
INVESTIGAR
→ ENTENDER O QUE JÁ EXISTE
→ DECIDIR A MENOR MUDANÇA
→ IMPLEMENTAR
→ TESTAR SÓ O AFETADO
→ REGISTRAR CHECKPOINT NA ISSUE/PR
→ CONTINUAR ATÉ E2E OU GATE REAL
```

Não transformar espera de CI, preview ou review em motivo para encerrar a lane.

## Papéis vigentes

- **Adriana**: produto/negócio e gates sensíveis. Por **D2**, é a **única aprovadora e a única executora** de mudança de banco: migration, coluna, índice, constraint, backfill, tabela nova, schema novo ou troca de autoridade. Ninguém mais executa no banco; agentes preparam e ela decide.
- **ChatGPT arquiteto/supervisor**: mantém o modelo mental, verifica sistema real, fecha a menor mudança, coordena lanes, revisa PRs, decide integração e registra o checkpoint.
- **Claude Code**: investiga e implementa o escopo delegado em branch `claude/...`; traz evidência independente; não amplia escopo e não mergeia por conta própria.
- **GitHub**: memória compartilhada e barramento entre lanes.

Se houver outro supervisor técnico no repositório, ele deve reconstruir o mesmo checkpoint; não nasce segunda arquitetura.

## Boundary de deploy

**Merge em `main` é boundary de deploy**, mas o efeito depende do componente:

- app/root Cloudflare: merge pode publicar automaticamente;
- migrations Supabase: merge pode aplicá-las pela integração;
- Edge Functions versionadas em `supabase/functions/`: **neste repo, sem `supabase/config.toml`, não assumir publicação automática**. As funções críticas atuais (`treble-inbound-agent`, `mindagent-chat`) têm deploy manual controlado depois do merge e comparação com a versão viva.

Por isso revisão/teste vêm antes do merge.

Gate explícito da Adriana antes de execução perigosa quando houver: dado destrutivo/irreversível, identidade, auth/RLS/security/secrets, preço/desconto/regra comercial, source of truth, outbound/disparo, write-back operacional material, **mudança estrutural de banco (tabela nova, schema novo, mudança de proveniência — D2)** ou mudança de produto não congelada.

## Arquitetura — uma linguagem só

| camada | papel |
|---|---|
| **Intelligence** | o que é verdade agora |
| **Playbook** | como um excelente profissional pensa/atua |
| **Decisioning** | qual estratégia faz sentido agora |
| **Agent** | o que efetivamente diz/faz |

> PLAYBOOK DECIDE COMO PENSAR. INTELLIGENCE INFORMA O QUE É VERDADE AGORA.

Coletor factual não decide, pontua, recomenda ou escreve.

Runtime canônico:

```text
CANAL/ENTRADA
→ INGESTÃO
→ IDENTIDADE
→ AGENT_CONTEXT
→ ROUTER se necessário
→ CAPABILITY GATE
→ KIT DA ROTA
→ DECISIONING
→ AGENT
→ AÇÃO/HANDOFF
→ PÓS-TURNO/MEMÓRIA
→ WRITE-BACK/DISPATCH
→ CONTINUIDADE/SILENCE
```

## Regras de implementação

- menor mudança correta; sem redesign lateral;
- não invente requisito, prompt, playbook ou conteúdo de negócio;
- use casas/taxonomias existentes;
- antes de criar tabela, prove que falta uma casa;
- **Regra #1 (D5):** toda tabela que fala de pessoa tem `mind_id` (D6: é o nome da coluna do ID universal em toda tabela), resolvido ou criado pela porta única `mind_identidade_resolver` **antes** da escrita (`mind_pessoa_ligar_tabela` põe uma tabela nova na regra); nunca grave pessoa ou identificador fora dela; nunca funda pessoas fora de `mind_fusao_decidir` — a fusão é decisão da Adriana;
- **função nasce fechada** (desde 25/09): o banco não dá mais EXECUTE a PUBLIC em função nova; a migration faz `revoke all ... from public, anon, authenticated` e concede só a quem chama — RPC interna é `service_role`, porta do app ou do site é `grant ... to anon`/`authenticated` de propósito (contrato: `tests/permissoes_funcoes_contract.sql`);
- não transforme hipótese futura em hardening atual;
- não exponha memória ao Agent sem o contrato de sensibilidade aprovado;
- não ligue outbound sem gate;
- não crie backend/identidade/session lifecycle paralelo para Play/Concierge;
- structured authoritative first; RAG só para long-tail;
- preço/checkout/desconto/horário/disponibilidade nunca dependem de vector como fonte da verdade;
- descoberta lateral: registre e volte ao caminho crítico.

## Ownership atual

As issues são donas da capacidade, não os PRs:

- #40 — Vendedor/Treble até E2E WhatsApp;
- #41 — Concierge até E2E app;
- #42 — pós-turno/memória/write-back/continuidade até o limite dos gates;
- #43 — Play/experiência até E2E no app.

Consulte `CHECKPOINT_ATUAL.md` para HEAD e próxima ação de cada lane.

## Como responder à supervisão

Ao terminar um chunk, devolva apenas:

- o que já existia/reutilizou;
- menor mudança feita;
- branch/PR/HEAD;
- arquivos tocados;
- testes afetados/resultados;
- divergência material nova;
- dependência/gate real que restou.

Poste checkpoint/coordenação diretamente na issue dona quando outra lane precisa da informação. Não espere Adriana retransmitir.
