# `supabase/functions/`

## Merge em `main` NÃO publica esta function — hoje

A integração GitHub do Supabase deste projeto roda migrations no merge, mas **só publica
Edge Function declarada em `supabase/config.toml`**, na forma `[functions.<slug>]`. O
próprio check avisa isso em toda PR:

> ⚠️ Only Functions declared in config.toml will be automatically deployed to branches

**Este repositório não tem `supabase/config.toml`.** Logo, o que está aqui é código
versionado e revisável, e **a publicação é um passo manual** — `supabase functions
deploy`, a dashboard ou o MCP.

Isso é uma escolha em aberto, não um esquecimento a corrigir de passagem: declarar as
functions no `config.toml` colocaria o runtime dentro do contrato **merge em `main` é
boundary de deploy** (`PROJECT_STATE.md` §2B), junto com as migrations. É decisão de
infraestrutura, e muda o que um merge faz.

## Este diretório não é o inventário das functions

O projeto tem mais de vinte Edge Functions ativas; a maioria vive só no Supabase. Uma
função entra aqui quando passa a ser versionada — e, a partir daí, **o repositório é a
referência**: publicar significa levar este arquivo para o ar, sobrescrevendo o que
estiver publicado.

Daí a única regra que importa aqui:

> Antes de publicar, **diferencie o arquivo contra a versão que está no ar**. Se alguém
> publicou pela dashboard ou pelo MCP desde que este arquivo foi escrito, publicar desfaz
> aquilo silenciosamente.

```bash
supabase functions download treble-inbound-agent --project-ref ymnmotgglsrxmjmonwjz
diff -u supabase/functions/treble-inbound-agent/index.ts <baixado>/index.ts
```

## O que está versionado

| function | por quê |
|---|---|
| `treble-inbound-agent` | runtime do Vendedor Summit — o turno atravessa Router → Capability Gate → Kit Loader, e essa mudança precisa ser revisável em PR |
| `mindagent-chat` | runtime do Concierge Summit — o turno atravessa Capability Gate → Kit Loader, e o mesmo endpoint executa as ferramentas do Play. Versionada a partir da **version 23** viva, num commit isolado, para o diff ser contra a fonte real |
