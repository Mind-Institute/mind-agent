# Customer Intelligence do Mind — ICPs, JTBD e Product Fit

Status: **decisão arquitetural fechada / plano de trabalho**  
Data: 2026-09-02  
Escopo atual: registrar contexto e investigar o sistema existente. **Não implementar ainda.**

---

# 1. Fonte desta frente

Documento-fonte recebido de Adriana em 2026-09-02:

- arquivo recebido na conversa: `Pasted markdown(20260902-051127).md`
- título interno: **“Índice. ICPs e jobs to be done para o agente do Mind Summit 2026”**
- origem declarada no próprio material: estudo interno **“Mind Summit 2025 — ICPs e Jobs-to-be-Done”**, baseado em 330 perfis classificados e 120+ fontes.

Este arquivo-fonte contém seis ICPs, seus contextos, tensões, JTBDs, sinais de reconhecimento, perguntas diagnósticas, objeções prováveis, argumentos comerciais, evidências e regras de segurança.

## Regra de preservação da fonte

Este documento de plano **não substitui o arquivo-fonte**. Ele registra a arquitetura decidida a partir dele.

Quando chegarmos à implementação da taxonomia/conteúdo, o arquivo-fonte deve ser consultado novamente. Se ele não estiver acessível em uma futura janela, pedir que Adriana o reenvie em vez de reconstruí-lo de memória.

---

# 2. O que este documento passa a representar para o sistema

A decisão é **não tratar este material como um playbook específico para vender o Summit**.

Ele passa a ser a matéria-prima para construir a **Customer Intelligence compartilhada do Mind**: uma camada capaz de ajudar Summit, Institute, Dash e outros agentes a entender progressivamente:

1. de que contexto profissional a pessoa vem;
2. quais problemas/jobs ela está realmente tentando resolver;
3. quais objetivos, interesses, restrições e prioridades ela explicitou;
4. qual é o job que está “em placa” agora;
5. qual solução, conteúdo ou próximo passo atual do Mind tem fit real com esse job.

A finalidade é dupla:

- **aumentar conversão**, tornando a conversa específica ao problema real da pessoa;
- **acumular conhecimento do cliente entre produtos e momentos**, para que o Mind não recomece do zero a cada interação.

Exemplo de continuidade desejada:

`Summit → aprende job/interesses/contexto → memória de Customer Intelligence → conversa futura → Institute/Dash/outro produto coerente com o mesmo job`

Isto deve ser uma ponte de aprofundamento real, não cross-sell genérico.

---

# 3. Arquitetura conceitual fechada

## 3.1 ICP = contexto relativamente estável

ICP ajuda o sistema a entender **de que lugar profissional a pessoa está falando**.

Exemplos atuais do estudo:

- CHRO / VP de Pessoas
- CEO / C-Suite
- Gestor / Middle Manager
- People Leader / Business Partner
- Executivo Sênior / Alto Performer
- Consultor / Coach / Psicólogo Corporativo

### Regra absoluta

**ICP nunca determina a dor.**

Cargo, empresa e contexto podem sustentar uma hipótese de ICP. Eles não sustentam automaticamente um JTBD.

Não fazer:

`cargo = CHRO → job = provar ROI`

Fazer:

`cargo/contexto → hipótese de ICP`  
`fala/comportamento/evidência → job realmente sustentado`

O Agent nunca deve dizer à pessoa que “ela pertence ao ICP X”.

---

## 3.2 JTBD = problema/resultado que está em placa

JTBD é a dimensão mais importante para personalização e conversão.

Ele responde:

> O que esta pessoa está tentando realizar/resolver agora?

Uma pessoa pode ter vários jobs. O sistema deve diferenciar, quando houver evidência suficiente:

- hipótese de job;
- job observado/confirmado pela conversa;
- job ativo/prioritário agora;
- job histórico, que pode continuar útil como memória, mas não deve dominar automaticamente a conversa atual.

### Regra absoluta

**JTBD precisa de evidência da pessoa/conversa. ICP gera hipótese; evidência confirma o job.**

Se o job já estiver claro, não perguntar de novo. Uma pergunta diagnóstica só deve existir quando a resposta puder mudar materialmente a recomendação.

