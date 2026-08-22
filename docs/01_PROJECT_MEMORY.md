# MIND INTELLIGENCE — PROJECT MEMORY

Este documento preserva o raciocínio estratégico que originou a arquitetura. Ele existe para evitar que o projeto perca sua intenção conforme pessoas, agentes e conversas mudem.

## 1. Problema que estamos resolvendo

O Mind precisa operar múltiplos agentes e experiências — inicialmente Sales Summit e Concierge Summit, depois Customer Success, Atendimento, Researcher e agentes de outras linhas de produto — sem criar silos de dados, memória ou conhecimento.

O risco observado no protótipo inicial foi exatamente o oposto:
- um runtime de Sales;
- outro runtime de Concierge;
- estruturas paralelas de conversa;
- estruturas de pessoa que competem entre si;
- dados comerciais morando dentro do schema Summit;
- produto e edição misturados;
- conhecimento dividido por conveniência local;
- prompts carregando responsabilidades que deveriam pertencer a dados ou políticas.

O objetivo do Mind Intelligence é transformar isso em uma arquitetura compartilhada e extensível.

## 2. Princípio orientador

A arquitetura não deve seguir o canal nem o agent. Deve seguir as **entidades e capacidades do negócio**.

Uma pessoa é a mesma pessoa no Treble, no app, no HubSpot e no Summit.
Um produto é o mesmo produto para Sales, Concierge e Customer Success.
Conversas em canais diferentes pertencem ao mesmo relacionamento, ainda que possam ser conversations distintas.
Uma evidência científica continua sendo a mesma evidência, independentemente do agent que a consulta.

## 3. O que é compartilhado vs específico

### Compartilhado
- identidade de pessoas e organizações;
- contact points e external refs;
- catálogo de produtos e runs;
- CRM e relação comercial;
- oferta/preço/pagamento/acesso;
- conversas/interações;
- facts, insights, intents, summaries, fit;
- conhecimento/evidência;
- privacy/contactability/suppression;
- playbooks;
- decisioning;
- runtime de agents;
- integrações, auditoria, idempotência, tracing e evals.

### Específico por linha
Cada linha pode ter profundidade própria sem obrigar todas as linhas a usar o mesmo modelo físico.

Summit precisa de agenda, sessões, espaços, reservas e presença.
Institute precisa de cohorts, módulos, aulas, faculty, conclusão e credenciais.
Dash precisa de soluções, metodologias, entregáveis e engagements.
Events pode ser mais simples.

A consistência é exigida na **interface semântica para os agents**, não necessariamente em tabelas idênticas por produto.

## 4. Arquitetura conceitual

A espinha dorsal é:

```text
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
```

Mas a revisão consolidada de agent engineering adiciona duas camadas externas obrigatórias:

```text
BUSINESS OUTCOME
      ↓
BEHAVIOR SPEC
      ↓
EVALS
      ↓
[espinha dorsal acima]
      ↓
OBSERVABILITY + EVAL DATA
      ↺
```

### Data
Fatos brutos e registros operacionais: pessoa, pedido, conversa, sessão, agenda, preço, participação, fonte científica.

### Intelligence
Interpretação persistente e rastreável da relação:
- facts;
- pains/needs/desires/goals;
- interests/preferences;
- objections/constraints;
- buying signals;
- current intent;
- product fit;
- relationship/commercial summaries.

### Playbook
Competência profissional codificada como dados/configuração:
- princípios;
- objetivos;
- estratégias;
- moves;
- objection strategies;
- evidence needs;
- guardrails;
- examples.

Não é script rígido de atendimento.

### Decisioning
Escolha dinâmica do que fazer agora, dadas as circunstâncias.

Exemplo: objeção de preço não deve automaticamente disparar desconto. O sistema deve entender o critério de decisão, o valor percebido e a situação antes de escolher um move.

### Agent
Executa a decisão em linguagem natural ou através de ferramentas.

O agent pode responder, consultar, recomendar, delegar, registrar, criar task ou fazer handoff conforme seu profile e permissões.

### Behavior Spec
Define o que é comportamento excelente antes de prompt, model, playbook ou implementação. Para Sales, ver `docs/11_SALES_AGENT_BEHAVIOR_SPEC.md`.

