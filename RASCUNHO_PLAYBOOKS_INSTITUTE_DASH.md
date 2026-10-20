# Rascunho — playbooks do Institute e do Dash

**Rascunho para discussão. Nada aqui foi aplicado, e nenhuma decisão comercial foi
tomada.** Documento de trabalho: muda a cada rodada nossa.

Ponto de partida combinado em 20/10: construir **a partir do comportamento**,
crescendo de `playbook_institute` (que já está limpo e já tem o formato certo) e
usando `vendas_institute` apenas como fonte de regras a não perder.

Prioridade que rege tudo abaixo, nas suas palavras:

> responder corretamente à necessidade do cliente, esclarecer quando necessário, e
> só recomendar uma oferta quando ela fizer sentido.

---

## 1. O playbook é menor do que parece — três camadas, não uma

O que descobri olhando o Kit vivo: **boa parte do que hoje está escrito nos
playbooks já chega pronto no contexto, a cada mensagem.** Escrever de novo só cria
duas fontes que divergem com o tempo — foi exatamente assim que o
`vendas_institute` acumulou 39 preços que o catálogo não tem mais.

| camada | o que carrega | de onde vem | pode estar no playbook? |
|---|---|---|---|
| **Fato comercial** | preço à vista e parcelado, prazo, datas, carga, duração, modalidade, formadoras, FAQ, páginas, condições, como comprar, contato do time | bloco `institute_catalogo`, lido do banco a cada mensagem | **nunca** |
| **Posicionamento** | o que cada produto é, resolve, não resolve, suas capacidades, profundidade, quando é adequado | bloco `product_intelligence`, idêntico nas duas rotas | **não precisa** |
| **Conduta** | como entender a necessidade, quando perguntar, quando não recomendar, o que nunca dizer, o que fazer quando falta dado | **só o playbook** | **é o playbook** |

### O que o Kit já diz, e que não precisamos reescrever

O `product_intelligence` chega nas duas rotas com um `regra_decisioning` que já é,
literalmente, a sua prioridade:

```
"ICP não determina produto"
"JTBD não determina sozinho o produto"
"interesse em um tema não prova intenção de compra"
"escolher pela transformação buscada, profundidade, escopo e urgência"
"nenhuma recomendação é um resultado válido"
"não apresentar uma solução como versão superior da outra"
```

E traz, por produto, `resolve`, `limites`, `capacidades`, `adequado_quando` e
`resultado_principal` — para Summit, Institute e Dash. Os playbooks atuais repetem
isso em prosa. **Proponho não repetir**: o playbook passa a mandar usar esses
campos, em vez de descrevê-los por fora.

O Dash, em particular, está bem servido: o bloco declara explicitamente
`nao_contem: [preço, lote, parcelamento, checkout, turma, disponibilidade]`. A
proibição de cotar preço no Dash não precisa ser só uma frase de prompt — ela é um
fato do contexto.

---

## 2. Esqueleto proposto — Institute

Base: `playbook_institute` v2, que já abre com "responda primeiro ao que ela pediu,
conecte a necessidade ao eixo adequado e recomende o Institute **apenas quando
houver fit real**".

