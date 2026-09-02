# Customer Intelligence do Mind — Passo 3: contrato da pessoa

Status: **PROPOSTA FECHADA PARA APROVAÇÃO — NÃO IMPLEMENTADA**  
Data: 2026-09-02  
Escopo: definir o que o sistema aprende sobre uma pessoa, como representa evidência/confiança/recência e quais casas existentes usa. **Nenhuma alteração em banco, HubSpot, prompt, Edge Function ou runtime foi feita neste passo.**

---

# 1. Fontes e decisões anteriores

Este contrato parte de:

- `CUSTOMER_INTELLIGENCE_ICP_JTBD_PLAN.md`;
- `CUSTOMER_INTELLIGENCE_STEP1_AUDIT.md`;
- `CUSTOMER_INTELLIGENCE_STEP2_TAXONOMY.md` — APROVADO/FROZEN;
- documento-fonte “Índice. ICPs e jobs to be done para o agente do Mind Summit 2026”;
- Supabase vivo `ymnmotgglsrxmjmonwjz`;
- HubSpot vivo, especialmente propriedades `icp`, `icp_confianca` e `lead_icp`.

Decisões já fechadas que este contrato preserva:

1. ICP diz de que contexto profissional a pessoa vem; não determina sua dor.
2. JTBD diz o que a pessoa está tentando resolver/realizar e precisa de evidência.
3. Os seis ICPs canônicos são os seis valores da propriedade `icp` do HubSpot.
4. Os 15 JTBDs canônicos do Passo 2 são a linguagem compartilhada do ecossistema.
5. Os 45 jobs do estudo permanecem como proveniência/nuance, não como 45 classificações concorrentes.
6. Customer Intelligence é compartilhada entre Summit, Institute, Dash e demais agentes.
7. Estado comercial permanece separado de Customer Intelligence.
8. Dados pessoais sensíveis não entram em memória durável.

---

# 2. Achados do sistema real que determinam o contrato

Snapshot no início deste passo:

| estrutura | linhas | leitura arquitetural |
|---|---:|---|
| `intelligence.participante_memoria` | 1.337 | casa viva de memória durável |
| `engagement.session_interests` | 68 | memória rápida da sessão |
| `intelligence.participante_contexto` | 3 | praticamente inativo; só `temas_relevantes` preenchido |
| `intelligence.participante_objetivos` | 0 | placeholder, não fluxo vivo |
| `intelligence.recomendacoes` | 0 | placeholder, não fluxo vivo |
| `intelligence.sinais_comerciais` | 1 | praticamente inativo |

Conclusão: **não criar nova tabela e não ressuscitar tabelas vazias só porque os nomes parecem adequados.**

A casa durável para ICP/JTBD será, salvo nova evidência no Passo 4:

`intelligence.participante_memoria`

Ela já tem:

- `tipo`;
- `chave`;
- `valor jsonb`;
- `confianca` 0–1;
- `origem`;
- `status` (`proposta`, `ativa`, `substituida`, `rejeitada`, `expirada`);
- `valido_ate`;
- `criado_em` / `atualizado_em`;
- `substituida_por`;
- `analise_conversa_id`;
- `evidencia_message_id`.

O índice único `(participante_id, chave) WHERE status='ativa'` já garante uma única memória ativa por chave.

---

# 3. Decisão central: memória não é Decisioning

A Intelligence NÃO deve armazenar como verdade estática:

`job_prioritario_atual = JT07`

A mesma pessoa pode ter vários jobs reais, e qual deles está “em placa” depende da conversa, do momento e do produto em questão.

Portanto:

## Intelligence guarda

- ICP sustentado;
- JTBDs que a pessoa efetivamente expressou;
- contexto específico em que cada job apareceu;
- objetivos;
- interesses;
- preferências;
- restrições/contexto profissional permitido;
- confiança;
- recência;
- proveniência.

## Decisioning decide em cada turno

- qual job é mais relevante agora;
- se existe um job principal e secundários;
- se uma memória antiga ainda deve influenciar a conversa;
- se vale fazer uma pergunta discriminante;
- qual produto/conteúdo é a próxima etapa coerente.

