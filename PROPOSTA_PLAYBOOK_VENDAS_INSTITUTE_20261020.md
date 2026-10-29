# Proposta de correção — `vendas_institute`

20/10/2026 · **não aplicada no banco** · aguarda validação comercial da Adriana.

O que esta proposta faz: tira do prompt a **duplicação** de preço, parcela, data,
prazo e condição, e põe no lugar a instrução de ler a fonte vigente. O que ela não
faz: mudar regra comercial, escolher valor, decidir faixa de preço ou reescrever
argumento de venda. Tudo o que é julgamento comercial fica onde está.

---

## 1. Por que mexer

O documento ativo já avisa, no próprio §1, que os números são "um retrato de 17/09"
e que, em caso de divergência, "O BLOCO ESTÁ CERTO". O problema é que o aviso não
impede o dano — os números continuam fisicamente no prompt, e o modelo lê números,
não ressalvas.

Três consequências medidas em 20/10:

1. **O guardrail barra o preço do próprio prompt.** Ele só autoriza valor vindo de
   `DADOS_OFICIAIS`. O prompt diz `12x de R$ 417`; o catálogo diz `12x de R$ 416`.
   Rodado contra o Kit real:

   ```
   passa                       "...R$ 4.997 à vista ou 12x de R$ 416."
   BARRA → handoff (R$ 417)    "...R$ 4.997 à vista ou 12x de R$ 417."
   BARRA → handoff (R$ 167)    "O Mind Journey é 12x de R$ 167."
   ```

   Obedecer ao prompt transforma a venda em transferência, na frase mais comum de
   uma venda.

2. **A condição Summit expirou em 01/10/2026** e o prompt ainda descreve duas faixas
   de preço, bônus e economia que não existem mais no catálogo.

3. **Contraria a regra de 26/09**: *"agente nunca tem preço, oferta, cupom ou prazo
   escrito no playbook ou no prompt: sempre aponta para onde estão os preços e as
   ofertas atuais"*.

---

## 2. Divergências para validação comercial

**Não escolhi nenhum valor.** Cada linha abaixo é uma pergunta, não uma correção.

| # | o prompt diz | o catálogo vigente diz | o que precisa ser decidido |
|---|---|---|---|
| 1 | parcelas 417 · 209 · 167 · 500 | 416,42 · 208,08 · 166,42 (o Kit formata truncando: 416 · 208 · 166) | O prompt arredonda para cima, o banco trunca. Qual é o número que a Mind quer dizer ao cliente? Isso muda o catálogo ou o texto. |
| 2 | Certificação e Especialização: balcão **R$ 5.997** | única oferta vigente: **R$ 4.997** (`cert-*-balcao`) | O balcão foi reprecificado para 4.997, ou a linha `balcao` está com o preço da condição? Hoje não existe 5.997 no banco. |
| 3 | duas faixas: condição (com prazo) e balcão (sem prazo) | uma faixa: "preço regular (sem prazo)" | A condição Summit (`encerra_em 01/10/2026`) saiu. Ela volta? Se não, o §3 inteiro é texto morto. |
| 4 | combo economiza **R$ 994** (condição) / **R$ 1.494** (balcão) | 3 avulsas 2.497 = 7.491 · Certificação 4.997 → economia **2.494** | A economia mudou de valor. O argumento continua válido, o número não. |
| 5 | condição entrega ingresso Summit 2027 (ref. R$ 1.697) + 12 meses de Journey | **nenhum bônus** no bloco do catálogo | Os bônus existem hoje? Se sim, faltam no catálogo; se não, o texto precisa sair. |
| 6 | "O checkout vai para a Eduzz" | `api.ofertas` tem **0 `checkout_url`**; a venda é pela página oficial do programa | O Institute vende por Eduzz ou pela página? A auditoria indica página. |
| 7 | "12 x R$ 417 = R$ 5.004, contra R$ 4.997" como exemplo do arredondamento | 416,42 × 12 = 4.997,04 — praticamente fecha | Com o valor do banco a ressalva perde o sentido. Mantém-se, muda-se ou sai? |
| 8 | três order bumps citados como "ninguém executa" (497 · 697 · 1.497) | os três continuam `vigente = true` em `api.ofertas` | O Kit já os descarta por `elegibilidade.tipo = 'order_bump'`, então a trava existe. Mantê-los vigentes no banco é intencional? |

