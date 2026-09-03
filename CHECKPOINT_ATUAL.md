# CHECKPOINT ATUAL — go-live Vendedor + Concierge

> **Leia este arquivo primeiro se estiver entrando no projeto sem contexto.**
>
> Atualizado em **03/09/2026** (checkout atribuído no App e WhatsApp; venda contextual habilitada no App).
> `main` verificado antes desta entrega: **`04384d838115119def2a9f1fc0e854649397582a`**.
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

#### 01/09 — O FLUXO CANÔNICO DO APP MUDOU

Branch `claude/go-live-vendedor-runtime-hjobov`. **Migrations aplicadas em produção e `mindagent-chat` publicada como version 25 (v1.6.0).** O que estava escrito acima — *"sem Router no app dedicado"*, *"Kit `concierge_summit` = `evento` + `programacao`"* — deixou de valer.

Fluxo do App agora:

```text
mensagem
  → identidade/contexto
  → ORIGEM AUTORITATIVA (se a porta já define a competência) ─┐
  → POLÍTICA DO CANAL (agentes.canal_competencia)             │
  → ROUTER (só quando há o que decidir)                       │
  → GATE  ←───────────────────────────────────────────────────┘
  → KIT DA ROTA
  → AGENT (com tool loop)
```

**`mind_summit_app` é uma entrada com rota autoritativa.** Quem chega pelo app oficial do
Summit já disse, pela porta, qual competência quer: `mind_summit_app → concierge_summit`,
sem chamar o Router. É a única entrada assim hoje, e ela mora em `ROTA_POR_ORIGEM`, na Edge
— um mapa de uma linha, não uma taxonomia nova. A origem vem do frontend em
`origem_codigo`, é persistida **uma vez** em `engagement.conversas.origem_codigo` (o banco
grava com `where origem_codigo is null`) e é a persistida que decide: um turno posterior
não reescreve a porta de entrada. Toda outra origem continua passando pelo Router, e o
**Gate continua obrigatório** nos dois caminhos — a origem diz qual competência foi
acionada, nunca se ela executa. Medível em `rota_origem` (`origem_autoritativa` vs
`router`) e em `blocos.origem_codigo`.

Quatro mudanças:

1. **O nome da URL chega à identidade.** `mindagent_chat_bind_identity` ganhou `p_nome` e repassa ao `mind_identidade_resolver`, que já sabia preencher nome faltante sem sobrescrever nome canônico. Antes o e-mail ligava a pessoa e `pessoas.pessoas` ficava sem nome.
2. **O App deixou de forçar `concierge_summit`.** A rota vem do Router, com o canal declarado; o universo legal é `concierge_summit` + `cliente_suporte`, e essa lista **não está escrita na Edge** — vem de `agentes.canal_competencia`. Quando o Router não decide, o desempate é a primeira candidata que ele mesmo devolveu; quando o Router não responde, o piso é `concierge_summit` — e os dois casos saem em `rota_origem`, medíveis.
3. **`cliente_suporte` executa no App.** O Gate devolvia `missing_kit` porque a rota tinha zero linhas em `agentes.kit_blocos` (o playbook sempre existiu). Agora tem `evento` + `programacao` + `inclusoes`, os mesmos providers já vivos. Vale para os dois canais.
4. **O Concierge ficou agentic.** `mind_agent_kit` parou de devolver `tools: []` fixo: a rota declara em `kit_blocos` (`secao='tools'`) e o descritor vem de `concierge.ferramentas`, filtrado por `escrita = false`. Duas tools, ambas já existentes desde 20260831070000: `buscar_intelligence` e `ler_intelligence`. Tool loop na Responses API, no máximo 2 rodadas por turno, múltiplas chamadas por rodada.

Estado vivo: `mindagent-chat` **version 25**, `router` version 5 (inalterado), `treble-inbound-agent` version 30 (inalterado).

**E2E no runtime real, 8/8** (via `pg_net`, sessão anônima igual à de qualquer visitante):

| teste | resultado |
|---|---|
| identidade (email + nome da URL) | nome persistido, 1 pessoa, sem duplicata |
| memória (persistir → recuperar em turno seguinte) | recuperou sem repetir os temas |
| Router App → concierge | `concierge_summit` |
| Router App → atendimento | `cliente_suporte`, **executando**, não `missing_kit` |
| agentic factual (Maslach) | grounded no `structured`, sem tool desnecessária |
| agentic por significado | `buscar_intelligence` → `ler_intelligence` → resposta, num turno |
| sem necessidade de tool | respondeu do `structured` |
| sem fonte | disse que não encontrou, não inventou |

