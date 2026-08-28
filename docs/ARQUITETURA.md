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
   - histórico de vida no Mind → `crm.contato_espelho` + `crm.vendas_historicas_mind_summit`;
   - deal **aberto** agora → `crm.pipeline_de_vendas_summit` (e pipelines futuros por vertical).
4. Atua com o playbook da função; se for venda, ao fechar atualiza o card do pipeline /
   cria caso e reflete no HubSpot.
5. Destila **inteligência** sobre a pessoa (`intelligence`) e registra o **engajamento**
   (`engagement`) — enriquecendo o que sabemos dela a cada conversa.

## Mapa dos schemas (o que é real × teste × futuro)

**Núcleo do lead**
- `pessoas` — identidade canônica (1 linha = teste).
- `crm` — espelho do HubSpot, **uma tabela por pipeline, com o nome do pipeline**. **REAL:**
  `contato_espelho` (11.829), `vendas_historicas_mind_summit` (7.092),
  `pipeline_de_vendas_summit` (2.675 = pipeline aberto), `pipeline_leads_inbound` (1.661),
  `empenho_summit_2026` (22), `mapa_produtos` (9).
- `intelligence` — o que sabemos do lead (sinais, intenções, dossiê, objetivos…). Teste/placeholder.
- `engagement` — conversas/mensagens/sessões. Dados de teste. A **origem do lead na chegada**
  é salva aqui (`origens`, provisório — a confirmar). *(candidato a virar vizinho de/parte de `intelligence`.)*
  A conversa do WhatsApp/Treble também mora aqui: `conversas` + `mensagens`, com a coluna
  `agente` marcando de qual agente veio a info (hoje `treble-inbound-agent`; haverá outros).
  O estado solto da venda (intent, objeção, needs_human, checkout, desfecho) fica em
  `conversas.variables` (jsonb) — sem coluna nova por campo.

**Verdades transversais**
- `ecossistema` — universais: `palestrantes_especialistas` (13). *(catálogo e políticas devem vir pra cá.)*
- `catalogo` — mapa vertical→produtos→pipelines: `produtos` (11). Tambem e o **registry comercial**:
  `pipelines_hubspot text[]` diz em quais pipelines de Deal do HubSpot cada produto e negociado
  hoje. *(alvo: dentro de `ecossistema`.)*
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

## Schema `eduzz` — espelho da bilheteria e das vendas  ✅ *carregado*

**Quem fala com a Eduzz não é este projeto.** É o Supabase `mind-summit-vendas-dashboard`
(`tkludhksqcnhhpgqyfqq`): ele tem dois tokens válidos no Vault dele (`eduzz_api_token` para o
Blinket, `eduzz_access_token` para as vendas) e já sincroniza sozinho — Blinket de 30 em 30 min
(`espelho_blinket_fire`/`_load`), vendas de 15 em 15 (`pull_eduzz_sales`).

O mind-agent **espelha o espelho**. Uma credencial, um sync. Montar uma segunda puxada aqui
seria uma segunda credencial e uma segunda coisa pra quebrar, buscando exatamente o mesmo dado.

```
Eduzz ──token──> projeto Vendas ──espelho_para_mind()──> mind-agent (schema eduzz)
                 (dono do sync)     leitura, com segredo      (só lê)
```

| peça | onde | o que faz |
|---|---|---|
| `public.espelho_para_mind(segredo, fonte, offset, limite)` | **no Vendas** | única porta. `SECURITY DEFINER`, **só leitura**, protegida por segredo no Vault de lá |
| `eduzz.ingressos` · `eduzz.vendas` | aqui | cópia crua da origem, sem coluna local |
| `eduzz.v_ingressos` · `eduzz.v_vendas` | aqui | as mesmas linhas **+ `pessoa_id` resolvido por junção** |
| `eduzz_espelho_gravar` / `_config` / `_estado` | aqui | encanamento do lote |
| edge `eduzz-espelho-sync` + cron job 14 (`:20`,`:50`) | aqui | orquestra, pagina de 500 |

**Carga completa: 3.202 ingressos + 3.192 vendas, em 5,4 s.**

**`pessoa_id` não é coluna, é junção.** Se fosse coluna, toda ressincronização apagaria a ligação
ou exigiria um passo extra pra refazê-la. Na view a resposta é sempre a atual e custa nada
(indexado). A regra do Passo 3 vale igual: **e-mail do cadastro do ingresso é evidência forte;
telefone só conta quando aponta para UMA pessoa** — `pessoa_criterio` diz qual dos dois casou.
Nem a view nem o sync escrevem identidade: essa porta continua sendo só `mind_identidade_resolver`.

