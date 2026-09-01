# Antes de aplicar qualquer coisa aqui

Descoberto em 2026-09-01, investigando o caminho dos avisos.

## O bootstrap do app está quebrado em produção

`GET /functions/v1/mindagent-bootstrap` responde **503** em toda chamada.
A Edge Function é só um proxy; quem falha é a função SQL que ela chama:

```
POST /rest/v1/rpc/mindagent_bootstrap
→ 404  {"code":"42P01","message":"relation \"summit.events\" does not exist"}
```

### Causa

Duas migrações de 24/08 renomearam os schemas:

| Migração | O que fez |
|---|---|
| `20260824160343 summit_vira_summit_2026` | `summit` → `summit_2026` |
| `20260824173701 comum_vira_ecossistema` | `comum` → `ecossistema` |

`api.mindagent_bootstrap` continuou lendo de `summit.events`,
`summit.sessions`, `summit.locations`, `summit.event_rules`,
`comum.taxonomy` e `comum.speakers`. Nenhum desses nomes existe mais.
Confirmado: `select count(*) from pg_namespace where nspname in
('summit','comum')` devolve zero. Os dados estão vivos em `summit_2026`
(1 evento, 77 sessões).

A migração `20260825050201 repointa_cinco_funcoes_vivas_para_pessoas`
consertou cinco funções. O bootstrap não estava entre elas.

### Por que ninguém viu

`CONFIG.useLocalFallback` é `true` e `data-service.js` cai para
`dados/summit.json` quando a API falha. O app funciona — com a
programação congelada no arquivo, não com a do banco. Está assim há
nove dias.

### O que mais depende dos mesmos nomes

`public.mind_admin_read_resource` e `public.mind_admin_mutate_resource`
leem de `summit.events`, `summit.sessions`, `summit.locations` e
`comum.speakers`. São as funções que servem os módulos REAIS do painel
(evento, programação, palestrantes, espaços, temas) no modo `hybrid`.
Pelo mesmo motivo, devem estar respondendo erro.

### O reparo não é achar-e-trocar

`summit.*` → `summit_2026.*` resolve a maior parte, mas **palestrante
não**: `comum.speakers` virou `ecossistema.palestrantes_especialistas`,
com colunas diferentes.

| Antes (`comum.speakers`) | Agora (`ecossistema.palestrantes_especialistas`) |
|---|---|
| `cargo` | `cargo_curto` |
| `organizacao` | `instituicao` |
| `bio` | `quem_e` |
| `foto_url` / `asset_path` | *(não existe)* |
| `destaque` | *(não existe)* |
| `temas` | *(não existe)* |

O bloco `pessoas` do bootstrap e o recurso `speakers` do painel precisam
ser remapeados, não renomeados. Enquanto isso não acontece, o app
continua servindo `dados/summit.json`.

## Consequência para a Home V3

O `02-bootstrap-app.sql` reproduz a função como ela está hoje, quebrada,
e só acrescenta as chaves `avisos` e `home`. **Aplicar não conserta o
503** — e também não piora nada. Foi escrito assim de propósito: dobrar
um reparo de produção dentro de uma entrega de conteúdo esconderia a
decisão.

Ou seja: **nada chega ao app enquanto o bootstrap não voltar.** O painel
passa a escrever de verdade com o `01`, o `03`, o `04` e o deploy — e é
metade do caminho, porque a outra metade é o app conseguir ler.

O `03` e o `04` já usam `summit_2026` — são os únicos arquivos daqui
escritos contra o schema que realmente existe.

---

## Os arquivos, e o que cada um destrava

| Arquivo | Onde roda | O que passa a existir |
|---|---|---|
| `01-concierge-avisos.sql` | banco | tabela `concierge.avisos` com os quatro avisos de hoje |
| `04-visualizacao-home.sql` | banco | chave `home` em `concierge.config` e as funções de estado/trocas |
| `03-admin-home-notices.sql` | banco | leitura e escrita de avisos para o painel |
| `02-bootstrap-app.sql` | banco | o app passa a receber `avisos` e `home` |
| `docs/edge/mindagent-admin/index.ts` | deploy | as três rotas do painel: avisos, estado, trocas |
| `RECURSOS_REAIS` no painel | build do admin | as páginas param de falar com o mock |

### Ordem

```text
01 → 04 → 03 → 02 → deploy da mindagent-admin → RECURSOS_REAIS
```

Os quatro primeiros são banco e podem ir juntos. Depois deles o painel
ainda fala com o mock — nada muda para ninguém. O deploy sozinho também
não muda nada. **É o último passo que liga a chave**, e é por isso que
ele é o último: até ali, tudo é reversível sem ninguém ver.

Publicar a Edge Function antes do `03`/`04` faz as páginas do módulo
responderem 503. Ligar `RECURSOS_REAIS` antes do deploy faz responderem
404.

### O que o app já sabe fazer

Sem depender de nada acima:

- `home/estado.js` usa `DADOS.avisos` quando o payload traz a chave, e
  os avisos embutidos quando não traz;
- `definirMomentoDoServidor()` obedece `DADOS.home.momento`, e o
  seletor local continua ganhando dele em desenvolvimento;
- com o painel no comando, a contagem regressiva para de virar a tela
  sozinha — duas autoridades decidindo a mesma coisa é como se perde o
  controle no dia do evento.
