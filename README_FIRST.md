# MIND INTELLIGENCE — READ ME FIRST

> Este arquivo é a porta de entrada obrigatória do projeto. Leia antes de alterar código, banco, prompts, integrações ou arquitetura.

## 1. O que este projeto é

Mind Intelligence é a camada compartilhada de **dados, contexto, memória, conhecimento, decisão e operação de agentes** do Mind.

Ela não é “o bot do Summit”, “o bot do Concierge” ou “o bot de vendas”. Esses são **profiles/capacidades que executam sobre um mesmo core**.

O objetivo é permitir que Sales, Concierge, Customer Success, Atendimento, Researcher e futuros agentes do Mind compartilhem:

- a mesma identidade de pessoa;
- o mesmo catálogo de produtos;
- a mesma memória de relacionamento;
- a mesma camada de inteligência;
- a mesma base de conhecimento;
- contratos de ferramentas consistentes;
- regras de segurança, privacidade e auditoria comuns.

A arquitetura deve suportar várias linhas de produto sem duplicar entidades centrais nem criar um banco por agente.

## 2. Prioridade operacional atual

### Entrega 1 — agora
**Sales Summit 2026 funcional end-to-end**, conectado ao Treble, com identidade, memória, contexto comercial correto, comportamento comercial excelente, resposta, persistência de conversa, captura de inteligência e evals críticos.

### Entrega 2 — imediatamente depois
**Concierge Summit 2026**, reutilizando o mesmo core compartilhado de identidade, engagement, intelligence, knowledge e agent runtime.

### Expansão posterior
Sales Outbound, Customer Success, Atendimento, Researcher, Institute, Dash e Events.

A prioridade atual **não autoriza atalhos que criem uma segunda arquitetura**. O objetivo é construir a primeira vertical completa sobre a arquitetura definitiva.

## 3. Hierarquia de documentos

Quando houver dúvida, use esta ordem de autoridade:

1. `README_FIRST.md` — regras de entrada e governança.
2. `docs/00_EXECUTION_CONTROL.md` — onde estamos AGORA e o que pode/não pode ser feito.
3. `docs/00_ARCHITECTURE.md` — arquitetura normativa de alto nível.
4. `docs/01_PROJECT_MEMORY.md` — memória estratégica detalhada e racional das decisões.
5. Documentos específicos de domínio (`02_...`, `03_...`, etc.).
6. Behavior specs e eval specs aplicáveis ao agente.
7. ADRs / decisões explícitas versionadas.
8. Código, contracts, tests e migrations vigentes.
9. Conversas antigas, prompts avulsos e notas pessoais — são contexto, não fonte normativa.

Se uma conversa antiga divergir da documentação versionada, **não escolha silenciosamente**. Sinalize o conflito e proponha atualização da documentação.

## 4. Fluxo conceitual congelado

```text
BUSINESS OUTCOME
      ↓
BEHAVIOR SPEC
      ↓
EVALS
      ↓
DATA
  ↓
INTELLIGENCE
  ↓
PLAYBOOK
  ↓
DECISIONING
  ↓
AGENT
  ↓
ACTION
  ↓
MEMORY LOOP
      ↓
OBSERVABILITY + EVAL DATA
      ↺
```

A espinha dorsal continua sendo:

`DATA -> INTELLIGENCE -> PLAYBOOK -> DECISIONING -> AGENT -> ACTION -> MEMORY LOOP`

Mas comportamento esperado e evals existem **antes** da implementação do agente.

### Intelligence
O que sabemos sobre a pessoa, empresa, relação, situação, necessidade, intenção e fit.

### Playbook
Como um excelente profissional deveria pensar e agir naquele domínio. Contém princípios, estratégias, moves, objection strategies, guardrails e exemplos.

### Decisioning
Qual estratégia/move/next best action faz sentido **agora**, considerando contexto, policies e playbook.

### Agent
Executa a decisão em linguagem natural e/ou ferramentas. O agent não é a memória e não é a estratégia em si.

### Behavior Spec
Define o que é comportamento excelente antes de escolher prompt, modelo ou playbook.

### Evals
Transformam qualidade de agente em critérios testáveis e regressões, não feeling.

## 5. Princípio central de contexto

> **O agente não conhece a topologia do Supabase. O sistema traz automaticamente o contexto essencial, e o agente dispõe de ferramentas simples para descobrir contexto adicional quando seu raciocínio exigir.**

Padrão:

```text
BASE CONTEXT
+ CONTEXT PLANNER
+ JUST-IN-TIME RETRIEVAL
+ DEEP MEMORY quando necessário
+ DEEP RESEARCH quando necessário
+ CONTEXT/RETRIEVAL TRACE para observabilidade
```

Não resolver falta de contexto carregando “o banco inteiro” no prompt.

## 6. Modelo mental do sistema

