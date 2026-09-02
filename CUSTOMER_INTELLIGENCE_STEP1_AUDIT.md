# Customer Intelligence — Passo 1: auditoria do sistema real

Status: **AUDITORIA READ-ONLY CONCLUÍDA**  
Data: 2026-09-02  
Sistema principal auditado: Supabase `mind-agent` (`ymnmotgglsrxmjmonwjz`) + GitHub `Mind-Institute/mind-agent`  
Dependências adicionais auditadas: `Mind-Institute/mind-catalog-sync`, Supabase comercial `mind-hubpost` (`aelmxpsgjrqwujadeuop`) e `Mind-Institute/mindinstitute`.

Nenhuma implementação de Customer Intelligence foi feita nesta etapa. As únicas escritas desta frente foram documentação no GitHub.

---

# 1. Objetivo da auditoria

Responder, antes de modelar ICP/JTBD:

- o que já existe;
- quais tabelas, funções, Edge Functions e fluxos participam;
- o que está realmente em uso e o que é placeholder/legado;
- quais dependências existem;
- o que já resolve parte do problema;
- qual é a menor mudança que parece necessária;
- quais fatos contradizem a arquitetura que imaginávamos inicialmente.

Fonte conceitual desta frente: `CUSTOMER_INTELLIGENCE_ICP_JTBD_PLAN.md` + documento original recebido de Adriana `Pasted markdown(20260902-051127).md`.

---

# 2. Observação de concorrência

Durante esta auditoria, Claude Code estava implementando os Passos 5 e 6 do Concierge.

O sistema vivo já apresentava mudanças compatíveis com esse trabalho, por exemplo:

- `analise_concierge` passou a estar ativo;
- `analise_projetar_memoria` ganhou gate específico de sensibilidade do Concierge;
- `mindagent_chat_get_context` passou a devolver memória durável e `rota_ativa`;
- `mindagent_chat_save_interests` deixou de promover memória permanente.

Portanto, este relatório é um **snapshot factual durante uma implementação concorrente**.

Antes de implementar a frente ICP/JTBD, revalidar somente os pontos diretamente afetados pelo trabalho do Claude — especialmente análise automática de conversas do App e leitura universal de memória.

Não modificar os mesmos objetos enquanto a entrega atual não estiver fechada/revisada.

---

# 3. Conclusão executiva

## 3.1 Não precisamos de uma nova arquitetura de Customer Intelligence

A espinha dorsal já existe e está em uso:

```text
CONVERSA
  ↓
analisar-conversa
  ↓
analise_classificador
  ↓
analisador(es) especializados
  ↓
intelligence.analise_conversa
  ↓
analise_projetar_memoria(customer_memory)
  ↓
intelligence.participante_memoria
  ↓
contexto do Agent
```

A principal casa viva da memória de cliente é hoje:

`intelligence.participante_memoria`

Não `participante_contexto`, não `participante_objetivos` e não uma tabela nova ainda inexistente.

## 3.2 O maior gap não é banco: é linguagem canônica + consumo universal

Faltam principalmente:

1. consolidar uma taxonomia canônica de JTBD sem duplicar linguagens existentes;
2. reconciliar os dois campos de ICP já existentes no HubSpot;
3. ensinar o analisador a extrair ICP/JTBD com evidência/confiança;
4. fazer a memória ativa ser consumida de forma universal entre canais/rotas;
5. conectar Customer Intelligence à Product Intelligence atual sem hardcode por produto.

## 3.3 O Product Intelligence do Institute já existe em partes — mas em casas separadas

A hipótese inicial “não temos catálogo atual do Institute” estava incompleta.

Existe:

- catálogo operacional/comercial no projeto `mind-hubpost`;
- mirror desse catálogo dentro do `mind-agent` em `eduzz.produto_catalogo`;
- conteúdo profundo dos programas no repositório `Mind-Institute/mindinstitute`;
- mas `catalogo.produtos`, Kits e Knowledge do `mind-agent` ainda não transformam isso numa Product Intelligence utilizável pelos Agents.

Logo, o gap futuro é **normalização/consumo**, não coleta do zero.

