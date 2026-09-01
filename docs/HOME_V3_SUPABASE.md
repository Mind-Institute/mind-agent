# Home V3 — o que falta no Supabase

Estado em 2026-09-01. A interface das duas pontas está pronta e testada;
o que não existe é o meio de campo. Este documento lista o que precisa ser
criado para a Home V3 sair da demonstração.

**Nada aqui foi executado.** Criar tabela, mexer em RLS e disparar aviso
são gates da Adriana pelo `CLAUDE.md`. Este é o mapa para fazermos juntos.

---

## Avisos: pronto para aplicar (2026-09-01)

A parte de **avisos** saiu do plano e virou código. Os arquivos abaixo
estão escritos, revisáveis e ainda **não aplicados** — a escrita em
produção é a decisão que falta.

| Arquivo | O que faz | Onde roda |
|---|---|---|
| `docs/sql/home-v3/01-concierge-avisos.sql` | Cria `concierge.avisos` e semeia os quatro avisos que estavam no código do app | Banco |
| `docs/sql/home-v3/02-bootstrap-avisos.sql` | `api.mindagent_bootstrap` passa a devolver `avisos` | Banco |
| `docs/sql/home-v3/03-admin-home-notices.sql` | Leitura e escrita do recurso `home_notices` para o painel | Banco |
| `docs/edge/mindagent-admin/index.ts` | v17 viva + a rota `home_notices` | Deploy da Edge Function |
| `admin/src/services/hybrid-admin-data-provider.ts` | Acrescentar `home_notices` a `RECURSOS_REAIS` e a `OPERACOES` | Painel — **fazer por último** |

O lado do app **já está pronto e no ar em localhost**: `home/estado.js`
consome `DADOS.avisos` quando o payload traz a chave e continua com a
lista embutida quando não traz. Aplicar o banco não quebra nada; não
aplicar também não.

### Três decisões diferentes do plano original

1. **`concierge.avisos`, não `public.home_notices`.** O schema
   `concierge` é o da experiência do participante e já tinha treze
   tabelas com a mesma configuração de RLS. Mais: `concierge.tutorial_passos`
   já apontava para avisos pela coluna `aviso_chave`, sem tabela do
   outro lado. A casa faltava ali, não em `public`.

2. **Sem `pg_cron`.** O plano previa uma rotina para virar
   `agendado` → `no-ar` na hora marcada. Não precisa: quem lê aplica a
   regra (`situacao='agendado' and disparo_em <= now()`), nos dois
   lados, com o mesmo critério. Menos peça, menos coisa para falhar às
   9h do dia 16.

3. **A leitura de aviso continua no dispositivo.** `home_notice_reads`
   guardaria por pessoa quem leu o quê — e isso é identidade, que é
   gate. O contador de não lidos funciona hoje em `sessionStorage`,
   por dispositivo, e `home/avisos.js` já isola essa porta em duas
   funções. Quando a identidade entrar, muda ali e em nenhum outro
   lugar.

### Ordem de aplicação

```text
01 → 02 → conferir o app em produção (avisos continuam iguais)
   → 03 → deploy da mindagent-admin → RECURSOS_REAIS no painel
```

Publicar a Edge Function **antes** do 03 faz a página de avisos
responder 503. Ligar `RECURSOS_REAIS` antes do deploy faz a página
responder 404. Fora dessa ordem, cada passo é inofensivo sozinho.

### O que continua só no plano

`home_state` e `home_schedule` — a página **Visualização** do painel
segue em banco de demonstração. Trocar o momento lá ainda não muda o que
o participante vê. As seções 1.1, 1.2 e 4 abaixo continuam valendo como
mapa.

---

## O que já funciona sem backend

| Ponta | Onde | O que faz |
|---|---|---|
| App | `home/estado.js` | Conteúdo dos quatro momentos e a lista de avisos, fixos no código |
| App | `home/avisos.js` | Tela de avisos, contador de não lidos, marcação de leitura em `localStorage` |
| App | `app.js` → `proximaExperiencia()` | Lê a grade real e escolhe a próxima sessão por afinidade |
| Painel | `admin/src/pages/home-visualizacao.tsx` | Troca de momento e trocas programadas, no banco de demonstração |
| Painel | `admin/src/pages/home-avisos.tsx` | Cria avisos com prévia, no banco de demonstração |

