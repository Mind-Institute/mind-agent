# CHECKPOINT ATUAL — go-live Vendedor + Concierge

> **Leia este arquivo primeiro se estiver entrando no projeto sem contexto.**
>
> Atualizado em **30/08/2026 à noite** (GitHub já mostra 31/08 UTC).
> `main` no momento desta atualização: **`0f210953fc783aed63ade6ca87b77337b08b6b7c`**.
>
> Este é o ponto de retomada operacional. `PROJECT_STATE.md` preserva arquitetura/decisões congeladas; `GO_LIVE_PARALLEL_20260830.md` preserva ownership; `BACKLOG.md` preserva investigações deferidas; `docs/CORE_UNIVERSAL.md` descreve o sistema vivo, mas ainda contém snapshot de 29/08 em alguns trechos. **PRs e issues são mais frescos que este arquivo para trabalho ainda não integrado.**

---

## 0. Prompt exato para uma nova janela

Cole isto na nova janela:

```text
Estamos continuando o projeto Agentes do Mind no repositório GitHub `Mind-Institute/mind-agent`.

Antes de responder ou propor qualquer mudança, reconstrua o checkpoint pelo sistema real.

LEIA, nesta ordem:
1. `CHECKPOINT_ATUAL.md` na raiz — é o ponto exato de retomada.
2. `PROJECT_STATE.md` — arquitetura, runtime, gates e decisões congeladas.
3. `GO_LIVE_PARALLEL_20260830.md` — ownership das lanes e ordem de integração.
4. `BACKLOG.md` apenas nas seções relacionadas às lanes ativas.
5. `docs/CORE_UNIVERSAL.md` para o que já está vivo; atenção: alguns trechos ainda refletem o snapshot de 29/08, então sistema real/PRs mais recentes vencem.

Depois, ANTES de agir:
- confira no GitHub o estado atual, HEAD, diff, comments/reviews e CI das PRs #47, #50, #46, #51 e #48;
- leia os comentários mais recentes das issues #40, #41, #42 e #43;
- confira `main` atual e produção Supabase antes de qualquer merge/deploy;
- se algum HEAD tiver avançado depois do checkpoint, atualize mentalmente o estado usando PR/issue como fonte mais fresca;
- não reinvestigue decisões fechadas sem fato novo material.

Você assume o papel de arquiteto/supervisor desta janela. Claude Code continua executor por lane. GitHub é memória/barramento: coordene diretamente nas issues/PRs; não use Adriana como mensageira entre janelas.

Ritual obrigatório:
INVESTIGAR → ENTENDER O QUE JÁ EXISTE → DECIDIR A MENOR MUDANÇA → IMPLEMENTAR → TESTAR SÓ O AFETADO → DOCUMENTAR → CONTINUAR ATÉ E2E OU GATE REAL.

Regras importantes:
- lane é dona da capacidade até E2E real, não até o primeiro PR;
- ordem de deploy ≠ ordem de trabalho;
- merge em `main` é boundary de deploy para migrations/app;
- as Edge Functions `treble-inbound-agent` e `mindagent-chat` NÃO são publicadas automaticamente hoje porque o repo não tem `supabase/config.toml`; publicação é manual;
- não criar segunda identidade, segundo backend ou segundo lifecycle para Play;
- não criar `mind_lead_capturar`;
- não ligar cron 13/outbound sem gate explícito;
- não mudar preço/regra comercial/source of truth/auth/RLS/security/identidade ou comportamento material sem o gate correspondente;
- não insistir em preview pago/recriado quando já existe prova transacional suficiente e a supervisão fechou que isso não bloqueia.

PONTO DE RETOMADA:
A Lane A/Core está concluída e em produção. As lanes ativas são B/C/D/E. Leia o estado detalhado neste `CHECKPOINT_ATUAL.md` e compare com os HEADs vivos.

Não faça recap genérico. Primeiro me diga em poucas linhas:
1. qual é o `main` atual;
2. qual é o HEAD vivo de B/C/D/E;
3. qual é o PRIMEIRO próximo movimento seguro na ordem de integração;
4. se existe algum gate meu neste exato momento.

Depois continue automaticamente tudo que não depender de gate meu.
```

---

## 1. Objetivo agora