### Evals
Definem como verificar se o comportamento realmente melhorou ou regrediu. Evals começam antes do primeiro agent target, não no final.

## 5. Context engineering

A arquitetura deliberadamente evita prompts gigantes e carregamento de histórico inteiro.

### Base Context
Pequeno, estável e quase sempre disponível:
- identidade;
- empresa/cargo;
- resumo relevante;
- últimas mensagens;
- insights ativos;
- intent atual;
- product scope;
- deal/ticket aberto quando aplicável.

### Context Planner
V1 pode ser determinístico ou um único structured output. Não precisa ser um mega-agent.

Exemplo:
```json
{
  "needs": [
    "commercial.offer_comparison",
    "summit.relevant_content",
    "people.amy_edmondson"
  ],
  "needs_deep_research": false,
  "needs_old_history": false
}
```

### Just-in-time retrieval
Busca só o necessário para o turno atual através de Agent API semântica.

### Deep memory
Histórico antigo, eventos, cliques e interações de menor frequência entram apenas quando necessários.

### Deep research
Pesquisa científica aprofundada pode ser delegada a Researcher em vez de poluir todo agent com contexto pesado.

### Context manifest / retrieval trace
Cada run deve conseguir registrar quais fontes/records/tools/versões chegaram ao modelo, sem guardar chain-of-thought. Isso permite depurar uma resposta ruim por evidência operacional, não por adivinhação.

## 6. Memória: quente e profunda

### Hot / Base
- identidade;
- company/role;
- summary;
- recent messages;
- active pains/goals/objections/interests;
- current intent;
- product fit;
- open deal/ticket.

### Deep
- conversas antigas;
- todos os cliques/emails;
- histórico de sessões;
- feedback antigo;
- purchases passados;
- documentos extensos.

## 7. Uma pessoa, múltiplas relações

`people.people` é a identidade global.

A mesma pessoa pode simultaneamente ser:
- participante do Summit;
- speaker;
- faculty no Institute;
- cliente;
- lead;
- autor;
- advisor.

Nenhum desses papéis justifica duplicar a pessoa.

`people.contact_points` representa meios/identificadores humanos de contato.
`integrations.external_refs` representa ids de sistemas externos.
`crm.contacts` representa a relação comercial com Mind.
`people.affiliations` representa vínculos institucionais.
`people.product_roles` representa papéis em produtos/runs.

## 8. Produto vs run

A distinção é estrutural:

### Product
Identidade duradoura.
Ex.: Mind Summit.

### Product run
Execução concreta.
Ex.: Mind Summit 2026.

`product_runs` deve ser a chave concreta usada por CRM, commercial, engagement, intelligence, playbooks e facets específicas.

`summit.editions` não cria outra identidade de Summit 2026; é extensão 1:1 daquele run.

## 9. Knowledge não é só RAG

Conhecimento científico não deve ficar passivamente esperando uma pergunta explícita.

O sistema deve conseguir conectar:

```text
need/pain
  ↕
concept
  ↕
session / program / expert / claim / evidence
```

Exemplos de concepts:
- psychological safety;
- burnout;
- wellbeing at work;
- meaning;
- leadership;
- job design;
- resilience.

Claims científicos devem ser estruturados, associados às fontes e ter força/caveats quando apropriado.

A revisão consolidada acrescenta uma regra forte: **structured authoritative truth vem antes de generic vector retrieval**. Preço, agenda, acesso, compra e disponibilidade não devem ser respondidos por embedding quando existe uma fonte estruturada autoritativa.

O pipeline de knowledge deve ser:
source → version/raw snapshot → parse/normalize → classify → validate/provenance → index → retrieval policy → Agent API.

Ver `docs/12_KNOWLEDGE_INGESTION_AND_RETRIEVAL.md`.

## 10. Agent model

Não criar um codebase separado para cada produto.

### Base agents possíveis
- router;
- sales;
- concierge;
- service;
- researcher;
- recommendation worker;
- CRM worker;
- opportunity worker.

### Profiles iniciais
- sales_summit;
- concierge_summit;
- service_default;
- researcher_scientific.

