# Contratos compartilhados — Chat e Admin

Dois produtos vivem neste repositório e dividem um backend:

| Produto | Onde | O que faz |
|---|---|---|
| **Mind Agent** | raiz (`index.html`, `app.js`, …) | chat público do participante — **lê** |
| **Painel Admin** | `admin/` | manutenção do conteúdo que o chat usa — **escreve** |

Eles não se importam. O que os liga é o backend, e é isso que este
documento fixa. Quem mexer no banco ou nas Edge Functions precisa passar
por aqui antes: **toda estrutura abaixo tem dois consumidores.**

## As três Edge Functions

| Função | Quem chama | Para quê | Auth |
|---|---|---|---|
| `mindagent-bootstrap` | Chat | ler a programação inteira | nenhuma (pública) |
| `mindagent-chat` | Chat | responder pergunta com IA | JWT anônimo + `apikey` |
| `mindagent-admin` | Admin | CRUD do conteúdo | JWT do operador + `apikey` |

Todas no projeto Supabase `ymnmotgglsrxmjmonwjz`.

**Chaves.** O frontend — os dois — carrega **apenas** a publishable key
(`sb_publishable_…`), que é pública por design e depende de RLS no banco.
`service_role`, secret key e `OPENAI_API_KEY` existem só dentro das Edge
Functions. Nenhum dos dois bundles pode conter essas chaves, e há teste
para isso.

## O que o Chat lê — `mindagent-bootstrap`

`GET {base}/eventos/{event_slug}/summit` → JSON:

```js
{
  evento:  { nome, dias: [ISO, ISO], local, regra_reserva, regra_vagas },
  temas:   [ { codigo, rotulo } ],
  sessoes: [ { id, dia, inicio, fim, titulo, descricao, quem, espaco,
               formato, etiqueta, trilhas[], vaga_limitada, online,
               temas[] } ],
  pessoas: [ { nome, credencial, resumo, foto, destaque, na_grade,
               temas[] } ],
  _meta:   { event_slug, generated_at, schema_version }
}
```

Consumido por `data-service.js`, que confere a presença de `evento.dias`,
`temas`, `sessoes` e `pessoas` — faltando qualquer um, a página **falha
dizendo** em vez de desenhar pela metade. Campos extra são ignorados, então
o backend pode acrescentar sem quebrar o chat.

**Cuidado ao mexer:** renomear ou remover qualquer campo dessa lista
apaga informação da tela do participante. `espaco` já vem `null` em 8 de
67 sessões e o chat trata (`"Espaço a confirmar"`); `foto` vem vazia em 5
de 44 pessoas e o card cai na inicial do título.

## O que o Chat pergunta — `mindagent-chat`

`POST {supabaseUrl}/functions/v1/mindagent-chat`

Headers: `apikey`, `Authorization: Bearer <JWT anônimo>`, `Content-Type`.

```js
{ message, event_slug, device_id, client_message_id, session? }
```

**Isto é a lista completa e fechada.** Não entra perfil, nome, e-mail
identificado, cargo, empresa nem histórico da conversa. O mascaramento de
e-mail e telefone acontece na função, antes da OpenAI, com `store: false`.
Quem adicionar campo aqui está mudando a política de privacidade do
produto, não só o payload.

Resposta:

```js
{ ok, answer, session: { id, conversation_id, token, expires_at },
  device_id, identity_verified, interests: [{ key, label, confidence }],
  sources: [{ type, count }], request_id }
```

O chat usa `answer` e guarda `session`. `interests` é gravado no Supabase
pela função e **aparece no painel** — é por aqui que o Admin vê o que os
participantes procuram.

## O que o Admin escreve — `mindagent-admin`

Recursos ligados à API real (`admin/src/services/hybrid-admin-data-provider.ts`):

| Recurso | Operações |
|---|---|
| `event` | list, get, update |
| `sessions` | list, get, create, update, publish, archive |
| `speakers` | list, get, create, update, publish, archive |
| `spaces` | list, get, create, update, archive |
| `themes` | **somente leitura** (`GET /admin/themes`) |

Os demais módulos do painel ainda rodam em memória. O painel marca na
tela o que é simulado (`faixa-demonstracao`, `aviso-escrita`) e recusa
operação que o contrato não tem, em vez de mandar e traduzir o 404.

