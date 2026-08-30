# Go-live 30/08/2026 — Vendedor Summit + Concierge Summit

> **Ordem operacional congelada para a entrega de hoje.**
>
> Este arquivo NÃO redefine a arquitetura do `PROJECT_STATE.md`. Ele transforma a arquitetura já congelada em uma sequência executável para o go-live de hoje, preservando dependências, critérios de pronto e limites de escopo para que Codex/Claude possam continuar sem depender da conversa.
>
> Em caso de conflito conceitual, valem as taxonomias e contratos canônicos do `PROJECT_STATE.md`. Para a ordem tática desta entrega, vale este arquivo até o fechamento do go-live.

---

## 0. Objetivo e definição de pronto

Entregar hoje dois produtos operacionais sobre o mesmo Core/Intelligence:

1. **Vendedor Summit**
   - entende `summit_b2c` e `summit_b2b`;
   - usa fatos atuais de evento, ingressos, inclusões, ofertas, regras comerciais e volume;
   - conduz compra sem inventar preço/regra;
   - responde via fluxo real do Treble/WhatsApp;
   - faz handoff quando existe necessidade real.

2. **Concierge Summit**
   - responde programação, horários, espaços, sessões e palestrantes;
   - usa `summit_2026.sessions` + `ecossistema.palestrantes_especialistas` + vínculos canônicos;
   - encontra conteúdo relevante e faz recomendação útil com os dados realmente disponíveis;
   - não inventa informação quando a Intelligence não resolve;
   - usa o mesmo Core, não um segundo backend paralelo.

**"Tudo hoje" significa tudo que muda o comportamento/experiência necessária desses dois produtos.** Limpeza de legado, abstração elegante, generalização hipotética, hardening não relacionado ao go-live e refactors sem efeito no usuário não entram no caminho crítico.

---

## 1. Regras de execução para hoje

Ritual continua obrigatório:

```text
INVESTIGAR O TRECHO ATUAL
→ ENTENDER O QUE JÁ EXISTE
→ DECIDIR A MENOR MUDANÇA
→ IMPLEMENTAR
→ TESTAR SÓ O AFETADO
→ VERIFICAR PRODUÇÃO
→ DOCUMENTAR ESTADO FINAL
→ SEGUIR
```

Regras adicionais desta entrega:

- não reinvestigar decisão já fechada;
- não abrir frente lateral enquanto houver passo anterior bloqueando o go-live;
- não construir segunda linguagem/taxonomia para conceito existente;
- não criar novo componente se o existente resolve corretamente com pequena mudança;
- merge em `main` é boundary de deploy;
- preview/teste relevante antes do merge quando disponível;
- alterações destrutivas, segurança/RLS/auth/secrets, preço/regra comercial, source of truth, outbound/disparo e decisões de negócio não congeladas continuam exigindo gate explícito;
- se uma espera técnica puder ser usada para adiantar investigação do próximo passo sem alterar sistema, pode paralelizar; não mudar a ordem de deploy/dependências;
- se um passo estourar o timebox por descoberta nova, registrar o bloqueio exato e proteger o restante do caminho crítico; não transformar em redesign.

---

# ORDEM DE EXECUÇÃO

## PASSO 1 — Fechar programação + palestrantes canônicos

### Para que serve

Permite ao Concierge saber, deterministicamente, **quem participa de qual sessão** e usar um único ID de pessoa do Ecossistema.

### Estado já fechado

- site atual: 77 sessões;
- `sessions.site_session_id`: 77/77 preenchidos e distintos;
- 8 Alumni Talks já existem em produção;
- `ecossistema.palestrantes_especialistas`: 64 pessoas;
- 31 dossiês ricos originais preservados;
- 33 pessoas novas com identidade + bio mínima do site;
- `speakers.json`: 63/63 pessoas resolvem para ID canônico;
- `programacao.json`: 83 ocorrências pessoa×sessão brutas;
- Sibelle Pedral e Virginie Leite: **fora por decisão** — não criar pessoa, não criar vínculo, não contar como pendência;
- ocorrências relevantes: **81/81 já resolvidas**;
- papéis esperados: 77 `palestrante`, 3 `mediacao`, 1 `apresentacao`;
- 63 pessoas em 60 sessões;
- 12 vínculos atuais já estão contidos nas 81 ocorrências.

### 1A — PR #37

Conteúdo:

- migration `20260830170000_sessions_flags_canonicos.sql`;
- versiona/reconcilia `lugares_limitados` e `reserva_recomendada`;
- `precisa_reserva` permanece somente compatibilidade legada;
- documentação do estado da programação/speakers.

Critério de pronto:

- preview verde;
- 281 migrations;
- última migration `20260830170000`;
- colunas/comments corretos;
- zero alteração indevida de dados.

Então mergear em `main` e verificar somente o efeito afetado em produção.

### 1B — PR #38

Migration deve ficar cronologicamente entre #37 e #36:

`20260830173000_session_speakers_speaker_id_canonico.sql`

Contrato fechado:

```sql
speaker_id bigint NOT NULL
PK (sessao_id, speaker_id)
palestrante_id uuid NULL  -- legado físico apenas
speaker_id FK -> ecossistema.palestrantes_especialistas(id)
```

Não criar UUID legado novo.
Não remover fisicamente `palestrante_id` hoje.

Depois do merge da #37:

1. atualizar branch #38 com `main`;
2. criar fresh preview;
3. validar somente:
   - `speaker_id NOT NULL`;
   - `palestrante_id` nullable;
   - PK `(sessao_id, speaker_id)`;
   - FK para Ecossistema preservada;
   - 12 linhas existentes preservadas;
   - zero duplicata;
   - smoke test de `mindagent_chat_search` sem regressão.

Se tudo corresponder ao contrato, mergear #38.

Ledger esperado após #38 em produção: **282 migrations**.

### 1C — backfill dos vínculos

Depois da #38 em produção:

- source: `Mind-Institute/mindsummit2026/src/data/programacao.json` atual;
- sessão: `programacao.json.id = summit_2026.sessions.site_session_id`;
- pessoa: `ecossistema.palestrantes_especialistas.id`;
- gravar `session_speakers.speaker_id`;
- não preencher `palestrante_id` em vínculos novos;
- operação idempotente por `(sessao_id, speaker_id)`;
- preservar papel explícito da source;
- default `palestrante` quando papel não vier informado;
- ignorar Sibelle Pedral, Virginie Leite e placeholders.

Critério de pronto:

- 81/81 ocorrências relevantes ligadas;
- 63 pessoas;
- 60 sessões com speakers;
- 77 `palestrante`;
- 3 `mediacao`;
- 1 `apresentacao`;
- zero vínculo sem `speaker_id`;
- zero duplicata `(sessao_id, speaker_id)`;
- zero Sibelle/Virginie.

**Depois disso, speakers deixa de ser frente ativa.** Enriquecimento editorial dos 33 mínimos fica para depois do go-live.

---

## PASSO 2 — Fechar Kit Loader universal mínimo — PR #36

### Para que serve

O Kit Loader esconde a topologia física da Intelligence. O Agent pede o Kit da rota e recebe apenas o que precisa para aquele turno.

Para `summit_b2c`:

- playbook;
- evento;
- inclusões;
- ofertas vigentes;
- regras comerciais.

Para `summit_b2b`:

- tudo acima;
- preços por volume.

`mind_kit_meta(rota)` responde se o Kit está configurado e realmente disponível. Isso evita o agente executar sem uma verdade obrigatória e inventar resposta.

### Contratos já congelados

Provider:

> SQL `NULL` = não consegue entregar a verdade mínima prometida pelo bloco. Payload JSON não-nulo = bloco disponível.

`mind_kit_meta(p_rota)`:

```text
ok
rota
kit_configurado
kit_disponivel
blocos_obrigatorios
blocos_ausentes
```

`mind_agent_kit(p_rota, p_conversa_id, p_necessidade)` sucesso:

```text
playbook
structured
knowledge=[]
tools=[]
meta
```

### Correções obrigatórias antes do merge

1. `mind_agent_kit` deve validar nesta precedência:

```text
rota_invalida
→ sem_conversa
→ conversa_nao_encontrada
→ success
```

Usar `engagement.conversas` **schema-qualified**.

Manter:

```text
SET search_path = public, agentes
```

Não adicionar `engagement` ao search_path.

2. Corrigir metadata histórica da função de volume, sem reescrever body:

```sql
ALTER FUNCTION public.mind_precos_por_volume() STABLE;
```

### Ordem

Depois de #37 + #38:

1. merge latest `main` na branch #36;
2. aplicar somente as duas correções acima;
3. criar fresh preview de verdade;
4. validar ledger completo;
5. testar somente providers/meta/loader e regressões diretamente afetadas.

Ledger esperado no preview da #36 após #37 + #38: **283 migrations**, incluindo `20260830181500_12b1c_kit_meta_e_agent_kit.sql`.

