# Mind Intelligence — arquitetura real

> O que o sistema **é hoje**, não o que uma IA imaginou. Fonte da verdade: banco real
> (`mind-agent`, Supabase). Quase tudo é teste/placeholder — dá pra remodelar à vontade.

## O que estamos construindo

Três agentes sobre um mesmo núcleo compartilhado:
- **Vendas** — conduz oportunidade comercial (qualquer vertical) e atualiza o HubSpot.
- **Atendimento** — pós-venda / suporte de quem já comprou.
- **Concierge** — embarcado no app do MindSummit; ajuda quem está no evento.

### Como um agente é montado
`prompt base` (comum a todos, em `agentes`) **+** `prompt da plataforma` (`concierge` p/ o
app, `treble` p/ WhatsApp) **+** `playbook da função` (vendas / atendimento / concierge —
independentes) **+** `contexto do produto` buscado na hora.

O vendedor vende Summit, Dash ou Institute com **o mesmo** playbook de vendas — muda só o
**contexto do produto** que ele busca. Playbooks vivem em `agentes.prompts` (por `chave`), por função.

### Onde mora a conversa e a inteligência de QUALQUER agente (regra de plataforma)
O núcleo é **um só e compartilhado** entre todos os agentes; muda só a **plataforma** (por onde
a pessoa fala) e a **função**. Quando nasce um agente numa plataforma nova (site, Instagram,
e-mail, telefone…), NÃO se cria um mundo à parte pra ele. A divisão é sempre esta:
- **Config da plataforma** → schema só de config (como `treble` p/ WhatsApp, `concierge` p/ o app):
  token, modelo, templates, flags. **Conversa não mora aqui.**
- **A conversa** (mensagens trocadas) → **SEMPRE** `engagement.conversas` + `engagement.mensagens`,
  com a coluna **`agente`** dizendo quem escreveu (ex.: `treble-inbound-agent`). Uma casa só pra
  todos. **Nunca** `treble.messages`, `concierge.mensagens`, `plataformaX.conversas`.
- **O que o agente APRENDE** com as mensagens (sinal, intenção, objeção, dossiê) → **SEMPRE**
  `intelligence.*`, marcando de qual agente veio. **Nunca** inteligência apartada por plataforma.
- **Quem a pessoa é** → `pessoas.pessoas` (identidade única); os canais dela → `engagement.identidades`.

Motivo: se cada plataforma tiver a sua tabela de conversa/inteligência, o vendedor do WhatsApp
não enxerga o que o concierge do app já sabia — a inteligência do Mind vira ilha. Detalhe completo
e o "antes de criar tabela, pergunte" estão no `README_FIRST.md`.

### O que acontece quando um lead chega
1. Identifica a pessoa e registra que ela chegou (e por onde) em `pessoas.pessoas`.
2. Deriva a **vertical** de onde veio: `intelligence.vertical_da_entrada(site, url)`
   (site do chat ou domínio do `first_url`) → grava em `intelligence.sinais_comerciais.vertical`.
3. Junta o que já se sabe dela, antes de responder:
   - histórico de vida no Mind → `crm.contato_espelho` + `crm.negocios_historicos`;
   - deal **aberto** agora → `crm.pipeline_summit_leads_captados` (e pipelines futuros por vertical).
4. Atua com o playbook da função; se for venda, ao fechar atualiza o card do pipeline /
   cria caso e reflete no HubSpot.
5. Destila **inteligência** sobre a pessoa (`intelligence`) e registra o **engajamento**
   (`engagement`) — enriquecendo o que sabemos dela a cada conversa.

## Mapa dos schemas (o que é real × teste × futuro)

**Núcleo do lead**
- `pessoas` — identidade canônica (1 linha = teste).
- `crm` — espelho do HubSpot. **REAL:** `contato_espelho` (11.587), `negocios_historicos`
  (7.092), `pipeline_summit_leads_captados` (2.675 = pipeline aberto), `mapa_produtos` (9).