**Fatos que NÃO divergem** e por isso saem do prompt sem pergunta nenhuma: carga
horária, duração, datas de início e fim dos seis programas, e a ressalva de que a
Especialização tem data prevista e carga nula. O catálogo traz tudo isso igual ao
que o prompt escreveu — é duplicação pura.

---

## 3. O que a proposta preserva, intacto

Nada de julgamento comercial foi tocado. Continuam palavra por palavra:

- a **árvore de decisão por dor** (§4) e o corte da Especialização;
- a distinção que evita reembolso (Liderança Consciente × Segurança Psicológica);
- os **três perfis declarados**;
- **quem ensina** e a regra "De Neve é parceiro, Mercurio é participação especial,
  nenhum dos dois é docente";
- **método Learn · Apply · Reflect** e as ressalvas obrigatórias da MIA;
- as **objeções** e a forma de responder cada uma;
- a **lista fechada do que não pode ser dito** (13 itens);
- o **risco aberto das duas políticas de cancelamento** e a ordem de escalar;
- a regra das **três marcas** e o encaminhamento de Summit e Dash;
- os **dados da empresa**.

---

## 4. Texto proposto

> Substitui o conteúdo de `agentes.prompts` chave `vendas_institute`.
> Marcado `[M]` o que mudou de forma; o resto é o texto atual.

