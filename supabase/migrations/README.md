# supabase/migrations

Migrations **novas** (target), aplicadas via Supabase e versionadas aqui para
reprodutibilidade. O nome do arquivo casa com a `version` registrada no Supabase
(`select version, name from supabase_migrations.schema_migrations`).

As migrations **históricas** recuperadas do protótipo estão em
`archive/pre-architecture/missing-migrations/` — não são reexecutadas; ficam como
memória do que já foi aplicado antes deste diretório existir.

Cada migration nova traz, no topo, um bloco `ROLLBACK` com o inverso exato.
