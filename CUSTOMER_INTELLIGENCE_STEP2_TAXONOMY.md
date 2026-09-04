# Customer Intelligence do Mind — Passo 2: Taxonomia canônica de ICP + JTBD

Status: **APROVADO/FROZEN; implementado pelo Passo 4**
Data: 2026-09-02  
Escopo original: modelagem conceitual e reconciliação de linguagens existentes.
Este arquivo preserva a decisão do Passo 2; a implementação posterior está
documentada em `CUSTOMER_INTELLIGENCE_STEP4_IMPLEMENTATION.md`.

---

# 1. Fontes usadas

1. Documento-fonte recebido em 2026-09-02: **“Índice. ICPs e jobs to be done para o agente do Mind Summit 2026”**, derivado do estudo interno “Mind Summit 2025 — ICPs e Jobs-to-be-Done”.
2. `CUSTOMER_INTELLIGENCE_ICP_JTBD_PLAN.md`.
3. `CUSTOMER_INTELLIGENCE_STEP1_AUDIT.md`.
4. HubSpot vivo — propriedades `icp`, `lead_icp`, `icp_confianca`.
5. Site atual do Mind Institute e `joinmind.com.br`, apenas como fonte de posicionamento/capacidades.
6. Repo `Mind-Institute/mindinstitute`, especialmente `src/content/catalogo.ts` e conteúdo dos programas.

Regra de precedência desta modelagem:

> decisão explícita posterior da Adriana > documento-fonte > fontes atuais de produto > legado.

Correção explícita desta rodada:

> Para o eixo do Institute, **não usar “saúde mental” como nome do job**. O conceito canônico é **GESTÃO ESTRATÉGICA DE BEM-ESTAR NO TRABALHO**.

O site/código ainda pode conter labels anteriores. Isso é uma diferença de conteúdo a revisar posteriormente e **não foi alterada sem aprovação**.

---

# 2. Decisões arquiteturais consolidadas

## 2.1 ICP não é dor

ICP responde **de que lugar profissional a pessoa fala**.

JTBD responde **o que ela está tentando realizar/resolver agora**.

Nunca inferir automaticamente um JTBD a partir do ICP.

Exemplo proibido:

`CHRO → provar ROI`

Exemplo correto:

`cargo/contexto → ICP provável`  
`fala/evidência → JTBD sustentado`

---

## 2.2 Os 45 jobs do estudo não devem virar 45 linguagens canônicas isoladas

Os 45 jobs originais contêm muitas variações contextuais do mesmo problema-raiz.

A proposta é preservar:

- os **45 códigos originais** como proveniência/evidência do estudo;
- os **6 ICPs** como contexto profissional;
- **15 jobs-raiz canônicos** como linguagem compartilhada do ecossistema;
- a nuance pelo **contexto de aplicação** da pessoa, não por uma proliferação de labels quase iguais.

Assim, por exemplo:

- “provar ROI de wellbeing para o board”;
- “usar dados de pessoas para influenciar decisões”;
- “demonstrar ROI para clientes”;
- “falar linguagem do negócio para acessar C-Suite”

não precisam ser quatro taxonomias desconectadas. São variações de um mesmo job-raiz: **traduzir pessoas/bem-estar em business case, dados e influência**, aplicado a contextos diferentes.

---

## 2.3 Os quatro “jobs” do Institute são eixos de solução, não a taxonomia do cliente

O Institute organiza hoje sua vitrine em desafios/capacidades de produto. Eles devem funcionar como **Product Intelligence**, não como substitutos dos Customer JTBDs.

Eixos canônicos propostos:

1. **Gestão Estratégica de Bem-Estar no Trabalho**
2. **Segurança Psicológica e Voz Ativa**
3. **Engajamento e Significado no Trabalho**
4. **Integração Sistêmica dos Três Desafios**

O quarto eixo não é um job independente da pessoa. Ele é um sinal de que múltiplos desafios organizacionais estão conectados e pedem uma visão integrada.

---

# 3. Taxonomia canônica de ICP

A propriedade oficial `icp` do HubSpot já possui exatamente os seis perfis relevantes. Portanto, **não criar uma nova enumeração**.

Labels canônicos:

1. `CHRO / VP de Pessoas`
2. `CEO / C-Suite`
3. `Gestor / Middle Manager`
4. `People Leader / Business Partner`
5. `Executivo Sênior / Alto Performer`
6. `Consultor / Coach / Psicólogo`

