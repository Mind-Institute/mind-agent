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
  → ROUTER (só quando a rota não veio determinada)
  → KIT DA ROTA
  → DECISIONING
  → AGENT
  → AÇÃO
  → MEMÓRIA / CONTINUIDADE
```

**O runtime completo ainda NÃO está implementado.** Hoje existem, de ponta a ponta, a
**ingestão**, a **identidade** e os **coletores factuais**. AGENT_CONTEXT, Router, Decisioning e
memória universal são arquitetura congelada, não código — ver §9, §10 e §11.

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

Algumas tabelas de CRM têm uma coluna `pessoa_id` de origem histórica. **Ela não é caminho
canônico de leitura e não deve ser propagada para tabelas novas.** Ver §13.

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
            → mind_pessoa_fatos · mind_crm_fatos · mind_crm_comercial · mind_engagement_fatos
```

**Compõe, não reimplementa.** Cada coletor é chamado uma vez e entra **integral**, na linguagem
dele. Esta função não reinterpreta nenhum deles, e nenhum precisou mudar para o Passo 8 existir.

| chave | vem de |
|---|---|
| `person` | `mind_pessoa_fatos` |
| `crm` | `mind_crm_fatos` |
| `commercial` | `mind_crm_comercial` |
| `entry` | `engagement.conversas` + `engagement.origens` |
| `conversation` | a conversa atual, tirada de `mind_engagement_fatos.conversas` |
| `engagement` | `resumo` + `conversas_anteriores` + `meta` do mesmo coletor |

**`conversation` é a conversa atual; `engagement` é a pessoa inteira.** As duas coexistem porque
o histórico é pessoa-wide (§8): as conversas anteriores vêm **completas, com suas mensagens** —
não reduzidas a contadores. Engagement factual não é Memory.

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

## 10. Router — roadmap

**Não implementado.** Taxonomia de rotas congelada:

```
summit_b2c · summit_b2b · institute · dash · cliente_suporte · concierge_summit
```

O Router **só decide quando a rota não veio determinada** pelo contexto de entrada.
**Identidade e contexto vêm antes do Router**, sempre.

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
| 10 | Router universal | ⏭️ **PRÓXIMO** |
| 11 | Registry de rotas + capability gate | |
| 12 | Separação Base / Router / Kit Loader | |
| 13 | Finalizar cérebro de vendas Summit | |
| 14 | Contrato universal de ação + handoff | |
| 15 | Análise pós-turno + memória universal | |
| 16 | Continuidade / Silence integrada ao runtime | |
| 17 | E2E vendas Summit via Treble | |
| 18 | Hardening, documentação e travas Core Universal | |

**Backlog:** 19 permissões legadas · 20 secrets hygiene · 21 exposed surface audit ·
22 write-back universal Mind Intelligence → HubSpot · 23 front-end/inbox de pendências.

O **Passo 22** inclui, no futuro: atualizar propriedades relevantes do contato, atualizar Lead
existente, criar Lead quando devido, e **centralizar o write-back** para que cada agente não
implemente a própria integração. Nada disso agora.

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

**Existe e está carregado:** 1.035 participantes + a fila e o espelho da Yazo. Fonte futura para
suporte, acesso e credenciamento. A coluna `password` da origem **não** é espelhada — o corte é
feito na porta do projeto de origem.

> Não existe ainda uma source-of-truth definitiva entre Eduzz, credenciamento e HubSpot além
> das decisões já tomadas acima. Não inventar uma.

### Espelhos de outros projetos Supabase

Encanamento único: `public.espelho_estado` + `espelho_config` / `espelho_gravar` /
`espelho_estado_set`, orquestrados pela edge `eduzz-espelho-sync` (cron `:20` e `:50`).
9 fontes, 2 projetos de origem.

---

## 13. Legado conhecido — não copiar

- **`pessoas.pessoas.hubspot_id`** é projeção legada de conveniência. Diverge da identidade e
  aponta para contato inexistente em alguns casos. **Nunca é caminho de leitura.**
- **`pessoa_id` em tabelas CRM** não é caminho canônico de leitura e **não deve ser propagado
  para tabelas novas**.
- **`public.mind_espelho_ligar()`** ainda contém blocos legados que preenchem `pessoa_id` em
  tabelas históricas via `crm.contato_espelho.pessoa_id`. **É legado conhecido, não padrão
  arquitetural** — não replicar em tabela nova. (Foi feito uma vez para
  `crm.empenho_summit_2026` e revertido.)
- **`crm.buscar_pessoa`** não é a interface canônica do novo Core.
- **`crm.pessoa_produtos`** está vazia e **não é fonte independente** da verdade comercial.
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