---

# 4. Mapa conceitual: o que já existe e qual casa deve ser preservada

| Conceito | Casa existente | Uso real hoje | Gap | Menor direção recomendada |
|---|---|---|---|---|
| Identidade da pessoa | `pessoas.pessoas` + `engagement.identidades` | ativo/canônico | nenhum estrutural | preservar |
| Cargo/empresa/contexto factual | pessoa + CRM + `participante_memoria` | ativo | fontes podem divergir por recência | usar fatos atuais + memória, sem nova tabela |
| ICP | HubSpot `icp`, `lead_icp`; mirror `crm.contato_espelho`; `mind_crm_fatos` | parcialmente ativo | duas linguagens; confiança inconsistente | adotar/reconciliar `icp` de 6 valores; não criar terceira enumeração |
| JTBD canônico | **não existe** | — | linguagem ainda fragmentada | consolidar no Passo 2 antes de escolher persistência da definição |
| JTBD da pessoa | pode caber em `participante_memoria` | ainda não extraído como JTBD | categoria/contrato não existe | provável extensão pequena da memória atual, decisão no Passo 3 |
| Objetivos/interesses/preferências | `participante_memoria`; `analise_concierge` | ativo/em implantação | ainda sem código JTBD | reaproveitar |
| Contexto reconstruído | `participante_contexto` | praticamente inativo | não é projeção viva hoje | não ressuscitar como segunda verdade sem consumidor real |
| Estado comercial | `analise_conversa` + `continuidade_comercial` | muito ativo no Summit | só Summit hoje | preservar separado de Customer Intelligence |
| Recomendação registrada | `intelligence.recomendacoes` | 0 linhas / sem writer real | placeholder | não usar agora |
| Objetivos estruturados | `intelligence.participante_objetivos` | 0 linhas | placeholder | não usar agora |
| Sinais comerciais | `intelligence.sinais_comerciais` | 1 linha | praticamente inativo | não duplicar estado comercial atual |
| Conteúdo Summit | sessions + speakers + `summit_2026.knowledge_documents` | ativo | retrieval Summit-only | preservar e depois generalizar consumo |
| Conteúdo Institute | repo `mindinstitute/src/content` | ativo no site | não chega aos Agents | futura Product Intelligence |
| Catálogo operacional Institute | `mind-hubpost.produto_catalogo` → mirror `eduzz.produto_catalogo` | ativo | não alimenta `catalogo.produtos`/Kit do Agent | normalizar/consumir mirror existente |
| Dash | registro/repo existem, mas rota/produto Agent inativos | não executável no Core atual | Product Intelligence não pronta | investigar apenas quando entrar no Passo 5 |

---

# 5. Customer Intelligence real hoje

## 5.1 Pós-conversa é a principal infraestrutura de aprendizado

Edge Function ativa:

`analisar-conversa`

Fluxo real:

1. busca conversa pendente;
2. monta `conversation_context` + transcrito + pessoa + CRM;
3. executa `analise_classificador`;
4. executa um ou mais analisadores permitidos;
5. grava em `intelligence.analise_conversa`;
6. `analise_gravar` projeta `dados.customer_memory` através de `analise_projetar_memoria`;
7. memória vai para `intelligence.participante_memoria`;
8. para análise comercial, sincroniza também continuidade comercial.

Whitelist da Edge já contempla:

- `analise_vendas_summit`
- `analise_vendas_institute`
- `analise_vendas_dash`
- `analise_atendimento`
- `analise_concierge`

Portanto: **não criar outro pipeline de extração de cliente sem necessidade**.

---

## 5.2 O que está efetivamente analisando conversas hoje

`intelligence.analise_conversa` tinha, no snapshot da auditoria:

- 597 análises;
- todas de `analise_vendas_summit`;
- nenhum histórico ainda de `analise_concierge`.

`analise_concierge` já estava ativo durante a auditoria, mas ainda sem histórico projetado no momento medido.

### Ponto crítico

`public.analise_pendentes` filtrava apenas:

```text
agente in ('treble', 'treble-inbound-agent')
```