**Ponto fraco conhecido, não bloqueante:** em 8 turnos a tool disparou 1 vez. Em `"O que combina comigo?"` o Kit voltou com 0 sessions e 0 speakers, as 2 tools estavam expostas e o modelo **não** buscou — respondeu que não conseguia apontar sessões. É afinação de prompt, não arquitetura: o caminho existe e foi provado no teste por significado.

**Divergência pré-existente registrada, não corrigida:** `mind_identidade_resolver` usa `split_part(nome, ' ', 1)` para `primeiro_nome` e não preenche `sobrenome` — "Adriana Teste E2E" virou `primeiro_nome='Adriana'`, `sobrenome=null`. É comportamento anterior a esta entrega e fora do escopo dado ("deixar o resolvedor atual cuidar do preenchimento").


---

#### 02/09 — Concierge utilizável: retrieval, Executor e conduta

Estado vivo: `mindagent-chat` **version 28 (v1.8.0)**, `router` version 5 (inalterado),
`treble-inbound-agent` version 30 (inalterado). Dez migrations aplicadas hoje, **todas com
arquivo no repo e todas idempotentes** — as guardas de todas as dez foram re-executadas
contra a produção atual e passaram, com o hash dos prompts inalterado.

**1. O retrieval parou de se comportar como AND.** `mindagent_chat_search` escalava o piso
de cobertura com o número de termos da pergunta (`0.1 * least(2, greatest(1, n_foco))`).
Como `ts_rank_cd` devolve exatamente `0.1` para um lexema único de peso D, dois termos
exigiam os dois — um AND acidental. O piso virou constante, os filtros estruturais passaram
a sair de `summit_2026.sessions.tipo` (não de lista manual), e existe fallback: tipo pedido
nunca devolve zero. Medido: `workshop RH` 0 → 12; `workshops sobre liderança` 12, nenhum
de outro tipo; `dia 17` 6; `masterclasses` 4; Amy/Maslach preservados; sem fonte, 0.
Lacuna conhecida e registrada, não disfarçada: `painel/painéis` (o stemmer devolve `pain`).

**2. O Executor deixou de ser um segundo playbook.** `contratoDoExecutor` (7.060 chars de
prosa dentro da Edge) dizia como recomendar, como escrever e o que fazer no suporte — isso
é competência, e competia com o playbook da rota. Foi removido; `instrucoes` agora é
`kit.playbook` e nada mais. Cada regra foi para a casa dela: transversal → `agentes.prompts['base']`;
conduta do concierge → `playbook_concierge_summit`; semântica de campo → `description` do
JSON Schema; horário → removido, porque a `nota` do bloco de programação já dizia. O que o
runtime garante continua garantido **em código**: allowlist de tool, validação de argumento,
teto de rodadas por `tool_choice`, timeout, schema estrito, Gate, Kit, persistência,
redaction e telemetria.

**3. Follow-up funciona.** `history` existia, vinha filtrado pelo vocabulário errado
(`user`/`assistant` em vez de `lead`/`agente`), chegava vazio e ainda era descartado pela
Edge. Corrigido nas duas pontas.

**4. O tool loop disparou em produção.** `presenteísmo` → `rodadas_tool: 2`,
`chamadas_tool: 2`, 6,7 s: buscou, leu e respondeu honestamente que não há sessão com esse
nome, oferecendo três adjacentes reais. O ponto fraco registrado em 01/09 está resolvido.

