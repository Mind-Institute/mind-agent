# Core Universal do Mind

> **Documento canônico.** Descreve o sistema como ele **é hoje**, verificado contra o Supabase
> real (`ymnmotgglsrxmjmonwjz`), não uma arquitetura ideal.
>
> Se este documento divergir do banco, **o banco vence** — e o documento é que está errado.
> Números conferidos em 29/08/2026.

---

## 1. Propósito

O Core Universal é o núcleo compartilhado por **todos** os agentes do Mind — vendas,
atendimento, concierge e os que vierem — e por **todos** os canais.

**Treble é um adapter de canal, não a arquitetura.** O mesmo vale para o app do Summit, o site
e qualquer canal futuro (Instagram, e-mail, telefone).

Agente novo **não reimplementa** identidade, contexto, memória ou histórico. Ele **consome** o
Core. Se cada canal tiver a sua tabela de conversa e a sua noção de pessoa, o vendedor do
WhatsApp não enxerga o que o concierge do app já sabia — e a inteligência do Mind vira ilha.

---

## 2. Arquitetura conceitual congelada

Quatro camadas, com responsabilidades que não se misturam:

| camada | responde |
|---|---|
| **INTELLIGENCE** | o que é **verdade agora** |
| **PLAYBOOK** | como um excelente profissional **pensa e atua** |
| **DECISIONING** | qual **estratégia** faz sentido agora |
| **AGENT** | o que efetivamente **diz ou faz** |

> **PLAYBOOK DECIDE COMO PENSAR. INTELLIGENCE INFORMA O QUE É VERDADE AGORA.**

Runtime universal alvo:

```
QUALQUER ENTRADA
  → INGESTÃO
  → IDENTIDADE
  → AGENT_CONTEXT
  → POLÍTICA DO CANAL (recorta as competências possíveis)
  → ROUTER (escolhe dentro delas)
  → CAPABILITY GATE
  → KIT DA ROTA
  → DECISIONING
  → AGENT
  → AÇÃO
  → MEMÓRIA / CONTINUIDADE
```

**O runtime completo ainda NÃO está implementado.** Hoje existem, de ponta a ponta, a
**ingestão**, a **identidade** e os **coletores factuais**; o **AGENT_CONTEXT** (§9), o **Router**
(§10) e o **Capability Gate** (§10B) existem e estão cobertos por teste, mas deliberadamente fora
do runtime — nada em produção depende deles ainda. Kit Loader, Decisioning e memória universal
seguem como arquitetura congelada, não código.

---

## 3. Identidade canônica

**`pessoas.pessoas.id` é o `pessoa_id` canônico e permanente.** (2.940 pessoas)

`pessoas.pessoas` é o **eixo de identidade**, não um perfil completo. O que sabemos *sobre* a
pessoa mora em `crm.*` (o que o CRM sabe) e em `intelligence.*` (o que o agente aprendeu).

**Identificadores e evidências vivem em `engagement.identidades`** (7.684 linhas):

| canal | o que é |
|---|---|
| `auth_user` | login no app — evidência mais forte (força 4) |
| `whatsapp` · `hubspot` | força 3 |
| `email` | força 2 |

HubSpot, e-mail, WhatsApp e auth são **identificadores/evidências**, nunca IDs alternativos de
pessoa. CRM e Engagement constroem conhecimento **ao redor da mesma pessoa** — a pessoa pode
nascer primeiro no Mind ou primeiro no CRM, e nos dois casos o eixo é o mesmo `pessoa_id`.

**Nome nunca identifica sozinho.** Só preenche buraco. Dispositivo é contexto de canal, não
pessoa. Sem nenhum identificador determinístico, não se cria pessoa.

### Conflito não funde

Identificadores da mesma entrada apontando para pessoas diferentes:

```
detecta → persiste evidência → vira pendência → NÃO faz auto-merge → resolução humana
```

A pendência vai para `engagement.identidade_fusoes` (263 pendentes hoje), e os identificadores
da outra pessoa **não são vinculados** — ninguém vê dado de terceiro.

### D5 — identidade universal (23/09/2026)

Regra #1 do sistema (`READ_ME_FIRST.md`): **toda linha sobre uma pessoa nasce ligada à
pessoa.** O que muda em relação ao texto acima:

- **Espelho passa pela porta única na escrita.** Antes, fonte em lote (HubSpot, Eduzz,
  credenciamento, Yazo) entrava como espelho e a pessoa era resolvida por junção na leitura.
  Agora cada tabela-fonte tem `pessoa_id`, `pessoa_criterio` e `pessoa_resolvido_em`, e um
  trigger `before insert or update` (`mind_pessoa_antes_de_escrever`) chama
  `mind_identidade_resolver` antes de a linha existir. Falha de identidade não bloqueia a
  escrita. `mind_pessoa_ligar_tabela(tabela, mapa)` põe uma tabela nova na regra.
- **Canais novos em `identidades`:** `cpf`, `cnpj`, `credenciamento`, `learnworlds` (além
  de `yazo` e `eduzz`, que já existiam no CHECK). Força: login 4 · WhatsApp e ids de
  terceiro 3 · e-mail 2 · **CPF/CNPJ 1** — evidência de apoio; nunca escolhem, criam nem
  abrem conflito. CPF igual com e-mail, WhatsApp ou nome diferente é pessoa diferente.
- **Só evidência forte cria pessoa**, e só quando nenhuma pessoa existente está por
  enriquecer (`pessoas.pessoas.enriquecida_em` nulo): enriquecer e unificar antes de criar.
- **Todo conflito nasce com proposta** (`identidade_fusoes.padrao`, `proposta`): quem
  sobrevive (login no app > mais identificadores > mais antiga), confiança, motivo.
- **Fusão existe, e só por decisão.** `mind_pessoa_fundir` repointa dinamicamente toda FK
  para `pessoas.pessoas`, mantém a absorvida com `fundida_em` (nenhum id morre) e recusa
  rodar fora de `mind_fusao_decidir`, que exige a decisão da Adriana — padrão inteiro só
  para confiança alta; média e baixa linha a linha.
- **Causa-raiz corrigida em `mind_crm_vincular_pessoa`:** ao ligar um contato do HubSpot à
  pessoa, o e-mail, os telefones e o nome do contato viram identidade dela. Antes só o id do
  HubSpot entrava, e a pessoa renascia no próximo login do app (586 duplicatas em 23/09).
- **`crm.contato_espelho.pessoa_id` deixa de ser legado**: é preenchido pela porta única,
  como em qualquer tabela-fonte. A leitura canônica continua por `identidades`.

| função | papel |
|---|---|
| `public.mind_pessoa_antes_de_escrever()` | trigger das tabelas-fonte: resolve ou cria antes de escrever |
| `public.mind_pessoa_ligar_tabela(regclass, jsonb)` | põe uma tabela na regra (colunas + trigger) |
| `public.mind_pessoa_enriquecer(uuid)` | fase A: completa uma pessoa com o que as fontes ligadas sabem; nunca cria |
| `public.mind_identidade_enriquecer_todas(int, bool)` · `mind_identidade_criar_faltantes(regclass, int, bool)` | motores das fases A e C, em lotes, com simulação |
| `public.mind_fusao_propor(uuid, uuid, text)` | classifica a duplicata e propõe quem sobrevive |
| `public.mind_fusao_decidir(text, text, text)` | **o único caminho que funde** (aprovar) ou descarta (rejeitar) |
| `public.mind_pessoa_fundir(uuid, uuid, text)` | a fusão em si; recusa-se fora de `mind_fusao_decidir` |
| `public.mind_pessoa_canonica(uuid)` | segue `fundida_em` até a sobrevivente |
| `pessoas.v_pessoa_360` | a pessoa com todos os ids numa linha |

### Funções vivas

| função | papel |
|---|---|
| `public.mind_inbound(p_evento jsonb) → jsonb` | **porta única de entrada** de qualquer canal |
| `public.mind_conversa_resolver(p_evento jsonb)` | resolve/abre a conversa |
| `public.mind_mensagem_registrar(p_conversa_id, p_papel, p_conteudo, …)` | persiste a mensagem |
| `public.mind_identidade_resolver(p_identificadores, p_nome, p_canal, p_pessoa_ancora)` | **única porta que escreve identidade** |
| `public.mind_identificadores_normalizar(p_ids jsonb)` | normaliza e atribui força |
| `public.mind_conflito_registrar(p_pessoa, p_tipo, p_motivo, p_outra, p_evidencia)` | **único escritor** da fila de pendências |
| `public.mind_pendencias_listar(p_status, p_tipo, p_limite, p_offset)` | lê a fila |
| `public.mind_pendencia_resolver(p_id, p_status)` | resolve uma pendência |
| `public.mind_conversa_estado(p_conversa_id)` · `mind_turno_registrar(…)` · `mind_pessoa_completar(…)` | estado e turno |

**A ordem em `mind_inbound` é a garantia:**

```
1. resolve a conversa
2. PERSISTE A MENSAGEM        ← antes de identidade, IA, router, enriquecimento
3. resolve identidade (em bloco de exceção próprio, ancorada na conversa)
4. liga conversa + mensagens à pessoa
5. vincula ao CRM só quando há evidência nova
```

