# READ ME FIRST — a Regra #1 do sistema Mind

> Leia isto antes de qualquer outro documento e antes de escrever qualquer linha que fale
> de uma pessoa. Decisão da Adriana em 22–23/09/2026 (**D5**, `PROJECT_STATE.md` v10).

## Regra #1 — toda linha sobre uma pessoa nasce ligada à pessoa

Nas palavras da Adriana:

> *Sempre que uma linha sobre qualquer pessoa for escrita em qualquer tabela, o sistema
> deve acionar imediatamente uma coluna, se não existir, com o ID universal da pessoa — e,
> antes de criá-lo, buscar na tabela `pessoas.pessoas` hints que a reconheçam. Todas as
> tabelas sobre clientes precisam conversar e estar linkadas às pessoas às quais se
> referem.*

Na forma operacional:

1. **O ID universal é `pessoas.pessoas.id` — o Mind ID.** Em toda outra tabela ele mora na coluna
   `mind_id` (D6, 23/09/2026; antes `pessoa_id`/`participante_id`). Uma linha por pessoa, de qualquer fonte —
   HubSpot, Eduzz, Blinket, credenciamento, Yazo, checkout, WhatsApp, app. Ele persiste:
   uma pessoa absorvida por fusão continua existindo, apontando para a sobrevivente
   (`fundida_em`), e o id antigo continua resolvendo (`mind_pessoa_canonica`).
2. **Toda tabela que fala de pessoa tem `mind_id`** (mais `mind_id_criterio` e
   `mind_id_resolvido_em`). Se a tabela é nova, ela entra na regra com uma chamada:
   `select mind_pessoa_ligar_tabela('schema.tabela', '{"emails":["email"],"telefones":["whatsapp"],"nome":["nome"]}')`.
3. **Resolver ou criar ANTES de escrever.** Um trigger `before insert or update` em cada
   tabela-fonte passa a linha pela **porta única** `mind_identidade_resolver`: procura os
   hints em `engagement.identidades`, liga à pessoa que achar, cria a pessoa se não achar
   ninguém e houver hint forte. Falha de identidade nunca bloqueia a escrita: a linha entra
   e `mind_id_criterio` diz por quê ficou sem pessoa.
4. **Antes de criar qualquer pessoa: enriquecer e unificar quem já existe.** Enquanto
   houver pessoa que a fase A ainda não completou, a porta só liga — não cria.
5. **Ninguém funde sem a Adriana decidir.** Duplicata vira proposta (`identidade_fusoes`,
   com `padrao` e `proposta`); só `mind_fusao_decidir` funde, por padrão inteiro (só as de
   confiança alta) ou linha a linha. Na dúvida, perguntar e não unificar.

## Os hints que reconhecem uma pessoa — v2 (23/09, madrugada, com a Adriana)

Duas perguntas separadas: **quem reconhece sozinho** (força) e **quem vence quando discordam**
(precedência). Nas palavras dela: *"e-mail, nome e sobrenome vencem; depois o WhatsApp; depois
CPF; depois CNPJ"*.

| hint | força | reconhece sozinho? | precedência | observação |
|---|---|---|---|---|
| login no app (`auth_user`) | 4 | sim | 1 | a evidência mais forte |
| id do HubSpot, da Yazo, do credenciamento, da Eduzz/Blinket, do LearnWorlds | 3 | sim | 2 | identifica o registro naquele sistema |
| **e-mail** | 2 | sim | **3** | chave de entrada; a pessoa pode ter mais de um |
| WhatsApp em E.164 | 3 | sim | 4 | chave de entrada — mas o telefone do comprador aparece nos ingressos de quem ele inscreveu |
| **CPF** | 1 | **não** | 5 | muitas vezes é do comprador ou do porta-voz; só apoio |
| CNPJ | 1 | não | 6 | é empresa, não pessoa |
| **nome e sobrenome** | — | nunca cria sozinho | **veta** | fonte de verdade: *"você não vai repetir o nome da pessoa"* |

**A regra do nome** (`mind_nomes_compativeis`): nome com grafia diferente, sem acento, com um
sobrenome a mais ou a menos, apelido ou nome composto é **o mesmo nome**; primeiro nome
claramente diferente é **outra pessoa**. E então:

| o que bate | o que difere | decisão |
|---|---|---|
| e-mail | nome parecido | **mesma pessoa** — liga |
| e-mail | nome claramente diferente | **não liga**: e-mail de comprador/porta-voz? vira proposta baixa (`mesmo_email_nomes_diferentes`) |
| telefone (e/ou CPF) | nome **e** e-mail | **pessoas diferentes**, inscritas por terceiro — não liga, não propõe |
| telefone | e-mail (nome igual) | **suspeita** — não liga; proposta média (`mesmo_telefone_emails_diferentes`) |
| telefone | nome (sem e-mail para comparar) | outra pessoa — não liga; proposta baixa (`nomes_divergentes`) |
| id de terceiro / login | nome | liga (é o mesmo registro), marcado `(nome divergente)` para revisão |

**Inscrição por terceiro**: quando o e-mail do participante é diferente do e-mail do comprador
(`buyer_email`, `email_comprador`, `text_40` da Yazo, "Email do comprador" do relatório), o
telefone e o CPF da linha são **do comprador** e ficam de fora — a pessoa entra por e-mail, nome e
id. Sem isso, uma compradora da Vale recebeu os e-mails de cinco colegas (medido em 23/09).

**Antes de criar qualquer pessoa, bater com `pessoas.pessoas`**: a porta procura em
`engagement.identidades` e nas colunas da própria pessoa (e-mail, WhatsApp, hubspot_id); só cria
quando existe identificador forte **livre** — nunca quando todos já são de gente que a regra do
nome recusou (a linha fica sem pessoa, com o motivo em `mind_id_criterio`).

Regras já combinadas (23/09):

- **e-mails diferentes podem ser a mesma pessoa** (`elisama@gmail` e `elisama@univoz`): caso a
  caso — proposta média, nunca fusão automática;
- **telefone em mais de duas pessoas** (central, empresa, comprador) nunca se aprova em bloco;
- **CPF do credenciamento e da Yazo é o do comprador** (igual ao "CPF do Comprador" em 100% do
  export de 21/09): não entra como hint da pessoa nessas fontes;
- **e-mail do comprador** de ingresso corporativo não é e-mail da pessoa;
- a proposta de fusão guarda **a evidência mais forte** que o par compartilha (e-mail acima de
  telefone), não a última registrada.

Ainda por combinar juntos: se id da Yazo repetido entre edições de Summit conta como a mesma
pessoa. Decidido em 23/09 (D6): a coluna do ID universal chama-se `mind_id` em toda tabela; as chaves
dos payloads das funções (`pessoa_id`, `participante_id` em jsonb) e os nomes de saída das views `api.*`
são contrato de API e ficam.

## A passada de acerto (uma vez), na ordem da Adriana

| fase | o que faz | quem roda |
|---|---|---|
| **A — enriquecer** | cada pessoa em `pessoas.pessoas` recebe todos os hints que as fontes já ligadas a ela conhecem (e-mail, telefone e nome do contato do HubSpot; ids do credenciamento, da Yazo, da Eduzz). Nunca cria pessoa. O que já é de outra pessoa vira proposta | Adriana |
| **B — unificar** | as propostas, agrupadas por padrão, são decididas: aprovar (funde) ou rejeitar. Só confiança alta em bloco | Adriana |
| **C — criar** | as tabelas de entrada, nesta ordem — **HubSpot → Eduzz → Blinket → conversas do Treble → credenciamento → Yazo** — ganham `mind_id` em toda linha; quem não existe, depois de procurado, é criado | Adriana |

Scripts numerados em `scripts/infra/identidade/`. Contrato que prova as promessas:
`tests/d5_identidade_universal_contract.sql`. Migration: `supabase/migrations/20260923024555_d5_identidade_universal.sql`.

## Onde cada coisa mora

| | |
|---|---|
| a pessoa | `pessoas.pessoas` |
| os hints dela | `engagement.identidades` (um por linha: canal + identificador) |
| a pessoa com todos os ids numa linha | `pessoas.v_pessoa_360` |
| a porta única | `public.mind_identidade_resolver` |
| o trigger | `public.mind_pessoa_antes_de_escrever` (`zz_d5_pessoa_antes_de_escrever` em cada tabela) |
| pôr uma tabela na regra | `public.mind_pessoa_ligar_tabela` |
| as duplicatas propostas | `engagement.identidade_fusoes` (`padrao`, `proposta`) |
| a decisão | `public.mind_fusao_decidir` — o único caminho que funde |

## Depois disto, leia

1. `CHECKPOINT_ATUAL.md` — onde estamos agora.
2. `PROJECT_STATE.md` — arquitetura e decisões congeladas (D1–D5).
3. `docs/CORE_UNIVERSAL.md` — o que está vivo, inclusive a identidade (§3).
4. `CLAUDE.md` / `AGENTS.md` — regras de trabalho.