Ou seja: o cron automático de 15 minutos processava conversas do WhatsApp/Treble, **não as conversas do App `mindagent-chat`**.

Isto precisa ser **revalidado depois que Claude fechar a entrega atual**. Se continuar assim, será o principal gap para o Concierge realmente aprender automaticamente com as conversas do App.

Não corrigir agora em paralelo.

---

## 5.3 `analise_concierge` já é a casa natural para extração rica da pessoa

O prompt vivo já extrai:

- cargo/função;
- empresa;
- objetivos;
- interesses;
- problemas/desafios profissionais;
- preferências;
- conteúdos/palestrantes desejados;
- escolhas/recusas;
- restrições práticas;
- contexto comercial observável;
- memória factual com scope/confiança/sensibilidade.

Também já estabelece:

- usar conversa inteira;
- não exigir repetição para confirmar contexto anterior;
- não registrar psicologia inferida;
- não inventar agenda pessoal;
- bloquear memória sensível.

**Conclusão:** depois que a taxonomia JTBD estiver consolidada, a menor solução é provavelmente **estender este analisador**, não criar `analise_icp_jtbd` separado.

Isso preserva uma função clara: `analise_concierge` = aprender quem é a pessoa e o que é útil para personalização futura.

A classificação comercial continua nos analisadores de venda.

---

# 6. Memória: casa ativa vs. casas que parecem certas, mas não estão em uso

## 6.1 `intelligence.participante_memoria` — ATIVA

É a casa que recebe `customer_memory` do pós-conversa.

No snapshot havia aproximadamente 1.296 linhas, com fatos de:

- identidade;
- cargo;
- empresa;
- objetivo;
- interesse;
- preferência;
- preferência comercial;
- restrição;
- logística;
- stakeholder;
- delegação;
- patrocínio;
- outros.

A maior parte veio de `analise_vendas_summit`.

A estrutura já oferece:

- `tipo`;
- `chave`;
- `valor jsonb`;
- confiança;
- origem;
- status (`ativa`, `proposta`, `substituida`);
- validade;
- importância;
- vínculo à análise de conversa.

Isto já resolve quase tudo que precisamos para armazenar **evidência sobre a pessoa**.

### Direção mínima futura

Não criar `participante_jtbd` automaticamente.

Primeiro testar se a memória existente pode receber de forma limpa algo como tipos canônicos `icp` / `jtbd`, preservando código, label, evidência, confiança e scope no `valor` JSONB.

A decisão final pertence ao Passo 3, depois da taxonomia.

---

## 6.2 `intelligence.participante_contexto` — NÃO É a casa viva que parecia

Embora tenha campos muito atraentes:

- `contexto_profissional`
- `necessidades`
- `resultados_desejados`
- `temas_relevantes`
- `preferencias`
- `prioridades_atuais`
- `contexto_comercial`

na prática havia apenas **3 linhas**:

- 0 com contexto profissional;
- 0 com necessidades;
- 0 com resultados desejados;
- 3 com temas relevantes;
- 0 com preferências;
- 0 com prioridades atuais;
- 0 com contexto comercial.

Não foi encontrado writer ativo reconstruindo essa tabela.

Além disso, a implementação em andamento do Concierge passou a ler diretamente `participante_memoria`.

### Conclusão

**Não transformar `participante_contexto` em segunda fonte da verdade só porque o schema parece perfeito.**

Se no futuro for útil como projeção/cache, deve ser derivada da memória canônica e ter um consumidor concreto. Hoje não é requisito.

---

## 6.3 Estruturas existentes mas não ativas

- `intelligence.participante_objetivos`: 0 linhas
- `intelligence.recomendacoes`: 0 linhas
- `intelligence.perguntas_feitas`: 0 linhas
- `intelligence.dossies`: 0 linhas
- `intelligence.sinais_comerciais`: 1 linha
- `concierge.ciclo_estado`: 0 linhas

Não usar estas tabelas como arquitetura só porque seus nomes combinam com o problema.

Elas são, neste momento, **schema preparado/placeholder**, não fluxo vivo.

---

# 7. O ICP já existe — e há duas linguagens que precisam ser reconciliadas