| | linhas | por e-mail | por telefone único | sem pessoa |
|---|---|---|---|---|
| `v_ingressos` | 3.202 | 1.083 | 507 | 1.612 |
| `v_vendas` | 3.192 | 1.150 | 589 | 1.453 |

**1.352 pessoas do Mind já têm ingresso ligado.** Os "sem pessoa" são compradores que nunca
falaram com a gente em nenhum canal — e ficam sem pessoa mesmo. Não se inventa gente a partir
de uma compra.

**Por que a chave daqui não serve (fechado, não é palpite):** `EDUZZ_API_KEY` existe nos secrets
(64 caracteres, hex) e não abre nada sozinha. O `accounts-api.eduzz.com/oauth/token` só aceita
**form-encoded** (JSON devolve 500) e, em form-encoded com `client_id=14449348`, responde
**`404 App not found`** — não existe app OAuth para essa conta. O formato legado
(`api2.eduzz.com/credential/generate_token`) devolve `#0002 Invalid credentials` em todas as
permutações de publickey/apikey, inclusive trocadas. Se um dia se quiser puxar direto daqui,
o caminho é **criar um app OAuth na Eduzz**, não descobrir a chave certa.

## Espelhos — o encanamento (9 fontes, 2 projetos de origem)

O mesmo mecanismo serve todos os espelhos vindos de outros Supabase da casa. **Nenhum deles é
dono do dado; todos são leitura.**

```
projeto de origem                          aqui
─────────────────                          ────
mind-summit-vendas-dashboard
  ingressos_espelho          → blinket              → eduzz.ingressos            3.220
  eduzz_vendas_historico     → vendas               → eduzz.vendas               3.207
  credenciamento_participantes → cred_participantes → credenciamento_summit_2026.participantes    1.028
  credenciamento_yazo_envio_fila → cred_yazo_fila   → credenciamento_summit_2026.yazo_envio_fila  4.026
  credenciamento_yazo_espelho → cred_yazo_espelho   → credenciamento_summit_2026.yazo_espelho       378
  credenciamento_yazo_sync_state → cred_yazo_sync_state → …yazo_sync_state                            1
mind-hubpost
  eduzz_produtos             → produtos             → eduzz.produtos               290
  produto_catalogo           → produto_catalogo     → eduzz.produto_catalogo       169
  hubspot_stage_config       → hubspot_stage_config → eduzz.hubspot_stage_config    21
```

| peça | onde | o que faz |
|---|---|---|
| `public.espelho_para_mind(segredo, fonte, offset, limite)` | **em cada origem** | única porta. `SECURITY DEFINER`, **só leitura**, segredo próprio no Vault de lá |
| `public.espelho_estado` | aqui | uma linha por fonte: origem, destino, status, contagens, erro |
| `public.espelho_gravar` / `espelho_config` / `espelho_estado_set` | aqui | encanamento do lote |
| edge `eduzz-espelho-sync` + cron job 14 (`:20`,`:50`) | aqui | orquestra as 9, pagina de 500 |

O encanamento **não tem mais o prefixo `eduzz_`**: ele já serve dois schemas. Pelo mesmo motivo
a tabela de estado saiu de `eduzz.sync_estado` para `public.espelho_estado` — senão daqui a um mês
alguém abre o schema da Eduzz e encontra credenciamento lá dentro.

Todas as tabelas espelhadas têm **RLS ligado e nenhuma policy**: ninguém lê por RLS. Os schemas já
estão revogados de `anon`/`authenticated`; isso é a segunda tranca. O `service_role` passa por cima,
então o sync não sente.

**`credenciamento_summit_2026.participantes.password` não é espelhada.** O corte é feito na
própria porta da origem (`to_jsonb(t) - 'password'`), então o valor nem cruza a rede. O agente não
precisa de senha de credenciamento pra nada, e copiar credencial pra um segundo banco só aumenta
superfície.

### `eduzz.produto_catalogo` — onde mora "pago, cortesia ou patrocínio"

É o mapeamento SKU da Eduzz → linguagem do Mind → funil do HubSpot, mantido no `mind-hubpost`.
Tabela **viva**: cresce conforme produto novo é mapeado.