Observações:

- O estudo chama o último de “Consultor / Coach / Psicólogo Corporativo”. O HubSpot atual usa “Consultor / Coach / Psicólogo”. Para não criar uma segunda linguagem no CRM, o label do HubSpot deve ser tratado como canônico de sistema; “corporativo” continua sendo contexto, não novo valor.
- `lead_icp` com valores `ICP1/ICP3/ICP4/ICP6` é legado. **Não mapear por suposição.** Só migrar se a origem/semântica desses códigos for comprovada.
- `icp_confianca` existe e sua descrição diz escala 0–10, mas os dados antigos estão inconsistentes. Não usar os valores legados como contrato até normalização.

---

# 4. Contrato conceitual de confiança do ICP

Sem criar campo novo, a semântica desejada é:

- **9–10 / alta** — autoidentificação explícita ou fonte estruturada confiável e inequívoca.
- **7–8 / forte** — cargo/contexto profissional muito compatível, sem conflito relevante.
- **4–6 / hipótese** — inferência plausível, útil para pensar perguntas, mas insuficiente para personalização assertiva.
- **0–3 / fraca** — não usar para personalização; tratar como desconhecido.

Regra:

> ICP pode ser inferido com confiança razoável a partir do cargo/contexto. JTBD não.

Antes de qualquer implementação em HubSpot, os valores históricos de `icp_confianca` precisam ser auditados/normalizados para a escala 0–10.

---

# 5. Taxonomia proposta — 15 JTBDs canônicos

## JT01 — Sustentar performance e bem-estar pessoal no longo prazo

**Pergunta que responde:** “Como continuar performando sem consumir minha capacidade física, emocional e profissional?”

Inclui energia, recuperação, sustentabilidade, longevidade executiva e pressão crônica quando formuladas como objetivo profissional.

Não transforma diagnóstico pessoal de saúde em memória.

---

## JT02 — Preservar clareza e qualidade de decisão

**Pergunta:** “Como proteger atenção, nitidez e capacidade cognitiva para as decisões que realmente importam?”

Inclui fadiga decisória, excesso de decisões, fragmentação e perda de pensamento estratégico.

---

## JT03 — Navegar pressão, mudança e ambiguidade com adaptabilidade

**Pergunta:** “Como permanecer eficaz e adaptável quando mudança e incerteza são permanentes?”

Inclui resiliência, estabilidade sob ambiguidade e adaptação pessoal ao novo contexto.

---

## JT04 — Desenvolver líderes e gestores

**Pergunta:** “Como aumentar a capacidade real de quem lidera pessoas?”

Inclui desenvolvimento gerencial, coaching de líderes, pipeline de liderança e desenvolvimento da equipe incorporado ao trabalho.

---

## JT05 — Conduzir conversas difíceis com accountability

**Pergunta:** “Como cobrar, dar feedback e enfrentar problemas sem destruir confiança ou evitar o conflito?”

É habilidade relacional de liderança. Não é sinônimo de segurança psicológica.

---

## JT06 — Construir segurança psicológica e voz ativa

**Pergunta:** “Como criar condições para que pessoas tragam problemas, discordem, perguntem, aprendam e assumam riscos interpessoais?”

Inclui voz, confiança, aprendizagem, erro, discordância e acesso da liderança à verdade organizacional.

---

## JT07 — Estruturar gestão estratégica de bem-estar no trabalho e riscos psicossociais

**Pergunta:** “Como transformar bem-estar, saúde mental no trabalho e riscos psicossociais em gestão real, e não ações isoladas ou compliance?”

Inclui:

- NR-1;
- riscos psicossociais;
- desenho do trabalho;
- prevenção sistêmica;
- papel do gestor diante de sofrimento da equipe;
- diagnóstico → intervenção → acompanhamento;
- consultor estruturando oferta responsável nesse domínio.

Nome canônico deliberadamente centrado em **gestão estratégica de bem-estar no trabalho**.

---

## JT08 — Traduzir pessoas e bem-estar em business case, dados e influência

**Pergunta:** “Como transformar evidência de pessoas/bem-estar em argumento que influencia decisões de negócio?”

Inclui ROI, KPIs, people analytics aplicado à decisão, linguagem do board/C-Suite e aumento de influência estratégica do RH/consultor.