---

## 3.3 Product Fit = camada separada

O documento original frequentemente liga:

`JTBD → argumento comercial do Summit`

Para a arquitetura do Mind, isso será separado em:

`JTBD → necessidade/capacidade → soluções/conteúdos atuais do Mind capazes de ajudar`

Somente depois o Decisioning escolhe o melhor caminho.

Portanto, não criar relações rígidas do tipo:

`ICP X → produto Y`

nem:

`JTBD X → curso Y`

O fit deve considerar:

- job ativo;
- contexto profissional;
- objetivo declarado;
- profundidade procurada;
- problema individual vs. organizacional;
- estágio comercial;
- produtos que a pessoa já possui/fez;
- catálogo e disponibilidade atuais;
- evidência de interesse;
- capacidade real da solução atual.

---

# 4. Como os quatro componentes do documento serão tratados

O material original mistura quatro tipos de ativo que no sistema devem ter casas conceituais diferentes.

## A. Taxonomia de ICPs

É **Customer Intelligence**.

Serve para contexto profissional e hipóteses de relevância.

## B. Taxonomia de JTBDs

É **Customer Intelligence** e deve se tornar linguagem canônica compartilhada no ecossistema.

Serve para necessidades, resultados desejados e prioridades reais da pessoa.

## C. Sinais linguísticos + perguntas diagnósticas + como reconhecer

É principalmente **PLAYBOOK**.

Ensina um excelente agente a testar uma hipótese sem presumir, rotular ou transformar a conversa em formulário.

## D. Evidências, índices, pesos e estatísticas do estudo

É **Knowledge/evidência interna da taxonomia**, com proveniência e temporalidade explícitas.

Não é verdade operacional de 2026 e não pode ser apresentada como dado atual sem validação em fonte atualizada.

## E. Argumentos comerciais e objeções prováveis

São aplicação comercial derivada do estudo. Devem informar **Decisioning/Playbook**, nunca substituir Product Intelligence atual.

---

# 5. Taxonomia inicial preservada do documento-fonte

A lista abaixo registra os nomes/códigos do estudo para não perdermos a linguagem original. Os códigos são internos e nunca devem ser expostos ao usuário.

## 5.1 CHRO / VP de Pessoas — 18,8% da base do estudo, n=62

Tensão central: agenda ampla de pessoas/saúde mental, RH sobrecarregado, líderes pouco preparados e necessidade de convencer o board com métricas e execução.

Jobs:

- `I1J1` — Desenvolver líderes e gestores para o novo contexto
- `I1J2` — Provar ROI de bem-estar e saúde mental para o board
- `I1J4` — Gerenciar riscos psicossociais e atender à NR-1
- `I1J3` — Criar cultura de engajamento em meio à incerteza
- `I1J5` — Redesenhar performance para a era da IA
- `I1J6` — Cuidar da saúde mental do próprio time de RH
- `I1J7` — Construir resiliência organizacional contínua
- `I1J8` — Liderar adoção ética de IA em gestão de pessoas

## 5.2 CEO / C-Suite — 13,3%, n=44

Tensão central: liderar transformação complexa com isolamento decisório, baixa margem para fragilidade e necessidade de preservar performance/capital humano.

Jobs:

- `I2J1` — Manter performance sem colapsar
- `I2J3` — Liderar transformação humana da IA
- `I2J4` — Reter e engajar talentos certos
- `I2J2` — Quebrar isolamento com pares de confiança
- `I2J5` — Transformar cultura em vantagem competitiva
- `I2J6` — Construir segurança psicológica real
- `I2J7` — Desenvolver pipeline de liderança
- `I2J8` — Longevidade executiva como estratégia

## 5.3 Gestor / Middle Manager — 22,7%, n=75

Tensão central: pressão por resultado de cima, esgotamento do time embaixo, pouco espaço para fragilidade e responsabilidade crescente sobre saúde mental/performance.

Jobs:

- `I3J1` — Gerenciar próprio burnout sem perder autoridade
- `I3J2` — Identificar sofrimento mental da equipe e agir
- `I3J4` — Manter energia e propósito sob pressão constante
- `I3J3` — Ter conversas difíceis com honestidade
- `I3J5` — Desenvolver equipe sem tempo para isso
- `I3J7` — Cumprir NR-1 na prática do dia a dia
- `I3J6` — Navegar IA sem se tornar obsoleto