As duas pontas **não se falam**. Trocar o momento no painel não muda o que
o participante vê, e um aviso criado lá não chega na home.

---

## 1. Tabelas

Os nomes das tabelas espelham os recursos já registrados em
`admin/src/contracts/resources.ts` — `home_state`, `home_schedule`,
`home_notices`. Manter isso alinhado é o que permite o painel trocar o
mock pelo HTTP sem reescrever tela.

### 1.1 `home_state` — o que está no ar

Linha única por evento.

| coluna | tipo | nota |
|---|---|---|
| `id` | text, PK | `home` |
| `event_slug` | text, FK → evento | qual evento |
| `momento` | text | `antes` \| `no-evento` \| `entre-dias` \| `depois` |
| `modo` | text | `manual` \| `programado` |
| `atualizado_em` | timestamptz | |
| `atualizado_por` | uuid | operador |

Restrição de valor por `CHECK`, não por enum de banco: a lista de momentos
ainda pode crescer, e enum em Postgres é caro de alterar.

### 1.2 `home_schedule` — trocas programadas

| coluna | tipo | nota |
|---|---|---|
| `id` | uuid, PK | |
| `event_slug` | text | |
| `quando` | timestamptz | com fuso, não `timestamp` |
| `momento` | text | mesmo `CHECK` |
| `nota` | text | por que a troca acontece ali |
| `aplicada` | boolean | vira `true` quando o horário passa |
| `criado_em`, `atualizado_em`, `atualizado_por` | | |

**Índice** em `(event_slug, quando) WHERE NOT aplicada` — é a consulta do
job que aplica as trocas.

### 1.3 `home_notices` — os avisos  ·  SUBSTITUÍDA

> Virou `docs/sql/home-v3/01-concierge-avisos.sql`, com nome e schema
> diferentes do esboço abaixo. O que vale é o arquivo.

| coluna | tipo | nota |
|---|---|---|
| `id` | uuid, PK | |
| `event_slug` | text | |
| `icone` | text | chave, não SVG. `megafone`, `lugar`, `relogio`, `sino`, `ingresso`, `fone`, `agenda`, `alerta`, `estrela` |
| `titulo` | text | ≤ 80 |
| `subtitulo` | text | ≤ 120, a linha de apoio do card |
| `descricao` | text | ≤ 1200, o texto que abre |
| `imediato` | boolean | |
| `disparo_em` | timestamptz | |
| `situacao` | text | `rascunho` \| `agendado` \| `no-ar` \| `encerrado` |
| `ver_no_app` | text, nulo | tela do tour a abrir (`qrcode`, `mapa`…) |
| `criado_em`, `atualizado_em`, `atualizado_por` | | |

O ícone é chave e não SVG de propósito: cada ponta desenha o seu, e trocar
o traço não exige migração de dado.

### 1.4 `home_notice_reads` — quem leu o quê  ·  ADIADA

> Depende de identidade, que é gate. Continua em `sessionStorage`.

É a tabela que o app precisa e ainda não tem.

| coluna | tipo | nota |
|---|---|---|
| `notice_id` | uuid, FK → `home_notices` | |
| `participant_id` | uuid, FK → participante | |
| `lido_em` | timestamptz | |

**PK composta** `(notice_id, participant_id)`: ler duas vezes não cria duas
linhas, e o `INSERT ... ON CONFLICT DO NOTHING` fica trivial.

**Decisão pendente:** hoje o app identifica a pessoa por e-mail vindo da
Yazo, não por `uuid`. Ou criamos a tabela de participantes de verdade, ou
`participant_id` vira o hash do e-mail. A primeira é a certa; a segunda
adianta o contador.

---

## 2. RLS

O que exige gate explícito, porque erra em silêncio.

- **`home_state`, `home_schedule`, `home_notices`** — leitura pública só do
  que está publicado: `situacao = 'no-ar'` para avisos, e a linha única de
  estado. Escrita só para operador autenticado com papel que permita.
