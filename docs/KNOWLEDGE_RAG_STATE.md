# Knowledge / RAG — estado operacional

> Memória canônica do trabalho de Knowledge/RAG iniciado em 29/09/2026.
> Esta frente é aditiva. Não substituir `PROJECT_STATE.md` nem `CHECKPOINT_ATUAL.md`;
> este documento registra apenas o control plane, a ingestão científica e o admin de Knowledge.

## Decisões congeladas

- `ecossistema` é o control plane transversal de conhecimento.
- O conteúdo físico pode continuar em `summit_2026`, `institute`, `dash` etc.
- `collection` = governança/routing; `construct` = ontologia científica; tags = descoberta.
- Uma fonte, seção, insight ou asset pode pertencer a várias collections.
- Não criar um vector DB por collection: corpus comum + filtros por metadata/acesso antes do ranking.
- Retrieval: identidade do agente → collections habilitadas → acesso → hybrid search → reranking → contexto.
- Autorização é pré-retrieval.
- Livro inteiro = `mind_only`.
- A regra “livro com licença restrita = `derived_only`” foi removida por decisão da Adriana em 29/09/2026. Direitos e modo de ingestão continuam registrados fonte a fonte (`direitos_uso`, `modo_ingestao`, `provenance_notes`).
- Referência citada por livro nasce como `reference_lead`; só vira evidência primária depois de ingerida/verificada.
- Conteúdo do Summit não vira evidência científica automaticamente; preservar `expert_statement`/proveniência.
- Decisões que exigem Adriana ficam em uma única coluna `pendencia_decisao`; execução continua com default conservador.

## Tabelas criadas em ecossistema

- `fontes_conhecimento`
- `source_locations`
- `source_text_versions`
- `chunks_conhecimento`
- `secoes_conhecimento`
- `insights_conhecimento`
- `knowledge_collections`
- `source_collections`
- `section_collections`
- `insight_collections`
- `knowledge_assets`
- `asset_collections`
- `agent_knowledge_access`
- `agent_asset_overrides`
- `ingestion_inventory`

RLS está habilitado nas tabelas novas. Embeddings usam `vector(1536)`. FTS dos chunks/insights usa configuração `simple` para corpus multilíngue.

## Collections atuais

behavior_change, burnout, business_performance, future_of_work, job_crafting,
job_design, leadership, learning_science, meaningful_work, measurement,
mental_health, mind_methodology, motivation, nr1, organizational_culture,
psychological_safety, psychosocial_risk, self_compassion, stress,
summit_2026_content, summit_2026_operations, workplace_wellbeing.

A taxonomia é viva: adicionar collection quando houver razão de routing/governança,
não para cada palavra-chave.

## Summit 2026

As 81 sessões e os documentos de `summit_2026.knowledge_documents` foram registrados como
`knowledge_assets`, sem mover o conteúdo.

- operação: credenciamento, intervalos, almoço, autógrafos, FAQ, ingresso, regras etc.
- conteúdo: palestras, painéis, workshops, masterclasses, slides, transcrições.

Keynotes/masterclasses de Amy Edmondson, Christina Maslach, Sonja Lyubomirsky,
Jan-Emmanuel De Neve e a palestra de Adriana já têm mappings iniciais de collections.

## Agentes

Keys reais encontradas no sistema:
`cliente_suporte`, `concierge_summit`, `dash`, `institute`, `summit_b2b`, `summit_b2c`.

Existe uma matriz provisória em `agent_knowledge_access`.
As decisões duvidosas estão em `pendencia_decisao`.
O runtime futuro não pode confiar em `agent_key` arbitrário vindo do cliente; identidade do agente deve ser derivada server-side.

## Admin

Nova Edge Function viva: `mindagent-knowledge`.

Rotas:
- GET /admin/knowledge_collections
- GET /admin/knowledge_assets
- GET /admin/agent_knowledge_access
- PATCH /admin/agent_knowledge_access/:id

O navegador não recebe `service_role`. A função valida sessão + `mind_admin_users`.
RPCs administrativos de Knowledge têm EXECUTE revogado de PUBLIC/anon/authenticated
e concedido apenas a service_role.

Branch frontend: `knowledge-rag-control-plane`.

Já contém:
- contratos de Knowledge;
- recursos no AdminDataProvider;
- conexão híbrida com `mindagent-knowledge`;
- rota `/knowledge`;
- menu Knowledge Base;
- Overview;
- tabela de Collections;
- tabela de Assets;
- matriz Agent × Knowledge.

Ainda não mergear antes de typecheck/build/review.

## Piloto científico

Nove fontes do piloto foram registradas e processadas na fonte canônica:

1. Frazier et al. (2017) — Psychological Safety meta-analysis.
2. Keyes (2002) — Mental Health Continuum.
3. Bailey et al. (2019) — Meaningful Work empirical review.
4. Wrzesniewski et al. (2013) — Job Crafting.
5. Schaufeli & Bakker (2004) — JD-R / burnout & engagement.
6. Ewert, Vater & Schröder-Abé (2021) — self-compassion & coping meta-analysis.
7. MTE (2025) — guia NR-1 / riscos psicossociais.
8. Rodrigues (2020) — COPSOQ III Brasil.
9. De Neve & Ward (2025) — Why Workplace Wellbeing Matters.

Direitos e ingest_policy estão explícitos por fonte.

### De Neve

Fonte = `licensed_restricted + derived_only + mind_only`.
O arquivo proíbe introdução do livro em retrieval system. Texto bruto não é persistido.

Os 12 capítulos foram processados capítulo a capítulo:
- 12/12 capítulos concluídos;
- apenas inteligência derivada/parafraseada persistida;
- raw text não armazenado;
- estudos citados relevantes viram `reference_lead` até a fonte primária ser ingerida e verificada.

### Retrieval global

Está viva a RPC `public.mind_knowledge_buscar_global`, service-role-only e SECURITY INVOKER.

Fluxo:
1. agente;
2. collections habilitadas;
3. acesso permitido;
4. geração de candidatos lexical/vector;
5. ranking híbrido;
6. retorno com provenance, evidence status, causal status e localizador.

O filtro de autorização ocorre antes do search/ranking.

Teste de isolamento executado com a mesma query:
- `knowledge_admin`: retornou resultados internos;
- `institute`, `dash` e `summit_b2b`: zero resultados enquanto os insights continuam `mind_only`.

Isso confirma que conteúdo interno não vaza para agentes configurados como `mind_public`.

### Embeddings

RPCs de fila/persistência:
- `mind_knowledge_embedding_pending`
- `mind_knowledge_embedding_save`

Edge Function viva:
- `mindagent-index-global-knowledge`

Ela gera embedding 1536-d somente para `insights_conhecimento`; nunca envia raw text de fonte restricted/derived_only ao embedding pipeline.

### Admin / RAG Playground

A página `/knowledge` agora contém:
- overview;
- Collections;
- Assets;
- matriz Agent × Knowledge;
- RAG Playground;
- botão de geração de embeddings pendentes.

O playground chama `POST /admin/knowledge_search` na Edge Function `mindagent-knowledge`.
A rota valida sessão/admin, resolve retrieval server-side e tenta busca híbrida quando há embedding da query, com fallback lexical.

Existe a persona técnica `knowledge_admin`, invisível na matriz normal, com acesso interno às 22 collections para teste administrativo. Ela não representa agente público.

## Piloto de livro em texto integral (30/09/2026)

Relatório completo: `docs/KNOWLEDGE_PILOTO_LIVRO.md`.

- Fonte `6b61c548-70c9-4d23-ba5e-ec12a6bfa147` (Henrich, *The Secret of Our Success*): `full_text`, `direitos_uso = unknown`, `mind_only`, `status_ingestao = processing`.
- No banco: 18 locais (PDF mestre + 17 arquivos de parte), 22 itens de inventário (4 cópias idênticas excluídas), 138 seções hierárquicas, `page_map` de 456 páginas. O texto canônico está parcial (308.000 de 1.140.013 caracteres) e há 0 chunks.
- A carga foi interrompida pela camada de segurança do Claude Code por causa da procedência da cópia. A decisão está pendente com a Adriana e registrada em `pendencia_decisao`.
- Proposta ainda não aplicada: `docs/sql/knowledge-livro/proposta_busca_global_com_chunks.sql` (põe chunks de fontes `full_text` na fila de embeddings e na busca global, sem criar objetos novos).
- Pipeline reaproveitável: `scripts/infra/knowledge-livro/`.

## Próxima ordem

1. Gerar embeddings dos insights derivados pelo fluxo autenticado do Admin.
2. Resolver reference leads prioritários com fontes primárias.
3. Definir, por fonte/insight, o que Adriana quer promover de `mind_only` para `mind_public`.
4. Rodar typecheck/build final do admin e revisar a branch.
5. Gerar a migration canônica do schema pelo workflow Supabase CLI.
6. Só então propor merge.
7. Escalar inventário/ingestão do Drive.

## Pendências técnicas

- O schema já foi alterado em produção via SQL iterativo. Ainda falta gerar/registrar a migration canônica no repo pelo workflow Supabase CLI, sem inventar filename.
- O frontend da branch ainda precisa de typecheck/build final após o RAG Playground.
- Embeddings ainda precisam ser gerados para os novos insights pelo fluxo autenticado.
- O retrieval global está implementado e testado isoladamente, mas ainda não foi conectado ao runtime dos agentes existentes.
- Advisors foram executados. O alerta `RLS enabled no policy` nos novos objetos é esperado no desenho fechado por service-role/backend; não foram abertas policies para anon/authenticated.
- Índices novos aparecem como “unused” porque o corpus/control plane acabou de ser criado; não remover até existir workload real.