---

## JT09 — Fortalecer engajamento, significado e retenção

**Pergunta:** “Como criar condições para que as pessoas se conectem, contribuam, encontrem significado e queiram ficar?”

Inclui pertencimento, propósito, contribuição, motivação, reconhecimento e retenção.

---

## JT10 — Construir cultura adaptativa e resiliência organizacional

**Pergunta:** “Como fazer cultura e sistema de gestão sustentarem estratégia, mudança e performance em vez de bloqueá-las?”

Inclui cultura, coesão, confiança sistêmica, transformação e capacidade organizacional de absorver mudança.

---

## JT11 — Liderar a dimensão humana da IA e do futuro do trabalho

**Pergunta:** “Como capturar o valor da IA e das novas formas de trabalho sem perder pessoas, cultura, relevância ou qualidade da liderança?”

Inclui adoção humana de IA, redesenho de papéis, performance na era da IA e capacidades humanas complementares.

---

## JT12 — Acessar pares e perspectivas para melhores decisões

**Pergunta:** “Como sair do isolamento e ampliar perspectiva com pares que entendem a complexidade do meu papel?”

Inclui troca executiva, benchmark, networking de pares e espaços de conversa qualificada.

---

## JT13 — Estruturar e vender soluções corporativas

**Pergunta:** “Como transformar minha expertise em uma solução que empresas entendam, comprem e implementem?”

Específico sobretudo a consultores/coaches/psicólogos e profissionais independentes.

Inclui proposta de valor, estruturação da oferta, precificação e acesso ao mercado corporativo.

---

## JT14 — Construir autoridade e credibilidade baseada em ciência

**Pergunta:** “Como me diferenciar por profundidade, evidência e pensamento próprio em um mercado saturado?”

Inclui atualização científica, autoridade técnica, curadoria e posicionamento.

---

## JT15 — Escalar expertise além do 1:1

**Pergunta:** “Como multiplicar impacto e receita sem multiplicar horas na mesma proporção?”

Inclui programas, treinamentos, produtos e outras formas de productização da expertise.

---

# 6. Mapeamento dos 45 jobs originais → jobs-raiz

O objetivo não é apagar os jobs do estudo. Eles continuam como variações contextuais e proveniência.

## CHRO / VP Pessoas

- `I1J1 Desenvolver líderes e gestores para o novo contexto` → **JT04**
- `I1J2 Provar ROI de bem-estar e saúde mental para o board` → **JT08**
- `I1J4 Gerenciar riscos psicossociais e atender à NR-1` → **JT07**
- `I1J3 Criar cultura de engajamento em meio à incerteza` → **JT09**, secundário **JT10**
- `I1J5 Redesenhar performance para a era da IA` → **JT11**
- `I1J6 Cuidar da saúde mental do próprio time de RH` → **JT07** quando sistêmico; nunca persistir saúde individual identificável
- `I1J7 Construir resiliência organizacional contínua` → **JT10**
- `I1J8 Liderar adoção ética de IA em gestão de pessoas` → **JT11**

## CEO / C-Suite

- `I2J1 Manter performance sem colapsar` → **JT01**
- `I2J3 Liderar transformação humana da IA` → **JT11**
- `I2J4 Reter e engajar talentos certos` → **JT09**
- `I2J2 Quebrar isolamento com pares de confiança` → **JT12**
- `I2J5 Transformar cultura em vantagem competitiva` → **JT10**
- `I2J6 Construir segurança psicológica real` → **JT06**
- `I2J7 Desenvolver pipeline de liderança` → **JT04**
- `I2J8 Longevidade executiva como estratégia` → **JT01**

## Gestor / Middle Manager

- `I3J1 Gerenciar próprio burnout sem perder autoridade` → **JT01**, com proteção de sensibilidade
- `I3J2 Identificar sofrimento mental da equipe e agir` → **JT07**
- `I3J4 Manter energia e propósito sob pressão constante` → **JT01**, secundário **JT03/JT09** conforme a fala
- `I3J3 Ter conversas difíceis com honestidade` → **JT05**
- `I3J5 Desenvolver equipe sem tempo para isso` → **JT04**
- `I3J7 Cumprir NR-1 na prática do dia a dia` → **JT07**
- `I3J6 Navegar IA sem se tornar obsoleto` → **JT11**, com componente pessoal de **JT03** quando explícito