## 7.1 Campo novo/correto do HubSpot: `icp`

O cache vivo de propriedades do HubSpot mostra um enum `icp` com exatamente estes seis valores:

1. `CHRO / VP de Pessoas`
2. `CEO / C-Suite`
3. `Gestor / Middle Manager`
4. `People Leader / Business Partner`
5. `Executivo Sênior / Alto Performer`
6. `Consultor / Coach / Psicólogo`

Isto coincide com a taxonomia do documento recebido.

`crm.contato_espelho` já espelha:

- `icp`
- `icp_confianca`

E `public.mind_crm_fatos` já entrega esses campos aos contextos de Intelligence.

### Conclusão

**Não criar uma nova enumeração de ICP no `mind-agent`.**

A linguagem canônica de ICP deve se alinhar a esses seis valores existentes.

---

## 7.2 Campo antigo: `lead_icp`

Também existe uma propriedade antiga:

- ICP1
- ICP3
- ICP4
- ICP6

Ela está amplamente populada:

- ICP3: 1.658
- ICP4: 777
- ICP1: 326
- ICP6: 39

O próprio metadata do HubSpot não traz descrição/mapeamento semântico desses códigos.

Não assumir que `ICP1 = CHRO`, etc., apenas por semelhança numérica com o estudo.

### Tratamento recomendado

- `lead_icp` = evidência/segmentação legada que pode continuar sendo lida historicamente;
- `icp` = linguagem atual de seis perfis;
- qualquer migração/mapeamento do legado exige evidência real antes de escrever.

---

## 7.3 `icp_confianca` ainda não tem contrato estável

Valores encontrados:

- 0.70
- 0.85
- 0.90
- 0.95
- 10

Ou seja, há mistura provável de escalas 0–1 e 0–10.

Antes de usar `icp_confianca` no Agent/Decisioning, normalizar o contrato e a origem de escrita. Não interpretar `10` como 100% sem verificar quem escreve.

---

# 8. JTBD: não existe taxonomia canônica no Core — mas existe uma segunda linguagem no Institute

## 8.1 No `mind-agent`

Não foi encontrada tabela/enum/coluna canônica de JTBD.

Existem referências genéricas a:

- `participante_contexto.necessidades`
- `participante_objetivos.dor_codigo`
- `knowledge_documents.problema`
- `knowledge_documents.resultado_desejado`

Mas nenhuma delas é hoje a taxonomia viva de jobs do cliente.

Portanto, **há um gap real de referência canônica JTBD**.

---

## 8.2 O site do Mind Institute já usa `job_id`

Repo: `Mind-Institute/mindinstitute`.

O site de formações já trabalha com:

- `job_id`
- `scope`
- `origin`

`JobId` permitido:

- `saude-mental`
- `voz-ativa`
- `significado`
- `integrado`

Esses `job_id`s alimentam o seletor e são enviados ao formulário como contexto.

Eles correspondem diretamente aos quatro caminhos atuais do site:

- estruturar saúde mental e bem-estar;
- construir confiança e voz ativa;
- fortalecer engajamento e significado;
- integrar os três desafios.

### Isso é importante, mas não é a mesma coisa que a nova taxonomia Customer JTBD

Os `job_id` do Institute são hoje **jobs de escolha de produto** — uma linguagem compacta desenhada para escolher entre quatro programas.

O documento ICP/JTBD contém jobs mais específicos, contextuais e transversais ao ecossistema.

Exemplo:

`construir_segurança_psicológica_real` pode ter fit com `voz-ativa`, mas não são necessariamente o mesmo objeto semântico.

### Regra para o Passo 2

Não substituir um pelo outro e não manter duas taxonomias concorrentes sem mapa.

Precisamos decidir:

- quais são os **Customer JTBDs canônicos**;
- quais `job_id` atuais do Institute são **categorias de Product Fit/chooser**;
- como um Customer JTBD pode mapear para uma ou várias capacidades/produtos.

---

# 9. Product Intelligence: três casas já existem e precisam ser conectadas, não recriadas

## 9.1 Registro universal no `mind-agent`