- **`home_notice_reads`** — cada pessoa lê e escreve **apenas as próprias
  linhas**. É a regra mais sensível do conjunto: sem ela, alguém consegue
  listar quem leu o quê, que é dado de comportamento individual.
- Nenhuma das tabelas pode ficar acessível pela chave publicável em
  escrita. A marcação de leitura tem que passar por função, não por
  `INSERT` direto do navegador.

---

## 3. Edge Functions

### 3.1 `mindagent-admin` — rotas novas

Seguindo o padrão dos módulos já reais (evento, programação, palestrantes,
espaços):

```
GET    /admin/home_state
PATCH  /admin/home_state/home
GET    /admin/home_schedule
POST   /admin/home_schedule
PATCH  /admin/home_schedule/{id}
DELETE /admin/home_schedule/{id}      (arquivar, não apagar)
GET    /admin/home_notices
POST   /admin/home_notices
PATCH  /admin/home_notices/{id}
DELETE /admin/home_notices/{id}       (arquivar)
```

Depois disso, registrar os três em `RECURSOS_REAIS` no
`admin/src/services/hybrid-admin-data-provider.ts`. **É a única mudança de
código do painel** — as páginas não sabem de onde o dado vem.

### 3.2 `mindagent-bootstrap` — o que o app lê

O app hoje não pede nada disso. Precisa passar a receber, junto com a
programação:

```json
{
  "home": { "momento": "no-evento" },
  "avisos": [
    { "id": "...", "icone": "lugar", "titulo": "...",
      "subtitulo": "...", "descricao": "...", "verNoApp": null }
  ],
  "avisosLidos": ["id1", "id2"]
}
```

`avisosLidos` só vem quando há participante identificado.

### 3.3 Marcar como lido

```
POST /avisos/{id}/lido
```

Autenticada pelo JWT anônimo que o chat já usa, com o e-mail da Yazo no
corpo. Idempotente.

---

## 4. O job das trocas programadas

Um `pg_cron` de minuto em minuto:

> Para cada evento em `modo = 'programado'`, pega a troca não aplicada mais
> antiga cujo `quando` já passou, escreve o `momento` dela em `home_state` e
> marca `aplicada = true`.

O mesmo job serve para os avisos: `situacao = 'agendado'` com `disparo_em`
no passado vira `no-ar`.

**Cuidado:** o job precisa respeitar o `modo`. Em `manual` ele não pode
tocar em `home_state` — é justamente para isso que o botão existe.

---

## 5. O que muda no app

Menor parte do trabalho, e a última.

1. `home/estado.js` — `CONTEUDO` continua no código (é layout), mas
   `AVISOS` passa a vir do bootstrap.
2. `home/estado.js` — `momentoAtual()` lê `home.momento` da resposta em vez
   do `sessionStorage`. O seletor de desenvolvimento continua sobrepondo em
   localhost.
3. `home/avisos.js` — `lidos()` e `marcarLido()` passam a falar com a API.
   **São as duas únicas funções que mudam**; nenhuma tela é tocada.
4. `app.js` — `INSTANTE_DEMO` sai: nos dias do evento o relógio já é real.

---

## 6. Ordem sugerida

1. Tabelas + RLS (gate)
2. Rotas no `mindagent-admin` → painel vira real trocando uma constante
3. `home_notice_reads` + `POST /avisos/{id}/lido` → contador real
4. Bootstrap devolvendo `home` e `avisos` → app lê do banco
5. `pg_cron` das trocas → programação passa a valer sozinha

Os passos 2 e 3 são independentes; 4 depende de 1; 5 depende de 1 e 4.

---

## 7. Perguntas em aberto

- **Identidade do participante.** Hoje é e-mail da Yazo em `sessionStorage`.
  Para `home_notice_reads` funcionar entre aparelhos, precisa virar registro.
  Isso é decisão de produto, não de banco.
- **Aviso é por evento ou por perfil?** Tudo aqui assume que todo mundo vê
  o mesmo. Segmentar por trilha ou por ingresso muda a tabela.
- **Notificação empurrada.** "Disparo imediato" hoje significa "aparece na
  home". Se tiver que virar push ou WhatsApp, é outro assunto — e outro
  gate, porque é outbound de verdade.