```text
DATABASE / SUPABASE
= memória e fonte estruturada

DATABASE FUNCTIONS / RPCs
= perguntas inteligentes sobre essa memória

EDGE FUNCTIONS
= coordenação/orquestração e integrações

LLM + PROFILE + PLAYBOOK + TOOLS
= agent runtime

QUEUE / BACKGROUND
= trabalho que não precisa bloquear a resposta

EVALS + TRACING
= mecanismo contínuo de qualidade e regressão
```

## 7. Famílias de produto congeladas

```text
SUMMIT
└── Mind Summit
    ├── Mind Summit 2025
    ├── Mind Summit 2026
    └── futuras edições

INSTITUTE
├── Formação Estratégica em Bem-Estar no Trabalho e Liderança Positiva
├── Significado no Trabalho
├── Segurança Psicológica
├── Mind Journey
└── On Demand

EVENTS
├── Oxford no Conselho
└── futuros eventos

DASH
├── Mind Dash
└── outros produtos/serviços de consultoria
```

Consultoria pertence a Dash. Não criar família “Consulting”. Não existe uma família “Sales Mind”.

## 8. Distinções que não podem se perder

### Pessoa ≠ contato CRM
`people.people` é a identidade canônica global.
`crm.contacts` é a relação comercial daquela pessoa com o Mind.

### Contact point ≠ external system id
`people.contact_points` guarda email/telefone/outros meios humanos de contato e seu estado de verificação/validade.
`integrations.external_refs` guarda IDs de entidades em HubSpot, Treble, Eduzz etc.

### Produto ≠ edição/turma/entrega
`catalog.products` é identidade canônica do produto.
`catalog.product_runs` é uma execução concreta (edição, cohort, delivery, version).

Exemplo: “Mind Summit” é produto. “Mind Summit 2026” é `product_run`.

### Conhecimento científico ≠ copy de produto
Evidência, conceitos e claims pertencem a `knowledge`.
Posicionamento, FAQ, proof points comerciais e proposta de valor pertencem a `catalog.product_content` / domínios comerciais apropriados.

### Structured truth ≠ generic RAG
Preço, agenda, acesso, compra e disponibilidade devem vir de fontes estruturadas autoritativas quando existentes. Embeddings não são autoridade universal.

### Fato ≠ inferência
Fato conhecido e insight inferido devem ser armazenados separadamente. Inferência de IA exige provenance e confidence.

### Canonical domain ≠ intelligence.facts
Não duplicar email, compra, preço ou affiliation em `intelligence.facts` quando já existe uma representação canônica melhor.

### Canal ≠ pessoa
Treble, app, site e HubSpot são pontos de contato. Eles não criam identidades independentes.

### Shared engagement ≠ uma conversa infinita
Uma pessoa pode ter múltiplas conversations por canal. Continuidade vem de identity, summaries e intelligence compartilhados.

### Inbound Sales ≠ Outbound workflow
Outbound reutiliza Sales intelligence/runtime, mas adiciona trigger, eligibility, contactability/suppression, cadence e send state.

## 9. Non-negotiables

1. Não criar uma segunda representação canônica de uma pessoa.
2. Não tratar contato do CRM como identidade global.
3. Não confundir contact point com provider external id.
4. Não criar um novo produto porque existe uma nova edição/turma.
5. Não duplicar person, organization, product, product_run ou concept por canal/agente.
6. Não colocar preço, lote, disponibilidade ou autoridade de desconto em prompt como fonte da verdade.
7. Não misturar ciência/evidência e copy comercial como uma única fonte.
8. Não usar embeddings/vector search como fonte universal quando structured authoritative data existe.
9. Inferência de IA nunca vira fato silenciosamente; guardar source, confidence e provenance.
10. `intelligence.facts` não duplica silenciosamente domínios canônicos.
11. LLMs usam Agent API / Functions semânticas; SQL livre não é a interface principal do agente.
12. Não criar tabela nova antes de verificar se a entidade já existe e qual domínio é responsável por ela.
13. Mudança estrutural de banco deve ser versionada por migration, validada e documentada.
14. Não alterar schema de produção manualmente pelo Dashboard como prática de desenvolvimento.
15. Mudança destrutiva exige checkpoint, plano de migração e rollback/recovery.
16. Produção não é ambiente de desenvolvimento.
17. Service-role e segredos privilegiados nunca vão para frontend/client.
18. Função pública sem autenticação explícita é risco e deve ter justificativa/mecanismo de segurança documentado.
19. Escritas externas (HubSpot, Treble, email etc.) devem ser idempotentes e auditáveis.
20. Não criar runtimes paralelos de identidade/memória por canal; `engagement` é compartilhado.
21. Capability compartilhável não deve virar lógica exclusiva de um único agente sem razão real.
22. Não criar abstração genérica prematuramente só para “ficar elegante”. Product schemas podem ser específicos.
23. Não mudar arquitetura silenciosamente. Mudança arquitetural exige registro explícito de impacto/decisão.
24. Não preservar estrutura ruim só porque já existe no protótipo; preservar comportamento/dados úteis, não topologia acidental.
25. Não refatorar áreas fora do escopo da tarefa atual “aproveitando que está aqui”.
26. Não implementar cinco chamadas LLM síncronas quando uma chamada estruturada segura resolve a versão atual.
27. Não construir o universo inteiro antes de validar a primeira vertical end-to-end.
28. Não considerar um agent “bom” porque conversa de forma convincente: behavior spec + evals são obrigatórios.
29. Não deixar LLM autorizar outbound quando contactability/suppression determinística bloquear.
30. Não alterar expected behavior de golden eval apenas para fazer uma implementação falha passar.

