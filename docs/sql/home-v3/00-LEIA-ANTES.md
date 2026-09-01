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

## Consequência para os avisos

O `02-bootstrap-avisos.sql` reproduz a função como ela está hoje,
quebrada, e só acrescenta a chave `avisos`. **Aplicar não conserta o
503** — e também não piora nada. Foi escrito assim de propósito: dobrar
um reparo de produção dentro de uma entrega de avisos esconderia a
decisão.

Ou seja: os avisos só chegam ao app depois que o bootstrap voltar a
responder. O `01` e o `03` são independentes disso.

O `03` já usa `summit_2026` — é o único arquivo daqui escrito contra o
schema que realmente existe.