Se a identidade explodir, o que a pessoa disse **continua registrado**, e a entrada seguinte
liga a mensagem órfã. Conversa já identificada é **âncora**: ganha de qualquer palpite novo.

### ⚠️ `pessoa_id` legado em tabelas CRM

~~Algumas tabelas de CRM têm uma coluna `pessoa_id` de origem histórica. **Ela não é caminho
canônico de leitura e não deve ser propagada para tabelas novas.** Ver §13.~~

> **Revisto por D5 (23/09/2026).** A coluna `pessoa_id` passa a ser **obrigatória** em toda
> tabela que fala de pessoa, preenchida pela porta única antes da escrita. O que continua
> valendo: a leitura canônica dos identificadores é por `engagement.identidades`, e o
> `pessoa_id` histórico que **não** passou pela porta é o legado — a passada D5 o refaz.

### `public.mind_pessoa_fatos(p_pessoa_id uuid) → jsonb`  *(Passo 7)*

Responde: **"quem é esta pessoa, em fatos?"** — e nada além disso.

Lê `pessoas.pessoas`, `engagement.identidades`, `engagement.identidade_fusoes` e
`crm.contato_espelho`. Sem LLM, sem inferência, sem score. Devolve `perfil` (primeiro nome,
sobrenome, empresa, cargo), `identificadores`, `conflitos_perfil` e `meta`.

**O caminho para o CRM é um só:**

```
pessoa_id → engagement.identidades (canal='hubspot') → identificador → crm.contato_espelho.hubspot_id
```

`pessoas.pessoas.hubspot_id` e `crm.contato_espelho.pessoa_id` são legado e **não** são caminho
de leitura. Uma identidade `hubspot` sem espelho correspondente não é silenciada nem inventada:
vira `meta.identidades_hubspot_sem_espelho`, e nunca um conflito de perfil.

**Divergência não elege vencedor.** Para cada campo, os valores não vazios de `pessoas.pessoas` e
de todos os contatos CRM ligados canonicamente são comparados com **trim, espaços consecutivos e
case** — só isso, nada de acento, similaridade ou semântica. Então:

| valores distintos | resultado |
|---|---|
| 0 | `perfil[campo] = null` |
| 1 | `perfil[campo]` = esse valor |
| 2 ou mais | `perfil[campo] = null` **e** o campo entra em `conflitos_perfil` |

No conflito, cada valor carrega a proveniência — `{"tipo":"pessoa"}` ou
`{"tipo":"crm","hubspot_id":…}`. Dois contatos que trazem o mesmo valor aparecem como **um**
valor com **duas** fontes. Nenhum `updated_at` desempata: esses timestamps são da linha, não do
campo, e usá-los seria inventar precedência.

`meta.pendencia_identidade` reporta fusões em aberto para a pessoa. É **fato, não efeito**: não
remove dado, não troca `pessoa_id`, não funde e não desempata perfil.

**Fato da pessoa ≠ estado da oportunidade.** Empresa e cargo são fatos sobre a pessoa e moram
aqui. B2B/B2C classifica a **negociação atual**, muda de uma conversa para outra e **não** pertence
a esta função — nem ICP, tier, produtos, compras, intenção, estágio, score ou recomendação.

---

## 4. CRM / HubSpot

O espelho do HubSpot mora em **`crm`**. Não existe schema `hubspot` — um segundo schema para o
mesmo CRM seria uma segunda casa para a mesma coisa.

**O caminho canônico até o HubSpot:**

```
pessoa_id
  → engagement.identidades (canal='hubspot')
  → HubSpot Contact ID
  → crm.contato_espelho.hubspot_id
```

**Nunca** por `pessoas.pessoas.hubspot_id` (projeção legada) nem por
`crm.contato_espelho.pessoa_id`.

Uma pessoa pode ter **mais de um contato HubSpot**. Todos contam, cada fato preserva de qual
contato veio, e **não há merge automático**.

| função | papel |
|---|---|
| `public.mind_crm_vincular_pessoa(p_pessoa_id uuid) → jsonb` | **único** escritor de `crm.contato_espelho.pessoa_id` |
| `public.mind_crm_fatos(p_pessoa_id uuid) → jsonb` | coletor factual de **perfil** CRM |
| `public.mind_crm_comercial(p_pessoa_id uuid) → jsonb` | coletor factual da **realidade comercial** |
| `public.mind_crm_sync_frescor() → jsonb` | frescor dos espelhos, por fonte |

**Nenhum deles é Decisioning.** Não escolhem estratégia, não pontuam, não recomendam, não
escrevem no HubSpot.

### Espelho: uma tabela por pipeline, com o nome do pipeline

| fonte | objeto | pipeline no HubSpot | tabela | linhas |
|---|---|---|---|---|
| `hubspot_contatos` | Contact | — | `crm.contato_espelho` | 11.829 |
| `hubspot_negocios` | **Deal** | `917379159` — "Pipeline de vendas - Summit" | `crm.pipeline_de_vendas_summit` | 2.675 |
| `hubspot_negocios_historicos` | **Deal** | `default` — "Vendas Históricas Mind Summit" | `crm.vendas_historicas_mind_summit` | 7.092 |
| `hubspot_negocios_empenho_2026` | **Deal** | `t_0793…` — "Empenho Summit 2026" | `crm.empenho_summit_2026` | 22 |
| `hubspot_leads_inbound` | **Lead** | `918902366` — "Pipeline leads Inbound" | `crm.pipeline_leads_inbound` | 1.661 |

O rótulo literal do HubSpot vive em `crm.sync_estado.pipeline_nome`; o nome da tabela é só um
identificador Postgres derivado dele.

Sync: edge `hubspot-sync` (dispara por `public.mind_espelho_disparar()`, cron diário).
`public.mind_espelho_gravar` monta o upsert a partir de `crm.sync_estado.tabela_destino` —
por isso pipeline novo é **três linhas de configuração**, não código.

---

## 5. Fontes da verdade comerciais

Esta seção é a que mais custa caro errar.

> **D1 — 21/09/2026, decisão da Adriana: a direção do fluxo está invertida.** O Supabase passa
> a ser a fonte da verdade do histórico do cliente, e passa a **alimentar** o HubSpot. O HubSpot
> deixa de ser origem e vira destino.
>
> **O que isso muda hoje: nada na leitura.** Enquanto a escrita para o HubSpot não for ligada —
> e **ligar é write-back operacional material, portanto continua atrás do gate de `AGENTS.md`**
> — quem responde pelo histórico consolidado continua sendo o contato espelhado, exatamente
> como descrito abaixo. D1 decide para onde a seta aponta; não autoriza o disparo.
>
> **O que isso muda já:** informação nova sobre o cliente nasce no Supabase, não no HubSpot.
> Curadoria à mão no HubSpot que vire fato — como o histórico de Summit — é dívida a trazer
> para cá, não padrão a repetir. Quem manda em cada fato, fonte por fonte, é registrado no
> schema `registry` (§12.11 do `BACKLOG.md`), não deduzido caso a caso.

### D3 — até onde o histórico do cliente vai hoje

Decisão da Adriana, 21/09/2026. **O histórico consolidado cobre três verticais com três
profundidades diferentes, e prometer paridade seria ficção de dado.**

| vertical | escopo | por quê |
|---|---|---|
| **Summit** | **completo** | compra, credenciamento e participação existem como dado |
| **Institute** | **parcial** | oferta, programa e encontro existem; `institute.programa_pessoas` tem 9 vínculos, e o histórico de matrícula ainda **não** foi trazido do LearnWorlds |
| **Dash** | **fora** | o schema `dash` inteiro tem 2 linhas, ambas de documento — **nenhuma de pessoa**. Não há histórico de cliente a consolidar |

Dash sai por **ausência de dado**, não por decisão de produto: entra quando houver cliente
ali. Enquanto não houver, agente, painel e relatório não devem prometer a vertical.

### Histórico consolidado de compra e participação → **o CONTATO**

`crm.contato_espelho`, incluindo o `propriedades jsonb` com o registro cru inteiro. É dali que
se entende **produtos adquiridos, participações, categoria, tipo de entrada e o histórico
consolidado** da relação da pessoa com os produtos.

Propriedades multi-select do HubSpot vêm separadas por `;` (`"2024;2025;2026"`).

### `crm.mapa_produtos` **não** é fonte da verdade

É **tradução auxiliar**: propriedade/evidência do contato → `produto_codigo`. `valor_origem='*'`
significa "qualquer valor não vazio serve".

**Propriedade relevante sem mapping continua existindo.** O coletor lê a realidade do contato
primeiro e só depois anexa `produto_codigo` quando há mapping. O mapa nunca filtra o que existe.

### Lead Object → verdade comercial corrente universal

`crm.pipeline_leads_inbound`. Associado por `hs_primary_contact_id`, nunca por `pessoa_id`
legado. É **universal**: consultado sempre, independentemente de produto.

### Deal pipelines correntes → negociações específicas de produto

Descobertos por `catalogo.produtos.pipelines_hubspot` (§6).

### Histórico de deals → detalhe transacional, e só

