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
| `hubspot-perfil-writeback` | perfil profissional → HubSpot (jobtitle, company, icp + icp_confianca, jtbd, `mind_resumo_inteligencia`) a partir de `mind_hubspot_perfil_plano(p_desde)`; ENSAIO por padrão; guarda de última escrita (`mind_hubspot_perfil_registrar` / `preservados`), JTBD como conjunto quando o HubSpot tem o que o Mind escreveu, guarda de qualidade do valor novo; quem não é lead (`nao_lead`, de `pessoas.relacionamento_mind`) tem `icp`, `icp_confianca`, `jtbd` e o resumo **limpos** (`limpezas`); `acao: "propriedades"` alinha `icp`/`jtbd` ao catálogo e cria o resumo. Irmã de `hubspot-commercial-writeback`. Publicada em 23/09/2026; **versão 5 viva = este código** (publicada às 14:46 UTC). Chamada de hora em hora pelo cron `hubspot_perfil_writeback_horario` e pelos gatilhos dos catálogos (`mind_hubspot_perfil_disparar`). Ver `docs/PERFIL_ICP_JTBD.md` |
| `mindagent-acesso` | o primeiro login com o Google da Mind — `POST /admin/vincular` liga a conta Google à pessoa da lista de admins do sistema pela porta `mind_admin_vincular_login` (migration `20260925232508`): conta Google, e-mail verificado @joinmind.com.br, uma pessoa só com esse e-mail, acesso ativo e marca de equipe. Função nova, `verify_jwt = false` porque valida a sessão por dentro e o preflight de CORS não leva token. Publicada em 25/09/2026; **versão 1 viva = este código**; conferida via `pg_net`: `health` 200, sem login 401, token falso 401, origem estranha 403, método errado 405. Contrato do banco: `tests/admins_do_sistema_contract.sql` → `ADMINS_OK` |
| `mindagent-catalogo` | o Catálogo do painel — lê e edita `catalogo.produtos` pelas portas `mind_admin_read_catalogo` / `mind_admin_mutate_catalogo` (migration `20260925183716`), com a mesma autorização da `mindagent-home` (`mind_admin_users`). Função nova, `verify_jwt = false` porque valida a sessão por dentro e o preflight de CORS não leva token. Publicada em 25/09/2026; **versão 2 viva = este código**. Contrato do banco: `tests/catalogo_painel_contract.sql` → `CATALOGO_OK` |
