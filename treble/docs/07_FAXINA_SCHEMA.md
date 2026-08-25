# Faxina do banco — executada em 22/08/2026

O banco nasceu como experimento para ver se o bot do Treble funcionava.
Funcionou — e carregava o formato do experimento: quase tudo morava num schema
`mind` que na prática só tinha o Mind Summit 2026, misturado com o que é da
empresa e com o que é de pessoa.

**Resultado:** cada produto com casa própria, o agente fisicamente incapaz de
ler o produto errado, e uma regra que se segura de cabeça — *schema = de quem
é a informação*.

Seis migrations, todas com o bot e o concierge no ar. Nenhuma Edge Function
mudou: todas chamam RPC em `public`, e as RPCs mantiveram nome e assinatura.

---

## O desenho final

```
EIXO PRODUTO
  catalogo     o indice: quais produtos existem, linha, datas, schema_dados
  mind         A EMPRESA: policies, organization_content                 (2)
  comum        o que os produtos reusam: speakers, taxonomy, materiais,
               motivos_ausencia, knowledge_* institucional               (7)
  summit       Summit, todas as edicoes; edicao = linha por event_id    (17)
  institute    formacoes e Journey            \
  dash         Mind Dash                       > nascem com knowledge_* vazio
  eventos      eventos de captacao de lead    /

EIXO PESSOA
  crm          quem e / o que comprou -- construido pela Adriana, INTOCADO (9)
  engagement   o que aconteceu: conversas, mensagens, identidades,
               dispositivos, feedback, atribuicao, pontos de entrada    (20)
  intelligence o que a gente infere: memoria, objetivos, contexto,
               sinais, recomendacoes, governanca de memoria             (10)

RUNTIME DOS AGENTES -- donos de nada
  treble       config, prompts, conversas do WhatsApp                    (6)
  concierge    config, prompts, ferramentas, filas, flags, casos de
               teste do agente                                          (16)
  platform     roteamento de LLM                                         (5)

CONTRATO E QUARENTENA
  public       as RPCs que os agentes chamam + admin                     (4)
  quarentena   mechanisms: 7 linhas, ninguem le, ninguem sabe o que e    (1)
```

`catalogo.produtos.schema_dados` aponta cada produto para a casa dele
(`summit`, `institute`, `dash`, `eventos`). Produto novo não pede redesenho:
pede uma linha no catálogo.

---

## As seis migrations

| # | O que fez |
|---|---|
| 01 | Cria os 8 schemas vazios. Não move nada. |
| 02 | **A pessoa.** `crm.pessoas` vence, `mind.people` sai. |
| 03 | **Promove o concierge**: 42 tabelas → 16. |
| 04 | **`comum` e `summit`**: 22 tabelas saem de `mind`. |
| 05 | **Conhecimento por linha de produto.** |
| 06 | Derruba o andaime de compatibilidade. |

### A receita que manteve tudo no ar

```sql
begin;
  alter table concierge.participante_memoria set schema intelligence;
  create view concierge.participante_memoria as
    select * from intelligence.participante_memoria;
commit;
```

`ALTER TABLE ... SET SCHEMA` é atualização de catálogo: instantânea, não
reescreve dado. A view nasce na mesma transação, então nenhuma sessão vê a
tabela sumida.

**A pegadinha:** `ON CONFLICT` não funciona em view auto-atualizável. Seis
funções fazem upsert. A solução foi colocar os schemas novos **antes** de
`mind`/`concierge` no `search_path`, para que o nome sem qualificar caísse na
tabela real e não na view.

No fim, o `DROP` das views de compatibilidade é o teste: se algo ainda lesse
por elas, ele falha. Falhou uma vez — `concierge.v_funil_valor` — e foi
corrigido antes de seguir.

---

## O que foi encontrado no caminho

**1. `mind.people` não custava "1 linha".** O plano dizia que apagá-la era de
graça. Na verdade **33 foreign keys** apontavam para ela, inclusive
`crm.consents`. Era o hub do grafo de pessoa. A linha migrou preservando o
mesmo `uuid`, então as 33 filhas não mudaram de dado — só de alvo.