## 5.4 People Leader / Business Partner — 11,5%, n=38

Tensão central: deveria influenciar o negócio, mas está preso ao operacional/cuidado dos outros e precisa desenvolver líderes, usar dados e responder à NR-1.

Jobs:

- `I4J2` — Desenvolver gestores que liderem pessoas de verdade
- `I4J1` — Ser reconhecido como parceiro estratégico
- `I4J3` — Implementar NR-1 transformando compliance em cultura
- `I4J4` — Usar dados de pessoas para influenciar decisões
- `I4J5` — Provar ROI dos programas de bem-estar
- `I4J6` — Cuidar do próprio bem-estar sem culpa
- `I4J7` — Dominar coaching de líderes

## 5.5 Executivo Sênior / Alto Performer — 13,0%, n=43

Tensão central: performance muito alta, pouco espaço para reflexão, sobrecarga/fadiga decisória, isolamento e cultura que premia resistência mais do que recuperação.

Jobs:

- `I5J1` — Proteger capacidade de decidir sob pressão crônica
- `I5J2` — Sustentar alta performance sem destruir saúde
- `I5J3` — Recuperar nitidez mental após sobrecarga
- `I5J4` — Romper isolamento sem comprometer autoridade
- `I5J5` — Desescalar estresse sem sinalizar fraqueza
- `I5J6` — Gerenciar budget cerebral para decisões que importam
- `I5J7` — Resiliência emocional para ambiguidade permanente
- `I5J8` — Bem-estar pessoal como vantagem competitiva

## 5.6 Consultor / Coach / Psicólogo Corporativo — 20,6%, n=68

Tensão central: expertise técnica relevante, mas pressão por aquisição de clientes, diferenciação, linguagem de negócio, autoridade, ROI e escala.

Jobs:

- `I6J1` — Vender e estruturar serviços para empresas
- `I6J2` — Demonstrar ROI das intervenções para clientes
- `I6J3` — Usar NR-1 como porta de entrada corporativa
- `I6J6` — Falar linguagem do negócio para acessar C-Suite
- `I6J4` — Construir autoridade em mercado saturado
- `I6J5` — Escalar além do atendimento individual 1:1
- `I6J7` — Aplicar ciência validada para ter credibilidade

---

# 6. Modelo mental desejado da Customer Intelligence da pessoa

Não é um schema aprovado ainda. É o contrato conceitual que deve orientar a investigação.

Exemplo:

```text
CONTEXTO PROFISSIONAL
- CHRO
- empresa grande

ICP PROVÁVEL
- chro_vp_pessoas
- confiança: alta
- evidência: cargo declarado

JOBS ATIVOS
- desenvolver gestores
  confiança: alta
  evidência: fala explícita

- transformar NR-1 em gestão/cultura
  confiança: média
  evidência: contexto explícito, mas prioridade ainda não confirmada

OBJETIVOS
- mobilizar gestores
- construir business case

INTERESSES
- segurança psicológica
- riscos psicossociais
- liderança

CONTEXTO DA DECISÃO
- precisa convencer board
```

Não criar campos/tabelas apenas porque aparecem neste exemplo. Primeiro mapear para as casas existentes.

---

# 7. Fluxo futuro desejado

```text
EVIDÊNCIA DA CONVERSA / PERFIL
        ↓
CONTEXTO PROFISSIONAL + HIPÓTESE DE ICP
        ↓
JTBDs SUSTENTADOS + PRIORIDADE ATUAL
        ↓
OBJETIVOS / INTERESSES / RESTRIÇÕES
        ↓
PRODUCT INTELLIGENCE ATUAL
        ↓
FIT JTBD ↔ CAPACIDADES / SOLUÇÕES
        ↓
DECISIONING
        ↓
AGENT
        ↓
RECOMENDAÇÃO / PRÓXIMO AVANÇO DE MENOR FRICÇÃO
```

Regra canônica:

> ICP diz de onde a pessoa vem.  
> JTBD diz o que ela está tentando resolver.  
> INTELLIGENCE atual diz quais soluções/conteúdos existem.  
> DECISIONING escolhe a melhor ponte entre os dois.  
> AGENT transforma isso numa conversa relevante.

---

# 8. Comportamento desejado dos agentes

## Concierge

Usa Customer Intelligence para recomendar conteúdo/jornada do Summit com base em jobs/interesses reais, sem recomeçar discovery se já há evidência suficiente.

## Vendas Summit

Usa os mesmos jobs/contexto para escolher argumento, experiência, delegação ou próximo avanço — sempre cruzando com verdade comercial atual.

## Institute

Usa o contexto acumulado para sugerir aprofundamento estruturado quando existir produto atual realmente aderente.

Exemplo de lógica desejada:

> “Você vinha tentando resolver X e demonstrou interesse em Y. Existe uma formação atual que aprofunda exatamente essa capacidade.”

Não fazer cross-sell genérico do tipo “foi ao Summit → venda um curso”.

## Dash / soluções corporativas

Quando o job for organizacional e houver solução atual com fit, pode reconhecer que o próximo passo é implementação/diagnóstico organizacional, não mais aprendizado individual.

## Atendimento

Pode conhecer Customer Intelligence para contexto, mas não deve transformar uma demanda de suporte em venda aleatória.

---

# 9. Métricas/learning que esta arquitetura poderá permitir depois

Quando o sistema estiver maduro, queremos conseguir observar:

- quais JTBDs aparecem mais;
- distribuição de jobs por ICP/contexto;
- conversão do Summit por job;
- passagem Summit → Institute por job;
- jobs que geram oportunidade Dash;
- conteúdos/sessões mais relevantes por job;
- recomendações dadas e aceitação/avanço;
- objeções/barreiras por job;
- jobs recorrentes sem solução adequada no portfólio;
- diferenças de jornada entre contextos profissionais sem transformar ICP em destino rígido.

Isto é etapa posterior. Não criar analytics/telemetria antes de existir um contrato correto de Customer Intelligence.

---

# 10. Plano de trabalho aprovado

## PASSO 1 — Investigar o sistema real (read-only)

### Objetivo

Descobrir quanto da Customer Intelligence, memória, Product Intelligence e recomendação já existe e qual é a menor mudança necessária.

### Consultar

#### Documentação Git canônica/operacional

- `AGENTS.md`
- `CHECKPOINT_ATUAL.md`
- `PROJECT_STATE.md`
- `docs/CORE_UNIVERSAL.md`
- `MAPA_DO_SISTEMA.md`
- documentos recentes de memória/Customer Intelligence/Decisioning
- este arquivo

#### Supabase vivo

Customer/person intelligence:

- `intelligence.participante_contexto`
- `intelligence.participante_memoria`
- `intelligence.participante_objetivos`
- `intelligence.sinais_comerciais`
- `intelligence.recomendacoes`
- `intelligence.analise_conversa`
- `intelligence.continuidade_comercial`
- `intelligence.intencoes`
- regras/gates de memória

Identity/context:

- `pessoas.pessoas`
- `engagement.conversas`
- `engagement.mensagens`
- `engagement.identidades`

Analysis/decisioning:

- `agentes.prompts` (`analise_*`, playbooks e base relacionados)
- funções que projetam análise para memória/contexto/sinais
- Edge/functions que executam pós-conversa

Product/knowledge:

- `catalogo.produtos`
- `summit_2026.*` relevante
- `institute.knowledge_documents/chunks`
- `dash.knowledge_documents/chunks`
- `ecossistema.palestrantes_especialistas`
- funções de retrieval/Kit usadas por agentes

### Perguntas que a investigação precisa responder