**5. Seis defeitos de conduta medidos e corrigidos por prompt, não por código** — cada um
na casa que a arquitetura define. Lista parcial anunciada como completa; total do recorte
atribuído ao evento inteiro (`sessions_total` vs `totais.sessoes`); total citado em
recomendação, onde ninguém pediu; justificativa formatada como sessão irmã; encaminhamento
oferecido para o que a própria pessoa faz no app; e o sistema vazando na fala ("o contexto
não trouxe", "com o que veio neste turno").

**Residual conhecido, não bloqueante:** em pergunta de seguimento com pronome ambíguo
("Por quê essa?" depois de três recomendações) o agente responde certo — usa a conversa e
dá o motivo — mas ainda abre com uma ressalva desnecessária em vez de perguntar de qual
sessão se trata. É afinação de redação, não caminho quebrado.


---

#### 02/09 — a programação do backend estava 3 dias atrasada

Descoberto ao ser perguntado se eu tinha trocado a programação. **Não tinha**: nas dez
migrations de hoje só há `update agentes.prompts`, nenhuma escrita em `sessions`,
`session_speakers`, `espacos` ou `knowledge_documents`. Mas a pergunta expôs coisa pior.

**A cadeia de sync existia e nunca funcionou.** `mindsummit2026` tem
`.github/workflows/sync-programacao.yml` (push em `src/data/programacao.json` → Edge
Function `summit-programacao-sync` → RPC `summit_sync_programacao`). Rodou 3 vezes desde
30/08, **as 3 vermelhas**, sempre `401 x-sync-secret invalido ou ausente`: o log mostra
`-H "x-sync-secret: "` — o secret `SYNC_SECRET` **não existe naquele repositório**. O
único sync bem-sucedido (30/08 19:33) foi manual.

Resultado: o commit de ontem 15:18 (`troca dos workshops "Bem-estar começa na agenda" e
"Falhar melhor"`) nunca chegou ao backend, e o Concierge respondia dia, horário e sala
errados para 3 workshops — com a confiança que o trabalho de hoje aumentou, porque agora
ele lista dias inteiros e afirma totais. Dado velho entregue de forma mais completa é pior,
não melhor.

**Corrigido no runtime, com a normalização canônica.** Um diff caseiro meu deu um falso
positivo (`d2-1720` tem `superTitulo: "Mind Talks"`, e a função normaliza o título para
"Mind Talks" de propósito) — por isso a correção foi feita chamando a própria Edge
Function, não reimplementando a regra. As 3 sessões que mudaram de horário mudaram de
`id`, e a função nunca apaga; então: sync criou as 3 novas → migrei os 2 vínculos de
palestrante → apaguei as 3 antigas, depois de provar que nenhuma tinha agenda pessoal,
feedback, jornada ou recomendação ligada (as 5 FKs são `CASCADE`). Backend voltou a 77
sessões, 39/38, idêntico ao site. Medido no runtime: `Falhar melhor` → 16/09 15:00–17:00,
Sala Workshop 2.

`summit-programacao-sync` foi para **version 6**: `VALIDO_ATE` de `2026-09-07` para
`2026-09-16`, a pedido da Adriana (a programação muda até a véspera e o Concierge lê esta
tabela).

**PR aberto no repo do site:** Mind-Institute/mindsummit2026#31 — `schedule` de 07:00 e
19:00 BRT no workflow, parando sozinho depois de 16/09.

**Pendências que são gate da Adriana, não minhas:**
- criar `SYNC_SECRET` em `mindsummit2026`. Sem isso o job continua 401, agendado ou não;
- **o segredo do sync está hardcoded em texto claro** dentro da Edge Function, como
  fallback. É por isso que esta função **não tem arquivo neste repo**: guardá-la aqui
  espalharia o segredo por um segundo lugar. A divergência repo/produção fica registrada
  de propósito e se resolve junto com a rotação do segredo para env var;
- toda troca de horário vira `id` novo e exige limpeza manual da linha velha — hoje fiz as
  3 à mão. Se isso virar rotina até o evento, vale decidir uma regra;
- `who` do JSON não vira vínculo de palestrante (o sync não escreve palestrante, por
  contrato): `Bem-estar começa na agenda` está sem palestrante no backend, embora o site
  traga "Esabela Cruz, Clarissa Daroit".


**Segunda rodada, 04:17 — o padrão se confirmou.** No check-in seguinte o site já tinha
mais dois commits (`Arena Top Voice` virou `Arena LinkedIn`; credenciamento passou a abrir
às 07:30) e alguém já os tinha aplicado no banco à mão, fora do sync — `sincronizado_em`
nulo, sem log. O conteúdo estava certo, mas **o credenciamento continuava com o `id`
antigo** (`d1-0800-credenciamento` com hora 07:30), enquanto o site já usava
`d1-0730-credenciamento`. Sem corrigir, o próximo sync inseriria os dois novos e deixaria
quatro credenciamentos.

Aqui o `id` era a única diferença, então a menor mudança correta foi **renomear**
`site_session_id`, não inserir-e-apagar: renomear preserva o UUID, os vínculos e todas as
FKs.

Depois disso rodei o sync com o JSON **completo** — a prova que faltava:
`200 · ok:true · recebidas 77 · inseridas 0 · atualizadas 77 · sumiram 0 · sem_id 0`.
Backend idêntico ao site, e o workflow ficará verde assim que o secret existir. Confirmado
no runtime: "credenciamento abre às 07:30 nos dois dias".

**O padrão, agora com duas ocorrências:** mudança de horário no site vira `id` novo, a
função nunca apaga, e alguém precisa limpar a linha velha à mão. Enquanto a programação
mudar até a véspera, isso vai se repetir. Vale decidir uma regra — a mais simples é o
sync aceitar remover o que sumiu do JSON quando a sessão não tiver nenhum dado de
participante ligado (as 5 FKs são CASCADE), mantendo a recusa quando tiver.

#### 02/09 — PASSOS 5 E 6: PROMPTS FINAIS, MEMÓRIA EM DOIS TEMPOS E HANDOFF EXECUTÁVEL

Branch `claude/go-live-vendedor-runtime-hjobov`, commit `4bae649`. **Migrations aplicadas em
produção e `mindagent-chat` publicada como version 29 (v1.9.0).** Especificações-fonte:
`SUMMIT_2026_STEP5_PROMPTS_SPEC.md`, `SUMMIT_2026_STEP5_MEMORY_ADDENDUM.md` (que prevalece
sobre a spec nos trechos de memória) e `SUMMIT_2026_STEP6_HANDOFF_SPEC.md`.

**Prompts (`agentes.prompts`).** Quatro reescritos e conferidos por `md5` repo↔produção:
`base` `39bb6406`, `playbook_concierge_summit` `a11ff293`, `playbook_cliente_suporte`
`3b6d80e0`, `analise_concierge` `01a77062`. Atenção para quem for conferir: **a coluna
`atualizado_em` de `agentes.prompts` não é mantida na escrita** — ela ainda mostra datas de
agosto para linhas reescritas hoje. Só o hash do conteúdo vale como prova de frescor.

**Memória rápida** (`engagement.session_interests`, escopo de sessão). Caíram os cortes
artificiais: `interests.maxItems = 2`, `.slice(0,2)`, `.slice(0,8)` do perfil, `.slice(0,3)`
do Kit, o teto de 12 por sessão e a rejeição de payload com mais de 5 itens. Caiu também o
campo `confirmed`. Entrou o gate de sensibilidade que o runtime **afirmava em comentário mas
não existia no banco**: `mindagent_chat_save_interests` agora lê `sensitivity` e só persiste
`none`; um item sensível é descartado sozinho, sem derrubar o resto do payload. A promoção
de interesse de sessão para memória durável saiu daqui — memória rápida é sessão, não
memória permanente.

**Memória durável** (`intelligence.participante_memoria`). Em `analise_projetar_memoria`,
**apenas no ramo `p_analisador = 'analise_concierge'`**: `sensitivity` ausente ou diferente
de `none` não persiste; `scope='temporary'` não vira durável; `high` + (`stable`|`opportunity`)
→ `ativa`. A semântica dos outros analisadores fica intacta — `analise_vendas_summit` continua
com `stable + high → ativa` e continuou escrevendo normalmente durante todo o dia.

**Read path.** `mindagent_chat_get_context` passou a devolver `memories` (só `status='ativa'`
e não expirada, aceitando as duas formas históricas `valor.text` e `valor.label`) e
`rota_ativa`. Antes desta mudança a memória durável era escrita e **nunca lida** — o
Concierge não reutilizava nada do que o analisador gravava.

**Passo 6 — handoff Concierge ↔ Atendimento.** Sem tabela nova, sem coluna nova, sem segunda
conversa, sem Router no App. A competência corrente mora em
`engagement.conversas.variables.rota_ativa`; `origem_codigo` continua imutável como porta de
entrada. Precedência do turno: **`rota_ativa` persistida > origem autoritativa > Router**, e o
Gate continua obrigatório depois de qualquer uma das três. O contrato Agent→runtime é o campo
`next_route` do schema de saída, cujo enum é montado em runtime a partir de
`mind_canal_rotas('mindagent-web')` — não existe segunda lista hardcoded de rotas. A escrita
acontece dentro de `mindagent_chat_save_message`, na **mesma transação** da gravação da
mensagem, depois de revalidar a rota por `mind_rota_capacidade` com o canal lido da conversa.
Isso fecha o estado impossível "a resposta disse que encaminhou, mas a rota não mudou".

**E2E real do App, produção, v1.9.0.** Cadeia completa da DoD do Passo 6 numa única pessoa,
sessão e conversa (`2f71c556`): turno 1 `origem_autoritativa`→`concierge_summit` com
`next_route=cliente_suporte` e `variables.rota_ativa` persistida; turno 2 `rota_ativa`→
`cliente_suporte` sem Router; turno 3 Atendimento devolve com `next_route=concierge_summit`;
turno 4 volta ao Concierge. Nenhuma pessoa, conversa ou sessão nova foi criada na troca.

Comportamento conferido no runtime real: "cardápio do almoço" sem dado → diz que não
encontrou e **não** troca para Atendimento; "como faço para reservar?" → orienta e não
executa; "quais sessões eu já reservei?" → não finge ler a agenda; VIP → Masterclass → Prime,
sujeito a reserva e disponibilidade, sem reservar; Mind → workshop → VIP como menor upgrade;
"me lista todos os workshops" → **12 de 12**, sem corte. Entrada `mindagent-web` sem origem
autoritativa continua caindo no Router (`rota_origem: router`).

Fail-closed conferido direto no writer: `next_route` com rota inexistente e com rota fora da
política do canal (`summit_b2c`) **não persistem** e não afirmam handoff; rota igual à atual
vira `null` antes de gastar Gate.

Memória conferida: 6 interesses permitidos num turno → 6 salvos; 4 permitidos + 1
`saude_do_titular` → `saved 4, blocked 1, promoted 0`; `opportunity + high` → `ativa`;
`temporary`, sensível e sem classificação → não persistem; `medium` → `proposta` e `proposta`
não volta para o Agent; numa sessão com 10 interesses e 3 memórias ativas, "me indica uma
sessão boa pra mim" respondeu ancorado em liderança, segurança psicológica e cultura — a
memória chega ao modelo e ao Kit sem corte em 3.

**Divergência material nova.** `analise_concierge` **não é exclusivo do App**: o cron
`analise_conversas` (job 12) também o aplica a conversas de **WhatsApp**. Com o Passo 5 ele
passou a de fato gravar memória durável — 12 linhas desde 05:30 de hoje, as 12 com
`sensitivity`, e antes disso ele nunca havia gravado nenhuma. O impacto está contido: a única
função que **lê** `intelligence.participante_memoria` é `mindagent_chat_get_context`, ou seja,
o App. `treble-inbound-agent` não lê. Não há efeito no comportamento da lane #40, mas quem for
mexer no analisador precisa saber que o contrato de memória do Passo 5 hoje governa também as
conversas de WhatsApp. Registrar em #42.

**Pendência que não é regressão desta lane.** O modo ação do Play responde
`502 acao_falhou` porque as RPCs `mind_play_nps`, `mind_play_feedback_sessao`,
`mind_play_feedback_evento` e `mind_play_feedback` **não existem no banco** — nunca existiram
neste repo, que só tem o ledger de idempotência (`mind_play_chamada_iniciar/concluir`). O
caminho de ação dentro da `mindagent-chat` está intacto e não foi tocado pelos Passos 5 e 6
(`git diff 4bae649^ 4bae649` não altera nenhuma linha de Play): ele valida a ferramenta,
resolve a sessão e recusa com o código certo. Os writers são da lane E/#43.

**Divergência conhecida e aceita entre repo e produção.** O código publicado difere do arquivo
do repo em exatamente dois pontos: `/[\u0300-\u036f]/g` no repo aparece como a classe literal
equivalente no bundle publicado. Mesma faixa de caracteres, nenhuma diferença semântica.


#### 02/09, mais tarde — REVISÃO, INCIDENTE E O TECLADO

Quatro coisas depois do bloco acima. Branch `claude/go-live-vendedor-runtime-hjobov`.

**Os 3 deltas da revisão da Adriana** (`292f2f0`, `mindagent-chat` version 30 / v1.9.1):

1. **O App estava fora do pós-turno.** `analise_pendentes` filtrava
   `c.agente in ('treble','treble-inbound-agent')` — só WhatsApp. Todas as análises daquele
   dia vieram de `agente='treble'`; nenhuma do App. Ou seja, o contrato de memória durável
   do Passo 5 nunca era exercido numa conversa do App. `20260902120000` acrescenta uma
   palavra ao universo; quem escolhe o analisador continua sendo o `analise_classificador`,
   que já é canal-agnóstico. Registro de erro meu: o comentário anterior dizia
   "`analise_concierge` também roda no WhatsApp" porque juntei `participante_memoria` a
   `conversas` por `participante_id` — isso conta qualquer conversa da pessoa, não a que
   produziu a análise. O caminho certo é por `analise_conversa`.
2. **Evidência do interesse** — `20260902...`/runtime: a correção do PR #52 (`27af67a`)
   trazida verbatim, `userMessage.mensagem_id` no lugar de `.id`, mais o stub do harness
   passando a espelhar a forma real. Antes: 19/19 interesses com `evidencia_message_id`
   nulo, e zero linhas com evidência em toda a tabela.
3. **Menus e reserva no playbook** — `20260902130000`. O menu chama-se `Programação`,
   nunca "Agenda"; ao recomendar Arena LinkedIn, Arena Sextante, workshop ou Masterclass,
   lembrar de agendar e conferir em `Minha Agenda`; Arena Mind é exceção e não exige
   reserva.

**A home passa a trocar de tela pela data** (`da5c77a`). A regra JÁ EXISTIA e estava
desligada: `api.mindagent_home_publico`, em `modo='programado'`, resolve o momento pegando
a última troca cujo horário já passou, no fuso do evento, sem cron. Faltava o dado —
`trocas` vazio e `modo` em `manual`, com a home pregada em `no-evento` desde 01/09. A
programação está em `docs/sql/home-v3/07-programacao-das-telas.sql`; a tela própria do Dia 2
não existe e está em `BACKLOG.md` §15.

**INCIDENTE — o App e o vendedor ficaram fora do ar** (`f0c9dd5`). Às 06:58,
`mindagent-chat` devolvendo `503 official_data_unavailable` em toda conversa.
`public.mind_customer_intelligence`, da entrega de Customer Intelligence
(`20260902140000`), ordenava a identidade de HubSpot por `i.atualizado_em` — coluna que
`engagement.identidades` não tem. PL/pgSQL só resolve nomes de coluna na execução, então a
função foi criada sem erro e o `BEGIN/ROLLBACK` estrutural não podia pegar.

O bloco `customer_intelligence` entrou nos Kits das QUATRO rotas, e como `mind_agent_kit`
monta todos os blocos, a exceção derrubava o Kit inteiro — App (Concierge e Atendimento) e
vendedor no WhatsApp. **O fail-closed funcionou como projetado**: foi ele que transformou
um erro de coluna em indisponibilidade visível em vez de resposta inventada sem dado
oficial. Corrigido em `20260902150000` trocando um token para `i.criado_em`; as outras
referências a `atualizado_em` no corpo são válidas e ficaram. Varreduras depois: 60 pessoas
de perfis variados e 30 conversas reais nos dois canais, zero exceções.

**Lição para o dia do evento, não resolvida:** qualquer bloco de Kit que levante exceção
derruba o Kit inteiro e cala o agente. Se um bloco OPCIONAL pudesse falhar sozinho sem
levar junto `evento` e `programacao`, um erro assim viraria degradação em vez de queda. É
mudança no contrato do fail-closed — decisão da Adriana, não feita.

**O teclado deixou de empurrar a tela do Concierge** (`c044d4b`). Causa: a tela é uma
coluna flex de `height: 100dvh`, e no iOS o teclado não encolhe o viewport de layout nem
muda `100dvh`/`innerHeight` — encolhe só o VISUAL. A página continuava desenhada com a
altura inteira e o Safari rolava o viewport de LAYOUT para trazer o campo focado à área
visível: quem subia era a página, não o campo. `teclado.js` publica `visualViewport.height`
em `--app-altura` e o body virou `position: fixed` com essa altura.

Segundo defeito no mesmo sintoma: ao enviar, o código fazia `campoChat.disabled = true` —
desabilitar um campo focado tira o foco, e no iOS isso fecha o teclado; o `focus()` de
volta, fora de um toque, o iOS ignora. O teclado fechava a cada mensagem e não voltava.
Quem impede envio duplicado é `respostaEmAndamento`.

Medido em navegador em 393×852, 852×393 e 375×667, nos quatro estados: header imóvel,
composer no fim da área visível, distância até o fim da conversa zero, `scrollY` zero, foco
preservado inclusive durante o envio. **Não testado em iPhone real** — o critério de aceite
que pede isso continua aberto. A bottom navigation do diagrama da Adriana **não existe
nesta tela** (o `#fnav` é o telefone simulado do tour); a regra que a esconde está escrita e
inerte, e falta saber se a barra é do app hospedeiro.

---

### D — pós-turno / memória / write-back / Silence

- **Issue:** #42
- **PR #46:** coletor de memória, draft
  - HEAD mais recente: **`1244b1809301246f9110a57a176d3c8c3f18ef97`**
- **PR #51:** memória segura + D1/D2, draft
  - HEAD mais recente: **`5712fe027531a42a5f057695b7c8d83deff40c60`**

- **PR #70:** write-back comercial HubSpot — **MERGEADA** em `6f9c899bc994e7f8a9d8f2fe312f8368c636943f`
  - migration registrada em produção: `20260903041743_hubspot_commercial_writeback`;
  - Edge `hubspot-commercial-writeback` **version 1 / ACTIVE**, `verify_jwt=true`;
  - modo padrão `preview`; `apply` continua atrás de `HUBSPOT_COMMERCIAL_WRITEBACK_ENABLED=true` e permanece desligado.

**03/09 — gate aprovado e publicação segura da #70.** A migration exata do commit mergeado foi
aplicada e registrada no ledger oficial do Supabase. O contrato SQL versionado passou novamente
em produção dentro de `BEGIN/ROLLBACK`: DDL, RLS/grants, FKs sem cascade, deduplicação por pessoa,
idempotência, backoff e teto de três tentativas apenas para update, sem retry automático para
create. O rollback removeu todas as fixtures; a tabela `crm.hubspot_commercial_writeback`
permaneceu com **zero linhas**.

A Edge publicada corresponde ao código mergeado, exige JWT no gateway e valida credencial
administrativa no runtime. Smoke com chave pública foi recusado com **401 `unauthorized`**.
Não foi criado atalho, não se desligou JWT e não se expôs chave administrativa para completar
o teste HTTP.

A prévia de negócio em produção, com corte `2026-09-02T00:00:00Z`, encontrou exatamente
1 pessoa candidata e terminou em **0 creates, 0 updates e 1 bloqueio**
(`contato_hubspot_ausente`). O ledger ficou vazio. A amostra histórica de Marianne Santana
continua inalterada no HubSpot: estágio `1401915457` (Novo lead), sem `hs_lead_label`;
portanto a sugestão Novo lead → Aguardando contato humano + HOT não foi aplicada.

A implementação continua sem escrever identidade e consome somente os contratos canônicos
`public.mind_crm_comercial(pessoa_id)` e `public.mind_pessoa_fatos(pessoa_id)`. O backfill
de todas as conversas e a fila humana de divergência de estágio permanecem no
`BACKLOG.md` §7. O próximo gate é um teste HTTP autenticado em `preview` por uma execução
server-side autorizada; só depois cabe discutir habilitar `apply` num teste controlado.

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

## 5B. 03/09 — checkout atribuído + venda contextual no App

Gate de produto dado pela Adriana nesta conversa. Implementado e publicado em produção:

- migration `20260903002220_checkout_attribution_agents.sql` aplicada;
- `mindagent-chat` **version 32 / v1.10.0**, `verify_jwt=true`;
- `treble-inbound-agent` **version 32 / v1.6.0**, `verify_jwt=false` como antes;
- `mindagent-web → summit_b2c` ativo, sem mudar a entrada `mind_summit_app → concierge_summit`;
- checkout aceito somente se for `https://*.eduzz.com` e corresponder exatamente a um
  `checkout_url` oficial do Kit, preservando parâmetros de negócio como cupom;
- URL emitida com canal, `ai_agent`, campanha/id, motivo, Agent e token opaco; nenhuma PII;
- ledger idempotente em `engagement.agente_eventos` e leitura de conversões em
  `intelligence.v_conversoes_agente`.

Evidência: 10/10 testes novos, 16/16 contrato de resposta longa, 71/71 guardrail comercial e
contrato SQL real em `BEGIN/ROLLBACK`. O teste SQL provou retry sem duplicação e venda espelhada
voltando para evento + conversa. Não houve compra real: `envios_reais=0` e `conversoes_reais=0`
logo após o deploy.

Institute e pré-venda do Summit seguinte ficaram deliberadamente sem oferta/URL nesta entrega.
O runtime já suporta ambos; falta cadastrar a verdade comercial e o `checkout_url` oficial nos
Kits antes de permitir qualquer envio.

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