- `intelligence` — o que sabemos do lead (sinais, intenções, dossiê, objetivos…). Teste/placeholder.
- `engagement` — conversas/mensagens/sessões. Dados de teste. A **origem do lead na chegada**
  é salva aqui (`origens`, provisório — a confirmar). *(candidato a virar vizinho de/parte de `intelligence`.)*
  A conversa do WhatsApp/Treble também mora aqui: `conversas` + `mensagens`, com a coluna
  `agente` marcando de qual agente veio a info (hoje `treble-inbound-agent`; haverá outros).
  O estado solto da venda (intent, objeção, needs_human, checkout, desfecho) fica em
  `conversas.variables` (jsonb) — sem coluna nova por campo.

**Verdades transversais**
- `ecossistema` — universais: `palestrantes_especialistas` (13). *(catálogo e políticas devem vir pra cá.)*
- `catalogo` — mapa vertical→produtos→pipeline: `produtos` (11). *(alvo: dentro de `ecossistema`.)*
- `agentes` — `prompts`: prompt base, playbooks e tom de voz, por `chave`
  (`playbook_router`, `playbook_summit_b2b`, `playbook_summit_b2c`, `playbook_cliente_suporte`,
  `tom_de_voz`). É AQUI que vivem os playbooks — não criar tabela separada.
- `platform` — infra de LLM: providers/models/routes + integrações. Real, útil.

**Verticais de produto** (produtos/ofertas + pipeline de cada frente)
- `summit_2026` — **RICO:** 67 sessões, 61 speakers, 27 locais, 25 ofertas (Prime/VIP/Mind,
  delegações, patrocínios), 17 docs. É a inteligência do evento deste ano.
- `institute` (formações), `dash` (consultoria), `eventos` (promocionais) — **vazios**,
  placeholders para o futuro. Tudo bem ficarem vazios.

**Plataformas dos agentes**
- `concierge` — config/inteligência do agente embarcado no app do Summit (templates, ferramentas, flags).
- `treble` — config dos agentes no WhatsApp (Treble). Catálogo de fluxos em `treble.polls`;
  status aberta/fechada por número em `treble.status_da_conversa`. Fluxo completo (janela de 24h
  → HubSpot, pra não disparar em cima de conversa aberta): ver **`docs/TREBLE_STATUS_24H.md`**.

## Fundação universal dos agentes — todo canal entra pela mesma porta

```
ENTRADA → PERSISTIR INTERAÇÃO → RESOLVER IDENTIDADE → pessoas.pessoas
                                   ↓ (etapa futura)
                            AGENT_CONTEXT → ROUTER → cérebro
```

**Canal não define identidade. CRM não define identidade.** `pessoas.pessoas` é a pessoa
canônica; `engagement.identidades` diz **como** a reconhecemos; `engagement.conversas` +
`engagement.mensagens` preservam a interação. Treble, web e app são **adaptadores**.

**A porta é uma só:** `public.mind_inbound(evento jsonb)`. O evento não tem nada de Treble:
`canal` (único obrigatório), `sessao_externa`, `mensagem {conteudo, papel, id_externo, blocos}`,
`identificadores {whatsapp, email, auth_user_id, hubspot_id, dispositivo}`, `nome`,
`origem {origem_codigo, utm_token, produto_codigo}`. Nenhum canal precisa mandar tudo, e
**ausência de HubSpot não é erro**.

**A ordem é a garantia.** A mensagem é gravada logo depois de resolver a conversa — antes de
identidade, IA, router, enriquecimento. A resolução de identidade roda dentro de um bloco de
exceção próprio: se ela explodir, o que a pessoa disse **continua registrado** e a próxima
entrada liga a mensagem órfã à pessoa. Antes disso o Treble só gravava no fim, junto com a
resposta: timeout da OpenAI apagava a fala do lead do sistema.

**Identidade = evidência determinística, com força.** `auth_user` (4) > `whatsapp` / `hubspot`
(3) > `email` (2). Nome **nunca** identifica sozinho — só preenche buraco. Dispositivo é
contexto do canal, não pessoa. Sem nenhum identificador determinístico não se cria pessoa.