Regra canônica:

> `status='ativa'` em `participante_memoria` significa **memória confiável e válida**, não “prioridade atual da pessoa”.

Isso evita criar um estado que envelhece silenciosamente e começa a mentir.

---

# 4. Contrato conceitual da pessoa

O estado de Customer Intelligence que os Agents/Decisioning devem conseguir receber é conceitualmente:

```json
{
  "professional_context": {
    "role": "...",
    "company": "...",
    "icp": {
      "value": "People Leader / Business Partner",
      "confidence": 0.9,
      "source": "memory | crm"
    }
  },
  "jobs_observed": [
    {
      "code": "JT04",
      "label": "Desenvolver líderes e gestores",
      "context": "precisa desenvolver os gestores que apoia sem transformar isso em treinamento isolado",
      "confidence": 0.9,
      "scope": "opportunity",
      "last_seen_at": "..."
    }
  ],
  "goals": [],
  "interests": [],
  "preferences": [],
  "constraints": [],
  "decision_context": {
    "stakeholders": [],
    "relevant_constraints": []
  }
}
```

Isto é **contrato de leitura**, não proposta de nova tabela/coluna.

`decision_context` é agrupamento derivado de memórias já existentes (`stakeholder`, `constraint`, `goal` etc.), não nova casa de persistência.

---

# 5. Contexto profissional e identidade

Não duplicar identidade em Customer Intelligence.

Casas canônicas existentes:

- `pessoas.pessoas` — pessoa, cargo, empresa e identidade consolidada;
- `engagement.identidades` — identificadores/evidências de identidade;
- `crm.contato_espelho` / `mind_crm_fatos` — fatos atuais do CRM.

`participante_memoria` pode continuar registrando cargo/empresa que a própria pessoa atualiza em conversa, porque isso preserva evidência e recência, mas não nasce uma segunda tabela de perfil.

Quando houver conflito, a fala atual e explícita da pessoa é evidência mais forte para a conversa atual do que um CRM potencialmente desatualizado. A correção da casa canônica é outro fluxo; este contrato não autoriza writeback automático.

---

# 6. ICP — contrato

## 6.1 Valores canônicos

Usar exatamente os **internal values reais** da propriedade HubSpot `icp`:

1. `CHRO / VP de Pessoas`
2. `CEO / C-Suite`
3. `Gestor / Middle Manager`
4. `People Leader / Business Partner`
5. `Executivo Sênior / Alto Performer`
6. `Consultor / Coach / Psicólogo`

Não criar slug/código paralelo para ICP sem consumidor concreto.

`lead_icp` (`ICP1`, `ICP3`, `ICP4`, `ICP6`) continua legado e **não participa desta classificação** enquanto sua semântica não for comprovada.

## 6.2 Persistência mínima em `participante_memoria`

Quando a classificação vier de conversa/análise:

```text
tipo   = icp
chave  = icp_atual
valor  = {
  "text": "People Leader / Business Partner",
  "scope": "stable",
  "evidence_kind": "self_declared | structured_crm | role_inference"
}
confianca = 0..1
origem = analise_concierge
status = ativa | proposta
```

`icp_atual` é chave fixa deliberadamente: só pode existir **um ICP atual ativo** por pessoa.

Se nova evidência confiável mudar o ICP, a linha anterior vira `substituida` e aponta para a nova, usando o mecanismo que a tabela já possui.

## 6.3 Evidência e confiança

### Pode virar `ativa`

- autoidentificação explícita;
- cargo/função atual inequívoco e compatível com um dos seis perfis;
- classificação estruturada confiável sem evidência atual conflitante.

### Fica `proposta`

- inferência plausível, mas ambígua;
- contexto profissional incompleto;
- títulos que podem pertencer a mais de um ICP.

### Não classificar

- somente campanha/origem;
- somente produto comprado;
- somente interesse em um tema;
- somente JTBD;
- qualquer tentativa de inferir ICP a partir de traço psicológico.

