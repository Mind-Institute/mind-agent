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
- Livro com licença restrita = `derived_only`: texto bruto não entra no corpus; processar capítulo por capítulo.
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

Nove fontes registradas no inventário e na fonte canônica:

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

Fonte é `licensed_restricted + derived_only + mind_only`.
Há aviso explícito no arquivo proibindo introdução do livro em retrieval system.
Não persistir texto bruto.

Os 12 capítulos foram registrados como seções e locations.
Capítulo 1, **Wellbeing at Work: An Overview**, foi processado:
- 1/12 capítulos concluídos;
- 20 insights derivados e parafraseados;
- raw text não armazenado;
- reference leads criados para estudos que precisam ser verificados na fonte primária.

## Próxima ordem

1. Processar capítulos 2–12 do De Neve em `derived_only`.
2. Processar as demais fontes piloto, respeitando rights/ingest_policy.
3. Resolver reference leads importantes com fontes primárias.
4. Implementar retrieval RPC que faça filtro por agente/collection/acesso antes de lexical/vector search.
5. Implementar RAG Playground no admin.
6. Rodar DB advisors e testes de segurança.
7. Rodar typecheck/build do admin e revisar a branch.
8. Só então propor merge.
9. Escalar inventário/ingestão do Drive.

## Pendências técnicas

- O schema já foi alterado em produção via SQL iterativo. Ainda falta gerar/registrar a migration canônica no repo pelo workflow Supabase CLI, sem inventar filename.
- O frontend da branch ainda precisa de typecheck/build.
- Embeddings ainda não foram gerados para os novos insights.
- Retrieval global ainda não está conectado ao runtime existente.