## 10. Situação do sistema legado/protótipo

O sistema começou como protótipo e já contém peças valiosas, mas também duplicações e topologia que não devem limitar o target.

Princípio de migração:

> **Reaproveitar comportamento e dados bons. Não tratar o endereço atual das coisas como restrição arquitetural.**

Peças atualmente conhecidas como úteis incluem:
- Sales/Treble com guardrails comerciais e fluxo end-to-end já funcional;
- Concierge com identidade/sessão/personalização mais madura;
- programação do Summit;
- palestrantes;
- preços, lotes, condições e desconto por volume;
- webhooks e contratos de integração já testados.

Há também gaps de recuperação importantes já documentados no checkpoint, incluindo migrations sem arquivo, configs curadas fora de migrations, dump estrutural ainda ausente e assets/secrets não capturados.

O estado real deve sempre ser conferido em `docs/07_CURRENT_STATE_2026-08-22.md`, `docs/00_EXECUTION_CONTROL.md` e no checkpoint vigente antes de uma migração.

## 11. Antes de começar qualquer tarefa

Leia, nesta ordem:

1. `README_FIRST.md`
2. `docs/00_EXECUTION_CONTROL.md`
3. `docs/00_ARCHITECTURE.md`
4. o documento específico do domínio alterado
5. behavior/eval specs aplicáveis
6. ADRs relacionados, se existirem

Depois responda internamente:
- Qual é a entrega atual?
- Esta mudança está dentro do escopo atual?
- Qual é a fonte de verdade deste dado?
- Estou criando uma entidade que já existe?
- Estou mudando arquitetura ou apenas implementando-a?
- Qual behavior spec / eval case valida esta mudança?
- Existe risco de produção, migração, privacidade ou ação externa?

## 12. Regra para coding agents

Coding agents são **executores técnicos**, não donos da arquitetura.

Se uma tarefa aparentar exigir entidade, schema, runtime, source of truth ou padrão arquitetural não previsto:

1. pare antes de implementar;
2. descreva o conflito exato;
3. explique por que o target atual não cobre o caso;
4. proponha as menores alternativas viáveis;
5. descreva impacto/migração;
6. aguarde aprovação explícita.

## 13. Regra para humanos

Nenhum colaborador deve alterar produção “só para testar”.

Quando houver dúvida sobre onde algo pertence, **não criar uma tabela provisória**. Registrar a dúvida e decidir o domínio primeiro.

## 14. Onde encontrar o detalhe

- Visão e arquitetura: `docs/00_ARCHITECTURE.md`
- Memória estratégica e racional: `docs/01_PROJECT_MEMORY.md`
- Modelo de dados: `docs/02_TARGET_DATA_MODEL.md`
- Agent runtime / contexto / memória: `docs/03_AGENT_RUNTIME_CONTEXT_MEMORY.md`
- Produtos e comercial: `docs/04_PRODUCT_AND_COMMERCIAL_MODEL.md`
- Roadmap e acceptance tests: `docs/05_IMPLEMENTATION_ROADMAP.md`
- Segurança e protocolo de mudança: `docs/06_SECURITY_AND_CHANGE_PROTOCOL.md`
- Fotografia do sistema atual: `docs/07_CURRENT_STATE_2026-08-22.md`
- Agent API e contratos: `docs/08_AGENT_CONTRACTS.md`
- Source of truth (draft até validação): `docs/09_SOURCE_OF_TRUTH_DRAFT.md`
- Glossário: `docs/10_GLOSSARY.md`
- Sales Behavior Spec: `docs/11_SALES_AGENT_BEHAVIOR_SPEC.md`
- Knowledge ingestion & retrieval: `docs/12_KNOWLEDGE_INGESTION_AND_RETRIEVAL.md`
- Evals & observability: `docs/13_EVALS_AND_OBSERVABILITY.md`
- Outbound workflow: `docs/14_OUTBOUND_WORKFLOW.md`
- Blueprint visual: `docs/architecture-blueprint.html`
- Estado de execução: `docs/00_EXECUTION_CONTROL.md`

## 15. Regra final

**O repositório deve carregar a memória do projeto.**

A arquitetura não deve depender da memória de Adriana, ChatGPT, Claude, Codex ou qualquer pessoa individual. O objetivo destes documentos é permitir que outra pessoa ou outro agente entenda não só *o que* construir, mas *por que* as decisões foram tomadas, **como saber se o agente ficou bom**, e quais decisões não devem ser reabertas sem motivo.