## People Leader / Business Partner

- `I4J2 Desenvolver gestores que liderem pessoas de verdade` → **JT04**
- `I4J1 Ser reconhecido como parceiro estratégico` → **JT08**
- `I4J3 Implementar NR-1 transformando compliance em cultura` → **JT07**, secundário **JT10**
- `I4J4 Usar dados de pessoas para influenciar decisões` → **JT08**
- `I4J5 Provar ROI dos programas de bem-estar` → **JT08**
- `I4J6 Cuidar do próprio bem-estar sem culpa` → **JT01**, com proteção de sensibilidade
- `I4J7 Dominar coaching de líderes` → **JT04**

## Executivo Sênior / Alto Performer

- `I5J1 Proteger capacidade de decidir sob pressão crônica` → **JT02**
- `I5J2 Sustentar alta performance sem destruir saúde` → **JT01**
- `I5J3 Recuperar nitidez mental após sobrecarga` → **JT02**
- `I5J4 Romper isolamento sem comprometer autoridade` → **JT12**
- `I5J5 Desescalar estresse sem sinalizar fraqueza` → **JT01**, com proteção de sensibilidade
- `I5J6 Gerenciar budget cerebral para decisões que importam` → **JT02**
- `I5J7 Resiliência emocional para ambiguidade permanente` → **JT03**
- `I5J8 Bem-estar pessoal como vantagem competitiva` → **JT01**

## Consultor / Coach / Psicólogo

- `I6J1 Vender e estruturar serviços para empresas` → **JT13**
- `I6J2 Demonstrar ROI das intervenções para clientes` → **JT08**
- `I6J3 Usar NR-1 como porta de entrada corporativa` → **JT07** como domínio da solução + **JT13** como intenção comercial
- `I6J6 Falar linguagem do negócio para acessar C-Suite` → **JT08**
- `I6J4 Construir autoridade em mercado saturado` → **JT14**
- `I6J5 Escalar além do atendimento individual 1:1` → **JT15**
- `I6J7 Aplicar ciência validada para ter credibilidade` → **JT14**

---

# 7. Como preservar nuance sem multiplicar taxonomia

A mesma família de JTBD precisa ser interpretada dentro do **escopo real da fala**.

Exemplo — JT07:

- gestor: “o que eu faço com riscos psicossociais no meu time?”
- HRBP: “como integro NR-1 à gestão/cultura?”
- CHRO: “como estruturo uma estratégia de bem-estar e risco?”
- consultor: “como construo uma oferta responsável nessa agenda?”

Não são quatro taxonomias. É o mesmo job-raiz em quatro contextos de aplicação.

No Passo 3, verificar se o contexto de aplicação já cabe naturalmente em `participante_memoria`/`contexto_profissional` antes de criar qualquer campo.

Escopos úteis para raciocínio, **ainda não aprovados como campos**:

- pessoa/própria capacidade;
- equipe;
- organização;
- cliente/mercado.

---

# 8. Regras para reconhecimento de JTBD

## Evidência forte

- pessoa declara diretamente problema, objetivo ou decisão;
- pergunta revela intenção concreta;
- descreve uma situação atual que corresponde claramente ao job.

Exemplo:

> “Preciso provar para o CFO que nosso programa de wellbeing gera valor.”

→ JT08, alta confiança.

## Evidência média

- pessoa descreve contexto que sugere fortemente um job, mas objetivo/prioridade ainda não está totalmente explícito.

Pode sustentar hipótese e uma pergunta discriminante curta.

## Evidência fraca

- apenas cargo/ICP;
- apenas estatística do estudo;
- apenas comportamento típico daquele perfil.

Nunca gravar como job ativo da pessoa.

### Regra operacional

Se o job já está claro, **não perguntar novamente**.

Perguntar apenas quando a resposta pode mudar materialmente:

- o job identificado;
- a prioridade;
- o tipo de solução relevante;
- a recomendação.

---

# 9. Estado/prioridade do JTBD

Uma pessoa pode ter vários jobs simultâneos.

Conceitualmente distinguir:

- **hipótese** — plausível, ainda sem evidência suficiente;
- **observado** — sustentado pela conversa/evidência;
- **ativo/prioritário** — é o problema que está “em placa” agora;
- **histórico** — já foi relevante e pode ser reutilizado como contexto, mas não domina automaticamente a conversa atual.