Um profile combina:
- base agent;
- product scope;
- context profile;
- playbook;
- capabilities;
- knowledge scopes;
- action scopes;
- tools;
- permissions.

### Dimensões separadas
Knowledge scope = o que pode conhecer/acessar.
Capability = o que sabe fazer.
Action scope = o que está autorizado a alterar/fazer.

## 11. Delegation

Delegação deve reutilizar o mesmo runtime.

Exemplo:
Sales → `delegate_task(agent_profile=researcher_scientific, task=...)`.

Researcher recebe outras instruções, tools e knowledge scope e retorna resposta estruturada, fontes e caveats.

A persona visível ao usuário pode permanecer a mesma.

## 12. Decisioning V1

Não é necessário criar um segundo LLM/service apenas para decisioning no início.

Um único LLM call pode devolver structured decision + resposta.

Separar em componentes adicionais somente se evals mostrarem ganho real.

## 13. Sales Summit — primeiro vertical slice

O objetivo não é apenas “um bot que responde”. O teste de existência do skeleton do Mind Intelligence é uma pessoa retornar e o sistema continuar a relação.

### Teste de referência
Conversa 1:
“Oi, sou Adriana, trabalho na Empresa X. Queria saber mais sobre o VIP.”

O sistema deve:
- resolver/criar pessoa;
- registrar relação com Empresa X;
- registrar interesse VIP;
- registrar intent de vendas;
- responder com contexto comercial correto.

Conversa 2, depois:
“Oi, voltei. Minha preocupação é que dois dias fora é muito.”

O agent deve automaticamente saber:
- quem é a pessoa;
- empresa X;
- que estava avaliando VIP;
- histórico da relação;
- interesse no Summit;
- nova objeção = tempo;

e responder sem reiniciar a descoberta.

Além de “funcionar”, Sales deve satisfazer a especificação de comportamento e golden evals. Um vendedor tecnicamente integrado porém comercialmente medíocre é falha do projeto.

## 14. Concierge Summit

Concierge deve reutilizar o mesmo core e adicionar capacidades específicas:
- agenda;
- session recommendations;
- reservas;
- attendance;
- feedback por palestra;
- NPS;
- materiais;
- planejamento do segundo dia;
- registro do que a pessoa foi, quis ir e não conseguiu;
- oportunidade comercial quando relevante.

A conversa não deve ser invasivamente diagnóstica. Pode aprender objetivos/dor suficiente para conectar conteúdo útil, mas não transformar experiência em interrogatório.

A conversa do app pode ser distinta da WhatsApp conversation; continuidade vem da mesma pessoa e intelligence compartilhada.

## 15. Service / CS / Support

Suporte e Customer Success devem compartilhar relação, histórico e oportunidade.

Support pode resolver um problema e depois recomendar/handoff para Sales.
CS deve entender goal, use, risk e opportunity.

Capacidades de recommendation e handoff devem ser reutilizáveis por Concierge, Sales, Support e CS.

## 16. Integrações e source of truth

Integrações devem usar `integrations.external_refs` para mapear entidade interna ↔ provider/external_id.

`webhook_events` deve preservar payload bruto antes de processamento quando apropriado.

Eventos de domínio podem incluir:
- person.identified;
- message.received;
- lead.objection_detected;
- lead.intent_changed;
- purchase.completed;
- session.attended;
- support.issue_opened;
- opportunity.detected.

`ops.outbox_events` suporta padrão transactional outbox para sincronização externa.

A matriz definitiva de source of truth deve ser explicitamente validada antes da migração. Hipótese atual: Supabase é autoridade para catálogo/knowledge/intelligence; HubSpot deve provavelmente permanecer autoridade operacional para owner/stage do CRM.

## 17. Segurança, privacy e outbound

Princípios:
- public schema quase vazio;
- schemas internos não expostos sem necessidade;
- schema `api` apenas para views/RPCs seguras quando necessário;
- RLS em objetos expostos;
- grants mínimos;
- LLM/browser nunca recebe credencial privilegiada;
- Edge Functions guardam secrets;
- SECURITY INVOKER por padrão quando possível;
- SECURITY DEFINER só com intenção e grants/search_path revisados;
- ações externas idempotentes/auditáveis;
- dev/staging antes de produção.

