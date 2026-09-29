# Mind Intelligence — direção do sistema e backlog vivo

**Decisões iniciais:** 29/09/2026  
**Estado:** documento vivo; direção, não especificação final.

## 1. Princípio de evolução

Este documento registra a direção que hoje parece mais coerente para o Mind Intelligence e o backlog que nasce do uso real do sistema.

A visão **não é definitiva**. Ela deve mudar à medida que amadurecemos o uso do produto, descobrimos limites, percebemos duplicações, encontramos melhores abstrações e aprendemos quais capacidades realmente geram valor.

Por isso, a regra é:

> **usar → observar → questionar → revisar a arquitetura → atualizar o backlog → construir o próximo caso real**

A cada dia de desenvolvimento relevante, este documento deve ser relido e questionado. Decisões aqui podem ser mantidas, refinadas, substituídas ou descartadas. O objetivo não é proteger uma arquitetura; é preservar coerência enquanto o sistema evolui.

Consequência prática:

> **não criar arquitetura vazia por antecipação.**

Uma nova tabela, schema, agente, skill, pipeline ou camada só deve ser materializada quando houver um caso de uso real que justifique sua existência. A direção arquitetural orienta o desenho; ela não vira automaticamente backlog de implementação.

---

## 2. Direção arquitetural atual

A direção que queremos explorar é:

```text
Sources / Data / Events
        ↓
Intelligence
        ↓
Playbooks
        ↓
Skills
        ↓
Agents
        ↓
Tools
        ↓
Actions
        ↓
Outcomes
        ↓
Learning
        ↺
melhores Intelligence / Playbooks / Skills
```

Essa sequência é conceitual. Nem toda camada precisa virar uma tabela ou serviço separado.

### Definições canônicas

**Intelligence = o que o sistema sabe.**  
Fatos, contexto, conhecimento, histórico e inteligência derivada que podem sustentar decisões.

**Playbook = como um excelente profissional pensa e age em um domínio.**  
Princípios, heurísticas, critérios, cenários, trade-offs e condutas. Hoje muitos playbooks vivem como prompts versionados em `agentes.prompts`.

**Skill = algo que o sistema sabe fazer.**  
Um processo/capacidade executável, com começo e fim, que pode combinar Intelligence, Playbooks e Tools.

**Agent = quem decide qual Skill usar e coordena a execução.**  
O Agent não precisa carregar toda a lógica em um prompt monolítico.

**Tool = com o que o sistema observa ou age.**  
Ex.: HubSpot, Supabase, busca em conhecimento, gravação de memória, tarefas, notas, arquivos.

**Outcome = o que aconteceu depois da ação.**  
Resposta, avanço de deal, reunião marcada, conversão, não resposta, perda, mudança de estágio etc.

**Learning = o que aprendemos a partir dos outcomes.**  
Pode melhorar Intelligence, Playbooks ou Skills, mas mudanças materiais não devem se auto-promover sem avaliação.

---

## 3. Intelligence: direção atual

A arquitetura atual já distingue grandes universos de conhecimento. Essa separação continua útil, mas deve permanecer plástica.

### Global Knowledge
Ciência, teoria, evidência, metodologia Mind e conhecimento perene.

### Business Strategy
Conhecimento sobre estratégia e gestão do negócio: modelos de negócio, pricing, growth, canais, finanças, vendas, marketing, operações, gestão etc.

### Business Intelligence
Conhecimento factual e operacional do próprio Mind: produtos, ofertas, regras, eventos, programas, políticas, operação e dados de negócio.

### Customer Intelligence
O que sabemos sobre uma pessoa: perfil, objetivos, interesses, preferências, JTBD, restrições, stakeholders citados, memórias e contexto.

Princípio já decidido:

> **conversa é evidência; análise é interpretação; memória é o que vale reutilizar; contexto é montado quando necessário.**

A conversa bruta permanece em `engagement`; análises em `intelligence.analise_conversa`; memória durável em `intelligence.participante_memoria`.

### Account Intelligence — direção
O que aprendemos sobre uma empresa/conta: prioridades organizacionais, ciclo orçamentário, estrutura decisória, contexto da relação com o Mind, stakeholders e histórico relevante.

Isto é uma **necessidade conceitual identificada**, não uma autorização para criar agora um novo schema ou tabela.