`catalogo.produtos` é o vocabulário canônico do Core.

Hoje:

- `mind-summit-2026` = ativo + vende
- `mind-institute` = inativo + não vende
- produtos Institute 2025 = inativos
- `mind-dash` = inativo + não vende

Se olhássemos só para esta tabela, concluiríamos incorretamente que o Institute não tem oferta atual.

---

## 9.2 Catálogo operacional/comercial real

Existe um sistema separado:

- repo `Mind-Institute/mind-catalog-sync`
- Supabase `mind-hubpost` / `aelmxpsgjrqwujadeuop`
- `public.produto_catalogo`
- `public.eduzz_produtos`

Ele resolve Eduzz → produto → pipeline HubSpot e já tem pipeline próprio do Institute.

No snapshot:

- 178 produtos/SKUs mapeados no total;
- 59 classificados como Institute;
- 54 dos 59 com status Eduzz `active`;
- 36 não arquivados;
- apenas **2 liberados para o funil**.

Isto prova:

**Eduzz ativo ≠ oferta que o agente pode vender.**

`liberado_para_funil` é uma condição operacional importante, mas ainda não necessariamente a regra completa de disponibilidade pública ao consumidor.

---

## 9.3 Esse catálogo já está espelhado no `mind-agent`

Existe:

`eduzz.produto_catalogo`

com as mesmas 178 linhas e campos de Institute.

O mirror estava atualizado em 2026-09-02 05:20 UTC no snapshot.

Existe a função:

`espelho_gravar('produto_catalogo', ...)`

Portanto:

**não precisamos criar nova integração entre bancos para começar Product Intelligence.**

O problema real é que `catalogo.produtos`, Kits e retrieval dos Agents ainda não transformam/consomem este mirror como catálogo lógico atual do Institute.

---

## 9.4 Conteúdo atual dos produtos Institute já tem outra fonte forte

Repo `Mind-Institute/mindinstitute` contém o site atual das formações.

A fonte central do produto está em `src/content/`.

O site publica quatro caminhos:

- Gestão Estratégica de Saúde Mental e Bem-Estar no Trabalho
- Segurança Psicológica Aplicada à Inovação
- Engajamento e Significado no Trabalho
- Certificação Avançada em Liderança e Saúde Mental Positiva

O modelo de conteúdo já possui:

- necessidade na voz do cliente;
- sinais;
- transformação;
- capacidades;
- módulos;
- formato;
- entregáveis;
- especialistas;
- investimento/CTA.

O README declara, no snapshot:

- estado comercial público: `Próxima turma em breve`;
- sem checkout no site;
- conversão = captura de interesse.

### Implicação

Product Intelligence futura precisa combinar **duas espécies diferentes de verdade**:

1. **conteúdo/capacidade/fit** → fonte atual do produto (site/repo ou futura CMS);
2. **disponibilidade/transação** → catálogo comercial/CRM/Eduzz.

Não usar uma como substituta da outra.

---

# 10. Knowledge/retrieval atual é Summit-only

## 10.1 Institute/Dash Knowledge existem como schemas, mas estão vazios

- `institute.knowledge_documents`: 0
- `institute.knowledge_chunks`: 0
- `dash.knowledge_documents`: 0
- `dash.knowledge_chunks`: 0

A estrutura desses documentos já prevê campos úteis como:

- `problema`
- `resultado_desejado`
- `produto_codigo`
- `audiencia`
- `cluster`
- validade
- `agents`

Mas não há conteúdo vivo ali hoje.

Não popular copiando a mesma taxonomia ICP/JTBD em cada vertical — isso criaria três fontes para o mesmo conceito.

---

## 10.2 Ferramentas de Intelligence estão hardcoded no Summit

`mind_intelligence_buscar` e `mind_intelligence_ler` leem:

- `mind-summit-2026`
- `summit_2026.knowledge_documents`
- sessões Summit
- `ecossistema.palestrantes_especialistas`

Ou seja: o Concierge pode investigar profundamente Summit, mas não usar a mesma ferramenta para Institute/Dash hoje.

---

