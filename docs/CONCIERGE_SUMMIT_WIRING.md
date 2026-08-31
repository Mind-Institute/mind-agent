# Concierge Summit — o `mindagent-chat` como executor da rota

> **O código é a fonte.** Desde a versão versionada da Edge, este documento
> explica **por que** o wiring é assim; o **o quê** está em
> `supabase/functions/mindagent-chat/index.ts`, e o diff real é
> `git diff <commit do baseline>..HEAD -- supabase/functions/`.
>
> **Versionar não publica.** O repositório não tem `supabase/config.toml` —
> conferido em toda a árvore —, então a integração do Supabase não tem
> configuração de Functions e o merge não republica a Edge. A publicação é
> manual, a partir do commit aprovado.

## 1. Baseline

`mindagent-chat` **version 23**, `VERSION "1.4.0"`, `verify_jwt: true`,
`ezbr_sha256 26a607f19992ee559bf3072a54f8fd741f7447a33432ac44a68115875dd1b0fd`,
trazida para o repositório num commit isolado, sem uma linha alterada.

Sobre esse hash, honestamente: `ezbr_sha256` é o hash do bundle que o Supabase
monta no deploy, não do `index.ts` — não é recomputável a partir do arquivo. O
que o commit do baseline atesta é a transcrição fiel da fonte viva, e é por
isso que ele vem sozinho: `git show` dele compara direto com a Function em
produção.

## 2. O que estava errado no caminho de hoje

```
… get_context → search(message + interesses) → save_message(user) → OpenAI(SYSTEM_INSTRUCTIONS)
```

1. **A rota nunca era verificada** — nenhum Capability Gate no caminho.
2. **O Kit não existia no caminho** — o executor recebia o retorno cru do
   retrieval, com a topologia física exposta, que é o que o Kit Loader existe
   para esconder.
3. **Memória e necessidade atual chegavam misturadas** em
   `personalizedSearchQuery`.
4. **A fala do lead só era gravada depois do retrieval.** Inofensivo enquanto
   nada entre os dois podia recusar o turno; com Gate e Kit entrando antes,
   uma recusa apagaria a mensagem da pessoa.

## 3. O caminho agora

```
auth → sessão/conversa → bind_identity → get_context
     → save_message(user)          ← antes de qualquer recusa
     → [modo ação do Play]         ← sai aqui, sem modelo
     → Gate  (mind_rota_capacidade)
     → Kit   (mind_agent_kit)  → fail-closed
     → OpenAI(kit.playbook + CONTRATO_DO_EXECUTOR)
     → save_message(assistant) · save_interests
```

**Sem Router**: `mindagent-web` é concierge por construção, e a regra canônica
é "se a rota já está determinada, pula o Router, **não** o Gate".
**Sem retrieval duplicado**: quem chama `mindagent_chat_search` é o provider
`mind_kit_programacao`, dentro do Kit.

### Playbook × contrato do executor

O playbook v7 — competência, aprovado, intocado — vem de
`agentes.prompts['playbook_concierge_summit']`, entregue pelo Kit. Ele fala de
`propor_memoria`, jornada e agenda da pessoa, check-in por QR, prints e o
resumo de continuidade entre os dias.

**Nada disso existe neste runtime** (`kit.tools` é `[]`). Por isso o
`CONTRATO_DO_EXECUTOR` declara o que este canal alcança e nomeia o que não
consegue, com a instrução de nunca dizer "reservei", "agendei" ou "registrei
sua presença". Editar o v7 de passagem seria mexer em conteúdo aprovado para
esconder uma limitação de runtime; quando as ferramentas existirem, o limite
encolhe e o playbook não muda.

## 4. `sensitivity` no interesse — coordenação D→C

Cada item de `interests` passa a carregar `sensitivity`, obrigatório no
`json_schema`, com o enum `none` + as chaves ativas de
`intelligence.memoria_bloqueios`.

- **O executor não decide política.** O valor é repassado **intacto** para
  `mindagent_chat_save_interests`, cuja assinatura não muda. Quem persiste ou
  descarta é o gate da Lane D, no banco.
- **Errar fecha, não abre.** Valor ausente ou fora do enum vira
  `"desconhecido"` — e desconhecido é bloqueado do outro lado. Se a tabela
  ganhar uma chave que este enum não conhece, o modelo não consegue emiti-la e
  o item é bloqueado; nunca liberado por omissão.
- **Classificação é pelo sujeito, não por palavra-chave.** O evento é sobre
  bem-estar no trabalho: burnout como tema da empresa é `none`. O que muda é a
  pessoa falar de si ou de alguém identificável — e declarar condição própria
  ao pedir conteúdo não deixa o item `none` só porque o rótulo parece
  profissional.

O enum está literal no código porque `json_schema` strict exige literal. A
autoridade continua sendo a tabela.

## 5. Modo ação do Play — coordenação E→C