- `tipo_de_acesso` — **Pago** (92) · **Cortesia** (38) · **Patrocínio** (17)
- `tipo_de_venda` — **Eduzz** (102) · **Não é venda** (55) · **Direta** (12)
- `motivo_concessao` — Convidado (21) · Parceria (9) · Palestrante (2) · Imprensa (1)
- `origem_do_acesso` — `Mind` (29) ou o nome do patrocinador (Beiersdorf, Vale, Natura, Heineken…)
- `modalidade_comercial` — Individual (130) · Business (17)

Não se confunde com `catalogo.produtos` (11 linhas), que é o catálogo **conceitual** do Mind
(Summit / Institute / Dash). Um SKU da Eduzz vira linha em `eduzz.produto_catalogo`; um produto
do Mind vira linha em `catalogo.produtos`. Granularidades diferentes, donos diferentes.

### Dois vocabulários para a mesma coisa  ⚠️ *decisão da Adriana*

A origem do ingresso está classificada em **dois lugares, com palavras diferentes**:

| | `eduzz.produto_catalogo.tipo_de_acesso` | `credenciamento_summit_2026.participantes.ticket_origin` |
|---|---|---|
| | Pago · Cortesia · **Patrocínio** | Pago · Cortesia · **Convidado institucional** · **Staff** |

Qual vocabulário vale é decisão de negócio — não invento.

**A cobertura parcial é esperada, não é defeito.** Juntando `eduzz.vendas.id_do_produto` →
`produto_catalogo.eduzz_product_id` casam **1.078 Pago · 178 Cortesia · 47 Patrocínio**, e
**1.904 vendas ficam sem mapeamento**; no credenciamento, **213 de 1.028 participantes** estão
com `ticket_type = "SEM MAPA"`. A Adriana confirmou (28/08) que **está certo e ela vai completar
o mapeamento depois** — é conteúdo pendente, não bug de encanamento. Conforme ela mapeia na
origem, o espelho pega sozinho no ciclo seguinte. **Não "conserte" isso por conta própria.**

## Espelho do HubSpot — uma tabela por pipeline, com o nome do pipeline

Mora em **`crm`**. Não existe schema `hubspot` — um segundo schema pro mesmo CRM seria uma
segunda casa pra mesma coisa.

**As tabelas se chamam como o pipeline se chama no HubSpot.** Antes não era assim, e o nome
mentia: `pipeline_de_vendas_summit` guardava **negócios**, não leads — o que fez parecer
que ela e a `pipeline_leads_inbound` eram a mesma coisa. Não são: uma é objeto **Deal**, a outra
é objeto **Lead**, pipelines diferentes.

| fonte | objeto | pipeline no HubSpot | tabela | linhas |
|---|---|---|---|---|
| `hubspot_contatos` | Contact | — | `crm.contato_espelho` | 11.829 |
| `hubspot_negocios` | **Deal** | `917379159` — "Pipeline de vendas - Summit" | `crm.pipeline_de_vendas_summit` | 2.675 |
| `hubspot_negocios_historicos` | **Deal** | `default` — "Vendas Históricas Mind Summit" | `crm.vendas_historicas_mind_summit` | 7.092 |
| `hubspot_negocios_empenho_2026` | **Deal** | `t_0793…` — "Empenho Summit 2026" | `crm.empenho_summit_2026` | 22 |
| `hubspot_leads_inbound` | **Lead** | `918902366` — "Pipeline leads Inbound" | `crm.pipeline_leads_inbound` | 1.661 |

O rótulo **literal** do HubSpot (com acento, espaço e hífen) vive em
`crm.sync_estado.pipeline_nome` — o nome da tabela é só um identificador Postgres derivado dele.

**Pipeline novo = três linhas, nenhuma lógica.** O encanamento é orientado a dados
(`crm.sync_estado` carrega `tabela_destino` e `chave_destino`, e `mind_espelho_gravar` monta o
upsert sozinho): uma linha em `crm.sync_estado`, uma na config de `platform.integracoes`, e uma
no mapa `FONTES` da edge `hubspot-sync`.

### Empenho Summit 2026 — a compra pública

Negócio institucional que não passa pelo carrinho: SSP Brasília (R$ 60 mil), SEPLAG/MG, Unesp,
TCU, Petrobras, Polícia Federal. Por isso vive em pipeline próprio.

Dois estágios dele interessam ao passo dos ingressos que não nascem de venda Eduzz:
**"Gerar Ingresso (vendedor cadastra na Eduzz)"** → **"Ingresso Gerado (após webhook Eduzz)"**.
Ou seja: o ingresso de empenho **é** cadastrado na Eduzz, à mão, depois que o empenho é conferido.