1. Onde já existe casa para contexto profissional?
2. Onde já existe casa para necessidade/job?
3. Onde já existe casa para objetivo e resultado desejado?
4. Onde já existe casa para interesses/preferências/prioridades?
5. Onde armazenamos evidência/confiança/recência hoje?
6. O que é reconstruído vs. memória durável?
7. Quais analisadores extraem esses dados hoje?
8. Quais estão ativos, inativos, placeholder ou legado?
9. O Sales analyzer atual já extrai parte de JTBD sem chamar assim?
10. `analise_concierge` deve assumir esta extração ou existe componente mais adequado?
11. Existe alguma taxonomia de ICP/job já implementada que não devemos duplicar?
12. O que `participante_contexto` realmente lê/serve aos Agents hoje?
13. Product Intelligence atual consegue representar Summit/Institute/Dash sem duplicar catálogo?
14. Institute e Dash têm produtos atuais confiáveis ou só legado/2025?
15. Existe mecanismo de recomendação que já conecta objetivo → conteúdo/produto?
16. Onde Decisioning deveria receber jobs/contexto?
17. Que parte do documento é Intelligence vs. Playbook vs. evidência?
18. Qual é a menor extensão do sistema atual para suportar tudo isso?

### Saída obrigatória

Mapa:

`conceito → casa existente → consumidor atual → uso real → problema/gap → menor mudança recomendada`

E relatório separado de:

- o que já existe;
- tabelas/funções/Edge Functions/fluxos participantes;
- o que está realmente em uso;
- o que é legado/placeholder;
- dependências;
- o que já resolve parte do problema;
- contradições com a arquitetura imaginada;
- menor mudança recomendada.

### Regra

Nenhuma implementação no Passo 1.

---

## PASSO 2 — Consolidar a taxonomia canônica ICP/JTBD

### Objetivo

Transformar os seis documentos/perfis em linguagem canônica única do ecossistema.

### Fazer

- preservar a proveniência do estudo;
- revisar duplicidades conceituais entre jobs de ICPs diferentes;
- decidir quando jobs semelhantes são:
  - o mesmo job com nuance contextual;
  - jobs realmente diferentes;
- manter códigos internos estáveis quando úteis;
- definir nome canônico, descrição, tensão, resultado desejado e contexto aplicável;
- separar completamente argumento do Summit da definição do job;
- preservar evidências/estatísticas como metadata histórica, não como verdade atual.

### Não fazer

- deduzir job pelo ICP;
- transformar ICP em segmentação comercial rígida;
- conectar job diretamente a produto atual antes de Product Intelligence estar pronta.

### Definition of Done

Uma taxonomia ICP/JTBD compartilhada que pode ser usada por qualquer vertical sem reescrever os conceitos.

---

## PASSO 3 — Definir o contrato de Customer Intelligence da pessoa

### Objetivo

Definir exatamente o que o sistema aprende e como diferencia fato, hipótese, prioridade e histórico.

### Decisões a fechar

- ICP provável e confiança/evidência;
- jobs observados;
- job prioritário atual;
- objetivo/resultados desejados;
- interesses;
- restrições;
- contexto da decisão;
- recência/validade;
- como uma evidência nova substitui ou reduz relevância de uma antiga;
- o que fica em memória durável vs. contexto reconstruído.

### Regra

Antes de criar campo novo, responder:

> quem usa esse dado e para quê?

Se não houver consumidor concreto, não criar.

---

## PASSO 4 — Conectar extração e memória às conversas

### Objetivo

Fazer o sistema aprender ICP/contexto/JTBD progressivamente sem formulário e sem interrogation flow.

### Comportamento esperado

- usar tudo que já se sabe antes de perguntar;
- extrair do histórico inteiro quando apropriado;
- registrar evidência/confiança;
- não gravar job apenas porque o ICP sugere;
- não perguntar novamente se o job já está claro;
- usar uma pergunta discriminante por vez somente quando ela muda recomendação;
- diferenciar job ativo de histórico.

### Investigar antes

Reaproveitar pós-conversa/analisadores atuais antes de criar novo analisador.

---

## PASSO 5 — Completar Product Intelligence do Mind

### Objetivo

Criar verdade atual compartilhada sobre o que o Mind realmente oferece hoje.

### Cobertura desejada

- Mind Summit;
- Mind Institute;
- Mind Dash;
- demais soluções vigentes.

### Para cada solução/produto

Precisamos poder recuperar, conforme aplicável:

- o que é;
- para quem serve;
- quais necessidades/capacidades ajuda a desenvolver/resolver;
- profundidade;
- formato;
- elegibilidade;
- status atual;
- disponibilidade;
- preço/condições/link, quando vendável;
- limites: o que não entrega.

