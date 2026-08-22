# MIND INTELLIGENCE — GLOSSARY

Use estes termos de forma consistente em código, migrations, docs e prompts.

## Agent
Runtime que executa decisões através de linguagem natural e tools. Não é sinônimo de prompt, memória ou playbook.

## Agent Profile
Configuração contextual de um base agent para um objetivo/produto, combinando product scope, context profile, playbook, capabilities, knowledge scope, action scope, tools e permissions.

Ex.: `sales_summit`, `concierge_summit`.

## Agent API
Interface semântica que esconde a topologia física do banco dos agents. Composta principalmente por Functions/RPCs/tools estreitas.

## Base Context
Conjunto pequeno de contexto essencial carregado quase sempre: pessoa, relação, summary, recent messages, active intelligence, scope, open work relevante.

## Capability
O que um agent sabe fazer, por exemplo: sell, recommend, research, record_intelligence, resolve_support.

Não confundir com autorização.

## Action Scope
O que um profile está autorizado a alterar/fazer. Ex.: pode criar CRM task, mas não aplicar desconto acima de limite.

## Knowledge Scope
O que um profile pode consultar/conhecer.

## Context Planner
Mecanismo que decide qual contexto adicional é necessário para o turno atual. V1 pode ser determinístico ou structured output simples.

## Just-in-time Retrieval
Busca de contexto apenas quando necessário para a tarefa/turno, em vez de carregar tudo no prompt.

## Deep Memory
Histórico antigo/detalhado consultado sob demanda.

## Deep Research
Pesquisa mais ampla, tipicamente delegada ao Researcher, com fontes/caveats.

## Intelligence
Representação do que sabemos/inferimos sobre pessoa, relação e situação. Inclui facts, insights, intents, summaries e product fit.

## Fact
Informação objetivamente conhecida/verificada, com provenance.

## Insight
Inferência útil com confidence/provenance, por exemplo pain, objection, preference, buying_signal.

## Intent
Sinal transitório de intenção/routing, por exemplo sales_b2b, support, event_navigation.

## Product Fit
Avaliação de aderência/intenção de pessoa a produto/run, com evidência.

## Summary
Compressão de histórico/relação válida até determinado momento. Não substitui evidência original.

## Playbook
Competência profissional codificada: principles, stages, moves, objection strategies, guardrails, examples. Não é script rígido.

## Move
Estratégia/tática selecionável dentro do playbook para avançar o objetivo atual.

## Guardrail
Limite/regra que restringe comportamento, por exemplo não inventar preço, desconto máximo, escalada obrigatória.

## Decisioning
Camada que escolhe o melhor move/next action para a situação atual usando intelligence, playbook e policies.

## Policy
Regra dura/determinística que restringe ou obriga comportamento.

## Decision
Registro estruturado da escolha operacional feita em um turno/run.

## Next Best Action
Próxima ação recomendada/pendente para pessoa/deal/relationship.

## Canonical Entity
Representação única e autoritativa de uma entidade global, por exemplo `people.people` para pessoa.

## Person
Identidade humana canônica global.

## CRM Contact
Relação comercial de uma person com Mind; não identidade global.

## Organization
Organização global/institucional.

## CRM Company
Representação comercial/CRM de empresa; pode referenciar organization.

## Product Family
Linha de produto: Summit, Institute, Events, Dash.

## Product
Identidade canônica duradoura, por exemplo Mind Summit.

## Product Run
Execução concreta de um produto: edition, cohort, delivery ou version. Ex.: Mind Summit 2026.

## Facet
Estrutura específica de domínio que estende uma entidade global sem duplicá-la. Ex.: `summit.editions` facet de `catalog.product_runs`.

## Offer
Forma comercial específica de adquirir/receber um product run. Ex.: VIP.

## Pricing Period
Janela de preço/lote.

## Offer Price
Preço de uma offer em determinado pricing period.

## Access Right
Direito efetivo de acesso/uso derivado de compra, convite, upgrade etc.

## Entry Context
Contexto de entrada na relação/conversa: source, campaign, landing page, UTM, entry point, offer/product hints.

## Conversation
Sessão/linha de conversa em determinado canal/contexto, pertencente ao domínio compartilhado engagement.

## Interaction
Evento não necessariamente textual da jornada: click, page view, purchase, attendance, feedback etc.

## External Ref
Mapeamento de entidade/id interno para provider/external_id.

## Domain Event
Fato operacional relevante emitido pelo sistema, por exemplo `message.received` ou `purchase.completed`.

## Outbox
Fila transacional para garantir efeitos externos confiáveis/idempotentes.

## Agent Run
Execução rastreável de um agent/profile para um turno/tarefa.

## Tool
Operação semântica que agent pode invocar. Tool não deve expor SQL arbitrário.

## Delegation
Um agent/profile chama outro specialist profile para executar tarefa específica.

## Handoff
Transferência explícita para humano/outro fluxo, com contexto suficiente.

## RAG
Retrieval-Augmented Generation. É apenas uma técnica dentro de knowledge/context; Mind Intelligence não é “um RAG”.

## Source of Truth
Sistema/domínio autoritativo para determinado dado.

## Provenance
Origem rastreável de um dado/inferência: sistema, mensagem, documento, evento, agent etc.

## Confidence
Grau de confiança de uma inferência, não substitui verificação factual.

## ADR
Architecture Decision Record: registro de decisão arquitetural, alternativas, impacto e rationale.

## Compatibility Layer
View/RPC/adapter temporário que mantém consumers funcionando durante migração para novo modelo.

## Vertical Slice
Implementação ponta a ponta de uma capacidade real, cobrindo dados → runtime → resposta → memória. Sales Summit é a primeira vertical slice.

## Memory Loop
Processo que transforma turnos/interações em memória útil e atualiza contexto futuro.

## Evals
Testes/métricas sistemáticos de comportamento e qualidade do agent/runtime.