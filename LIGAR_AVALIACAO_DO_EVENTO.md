# Ligar a Avaliação do evento

Quatro passos. Nenhum deles é reversível sozinho por acidente, mas todos são
reversíveis — o "desfazer" de cada um está ao lado.

O código está todo na `dev`, HEAD `491eab7`. **Nada está ligado.** A chave
`avaliacao_do_evento` em `concierge.config` nasce desligada, e o card só aparece
na home quando o servidor confirma que a pesquisa está aberta.

---

## 1 · Aplicar a migration

⚠ **NÃO use `supabase db push`.** Ele aplicaria *todas* as migrations pendentes,
e entre elas está `20260918140000_avaliacao_do_evento_convite.sql`, que é **gate
da Adriana** e não pode subir agora.

Abra o SQL Editor do Supabase, cole o conteúdo de
`supabase/migrations/20260918120000_avaliacao_do_evento.sql` e rode.

Ela cria uma tabela, uma linha de config e quatro funções. Não altera nada que
já existe — foi rodada contra produção dentro de uma transação desfeita, e a
`engagement.avaliacao_do_dia` continuou com as 40 linhas dela.

**Conferir:**

```sql
select count(*) from engagement.avaliacao_do_evento;
select valor from concierge.config where chave = 'avaliacao_do_evento';
```

Espere `0` e `{"abre": null, "ativo": false, "fecha": null}`.

**Desfazer:** o bloco `DESFAZER` no topo do próprio arquivo.

---

## 2 · Publicar a Edge Function

A viva é a **versão 1**, runtime `1.0.0`. O repo está na `1.2.0`.

```powershell
npx supabase functions deploy mindagent-avaliacao --project-ref ymnmotgglsrxmjmonwjz --no-verify-jwt
```

`--no-verify-jwt` **não é opcional**: a função viva está com `verify_jwt: false`,
e publicar sem a flag ligaria a verificação e derrubaria a pesquisa do dia junto.

**O que muda na 1.2.0:**

- entram `/evento/estado`, `/evento/enviar` e `/admin/evento/…`;
- entram `/convite/…`, que respondem **503 enquanto a migration do convite não
  for aplicada** — e não derrubam mais nada por isso;
- a lista de perguntas passa a ser lida num lugar só pelas duas pesquisas;
- **correção:** a Edge recusava nota `4.5` e `"5"` na porta e deixava `-1` e `6`
  atravessarem até o banco. Valia para as duas pesquisas.

**Conferir:**

```powershell
curl.exe https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/mindagent-avaliacao/health
```

Espere `{"ok":true,"service":"mindagent-avaliacao","version":"1.2.0"}`.

**Desfazer:** publicar de novo a partir do commit anterior a `46b318f`.

---

## 3 · Definir a janela e ligar

As datas abaixo são um palpite meu — **abre hoje, fecha em 14 dias**. Troque à
vontade; é só dado.

```sql
update concierge.config
set valor = jsonb_build_object('ativo', true, 'abre', '2026-09-18', 'fecha', '2026-10-02')
where chave = 'avaliacao_do_evento';
```

As duas datas são lidas no **fuso do evento**, não no do servidor. `fecha` é
inclusive: no dia 02/10 ainda dá para responder. Qualquer uma pode ser `null` —
`abre` nulo é "assim que ligar", `fecha` nulo é "sem prazo".

A janela vale **no envio**, e não só na abertura da tela: quem deixou a aba
aberta e mandou depois de fechar não entra.

**Desfazer:** `set valor = jsonb_set(valor, '{ativo}', 'false')`. A pesquisa some
da home no próximo carregamento, e as respostas já dadas ficam.

---

## 4 · Subir o app

```powershell
git checkout main
```

```powershell
git merge --no-ff dev
```

```powershell
git push origin main
```

O merge em `main` publica o app pela Cloudflare. Sobe a tela da pesquisa, o card
no momento `depois` e a página `/avaliacao-do-evento` no painel.

Pode ser feito **antes** dos passos 1 a 3 sem risco: sem a migration, a leitura
do estado falha, `estadoDaAvaliacaoDoEvento` fica nulo e a home fica exatamente
como é hoje. Conferi isso rodando o app.

**Desfazer:** `git revert -m 1 <hash do merge>` e push.

---

## O que fica de fora, e por quê

**O convite por link** (`20260918140000_avaliacao_do_evento_convite.sql`, as
rotas `/convite/…` e a emissão de convites) está escrito, provado e **não
aplicado**. Ele faz um token no link valer como identidade sem login — é auth, e
o `CLAUDE.md` pede gate explícito da Adriana para isso. O disparo por WhatsApp ou
e-mail é gate separado.

Falta também decidir **limite de tentativa** nas rotas `/convite/…`: elas são as
únicas da função que respondem sem sessão. O token tem 256 bits, então adivinhar
é inviável; o que não está resolvido é volume.

---

## Depois de ligar, conferir de ponta a ponta

1. abrir o app como participante identificado e ver o card **Avaliação do
   evento** na home;
2. responder e conferir que a segunda tentativa é recusada;
3. abrir `/admin/avaliacao-do-evento` e ver a resposta na lista.