`crm.vendas_historicas_mind_summit` serve para **carrinho, fatura, pendência, refund, upgrade,
datas, valores, cupom**. A coluna `situacao` já classifica: `fechado` · `carrinho_abandonado` ·
`fantasma` · `pendente_a_confirmar` · `aberto_status_aberto` · `aberto`.

**Deals históricos NÃO reconstroem o histórico consolidado de compra.** Isso é do contato.

### Regra determinística do sinal superado

```
sinal não convertido (carrinho / fatura aberta / pendência)
+ contato confirma posteriormente a aquisição daquele produto
= sinal histórico SUPERADO, não oportunidade atual
```

Sem a confirmação no contato, o sinal é **oportunidade comercial atual**.

### Refund

**Refund continua aparecendo como evidência transacional** mesmo quando o contato ainda mostra o
produto. Há refunds que ainda não atualizam as propriedades consolidadas; ignorá-los esconderia
a verdade. Corrigir isso pertence ao Passo 22.

---

## 6. Catálogo de produtos

`catalogo.produtos` (11 linhas) é **vocabulário canônico de produto + registry comercial**.

| campo | o que é |
|---|---|
| `codigo` | identificador canônico (`mind-summit-2026`) |
| `nome` · `tipo` · `vertical` | descrição |
| `vende` · `ativo` | se é produto corrente |
| `schema_dados` | schema onde vive a inteligência daquele produto (`summit_2026`) |
| `pipelines_hubspot text[]` | **Deal Pipelines onde negociações correntes daquele produto são geridas** |

Hoje, o único produto corrente:

```
mind-summit-2026   ativo=true  vende=true  vertical=summit  schema_dados=summit_2026
pipelines_hubspot = [ '917379159',                          -- Pipeline de vendas - Summit
                      't_0793cc05e971d67df328451ab573de97' ] -- Empenho Summit 2026
```

**Não entram nesse array:**
- `918902366` — Pipeline Leads Inbound: é **universal**, não pertence a produto nenhum;
- `default` — Vendas Históricas Mind Summit: não é pipeline corrente do produto;
- qualquer pipeline que exista no HubSpot sem ser gestão corrente confirmada daquele produto.

### A separação que elimina o hardcode

```
catalogo.produtos   = QUAL produto usa QUAL pipeline      (semântica de produto)
crm.sync_estado     = ONDE aquele pipeline está espelhado (operação)
```

`crm.sync_estado` carrega `pipeline_id → pipeline_nome → tabela_destino`. É por isso que o
coletor comercial **não** contém `if summit → tabela A`.

---

## 7. Componentes implementados — Passos 1 a 5A, fechados

### Passo 1 — Ingestão + identidade universal
Porta única `public.mind_inbound(jsonb)`. Evento sem nada de Treble: `canal` (único
obrigatório), `sessao_externa`, `mensagem {conteudo, papel, id_externo, blocos}`,
`identificadores {whatsapp, email, auth_user_id, hubspot_id, dispositivo}`, `nome`,
`origem {origem_codigo, utm_token, produto_codigo}`. **Ausência de HubSpot não é erro.**
Treble, web e app viraram adapters. Detalhe em §3.

### Passo 2 — Ponte pessoa ↔ HubSpot
`public.mind_crm_vincular_pessoa(uuid)` é a única função que escreve
`crm.contato_espelho.pessoa_id`. Telefone só vale como evidência quando identifica **um**
contato; telefone corporativo compartilhado vira pendência, não vínculo.

### Passo 3 — Fila persistente de resolução de conflito
`engagement.identidade_fusoes`, com três tipos: `conflito_identidade` ·
`contato_crm_de_outra_pessoa` · `suspeita_sobre_merge`. Escritor único
(`mind_conflito_registrar`), leitura por `mind_pendencias_listar`, resolução humana por
`mind_pendencia_resolver`. **263 pendências abertas.**

### Passo 4 — Coletor factual de CRM
`public.mind_crm_fatos(p_pessoa_id uuid) → jsonb`. Devolve `contatos[]` (um por HubSpot
Contact, com o `hubspot_id` junto) + `meta`. **Só fatos** — sem score, sem ICP inferido, sem
decisão comercial.

### Passo 5A — Coletor da realidade comercial
`public.mind_crm_comercial(p_pessoa_id uuid) → jsonb`.

```jsonc
{
  "ok": true,
  "pessoa_id": "…",
  "contato_consolidado": [   // a realidade do contato, com ou sem mapping
    { "hubspot_contact_id": "…", "propriedade": "…", "valor": "…", "produto_codigo": "…|null" }
  ],
  "produtos": [              // rollup canônico do que casou com catalogo.produtos
    { "produto_codigo": "…", "nome": "…", "vertical": "…", "evidencias": [ … ] }
  ],
  "lead_atual": [ /* fatos do Lead Object */ ],
  "negociacoes": [
    { "produto_codigo": "…", "vertical": "…", "pipeline_id": "…", "pipeline_nome": "…", /* fatos do deal */ }
  ],
  "sinais_transacionais": {
    "relevantes": [ { "tipo": "carrinho_abandonado|fatura_aberta|pendencia", "superado_por_conversao": false, … } ],
    "superados":  [ { "superado_por_conversao": true, "superado_por": "…", … } ],
    "refunds":    [ { "aviso": "…", … } ]
  },
  "meta": {
    "contatos_hubspot_considerados": [ … ],
    "sem_contato_hubspot": false,
    "fontes_lidas": [ … ],
    "pipelines_sem_espelho": [ … ],
    "evidencias_sem_mapping": 0,
    "sync": [ … ]
  }
}
```

Também: `public.mind_crm_sync_frescor() → jsonb`.

**A leitura de negociações não tem hardcode de tabela:**

```
catalogo.produtos.pipelines_hubspot → crm.sync_estado.pipeline_id → tabela_destino
```

SQL dinâmico com o identificador vindo **sempre** de `crm.sync_estado`, quotado com `%I`.
Pipeline autorizado no catálogo sem linha em `crm.sync_estado` **não é silenciado**: sai em
`meta.pipelines_sem_espelho`.

Se houver dois Leads ou duas negociações legítimas, os dois voltam. **O coletor não escolhe
vencedor.**

---

## 8. Engagement

Estado real hoje:

| tabela | linhas | o que é |
|---|---|---|
| `engagement.conversas` | 6.747 | contêiner de conversa/sessão por canal — **pode conter várias mensagens** (máximo observado: 94) |
| `engagement.mensagens` | 7.464 | papéis canônicos: `lead`, `agente`, `sistema` |
| `engagement.identidades` | 7.684 | como reconhecemos a pessoa |
| `engagement.identidade_fusoes` | 263 | fila de pendências |
| `engagement.origens` · `utm_sessoes` | — | origem do lead na chegada |

**Engagement inclui interação humana e de IA.** Mensagem humana é **first-class data**, não um
caso especial. A coluna `agente` fica em `engagement.conversas` e diz por qual runtime a conversa
passou (`treble`, …) — é proveniência operacional, não autoria.

O estado solto da venda (intent, objeção, needs_human, checkout, desfecho) fica em
`engagement.conversas.variables` (jsonb) — sem coluna nova por campo.

### O histórico é PESSOA-WIDE, não conversa-escopo

`participante_id` é o nome legado da coluna em `conversas` e `mensagens`, mas tem **FK real para
`pessoas.pessoas`** (verificado: zero órfãos). É o `pessoa_id` canônico. Não se cria uma coluna
`pessoa_id` duplicada.

1.926 das 2.939 pessoas com histórico têm **mais de uma conversa** (máximo: 10 conversas,
110 mensagens). Qualquer coletor preso à conversa atual perde a maior parte da história — por
isso o coletor atravessa todas as conversas da pessoa.

### Normalização do Treble — text, HSM e mídia

`public.treble_sessao_encerrada_gravar(jsonb)` é o adapter do WhatsApp. Ele normaliza:

| tipo no payload | `conteudo` | `blocos` |
|---|---|---|
| `text` | `text.message` | — |
| `hsm` | `hsm.message` | `{"tipo":"hsm"}` |
| `image`·`audio`·`document`·`video` | `caption`, quando houver | `{"tipo":…, "url":…}` |

**`papel='agente'` significa LADO MIND da conversa, não "IA".** O payload do Treble só traz
`sender: user|company` — não existe nele metadado que distinga humano, bot ou IA, e não se
inventa autoria. O coletor devolve isso explicitamente em
`meta.autoria_individual_treble_disponivel: false`.

**Idempotência:** nenhuma mensagem do Treble tem `id` no payload, então a chave é a posição no
array — `client_msg_id = 'treble-close:<ordinal>'`. Vale porque cada `session_external_id` tem no
máximo um `session.close`. A verificação de "já capturada ao vivo" ignora linhas `treble-close:*`,
para que duas mensagens do mesmo payload nunca se suprimam.

Texto casa por conteúdo; **mídia casa por arquivo**. Um item de áudio do close não tem texto, então
a comparação por conteúdo nunca o alcança — a chave dele é igualdade exata de `blocos.url`, que não
tem querystring, não expira e é única por arquivo.

### `public.mind_engagement_fatos(p_pessoa_id uuid) → jsonb`  *(Passo 6)*

Responde: **"o que sabemos, pelo histórico real de interação, que esta pessoa falou, recebeu e
viveu nos canais do Mind?"**

