# `supabase/functions/`

## Merge em `main` publica Edge Function

A integração GitHub do Supabase deste projeto **não roda só migrations**: a branch `main`
aparece em `list_branches` com status `FUNCTIONS_DEPLOYED`. O que estiver aqui é
publicado no projeto `ymnmotgglsrxmjmonwjz` quando a PR é mergeada, exatamente como
`supabase/migrations/` é aplicado.

Isso é o contrato canônico **merge em `main` é boundary de deploy** (`PROJECT_STATE.md`
§2B) valendo também para runtime, não só para schema. Revisão e teste vêm **antes** do
merge.

## Este diretório não é o inventário das functions

O projeto tem mais de vinte Edge Functions ativas; a maioria vive só no Supabase. Uma
função entra aqui quando passa a ser versionada — e, a partir daí, **o repositório é a
fonte**: um merge sobrescreve a versão publicada com o que estiver neste arquivo.

Consequência prática, e a única regra que importa aqui:

> Antes de mergear qualquer mudança neste diretório, **diferencie o arquivo contra a
> versão que está no ar**. Se alguém publicou pela dashboard ou pelo MCP desde que este
> arquivo foi escrito, o merge desfaz aquilo silenciosamente.

```bash
supabase functions download treble-inbound-agent --project-ref ymnmotgglsrxmjmonwjz
diff -u supabase/functions/treble-inbound-agent/index.ts <baixado>/index.ts
```

## O que está versionado

| function | por quê |
|---|---|
| `treble-inbound-agent` | runtime do Vendedor Summit — o turno atravessa Router → Capability Gate → Kit Loader, e essa mudança precisa ser revisável em PR |