```
1. QUEM VOCÊ É E O QUE ESTÁ FAZENDO AQUI
   identidade, canal, e a regra de que não finge ser humana

2. A ORDEM DO TURNO            ← o coração, e o que hoje não está explícito
   responda o que foi perguntado
   → só então avalie se há fit
   → só então recomende
   nunca inverta: recomendação não é resposta

3. QUANDO PERGUNTAR EM VEZ DE RECOMENDAR
   o que torna uma necessidade ambígua
   uma pergunta por vez, e só se a resposta mudar a orientação
   o que NÃO justifica perguntar (falta de dado que o Kit já tem)

4. QUANDO NÃO RECOMENDAR NADA
   "nenhuma recomendação é um resultado válido" deixa de ser nota e vira seção
   pergunta informacional, pessoa pesquisando, fit inexistente, tema fora

5. COMO ESCOLHER, QUANDO HOUVER FIT
   a árvore por DOR (vem do vendas_institute, §6 abaixo)
   as distinções que evitam reembolso
   usar `resolve` / `adequado_quando` / `limites` do Kit, não descrição própria

6. COMO FALAR DE DINHEIRO
   leia a oferta do Kit; cite à vista e parcelado como vierem
   nunca multiplique parcela para "provar" total
   prazo só quando a oferta tiver; sem prazo, sem urgência
   fora do catálogo (corporativo, cupom, NF) → contato do time

7. COMO MANDAR A PESSOA PARA A INSCRIÇÃO
   a página do Kit, inteira, inclusive o que vem depois do #

8. OBJEÇÕES
   as do vendas_institute, com a parte factual vindo do Kit

9. O QUE NUNCA PODE SER DITO
   lista fechada, herdada inteira

10. QUANDO NÃO É COM VOCÊ
    Summit → encerrado, encaminhamento
    transformação organizacional → `next_route=dash`
    problema operacional / pedido de humano → time

11. RISCO CONHECIDO
    duas políticas de cancelamento incompatíveis → só o que o checkout promete
```

**A novidade real é a seção 2.** Hoje a ordem "responde → esclarece → recomenda"
está dita de passagem em `playbook_institute` e desmentida na prática pelo
`vendas_institute`, que é um catálogo organizado para empurrar produto. Virar isso
em seção própria, com exemplos do que é inverter a ordem, é o que mais muda a
conversa.

---

## 3. Esqueleto proposto — Dash

`playbook_dash` já está limpo de preço e já é consultivo. O que falta é menos.

```
1. QUEM VOCÊ É E O QUE ESTÁ FAZENDO AQUI

2. A ORDEM DO TURNO
   leitura do problema → implicação → recomendação OU pergunta discriminante
   (já existe; vira explícita)

3. O QUE CARACTERIZA FIT COM O DASH          [herdado, sem mudança]
   o problema é da organização, não do desenvolvimento individual
   cargo não determina fit; a transformação desejada determina

4. O QUE VOCÊ NÃO FAZ                         ← reforçar com o Kit
   o bloco declara `nao_contem: preço, lote, parcelamento, checkout, turma,
   disponibilidade` — a proibição vira fato, não só instrução
   não prometer reunião, contato, proposta ou retorno que o runtime não executa
   (ponto aberto: ver §7)

5. QUANDO É OUTRA COMPETÊNCIA
   desenvolver pessoas → `next_route=institute`
   Summit → encerrado
   suporte → time

6. LIMITES                                    [herdado, sem mudança]
   nada clínico, legal, regulatório ou trabalhista
   diagnóstico organizacional ≠ diagnóstico de pessoas
   sem promessa de resultado
```

---

## 4. O que precisa ser decidido sobre o Dash, e eu não decido

O `playbook_dash` manda "não prometa reunião, contato, proposta, encaminhamento ou
retorno que o runtime não executa". Combinado com a decisão de 20/10 de que o Dash
**responde consultivamente mas não vende**, sobra uma pergunta em aberto:

**Quando alguém com fit real de Dash quiser falar com o time, o que o agente faz?**

Hoje não há resposta. Para o Institute existe o WhatsApp do time no catálogo; para o
Dash, o Kit não traz contato nenhum. As saídas possíveis são de produto, não de
engenharia, e nenhuma delas é minha:

- a conversa termina em `needs_human` e alguém assume;
- existe um contato do Dash a ser publicado no Kit, como o do Institute;
- o Dash só qualifica e a pessoa é convidada a procurar por outro canal.

---

## 5. O inventário — o que não pode se perder do `vendas_institute`

Extração fiel, sem juízo comercial meu. **Carrega** = vai para o playbook novo.
**Sai** = o Kit já entrega. **Parado** = depende de decisão sua.

### Carrega — conduta e regra de venda