```
pessoas.pessoas.id → engagement.conversas.participante_id → engagement.mensagens
```

Factual e determinístico. **Não usa LLM, não escreve, não lê CRM/HubSpot, nem
`intelligence.analise_conversa`, `participante_memoria` ou Silence.** O coletor não conhece
payload de canal — quem normaliza é o adapter.

```jsonc
{
  "ok": true, "pessoa_id": "…",
  "resumo": { "conversas_total", "mensagens_total", "canais": [],
              "primeira_interacao_em", "ultima_interacao_em" },
  "conversas": [ { "conversa_id", "canal", "agente", "origem_codigo", "produto_codigo",
                   "iniciada_em", "ultima_atividade", "encerrada_em",
                   "mensagens": [ { "mensagem_id", "papel", "conteudo", "blocos",
                                    "origem", "criado_em" } ] } ],
  "meta": { "autoria_individual_treble_disponivel": false }
}
```

Conversas e mensagens em ordem cronológica, sem paginação — o volume por pessoa é pequeno.
`origem_codigo` e `produto_codigo` entram porque explicam em que contexto a conversa nasceu.

Fora do contrato de propósito: `variables`, telefone, e-mail, `session_external_id`, payload cru
e qualquer coisa de `intelligence.*`. Análise pós-turno e memória são o **Passo 15**;
continuidade/Silence é o **Passo 16**.

### Passo 6B — normalização de áudio  ✅ *fechado*

**Um áudio é uma mensagem, não um anexo à parte.** Uma pessoa mandou um áudio: existe UMA linha em
`engagement.mensagens`, com `conteudo` = a transcrição e `blocos` = `{"tipo":"audio","url":…}`.
Não há tabela de áudio, canal paralelo, nem uma segunda mensagem para representar o arquivo.

**A Treble é a fonte do transcript.** Ela transcreve o áudio antes de chamar o nosso inbound e
entrega o texto na chave `mensagem`, com o arquivo em `mensagem_file_url`. O `treble-inbound-agent`
lê os dois e monta uma única `p_mensagem`; o resto do caminho — `treble_agent_start` →
`mind_inbound` → `mind_mensagem_registrar` — já aceitava `conteudo` + `blocos` e não mudou. No
histórico, o mesmo texto está em `message.text` do `GET /devapi/session/{id}/history`, recuperável
de forma determinística por `session_external_id` + igualdade exata de `file_url`.

**O transcript pode não existir.** Quando falta, nada é inventado:

```
áudio chega
  → tem transcript?  sim → conteudo = transcrição, blocos = {tipo, url}  → o Agent responde
                     não → conteudo = NULL,        blocos = {tipo, url}  → o Agent NÃO é chamado
```

Três regras sustentam isso:

- **O arquivo é sempre preservado**, com texto ou sem. `blocos.url` é a prova de que a fala
  existiu, e é por ela que a transcrição pode ser recuperada depois.
- **Ausência de transcript nunca vira conteúdo.** Uma URL não é fala de ninguém, e o texto de um
  turno anterior não é a mensagem atual — o fallback que varria `user_session_keys` está fechado
  para os dois casos. Sem texto confiável o turno para ali: a IA não é chamada fingindo ter
  entendido, e nenhuma resposta é devolvida ao fluxo.
- **O `session.close` não duplica.** O item de áudio do close não tem texto, então o de-dup por
  conteúdo nunca o alcançava. Para mídia a identidade é o próprio arquivo: igualdade exata de
  `blocos.url`, sem janela de tempo.

**Limitação conhecida, ainda aberta: o áudio que abre a sessão.** Nos casos observados, o áudio
que abriu a sessão não teve transcript e não chegou ao inbound antes do `session.close`. Esse
cenário permanece como **limitação conhecida do adapter Treble**; ainda não há evidência suficiente
para tratá-lo como regra geral da plataforma. Esses áudios ficam com `conteudo` nulo e o arquivo
preservado — a conversa registra que a pessoa falou, sem inventar o que ela disse. Whisper não foi
implementado, e nenhuma arquitetura nova se abre aqui sem evidência de que ela é necessária.

`mind_engagement_fatos` não mudou de contrato: já devolvia `conteudo` + `blocos`.

---

## 9. AGENT_CONTEXT universal  ✅ *fechado (Passo 8)*

`public.mind_agent_context(p_conversa_id uuid) → jsonb`

**A conversa é a única âncora.** Não existe parâmetro de pessoa: ela vem de
`engagement.conversas.participante_id`. Isso torna impossível, por construção, montar um contexto
com a pessoa A e a conversa B.

```
conversa_id → conversas.participante_id → pessoa_id
            → mind_pessoa_fatos · mind_crm_fatos · mind_crm_comercial
            → mind_credenciamento_fatos · mind_engagement_fatos
```

**Compõe, não reimplementa.** Cada coletor é chamado uma vez e entra **integral**, na linguagem
dele. Esta função não reinterpreta nenhum deles, e nenhum precisou mudar para o Passo 8 existir.

| chave | vem de |
|---|---|
| `person` | `mind_pessoa_fatos` |
| `crm` | `mind_crm_fatos` |
| `commercial` | `mind_crm_comercial` |
| `credenciamento` | `mind_credenciamento_fatos` |
| `entry` | `engagement.conversas` + `engagement.origens` |
| `conversation` | a conversa atual, tirada de `mind_engagement_fatos.conversas` |
| `engagement` | `resumo` + `conversas_anteriores` + `meta` do mesmo coletor |

**`conversation` é a conversa atual; `engagement` é a pessoa inteira.** As duas coexistem porque
o histórico é pessoa-wide (§8): as conversas anteriores vêm **completas, com suas mensagens** —
não reduzidas a contadores. Engagement factual não é Memory.

**`credenciamento` é Intelligence da pessoa, não Kit de produto.** O coletor recebe somente o
`pessoa_id` já resolvido. Para o participante, devolve os dados presentes no credenciamento
oficial — nome, e-mail e WhatsApp quando inequívocos — mais categoria(s) ativa(s) e quantidade.
Dados do comprador permanecem armazenados no espelho, mas nunca entram no contexto do modelo,
não são tratados como dados do participante e não ganharam endpoint de consulta. Se houver
categorias diferentes, `categoria_unica` fica nula e todas são preservadas. O mesmo bloco chega
ao WhatsApp por `mind_conversa_estado` e ao App por `mindagent_chat_get_context`.

E-mail e WhatsApp declarados na conversa são validados pelo formato canônico antes de qualquer
gravação. Validação de formato não significa propriedade ou entregabilidade. O WhatsApp
declarado é salvo como evidência não verificada, com confiança média; o número do próprio canal
continua sendo a evidência forte. Conflito nunca troca a pessoa ancorada na conversa.

### `entry` — só o fato da entrada atual

`canal` · `origem_codigo` · `origem` (apenas `site`, `botao_rotulo`, `descricao`) ·
`produto_codigo` · `entry_action`.

`entry_action` é a CTA que a pessoa clicou, extraída de `conversas.variables` — que existe em duas
formas: **array** de `{key,value}` quando vem do `session.close`, e **objeto** quando o agente
escreve. As duas são normalizadas, com prioridade `hubspot_opcao_selecionada_treble` →
`opcao_selecionada`. **`variables` nunca sai cru.**

**Fora do contrato, de propósito:**

- `audience`, `stage`, `intent`, `ticket_interest`, `objection`, `needs_human`, `checkout_sent`,
  `desfecho` — moram em `conversas` e parecem entrada, mas são **escritos pelo agente**
  (`mind_turno_registrar`). São estado/resultado, não fato.
- `session_external_id`, `telefone`, `nome_contato`, `dispositivo_id`, `utm`, `utm_token` —
  transporte de canal, PII já coberta por `person`, ou coluna sem dado.
- **evento, ofertas, agenda, FAQ, políticas, regras comerciais** — conhecimento de **um produto**.
  Pertence ao **Kit da rota**, carregado depois do Router. `treble_agent_context` e
  `treble_agent_context_base` são exatamente isso, apesar do nome: nenhuma das duas contém um
  único fato sobre a pessoa, a entrada ou a conversa.
- `memory` — Passo 15. A chave **não aparece** enquanto não existir.

**Não é Decisioning. Não se usa LLM para construí-lo.**

Erros, sem exception: `sem_conversa` · `conversa_nao_encontrada` · `conversa_sem_pessoa`.

### Contrato coberto por teste  *(Passo 9)*

**`tests/mind_agent_context_contract.sql`** — arquivo reexecutável, autocontido, que roda inteiro
dentro de uma transação e termina em `ROLLBACK`. Não cria extensão, schema, tabela, função
permanente, migration nem CI; não deixa fixture; não altera nada. Roda com
`psql "$DATABASE_URL" -f tests/mind_agent_context_contract.sql` e aborta com uma exception que
nomeia o contrato quebrado.

Ele testa o contrato **observável** — nunca reimplementa a função para comparar duas cópias da
mesma lógica. Quando precisa de referência, compara com `engagement.conversas` e com os quatro
coletores. O que fica travado:

- **âncora da conversa** — `pessoa_id` é sempre o `participante_id` da conversa pedida;
- **passthrough dos coletores** — `person`, `crm` e `commercial` idênticos, JSON a JSON;
- **`entry`** — conjunto exato de chaves, `origem` reduzida a `site`/`botao_rotulo`/`descricao`, e
  a `entry_action` nos dois formatos de `variables` com a precedência fechada;
- **partição atual × histórico** — `conversation` + `conversas_anteriores` reproduzem exatamente
  as conversas do coletor, sem perda, sem duplicata e na mesma ordem; as somas fecham com o
  `resumo`;
- **ausência de Decisioning, Kit e Memory** — verificada pela estrutura do JSON, nunca por busca
  textual, para que uma palavra escrita por uma pessoa numa mensagem não vire falso positivo;
- **determinismo** e os **três contratos de erro**;
- **propriedades da função** — `STABLE`, `SECURITY DEFINER`, `search_path` explícito e `EXECUTE`
  fechado para `public`/`anon`/`authenticated`.

---

## 10. Router universal  ✅ *fechado (Passo 10)*

**O Router responde a uma pergunta só: qual competência assume a necessidade atual.**
Não é classificador de assunto, não é detector de produto, não é filtro de canal. Ele nomeia a
rota — e quem executa a rota é outro componente.

### As seis rotas

| rota | competência |
|---|---|
| `summit_b2c` | comprar ingresso para si — decisão individual |
| `summit_b2b` | levar time, grupo ou delegação — decisão de empresa |
| `institute` | formação/curso do Mind Institute |
| `dash` | produto Dash — assinatura, acesso, uso |
| `cliente_suporte` | resolver um problema operacional |
| `concierge_summit` | viver o Summit — agenda, local, logística, conteúdo |

**`cliente_suporte` é problema operacional, transversal ao produto.** Erro de pagamento,
reembolso, acesso, ingresso que não chegou, troca de titularidade, problema técnico, reclamação,
exceção fora da política. Prevalece sobre a venda: quem tem um problema operacional é atendimento,
qualquer que seja o produto envolvido. **Compra prévia não é requisito** — quem nunca comprou pode
ter um erro de pagamento tentando comprar, e isso é suporte do mesmo jeito.

**`concierge_summit` é a experiência de participação no Summit.** Programação, horários, agenda,
localização, onde ir, workshops e masterclasses, conteúdo, orientação durante o evento. **Ter
comprado, sozinho, não determina a rota** — quem comprou pode estar pedindo suporte, comprando de
novo ou perguntando de outro produto; o que manda é a necessidade atual.

**`ja_comprou` e `desconhecido` não são rotas.** Já ter comprado é um fato sobre a pessoa, não uma
competência — quem já comprou pode estar comprando de novo (`summit_b2b`), pedindo suporte
(`cliente_suporte`) ou perguntando da programação (`concierge_summit`). E não saber ainda qual é a
necessidade não é uma competência: é a ausência de decisão, que o contrato representa como
`rota = null` + `precisa_esclarecer = true` **com pelo menos uma candidata**.

### A necessidade atual decide; o histórico informa

`origem_codigo`, `produto_codigo` e `entry_action` são **evidência**, não autoridade. Uma pessoa
que entrou por uma campanha de delegações e escreveu "meu ingresso não chegou" é
`cliente_suporte`, não `summit_b2b` — a campanha explica de onde ela veio, não o que ela precisa
agora. O mesmo vale para o CRM: cargo de diretoria e empresa grande no espelho não transformam
"quero comprar meu ingresso" em B2B.

### Quando o Router roda

**Só quando a rota ainda não está determinada.** Se o contexto de entrada já fecha a rota, não há
o que decidir e a chamada é desperdício. **Identidade e contexto vêm antes do Router, sempre** — o
Router não resolve pessoa, não monta contexto e não lê o banco por conta própria: ele consome o
`AGENT_CONTEXT` do Passo 8 e mais nada.

No Treble comercial existe um pré-roteamento determinístico e estreito em
`_shared/treble-commercial-route.ts`, publicado em 04/09 para não pagar a latência do Router em
todo turno. Ele só fecha `summit_b2c` ou `summit_b2b`: B2C é o padrão e B2B de ingressos exige
destino empresa/equipe mais pluralidade. Suporte, outra solução e empresa sem quantidade continuam
no Router. Patrocínio segue B2B como demanda própria. O código e o prompt do Router compartilham o
mesmo contrato e são cobertos pelos mesmos casos de regressão.

### `router` — Edge Function

`POST /router?token=<intelligence.config.analise_token>` com `{ "conversa_id": "<uuid>" }`.
Mesmo padrão de auth e de config do `analisar-conversa`: token em `intelligence.config`, prompt em
`agentes.prompts`, OpenAI Responses API com `json_schema` strict e `store:false`.

```jsonc
{ "ok": true, "conversa_id": "…",
  "rota": "summit_b2b" | null,
  "precisa_esclarecer": false,
  "candidatas": [] }
```

Invariantes garantidas no servidor e não confiadas ao modelo:

- `rota` ∈ **exatamente** as seis rotas, ou `null`. O `enum` do schema fecha a taxonomia.
- `precisa_esclarecer` é `rota is null` — não é um campo independente que possa contradizer a rota.
- rota escolhida ⇒ `candidatas = []`. Candidatas só existem quando não houve decisão.
- **`rota = null` com `precisa_esclarecer = true` exige pelo menos uma candidata canônica.**
- `ok` e `conversa_id` são preenchidos pela Edge, não pelo modelo: o id já é conhecido com
  certeza, e pedir para o modelo repetir um uuid só cria espaço para ele errar.

**Contrato de clarify.** Pedir esclarecimento sem dizer entre o que é uma saída vazia disfarçada de
decisão — quem consome não teria o que perguntar. Se, depois da sanitização, `rota = null` e
`candidatas = []`, a saída do modelo está inválida e a Edge devolve `saida_invalida`.

**O servidor não inventa candidata.** Escolher quais rotas continuam plausíveis é competência do
prompt; a Edge forjar essa lista seria roteamento escondido no encanamento. Por isso a saída é
rejeitada em vez de completada. A regra também está escrita no prompt, explicitamente.

**Sem fala do lead, não chama IA** — e essa é a **única** saída legítima com `rota=null` e
`candidatas=[]`. Conversa sem nenhuma mensagem `papel='lead'` devolve `rota=null`,
`precisa_esclarecer=false`, `candidatas=[]`: não há necessidade atual para rotear, e isso não é
ambiguidade. A entrada do modelo é a **última fala do lead** como necessidade atual, mais o
`AGENT_CONTEXT` inteiro como evidência.

Os três contratos de erro do `mind_agent_context` são espelhados tal como são —
`sem_conversa` · `conversa_nao_encontrada` · `conversa_sem_pessoa` — em HTTP 200 com `ok:false`.

O prompt vive em `agentes.prompts['router_universal']` (ativo, v4). Fora do atalho comercial
estreito do Treble descrito acima, a Edge é encanamento e a competência continua sendo do prompt.

### Integração ao runtime

O Router está integrado ao `treble-inbound-agent`. O atalho comercial tenta fechar primeiro os
casos B2C/B2B seguros; quando devolve `rota=null`, o runtime chama o Router. A rota decidida e sua
origem são persistidas nos blocos da mensagem do agente por `mind_turno_registrar`, incluindo
`rota`, `rota_aplicada`, `rota_origem`, `precisa_esclarecer` e `candidatas`.

**Capability não altera rota.** Se a competência certa é `dash`, a rota é `dash` mesmo que ainda
não exista nada capaz de atender — o que se faz com uma rota sem capacidade é o **capability gate
do Passo 11**. Handoff é o **Passo 14**.

### Busca no Product Intelligence — estratégia canônica

O retrieval estruturado do Summit é `public.mindagent_chat_search`, consumido pelo chat web e pelo
bloco de agenda do WhatsApp.

**A pergunta vira uma disjunção dos seus lexemas, e o resultado é ordenado por relevância.**
`plainto_tsquery` conjugava os termos: "diferença VIP Prime" não casava com documento nenhum,
embora "diferença VIP" casasse. Trocar por `websearch_to_tsquery` não resolveria — para essas
consultas ele produz exatamente a mesma conjunção. A consulta canônica é
`to_tsvector(pergunta)` com os lexemas unidos por `|`, e o ranking é `ts_rank_cd`.

**Corte de relevância: `0.1 × least(2, nº de lexemas da pergunta)`, calibrado empiricamente.**
`ts_rank_cd` pontua por **frequência de ocorrências**, e **não garante cobertura de lexemas
distintos**: um registro pode alcançar o corte repetindo o mesmo termo. O piso foi ajustado contra
as perguntas reais para cortar acertos fracos — derruba a sessão que casava apenas por "existir"
numa pergunta sem sentido, e preserva "Maslach" perguntado sozinho. É um filtro de relevância, não
uma garantia de cobertura.

**Falsos positivos pontuais continuam possíveis, e isso é conhecido.** Em "precisa de reserva", o
documento "Prime Lounge" entra no bloco `mind` porque "reservado" aparece duas vezes no corpo —
duas ocorrências do mesmo lexema, não dois termos da pergunta. Não foi eliminado nesta mudança.