Se contrato e testes baterem, mergear #36 e verificar produção.

### Não fazer aqui

- Gate;
- Treble;
- retrieval novo;
- calendário no Kit;
- cache/helper/abstração;
- Source Registry físico completo;
- memória;
- tools novas.

---

## PASSO 3 — Ligar o Capability Gate ao Kit real

### Para que serve

O Router escolhe a rota correta. O Gate responde se **essa rota pode executar agora**.

Ele deve verificar:

- playbook existe;
- Kit obrigatório está disponível;
- canal é compatível.

Não decide estratégia e não muda rota.

### Mudança mínima

Alterar apenas a célula/verdade `kit` de `public.mind_rota_capacidade(text,text)` para usar:

```text
mind_kit_meta(rota).kit_disponivel
```

Preservar:

- assinatura;
- seis rotas canônicas;
- regras de canal;
- lookup de playbook;
- razões e precedência:

```text
missing_playbook > missing_kit > canal_incompativel
```

### Critério de pronto

- B2C/B2B refletem o Kit real, não matriz hardcoded;
- rotas/canais antigos não mudam indevidamente;
- Gate não chama full loader;
- testes apenas dos seis routes × canais afetados.

---

## PASSO 4 — Finalizar cérebro do Vendedor Summit

### Para que serve

Transformar contexto + rota + Kit em **estratégia comercial do turno**, preservando as quatro camadas:

```text
INTELLIGENCE = o que é verdade agora
PLAYBOOK = como um excelente vendedor pensa
DECISIONING = qual estratégia faz sentido agora
AGENT = o que efetivamente diz/faz
```

### Fluxo esperado

```text
mensagem
→ identidade/conversa
→ AGENT_CONTEXT
→ Router
→ summit_b2c ou summit_b2b
→ Capability Gate
→ Kit Loader
→ Decisioning comercial
→ Agent
→ resposta + action/needs_human
```

### B2C precisa conseguir

- explicar Summit;
- diferenciar Mind/VIP/Prime;
- informar preços vigentes e checkout corretos;
- explicar inclusões;
- usar programação para apoiar decisão;
- lidar com objeções sem inventar benefício/desconto;
- conduzir para compra;
- respeitar regras comerciais.

### B2B precisa conseguir

- reconhecer intenção de grupo/delegação;
- usar preços por volume e regras corretas;
- explicar diferenças de ingresso para equipes;
- entender quantidade/contexto suficiente para orientar;
- conduzir próximo passo comercial;
- não aplicar regra B2C como se fosse B2B.

### Menor implementação

Antes de criar função/tabela nova, investigar o runtime real atual e reaproveitar playbooks/prompts/Decisioning existente. Criar somente o que estiver realmente faltando para o turno comercial funcionar.

Não construir um “motor universal elegante” se o contrato atual puder ser completado com pequena mudança.

---

## PASSO 5 — Ação + handoff do Vendedor

### Para que serve

Converter decisão em saída segura do canal.

Contrato de necessidade humana já congelado:

`needs_human=true` quando houver:

- pedido explícito de humano;
- erro de pagamento;
- reclamação séria;
- situação fora da política;
- dúvida que os dados não resolvem e trava a decisão.

Transferir é último recurso. Antes, entregar valor e recolher o que for útil.

Horário calibra expectativa; não nega handoff.

### Hoje

Usar o mecanismo real que o Treble já aceita. Não construir orquestrador novo de filas humanas.

Critério de pronto:

- runtime devolve resposta compatível com o Treble;
- `needs_human` chega corretamente;
- conversa normal não é transferida cedo demais;
- caso obrigatório transfere.

---

## PASSO 6 — Colocar Vendedor no Treble real

### Para que serve

Trocar o caminho legado pelo Core novo no canal que realmente recebe leads.

Runtime alvo:

```text
Treble / WhatsApp
→ treble-inbound-agent
→ ingestão/identidade/contexto
→ Router
→ Gate
→ Kit
→ Decisioning
→ Agent
→ resposta_ia + needs_human
→ Treble
```

### Regras

- Treble continua adapter de canal, não casa da inteligência;
- não duplicar preço/regras/playbook dentro da Edge Function;
- não criar segundo Router;
- preservar payload/contrato externo necessário ao fluxo atual;
- mudar só o trecho necessário para passar pelo Core canônico.

### Smoke tests prioritários

B2C:

- “Quanto custa?”
- “Diferença Mind/VIP/Prime?”
- “O Prime vale a pena?”
- “Tem desconto?”
- “Não quero mais.”

B2B:

- “Quero 5 ingressos.”
- “Quero 15.”
- “Quanto fica por pessoa?”
- “Quero levar meu time.”

Handoff:

- “Quero falar com alguém.”
- erro/política/dúvida que trava.

Critério: factual correto, tom adequado, sem invenção, rota correta e handoff correto.

---

## PASSO 7 — Concierge Summit v1 operacional

### Para que serve

Responder o evento usando Product Intelligence + Ecossistema, sem construir backend paralelo.

### Base factual existente a reaproveitar

- `summit_2026.sessions`;
- `site_session_id` determinístico;
- `session_speakers.speaker_id` canônico;
- `ecossistema.palestrantes_especialistas`;
- locais/tipos/dados atuais da programação;
- `public.mindagent_chat_search` como retrieval vivo a ser reaproveitado/ajustado apenas se necessário.

### Fluxo alvo

```text
pergunta
→ rota concierge_summit
→ Gate
→ contexto factual
→ retrieval da necessidade
→ programação + palestrantes + knowledge disponível
→ Decisioning do concierge
→ Agent
→ resposta
```

### Deve responder pelo menos

- quem é determinado palestrante;
- quando ele/ela fala;
- quem participa de uma sessão;
- horário/local de sessão;
- o que existe em determinado dia/faixa de horário;
- busca temática básica (“quero algo sobre burnout/segurança psicológica”);
- recomendação baseada no pedido atual e nos dados disponíveis;
- admitir lacuna quando a base não suporta resposta.

### Não fazer

Não criar um segundo banco de programação, segunda identidade de speaker ou segundo retriever do zero se o atual puder ser aproveitado.

---

## PASSO 8 — Memória + análise pós-turno

### Para que serve

Permitir continuidade real entre turnos/conversas sem transformar cada mensagem em contexto infinito.

Objetivo funcional de hoje:

- identificar fatos/preferências/objetivos realmente úteis que surgiram na conversa;
- persistir no lugar canônico já existente ou na menor estrutura necessária;
- não persistir Product Intelligence mutável como “memória da pessoa”;
- não transformar inferência fraca em fato;
- próxima interação poder recuperar contexto relevante.

### Regra

Primeiro investigar tabelas/funções de memória/engagement que já existem. Completar o caminho existente; não criar arquitetura paralela.

Critério de pronto:

- ao menos um fluxo de preferência/objetivo persistente é escrito e reaparece em turno seguinte;
- fatos de produto continuam vindo do Kit/Intelligence atual.

---

## PASSO 9 — Write-back / dispatch operacional

### Para que serve

Refletir para sistemas operacionais o que o agente aprendeu/decidiu quando houver uso concreto.

Hoje focar apenas em write-backs necessários ao produto entregue, por exemplo:

- estado/atributo comercial relevante já previsto no fluxo;
- handoff/necessidade humana;
- sinal operacional que HubSpot/Treble realmente consume.

### Regras

- investigar writers existentes antes de criar outro;
- idempotência;
- não escrever preço/regra como dado da pessoa;
- não disparar outbound sem regra/aprovação específica;
- não tentar sincronizar todos os sistemas do Mind hoje.

---

## PASSO 10 — Continuidade / Silence

### Para que serve

Separar “responder agora” de “retomar depois”. Evita agente insistente e permite follow-up quando realmente apropriado.

Objetivo funcional de hoje:

- distinguir turno síncrono de continuidade;
- respeitar desinteresse/opt-out/regras comerciais;
- impedir follow-up quando deve ficar em silêncio;
- permitir regra de retomada somente onde já houver canal e política aprovados.

Não construir campanha/nutrição autônoma genérica neste passo. Outbound/disparo continua gate sensível.

---

## PASSO 11 — Concierge: recomendação e experiência “Play” necessárias para a entrega

### Para que serve

Transformar Concierge de buscador em experiência útil durante o evento.

Executar depois que pergunta/resposta factual do Concierge estiver confiável.

### 11A — recomendação contextual

Usar somente dados reais disponíveis para recomendar sessões com base em:

- pedido atual;
- temas/conceitos recuperados;
- dia/horário;
- acesso/ticket quando essa informação estiver disponível no contexto;
- preferências/memória quando já implementadas.

Não prometer personalização que os dados não suportam.

### 11B — Play / interação no evento