**2. Duas funções já estavam quebradas em produção.**
- `api.my_data` lia `mind.consents`, que deixou de existir quando `consents`
  foi para o `crm`.
- `concierge.resumo_do_dia` lia `agenda_sessoes`, renomeada para
  `mind.sessions` há tempos — os índices ainda carregam o nome velho
  (`mind.agenda_sessoes_pkey`). Só apareceu porque `CREATE OR REPLACE`
  revalida o corpo.

Ambas consertadas.

**3. Existe um schema `api` com 15 funções** que não estava em nenhum
inventário anterior. É a API do concierge do site.

**4. Três tabelas estavam classificadas errado.** `avaliacoes` e
`avaliacao_execucoes` são casos de teste do agente (provedor, modelo, passou,
custo_usd) — runtime, ficam no concierge. `intencoes` é roteamento
(nome, padroes, rota, ferramenta) — também runtime.

**5. `knowledge_sources` não era órfã.** `api.knowledge` lê ela, e
`knowledge_documents.fonte_id` aponta para ela. É procedência de conteúdo, e
foi para `comum`. Só `mechanisms` sobrou sem explicação.

---

## O isolamento do conhecimento, provado

```
comum.knowledge_documents        3  (institucional: políticas, termos)
summit.knowledge_documents      17  (experiências, FAQ, ingressos)
institute.knowledge_documents    0

summit.conhecimento             20  ← a linha + o institucional
institute.conhecimento           3  ← só o institucional, NUNCA o Summit
```

Cada linha expõe `conhecimento` e `conhecimento_chunks` = a casa dela UNION
`comum`. O agente do Institute lê `institute.conhecimento` e é fisicamente
incapaz de trazer chunk do Summit. Não depende de a consulta lembrar de
filtrar.

Isso apaga 4 das 7 colunas de escopo que tinham sprawlado: `produto_codigo` e
`cluster` viram o schema, `aprovado_treble` vira grant, `event_id` continua
(edição é linha dentro de `summit`). Sobram `ativo`, `valido_de`,
`valido_ate` — que são validade, não escopo.

---

## Verificação

Rodado depois de cada passo, e tudo de novo no fim:

| Teste | Antes | Depois |
|---|---|---|
| Todas as funções recriam sem erro | 1 quebrada | **0** |
| `treble_agent_context` → ofertas / preços por volume | 3 / 12 | 3 / 12 |
| `conteudo_aprovado` / `politicas` / `regras_comerciais` | 12 / 6 / 4 | 12 / 6 / 4 |
| admin: sessões / palestrantes / espaços | 67 / 44 / 27 | 67 / 44 / 27 |
| As 7 views do concierge | OK | OK |
| `mindagent_treble_start` (escrita + leitura) | OK | OK |
| Views de compatibilidade restantes | — | **0** |

**O teste que se parece com o real** — webhook em produção, pergunta de preço
e de grupo:

> *"Para VIP individual, hoje está em R$ 2.597, com parcelamento em 12x de
> R$ 216. Para 12 pessoas da empresa, entra na condição de +10 ingressos, com
> 20% off: R$ 2.078 por ingresso, em 12x de R$ 173. Além do desconto, o VIP
> inclui os workshops práticos com certificação e ainda as gravações das
> Arenas Mind, Top Voice e Sextante por 90 dias. E faltam 5 dias para a
> virada de lote."*

`needs_human: false`, `audience: b2b` — a regra de não transferir cedo no B2B
continua de pé.

---

## O que ficou de fora, e por quê

**1. `treble.conversations` continua com 24 colunas.** O plano previa
desmontá-la em `engagement.conversas` + `intelligence.sinais`. Não dá para
fazer direto: **`engagement.conversas` já existe**, vinda do concierge. Juntar
as duas exige decidir se conversa de site e conversa de WhatsApp são a mesma
entidade com uma coluna `canal` — e isso é decisão de desenho, não migration.

**2. Os renomes não foram feitos.** `origens` → `pontos_de_entrada` e
`utm_sessoes` → `atribuicao` ficaram com o nome antigo. Vinte funções usam
esses nomes sem qualificar; o rename tem que vir junto com a reescrita delas,
e isso merece migration própria.

**3. `quarentena.mechanisms`** continua esperando alguém dizer o que ela é.