### Escrita em lote — `scripts/alimentar-banco.mjs`

O painel edita um registro por vez, o que é certo para curadoria e caro
para preencher lacuna em 30 sessões. O script faz isso pela **mesma**
Edge Function — logo herda validação, tradução admin→chat, auditoria e
RLS. Não existe atalho pelo Postgres, e ele recusa token cuja `role` não
seja `authenticated`.

```
npm run banco:inspecionar                        # snapshot + relatório de lacunas
npm run banco:lacunas                            # só o relatório, do snapshot
npm run banco:aplicar -- plano.json              # dry-run: mostra o diff
npm run banco:aplicar -- plano.json --aplicar    # escreve
```

Um plano é dado, não código — `{ recurso, acao, id, campos, motivo }`,
com `acao` em `atualizar` | `criar` | `publicar`. Três garantias que
importam:

- **Dry-run é o padrão.** Sem `--aplicar` nada sai da máquina.
- **Campo com conteúdo não é sobrescrito** sem `--sobrescrever`. O banco
  está à frente do repositório; presumir o contrário apaga trabalho.
- **Toda escrita manda `If-Unmodified-Since-Version`.** Registro que
  mudou desde o snapshot dá conflito em vez de atropelar o painel.

O token do operador vem de `MINDAGENT_ADMIN_TOKEN` no ambiente ou em
`.env.admin.local` (ignorado pelo git) — nunca por argumento, que vaza
em histórico de shell. Snapshot e diário de escritas ficam em `.banco/`,
também fora do git: retrato de um instante não é fonte de verdade.

**Cuidado:** sessão já publicada aparece no chat na hora do `PATCH`. Não
existe rascunho de campo — o fluxo editorial é do registro, não da
edição.

## Onde os dois nomes divergem

O Admin edita em um vocabulário e o Chat lê em outro. **A tradução mora
na Edge Function**, não no frontend — e é o ponto mais fácil de quebrar
sem perceber:

| Admin (`contracts/speaker.ts`) | Bootstrap (chat) | Observação |
|---|---|---|
| `cargo` + `organizacao` | `credencial` | a função junta os dois numa linha |
| `biografia` | `resumo` | mesmo campo, nome diferente |
| `sessaoIds` (derivado) | `na_grade` | booleano vem da existência de sessão |
| `foto` (caminho) | `foto` | igual — ver abaixo |
| `status` editorial | *(ausente)* | rascunho não sai no bootstrap |

**Regra:** mudar nome de campo em um lado exige atualizar a tradução na
função **e** conferir o outro consumidor. Um `rename` silencioso no banco
quebra um dos dois produtos sem erro visível — o campo só chega vazio.

## O acoplamento que sobrou (conhecido)

Três pontos em que o Admin depende de arquivos do Chat. Nenhum é
importação de código ou de estado, e todos são leitura:

1. **`admin/src/lib/fotos.ts`** faz `import.meta.glob` de
   `../../../assets/palestrantes/*.webp` para pré-visualizar a foto que o
   operador digitou. Efeito: as 39 fotos (1,7 MB) entram no bundle do
   painel, e foto nova só aparece no painel depois de rebuild dele.
2. **`admin/src/mocks/seed/summit.ts`** importa `../dados/summit.json` —
   o *fallback* do chat — como dado de demonstração do modo mock.
3. **`@marca/simbolo-mind-verde.png`** (logo, em duas telas).

`foto` é um caminho de texto (`palestrantes/amy.webp`), não um upload: o
arquivo tem de existir em `assets/palestrantes/` do chat e vai para o ar
com o chat. É por isso que palestrante criado no painel nasce sem foto.

## Deploy

`npm run build` na raiz: constrói o painel e monta `dist/`.

```
dist/            → Mind Agent (arquivos da raiz)
dist/admin/      → Painel Admin (build do Vite, base /admin/)
dist/_redirects  → /admin/* → /admin/index.html 200
```

`/` abre o chat, `/admin` abre o painel. O `base: '/admin/'` do Vite e o
`basename` do roteador saem do mesmo valor, então rota e asset não
discordam. Os dois `assets/` ficam em pastas diferentes — não colidem.

**Nunca publicar a raiz do repositório**: os dois `assets/` colidiriam e
README, `admin/node_modules` e `.env.local` iriam para o ar.