## 10.3 `mind_agent_kit` ainda não carrega Knowledge universal

A função retorna:

```json
"knowledge": []
```

Os Kits atuais carregam playbook + `structured` + tools.

Não existe ainda a camada transversal de Knowledge institucional/Customer Intelligence que imaginamos.

---

## 10.4 `mind.organization_content` não é solução pronta

A tabela existe, mas:

- 0 linhas;
- categorias fixas voltadas a conteúdo institucional/evento (`sobre`, `missao`, `historia`, `produto`, `faq`, etc.);
- único consumidor encontrado: `api.treble_event_bundle`.

Não usá-la para ICP/JTBD apenas porque é transversal.

---

# 11. Summit já possui matéria-prima boa para fit JTBD → conteúdo

Não precisamos hardcodar `JTBD → palestrante` no documento de ICP.

Já existem no sistema:

## `summit_2026.sessions`

- `trilhas`
- `topicos_aprendizado`
- `resultados`
- descrição/tipo/nível

## `ecossistema.palestrantes_especialistas`

- `dores_e_problemas_que_ajuda_a_compreender`
- `relevancia_para_os_icps_do_mind`
- contribuições
- conceitos
- o que aprender
- limites científicos

Isto permite um fit muito mais robusto:

`JTBD da pessoa → necessidade semântica → sessão/especialista atual`

em vez de tabela rígida:

`I1J1 → palestrante X`.

---

# 12. Rotas Institute/Dash existem no vocabulário, mas não são executáveis hoje

`agentes.canal_competencia` contém `institute` e `dash`, porém inativos no App e WhatsApp.

`agentes.kit_blocos` não tem Kit configurado para Institute/Dash.

`agentes.prompts`:

- `analise_vendas_institute`: inativo/vazio
- `analise_vendas_dash`: inativo/vazio
- não há playbook ativo de Institute/Dash para execução pelo Agent

Portanto:

- as rotas já fazem parte da taxonomia universal;
- os produtos/agentes ainda não estão implementados como lanes executáveis.

Não precisamos resolver isso para construir Customer Intelligence compartilhada. A Customer Intelligence deve nascer independente dessas lanes e estar pronta para elas quando forem ativadas.

---

# 13. Consumo da memória ainda não é universal

Durante a implementação concorrente, `mindagent_chat_get_context` já passou a devolver:

- `participant_profile`
- `interests`
- `memories` de `participante_memoria`
- `rota_ativa`

Isso é correto para o App.

Entretanto, `public.mind_agent_context`, a porta universal de fatos pessoa/CRM/engagement, ainda não inclui `participante_memoria` no snapshot auditado.

Logo existe uma assimetria:

- App: memória durável já começa a voltar ao Agent;
- contexto universal: ainda não.

### Menor direção futura

Depois que Claude fechar, verificar se isto continua verdadeiro.

Se sim, a melhor correção não é criar outro Customer Context. É **fazer a memória canônica aparecer na porta universal existente**, preservando regras de privacidade/sensibilidade.

---

# 14. O que é vivo, o que é placeholder e o que é legado

## Vivo / usar como base

- `pessoas.pessoas`
- `engagement.identidades`
- `engagement.conversas/mensagens`
- `crm.contato_espelho`
- `mind_crm_fatos`
- `mind_crm_comercial`
- `analisar-conversa`
- `analise_classificador`
- `analise_vendas_summit`
- `analise_concierge` (novo/concorrente, revalidar após Claude)
- `intelligence.analise_conversa`
- `intelligence.participante_memoria`
- `intelligence.continuidade_comercial` para estado comercial
- `catalogo.produtos` como vocabulário do Core
- `eduzz.produto_catalogo` como mirror comercial
- `summit_2026.sessions`
- `summit_2026.knowledge_documents`
- `ecossistema.palestrantes_especialistas`
- repo `mindinstitute/src/content` para conteúdo atual Institute

## Placeholder / schema sem uso suficiente

- `participante_objetivos`
- `recomendacoes`
- `perguntas_feitas`
- `dossies`
- `concierge.ciclo_estado`
- a maior parte de `participante_contexto`
- `institute.knowledge_*`
- `dash.knowledge_*`
- `mind.organization_content`