**Conflito não funde.** Identificadores da mesma entrada apontando para pessoas diferentes:
escolhe a da evidência mais forte, registra o par em `engagement.identidade_fusoes`
(`status='pendente'`) e **não vincula** os identificadores da outra — ninguém vê dado de
terceiro. A fusão é decisão humana.

**Identidade não é formulário.** `falta_obrigatorio`, `pedir_email` e `falta_desejavel` saíram do
core. Regra: **use o que já sabemos antes de perguntar**. Só outro componente, mais tarde, pode
decidir perguntar algo quando for necessário para resolver a necessidade atual.

**As peças:** `mind_inbound` (contrato) · `mind_conversa_resolver` · `mind_mensagem_registrar`
(idempotente) · `mind_identidade_resolver` · `mind_identificadores_normalizar` ·
`mind_conversa_estado` (histórico/perfil — **não** é AGENT_CONTEXT) · `mind_turno_registrar`.
Adaptadores: `treble_agent_start` (+ janela de 24h, que é do canal) e `mindagent_chat_start`
(+ autenticação de sessão, que é do canal).

**O core não é público.** `create function` no Postgres dá EXECUTE a PUBLIC por padrão, e no
Supabase PUBLIC alcança `anon`/`authenticated` via PostgREST — qualquer um com a chave anon
poderia criar pessoa, gravar mensagem e **ler perfil alheio** em `mind_conversa_estado`. Todas as
funções do core foram revogadas de PUBLIC/anon/authenticated e concedidas só a
`postgres, service_role`. Os adaptadores são edge functions com service role; o site só chama a
edge `mindagent-bootstrap`, nunca RPC direto.

**E-mail citado não é identidade.** Achar um e-mail no texto não é evidência de que ele seja da
pessoa — "manda também pra minha colega ana@empresa.com" é o contraexemplo. Só
`email_informado` (semântica: *o lead disse que este e-mail é dele*) vira candidato a
identificador. E como o e-mail não vai em texto claro para a OpenAI, ele viaja **mascarado**
como `[email_1]`, `[email_2]`: o modelo devolve o rótulo do que é dele, e o adaptador resolve o
valor deste lado. A regex só extrai e valida depois que a semântica já está estabelecida.

**A conversa identificada é âncora.** Se `conversas.participante_id` já está preenchido, uma
entrada posterior **nunca** devolve outra pessoa. Evidência nova ou enriquece a pessoa ligada, ou
vira conflito pendente. Nunca troca `participante_id`, nunca move identificador.

**`mind_pessoa_completar` não tem autoridade de identidade** — só sobrenome, empresa e cargo.
E-mail, WhatsApp, auth e HubSpot passam exclusivamente por `mind_identidade_resolver`.

**Chaves que deixaram de assumir um canal só:** `engagement.conversas` agora é
`unique (canal, session_external_id)` — antes o id de sessão era único no sistema inteiro e dois
canais colidiam. `engagement.mensagens` é `unique (conversa_id, client_msg_id)` — id externo não
é globalmente único; a chave mínima que impede duplicar o **mesmo evento** é conversa + id.

## Ponte Pessoa Mind ↔ CRM/HubSpot

Uma pessoa do Mind pode ter **vários** contatos no HubSpot. A ponte liga todos e não escolhe
nenhum como principal — isso é decisão de outra etapa.

**Um caminho só: `public.mind_crm_vincular_pessoa(pessoa_id)`.** É a única função do banco que
escreve `crm.contato_espelho.pessoa_id`. Ela parte dos identificadores que a pessoa já tem em
`engagement.identidades` e procura contatos por `hubspot_id`, e-mail normalizado e telefone
(pelos últimos 10 dígitos — a convenção já indexada do espelho, `idx_ce_phone10`/`idx_ce_wa10`).