O Agent nunca precisa expor a etiqueta ICP para a pessoa.

## 6.4 HubSpot como seed, não segunda linguagem

`crm.contato_espelho` já possui `icp` e `icp_confianca`.

O `icp` pode servir como classificação estruturada quando não houver memória mais atual e explícita em conflito.

`icp_confianca` tem contrato declarado 0–10 no HubSpot, mas os dados históricos estão inconsistentes (há valores em 0–1 e valores até 10). **Não usar essa coluna histórica como confiança canônica antes de normalizá-la.**

Escala interna de Customer Intelligence permanece 0–1, porque `participante_memoria.confianca` já usa essa escala.

Quando houver futuro writeback para HubSpot, a conversão de escala é responsabilidade da borda CRM; não mudamos a escala interna do sistema.

---

# 7. JTBD — contrato

## 7.1 Um participante pode ter vários JTBDs

Cada um usa uma chave estável:

```text
jtbd:JT01
jtbd:JT02
...
jtbd:JT15
```

Exemplo:

```text
tipo  = jtbd
chave = jtbd:JT07
valor = {
  "code": "JT07",
  "text": "Estruturar gestão estratégica de bem-estar no trabalho e riscos psicossociais",
  "context": "quer transformar NR-1 em gestão real e mobilizar os gestores",
  "scope": "opportunity",
  "evidence_kind": "explicit_statement"
}
confianca = 0.90
origem = analise_concierge
status = ativa
```

O `context` é importante porque os 45 jobs originais foram consolidados em 15 jobs-raiz. Ele preserva **como aquele job aparece para aquela pessoa** sem proliferar taxonomias.

Não armazenar o código antigo `I1J4`, `I4J3` etc. em cada pessoa apenas por proveniência. O estudo continua preservado nos documentos da taxonomia; a pessoa precisa do job canônico + contexto real dela.

## 7.2 O que sustenta um JTBD

### Alta confiança / memória ativa

- a pessoa declara o problema ou resultado que quer atingir;
- a pessoa descreve situação concreta que semanticamente equivale ao job;
- evidências convergentes deixam o job inequívoco.

### Média confiança / proposta

- comportamento/escolha oferece sinal relevante, mas o job ainda não foi realmente estabelecido;
- contexto é consistente, mas poderia significar mais de um job.

### Não é evidência suficiente

- ICP da pessoa;
- cargo isoladamente;
- campanha/origem;
- página visitada;
- conteúdo que o Agent recomendou;
- assunto que apareceu apenas nos dados oficiais;
- compra passada;
- uma pergunta informacional isolada;
- interesse temático isolado quando não revela o problema que a pessoa tenta resolver.

Regra absoluta:

> **ICP pode gerar hipótese de onde investigar. Nunca confirma JTBD.**

## 7.3 Interesse não é JTBD

Exemplos:

`"Quero ver a Amy Edmondson"`
→ interesse em Amy / possivelmente segurança psicológica  
→ **não basta** para gravar JT06.

`"Meu time evita trazer problema e discordar de mim; quero mudar isso"`
→ JT06 sustentado.

`"Tem formação de segurança psicológica?"`
→ interesse/comercial Institute  
→ só vira JT06 se a conversa revelar a necessidade que a pessoa tenta resolver.

---

# 8. Objetivo, resultado desejado, interesse e contexto de decisão

Não criar novas casas.

Usar os tipos já existentes em `participante_memoria`:

| conceito | tipo existente |
|---|---|
| resultado/objetivo concreto | `objetivo` |
| tema/conteúdo relevante | `interesse` |
| preferência de formato/abordagem | `preferencia` |
| restrição real | `restricao` |
| pessoa/grupo cuja aprovação/participação importa | `stakeholder` |
| contexto de delegação | `delegacao` |
| necessidade logística permitida | `logistica` |

`contexto da decisão` é a combinação factual desses itens, não um novo campo.

Exemplo:

> “Preciso convencer o board a aprovar uma agenda de bem-estar baseada em dados.”

Pode gerar:

- JT08 — business case/dados/influência;
- objetivo — conseguir aprovação/estruturar business case;
- stakeholder — board;

Não precisamos de `decision_context` persistido separadamente.

---

# 9. Hipótese, fato e uso pelo Agent

O banco já tem os dois estados necessários:

## `status='proposta'`

Hipótese útil, ainda insuficiente para tratar como fato.

- pode ser corroborada por análise futura;
- não deve ser apresentada pelo Agent como verdade sobre a pessoa;
- não precisa ser carregada no prompt operacional comum.

## `status='ativa'`

Memória sustentada o suficiente para reutilização.

- pode entrar no Customer Intelligence entregue ao Agent;
- ainda deve ser usada com linguagem proporcional à evidência;
- `ativa` não significa “prioridade atual”.

Não criar `confirmed=true`, `is_hypothesis`, enum paralelo ou outra taxonomia para o mesmo conceito.

---

# 10. Recência, prioridade e validade

## 10.1 Recência

Usar `atualizado_em` existente.

Não criar `last_seen_at` no banco: o contrato de leitura pode expor `atualizado_em` como `last_seen_at`.

Repetição do mesmo JTBD aumenta evidência/recência, mas não cria nova linha se a chave canônica é a mesma.

## 10.2 Prioridade atual

Não persistir como fato estático.

Decisioning calcula usando, em ordem de força:

1. fala atual explícita;
2. contexto recente da conversa;
3. JTBDs confiáveis observados recentemente;
4. demais memórias históricas relevantes.

Se a pessoa disser “minha prioridade agora é X”, X vence no turno atual.

Se uma memória for antiga e não houver reforço recente, o Agent pode usá-la como histórico (“você tinha comentado que...”), não como certeza de prioridade atual.

## 10.3 Validade

Não inventar TTL de 30/60/90 dias.

`valido_ate` só deve ser usado quando houver uma validade real conhecida/explicitada.

Para necessidades profissionais sem prazo explícito, recência + contexto atual orientam o Decisioning.

---

# 11. Contradição e correção de memória

Nova evidência explícita vence inferência antiga.

Usar os estados que já existem:

- `substituida` — fato de valor único mudou, como ICP/cargo/empresa;
- `rejeitada` — hipótese estava errada e foi explicitamente corrigida;
- `expirada` — fato/contexto tinha validade e deixou de valer.

Exemplos:

> “Não sou mais CHRO; hoje atuo como consultora.”

→ novo `icp_atual = Consultor / Coach / Psicólogo` se a evidência sustentar; ICP anterior `substituida`.

> “Você entendeu errado: NR-1 não é uma prioridade minha.”

→ uma hipótese JT07 pode ser `rejeitada`.

> “Isso era uma prioridade no ano passado, agora não é mais.”

→ não tratar o job como prioridade atual; se houver evidência clara de encerramento, pode ser `expirada` na projeção futura.

A análise histórica em `intelligence.analise_conversa` preserva que aquilo já apareceu; não precisamos manter como memória ativa algo que a pessoa corrigiu.

---

# 12. Memória durável vs. memória rápida vs. contexto reconstruído

## A. Memória rápida — `engagement.session_interests`

Serve à conversa/sessão atual.

- interesse novo de conteúdo;
- personalização imediata;
- evidência ligada à mensagem.

Não é Customer Intelligence durável e não é casa de ICP/JTBD.

## B. Memória durável — `intelligence.participante_memoria`

Serve à continuidade pessoa-wide entre canais/produtos.

Pode guardar, quando permitido e sustentado:

- ICP;
- JTBD;
- objetivo;
- interesse;
- preferência;
- restrição profissional;
- stakeholder/contexto útil;
- outros fatos não sensíveis relevantes.

## C. Contexto reconstruído

Vem de fatos atuais externos/canônicos a cada leitura:

- pessoa/cargo/empresa;
- CRM;
- produtos comprados;
- categoria de ingresso;
- estado comercial atual;
- conversa atual.

Não copiar tudo para memória só para “ter junto”.

---

# 13. O que NÃO entra em Customer Intelligence durável