Não remover agora; apenas **não construir a nova arquitetura sobre elas sem consumidor real**.

## Legado / linguagem a não expandir

- `lead_icp` com códigos ICP1/3/4/6, até que haja mapeamento comprovado;
- docs antigos do Core que contradizem runtime atual;
- produtos 2025 do `catalogo.produtos` como fonte de oferta atual.

---

# 15. Contradições importantes à arquitetura imaginada inicialmente

## Contradição 1 — “Precisamos criar uma casa para o perfil da pessoa”

Não.

`participante_memoria` já é a casa viva suficiente para a evidência durável sobre a pessoa.

## Contradição 2 — “`participante_contexto` parece ser a tabela certa para ICP/JTBD”

O nome/schema sugere isso, mas o sistema real não usa essa tabela como projeção viva. Torná-la canônica agora criaria outra fonte.

## Contradição 3 — “Não existe ICP atual no sistema”

Existe. O HubSpot já possui exatamente os seis valores novos em `icp`.

## Contradição 4 — “Os códigos ICP1... podem ser os códigos do estudo”

Não há evidência disso. Não mapear por palpite.

## Contradição 5 — “Não existe catálogo atual do Institute”

Existe catálogo operacional separado e ele já é espelhado no `mind-agent`.

O que não existe é Product Intelligence do Institute pronta para os Agents.

## Contradição 6 — “Precisamos inventar uma integração de catálogo”

Não. O mirror `eduzz.produto_catalogo` já existe e estava fresco.

## Contradição 7 — “JTBD é uma linguagem nova no ecossistema”

Não inteiramente. O site do Institute já usa quatro `job_id`s próprios. Eles precisam ser reconciliados com a nova taxonomia, não ignorados.

## Contradição 8 — “O pós-conversa do Concierge já aprenderá automaticamente com o App”

No snapshot, não: `analise_pendentes` ainda selecionava apenas Treble. Revalidar após Claude.

---

# 16. Menor arquitetura que eu recomendaria — SEM IMPLEMENTAR AINDA

A recomendação abaixo é direção para os próximos passos; não é autorização de mudança antes do Passo 2/3.

## 16.1 Não criar tabela de perfil/ICP da pessoa

Usar:

- fatos pessoa/CRM como evidência;
- `participante_memoria` para conhecimento durável aprendido.

## 16.2 Não criar `participante_jtbd` ainda

Depois de consolidar a taxonomia, testar uma extensão mínima do contrato `customer_memory` com tipos canônicos como:

- `icp`
- `jtbd`

A memória já oferece confiança, origem, status, validade e JSONB suficiente para armazenar código/label/evidência/scope.

Se isso ficar semanticamente limpo, nenhuma tabela de associação nova é necessária.

## 16.3 Não criar novo analisador

Estender `analise_concierge` para reconhecer ICP/JTBD, porque sua responsabilidade já é conhecer a pessoa e personalizar interações futuras.

Separar:

- ICP = hipótese de contexto profissional;
- JTBD = somente quando sustentado por evidência;
- prioridade/job ativo = recência + fala/ação concreta.

## 16.4 Preservar `analise_vendas_*` para estado comercial

Não empurrar Customer Intelligence para o Sales analyzer apenas porque hoje ele é o mais usado.

Vendas pode consumir Customer Intelligence e continuar responsável por estado/estratégia comercial.

## 16.5 Tornar memória universal, não criar outro Context

Após fechar Claude, se `mind_agent_context` ainda não carregar memória, estender a porta universal existente.

## 16.6 Criar uma única referência canônica de JTBD somente depois do Passo 2

Hoje não existe casa adequada e ativa para **definições** dos jobs.

É possível que seja necessária uma estrutura compartilhada pequena para definição da taxonomia, porque:

- não deve morar no prompt;
- não deve ser duplicada em Summit/Institute/Dash;
- precisa ser usada por análise e Decisioning;
- precisa ter códigos estáveis e metadata/proveniência.

