# MIND INTELLIGENCE — READ ME FIRST

Leia este arquivo antes de alterar qualquer parte do projeto.

## O que este projeto é

Mind Intelligence é a camada compartilhada de inteligência, contexto, memória e operação que serve múltiplos agentes e produtos do Mind.

Os agentes não possuem bases independentes. Sales, Concierge, Customer Success, Atendimento e Researcher compartilham o mesmo núcleo de dados e contratos, mudando principalmente profile, playbook, capabilities, knowledge scope e action scope.

## Prioridade operacional atual

1. Sales Summit funcional end-to-end.
2. Concierge Summit funcional na sequência imediata.
3. Depois: Customer Success, Atendimento, Researcher, Institute, Dash e Events.

A prioridade atual NÃO autoriza atalhos que criem dívida estrutural ou duplicação de entidades.

## Fluxo conceitual congelado

DATA -> INTELLIGENCE -> PLAYBOOK -> DECISIONING -> AGENT -> ACTION -> MEMORY LOOP

- Intelligence = o que sabemos sobre a pessoa, relação e realidade.
- Playbook = como um ótimo profissional deve pensar e agir.
- Decisioning = qual estratégia/move faz sentido agora.
- Agent = executa a decisão em linguagem natural e/ou ações.

## Regra central de contexto

O agente não conhece a topologia do Supabase.

O sistema traz automaticamente o contexto essencial e oferece ferramentas semânticas para buscar contexto adicional quando necessário.

Padrão:

BASE CONTEXT + CONTEXT PLANNER + JUST-IN-TIME RETRIEVAL

Não carregar todo o banco no prompt.

## Non-negotiables

1. Não criar uma segunda representação de uma pessoa. A identidade canônica futura é `people.people`.
2. `crm.contacts` representa relação comercial; não substitui a pessoa canônica.
3. Produto e execução concreta são coisas diferentes: `catalog.products` != `catalog.product_runs`.
4. Mind Summit 2026 deve existir como um único `product_run_id`; outras tabelas apenas referenciam essa identidade.
5. Não duplicar person, organization, product ou concept por canal, agente ou produto.
6. Preço, lote, disponibilidade e regra comercial não têm prompt como fonte da verdade. Devem vir do domínio `commercial`.
7. Ciência/evidência não deve ser misturada com copy de produto como fonte da verdade. Conhecimento científico pertence a `knowledge`.
8. Inferência de IA nunca vira fato silenciosamente. Deve armazenar source, confidence e provenance.
9. LLMs usam Agent API / Functions semânticas; SQL livre não é a interface principal do agente.
10. Não criar tabela nova antes de verificar se a entidade já existe em algum domínio compartilhado.
11. Mudança estrutural de banco deve ser versionada por migration e testada.
12. Não alterar schema de produção manualmente pelo Dashboard como método normal de desenvolvimento.
13. Mudança destrutiva exige checkpoint e plano de rollback.
14. Não desenvolver ou testar diretamente em produção.
15. Service role e outros segredos privilegiados nunca vão para frontend.
16. Função pública sem autenticação explícita deve ser tratada como risco e justificada.
17. Escritas em sistemas externos devem ser idempotentes e auditáveis.
18. Não criar runtimes paralelos de conversa; `engagement` é a camada compartilhada de conversas/interações.
19. Capabilities compartilháveis não devem virar lógica exclusiva de um agente sem necessidade real.
20. Mudança de arquitetura não pode ser feita silenciosamente. Primeiro registrar decisão e impacto.

## Antes de começar qualquer tarefa

Leia, nesta ordem:

1. `README_FIRST.md`
2. `docs/00_EXECUTION_CONTROL.md`
3. `docs/00_ARCHITECTURE.md`
4. o documento específico do domínio que será alterado

## Regra para coding agents

Coding agents são executores técnicos, não donos da arquitetura.

Se a tarefa parecer exigir mudança estrutural não prevista:

1. pare;
2. descreva o conflito;
3. proponha opções;
4. não implemente a mudança até aprovação.

## Fonte de verdade de execução

`docs/00_EXECUTION_CONTROL.md` informa:
- objetivo atual;
- etapa atual;
- o que está concluído;
- o que está proibido mexer;
- próxima ação.

Se houver divergência entre uma conversa antiga e esse documento, o documento versionado no repositório prevalece até revisão explícita.