Outbound não é “inbound ao contrário”. Ele reutiliza Sales runtime, mas adiciona trigger, eligibility, why-now, contactability/consent/suppression, cadence/send state e coordenação com humano/owner.

LLM nunca pode sobrescrever uma suppression/contactability negativa.

Ver `docs/14_OUTBOUND_WORKFLOW.md`.

## 18. Evals e observability

Evals não são trabalho futuro. Eles começam antes do primeiro agent target.

Dimensões:
- accuracy;
- relevance;
- naturalness;
- uso correto de contexto;
- preço/produto corretos;
- estratégia de objeção;
- conversão/resolução;
- não inventar fatos;
- não perguntar informação já conhecida;
- tool/retrieval discipline;
- memory extraction quality;
- human feedback.

Também devemos testar variantes de contexto:
- 5 vs 10 mensagens recentes;
- summary + recent vs full history;
- context profiles;
- playbook versions;
- Sales sozinho vs Sales + Researcher.

Agent runs devem guardar model/prompt/playbook/context versions + tool/retrieval trace suficiente para reproduzir operationalmente uma resposta ruim.

Ver `docs/13_EVALS_AND_OBSERVABILITY.md`.

## 19. Filosofia de implementação

1. Preservar comportamento bom, não topologia acidental.
2. Primeiro vertical completa, depois expansão.
3. Uma tarefa de implementação por vez.
4. Mudança arquitetural precisa ser explícita.
5. Não overbuildar componentes futuros.
6. Manter compatibilidade conceitual com Concierge desde o Sales.
7. Arquitetar contactability/privacy cedo para não retrofit outbound.
8. Definir comportamento e evals antes de otimizar prompt/model.
9. Transformar arquitetura em contracts/tests, não só documentos.
10. Commit/checkpoint em marcos importantes.
11. Nunca depender da memória de uma pessoa ou agent para manter a arquitetura.

## 20. Divisão de trabalho esperada

### Guia/arquitetura
Mantém macro, escopo, behavior specs, acceptance tests, decisões e documentação.

### Coding agent
Executa implementação no repositório e deve parar diante de conflito arquitetural.

### Supabase
Banco, Functions, runtime server-side e integrações.

### Treble
Canal real de vendas / WhatsApp.

### App
Canal do Concierge.

## 21. Estado de prioridade consolidado

A ordem operacional consolidada é:

1. checkpoint;
2. documentação/guardrails + behavior specs + eval baseline;
3. current-to-target + migration plan;
4. ambientes/security/contracts executáveis;
5. identity + catalog;
6. Summit + commercial + knowledge mínimo;
7. engagement + intelligence + CRM core;
8. Sales Summit Inbound E2E;
9. Concierge Summit;
10. Sales Outbound;
11. Service/CS/Support + Researcher;
12. Institute/Dash/Events;
13. advanced optimization.

Evals, observability, memory quality, knowledge quality e security são trilhas contínuas, não fases finais.

Consulte `docs/00_EXECUTION_CONTROL.md` para o estado atual exato.

## 22. Nota de revisão de agent engineering — 2026-08-22

Após a primeira documentação da arquitetura, foi feita uma revisão explícita com foco em sistemas agentic e Vibe Code. A conclusão foi:

- a plataforma de dados estava bem desenhada;
- o maior risco remanescente era construir infraestrutura elegante sem especificar suficientemente a excelência do agente;
- por isso Behavior Specs e Evals foram movidos para o início;
- knowledge passou a ter ingestão/versionamento/authority/retrieval policy explícitos;
- contact points foram separados de external refs;
- privacy/contactability/suppression virou requisito fundacional antes de outbound;
- outbound foi definido como workflow, não um segundo Sales brain;
- context manifests/retrieval traces passaram a ser obrigatórios para observabilidade;
- `intelligence.facts` deixou de poder virar cópia genérica do banco;
- shared engagement foi esclarecido como domínio comum, não uma única conversation infinita.

Essas não são otimizações opcionais. Elas fazem parte da intenção arquitetural consolidada.