### Opportunity / Deal Intelligence — direção
O que sabemos sobre uma oportunidade específica: hipótese de necessidade, produto, estágio, objeções, compromissos, próximos passos, concorrência, timing, risco e progresso.

Também é uma **direção**, não necessariamente uma nova casa física.

### Commercial Intelligence
Conhecimento sobre o processo comercial e seu desempenho: pipeline, velocity, conversão, aging, objeções, motivos de ganho/perda, eficácia de follow-ups, ciclo de venda, canais e padrões que emergem dos deals.

### Agent Intelligence
Governança/orquestração de acesso e capacidade dos agentes. Não é um novo corpus de negócio.

A direção é evoluir de **Agent × Knowledge** para algo mais completo, possivelmente:

> **Agent × Skill × Knowledge × Tool**

Mas isso só deve ser materializado quando o uso exigir.

---

## 4. Playbook ≠ Skill

Esta distinção fica decidida em 29/09/2026.

### Playbook
É conhecimento operacional sobre como pensar, decidir e agir em diversos cenários.

Exemplo: um playbook de venda B2B pode orientar:
- como reconhecer interesse real;
- quando aprofundar necessidade;
- como lidar com objeção;
- como vender para CEO versus RH;
- como interpretar silêncio;
- quando envolver outro stakeholder;
- como propor próximo passo;
- que comportamentos evitar.

Um mesmo playbook pode servir a vários processos.

### Skill
É um processo executável.

Exemplo: `meeting_debrief`:
1. receber transcript/notas;
2. identificar fatos;
3. separar memória de pessoa, conta e oportunidade;
4. identificar stakeholders, objeções e compromissos;
5. propor próximo passo;
6. propor gravações no Mind Intelligence;
7. propor nota/task/update no HubSpot;
8. devolver saída estruturada.

Uma Skill pode usar:
- vários playbooks;
- várias fontes de Intelligence;
- várias Tools;
- contratos próprios de entrada e saída.

Portanto:

> **Playbook é transversal; Skill tem começo e fim.**

E:

> **1 Skill ≠ 1 prompt.**

---

## 5. Direção para agentes

A mesma arquitetura deve ser reutilizável entre agentes.

O que diferencia um agente é principalmente:

- quais Skills pode usar;
- quais Playbooks pode carregar;
- quais Inteligências pode consultar;
- quais Tools pode executar;
- quais ações pode realizar autonomamente ou apenas propor.

### Exemplo: Commercial B2B

Skills candidatas:
- Daily Pipeline Review
- Pipeline Health
- Deal Strategy
- Account Strategy
- Meeting Prep
- Meeting Debrief
- B2B Outreach
- Follow-up
- Proposal Strategy
- Objection Handling
- Deal Hygiene
- Revenue Planning
- Commercial Retrospective

Essas Skills podem compartilhar playbooks e ferramentas.

### Exemplo: Concierge

Skills candidatas:
- answer_event_question
- recommend_session
- build_agenda
- navigate_event
- capture_interest
- collect_feedback
- create_post_event_plan

### Exemplo: Customer Support

Skills candidatas:
- identify_problem
- resolve_access_issue
- explain_purchase
- recover_order
- escalate_case

### Exemplo: Institute / Dash

Podem usar a mesma arquitetura, combinando Skills comerciais, educacionais, diagnósticas e consultivas conforme o contexto.

Nada disso implica criar essas Skills agora. São exemplos para testar a coerência da arquitetura.

---

## 6. Princípios de construção

### 6.1 Use case first
Construímos primeiro aquilo que Adriana/time realmente vai usar.

### 6.2 O mínimo necessário
Cada caso de uso deve materializar apenas as peças necessárias para funcionar bem.

### 6.3 Fonte única de verdade
Evitar duplicar a mesma verdade em várias tabelas. Projeções podem compor dados sem virar novo depósito canônico.

### 6.4 Separar pessoa, conta e oportunidade
Nem tudo que aparece numa conversa pertence à memória da pessoa.

Exemplo:
- “prefere mensagens curtas” → pessoa;
- “orçamento fecha em novembro” → conta;
- “proposta precisa chegar até dia 15” → oportunidade.

### 6.5 Security before retrieval
Customer/Account/Opportunity Intelligence exige autorização por escopo antes de recuperação.

