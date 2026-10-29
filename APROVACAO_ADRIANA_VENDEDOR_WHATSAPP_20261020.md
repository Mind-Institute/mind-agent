# Para aprovação — Adriana

20/10/2026 · vendedor do WhatsApp · branch `claude/vendedor-institute-dash-whatsapp`
**Nada publicado. Nada aplicado no banco. Treble não tocada.**

São **três decisões separadas**, e elas não dependem uma da outra. Misturá-las é o
que faria o lançamento esperar por uma reforma que ele não precisa.

| | o que é | precisa para lançar? |
|---|---|---|
| **A** | aprovar as 4 funções alteradas (D7) | **sim** |
| **B** | declarar qual é a fonte oficial da oferta do Institute | **sim** |
| **C** | reorganizar oferta/painel no schema `catalogo` | **não** |

---

## A. As quatro funções que mudam — D7

A decisão **D7** (07/10) exige o seu ok antes de criar, alterar ou apagar função.
As quatro já estão escritas e testadas; nenhuma foi aplicada nem publicada.

### A1. Edge Function `treble-inbound-agent` → `1.11.1`

**Por quê.** Em 24/09 você desligou `summit_b2c`/`summit_b2b` no WhatsApp e ligou
`institute` e `dash`, anotando que "o runtime do Treble ainda não executa". O
runtime parou em 06/09. Enquanto isso, a conta era fechada: o Router no WhatsApp só
podia escolher entre `cliente_suporte`, `dash` e `institute`; o runtime só executava
as duas do Summit; **100% dos turnos viravam transferência**.

**O que muda.** O runtime passa a executar `institute` (vende) e `dash` (consultivo).
`cliente_suporte` continua com o time. Summit segue desligado — o Gate não foi
afrouxado. Além disso: o guardrail passou a entender o formato de preço do catálogo
do Institute; a página oficial do programa virou link validado; `next_route` passou
a existir; e a deduplicação deixou de engolir duas falas iguais da mesma pessoa.

**Impacto.** Hoje o agente não recebe turno algum (zero chamadas em 24 h, última
conversa em 09/09), então publicar **não muda nada sozinho** — o tráfego só volta
quando a Treble for reapontada, e isso é passo separado e reversível num clique.

**Reversão.** Republicar a versão 63, que continua no ar até lá.

### A2. `mind_kit_meta` — Gate deixa de dizer "kit disponível" sobre kit vazio

**Por quê.** Hoje o Gate considera um bloco presente se o provedor devolve qualquer
coisa. `mind_kit_ofertas_b2b` devolve `{ofertas: [], pode_vender: false}` — objeto
vazio, mas objeto. Resultado: `summit_b2b` aparece com kit disponível, e só o flag
de canal o segura. Se alguém reativasse o canal, o agente abriria turno de venda com
zero oferta.

**O que muda.** Bloco obrigatório que declara `pode_vender: false` conta como
ausente. **Fecha, não abre.**

**Impacto medido em produção, sem aplicar:** muda **só** `summit_b2b`
(`canal_incompativel` → `missing_kit`, continua fechado). `institute`, `dash`,
`cliente_suporte`, `concierge_summit` e `summit_b2c` ficam idênticos.

**Reversão.** Restaurar o corpo anterior; está no histórico da migration.

### A3. `treble_agent_start` — devolve `rota_ativa`

**Por quê.** Os playbooks de Institute, Dash e Atendimento mandam usar
`next_route=…` para passar a conversa a outra competência. O App já faz isso; o
WhatsApp não tinha o mecanismo. Para o turno seguinte saber em que competência está,
a função precisa devolver a rota ativa junto com o resto do estado.

**O que muda.** Uma chave a mais no JSON de retorno, lida da mesma coluna de onde já
sai `needs_human`. Aditivo: nenhum consumidor perde nada, nada novo é escrito.

**Reversão.** Remover a chave.

### A4. `agentes.prompts` → `vendas_institute` *(ainda não escrita)*