| # | regra |
|---|---|
| 1 | Pergunte pela **dor**, não pelo cargo |
| 2 | Árvore de decisão: reage antes de decidir / centraliza → Liderança Consciente · time cala, erro chega tarde → Segurança Psicológica · desengajamento, propósito só no discurso → Engajamento e Significado · as três e lidera pessoas → Certificação · responde pela agenda de bem-estar da organização → Especialização · quer continuidade e acervo → Journey |
| 3 | A distinção que mais evita reembolso: Liderança Consciente trabalha o que acontece **dentro** do líder; Segurança Psicológica, o que o líder **produz** no time |
| 4 | Corte da Especialização: ela **não** é para desenvolver a própria liderança — quem chega assim vai para a Certificação |
| 5 | Três perfis declarados: líderes/gestores/empreendedores · RH e desenvolvimento · consultores e facilitadores |
| 6 | A Certificação entrega as três formações (regra de produto) |
| 7 | Comparar com a soma das avulsas é o argumento mais forte — **com a conta feita na hora, com os valores do Kit** |
| 8 | De Neve é **parceiro**, Mercurio é **participação especial** — nenhum é docente |
| 9 | Ressalvas obrigatórias da MIA: não é analytics, não analisa bases, não produz diagnóstico a partir de pesquisa, não estabelece causalidade, não substitui a faculty nem a decisão da organização |
| 10 | Objeções: está caro · não tenho tempo · e se eu faltar · por quanto tempo tenho acesso · preciso ser líder ou psicólogo · posso fazer só uma (**sempre dizer o escopo**) · diferença entre as duas certificações · a empresa pode pagar · já sou aluno (**não vender por cima, escalar**) |
| 11 | Lista fechada dos 13 "o que não pode ser dito" |
| 12 | Os números institucionais (+7 mil líderes, 86%, +60 multinacionais) são do **Summit**, nunca resultado de formação |
| 13 | Duas políticas de cancelamento incompatíveis: responder só "garantia de 7 dias" e escalar o resto |
| 14 | Três marcas, só o Institute é vendido aqui |
| 15 | Learn · Apply · Reflect |
| 16 | Marcador cru (`%%ACESSO_EM%%`, `%%PRECO_COMPLETO%%`…) sem resolver → **não responda**, pergunte ou escale |

### Sai — o Kit já entrega, a cada mensagem

Carga horária · duração · datas de início e fim · modalidade · preço à vista ·
parcelado · prazo · formadoras por programa · FAQ · páginas oficiais · conteúdo
programático · condições (garantia, contratação anual, escopo de cada contratação) ·
como comprar · WhatsApp do time do Institute.

### Parado — depende de decisão comercial

| # | o que está parado | por quê |
|---|---|---|
| 1 | as 8 divergências de preço e condição | listadas em `PROPOSTA_PLAYBOOK_VENDAS_INSTITUTE_20261020.md` §2 |
| 2 | "o checkout aceita CNPJ" | depende de o Institute vender por Eduzz ou pela página — hoje há 0 `checkout_url` no catálogo |
| 3 | "matrícula automática desligada, entrega manual" | é fato operacional de 17/09; não sei se ainda vale |
| 4 | "existem dois depoimentos nominais e só eles podem ser citados" | os dois não estão no Kit nem no texto — quais são? |
| 5 | bônus da condição Summit (ingresso 2027 + Journey) | a condição expirou em 01/10 e o Kit não traz bônus nenhum |
| 6 | contato do time do **Dash** | ver §4 |

---

## 6. O que eu gostaria de confirmar antes de escrever a prosa

1. **O esqueleto do Institute faz sentido na ordem proposta?** Em especial a seção 2
   como seção própria.
2. **Concorda em não repetir no playbook o que o `product_intelligence` já diz?**
   É o que impede o texto de envelhecer junto com o produto.
3. **Alguma regra do inventário §5 que você quer mudar, e não só preservar?** Eu
   extraí como está; não julguei nenhuma.
4. **O Dash ganha um contato, ou termina em `needs_human`?** (§4)

---

## 7. Como isto vira texto, quando chegarmos lá

Seção por seção, escrita e revista por você antes de ir para a seguinte. Depois:
proposta de migration para `agentes.prompts`, **não aplicada**, junto com a baixa do
`vendas_institute`. Nada vai ao banco sem o seu ok e sem a bateria com modelo real
rodada contra o texto novo.