**Ofertas usam corte 0,1.** São três linhas públicas de texto curto, onde um piso mais alto
excluiria acertos legítimos. Nomear o produto — "VIP", "Prime", "Mind" — é o sinal. Elas deixaram de depender de uma regex de palavras-gatilho, que devolvia vazio
para "quanto custa o VIP" porque "custa" não estava na lista.

**Palestrante casa por identidade, não por prosa** — nome, cargo e instituição. O bio é texto longo
e, com disjunção, acumulava acerto em termos genéricos; continua saindo no campo `bio`, apenas não
é superfície de busca.

**Um alias estrutural, factual.** `precisa_reserva` é boolean e nenhuma das 33 sessões que exigem
reserva diz "reserva" em texto — nenhum ranking as encontraria. O atributo entra no texto indexado
escrito por extenso, só quando verdadeiro. Duas palavras derivadas do dado, sem sinônimo inventado.

Os gatilhos de **categoria** continuam ("me mostra a programação", "quem são os palestrantes"):
essas perguntas não compartilham lexema com nenhum registro, e ranking nenhum as substitui. Agora
convivem com a busca ranqueada em vez de serem o único caminho.

**O que isso passou a resolver:** diferença entre tiers · preço de um tier nomeado sem palavra-chave
de preço · sessões que exigem reserva · e, mantidos, FAQ de tradução e estacionamento, localização e
palestrante por nome. Das 16 perguntas reais da auditoria, 11 encontram algo — eram 6.

Em "precisa de reserva" a precisão é **100% no bloco `sessions`** — 8 de 8 exigem reserva de fato.
No resultado inteiro não é: o bloco `mind` traz um documento a mais, pelo motivo acima.

**`commercial_rules` continua fora deste caminho.** "Desconto para 10 pessoas" segue sem resposta
aqui, deliberadamente: trazer essa fonte mudaria o contrato que o `treble-inbound-agent` filtra em
`agendaSegura`, e compor Product Intelligence é o **Passo 12B**.

**RAG continua desnecessário para esses casos.** Nenhuma das perguntas exigiu vetor; todas são
lookup estruturado. `knowledge_chunks` segue vazio por não haver produtor, e isso não bloqueia nada
aqui.

O **Passo 12A segue aberto** — esta foi a primeira de várias mudanças.

### Integridade do dado de produto — estado após o hotfix

Os schemas `summit` e `comum` foram renomeados e não existem mais, mas um conjunto de funções
continuou apontando para eles. Quatro delas estavam no caminho vivo e o efeito chegava ao cliente.
Corrigidas — troca de schema, sem redesenho:

| função | efeito que causava | estado |
|---|---|---|
| `mindagent_sync_offers` | cron de preço falhando a cada 30 min | ✅ sincroniza |
| `mind_precos_por_volume` | bloco `precos_por_volume` indisponível | ✅ calcula |
| `mindagent_chat_search` | chat web sem dados oficiais; agenda vazia no WhatsApp | ✅ responde |
| `api.treble_find_location` | busca de local morta | ✅ responde |

**Preço.** A fonte canônica de preço, lote e desconto por volume é o projeto
**`mind-summit-propostas`**; `summit_2026.offers` e `commercial_rules` são espelho, alimentado
pelo `mindagent-sync-precos`. Com o sync parado, o agente cotou um lote encerrado. Após o hotfix,
as 18 linhas de lote conferem com a fonte — preço, datas e o par `ativo`/`publico` —, só o lote
vigente está ativo, e nenhuma oferta de grupo está pública.

**Palestrantes — cobertura ainda limitada.** `summit_2026.session_speakers` tem duas colunas de
palestrante: `palestrante_id` (uuid, apontando para a tabela removida) e `speaker_id` (bigint,
canônico, para `ecossistema.palestrantes_especialistas`). Dos 61 vínculos, **9 têm o
`speaker_id`** e são os únicos que o retrieval enxerga. Dos 52 restantes, **16 são
deterministicamente resolvíveis** — título casando com a fonte da programação e nome batendo exato
com o palestrante canônico. Os demais esbarram num mirror incompleto: `palestrantes_especialistas`
tem 31 dos 54 palestrantes da fonte. Completar o mirror vem antes de reparar o vínculo, e nem um
nem outro se faz por semelhança de nome. Ambos são do **Passo 12A**.

**`summit_b2b` continua `missing_kit`.** `mind_precos_por_volume` voltou a funcionar, mas o loader
vivo ainda não entrega esse bloco aos `DADOS_OFICIAIS` — e kit, para o Capability Gate, é
capacidade acessível ao runtime. Ligar os dois é o **Passo 12B**.

### Blocker conhecido para a integração

A confiabilidade do transporte da Treble (§8, Passo 6B) continua aberta. **O que se sabe são dois
turnos observados:** um de ~4,43 s chegou ao WhatsApp, um de ~5,96 s não foi emitido. Isso
demonstra um problema real de confiabilidade/latência, mas **não prova limiar universal** — não há
threshold medido, e duas observações não fundamentam um. Somar uma chamada de Router a um caminho
cuja confiabilidade ainda não foi entendida misturaria dois problemas. Registrado aqui como
restrição para o Passo 11 — não se resolve neste passo, e o Passo 10 não a agrava justamente por
não estar no caminho do turno.

### Testes

14 testes contra a Edge ao vivo, com fixtures isoladas criadas e removidas (resíduo verificado em
zero). Cobrem as seis rotas; a prevalência de `cliente_suporte` sobre a origem da campanha e sobre
"já comprou"; `origem_codigo`/`entry_action` como evidência e não autoridade; CRM de empresa
grande que **não** transforma compra individual em B2B; ambiguidade real (`rota=null`,
`precisa_esclarecer=true`, candidatas não vazia); conversa sem fala do lead; e uma varredura final
das respostas confirmando taxonomia fechada, invariantes e formato exato do contrato — nenhuma rota
fora da taxonomia, nenhuma invariante quebrada, nenhuma resposta fora do formato.

O **contrato de clarify** tem os três casos que o delimitam cobertos: ambiguidade real com
candidatas não vazia · rota decidida com `candidatas=[]` · conversa sem fala do lead com
`rota=null`, `precisa_esclarecer=false` e `candidatas=[]`.

---

## 10B. Capability Gate  ✅ *fechado (Passo 11)*

**O Router decide a rota correta. O Capability Gate decide se o runtime atual consegue
executá-la.** São perguntas diferentes, e a resposta de uma não altera a outra: uma rota certa
continua certa mesmo quando não existe nada capaz de atendê-la.

```
public.mind_rota_capacidade(p_rota text, p_canal text) → jsonb
```

Determinística. `STABLE`, `SECURITY DEFINER`, `search_path` explícito, `EXECUTE` só para
`postgres` e `service_role`. Sem LLM, sem escrita, sem Edge Function. **Não decide rota** — recebe
a rota já decidida.

```jsonc
{ "ok": true, "rota": "…", "canal": "…",
  "pode_executar": true,
  "needs_human": false,
  "reason": null }
```

Rota fora das seis canônicas devolve `{"ok": false, "motivo": "rota_invalida"}`; canal fora dos
dois vivos, `{"ok": false, "motivo": "canal_invalido"}`. Não há alias: `web` não é canal.

### Registry sem tabela nova

O mapa rota → playbook é a **convenção de nome** `playbook_<rota>` em `agentes.prompts`, e a
coluna `ativo` já é o interruptor. Não se criou tabela de registry porque a convenção já faz o
papel — e **a ausência da linha significa exatamente `missing_playbook`**. Por isso também não
existem playbooks vazios: um placeholder inativo não acrescenta informação nenhuma ao que o vazio
já diz. Quando o conteúdo existir, a linha nasce.

Um playbook só conta como disponível quando **existe, está ativo e tem conteúdo**. Um playbook
vazio não ensina nada.

### Estado atual

> **Atualizado em 01/09/2026.** A matriz abaixo é conferível a qualquer momento com
> `select cc.canal, cc.rota, public.mind_rota_capacidade(cc.rota, cc.canal) from agentes.canal_competencia cc;`
> — a política de canal saiu do `CASE` e virou tabela, e o Kit saiu do corpo da função e virou
> `agentes.kit_blocos`. O que segue é o retrato de 01/09, não a fonte da verdade.

| rota | playbook | kit | `whatsapp` | `mindagent-web` |
|---|---|---|---|---|
| `summit_b2c` | ✅ `playbook_summit_b2c` | ✅ | ✅ | — (política) |
| `summit_b2b` | ✅ `playbook_summit_b2b` | ✅ | ✅ | — (política) |
| `cliente_suporte` | ✅ `playbook_cliente_suporte` | ✅ | ✅ | ✅ |
| `concierge_summit` | ✅ `playbook_concierge_summit` | ✅ | — (política) | ✅ |
| `institute` | ❌ | ❌ | — | — |
| `dash` | ❌ | ❌ | — | — |

`— (política)` distingue o que este runtime **saberia** executar do que o canal **permite**: a rota
tem playbook e kit, mas `agentes.canal_competencia` não a habilita ali, e o Gate responde
`canal_incompativel`. É diferente de `missing_playbook`/`missing_kit`, que são falta de capacidade.

