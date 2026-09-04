# Product Intelligence + Product Decisioning — CANON

Status: **APROVADO / IMPLEMENTADO / FROZEN**  
Data: 2026-09-02

Este documento congela a verdade estável de produto, o contrato de decisão entre soluções e a integração com os Agents vivos. Ele não contém preço, lote, checkout, turma ou disponibilidade.

## 1. Arquitetura

```text
CUSTOMER INTELLIGENCE = o que sabemos sobre a pessoa
PRODUCT INTELLIGENCE = o que cada solução realmente é capaz de fazer
COMMERCIAL INTELLIGENCE = o que está vendável agora, com preço, condição e canal
PRODUCT DECISIONING = qual solução faz sentido para a transformação buscada agora
AGENT = como explicar e conduzir o próximo passo permitido
```

Regras congeladas:

- ICP não determina produto.
- JTBD não determina sozinho produto.
- Tema de interesse não prova intenção de compra.
- Produto disponível não é automaticamente produto recomendado.
- Fit e sellability são decisões diferentes.
- `nenhuma` é uma recomendação válida.

## 2. Fontes e precedência

Fontes revisadas:

- `https://joinmind.com.br/`;
- `https://mindinstitute.com.br/`;
- `https://mindinstitute.com.br/formacoes/`;
- páginas atuais das três formações;
- `https://mindinstitute.com.br/certificacao-avancada/`;
- `https://mindinstitute.com.br/para-empresas/`;
- `https://mindinstitute.com.br/quem-somos/`;
- repositório `Mind-Institute/mindinstitute`, especialmente `src/content/catalogo.ts`, `src/content/programas.ts` e `src/lib/routes.ts`;
- sistema vivo do `mind-agent`.

Precedência:

> decisão explícita posterior da Adriana > fonte atual canônica de produto > página pública atual compatível > conteúdo histórico.

### Comercial mutável

Site/repo de produto é fonte para posicionamento, problemas, capacidades, formato estável e aplicação.

Preço, lote, turma, disponibilidade, parcelamento e checkout pertencem somente à Commercial Intelligence operacional atual.

O bloco `product_intelligence` declara explicitamente que não contém essas informações comerciais.

## 3. Mind

Natureza: **ecossistema**.

O Mind conecta ciência e prática para profissionais, líderes e organizações.

- Summit amplia repertório e conexões.
- Institute desenvolve competências.
- Dash apoia diagnóstico, desenho, implementação e acompanhamento de transformações organizacionais.

`Mind` não é uma quarta solução concorrente; é o ecossistema que integra as três frentes.

## 4. Mind Summit

Natureza: **descoberta, repertório e conexão**.

Resultado principal:

> ampliar repertório, perspectivas e conexões para melhorar decisões e mobilizar agendas.

Profundidade:

> exposição qualificada, comparação de perspectivas e aprendizagem em múltiplos formatos.

Formato:

> evento presencial com palestras, painéis, workshops, masterclasses e networking, conforme o acesso do ingresso.

Escopo:

> pessoa, grupo ou delegação vivendo a experiência do evento.

Faz sentido principalmente quando é necessário:

- ampliar repertório;
- acessar referências e perspectivas;
- descobrir temas, especialistas e caminhos possíveis;
- conectar-se a pares;
- mobilizar lideranças em torno de uma agenda;
- explorar possibilidades antes de escolher uma intervenção.

Limites:

- não diagnostica a organização;
- não implementa uma transformação;
- não substitui formação executiva;
- não substitui consultoria;
- participação no evento não garante resolução do problema.

Horários, ingressos, reservas, sessões, disponibilidade e ofertas continuam nas casas específicas do Summit.

## 5. Mind Institute

Natureza: **desenvolvimento de competência**.

Resultado principal:

> desenvolver capacidade aplicada para decidir e agir com método no trabalho.

Profundidade:

> aprendizagem estruturada, aplicação e reflexão.

Formato:

> formações executivas online com conteúdo assíncrono e encontros ao vivo; cohorts abertos ou corporativos.

Escopo:

> profissional, liderança, RH, consultoria ou cohort em desenvolvimento.

Metodologia transversal observada nas fontes atuais:

- ciência aplicada;
- Learn–Apply–Reflect;
- aplicação em desafios reais;
- aprendizagem em cohort/comunidade;
- formação executiva e credenciais.

### 5.1 Gestão Estratégica de Bem-Estar no Trabalho

**Eixo canônico:** Gestão Estratégica de Bem-Estar no Trabalho.

Nome oficial atual do produto no site: `Formação em Gestão Estratégica de Saúde Mental e Bem-Estar no Trabalho`.

Faz sentido quando é preciso:

- estruturar bem-estar como agenda de gestão;
- identificar riscos e ativos psicossociais;
- conectar diagnóstico a intervenção;
- construir plano de ação;
- construir business case e indicadores;
- integrar NR-1 a uma abordagem de gestão, e não apenas documental.

Capacidades centrais:

- mapear riscos e ativos psicossociais;
- diferenciar sintomas de causas do trabalho;
- interpretar diagnósticos;
- selecionar intervenções coerentes;
- estruturar plano de ação;
- construir business case e indicadores.