### 6.6 Aprender sem auto-corromper
Outcomes podem gerar hipóteses de melhoria. Mudança de playbook/skill relevante deve ser versionada, avaliada e aprovada antes de virar comportamento ativo.

### 6.7 Não criar por antecipação
Se a justificativa for apenas “isso pode ser útil no futuro”, permanece em Direction/Explore.

---

## 7. Caso de uso prioritário para aprender a arquitetura

### Commercial Intelligence B2B

É um bom laboratório porque atravessa quase todas as camadas:

```text
HubSpot / reuniões / conversas
        ↓
Customer + Account + Opportunity + Commercial Intelligence
        ↓
Playbooks comerciais
        ↓
Skills
        ↓
Commercial Agent
        ↓
HubSpot / memória / mensagens / tasks
        ↓
Outcomes
        ↓
Learning
```

Experiência desejada, em linguagem de usuário:

- “Como está meu pipeline?”
- “O que eu tenho que fazer hoje?”
- “Quais deals estão parados?”
- “O que está vencido?”
- “Qual a estratégia para esta oportunidade?”
- “Prepare minha reunião.”
- “Leia este transcript e grave o que aprendemos.”
- “Escreva o follow-up usando tudo o que sabemos.”
- “Qual deve ser o next step no HubSpot?”
- “O que está funcionando ou não no nosso processo comercial?”

O HubSpot continua sendo o CRM operacional. O Mind Intelligence agrega memória, contexto, conhecimento e inteligência. Não devemos criar um CRM paralelo.

---

## 8. Como priorizar o backlog

### NOW
Trabalho necessário para um caso de uso real que está sendo desenhado ou usado.

**Atual:**
- continuar estudando o Commercial Intelligence B2B;
- definir sua experiência real de uso antes de construir;
- identificar, durante esse desenho, quais capacidades já existem e quais faltam;
- conectar Customer Intelligence de forma canônica ao uso comercial quando o caso exigir;
- revisar este documento antes de materializar novas entidades.

### NEXT
Itens que já ficaram claramente úteis a partir do uso, mas ainda não bloqueiam o caso atual.

Por enquanto, nenhum item deve ser promovido automaticamente para NEXT sem evidência de uso.

### EXPLORE / DIRECTION
Hipóteses arquiteturais que parecem promissoras, mas ainda não justificam construção:

- biblioteca formal de Skills;
- Account Intelligence como camada explícita;
- Opportunity Intelligence como camada explícita;
- evolução de Agent × Knowledge para Agent × Skill × Knowledge × Tool;
- Skill Foundry;
- aprendizado sistemático a partir de outcomes;
- avaliação/versionamento automatizado de Skills e Playbooks;
- biblioteca de Skills compartilhadas entre agentes.

---

## 9. Regra de revisão diária

Antes de começar uma frente relevante de desenvolvimento, revisar:

1. O caso de uso que estamos resolvendo continua claro?
2. Estamos criando algo porque precisamos agora ou porque parece elegante?
3. Alguma abstração deste documento ficou errada à luz do uso recente?
4. Alguma nova informação deveria mudar a direção arquitetural?
5. Algum item de Explore ganhou evidência suficiente para ir para Next?
6. Algum item de Next deixou de fazer sentido?
7. Estamos duplicando uma fonte de verdade?
8. Estamos confundindo Intelligence, Playbook, Skill, Agent ou Tool?
9. O backlog reflete o que realmente queremos construir agora?

Se a resposta exigir mudança, **atualizar este documento antes ou junto da implementação**.

---

## 10. Log leve de evolução

### 29/09/2026 — versão inicial
Decisões/direções registradas:
- arquitetura orientada por Intelligence → Playbooks → Skills → Agents → Tools → Outcomes → Learning;
- definição explícita de Playbook versus Skill;
- mesma arquitetura como direção para diferentes agentes;
- Customer, Account e Opportunity representam contextos diferentes;
- Commercial Intelligence B2B como primeiro laboratório provável;
- princípio “use case first”;
- proibição de criar arquitetura vazia por antecipação;
- backlog dividido em Now / Next / Explore;
- revisão diária e possibilidade explícita de reformular a visão.

---

## 11. Regra final

Este documento existe para preservar raciocínio sem transformar hipótese em dogma.

> **A arquitetura serve ao uso. O uso não deve servir à arquitetura.**
