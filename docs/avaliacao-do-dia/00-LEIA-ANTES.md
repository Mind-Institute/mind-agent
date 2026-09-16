# Avaliação do dia — como colocar no ar

Estado em 2026-09-16: **implementado, testado, e desligado.** Nada foi
aplicado em produção — nem migration, nem Edge Function, nem variável de
build.

## O que é

A pesquisa "Avaliação do dia" do Mind Summit: uma resposta por
participante por dia, mais notas opcionais por atividade. Notas de 0 a 5.

**Não é NPS.** Não há escala 0–10, não há promotor nem detrator, e
nenhuma média vira índice. `engagement.nps` continua existindo, intacta e
não reaproveitada — a pesquisa tem outro contrato, e misturar as duas
estragaria as duas.

## A regra que desenhou tudo isto

**Nada que já existe é alterado.** Nenhuma tabela, coluna, função,
trigger, policy ou permissão muda. Tudo é objeto novo, ao lado.

| | |
|---|---|
| tabelas novas | `engagement.avaliacao_do_dia`, `engagement.avaliacao_do_dia_atividade` |
| funções novas | 4, todas com nome próprio |
| linha nova numa tabela existente | chave `avaliacao_do_dia` em `concierge.config` |
| Edge Function nova | `mindagent-avaliacao` |
| **modificado** | **nada** |

Nos arquivos do app e do painel, só os encaixes: o card na home, a rota
da tela, o item do menu e a entrada no build.

---

## Ordem exata de aplicação

```text
1. migration  →  2. Edge Function  →  3. variáveis de build
→  4. verificação  →  5. ativação
```

Nenhum passo antes do anterior. Em particular: **ativar antes de 1 e 2
faz a tela aparecer e não funcionar.**

### 1 · Migration

Arquivo: `supabase/migrations/20260916210000_avaliacao_do_dia.sql`.

No SQL Editor do Supabase, ou pela integração Git ao mergear em `main`.
É `create table if not exists` e `create or replace` — reexecutar é
seguro e não duplica dado.

Conferência depois de aplicar:

```sql
select count(*) from engagement.avaliacao_do_dia;                 -- 0
select valor from concierge.config where chave = 'avaliacao_do_dia'; -- {"ativo": false}
```

### 2 · Edge Function

```bash
npx supabase functions deploy mindagent-avaliacao --project-ref ymnmotgglsrxmjmonwjz --no-verify-jwt
```

O `--no-verify-jwt` é o mesmo das outras funções do projeto e não é
frouxidão: a função **verifica o token por conta própria** em toda rota,
e é ela que decide se o token é de participante ou de administrador. Sem
a flag, o gateway recusaria antes de a função poder distinguir os dois.

Conferência:

```bash
curl -s https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/mindagent-avaliacao/health
```

### 3 · Variáveis de build

**No app** (`config.js`, linha `avaliacaoApiUrl`):

```js
avaliacaoApiUrl: 'https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/mindagent-avaliacao',
```

**No painel** (Cloudflare → Workers & Pages → mind-agent → Settings →
Build → Variables and Secrets, como *plain text*), e em
`admin/.env.local` para desenvolvimento:

```
VITE_AVALIACAO_API_BASE_URL=https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/mindagent-avaliacao
```

Sem ela, a página **Avaliação do dia** abre dizendo que a pesquisa não
foi ligada — e não inventa endereço.

### 4 · Verificação, antes de ativar

Com a pesquisa ainda desligada:

- o card **não** aparece na home;
- a página do painel abre e mostra zero respondentes;
- `GET /estado` responde `{"ativo": false}`.

### 5 · Ativação

```sql
update concierge.config
   set valor = jsonb_build_object('ativo', true)
 where chave = 'avaliacao_do_dia';
```

O card aparece na próxima abertura do app. Não há cron e não há cache do
lado do servidor: quem lê aplica a regra.

---

## Como desligar preservando as respostas

```sql
update concierge.config
   set valor = jsonb_build_object('ativo', false)
 where chave = 'avaliacao_do_dia';
```

Efeito imediato:

- o card some da home;
- quem já estiver com a tela aberta recebe recusa ao enviar, com a
  mensagem certa — e o rascunho dele continua no aparelho;
- **nenhuma resposta é apagada**, e o relatório continua mostrando tudo
  que foi coletado.

Há um segundo interruptor, do lado do app: `avaliacaoApiUrl: null` em
`config.js`. Ele é mais forte — o app nem chama a função — mas exige
deploy. **Para ligar e desligar no dia, use o do banco.**

Desfazer por completo (só se a pesquisa for cancelada):