- saúde pessoal do titular;
- diagnóstico/medicação/afastamento;
- saúde de terceiro identificável;
- religião, opinião política, orientação sexual, origem racial/étnica, filiação sindical;
- CPF/documentos/códigos/segredos;
- psicologia inferida;
- opinião do Agent sobre personalidade;
- problema operacional momentâneo depois de resolvido, salvo contexto não sensível realmente útil;
- saudação;
- pergunta informacional isolada;
- preço consultado;
- recomendação feita pelo Agent sem adesão da pessoa;
- produto/oferta como se fosse característica do cliente;
- estado de funil comercial como JTBD;
- “B2B/B2C” como ICP;
- agenda/reserva inferida pelo sistema: só o que a própria pessoa contou quando útil.

---

# 14. Comercial continua separado

Customer Intelligence responde:

> Quem é esta pessoa profissionalmente e que problemas/resultados ela revelou?

Commercial/Decisioning responde:

> Existe uma oportunidade? De qual produto? Em qual estágio? Qual próximo avanço comercial?

Portanto:

- interesse em preço não vira JTBD;
- compra não vira ICP;
- ICP não vira intenção de compra;
- JTBD não prova que a pessoa quer comprar;
- `analise_vendas_*`, CRM e continuidade comercial continuam responsáveis pelo estado comercial.

Customer Intelligence pode enriquecer a estratégia comercial, mas não substitui essa camada.

---

# 15. Leitura compartilhada entre todos os Agents

## Achado atual

Hoje os leitores estão fragmentados:

- `mindagent_chat_get_context` lê `participante_memoria` para o App;
- `mind_agent_context` já lê pessoa + CRM + commercial + engagement, mas não `participante_memoria`;
- `mind_crm_fatos` já expõe `icp` e `icp_confianca`;
- o runtime atual do App achata valores de memória dentro de `personalization_profile.interesses`, perdendo `tipo`.

Isso **não serve** ao contrato futuro: um JTBD não pode chegar ao Agent como se fosse apenas mais um “interesse”.

## Menor direção recomendada no Passo 4

Criar **um único leitor derivado**, sem nova casa de verdade, por exemplo:

`mind_customer_intelligence(p_pessoa_id)`

Responsabilidade única:

- ler pessoa/CRM onde necessário;
- ler `participante_memoria` ativa e não expirada;
- agrupar por tipo;
- resolver ICP de forma determinística;
- devolver a estrutura do contrato deste documento;
- não decidir prioridade/job atual;
- não decidir produto;
- não escrever nada.

Consumidores:

- `mindagent_chat_get_context`;
- `mind_agent_context` / runtimes WhatsApp;
- futuros Agents Institute/Dash.

Esta função é uma **projeção de leitura**, não segunda fonte da verdade. O ganho concreto é impedir que cada canal reconstrua Customer Intelligence de um jeito diferente.

Não implementar ainda; validar no Passo 4 contra o estado final da PR #54.

---

# 16. Correções mínimas já identificadas para o Passo 4

Sem implementar neste passo, a investigação mostrou que o futuro patch precisará ao menos avaliar:

1. **`analise_montar_contexto`**
   - hoje entrega `lead_icp` legado ao analisador;
   - precisa entregar `icp` canônico;
   - `icp_confianca` só pode ser usado depois de resolver os dados históricos inconsistentes.

2. **`analise_concierge`**
   - continua sendo o mecanismo natural de aprendizado da pessoa;
   - precisa reconhecer as categorias `icp` e `jtbd`;
   - precisa conhecer os 6 ICPs + 15 JTBDs canônicos;
   - precisa emitir código JTBD e contexto da aplicação;
   - não deve inferir JTBD a partir de ICP.

3. **`analise_projetar_memoria`**
   - precisa mapear `icp` e `jtbd` como tipos próprios, não `outro`;
   - `icp_atual` precisa usar substituição;
   - `jtbd:JTxx` precisa deduplicar por código e atualizar evidência/recência;
   - preservar gate de sensibilidade.

