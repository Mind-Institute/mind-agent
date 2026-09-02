# Home V3 em produção — o que aplicar

Estado em 2026-09-01.

| passo | estado |
|---|---|
| Edge Function `mindagent-home` | **publicada** — v1, ativa, `verify_jwt` off |
| `VITE_HOME_API_BASE_URL` no painel | **preenchida** em `admin/.env.local` |
| os quatro SQL | **pendentes** — o ambiente bloqueia escrita no banco |

A função responde e já foi conferida em produção: `/health` volta ok, a
origem de preview passa no CORS e a forjada leva 403. A rota `/publico`
devolve 503 porque a função SQL que ela chama ainda não existe — é o
que os quatro arquivos abaixo criam.

## A regra que desenhou tudo isto

**Nada que já existe é tocado.** Nenhuma tabela, função ou Edge Function
da programação do evento muda. Tudo aqui é objeto novo, ao lado.

| | |
|---|---|
| tabela nova | `concierge.avisos` |
| linha nova numa tabela existente | chave `home` em `concierge.config` |
| funções novas | 5, todas com nome próprio |
| Edge Function nova | `mindagent-home` |
| **modificado** | **nada** |

Desfazer é `drop` no que foi criado e apagar a função. O evento volta
exatamente ao que era.

---

## Os quatro arquivos, na ordem

| # | Arquivo | O que cria |
|---|---|---|
| 1 | `01-concierge-avisos.sql` | tabela `concierge.avisos`, com os quatro avisos que hoje estão no código do app |
| 2 | `04-visualizacao-home.sql` | chave `home` em `concierge.config` + 2 funções (estado e trocas) |
| 3 | `03-admin-home-notices.sql` | 2 funções de leitura e escrita de avisos |
| 4 | `06-funcao-publica.sql` | `api.mindagent_home_publico()` — o que o app lê |

Rodar no SQL Editor do Supabase, um de cada vez, nessa ordem. Nenhum
deles muda nada visível: até aqui o app segue com os avisos embutidos e
o painel segue em memória.

## A Edge Function — JÁ PUBLICADA

```bash
npx supabase functions deploy mindagent-home --project-ref ymnmotgglsrxmjmonwjz --no-verify-jwt
```

O `--no-verify-jwt` é necessário e não é frouxidão: a rota `/publico` é
lida pelo app do participante, que não tem sessão, e a rota `/admin`
verifica o token e o papel por conta própria, na mesma tabela
`mind_admin_users` que a `mindagent-admin` usa. É a mesma configuração
que a `mindagent-admin` e a `mindagent-bootstrap` já têm.

O código está em `supabase/functions/mindagent-home/index.ts`.

## E o painel aponta para ela

Em `admin/.env.local` (já preenchido nesta máquina):

```
VITE_HOME_API_BASE_URL=https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/mindagent-home
```

Sem essa variável, avisos e visualização continuam em memória. Com ela,
falam com a função. É o interruptor, e por isso é o último passo.

---

## Por que uma Edge Function nova

O caminho óbvio seria acrescentar rotas à `mindagent-admin` e chaves ao
`mindagent-bootstrap`. Os dois são de outra lane, e o segundo está
quebrado desde 24/08 (ver abaixo). Rota nova para conteúdo novo custa
uma função e não custa risco nenhum.

O contrato é o mesmo da `mindagent-admin` — mesmos formatos, mesmos
códigos de erro, mesma verificação de papel — porque o painel usa o
mesmo cliente HTTP para as duas.

## Sem cron

Aviso `agendado` entra em circulação sozinho quando o horário chega, e a
troca de composição também: **quem lê aplica a regra**. Nada depende de
uma rotina que pode não rodar às 9h do dia 16.

---

## O que NÃO está aqui, e por quê

### O bootstrap do app está quebrado

`GET /functions/v1/mindagent-bootstrap` responde **503 desde 24/08**:
ele lê de `summit.*` e `comum.*`, schemas renomeados naquele dia
(`summit_vira_summit_2026`, `comum_vira_ecossistema`). O app vive de
`dados/summit.json` desde então, porque tem fallback local.

**Isso não atrapalha os avisos.** Eles vêm por outra porta. A
programação continua vindo do arquivo local, como já vem há nove dias.

O reparo está escrito em `reparo-do-bootstrap/`, com um custo que
precisa de decisão: a grade viva tem 77 sessões **sem tema nenhum**
(`topicos_aprendizado` está `[]`), e sem tema não há recomendação. O
`05` de lá recupera 39 classificações do arquivo local; 24 sessões de
conteúdo continuariam sem. É outra conversa, e é da lane do evento.

### As funções administrativas do evento também

`mind_admin_read_resource`, `mind_admin_mutate_resource` e
`mind_admin_dashboard_counts` leem dos mesmos schemas renomeados.
Confirmado: `mind_admin_dashboard_counts` estoura em
`relation "summit.sessions" does not exist`.

Por isso a **Visão geral** do painel não abre, e os módulos de evento,
programação, palestrantes e espaços devem estar no mesmo estado. O
módulo Home V3 não depende de nenhuma delas.

### A API administrativa recusa origens

`mindagent-admin` só aceita `localhost:5174`, `127.0.0.1:5174` e o
worker publicado. Abrir o painel em qualquer outra porta dá **"A API
administrativa não respondeu"** — não é login, é CORS. A `mindagent-home`
aceita também a porta do app, para não repetir a armadilha.