Não criar enum/campo novo antes do Passo 3. Primeiro verificar como isso se encaixa no modelo de memória vivo.

---

# 10. Proteção de dados sensíveis

Os jobs JT01/JT02/JT03 podem aparecer em conversas sobre burnout, ansiedade, depressão, medicação ou outras condições pessoais.

Regra:

- usar a informação sensível para responder com cuidado no contexto atual quando necessário;
- **não persistir diagnóstico, condição de saúde, medicação, afastamento ou inferência de saúde pessoal**;
- não persistir um JTBD derivado exclusivamente de uma informação sensível pessoal;
- um objetivo profissional não sensível pode ser persistido quando explicitamente formulado, por exemplo: “quero melhorar minha gestão de energia e performance sustentável”.

Temas de equipe/empresa (ex.: burnout da organização, absenteísmo, riscos psicossociais) são contexto profissional e podem ser tratados como tal, sem identificar saúde de terceiros.

---

# 11. Institute — o que podemos extrair das fontes atuais

## 11.1 Posicionamento institucional útil

O `joinmind.com.br` posiciona o Mind Institute como formações executivas que transformam ciência em ação estratégica e promovem bem-estar, liderança e capacidades do futuro do trabalho.

Capacidades transversais observadas nas páginas atuais:

- ciência de ponta aplicada ao contexto corporativo;
- frameworks práticos;
- aplicação no trabalho real;
- metodologia Learn–Apply–Reflect;
- aprendizagem em cohort/comunidade;
- credenciais/badges;
- formação para líderes, RH e especialistas.

Isso é Product Intelligence relativamente estável.

## 11.2 Eixo 1 — Gestão Estratégica de Bem-Estar no Trabalho

**Nome conceitual aprovado nesta rodada:** Gestão Estratégica de Bem-Estar no Trabalho.

O conteúdo atual da formação suporta capacidades como:

- compreender bem-estar como sistema de gestão, não benefício;
- identificar ativos e riscos psicossociais;
- conectar diagnóstico ao desenho do trabalho;
- escolher intervenções baseadas em evidência;
- estruturar plano de ação e acompanhamento;
- construir business case e indicadores;
- conectar NR-1 a gestão e performance.

Fit provável com: **JT07, JT08, JT10** e, em alguns contextos, JT04.

## 11.3 Eixo 2 — Segurança Psicológica e Voz Ativa

Capacidades observadas:

- diagnosticar/medir segurança psicológica;
- fortalecer confiança e voz;
- liderar conversas difíceis;
- integrar accountability e segurança psicológica;
- transformar diagnóstico em plano de mudança;
- atuar nos níveis pessoa/equipe/organização.

Fit provável: **JT06, JT05, JT04, JT10**.

## 11.4 Eixo 3 — Engajamento e Significado no Trabalho

Capacidades observadas:

- compreender trabalho significativo;
- fortalecer comunidade/pertencimento;
- tornar contribuição visível;
- reconhecimento;
- autonomia e crescimento;
- conectar significado a engajamento, retenção e performance.

Fit provável: **JT09**, com relações secundárias a JT04/JT10.

## 11.5 Eixo 4 — Integração Sistêmica

A certificação integra os três eixos anteriores.

Não usar como “job da pessoa”. Usar quando a necessidade real cruza múltiplas dimensões e a pessoa busca formação mais abrangente.

---

# 12. Dash — o que podemos extrair de `joinmind.com.br`

O site atual descreve o Mind Dash como **consultoria/assessoria estratégica em bem-estar para organizações**, com rigor científico e foco em alta performance organizacional.

Capacidades/posicionamento que podem virar Product Intelligence após aprovação:

- diagnóstico/assessoria organizacional;
- soluções integradas e sob medida;
- saúde mental e bem-estar corporativo;
- prevenção de burnout em nível organizacional;
- fortalecimento de cultura;
- desenvolvimento de liderança saudável;
- performance sustentável;
- aplicação de base científica internacional;
- possibilidade de colaboração com especialistas internacionais, incluindo Jan-Emmanuel De Neve/Oxford, quando aplicável à entrega real.

O site também posiciona o Dash como ponte entre organizações no Brasil e expertise acadêmica internacional em bem-estar organizacional.

### Regra de fit conceitual

Dash **não entra porque a pessoa tem determinado ICP**.

Ele começa a ganhar fit quando o job:

1. é **organizacional**, não apenas de aprendizado individual;
2. exige **diagnóstico, desenho, estratégia, intervenção ou implementação**;
3. não se resolve apenas com formação/repertório;
4. existe uma entrega atual do Dash capaz de atender ao problema.

Jobs-raiz com fit potencial forte, dependendo do contexto: **JT07, JT08, JT10, JT04, JT06, JT09**.

Nenhum desses mappings deve virar regra rígida de venda.

---

# 13. Distinção futura Summit × Institute × Dash

Isto ainda pertence a Product Fit/Decisioning, não à taxonomia do cliente, mas a leitura atual sugere uma distinção útil:

### Summit

Bom fit quando a pessoa busca:

- repertório amplo;
- descoberta;
- perspectivas/especialistas;
- networking;
- atualização;
- inspiração aplicada;
- exploração de diferentes caminhos.

### Institute

Bom fit quando a pessoa busca:

- desenvolver competência;
- aprofundar um domínio;
- aprender metodologia/frameworks;
- aplicar no próprio trabalho;
- formação estruturada;
- credencial.

### Dash

Bom fit quando a organização precisa:

- diagnóstico;
- desenho de estratégia;
- implementação;
- intervenção customizada;
- apoio organizacional continuado.

Essa distinção deve depois ser validada contra Product Intelligence atual antes de virar Decisioning.

---

# 14. O que NÃO deve ser usado automaticamente como verdade comercial

A leitura das páginas públicas revelou conteúdo comercial com combinações de:

- “próxima turma em breve”;
- períodos antigos de inscrição;
- mais de um preço/oferta na mesma página;
- bônus e datas promocionais históricas.

Conclusão:

> site público é uma boa fonte para **necessidades, posicionamento, currículo e capacidades**; preço, lote, disponibilidade, data de turma, link de checkout e oferta devem vir da fonte comercial operacional atual.

Não copiar automaticamente preço/disponibilidade do site para Intelligence sem reconciliação.

---

# 15. Diferenças de conteúdo identificadas — NÃO ALTERAR SEM APROVAÇÃO

1. O `mindinstitute`/site atual usa expressões como “Estruturar saúde mental e bem-estar” e slug técnico `gestao-saude-mental`.
2. Adriana definiu nesta rodada que o conceito/job correto para nossa arquitetura é **Gestão Estratégica de Bem-Estar no Trabalho**.
3. Não alterar slug, site, cards, programa ou checkout nesta etapa.
4. Em etapa posterior, decidir com Adriana se:
   - muda apenas o label de vitrine;
   - muda o nome conceitual interno;
   - mantém slug técnico legado invisível;
   - há outras ocorrências que também precisam ser atualizadas.

---

# 16. Menor arquitetura recomendada para o próximo passo

Não implementar ainda.

No Passo 3, investigar como representar a taxonomia acima usando **a infraestrutura de memória já existente**, priorizando:

- `intelligence.participante_memoria` como casa durável da Customer Intelligence;
- `analise_concierge` como extrator natural de contexto/ICP/JTBD, se a implementação em curso do Claude continuar compatível;
- o `icp` oficial do HubSpot como linguagem de ICP, quando/onde houver writeback apropriado;
- uma única taxonomia canônica de JTBD compartilhada pelos agentes.

Evitar:

- tabela nova só para “perfil do cliente” sem necessidade;
- segunda enum de ICP;
- 45 enums de JTBD;
- `ICP → produto` hardcoded;
- `JTBD → produto` hardcoded;
- duplicar Product Intelligence dentro do analisador de pessoa.

---

# 17. Pontos que precisam de aprovação antes de congelar/implementar

1. **15 jobs-raiz** como taxonomia canônica.
2. Manter os 45 códigos originais apenas como proveniência/variação contextual.
3. Usar os seis labels atuais do HubSpot como ICP canônico.
4. Tratar os quatro desafios do Institute como Product Intelligence, com primeiro eixo = **Gestão Estratégica de Bem-Estar no Trabalho**.
5. Usar `joinmind.com.br`/site do Institute como fonte de posicionamento/capacidades, mas não de verdade comercial sem reconciliação.
6. Tratar Dash como solução de nível organizacional quando o job exige diagnóstico/estratégia/implementação — nunca apenas por ICP.

Até essa aprovação, este arquivo é **proposta de Step 2**, não implementação.