4. **read path universal**
   - preservar tipos em vez de achatar tudo em interesses;
   - disponibilizar Customer Intelligence igualmente para App/WhatsApp/futuros canais.

5. **pipeline pós-conversa do App**
   - a correção já foi solicitada na revisão da PR #54;
   - revalidar antes de mexer nesta frente.

Não incluir Product Intelligence nem Product Fit neste patch; são Passos 5 e 6 desta frente.

---

# 17. Exemplos completos

## Exemplo A — HRBP com job claro

Pessoa:

> “Sou HRBP e preciso desenvolver os gestores que apoio. Eles evitam conversas difíceis e eu preciso dar mais repertório para eles.”

Customer Intelligence possível:

- ICP: `People Leader / Business Partner` — alta confiança;
- JT04 Desenvolver líderes e gestores — alta confiança;
- JT05 Conversas difíceis com accountability — alta confiança;
- objetivo: aumentar repertório dos gestores;
- interesse: liderança/conversas difíceis.

Nada precisa ser perguntado para “confirmar” o que já está claro.

## Exemplo B — tema sem job suficiente

Pessoa:

> “Quero muito ver a Amy Edmondson.”

Memória:

- interesse em Amy Edmondson.

Não gravar automaticamente:

- ICP;
- JT06 segurança psicológica;
- intenção de compra.

## Exemplo C — problema organizacional

Pessoa:

> “Minha empresa precisa sair de ações pontuais de bem-estar. Tenho que estruturar NR-1, envolver gestores e levar um plano para o board.”

Possível Customer Intelligence:

- JT07 Gestão estratégica de bem-estar/riscos psicossociais;
- JT08 Business case/dados/influência;
- objetivo: estruturar plano organizacional;
- stakeholder: board;
- contexto: mobilização de gestores.

Isto futuramente pode fazer Decisioning considerar Dash/Institute/Summit conforme a pergunta e o produto atual — **não grava Dash como destino da pessoa**.

---

# 18. Definition of Done do Passo 3

O contrato está correto se:

- [x] usa casas existentes como fonte da verdade;
- [x] não cria nova tabela;
- [x] representa os 6 ICPs sem segunda enumeração;
- [x] representa múltiplos JTBDs por pessoa com os 15 códigos canônicos;
- [x] preserva contexto sem reabrir 45 labels;
- [x] diferencia memória confiável de hipótese usando `ativa` / `proposta` já existentes;
- [x] não persiste “job prioritário atual” como verdade estática;
- [x] define recência sem TTL arbitrário;
- [x] define substituição/correção usando estados já existentes;
- [x] mantém comercial separado;
- [x] mantém dados sensíveis fora da memória durável;
- [x] identifica o gap real do read path universal;
- [x] deixa um Passo 4 mínimo e testável, sem Product Intelligence nem Product Fit.

---

# 19. Decisões propostas para aprovação

1. `intelligence.participante_memoria` continua sendo a casa durável de Customer Intelligence.
2. Novos tipos sem nova tabela: `icp` e `jtbd`.
3. ICP usa `chave='icp_atual'` e os valores exatos do HubSpot.
4. JTBD usa `chave='jtbd:JT01' ... 'jtbd:JT15'`.
5. `valor.context` preserva a nuance real do job da pessoa.
6. `status='ativa'` significa memória válida, não prioridade atual.
7. Job prioritário atual é Decisioning, não persistência.
8. `atualizado_em` é a recência; nenhum TTL artificial.
9. `proposta/ativa/substituida/rejeitada/expirada` são suficientes; não criar novos estados.
10. `participante_contexto`, `participante_objetivos`, `recomendacoes` e `sinais_comerciais` não serão recrutados para esta frente sem consumidor real.
11. `lead_icp` legado não entra no contrato.
12. Escala interna de confiança permanece 0–1; eventual HubSpot 0–10 é conversão de borda.
13. Comercial permanece separado de Customer Intelligence.
14. No Passo 4, preferir um leitor compartilhado de Customer Intelligence a duplicar lógica em App/WhatsApp.

Se aprovado, este documento vira constraint para o Passo 4.