Mas só decidir essa estrutura quando a taxonomia consolidada existir e tivermos consumidores concretos definidos.

## 16.7 Product Intelligence: consumir fontes já existentes

Future pipeline conceitual:

```text
CATÁLOGO COMERCIAL / MIRROR
+ CONTEÚDO CANÔNICO DO PRODUTO
      ↓
PRODUCT INTELLIGENCE NORMALIZADA
      ↓
FIT JTBD ↔ CAPACIDADE / PRODUTO
```

Não copiar manualmente todas as ofertas Eduzz para o Agent.

## 16.8 `job_id` do Institute não vira Customer JTBD automaticamente

Tratá-lo como sinal explícito de escolha/necessidade quando chegar de uma interação do site, mas mapear para a taxonomia canônica somente por relação aprovada.

---

# 17. Dependências que o Passo 2 deve levar consigo

Ao consolidar a taxonomia ICP/JTBD, consultar obrigatoriamente:

1. fonte original `Pasted markdown(20260902-051127).md`;
2. enum atual do HubSpot `icp`;
3. legado `lead_icp` sem assumir mapping;
4. `Mind-Institute/mindinstitute/src/content/types.ts` (`JobId`);
5. `Mind-Institute/mindinstitute/src/content/catalogo.ts` (jobs de escolha dos programas);
6. campos `topicos_aprendizado` / `resultados` das sessões Summit;
7. campos de dores/relevância ICP dos especialistas;
8. `analise_concierge` vivo depois do fechamento do Claude.

Pergunta central do Passo 2:

> Quais são os jobs canônicos do CLIENTE — independentes de produto — e como as linguagens existentes (I1J1..., Institute job_id, CRM ICP) se relacionam com eles sem se tornarem sinônimos falsos?

---

# 18. Segurança encontrada durante a investigação

A auditoria read-only do Supabase também retornou avisos de segurança que **não pertencem ao escopo funcional de ICP/JTBD**, mas precisam ser registrados.

No projeto comercial `mind-hubpost`, duas tabelas `public` estão com RLS desabilitado:

- `public.replay_funil_5d_queue`
- `public.blinket_snapshot_2026`

O advisor informa que tabelas `public` sem RLS podem ficar expostas a papéis `anon/authenticated`, dependendo dos grants/Data API.

Também houve avisos de RLS desabilitado em tabelas de outros schemas/projetos durante a inspeção do `mind-agent`.

**Nenhuma correção foi aplicada**, porque este passo era read-only e habilitar RLS sem revisar policies pode quebrar fluxos existentes.

Isto deve virar uma frente de segurança separada/priorizada conscientemente — não ser misturado na implementação Customer Intelligence sem decisão.

---

# 19. Definition of Done do Passo 1

Atendido:

- [x] documentação canônica/operacional revisada;
- [x] Customer Intelligence atual auditada;
- [x] memory writers/readers auditados;
- [x] analisadores e cron auditados;
- [x] ICP existente no CRM auditado;
- [x] ausência de JTBD canônico confirmada;
- [x] linguagem `job_id` do Institute identificada;
- [x] Product Intelligence Summit auditada;
- [x] catálogo comercial Institute localizado;
- [x] mirror do catálogo no `mind-agent` confirmado;
- [x] conteúdo atual do Institute localizado;
- [x] Institute/Dash routes/Kits auditados;
- [x] estruturas vivas vs. placeholder diferenciadas;
- [x] menor direção arquitetural definida sem implementação.

---

# 20. Próximo passo

**Não implementar ainda.**

Aguardar Claude fechar os Passos 5/6 atuais do Concierge.

Depois:

1. revisar e documentar o que Claude realmente implementou;
2. atualizar docs canônicos/checkpoint;
3. limpar a raiz conforme combinado, consolidando arquivos transitórios;
4. revalidar apenas:
   - `analise_pendentes` para App;
   - `analise_concierge`;
   - `mindagent_chat_get_context`;
   - `mind_agent_context`;
5. executar **PASSO 2 — consolidar taxonomia canônica ICP/JTBD**.

O Passo 2 deve ser feito como arquitetura/conteúdo antes de qualquer migration.