`play-service.js` monta `{ ferramenta, argumentos, event_slug, identity,
session?, client_action_id }` e espera `{ ok, resultado }` ou
`{ ok:false, error:{ code, message } }`. O mesmo endpoint atende: o que
distingue os modos é a presença de `ferramenta`.

**Por que aqui e não numa segunda Edge.** As `mind_play_*` são
`SECURITY DEFINER` com `EXECUTE` só para `service_role` — o navegador não pode
chamá-las, e quem sabe quem é a pessoa é este runtime. Uma segunda Function
refaria auth, bind de identidade e sessão: dois lifecycles para a mesma pessoa.

**Yazo identificado sem conversa anterior funciona** porque sessão, bind e
contexto acontecem **antes** da bifurcação: quem chega direto ao Play tem a
sessão canônica criada por `mindagent_chat_start` e a pessoa resolvida por
`mindagent_chat_bind_identity`, exatamente como no chat.

**Allowlist estática**, auditável no código:

| ferramenta (cliente) | RPC | vínculo |
|---|---|---|
| `registrar_feedback_sessao` | `mind_play_feedback_sessao` | `p_conversa_id` |
| `registrar_nps` | `mind_play_nps` | `p_conversa_id` |
| `registrar_feedback_evento` | `mind_play_feedback_evento` | `p_mensagem_id` |
| `registrar_feedback` | `mind_play_feedback` | — |

O nome vindo do cliente é **chave de consulta**, nunca nome de RPC: só o que
está no mapa executa. **A ação não chama modelo nenhum** — e por isso a falta
da `OPENAI_API_KEY` não a derruba.

**Person-bound v1**: sem `pessoa_id`, a coleta não executa. A recusa volta como
`{ ok:false, error:{ code:"sem_pessoa" } }` em HTTP 200, porque é regra de
produto e não erro de servidor — a tela precisa poder dizer isso.

**Idempotência de transporte.** `client_action_id` chega com um contrato
explícito do cliente — *"rede repete; a pessoa não"* — e antes era só log. Os
writers da Lane E já são idempotentes por **chave natural**: upsert por
(participante, sessão), UNIQUE por pessoa no NPS, `(pessoa, tipo, valor,
contexto)` no feedback tipado. A exceção é `registrar_feedback_evento` sem
mensagem — que é exatamente como este runtime o chama: ali um retry vira dois
relatos.

A casa já existia: `concierge.ferramenta_chamadas`, com `idempotency_key` e
índice UNIQUE parcial, vazia e sem consumidor. A migration
`20260830233500` acrescenta só as duas funções que faltavam para escrever
nela — `mind_play_chamada_iniciar` e `..._concluir`. Nada de tabela, coluna,
identidade ou lifecycle novo.

```
reserva (insert … on conflict do nothing)
  ├ nova         → executa o writer → conclui (concluida | recusada | falhou)
  ├ repetida     → devolve o desfecho gravado, sem executar
  ├ em_andamento → 409 acao_em_andamento (a primeira ainda não respondeu)
  └ conflito     → 409 chave_conflitante
```

Reservar **antes** de executar é o que fecha a corrida: o índice UNIQUE decide
quem executa, não o relógio. Checar-depois-escrever deixaria as duas tentativas
simultâneas passarem — que é o defeito. Sem `client_action_id` nada muda: o
índice é parcial, NULL não colide, e a chamada executa como hoje. Se o ledger
não estiver disponível, a ação **falha fechado**: foi prometida deduplicação, e
executar assim mesmo é o defeito, não o contorno. Por isso a Edge só é
publicada depois desta migration.

**Recusa do writer é recusa, não sucesso.** As `mind_play_*` devolvem erro de
domínio como **dado** — `{ok:false, motivo:"sem_nota"}` — e não como exception,
então `acaoError` vem nulo. Olhar só o `acaoError` fazia a Edge responder
top-level `ok:true` carregando um `{ok:false}` dentro; o `play-service.js` lê o
top-level e a tela diria que registrou o que o banco recusou. Sucesso agora
exige as duas coisas: sem `acaoError` **e** `resultado.ok === true`.

O `motivo` do writer **é** o código de domínio que volta em `error.code` — nada
é traduzido, porque inventar enum aqui criaria uma segunda taxonomia para a
mesma recusa. Só passa o que tem forma de código (`^[a-z][a-z0-9_]{1,39}$`);
qualquer outra coisa vira `acao_recusada`, para não vazar texto interno. Recusa
de negócio responde **200 com `ok:false`**, igual ao `sem_pessoa`; contrato
quebrado (writer sem `ok`) é 502.

As `mind_play_*` vivem na PR #48 e ainda não estão em produção — conferido: 0
funções `mind_play_*` no banco vivo. Até ela mergear, a ação responde
`acao_falhou`. É o comportamento correto, e é o motivo de o E2E do Play
depender das duas lanes.

## 6. O que NÃO muda

- Auth, sessão anônima, `device_id`, `token_hash`, expiração, CORS, health.
- `mindagent_chat_start` · `bind_identity` · `get_context` · `save_message` ·
  **`save_interests`** — nenhuma assinatura tocada, nenhuma política de memória
  inventada aqui.