**Kit é capacidade acessível ao runtime atual — não existência do dado na base.** Um fato que o
loader vivo não entrega não está no kit: ele é Intelligence que existe, e nada além disso. O Gate
responde *"o runtime atual consegue executar esta rota autonomamente?"*, nunca *"existe em algum
lugar do banco informação suficiente para um dia executá-la?"*.

**Estado transitório.** Hoje não existe Kit Loader: o que cada canal carrega está fixo dentro do
próprio executor. `treble_agent_context` ignora os cinco parâmetros que recebe e devolve sempre
evento + ofertas do `summit_2026`; o `mindagent-chat` traz o próprio prompt como constante no
código. Por isso a matriz de kit está escrita **no corpo da função**, e o **Passo 12B — Kit Loader
universal** a substitui pelo loader canônico. Não se criou tabela para atravessar esse intervalo.

O que sustenta cada célula:

- `summit_b2c` — ofertas ativas e públicas com preço, condições e checkout em `summit_2026.offers`,
  entregues pelo `treble_agent_context` — que é exatamente o que o playbook precisa.
- `concierge_summit` — `sessions`, `locations`, `speakers`, `exhibitors` e `event_rules` do
  `summit_2026`, pelos blocos `evento` + `programacao`. É o kit mais rico de todos. **O playbook
  chegou** (`playbook_concierge_summit`), e desde 01/09 a rota também expõe `tools`:
  `buscar_intelligence` e `ler_intelligence`, declaradas em `kit_blocos` (`secao='tools'`) e
  descritas em `concierge.ferramentas`.
- `summit_b2b` — **não tem.** Os fatos comerciais B2B existem em `summit_2026`:
  `commercial_rules.desconto_por_volume` está ativo, com tiers. Mas o `treble-inbound-agent` monta
  `DADOS_OFICIAIS` a partir do `treble_agent_context`, e essa função **não entrega
  `commercial_rules` nem `precos_por_volume`** — enquanto o `playbook_summit_b2b` ativo depende
  explicitamente do bloco `precos_por_volume` dentro de `DADOS_OFICIAIS`. O dado existe; o kit não
  chega ao agente. Corrigir isso é o Passo 12B, não este.
- `cliente_suporte` — **passou a ter em 01/09**: `evento` + `programacao` + `inclusoes`, os mesmos
  providers já vivos nas outras rotas. Não é base de política de suporte nem consulta de pedido —
  continua não havendo nenhuma das duas, e o destino `suporte.chamado` continua apontando para um
  schema que não existe. É o mínimo para responder o que o playbook manda responder com dado
  oficial; o resto ele escala, pela regra de handoff do playbook `base`.

**Produto vendável não é Kit.** `catalogo.produtos.ativo` e `vende` dizem se há algo a vender, não
se a rota tem com que trabalhar. São conceitos distintos e o gate não os confunde — o catálogo
segue consultável quando for factual e relevante, mas não define `missing_kit` sozinho.

**Canal.** A matriz responde *"este runtime executa esta rota autonomamente?"* — nunca *"este canal
alcança um humano"*, que é pergunta do Passo 14. `whatsapp` é o `treble-inbound-agent`, que compõe
playbook por `treble_agent_prompt` e cuja pilha inteira é venda; `mindagent-web` é o
`mindagent-chat` que, **desde 01/09, não é mais concierge por construção**: ele declara o canal e
o Router escolhe entre as competências que a política habilita ali. Desde 03/09, o universo do
App é `concierge_summit` + `cliente_suporte` + `summit_b2c`: a entrada continua sendo Concierge,
e `summit_b2c` só assume após intenção explícita de compra ou upgrade. O executor não inventa nem
confirma compra; ele pode emitir um checkout oficial validado pelo runtime. Dois canais canônicos vivos, e a
matriz fica legível dentro da função. Se aparecer um terceiro canal real, ou a necessidade concreta
de editar capability sem deploy, revisitamos — não se antecipa isso.

### Checkout atribuído ao Agent — vivo em 03/09

Os dois runtimes validam a escolha contra os campos `checkout_url` do Kit. Link externo, checkout
Eduzz que não estava no Kit ou cupom diferente são recusados. No envio real, a URL recebe:

- `utm_source=whatsapp|app`, `utm_medium=ai_agent`, campanha e `utm_id` padronizados;
- `utm_content=<motivo>__ae_<token>` e o mesmo token em `utm_term`;
- `agent_id` e um `conversation_id` opaco, sem expor o UUID interno da conversa ou PII.

O token é o id idempotente de `engagement.agente_eventos` (`tipo=checkout_link_enviado`). A view
`intelligence.v_conversoes_agente`, com `security_invoker=true`, liga esse evento a `eduzz.vendas`
quando o espelho traz o token e expõe pedido, status, valor, quantidade, ingresso, canal, Agent,
rota, motivo e conversa — sem nome, e-mail, telefone, documento ou endereço. A integração atual
já preserva `utm_content`; `utm_term` fica como redundância para a evolução do conector.

No WhatsApp, o checkout oficial é resolvido antes da decisão final do guardrail de preço. Se o
modelo escolher um `checkout_url` válido do Kit, mas escrever na mesma copy um valor rejeitado,
o runtime remove a resposta livre inteira e entrega somente uma frase neutra sem preço com o
checkout rastreado. Isso preserva a conversão sem permitir que o valor incorreto chegue ao lead.
Quando não existe checkout oficial validado, o guardrail continua bloqueando e acionando handoff.
Comportamento vivo no `treble-inbound-agent` version 35 / v1.6.2.

Institute e pré-venda do Summit seguinte não foram inventados nesta entrega. O encanamento aceita
novas ofertas automaticamente quando cada checkout e regra comercial oficial forem adicionados
ao Kit correto.

### `pode_executar`, `needs_human` e os reasons

`pode_executar` é `reason is null`. Nada além disso.

**`needs_human` é necessidade, não mecanismo.** Significa *"esta necessidade não pode ser concluída
autonomamente e requer intervenção humana"*. **Não** significa *"existe humano disponível para
transferência ao vivo neste canal"* — e por isso vale também em `mindagent-web`, onde não há
ninguém do outro lado. Como essa intervenção acontece — transferência no WhatsApp, e-mail e
dispatch no Dash, outro mecanismo no app — é o **Passo 14**.

Três reasons canônicos, com **precedência fechada**:

```
missing_playbook  >  missing_kit  >  canal_incompativel
```

Um único `reason`, nunca uma lista. A ordem vai do que falta mais fundo para o que falta mais na
ponta — e o primeiro é o único que uma pessoa destrava escrevendo um texto.

### Pré-roteamento determinístico — ainda não

A regra arquitetural continua valendo: **se a aplicação já souber a rota, pula o Router e chama o
Capability Gate; se não souber, Router e depois o Gate.** O que não existe é o pré-roteamento por
entrada — e não existe porque **hoje não há sinal autoritativo no runtime vivo que o justifique**:
`origem_codigo` está presente em **zero** conversas do agente vivo (as 58 conversas com origem são
todas do fluxo legado `treble`), e `audiencia_sugerida` é sugestão, com taxonomia que não é a das
rotas — nada no sistema roteia por ela. Origem e `entry_action` são histórico e evidência, não
autoridade sobre a necessidade atual. Quando surgir uma entrada realmente autoritativa, o
short-circuit entra na orquestração — e nunca pulando o Gate.

---

## 11. Roadmap vigente

| # | passo | estado |
|---|---|---|
| 1 | Ingestão + persistência + identidade universal | ✅ **fechado** |
| 2 | Ponte Pessoa Mind ↔ CRM/HubSpot | ✅ **fechado** |
| 3 | Fila universal de resolução identidade/CRM | ✅ **fechado** |
| 4 | Coletor factual CRM | ✅ **fechado** |
| 5 | Compras + contexto comercial | ✅ **5A fechado** |
| 6 | Coletor factual de Engagement | ✅ **fechado** |
| 6B | **Normalização de áudio** | ✅ **fechado** |
| 7 | **Normalização determinística da pessoa** | ✅ **fechado** |
| 8 | **AGENT_CONTEXT universal** | ✅ **fechado** |
| 9 | **Testes de contrato do AGENT_CONTEXT** | ✅ **fechado** |
| 10 | **Router universal** | ✅ **fechado** |
| 11 | **Registry de rotas + capability gate** | ✅ **fechado** |
| 12A | **Auditoria e reforma de Product Intelligence / Knowledge** | ⏭️ **PRÓXIMO** |
| 12B | Kit Loader universal | |
| 13 | Finalizar cérebro de vendas Summit | |
| 14 | Contrato universal de ação + handoff/escalation | |
| 15 | Análise pós-turno + memória universal | |
| 15B | **Write-back + dispatch operacional pós-turno** | |
| 16 | Continuidade / Silence | |
| 17 | E2E vendas Summit via Treble | |
| 18 | Hardening, documentação e travas Core Universal | |

### 12A e 12B — o que eram um passo só

O antigo **12 — Separação Base / Router / Kit Loader** virou dois, porque construir o loader antes
de saber o que ele carrega seria encanar uma fonte que ninguém auditou.

