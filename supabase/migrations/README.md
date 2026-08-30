# `supabase/migrations/`

## Stubs históricos (`*_historical_prod_stub.sql`)

Os arquivos com o sufixo `_historical_prod_stub.sql` **não executam nada**. Cada um
representa uma versão que **já está aplicada em produção** e registrada no ledger
`supabase_migrations.schema_migrations`.

Eles existem por um único motivo: satisfazer o pre-flight do Supabase Git integration,
que falha com `Remote migration versions not found in local migrations directory.`
quando o ledger remoto tem versões sem arquivo correspondente aqui.

**Eles não tentam reconstruir o DDL histórico.** São comentários apenas — nenhum SQL
executável. O schema real de produção é a fonte de verdade para tudo o que veio antes
delas.

O SQL histórico recuperado, quando existe, está em
`archive/pre-architecture/missing-migrations/`. Aquele diretório é material de consulta:
**não forma uma cadeia executável** e não deve ser rodado de ponta a ponta.

## Migrations novas

Migrations reais continuam sendo arquivos normais, com timestamp **posterior** ao topo do
ledger histórico, e contendo o DDL de verdade. Elas são aplicadas normalmente pelo deploy
automático no merge em `main`.