- Mascaramento de e-mail e telefone antes da OpenAI, `store: false`,
  `safety_identifier`, timeout de 25 s, `max_output_tokens`.
- Contrato HTTP do chat consumido pelo `chat-service.js`: `ok`, `answer`,
  `session`, `device_id`, `identity_received`, `profile_loaded`, `interests`,
  `sources`, `request_id`. `blocks.sources` mantém `{type, count}` — só a
  origem passa a ser o Kit.
- `treble-inbound-agent`: **não é tocado**. Continua chamando
  `mindagent_chat_search` direto no `agendaSegura`, e o contrato de saída do
  retrieval foi preservado para isso.

## 7. O que os testes provam — e o que só o E2E prova

`npm run test:edge` roda duas camadas, 52 contratos.

**Estrutura** (`tests/mindagent_chat_wiring.test.mjs`, 21) lê o fonte versionado
e trava as decisões de escrita: a ordem save → Gate → Kit → OpenAI, a ausência
de retrieval direto e de Router, o enum de sensibilidade, a allowlist do Play.

**Comportamento** (`tests/mindagent_chat_comportamento.test.mjs`, 31) **executa
o handler real**. O harness (`tests/helpers/`) troca só o que não existe no
Node — `Deno`, o cliente Supabase e a OpenAI — reescrevendo um único
especificador de import; se esse import mudar, o harness falha alto em vez de
testar outra coisa. O que ele observa é o que o executor faz:

| caso | contrato provado |
|---|---|
| chat normal | ordem exata das RPCs, `pergunta` × `interesses` separados, `instructions` começando pelo playbook do Kit, `sources` vindas do Kit, contrato HTTP intacto |
| Gate fechado | 503 `rota_indisponivel`, fala do usuário já persistida, Kit e modelo **não** chamados |
| Kit incompleto | fail-closed nas seis formas (sem bloco, sem playbook, `kit_disponivel:false`, `ok:false`, erro de RPC) — sempre antes da OpenAI |
| `event_slug` | malformado → 422 sem tocar o banco; de outro evento → repassado intacto, e quem recusa é o Kit |
| retry | `client_message_id` repassado verbatim, assistant em `<id>:assistant` |
| sensitivity | `none` e chave sensível repassadas intactas; ausente/inválida vira `desconhecido`, **nunca** `none`; evidência apontando para a fala, não para a resposta |
| Play sem conversa anterior | `start` → `bind_identity` → `get_context` → ferramenta, sessão canônica devolvida, sem modelo e sem turno de chat |
| Play sem pessoa | `sem_pessoa` em 200, nenhuma `mind_play_*` executada |
| fora da allowlist | `mind_play_nps`, `__proto__`, `constructor` e afins → 400 sem abrir sessão |
| idempotência | mesmo `client_action_id` → writer chamado **uma** vez e mesmo resultado; ids diferentes → tentativas distintas; sem chave → comportamento de hoje; em andamento e chave alheia → 409 sem tocar o writer; ledger fora → falha fechado |
| recusa do writer | `{ok:false,motivo}` sem erro de RPC → top-level `ok:false` com o motivo, em 200; retry devolve a mesma recusa; motivo sem forma de código → `acao_recusada`; writer sem `ok` → 502 |

A suíte foi verificada por mutação: mover o `save_message(user)` para depois do
Gate, afrouxar o fail-closed e trocar `desconhecido` por `none` fazem os testes
correspondentes falharem. Os dez testes das duas correções acima **falham no
HEAD anterior** (`b0e5135`) e passam agora — é o que os torna prova, e não
descrição.

O ledger SQL tem contratos próprios em
`tests/concierge_play_idempotencia_contract.sql`: 8, validados em
`BEGIN … ROLLBACK` contra produção, com produção conferida intacta depois.

`tsc --noEmit` passa limpo com shims de `Deno` e do cliente Supabase (não há
Deno neste ambiente — `deno.land` é bloqueado pela política de egresso).

**O que continua sendo só do E2E**, porque depende do mundo real e não do
código: o Gate realmente aberto e o Kit realmente montado no banco vivo; a
idempotência de fato do `mindagent_chat_save_message` (writer da Lane D); o
modelo real classificando `sensitivity` bem — o repasse está provado, o
julgamento não; as `mind_play_*` existindo em produção (PR #48); e o horário
local correto na resposta que a pessoa lê.

## 8. Ordem de go-live

1. Preview final → merge controlado das migrations e do código.
2. Confirmar o DB vivo (Gate aberto, Kit disponível).
3. **Publicar a Edge manualmente** a partir do commit aprovado — gate
   explícito da Adriana, porque muda comportamento de produto no canal vivo.
4. E2E real no app; corrigir somente o afetado.

Inverter 1 e 3 não quebra nada: a Edge nova depende do Gate aberto e do Kit
registrado, então publicá-la antes deixaria o canal em `rota_indisponivel`.