### Dois consertos no sync (28/08)

**O status era mentira.** O CHECK de `crm.sync_estado.status` aceitava só
`ocioso | rodando | concluido | erro`, mas a edge grava **`parcial`** quando a fonte não termina
dentro do orçamento. A RPC estourava, a edge não checava o retorno, e o status ficava preso em
`rodando` pra sempre — desde 24/08 parecia sync quebrado quando na verdade os dados entravam
todo dia. Agora `parcial` é valor válido, e uma falha na marcação final aparece no relatório em
vez de sumir.

**O orçamento era global.** Os 20 s eram medidos desde o início da requisição, então a primeira
fonte comia tudo e as seguintes saíam sem ler quase nada. Agora o teto é folgado (120 s, sob os
150 s do `net.http_post` que dispara) e **cada fonte tem sua fatia**, medida do início dela.

## Realidade comercial universal — `public.mind_crm_comercial(pessoa_id)`  *(Passo 5A)*

Responde: **"o que comercialmente já sabemos sobre esta pessoa no HubSpot agora?"** Pertence à
Mind Intelligence, não ao vendedor do Summit. Serve qualquer agente futuro.

> **PLAYBOOK DECIDE COMO PENSAR. INTELLIGENCE INFORMA O QUE É VERDADE AGORA.**

Não escolhe estratégia, não pontua, não recomenda oferta, não decide rota, não cria Lead, não
escreve no HubSpot. Só coleta e normaliza fato.

**O contato é a fonte da verdade** do histórico consolidado (o que comprou, de que participou,
categoria, tipo de entrada). Os deals históricos **não** reconstroem esse histórico — servem só
para fato transacional (carrinho, fatura aberta, pendência, refund, valores, datas, cupom).

**`crm.mapa_produtos` enriquece, nunca filtra.** A ordem é: ler a realidade do contato primeiro,
depois anexar `produto_codigo` quando houver mapping. Propriedade sem mapping **não some** —
aparece em `contato_consolidado` com `produto_codigo` nulo, e `meta.evidencias_sem_mapping` conta
quantas foram. Numa pessoa de teste isso preservou 6 fatos, incluindo
`summit__categoria_do_ingresso`, que não tem mapping nenhum.

**Como descobre pipeline sem hardcode** — a divisão de papéis é o que elimina o `if summit → tabela A`:

```
catalogo.produtos.pipelines_hubspot   → QUAL produto usa QUAL pipeline (semântica)
crm.sync_estado.pipeline_id           → ONDE aquele pipeline está espelhado (operação)
        ↓
   tabela_destino → leitura via SQL dinâmico, identificador sempre vindo de
   crm.sync_estado e quotado com %I
```

Pipeline autorizado no catálogo mas sem linha em `crm.sync_estado` **não é silenciado**: sai em
`meta.pipelines_sem_espelho`.

**Identidade:** `pessoa_id` → `engagement.identidades (canal='hubspot')` → contato. **Nunca** por
`pessoas.hubspot_id`, `crm.contato_espelho.pessoa_id` ou `deal.pessoa_id` — foi por esse caminho
legado que veio o overmerge por telefone corporativo compartilhado. Pessoa com mais de um contato
mantém os dois, com proveniência por evidência; sem merge automático.

**Carrinho superado.** Um sinal transacional não convertido só é oportunidade **atual** se o
consolidado do contato não mostrar que a pessoa depois adquiriu aquele mesmo produto. Carrinho
Summit 2026 + `summit__participacao_anual` contendo 2026 → fica como fato histórico em
`superados`, com `superado_por_conversao: true`. Sem a participação → vai para `relevantes`.

**Refund é preservado sempre**, mesmo quando o contato ainda mostra o produto — há refunds que
ainda não atualizam as propriedades consolidadas, e ignorá-los esconderia a verdade.

Contrato: `{ ok, pessoa_id, contato_consolidado[], produtos[], lead_atual[], negociacoes[],
sinais_transacionais{relevantes,superados,refunds}, meta{contatos_hubspot_considerados,
sem_contato_hubspot, fontes_lidas, pipelines_sem_espelho, evidencias_sem_mapping, sync} }`.
Dois Leads ou duas negociações legítimas voltam os dois — o coletor não escolhe vencedor.

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
da pessoa**. Funciona pros quatro pipelines espelhados — ver a tabela em *Espelho do HubSpot*.
Pipeline novo é **três linhas de configuração**, não código: `crm.sync_estado` +
`platform.integracoes` + o mapa `FONTES` da edge.

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