**12A — Auditoria e reforma de Product Intelligence / Knowledge.** Usa o Summit como primeiro
sistema real e investiga: fontes autoritativas por conceito · a estrutura atual de `summit_2026` ·
conteúdo espalhado por outros schemas e funções · duplicações e legado · freshness e origem dos
dados · conhecimento estruturado versus long-tail/RAG · `knowledge_documents` e `knowledge_chunks`
— inclusive **por que `knowledge_chunks` está vazio** · estruturas duplicadas entre `summit_2026`,
eventos, Dash e Institute · funções de retrieval existentes, quebradas ou legadas · e a qualidade
real do retrieval.

Princípio fechado:

> **ESTRUTURADO AUTORITATIVO PRIMEIRO. RAG PARA LONG-TAIL.**

Preço, checkout, desconto, horário, inclusão e disponibilidade **não podem depender de vetor**.

E uma regra que o Passo 11 já tornou concreta: **não basta a informação existir — é preciso provar
que o agente a encontra quando precisa.** A auditoria do 12A usa perguntas reais para verificar se
a informação existe, se a fonte correta é recuperada, se veio informação suficiente, se algo
decisivo se perdeu e se veio ruído que atrapalha.

**12B — Kit Loader universal.** Só então:

```
ROTA + NECESSIDADE ATUAL + AGENT_CONTEXT  →  KIT DA ROTA
```

contendo, conceitualmente, **playbook + Product Intelligence relevante + Knowledge recuperado para
aquele turno + tools**. O contexto de produto é **recomposto a cada turno** a partir das fontes
atuais — nunca persistido como um bloco gigante estático dentro da conversa.

**Backlog:** 19 permissões legadas · 20 secrets hygiene · 21 exposed surface audit ·
23 front-end/inbox de pendências.

O **Passo 15B** — promovido do backlog, porque write-back não é higiene, é o que fecha o ciclo da
inteligência — cobre, no futuro:

- atualizar o **Contact**;
- atualizar **Lead existente**;
- **criar Lead** quando houver oportunidade e pipeline aplicável;
- atualizar / mover o **estado do Lead**;
- quando o produto **não tiver pipeline apropriado, não inventar pipeline**: persistir a
  inteligência e fazer **dispatch para os responsáveis do produto** — e-mail, follow-up, o que a
  operação daquele produto usar.

E centralizar tudo isso, para que cada agente não implemente a própria integração. Nada disso
agora.

Decisões de negócio ainda abertas e dívida conhecida ficam em `BACKLOG.md`.

---

## 12. Sistemas adjacentes

### `eduzz` — espelho de vendas e bilheteria

**Existe e está carregado.** 3.228 ingressos (Blinket) + 3.214 vendas + catálogo de produtos
(`eduzz.produtos`, `eduzz.produto_catalogo`, `eduzz.hubspot_stage_config`).

**Este projeto não fala com a Eduzz.** Quem fala é o Supabase `mind-summit-vendas-dashboard`,
que tem os tokens e já sincroniza sozinho; o mind-agent espelha o espelho por uma porta só de
leitura (`espelho_para_mind`, protegida por segredo no Vault de lá). A `EDUZZ_API_KEY` guardada
aqui **não abre nada** — não existe app OAuth para a conta 14449348.

`pessoa_id` nas views `eduzz.v_ingressos` / `v_vendas` é **junção**, não coluna.

**A integração completa com Intelligence ainda não foi fechada.**

### `credenciamento_summit_2026`

**Existe e está carregado:** 1.272 registros no espelho em 03/09/2026 + a fila e o espelho da
Yazo. `credenciamento_summit_2026.v_participantes` liga o registro ao `pessoa_id` canônico por
e-mail e, quando inequívoco, WhatsApp. `mind_credenciamento_fatos` é a porta interna mínima de
leitura para agentes; nunca usa nome como identidade e nunca expõe dados do comprador. A coluna
`password` da origem **não** é espelhada — o corte é feito na porta do projeto de origem.

> ~~Não existe ainda uma source-of-truth definitiva entre Eduzz, credenciamento e HubSpot além
> das decisões já tomadas acima. Não inventar uma.~~
>
> **Revogado em 21/09/2026 por D1** (§5). A regra existia porque ninguém tinha decidido quem
> manda; agora alguém decidiu. **O Mind manda no histórico consolidado do cliente**, e cada
> origem externa é autoridade apenas **sobre o fato que ela própria observa** — a Eduzz sobre
> a liquidação do pagamento, o LearnWorlds sobre o progresso no curso. Nenhuma delas manda no
> consolidado.
>
> **A presença no Summit é nossa, não da Yazo** (correção da Adriana, 21/09). O credenciamento
> acontece na nossa porta, no nosso evento, pela nossa equipe; a Yazo é a ferramenta que o
> opera, e a planilha de 2026 é o canal de entrada, não o dono do fato. **Autoridade segue o
> processo, não o fornecedor** — a régua completa está em `PROJECT_STATE.md` §8.
>
> **A proibição de inventar continua valendo em outra forma:** autoridade por fonte não se
> deduz no código que consome — ela é **declarada** em `registry.fontes` e mudá-la é decisão
> da Adriana, não do consumidor. Fonte sem classificação vira pendência; não vira palpite.

### Espelhos de outros projetos Supabase

Encanamento único: `public.espelho_estado` + `espelho_config` / `espelho_gravar` /
`espelho_estado_set`, orquestrados pela edge `eduzz-espelho-sync` (cron `:20` e `:50`).
9 fontes, 2 projetos de origem.

---

## 13. Legado conhecido — não copiar

- **`pessoas.pessoas.hubspot_id`** é projeção legada de conveniência. Diverge da identidade e
  aponta para contato inexistente em alguns casos. **Nunca é caminho de leitura.**
- ~~**`pessoa_id` em tabelas CRM** não é caminho canônico de leitura e **não deve ser propagado
  para tabelas novas**.~~ **Invertido por D5 (23/09/2026):** toda tabela que fala de pessoa
  tem `pessoa_id`, preenchido pela porta única antes da escrita (§3, "D5"). Legado é o
  `pessoa_id` gravado por fora da porta; a passada D5 o refaz.
- **`public.mind_espelho_ligar()`** ainda contém blocos legados que preenchem `pessoa_id` em
  tabelas históricas via `crm.contato_espelho.pessoa_id`. **É legado conhecido, não padrão
  arquitetural** — não replicar em tabela nova. (Foi feito uma vez para
  `crm.empenho_summit_2026` e revertido.)
- **`crm.buscar_pessoa`** não é a interface canônica do novo Core.
- **`crm.pessoa_produtos`** está vazia e **não é fonte independente** da verdade comercial.
  > **Em conflito com D1 desde 21/09/2026 — não resolvido aqui.** Esta linha foi escrita
  > quando o HubSpot era a origem: nesse mundo, uma tabela local consolidada só podia ser
  > cópia, nunca fonte. **D1 inverte a direção**, e com ela a premissa da linha.
  >
  > Os fatos, sem conclusão: a tabela tem FK para `pessoas.pessoas` e `catalogo.produtos`,
  > UNIQUE `(pessoa, produto)`, RLS ligada e **0 linhas**; `crm.contexto_comercial` **já a
  > lê**, junto com `crm.pessoa_nps`. Ou seja, o leitor do consolidado local já existe.
  >
  > **Proposta, não decisão:** é ela a casa do histórico consolidado que D1 pede. Quem
  > decide é a Adriana (**D2**), e a pergunta entra como pendência no `registry` — é o
  > primeiro caso real que a Inbox vai carregar. Até lá, **valem as duas coisas**: a tabela
  > continua não sendo lida como fonte, e ninguém cria uma tabela nova para o mesmo fim.
- **Documentação target antiga**, removida nesta faxina, não deve reaparecer como requisito.
  Entidades como `people.people`, `catalog.products` ou `commercial.orders` **não existem** e
  não são alvo.

---

## 14. Segurança conhecida

Há tabelas espelhadas de CRM e catálogo com **RLS desabilitada**, apontadas pelos advisors do
Supabase. Está conscientemente no **backlog de permissões (Passo 19)**.

Os schemas novos (`eduzz`, `credenciamento_summit_2026`) e `public.espelho_estado` já estão com
RLS ligada e revogados de `anon`/`authenticated`.

---

## 15. Consultas úteis

```sql
-- realidade comercial de uma pessoa
select public.mind_crm_comercial('<pessoa_id>');

-- perfil CRM
select public.mind_crm_fatos('<pessoa_id>');

-- fila de pendências de identidade
select * from public.mind_pendencias_listar('pendente', null, 20, 0);

-- frescor dos espelhos HubSpot
select public.mind_crm_sync_frescor();

-- espelhos vindos de outros projetos Supabase
select fonte, projeto_origem, destino, status, registros_gravados, erro, concluido_em
  from public.espelho_estado order by projeto_origem, fonte;
```

---

## Documentos vizinhos

| documento | função |
|---|---|
| `BACKLOG.md` | decisões de negócio pendentes e dívida conhecida |
| `docs/TREBLE_STATUS_24H.md` | fluxo específico da janela de 24h do Treble → HubSpot |
| `shared/CONTRATOS.md` | contratos entre o chat público, o painel admin e as Edge Functions |
| `archive/pre-architecture/` | checkpoint de 22/08: 72 migrations e 5 edge functions recuperadas da produção |