```sql
drop function if exists public.mind_avaliacao_do_dia_respostas(text,date,text,uuid,int,int);
drop function if exists public.mind_avaliacao_do_dia_relatorio(text,date,text);
drop function if exists public.mind_avaliacao_do_dia_registrar(uuid,text,date,jsonb);
drop function if exists public.mind_avaliacao_do_dia_estado(uuid,text,date);
drop table if exists engagement.avaliacao_do_dia_atividade;
drop table if exists engagement.avaliacao_do_dia;
delete from concierge.config where chave = 'avaliacao_do_dia';
```

---

## As decisões que valem checar antes de aprovar

### Quem responde é o dono do token, nunca um id do cliente

O app manda o token da sessão anônima que o chat já abre — **a mesma**, e
não uma segunda. As funções do banco recebem `p_auth_user_id` e procuram
a pessoa em `engagement.identidades` (canal `auth_user`). Um
`participante_id` mandado pelo navegador não é aceito por nenhum caminho.

Quem nunca conversou ainda não tem esse vínculo. Para esse caso a Edge
chama `mind_identidade_resolver` — a **mesma** porta canônica, com os
mesmos argumentos, que a `mindagent-chat` usa na primeira mensagem.

> **Ponto de atenção, herdado e não alterado:** essa porta confia no
> e-mail que a Yazo colocou na URL. Quem abrir o app com o e-mail de
> outra pessoa responde como ela — exatamente como já conversa como ela
> hoje. Mudar isso é mudar o contrato de identidade do app inteiro, que
> é outra decisão e outra lane.

### Zero é nota, ausência não é

`nota_expectativas` e `nota_programacao` são `not null` com `check
between 0 and 5`. As notas por atividade existem como **linha**: sem
linha, não há avaliação. O relatório nunca mostra média zero para
atividade sem nota — mostra "Sem avaliações".

Um defeito real disso foi encontrado e corrigido durante a implementação:
`Number(null)` é `0` em JavaScript, e a Edge convertia nota ausente em
zero. Hoje só número inteiro de verdade atravessa.

### O dia é fixado na abertura

O servidor decide o dia (hoje, no fuso `America/Sao_Paulo`) e devolve.
A tela guarda e devolve o mesmo valor no envio; o servidor confere de
novo se ele é um dos `dias` do evento. Atravessar a meia-noite não muda
nada, e não há pesquisa para data fora do evento.

### A trava é do banco, não do `localStorage`

`unique (participante_id, event_id, dia)`, mais um
`pg_advisory_xact_lock` por participante/evento/dia contra clique duplo e
envio concorrente. Reenvio idêntico devolve a resposta já gravada
(`jaRegistrado: true`, o caso do timeout); reenvio divergente é recusado.
Limpar o armazenamento do aparelho ou abrir em outro não destrava nada.

### Categoria de acesso, não trilha

A grade sai de `summit_2026.sessions`. O filtro **Todos / Mind / VIP /
Prime** usa `ingressos`, que é a categoria de acesso. `trilhas` existe na
tabela e está **vazia nas 77 sessões** — filtrar por ela devolveria uma
lista vazia que pareceria falha de carregamento.

Credenciamento, intervalo e almoço aparecem na lista para a grade ficar
inteira, marcados como bloco de operação e **sem nota**. O servidor
recusa nota para eles.

---

## Duas divergências que precisam de decisão de produto

### 1 · `camarote` existe e não está no formulário

A pergunta 2 oferece **Mind / VIP / Prime**, como especificado. Mas
`summit_2026.sessions.ingressos` e o espelho do credenciamento têm uma
quarta categoria viva: **Camarote**. O app já a reconhece no cabeçalho
desde 06/09.

Hoje, quem é Camarote não recebe sugestão (o campo vem em branco) e
precisa escolher uma das três — ou seja, **declara algo que não é**.

São três caminhos, e o primeiro é meu voto:

1. acrescentar `camarote` como quarta opção e quarto filtro;
2. manter as três e aceitar que o Camarote se declare Prime;
3. manter as três e não mostrar a pesquisa para Camarote.

Acrescentar é uma linha no `check` da tabela, uma no `EXPERIENCIAS` e
uma no `FILTROS`. **Fazer depois da primeira resposta coletada é pior**,
porque a série muda no meio.

### 2 · Taxa de participação está omitida, de propósito

A pesquisa pede o KPI "só se houver denominador confiável de presentes no
dia". Não há: o espelho do credenciamento tem quem **comprou**, não quem
**entrou**. O KPI não aparece. Se aparecer um registro de entrada
confiável, ele entra.
