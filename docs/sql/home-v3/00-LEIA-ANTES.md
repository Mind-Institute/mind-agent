# Antes de aplicar qualquer coisa aqui

Estado em 2026-09-01. Cinco arquivos SQL, um arquivo de Edge Function e
uma linha no painel. **Nada foi aplicado.**

---

## O que está quebrado hoje

`GET /functions/v1/mindagent-bootstrap` responde **503 em toda chamada**,
desde 24/08. A Edge Function é só um proxy; quem falha é a função SQL:

```
POST /rest/v1/rpc/mindagent_bootstrap
→ 404  {"code":"42P01","message":"relation \"summit.events\" does not exist"}
```

### Causa

| Migração (24/08) | O que fez |
|---|---|
| `20260824160343 summit_vira_summit_2026` | `summit` → `summit_2026` |
| `20260824173701 comum_vira_ecossistema` | `comum` → `ecossistema` |

`api.mindagent_bootstrap` continuou lendo de `summit.*` e `comum.*`.
Confirmado: `select count(*) from pg_namespace where nspname in
('summit','comum')` devolve zero. A migração
`20260825050201 repointa_cinco_funcoes_vivas_para_pessoas` consertou
cinco funções; o bootstrap não estava entre elas.

### Por que ninguém viu

`CONFIG.useLocalFallback` é `true` e `data-service.js` cai para
`dados/summit.json` quando a API falha. O app funciona — com a
programação congelada num arquivo. Há nove dias.

### O que mais depende dos mesmos nomes

`public.mind_admin_read_resource` e `public.mind_admin_mutate_resource`
leem de `summit.events`, `summit.sessions`, `summit.locations` e
`comum.speakers`. São as funções que servem os módulos REAIS do painel
(evento, programação, palestrantes, espaços, temas). Pelo mesmo motivo,
devem estar respondendo erro. **Não estão consertadas aqui** — o
`02-bootstrap-app.sql` cuida só do lado do app.

---

## O buraco maior: a grade não tem temas

`summit_2026.sessions.topicos_aprendizado` está `[]` nas **77 sessões**,
e `trilhas` está vazio. Sem tema não há afinidade; sem afinidade o
Concierge não recomenda nada.

Consertar o bootstrap sozinho deixaria o app **pior** do que está: ele
ganharia a grade real e perderia a recomendação inteira. Por isso o
`05-temas-das-sessoes.sql` existe e vem antes.

O 05 recupera a classificação que ainda existe em `dados/summit.json`:
39 sessões casadas por dia, horário e título. Depois dele, **35 das 59
sessões de conteúdo têm tema; 24 continuam sem** — e essas o Concierge
não vai recomendar, porque não sabe do que falam. Classificar as que
faltam é trabalho de conteúdo, não de migração.

---

## O que muda para o participante quando o 02 rodar

| | arquivo local (hoje) | grade viva (depois) |
|---|---|---|
| sessões | 53 | 77, com credenciamento, intervalo e almoço |
| com tema | 49 | 35 |
| palestrantes | 39 | 63 |
| foto | sim | **não** |
| destaque | sim | **não** |

`ecossistema.palestrantes_especialistas` não tem `foto`, `destaque` nem
`temas` — decisão de 01/09: foto e destaque deixam de existir, e os
temas passam a ser **derivados das sessões em que a pessoa fala**. Muda o
significado: antes era "sobre o que essa pessoa trabalha", agora é "sobre
o que ela fala neste evento". Para recomendar dentro do Summit, serve
melhor.

`cardPessoa()` já foi ajustado: sem retrato, mostra as iniciais.

A etiqueta da sessão também perde qualidade: vinha da taxonomia (que
morava em `comum`) e passa a sair do próprio tipo. "Masterclass Prime"
vira "Masterclass"; "Workshop VIP" vira "Workshop".

---

## Os arquivos, e o que cada um destrava

| Arquivo | Onde roda | O que passa a existir |
|---|---|---|
| `01-concierge-avisos.sql` | banco | tabela `concierge.avisos` com os quatro avisos de hoje |
| `04-visualizacao-home.sql` | banco | chave `home` em `concierge.config` e as funções de estado/trocas |
| `05-temas-das-sessoes.sql` | banco | 39 sessões voltam a ter tema |
| `03-admin-home-notices.sql` | banco | leitura e escrita de avisos para o painel |
| `02-bootstrap-app.sql` | banco | **conserta o 503** e entrega `avisos` e `home` ao app |
| `docs/edge/mindagent-admin/index.ts` | deploy | as três rotas do painel: avisos, estado, trocas |
| `RECURSOS_REAIS` no painel | build do admin | as páginas param de falar com o mock |

### Ordem

```text
01 · 04 · 05 · 03   (banco, podem ir juntos — nada muda para ninguém)
       ↓
02                  (liga o app: sai o arquivo local, entra a grade viva)
       ↓
deploy da mindagent-admin
       ↓
RECURSOS_REAIS      (liga o painel)
```

Os quatro primeiros são invisíveis: o app continua no arquivo local e o
painel continua no mock. **O 02 é a virada do app** e o
`RECURSOS_REAIS` é a virada do painel. Até o 02, tudo é reversível sem
ninguém ver.

Publicar a Edge Function antes do `03`/`04` faz as páginas do módulo
responderem 503. Ligar `RECURSOS_REAIS` antes do deploy faz responderem
404.

### Como voltar atrás

| Arquivo | Desfazer |
|---|---|
| 01 | `drop table concierge.avisos;` |
| 04 | `drop function` nas duas + `delete from concierge.config where chave='home'` |
| 05 | não tem desfazer automático — mas só preenche campo que estava vazio |
| 03 | `drop function` nas duas |
| 02 | reaplicar a v17 (está no histórico do git deste arquivo) |
| deploy | republicar a versão anterior da função |

---

## O que o app já sabe fazer

Sem depender de nada acima:

- `home/estado.js` usa `DADOS.avisos` quando o payload traz a chave, e os
  avisos embutidos quando não traz;
- `definirMomentoDoServidor()` obedece `DADOS.home.momento`, e o seletor
  local continua ganhando dele em desenvolvimento;
- com o painel no comando, a contagem regressiva para de virar a tela
  sozinha — duas autoridades decidindo a mesma coisa é como se perde o
  controle no dia do evento;
- `cardPessoa()` desenha palestrante sem foto.