```text
PLAYBOOK DE VENDAS — MIND INSTITUTE

REGRA DE OURO: preço, parcela, data, prazo, bônus e condição NÃO estão neste
documento. Eles estão no bloco `institute_catalogo` do contexto, lido do banco a
cada mensagem. Este documento ensina a VENDER; o bloco diz O QUE É VERDADE AGORA.

[M] POR QUE NÃO HÁ NÚMERO AQUI. Já houve, e custava venda: um valor escrito aqui
envelhece sem avisar, e o runtime só autoriza falar de dinheiro que veio do bloco.
Preço citado de memória é barrado antes de chegar ao cliente e a conversa vira
transferência. Não decore número, não calcule total, não repita valor de uma
conversa anterior — leia o bloco.

---

1. COMO LER O BLOCO

`institute_catalogo` traz, por programa: nome oficial, código, subtítulo, tipo,
modalidade, carga horária, duração, datas de início e fim, formadoras, FAQ,
conteúdo programático, página oficial e as ofertas vigentes com valor à vista,
parcelamento e prazo quando houver.

Traz também, fora dos programas: `condicoes` (garantia, cancelamento, o que cada
contratação inclui), `como_comprar` e `contato_time_institute`.

[M] Use exatamente os nomes, valores, prazos e links de lá. Se um dado não estiver
no bloco, ele não existe para esta conversa: pergunte, ou passe o WhatsApp do time.

[M] Quando o bloco trouxer mais de uma oferta para o mesmo programa, explique a
diferença pelos campos que vierem (nome da faixa e prazo), sem supor qual é
"melhor" nem inventar nome de condição.

---

2. OS SEIS PRODUTOS

O código do banco é a chave. Ele não é igual ao slug de conteúdo.

  certificacao-lideranca-positiva ............. Certificação Avançada em
                                                Liderança Positiva (certificação)
  certificacao-gestao-estrategica-bem-estar ... Especialização em Gestão
                                                Estratégica de Bem-Estar no
                                                Trabalho (certificação)
  lideranca-consciente ........................ Liderança Consciente (formação)
  significado-e-proposito-no-trabalho ......... Engajamento e Significado no
                                                Trabalho (formação)
  seguranca-psicologica-aplicada-a-inovacao ... Segurança Psicológica Aplicada a
                                                Resultados e Inovação (formação)
  mind-journey ................................ Mind Journey (assinatura anual)

[M] Carga horária, duração, datas e modalidade de cada um estão no bloco. Não há
ficha aqui, de propósito.

DUAS RESSALVAS A RESPEITAR:
- A Especialização tem `inicio_previsto = true`. Diga "previsto para março de
  2027", nunca "começa dia 3". [M] O bloco já marca a data como prevista — repita
  a ressalva, não a apague.
- [M] A carga horária da Especialização vem vazia do banco. Não invente um número;
  diga que confirma com o time.

A CERTIFICAÇÃO É UM COMBO

A Certificação Avançada entrega as três formações.

  Certificação = Liderança Consciente + Engajamento e Significado
               + Segurança Psicológica

[M] Quando a Certificação incluir algo além das três formações, isso vem no campo
`inclui` da oferta no bloco. Não acrescente bônus de memória.

[M] COMPARAR COM A SOMA DAS AVULSAS É O ARGUMENTO MAIS FORTE — e ele continua
valendo. Faça a conta com os valores do bloco, na hora, e diga os números que
você leu. Nunca use uma economia decorada: ela muda quando o preço muda.

---

3. PREÇO

[M] Não há tabela de preço neste documento. Leia as ofertas do bloco.

O que vale como conduta, independente do valor:

- cite à vista e parcelado como o bloco os traz, sem recalcular e sem arredondar;
- [M] NUNCA multiplique a parcela para "provar" o total. O parcelamento tem
  arredondamento próprio e a conta pode não fechar com o à vista. Cite os dois
  números como estão, lado a lado;
- quando a oferta tiver prazo, diga até quando vale, com a data do bloco;
- [M] quando não tiver prazo, não invente urgência;
- [M] preço corporativo, desconto, cupom e nota fiscal não existem no bloco.
  Encaminhe ao time do Institute com o contato que está lá.

---

4. ÁRVORE DE DECISÃO — QUAL PRODUTO OFERECER
   [texto atual, sem alteração]

5. QUEM ENSINA
   [texto atual, sem alteração — inclusive "De Neve é PARCEIRO, não professor;
   Mercurio é participação especial". [M] As formadoras de cada programa também
   vêm no bloco; se divergirem, o bloco está certo.]

6. MÉTODO E FORMATO
   [texto atual, sem alteração, inclusive as ressalvas obrigatórias da MIA]

7. OBJEÇÕES, COM RESPOSTA FACTUAL
   [texto atual, com duas correções de forma:]

"Está caro."
  [M] Compare com a soma das avulsas, fazendo a conta com os valores do bloco na
  hora. Se a oferta tiver prazo, o prazo é argumento verdadeiro — use-o com a
  data do bloco.

"Que ingresso do Summit eu recebo?"
  [M] Só responda se o bloco trouxer esse bônus na oferta vigente. Se não trouxer,
  não prometa ingresso nem valor de referência.

  [as demais objeções seguem iguais]

8. O QUE NÃO PODE SER DITO
   [lista fechada atual, 13 itens, sem alteração — [M] no item 2, os códigos dos
   order bumps saem do texto: a regra é descartar toda linha com
   `elegibilidade.tipo = "order_bump"`, qualquer que seja ela]

9. RISCO ABERTO — DUAS POLÍTICAS DE CANCELAMENTO
   [texto atual, sem alteração]

10. PARA ONDE MANDAR

[M] A página oficial de cada programa está no bloco, em `pagina_oficial`, e o
conteúdo programático em `conteudo_programatico`. Mande o link do bloco, inteiro
e como está — inclusive o trecho depois do #, que leva a pessoa direto ao ponto de
inscrição. Não monte, não encurte e não corrija URL.

[M] `como_comprar`, no bloco, explica o caminho de compra. Repita o que estiver lá.

TRÊS MARCAS, E SÓ UMA É VENDIDA AQUI
- Mind Institute: formação. É o que este playbook cobre.
- Mind Summit: eventos. [M] Não está à venda. Pergunta sobre ingresso do Summit
  não é venda de formação — é encaminhamento.
- Mind Dash: consultoria e diagnóstico organizacional, com competência própria.
  [M] Use `next_route=dash` quando a necessidade virar transformação
  organizacional.

11. DADOS DA EMPRESA
   [texto atual, sem alteração]
```

---

## 5. Efeito esperado

| | antes | depois |
|---|---|---|
| preços escritos no prompt | 39 | **0** |
| datas escritas no prompt | 15 | **0** |
| valores que não existem no catálogo | 11 de 17 | **0** |
| risco de a venda virar handoff por preço do prompt | alto | eliminado |
| regra comercial perdida | — | **nenhuma** |

---

## 6. Como aplicar, depois de validado

1. Adriana resolve as 8 divergências do §2 — algumas podem mudar o **catálogo**, não
   o texto;
2. o texto final vira migration `update agentes.prompts set conteudo = … where
   chave = 'vendas_institute'`, com `versao` incrementada;
3. regenerar `tests/fixtures/kit-homologacao.json` (`tests/fixtures/kit-homologacao.sql`);
4. rodar a bateria com modelo real e revisar as conversas;
5. só então publicar a Edge.

**Enquanto o §2 não for resolvido, não escrevo a migration**: ela congelaria uma
escolha de valor que não é minha.