**Telefone compartilhado não decide identidade.** `hubspot_id` e e-mail exato são evidência forte;
telefone só vale quando aquele número aponta para **um único** contato no espelho. Número
corporativo/central que aparece em vários contatos não vincula ninguém — vira pendência
`suspeita_sobre_merge`. O achado que obrigou essa regra: uma "pessoa" tinha acumulado **41
contatos, com 41 nomes e 41 e-mails diferentes**, todos com o mesmo número.

Para cada contato encontrado: mesma pessoa → nada; sem dono → vincula; **de outra pessoa →
não sobrescreve, não funde**, registra pendência em `engagement.identidade_fusoes` e nem sequer
registra a identidade `hubspot` (isso moveria identificador). O `hubspot_id` do contato entra
como identidade pela porta única, ancorado na pessoa.

**Roda sozinha** no fim do `mind_inbound`, mas só quando há evidência nova (pessoa criada ou
identificador novo) — não varre o espelho a cada mensagem de conversa já resolvida. Isolada num
bloco de exceção: o CRM nunca derruba a ingestão.

**Os dois caminhos paralelos que existiam foram desligados.** `mind_espelho_ligar` casava
`pessoas.email`/`pessoas.whatsapp` por conta própria — lendo a *projeção* em vez das identidades;
agora delega (a parte de negócios e produtos ficou intacta). `pessoa_vincular_hubspot` escrevia
`pessoas.hubspot_id` direto, sem identidade e sem tocar no espelho; agora passa pelo resolvedor
e pela ponte, mantendo a assinatura que a edge `treble-status-hubspot` usa.

`pessoas.pessoas.hubspot_id` continua **atalho legado**: preenchido só quando está vazio e
ninguém mais é dono daquele valor. Para quem tem mais de um contato ele aponta para um deles de
forma arbitrária — a verdade multi-contato está em `engagement.identidades` + `crm.contato_espelho`.

## Schema `eduzz` — espelho do Blinket (bilheteria)  ⛔ *carga bloqueada por credencial*

Mesmo padrão do espelho do HubSpot: colunas promovidas para o que a gente usa **+ `payload jsonb`
com o registro cru**, para a carga nunca ficar presa a um palpite de formato — puxa primeiro,
promove coluna depois de ver o dado real.

`eduzz.eventos` · `eduzz.ingressos` (uma linha por participante da lista de presença, com
telefone normalizado pelo mesmo `telefone_normalizar`) · `eduzz.marcadores` ·
`eduzz.ingresso_marcadores` · `eduzz.sync_estado`.

`eduzz.ingressos.pessoa_id` existe e fica **nulo**: quem resolve identidade é
`mind_identidade_resolver`, nunca uma carga de terceiro.

**O que trava:** `EDUZZ_API_KEY` existe nos secrets (64 caracteres, hex) mas **não é access token
OAuth**. Diagnóstico: `api.eduzz.com/blinket/v1/events` existe e exige `Bearer` válido;
`api2.eduzz.com/credential/generate_token` é a rota certa do formato legado e respondeu
`#0002 Unauthorized - Invalid credentials` com `publickey=14449348` + a chave atual;
`accounts.eduzz.com/oauth/token` devolve tela de login (fluxo de navegador, não máquina).
Falta a **publickey** correta e o **e-mail da conta Eduzz**.

## Coletor factual de CRM — `public.mind_crm_fatos(pessoa_id)`

O que o CRM sabe sobre uma pessoa, para qualquer agente. **Só fatos**: sem score, sem ICP
inferido, sem decisão comercial. Deals, compras e pagamentos são Passo 5.

**Chega pelos contatos assim, e só assim:** `pessoa_id` → `engagement.identidades (canal='hubspot')`
→ `crm.contato_espelho.hubspot_id`. **Nunca por `pessoas.hubspot_id`** — a projeção legada diverge
da identidade em 70 pessoas e aponta para contato inexistente em 20.