### 5.2 Segurança Psicológica e Voz Ativa

Produto atual: `Formação em Segurança Psicológica Aplicada à Inovação`.

Faz sentido quando:

- pessoas evitam perguntar, discordar ou comunicar problemas;
- é preciso fortalecer confiança, aprendizagem e voz ativa;
- segurança psicológica precisa coexistir com accountability;
- líderes precisam conduzir conversas difíceis com mais capacidade.

Capacidades centrais:

- diagnosticar barreiras à voz ativa;
- fortalecer confiança e aprendizagem;
- conduzir conversas difíceis;
- equilibrar segurança psicológica e responsabilização;
- transformar diagnóstico em plano de ação.

### 5.3 Engajamento e Significado no Trabalho

Produto atual: `Formação em Engajamento e Significado no Trabalho`.

Faz sentido quando:

- propósito existe no discurso mas não aparece na rotina;
- pertencimento precisa ser fortalecido;
- a contribuição das pessoas está invisível;
- reconhecimento é genérico ou insuficiente;
- líderes precisam equilibrar autonomia, apoio e crescimento.

Capacidades centrais:

- conectar propósito ao cotidiano;
- fortalecer comunidade e pertencimento;
- tornar contribuição e impacto visíveis;
- praticar reconhecimento específico;
- equilibrar autonomia, apoio e desafio;
- estruturar práticas e plano de ação.

### 5.4 Certificação Avançada

Produto atual: `Certificação Avançada em Liderança e Saúde Mental Positiva`.

Natureza: jornada integrada das três formações e projeto aplicado.

Faz sentido somente quando:

- os três desafios aparecem de forma realmente conectada;
- a pessoa busca uma visão sistêmica e formação abrangente;
- existe intenção real de integrar as três formações em um projeto aplicado.

Não usar Certificação como upsell automático ou como versão superior das formações individuais.

## 6. Mind Dash

Natureza: **intervenção organizacional**.

Resultado principal:

> transformar diagnóstico e prioridades em um sistema de gestão com implementação e acompanhamento.

Profundidade:

> diagnóstico, desenho, implementação ou apoio à implementação e acompanhamento.

Formato:

> consultoria e assessoria estratégica sob medida.

Escopo:

> organização, cultura, liderança, desenho do trabalho e práticas de gestão.

Faz sentido quando a necessidade deixou de ser apenas aprender e a organização precisa:

- diagnosticar riscos, ativos ou padrões;
- interpretar dados no contexto real;
- definir prioridades;
- desenhar plano de ação;
- implementar ou apoiar implementação;
- construir indicadores;
- acompanhar resultados e ajustar a estratégia.

Limites:

- não é curso individual;
- não é benefício isolado;
- não é avaliação clínica de funcionários;
- não é pacote idêntico para qualquer organização;
- não promete eliminar burnout;
- não é simples adequação documental à NR-1.

## 7. Product Decisioning v2

Prompt canônico: `agentes.prompts['product_decisioning']`, versão **2**.

### Quatro eixos

1. transformação desejada;
2. profundidade necessária;
3. escopo da mudança;
4. urgência/momento da decisão.

Pergunta central:

> Por que esta solução, para esta transformação, neste momento?

### No-fit

**Nenhuma recomendação é um resultado válido.**

Se nenhuma solução resolver de forma coerente o que a pessoa quer realizar agora:

- não forçar fit;
- não inventar dor;
- não fazer cross-sell só porque há produto disponível;
- continuar ajudando dentro da competência atual ou dizer que não há solução clara para recomendar.

Saída interna:

`SOLUCAO_PRINCIPAL = Summit | Institute | Dash | nenhuma`.

### Ambiguidade

Quando duas soluções forem plausíveis:

- identificar a diferença que muda a decisão;
- fazer no máximo UMA pergunta discriminante;
- não aplicar questionário de quatro eixos.

### Institute como solução principal

Se Institute for o fit principal, escolher um programa específico somente quando a transformação atual sustentar essa escolha.

Não escolher programa por ICP nem por código JTBD isolado.

- gestão estratégica → bem-estar como gestão, riscos/ativos, diagnóstico → intervenção, business case/indicadores;
- segurança psicológica → confiança, voz, aprendizagem, accountability e conversas difíceis;
- engajamento/significado → propósito, pertencimento, contribuição, reconhecimento, autonomia e crescimento;
- certificação → múltiplos eixos realmente conectados ou desejo explícito de jornada integrada.

Se Institute for o fit mas ainda não houver informação para escolher um programa, recomendar Institute como caminho e, se necessário, fazer uma pergunta discriminante.

### Fit ≠ sellability

1. decidir fit;
2. consultar Commercial Intelligence atual;
3. somente então definir próximo passo executável.

Se o melhor fit não estiver vendável:

- não substituir automaticamente por Summit;
- não inventar preço/turma/checkout;
- explicar a coerência do fit;
- usar somente o próximo passo permitido pelo runtime.

## 8. Implementação viva

Casas:

- `catalogo.produtos` — identidade/resumo dos códigos `mind`, `mind-summit-2026`, `mind-institute`, `mind-dash`;
- `summit_2026.knowledge_documents` — Product Intelligence estável do Summit;
- `institute.knowledge_documents` — Product Intelligence estável do Institute;
- `dash.knowledge_documents` — Product Intelligence estável do Dash.

Provider transversal:

`public.mind_kit_product_intelligence(uuid,jsonb)`

Retorna definição, natureza, resultado principal, profundidade, formato, escopo, problemas, capacidades, programas/eixos do Institute, adequação e limites.

Não retorna preço, lote, parcelamento, checkout, turma ou disponibilidade.

Segurança: `EXECUTE` somente `postgres`/`service_role`.

Bloco `product_intelligence` ativo nos Kits:

- `concierge_summit` — opcional;
- `cliente_suporte` — opcional;
- `summit_b2c` — opcional;
- `summit_b2b` — opcional;
- `institute` — obrigatório;
- `dash` — obrigatório.

## 9. Integração do Product Decisioning nos Agents

### Registry

`agentes.kit_blocos.secao` aceita agora:

- `structured`;
- `knowledge`;
- `tools`;
- `decisioning`.

Registro vivo do App:

```text
rota = concierge_summit
bloco = product_decisioning
provider = agentes.prompts
secao = decisioning
obrigatorio = false
ativo = true
```

### Concierge/App

`public.mind_agent_kit` devolve `decisioning` em campo próprio.

Na baseline desta implementação, a `mindagent-chat` v30 / `1.9.1` passou a
usar `kit.playbook` como bundle de `instructions`. A versão operacional atual
deve ser consultada em `CHECKPOINT_ATUAL.md`. O Kit compõe por turno:

```text
base + playbook da competência + decisioning registrado
→ kit.playbook  [bundle consumido pelo runtime]
```

Ao mesmo tempo `kit.decisioning` preserva a camada separada para auditoria e futuros runtimes.

**O prompt-fonte `playbook_concierge_summit` não contém cópia de `product_decisioning`.**

No mesmo turno, o Concierge recebe:

```text
structured.customer_intelligence
+ structured.product_intelligence
+ fala/necessidade atual
+ product_decisioning v2
+ playbook da competência
→ Agent
```

### Vendas Summit

`summit_b2c` e `summit_b2b` já recebem Product Decisioning v2 pela composição `treble_agent_prompt(..., 'decisioning')`.

### Atendimento

`cliente_suporte` **não recebe Product Decisioning**. Atendimento resolve necessidade operacional; não é superfície de recomendação/cross-sell entre soluções.

### Institute/Dash

As rotas existem no registry, mas ainda não são Agents operacionais em canal real. Não antecipar wiring sem consumidor.

## 10. Migrations

Produção e Git possuem:

- `20260902073929_product_intelligence_compartilhada.sql`;
- `20260902085815_product_decisioning_entre_solucoes.sql`;
- `20260902224703_product_intelligence_decisioning_v2.sql`;
- `20260902230159_kit_decisioning_section_concierge.sql`;
- `20260902230319_kit_decisioning_runtime_compat.sql`.

## 11. Verificação realizada

Product Intelligence:

- provider devolve 4 entidades (`Mind`, Summit, Institute, Dash);
- Institute devolve 4 caminhos atuais;
- profundidade/formato/escopo presentes;
- nenhum valor `R$` entra no Product Intelligence;
- provider restrito a `service_role`/postgres.

Product Decisioning:

- prompt ativo = versão 2;
- no-fit presente;
- subdecisão do Institute presente;
- Treble B2C continua com v2.

Integração Concierge:

- Kit `kit_disponivel=true`;
- `structured.customer_intelligence` presente;
- `structured.product_intelligence` presente;
- `kit.decisioning` contém v2;
- bundle consumido pelo runtime contém v2;
- playbook-fonte do Concierge não contém Decisioning;
- Atendimento não recebe Decisioning.

Teste versionado:

`tests/product_decisioning_agent_integration.sql`.

Implementação detalhada:

`PRODUCT_DECISIONING_AGENT_INTEGRATION.md`.

## 12. Cenários do E2E de recomendação

1. “Quero expor minha liderança a novas referências e trazer o tema para a agenda.” → Summit provável.
2. “Quero formar HRBPs para aplicar segurança psicológica e trabalhar conversas difíceis.” → Institute → Segurança Psicológica provável.
3. “Precisamos diagnosticar riscos psicossociais, priorizar e implementar um plano na organização.” → Dash provável.
4. “Quero desenvolver competência em bem-estar, segurança psicológica e significado de forma integrada.” → Institute → Certificação provável.
5. Necessidade fora das capacidades atuais do ecossistema → `nenhuma` é resposta correta.
6. Interesse temático sem profundidade/escopo claros → uma pergunta discriminante; nunca mapear automaticamente.

## 13. Próximo gate

**E2E real de recomendação entre soluções no runtime autenticado do App.**

A camada estrutural está fechada. O E2E deve provar comportamento do modelo, não apenas presença de prompt/dado.

Depois disso, seguir para E2E do vendedor Summit no WhatsApp e pós-conversa/write-back.