Investigar e implementar pela menor superfície possível os recursos necessários à experiência prevista:

- NPS/feedback da sessão;
- acesso a slides/materiais quando existirem;
- insights/AMA quando a fonte existir;
- votação de palestrantes/2027 quando houver estrutura de coleta;
- perguntas de repetição/valor de masterclass/workshop;
- ofertas contextuais do Mind/Institute quando baseadas em regra aprovada;
- humor como camada de linguagem, sem sacrificar factualidade.

Não fabricar materiais/insights inexistentes. Cada recurso deve apontar para uma source real ou para uma coleta explícita.

### 11C — reservas/agendamento

Não construir um novo motor de reservas/check-in/QR nesta frente sem provar necessidade e integração viável. Se já existir superfície operacional contratada/embedável, o Concierge pode orientar/levar o usuário até ela.

A semântica canônica continua:

- `lugares_limitados`;
- `reserva_recomendada`;
- reserva não é obrigatória por definição geral.

---

## PASSO 12 — E2E completo dos dois produtos

### Vendedor

Provar conversa real do Treble de entrada até saída/handoff.

### Concierge

Provar pergunta real no canal disponível até retrieval/resposta.

### Regressões que importam

- identidade/conversa não quebra;
- Router escolhe rota certa;
- Gate bloqueia quando deve;
- Kit traz fatos atuais;
- preço/volume/inclusões não são inventados;
- speaker/session resolve por IDs canônicos;
- handoff funciona;
- memória não contamina Product Intelligence;
- write-back não duplica;
- silêncio não dispara ação indevida.

Testar casos críticos, não suíte irrelevante.

---

## PASSO 13 — Fechamento do go-live

Somente depois dos E2E:

1. atualizar `docs/CORE_UNIVERSAL.md` com o que realmente ficou vivo;
2. atualizar `BACKLOG.md` com pendências investigadas/deferidas, sem números antigos;
3. atualizar `PROJECT_STATE.md` com novo checkpoint/ordem seguinte;
4. remover ou consolidar documentação temporária que tenha virado duplicata canônica;
5. registrar SHAs de merges/deploys e estado final de produção;
6. não fazer limpeza de legado/refactor apenas por estética antes de declarar o produto entregue.

---

# O que explicitamente NÃO pode sequestrar as 6 horas

Mesmo com a exigência de “tudo hoje”, estas atividades não são entrega do produto se não mudarem o comportamento necessário de Vendedor/Concierge:

- apagar funções legadas mortas;
- remover fisicamente `palestrante_id`;
- redesenhar schemas inteiros;
- criar tabelas conceituais sem consumidor;
- Source Registry/autodiscovery completos;
- Intelligence Inbox;
- cache/otimização sem problema medido;
- hardening para risco hipotético;
- frontend totalmente novo se uma superfície existente/embed/endpoint já entrega a experiência;
- sincronização automática de toda fonte externa;
- generalizar o Core para Institute/Dash além do necessário para não quebrar contratos existentes.

Se algum desses itens virar bloqueio real para Vendedor/Concierge, ele volta pelo ritual normal e entra pela menor mudança necessária.

---

# Checkpoint de retorno se a execução for interrompida

Retomar sempre pelo primeiro item incompleto desta lista, sem reinvestigar os anteriores:

```text
1. #37 → merge/verificação
2. #38 → fresh preview → merge → backfill 81/81
3. #36 → main atualizado → 2 correções → fresh preview → merge
4. Gate → mind_kit_meta
5. Decisioning/Agent vendas
6. Handoff/ação
7. Treble E2E vendedor
8. Concierge factual/retrieval
9. Memória pós-turno
10. Write-back/dispatch
11. Continuidade/Silence
12. Recomendação + Play necessários
13. E2E completo Vendedor + Concierge
14. documentação final
```

### Estado esperado dos ledgers durante o início

```text
main atual antes de #37: 280 migrations
após #37: 281
após #38: 282
preview/merge #36: 283
```

Não usar números antigos se o ledger real avançar por outra migration; verificar o delta, não forçar contagem histórica.

---

# Critério de decisão rápido

Antes de qualquer nova tarefa hoje, perguntar:

> **Isto aumenta diretamente a chance de Vendedor ou Concierge funcionarem corretamente hoje?**

- **sim** → entra na ordem no ponto correto;
- **não** → backlog/documentação, sem abrir frente;
- **não sabemos e pode mudar materialmente a solução** → investigação curta do sistema real;
- **já sabemos** → não reinvestigar.