Devolve `contatos[]` no plural, cada um com seu `hubspot_id` junto, para se saber de qual contato
veio cada fato. Nada de escolher um "principal". Campo vazio não aparece (`jsonb_strip_nulls`), e
as colunas permanentemente vazias do espelho (`produto_de_interesse`, `intent_signals`,
`hs_buying_role`, todas as de formação/certificação do Instituto) ficam de fora.

**`meta` é operacional:** quantos contatos, se há pendência de identidade aberta, o status do sync
em `crm.sync_estado` — e também `espelho_ultimo_sincronizado_em`, porque `sync_estado` está
travado em "rodando" desde 24/08 enquanto o espelho **é sincronizado todo dia**. Sem os dois, o
agente leria frescor errado.

## Fila de resolução — `engagement.identidade_fusoes`

Sem tabela nova. A que já existia virou a fila mínima de problemas de identidade/CRM.

**Três tipos:** `conflito_identidade` (evidências apontando para pessoas diferentes numa
conversa) · `contato_crm_de_outra_pessoa` (o contato do espelho já tem outro dono) ·
`suspeita_sobre_merge` (uma pessoa Mind colada a vários contatos por telefone compartilhado —
aqui `participante_origem` é nulo, porque ainda não existe uma segunda pessoa identificada).

**Idempotência por dois índices parciais:** por par+tipo quando há duas pessoas, por pessoa+tipo
quando não há. Enquanto uma pendência está `pendente`, a mesma não empilha. Resolver libera o
índice — se o problema voltar, ele reaparece na fila, que é o comportamento certo.

**Um escritor só:** `mind_conflito_registrar(pessoa, tipo, motivo, outra?, evidencia?)`. O
resolvedor de identidade e a ponte CRM usam o mesmo — não há dois formatos de gravação.

**Acesso:** `mind_pendencias_listar(status, tipo, limite, offset)` (a tabela tem RLS sem policy,
então sem essa função SECURITY DEFINER a fila é invisível) e `mind_pendencia_resolver(id,
'fundido'|'descartado')`, que só grava a decisão e `resolvido_em`. **Não executa merge.**

## Reconhecimento do lead — LEITURA, não cópia
Na chegada, o "dossiê" do lead é **montado por uma função que LÊ** (estende `crm.buscar_pessoa`),
**não** uma tabela nova. Nunca copiar histórico pra `pessoas`/`intelligence` (duplica e envelhece).
Papéis: `pessoas.pessoas` = identidade; `crm.*` = histórico/deals (lido ao vivo); `intelligence.*`
= o que o agente **aprende** (escrito depois); `engagement` = origem (`origens` catálogo +
`utm_sessoes` evento do lead) + conversas.
**Chave de join = email** → `crm.contato_espelho.hubspot_id` → **`crm.negocio_contatos`** (view:
relação deal↔contato derivada de `propriedades->_contatos`; 100% casa com o espelho) → os **deals
da pessoa**. Já funciona pros 2 pipelines espelhados: `default` (histórico, `negocios_historicos`)
e `917379159` (summit, `pipeline_summit_leads_captados`). `pessoa_id` segue NULO nesses espelhos
(ligamos por hubspot_id/email, não por pessoa_id). Pipelines ainda NÃO espelhados no Hub precisam
de sync (tabela por pipeline).

## Silence Re-evaluation Engine — quem manda no relógio  ⏸️ *pausado em 28/08*

> **Estado:** construído e testado, mas o cron `silence_reavaliar` (job 13) está **desligado** —
> ninguém acorda ninguém. O `silence_sync_from_analysis` segue ligado (só mantém o estado em dia,
> sem IA). Religa com `select cron.alter_job(13, active := true);`.
> As decisões pendentes estão em **BACKLOG item 2**.


Duas coisas diferentes que costumam ser confundidas: **REVIEW ≠ FOLLOW-UP.** Review é o sistema
acordar a oportunidade e *olhar* pra ela. Follow-up é falar com a pessoa. Toda review olha; nem
toda review fala.