### Constraint

Não colocar catálogo atual dentro da taxonomia ICP/JTBD.

Product Intelligence informa **o que existe agora**.

---

## PASSO 6 — Modelar fit JTBD ↔ soluções/conteúdos

### Objetivo

Permitir que o Decisioning escolha uma próxima etapa coerente para o problema real da pessoa.

### Não criar uma tabela simplista

Não basta `I1J1 → Produto X`.

O fit deve considerar contexto, profundidade, indivíduo vs. organização, etapa, histórico e disponibilidade atual.

### Exemplos de caminhos possíveis

- Summit → exposição/repertório/conteúdo/especialistas
- Institute → formação/aprofundamento estruturado
- Dash → diagnóstico/intervenção/implementação organizacional

O sistema pode concluir que **nenhuma oferta** é apropriada agora.

---

## PASSO 7 — Incorporar ao Decisioning e Agents

### Objetivo

Fazer diferentes agentes consumirem a mesma Customer Intelligence sem duplicar linguagem/conhecimento.

### Aplicação

- Concierge: recomendação de conteúdo/jornada
- Summit Sales: fit, argumento, upgrade/delegação
- Institute: aprofundamento coerente
- Dash: solução organizacional quando aplicável
- Atendimento: contexto sem venda aleatória

### Regra

PLAYBOOK decide como pensar.  
INTELLIGENCE informa o que é verdade agora.  
DECISIONING decide qual caminho faz sentido.  
AGENT diz/faz.

---

## PASSO 8 — Fechar ciclo de aprendizado e conversão

### Objetivo

Transformar a Customer Intelligence em aprendizado de produto/comercial sem automatizar conclusões frágeis.

### Possíveis outputs futuros

- conversão por job;
- jornada cross-product;
- conteúdo × job;
- recomendação × avanço;
- jobs sem solução;
- padrões de objeção/barreira;
- oportunidades de produto.

### Regra

Só depois que taxonomia, extração, memória e Product Intelligence estiverem estáveis.

---

# 11. Dependência já conhecida antes do Passo 1

Na checagem preliminar de 2026-09-02, `catalogo.produtos` já tinha Summit 2026 ativo/vendável, enquanto registros de Institute observados eram ofertas 2025/inativas e `mind-dash` estava inativo.

Isto é uma **hipótese de gap a ser confirmada no Passo 1**, não autorização para reconstruir catálogo.

---

# 12. Coordination com a implementação atual do Concierge

Claude Code está implementando separadamente os Passos 5 e 6 do runbook do Concierge Summit (prompts/memória/handoff).

Esta frente de Customer Intelligence deve permanecer **investigativa** até essa implementação fechar e ser revisada.

Não modificar os mesmos prompts/functions/runtime enquanto Claude estiver executando aquela entrega.

Quando a entrega do Claude fechar:

1. revisar o que foi realmente implementado;
2. atualizar `CHECKPOINT_ATUAL.md`, `PROJECT_STATE.md` e docs canônicos necessários;
3. consolidar decisões que hoje estão em arquivos temporários de execução;
4. limpar a raiz do Git de specs/runbooks/prompts transitórios que já cumpriram sua função;
5. manter somente documentação canônica e útil para formar o modelo mental do sistema;
6. só então iniciar implementação desta frente de Customer Intelligence.

A limpeza futura não deve apagar histórico necessário antes que as decisões estejam consolidadas nos documentos canônicos.

---

# 13. Checkpoint desta frente

**Decidido:**

- o documento ICP/JTBD vira base para Customer Intelligence compartilhada do Mind;
- ICP = contexto/hipótese, nunca dor automática;
- JTBD = problema/resultado sustentado por evidência;
- Product Fit é separado da taxonomia do cliente;
- Summit, Institute e Dash devem consumir a mesma inteligência da pessoa;
- cross-sell futuro deve ser continuidade de job, não oferta genérica;
- primeiro investigar o sistema real;
- não implementar esta frente ainda.

**Em andamento agora:**

- PASSO 1 — auditoria read-only do sistema existente.

**Depois:**

- decidir a menor mudança com base no que realmente existe.