Não é função, mas é mudança que depende de você — e **é conteúdo comercial**. Está em
`PROPOSTA_PLAYBOOK_VENDAS_INSTITUTE_20261020.md`, com 8 divergências para você
resolver. **Não escrevi a migration**, porque ela congelaria escolhas de valor que
não são minhas.

O motivo de ela existir: o prompt tem 39 preços escritos, 11 dos 17 valores não
existem no catálogo, e **as parcelas do prompt (417/209/167) são barradas pelo
guardrail** — ou seja, obedecer ao prompt transforma a venda em transferência.

---

## B. Qual é a fonte oficial da oferta do Institute — decisão para lançar

**Esta é a decisão que o lançamento precisa, e ela é de uma linha.**

Hoje o agente lê o catálogo de `api.ofertas` / `api.programas`, que são views sobre
o schema `institute`. Funciona: 6 programas, 9 ofertas vigentes, preço à vista e
parcelado, datas, formadoras, FAQ, páginas. O Kit monta certo e o guardrail valida
contra ele.

A regra de 26/09 diz que "preço, oferta, order bump e cupom moram no schema
`catalogo`, e o painel `admin/` é o controle dele". Hoje `catalogo.ofertas` tem
apenas as 14 ofertas do Summit, todas inativas.

**O que precisa do seu ok:** declarar que, para o lançamento, **`institute.*` via
`api.ofertas` é a fonte oficial da oferta do Institute**, e que a regra de 26/09 se
refere ao Summit enquanto a unificação não acontecer.

Se a resposta for sim, o lançamento segue — nada muda no banco. Se for não, o
lançamento espera o item C.

**Consequência operacional de dizer sim, dita com todas as letras:** o painel
`admin/` **não** controla o preço que o agente informa. Mudança de preço do Institute
é feita onde é feita hoje, e o agente reflete na mesma hora — o catálogo é lido a
cada mensagem.

---

## C. Reorganizar a oferta no `catalogo` — projeto próprio, não é pré-requisito

Unificar `institute.*` e `catalogo.*` numa casa só, com o painel controlando as
duas, é **mudança estrutural e de proveniência: D2**. Precisa de justificativa
própria porque:

- mexe em quem é dono do fato (hoje `institute`, passaria a `catalogo`);
- os consumidores atuais (`api.ofertas`, `mind_kit_institute_catalogo`, o site e o
  painel) teriam de migrar juntos;
- enquanto migra, há dois lugares dizendo preço — exatamente o problema que a
  regra de 26/09 existe para evitar.

**Não proponho fazer agora** e não escrevi nada a respeito. Registro como pendência
para você decidir quando, com escopo e prazo próprios. O lançamento não depende
disso: depende de B.

---

## Validação já feita

| o quê | resultado |
|---|---|
| suíte Edge | **479/479** |
| contratos do vendedor | **186/186** (88 guardrail · 16 B2B · 16 falha sem silêncio · 17 truncamento · 79 fluxo completo) |
| fluxo completo no handler real, com dublê de modelo | ingestão, Router, Gate, Kit, preço, link com âncora, continuidade, troca de competência, suporte com o time, reentrega, falha de modelo |
| efeito da migration do Gate | medido em produção **por leitura**, sem aplicar |
| âncoras das páginas | lidas das páginas publicadas, não inventadas |
| conversas com modelo real | **pendente** — depende de A4 validado e da chave |

---

## O que ainda não é verde

1. **A Treble não encaminha ao agente desde 09/09.** Fica no painel dela. Sem isso,
   publicar não muda nada.
2. **Homologação das conversas** com modelo real, para leitura humana.
3. **E2E com entrega no aparelho** — HTTP 200 não é o critério.
4. **`analise_vendas_institute` e `analise_vendas_dash` com prompt vazio.** Ligado o
   tráfego, essas conversas não geram análise nenhuma. É Lane D (#42).
5. **Sem atribuição no Institute**: o link vai sem rastreio, por decisão de 20/10.
   Não haverá número de conversão do agente até alguém pedir.