**A divisão de trabalho:** a IA lê o estado comercial e decide *o quê*
(`ACT | WAIT | ESCALATE | DORMANT | STOP`). O **código** decide *quando* — a IA nunca escolhe
timestamp, e `NEXT_REVIEW_AT` nem aparece no schema de saída dela.

**Onde mora:** `intelligence.continuidade_comercial` (1 linha por conversa; PK `conversa_id`).
Guarda `continuation_status`, `next_review_at`, `next_review_policy`, `followup_count`,
`last_followup_at`, `last_decision` (decisão + cálculo, pra auditar) e `processing_until` (lock).

**Configuração do relógio:** `intelligence.config` chave `silence_timing_v1` — a matriz da seção 7
do playbook (1ª revisão: critical 30min · very_high 90 · high 180 · medium 360 · low 1440;
depois de follow-up, uma lista por chave; estourou a lista → `DORMANT`). Mudar o ritmo é mudar
esse JSON — não é mexer em código nem em prompt.

**Precedência (nesta ordem, e ela existe pra proteger a pessoa):**
1. compra (no CRM ou declarada), opt-out, `STOP`/`STOPPED` → não agenda nada;
2. `DORMANT` → sai da fila, só volta por evento;
3. `ESCALATE` com dono humano → pausa (o humano assumiu);
4. **sem open loop real → não agenda.** Silêncio sozinho não autoriza follow-up;
5. compromisso com data real → o compromisso manda;
6. senão, matriz determinística ancorada no **último evento da conversa** (nunca em `now()`).

**Duas travas que só existem porque o teste real mostrou que precisavam:**
- **Piso temporal.** Sem ele, conversa parada há dias reagendava sempre no passado e era
  reavaliada em loop a cada rodada do cron. Numa reavaliação o próximo passo é sempre no futuro,
  usando o mesmo intervalo da matriz.
- **Compromisso só com data real.** Quando o lead falou vago ("acho que respondem essa semana"),
  a reavaliação chutou 27/08 numa rodada e 31/08 na outra — a IA escolhendo o relógio pela porta
  dos fundos. Data de compromisso só vale se veio do analisador, que lê o que a pessoa
  efetivamente disse. Compromisso sem data é open loop, e quem manda nele é a matriz.

**As peças:** `silence_calcular_next_review` (o relógio, não grava nada) ·
`silence_sync_from_analysis` (chamada pelo `analise_gravar`, monta o estado) ·
`silence_claim_pendentes` (`FOR UPDATE SKIP LOCKED` + lock de 10 min) · `silence_registrar_decisao`
· `silence_compra_summit_2026` (`purchased`/`not_purchased`/**`unknown`** — na dúvida, `unknown`) ·
edge `silence-reavaliar` + cron a cada 5 min.

**Hoje ela NÃO envia mensagem** — decisão da Adriana. `ACT` vira registro, e por isso
`followup_count` não sobe: contar tentativa sem falar com ninguém queimaria as 3 retomadas do
playbook em silêncio. Quando a camada de envio existir, ela passa
`p_followup_enviado := true`. Ver **BACKLOG item 2**.

## Schemas do sistema (do Supabase — não são design nosso, ignorar)
`auth`, `storage`, `supabase_migrations` (histórico de migrations), `vault` (segredos),
`net`/`pg_net`, `pgbouncer`, `realtime`, `cron`, `extensions`, `graphql`/`graphql_public`
(GraphQL do PostgREST — não usamos, pode ignorar).

## Limpeza / pendências
- `quarentena` — **removido** (lixo).
- `mind` — `policies` (6) devem ir p/ `ecossistema`; `organization_content` vazio. Depois `mind` some.
- `public` — só tem o backend do painel admin (`mind_admin_*`); ideal mover p/ schema `admin`.
- **Faxina** de `engagement`+`intelligence` (feedback espalhado em 6 tabelas, perfis
  duplicados) — decidir tabela a tabela o que fica; são as casas da saída dos agentes.
- **Edge functions** (12) — inventariar e remover os mortos (`*-diag`); manter `hubspot-sync`,
  `treble-inbound-agent`, `mindagent-chat`.