Fechar dois produtos sobre o mesmo Core:

1. **Vendedor Summit** no Treble/WhatsApp, B2C e B2B, com Router → Gate → Kit → Decisioning/Agent → resposta/handoff e zero invenção comercial.
2. **Concierge Summit + Play** no app, com programação/palestrantes/recomendação factual, actions person-bound (NPS/feedback/insight) e o mesmo runtime/identidade.

Depois fechar memória/pós-turno/write-back/continuidade dentro dos gates e rodar E2E transversal.

---

## 2. O que já está fechado em `main` e produção

### Lane A / Core — CONCLUÍDA

Já integrados/verificados:

- speakers canônicos: **81/81 vínculos**, 63 pessoas, 60 sessões;
- Kit Loader universal mínimo (#36): `mind_kit_meta` + `mind_agent_kit`;
- Capability Gate lendo Kit real (#44);
- `mind_kit_evento` corrigido pela correspondência real `evento.produto_codigo = catalogo.produtos.codigo` (#49);
- #49 mergeada no commit `a226e2888d029b1fd661795b16c18a9dc02a6dac` e já refletida no Supabase;
- último ledger de produção observado depois de #49: **285 migrations**;
- B2C/B2B em WhatsApp: Gate/Kit disponíveis com blocos obrigatórios.

Não reabrir Lane A sem fato novo.

---

## 3. Lanes ativas — estado mais recente conhecido

### B — Vendedor Summit / Treble

- **Issue:** #40
- **PR:** #47, draft
- **Branch:** `claude/go-live-vendedor-runtime-hjobov`
- **HEAD mais recente verificado:** **`ff223c0df3323734a4ecb47fd9ce5e5c64816a87`**

O runtime/guardrail está **encerrado na revisão estática**:

- `treble-inbound-agent` v1.4.0 preparado para Router → Gate → Kit;
- Gate roda para qualquer rota canônica decidida; Kit comercial só para B2C/B2B;
- clarify preserva `candidatas` e não grava audience nova;
- `mind_lead_capturar` removida como chamada morta, sem writer substituto;
- guardrail comercial valida **papel + faixa + experiência**, percentual, centavos e contexto local por valor;
- fixture espelha Kit vivo por asserção: 3 experiências, 3 ofertas vigentes, 12 linhas de volume;
- **71/71** contratos + `tsc --strict` limpo;
- #49 sincronizada e revalidada;
- smoke não usa mais telefone fake hardcoded: exige `TREBLE_SMOKE_CELLPHONE`, falha antes de tocar produção se faltar/inválido e não apaga pessoa/identidade/CRM;
- `node --check` smoke ✅; sem env → exit 2, zero request;
- `core_rota_kit` continua desligado;
- Edge não publicada.

**Próximo movimento B:** revisar o HEAD vivo/CI `ff223c0`, marcar Ready/merge quando seguro, confirmar migration, comparar código versionado com Edge viva, **parar no gate de publicação manual se exigido**, publicar `treble-inbound-agent`, ligar flag e rodar smoke E2E real no WhatsApp controlado.

DoD: HTTP 200 não basta; resposta tem de chegar no aparelho. Se houver turno devolvido pela Edge que não chega no WhatsApp, flag volta a `false`.

---

### C — Concierge Summit / runtime canônico

- **Issue:** #41
- **PR:** #50, draft
- **Branch:** `claude/go-live-concierge`
- **HEAD mais recente verificado:** **`b0e51356991f8d7d02d4e761f264ae43bfc5a9e8`**

SQL/retrieval/Kit aceitos neste estágio:

- `mindagent_chat_search` corrigido para nomes parciais, tema, dia/faixa, múltiplos dias, minuto real, nested speaker sessions, horário local e ausência de fonte;
- `mind_kit_programacao` separa `pergunta` (seleciona) de `interesses` (só rerankeia);
- `event_slug` preservado e resolvido explicitamente;
- playbook v7 copiado byte a byte para `agentes.prompts['playbook_concierge_summit']`; `concierge.prompts` fica intacta/histórica por decisão fechada;
- Kit `concierge_summit` = `evento` + `programacao`;
- **17 contratos SQL** em `BEGIN/ROLLBACK` contra produção, produção intacta.

Runtime real já versionado na PR:

- baseline Edge viva `mindagent-chat` v23 versionada em commit isolado `0deca7f` antes das alterações;
- hash vivo conferido: `26a607f19992ee559bf3072a54f8fd741f7447a33432ac44a68115875dd1b0fd`;
- código atual: auth/sessão/bind/contexto → salva mensagem do usuário → modo action Play OU Gate → Kit → OpenAI;
- sem Router no app dedicado;
- fail-closed sem Kit/playbook/blocos;
- `sensitivity` obrigatório em cada `interest`, enum `none` + 10 chaves existentes, repassado intacto à RPC;
- modo Play no **mesmo** `mindagent-chat`, allowlist explícita, sem OpenAI;
- pessoa identificada pode entrar direto no Play sem conversa anterior; sem `pessoa_id`, coleta não executa;
- `npm run test:edge`: **19/19**; `tsc --noEmit` limpo;
- Edge **não publicada**.

Compatibilidade C→D fechada: é correto C começar a enviar `sensitivity` **antes** do gate SQL da D; RPC atual recebe JSON extra e ignora até #51 entrar.

**Próximo movimento C:** revisão final do diff do runtime no HEAD vivo → merge controlado das migrations/código → confirmar DB vivo → **gate/publicação manual da `mindagent-chat`** → E2E real no app. Não insistir em branch Supabase paga/recriada para #50.

---

### D — pós-turno / memória / write-back / Silence

- **Issue:** #42
- **PR #46:** coletor de memória, draft
  - HEAD mais recente: **`1244b1809301246f9110a57a176d3c8c3f18ef97`**
- **PR #51:** memória segura + D1/D2, draft
  - HEAD mais recente: **`5712fe027531a42a5f057695b7c8d83deff40c60`**

Chunk atual aceito tecnicamente:

- `mind_memoria_fatos(pessoa_id)` pronto/desligado;
- coletor só expõe `valor.sensitivity='none'`; legado v1 fica preservado e invisível;
- `analise_vendas_summit` v2 emite `sensitivity`;
- `analise_projetar_memoria` fail-closed **só para analisador sob contrato**;
- revalidação adiciona marcador sem duplicar;
- substituição `ativa → ativa` identidade/cargo/empresa corrigida;
- `mindagent_chat_save_interests` também é fail-closed **antes** de `session_interests`, memória e perfil;
- Silence D1 corrigido no contrato; D2 exige `followup_count > 0` para `followup_exhausted`;
- #51: **11 contratos** em transação revertida;
- #46: **9 contratos** em transação revertida;
- produção segue sem coletor/gate novos; cron 13/outbound desligado.

**Rename da #46 JÁ FOI FEITO**:

```text
20260830230000_15_mind_memoria_fatos.sql
→ 20260830234000_15_mind_memoria_fatos.sql
```

HEAD #46 atual `1244b18`. O preview da #46 ficou **stale e vermelho por causa do ledger antigo do próprio preview** (`Remote migration versions not found in local migrations directory`). Isso não é evidência contra o diff atual. Não recriar/resetar preview só para deixá-lo verde. Evidência válida: 9/9 contra produção em transação revertida com a migration atual.

Produção observada: **887 memórias**; a 887ª veio de atividade real do cron 12, não de fixture. Prompt ainda v1; coletor não existe; cron 13 off.

**Próximo movimento D:** aguardar/acompanhar integração C para ordem correta, então integrar migrations seguras e continuar a lane — wiring de leitura da memória no runtime correto, pós-turno do Concierge, write-back realmente necessário dentro do gate de CRM/source-of-truth e continuidade/Silence até o limite permitido. **Não ligar cron 13/outbound.**

---

### E — Play / experiência do Concierge

- **Issue:** #43
- **PR:** #48, draft
- **Branch:** `claude/go-live-play-labrz9`
- **HEAD mais recente verificado:** **`2a08e26eb756dc9d33b5aa307710fc15cc3a256d`**

Já feito:

- writers person-bound `mind_play_feedback_sessao`, `mind_play_nps`, `mind_play_feedback_evento`, `mind_play_feedback` + agregado;
- zero tabela/coluna nova;
- UI real tenta persistir insight/nota/NPS e não mente dizendo “Guardei” quando falha;
- Play não exige conversa prévia; reusa auth/sessão/identidade;
- v1 não aceita coleta anônima;
- slides/materiais deferidos até source canônico;
- contrato cliente já é compatível com executor Play da #50;
- SQL 9 contratos; navegador real 8 contratos no estado atual da PR.

**Rename E ainda está pendente** para manter E por último:

```text
20260830231500_lane_e_play_coleta.sql
→ 20260830235000_lane_e_play_coleta.sql
```

Depois: sincronizar com C, apontar `CONFIG.playActionUrl` para a mesma `mindagent-chat` quando ela estiver publicada e fazer E2E real: pessoa identificada, sem conversa prévia, entra no Play e grava coleta person-bound nas casas canônicas.

Não consertar `mindagent_bootstrap` pela metade: hoje o fallback local preserva temas que o banco ainda não consegue devolver sem regressão.

---

## 4. Ordem de migrations pretendida

```text
#47 B   20260830210000
#49 A   20260830220000   [JÁ EM MAIN/PROD]
#50 C   20260830223000
#50 C   20260830233000
#46 D   20260830234000   [RENAME FEITO]
#51 D   20260830234500
#48 E   20260830235000   [RENAME PENDENTE]
```

Não crie segunda migration para corrigir número de arquivo que nunca rodou em produção.

---

## 5. Ordem de integração/deploy

```text
B — review final do HEAD vivo → merge → deploy manual Edge → flag → E2E WhatsApp
→ C — review final → merge migrations/código → DB vivo → deploy manual mindagent-chat → E2E Concierge
→ D — migrations seguras → wiring pós-turno/memória/write-back/continuidade dentro dos gates
→ E — rename + migration/UI integrada ao executor C → E2E Play
→ E2E transversal Vendedor + Concierge + Play
→ reconciliar CORE_UNIVERSAL/BACKLOG/PROJECT_STATE no estado final
```

**Ordem de deploy ≠ ordem de trabalho.** D/E podem corrigir coisas independentes enquanto B/C fecham.

---

## 6. Gates vigentes

Exigem decisão/gate explícito antes da execução perigosa:

- preço, desconto ou regra comercial;
- alteração destrutiva/irreversível de dados;
- auth/RLS/security/secrets/identidade;
- source of truth;
- outbound/disparo, inclusive cron 13;
- write-back material em CRM sem contrato já fechado;
- publicação de runtime vivo quando a mudança materializa comportamento novo de produto/canal;
- outra mudança material de produto não congelada.

Já fechado e não precisa ser rediscutido:

- Router com seis rotas;
- semantics Gate/Kit;
- regra comercial atual = exatamente regras/playbooks ativos, sem D1–D4 revelado;
- `mind_lead_capturar` não deve ser criada;
- Play v1 person-bound;
- slides deferidos;
- `sensitivity` usa taxonomia existente e escrita fail-closed;
- `concierge.prompts` fica intacta/histórica por enquanto;
- C pode emitir `sensitivity` antes de D estar live;
- `schema_dados` não volta como proxy no `mind_kit_evento`.

---

## 7. NÃO reabrir agora

- completar toda Intelligence do Summit;
- taxonomy/conceitos novos;
- RAG/vector sem necessidade real;
- Intelligence Inbox/autodiscovery;
- limpeza de legado por estética;
- segunda identidade/backend/session lifecycle para Play;
- `mind_lead_capturar`;
- cron/outbound antes do gate;
- fonte falsa para slides/materiais;
- `mindagent_bootstrap` retornando `temas=[]` só para “ficar verde”.

---

## 8. Regra de retomada para IA nova

1. leia o prompt da seção 0 e os documentos na ordem indicada;
2. **re-fetch** PRs #47/#50/#46/#51/#48 e issues #40–#43 antes de confiar nos HEADs acima;
3. PR/issue mais recente vence este snapshot para trabalho ainda não integrado;
4. produção vence documentação em claims de estado vivo;
5. preserve decisões fechadas;
6. comece pelo **primeiro próximo movimento seguro** na ordem de integração;
7. não pare por CI, review ou espera técnica; pare somente em gate real.

GitHub é o barramento entre lanes. Coordene por comentário/review nas issues/PRs, não por Adriana.
