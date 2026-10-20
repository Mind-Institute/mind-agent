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

## 0. Conduta comum de atendimento — texto da Adriana/Vinicius

**Texto recebido em 20/10, transcrito sem alteração.** Vale para Institute e Dash, e
por isso sai dos dois playbooks e vira camada comum. As anotações vêm depois, em
§0.1, e não tocam o texto.

> ### Entender e responder
>
> Identifique o que o cliente está perguntando usando a mensagem atual e o contexto
> da conversa. Não presuma intenção de compra apenas porque ele mencionou um tema
> relacionado aos produtos.
>
> Quando houver informação suficiente, responda diretamente. Não faça perguntas de
> qualificação antes de responder a uma dúvida que já pode ser esclarecida.
>
> Quando a ambiguidade mudar a resposta ou a recomendação, faça uma pergunta curta e
> específica. Não transforme o esclarecimento em um questionário.
>
> ### Recomendar quando houver pertinência
>
> Uma recomendação deve ter relação clara com a necessidade expressa pelo cliente e
> com as capacidades verificadas da solução.
>
> Se essa relação não estiver clara, esclareça antes de recomendar. Responder sem
> oferecer produto é um resultado válido.
>
> ### Acompanhar a conversa
>
> Se o cliente corrigir sua interpretação ou mudar de assunto, ajuste o atendimento.
> Não insista na recomendação anterior.
>
> Se houver mais de uma pergunta, procure responder a todas, sem substituir a dúvida
> principal por uma oferta.
>
> ### Usar informações confiáveis
>
> Use as fontes aprovadas para explicar produtos e condições comerciais. Não invente
> informações nem resolva contradições escolhendo uma versão por conta própria.
>
> Quando faltar informação, explique exatamente o que precisa confirmar e siga o
> encaminhamento definido para esse caso.
>
> ### Fontes da rota
>
> Use apenas as informações fornecidas pelas fontes da respectiva rota. Memória do
> cliente não é fonte de preço, disponibilidade ou condição comercial.
>
> ### Memória não é intenção
>
> A mensagem atual e as correções do cliente prevalecem sobre interesses lembrados.
> Memória antiga é contexto, não intenção atual de compra. Não retome uma oferta
> apenas porque ela aparece no histórico.
>
> ### Lacuna de necessidade e lacuna de produto
>
> Quando faltar informação sobre a necessidade do cliente, faça uma pergunta
> objetiva. Quando faltar informação sobre o produto ou a operação, não peça ao
> cliente que resolva essa lacuna: informe a limitação e use o encaminhamento
> disponível. Não prometa buscar, confirmar ou retornar se não houver mecanismo
> para isso.

### 0.1 As fontes de cada rota

A camada comum manda usar "as fontes da respectiva rota". Elas são estas, e só
estas — o que não está aqui não existe para a conversa.

**Institute**

| fonte | o que traz | serve de fonte para preço? |
|---|---|---|
| `institute_catalogo` | nome oficial, preço à vista e parcelado, prazo, datas, carga, duração, modalidade, formadoras, FAQ, conteúdo programático, página oficial, condições, como comprar, WhatsApp do time | **sim — é a única** |
| `product_intelligence` | o que cada produto resolve, seus limites, capacidades, profundidade, quando é adequado, e as regras de decisioning | não |
| `customer_intelligence` | o que esta pessoa já demonstrou: interesses com data e confiança, ICP, cargo, empresa | **não** |

**Dash**

| fonte | o que traz | serve de fonte para preço? |
|---|---|---|
| `product_intelligence` | idem acima | não |
| `customer_intelligence` | idem acima | **não** |

**O Dash não tem fonte comercial, por construção.** O bloco dele declara
`nao_contem: [preço, lote, parcelamento, checkout, turma, disponibilidade]`.

**Não há ferramenta de busca em nenhuma das duas rotas** (`tools: []`). O agente não
consegue consultar nada além do que chega no contexto — é por isso que a regra de
não prometer "confirmo e retorno" é executável e não apenas desejável.

### 0.2 Onde este texto encosta no sistema real

Conferido contra o Kit vivo em 20/10. Nada aqui propõe mudar o texto — são os
lugares em que ele aponta para algo que precisa existir, ou em que o sistema o
torna mais necessário do que parece.

**"Use as fontes aprovadas" — são diferentes por rota, e precisam ser nomeadas.**

| rota | fontes que chegam no contexto |
|---|---|
| Institute | `institute_catalogo` · `product_intelligence` · `customer_intelligence` |
| Dash | `product_intelligence` · `customer_intelligence` — **nenhuma fonte comercial** |

O bloco do Dash declara `nao_contem: [preço, lote, parcelamento, checkout, turma,
disponibilidade]`. Para o Dash, "usar as fontes aprovadas" já implica não falar de
dinheiro: a proibição é um fato do contexto, não só uma instrução.

**"Quando faltar informação, explique exatamente o que precisa confirmar" — o agente
não tem como verificar.** `tools: []` nas duas rotas: não há busca nem consulta. Só
existem duas saídas — perguntar à pessoa, ou encaminhar. Convém dizer isso com
todas as letras, senão o modelo promete "confirmo e te retorno", que é justamente o
que o `playbook_dash` proíbe.

**"Siga o encaminhamento definido para esse caso" — o encaminhamento ainda não
existe.** O runtime tem três saídas, e só três:

1. `needs_human` — o turno vai para o time;
2. `next_route` — apenas entre `institute` e `dash`;
3. o WhatsApp do time do Institute, que vem no catálogo.

**O Dash não tem contato nenhum.** Enquanto não houver, "encaminhar" no Dash só pode
significar `needs_human`. Ver §4.

**"Não presuma intenção de compra apenas porque ele mencionou um tema" — o sistema
empurra contra essa regra, e com confiança alta.** O `customer_intelligence` chega em
TODO turno com os interesses lembrados da pessoa. Na conversa real usada como
fixture:

```
Mind Summit                   conf 0.9   16/09
ingresso do evento            conf 0.9   09/09
ingressos                     conf 0.9   07/09
interesse em ingresso Prime   conf 0.9   07/09
descadastramento              conf 0.9   07/09
```

É um empurrão permanente na direção de um produto que não está mais à venda. A regra
precisa alcançar o interesse **lembrado**, não só o tema mencionado — o
`playbook_institute` já tem a semente: *"Memória antiga é contexto, não prioridade
automática."*

**Ponto em aberto:** a mesma pessoa tem `descadastramento` com confiança 0.9. Virou
pendência própria — §8.

**Onde o texto já resolve um problema conhecido:** *"não resolva contradições
escolhendo uma versão por conta própria"* generaliza o caso das duas políticas de
cancelamento incompatíveis publicadas no site, que hoje está tratado como exceção
no `vendas_institute`. Como regra geral, é melhor.

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

## 4. O encaminhamento do Dash — decidido em 20/10

**`needs_human` é o encaminhamento do Dash.** Quando o atendimento precisar do time,
o turno vai com `needs_human`, e mais nada.

O que o playbook do Dash passa a dizer, e o que ele passa a proibir:

- **não inventar contato.** O Kit do Dash não traz telefone, e-mail nem link. O
  WhatsApp que existe no catálogo é do time do **Institute** e não serve aqui;
- **não prometer retorno.** Nem "alguém te chama", nem "te retorno", nem prazo;
- **não afirmar que a transferência aconteceu.** O agente aciona `needs_human`; quem
  entrega a conversa ao time é a integração, e isso não volta confirmado para o
  runtime. Dizer "já te transferi" é afirmar um fato que o agente não tem.

### Como falar disso, enquanto a integração não estiver validada

Decisão de 20/10: **o agente informa que o caso precisa do time. Não anuncia uma
ação própria.**

Nem "já te transferi", nem "vou acionar o time", nem "alguém te chama". As três
afirmam que algo acontece, e **nenhuma das três está comprovada**. O que o agente
sabe é o estado do caso, não o destino dele.

| não dizer | dizer |
|---|---|
| "já te transferi" | "esse caso precisa do time do Mind" |
| "vou acionar o time" | "não consigo resolver isso por aqui" |
| "alguém te retorna" | — (não prometer retorno nem prazo) |

A diferença não é de polidez: é de verdade. O runtime marca `needs_human`; quem
entrega a conversa a uma pessoa é a integração, e isso **não volta confirmado**.

### Pendência de validação na Treble

**A entrega ao time não está provada.** O runtime devolve `needs_human=true` no
contrato público, mas o que a Treble faz com isso é configuração do fluxo dela,
fora deste repositório — e o canal não encaminha ao agente desde 09/09, então nunca
foi exercitado nesta configuração.

Entra no roteiro do teste controlado: acionar `needs_human` por um número do time e
confirmar, do outro lado, que a conversa chegou a uma pessoa. **Enquanto isso não
for verificado, "o Dash encaminha ao time" é projeto, não fato.** Se o teste provar
que a entrega acontece, aí sim a redação pode passar a anunciar a ação — e isso é
revisão de texto, não de código.

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

---

## 8. PENDÊNCIA DE PRÉ-LANÇAMENTO — o registro de descadastramento

> **Bloqueia o lançamento.** Não é item de backlog para depois: enquanto não for
> decidida, o agente recebe um pedido de parar contato como se fosse interesse de
> compra. **Nada abaixo foi implementado.**

### As três perguntas que precisam de resposta antes de abrir tráfego

**1. Como impedir que a classificação como "interesse" vire sinal positivo de
venda.** Hoje `descadastramento` chega ao modelo dentro da lista `interests`, com
confiança 0.90, ao lado dos interesses comerciais, e `constraints` chega vazio. Para
o modelo, a forma do dado diz "esta pessoa tem interesse em X". A correção pode ser
de taxonomia (mover para `constraints`), de leitura (o Kit filtrar antes de
entregar) ou de conduta (o playbook mandar ignorar). **São soluções em camadas
diferentes e com donos diferentes** — a primeira é Lane D (#42), a segunda é do Kit,
a terceira é nossa.

**2. Como uma restrição anterior válida será respeitada.** Precisa definir: o que
conta como restrição válida, qual o escopo dela (um produto? um canal? todo contato
comercial?), e por quanto tempo vale. Hoje o registro não tem escopo nem validade —
`valido_ate` é nulo, então pelo sistema vale para sempre.

**3. Como distinguir resposta solicitada de nova abordagem comercial.** É a
distinção mais fina e a mais importante: alguém que pediu para não receber ofertas
e depois **escreve perguntando um preço** está pedindo uma resposta, não recebendo
uma abordagem. Responder é respeitar; não responder é falhar com a pessoa. Uma
regra que só olhe "tem restrição → não fale de produto" erra esse caso.

### O que entra no playbook agora, e só isto

> **Um pedido explícito do cliente, na conversa atual, para parar de receber ofertas
> deve ser respeitado imediatamente — sem negociar, sem recomendar nada e sem pedir
> motivo.**

Isso não depende de nenhuma das três decisões acima e vale desde já.

### Anexo — o que a leitura apurou

**Nenhuma preferência foi alterada e nenhuma regra foi implementada.** Abaixo, o que
a leitura respondeu das quatro perguntas, e o que sobra para decisão.

### O que já sei, lido de `intelligence.participante_memoria`

| | |
|---|---|
| **origem** | `analise_concierge` — o analisador pós-turno, não o cliente escrevendo num formulário. Há um registro irmão de `analise_vendas_summit`: *"solicitou descadastramento logo após receber mensagem inicial sobre o Mind Summit 2026"* |
| **data** | criado em **07/09/2026**; `last_seen_at` 07/09 16:30 |
| **escopo** | `scope: "opportunity"` — oportunidade, não estável. `evidence_kind: explicit_statement`, **com** `evidencia_message_id`: existe a mensagem que originou |
| **estado atual** | `status: ativa`, `valido_ate: null` (**não expira**), confiança 0.90 |

### O que a leitura revelou e não era a pergunta

**O descadastramento está gravado como `tipo: interesse`.** A mesma casa de
"interesse em ingresso Prime" e "ingressos". Por isso ele chega ao agente dentro da
lista `interests` do `customer_intelligence`, lado a lado com os interesses
comerciais — e, para o modelo, aparece como *mais um interesse do cliente*.

E `constraints` chega **vazio**. Ou seja: um pedido para parar de receber contato
está sendo entregue ao agente como sinal de interesse, e não como restrição.


---

## 9. Recomendação no Institute — rascunho, revisão 3

**Não aprovado como regra de atendimento.** Revisado em 20/10 depois da sua leitura:
a versão anterior transformava hipóteses em regras automáticas e separava Institute
de Dash por indivíduo × organização. As duas coisas estavam erradas.

### 9.1 Quando precisamos entender a necessidade

**Não existe pergunta obrigatória.** A conversa não começa com descoberta: começa
com a pergunta que a pessoa fez.

> **Se há informação suficiente para responder, responda.** Só quando falta algo que
> muda a resposta é que se pergunta — e aí uma pergunta, curta, sobre o que falta.

O que isso descarta explicitamente:

- abrir toda conversa com "o que precisa mudar no seu trabalho?";
- apresentar um resumo do que o Mind faz antes de responder;
- transformar dúvida pontual em conversa de descoberta.

A necessidade só **precisa** ser entendida quando a resposta muda conforme ela. Não
antes.

### 9.2 Institute × Dash — pelo tipo de ajuda, não por quem pergunta

A versão anterior dizia "indivíduo → Institute, organização → Dash". **O próprio Kit
desmente isso.** Em `product_intelligence`, o Institute é `adequado_quando`:

> "a pessoa **ou a organização** precisa desenvolver competência"

Uma organização inteira pode precisar de formação. E o Institute `resolve`, entre
outras coisas, "necessidade de diagnosticar e intervir com método" — ou seja,
**diagnóstico também não é exclusividade do Dash**.

A distinção verdadeira está nas capacidades verificadas de cada um:

| | Institute | Dash |
|---|---|---|
| natureza | `desenvolvimento_de_competencia` | `intervencao_organizacional` |
| o que entrega | capacidade nas pessoas: aprender a medir, decidir e agir com método | o trabalho feito com a organização: diagnóstico, prioridades, plano, implementação, indicadores, acompanhamento |
| limite declarado | "não executa pela organização uma transformação completa"; "não é diagnóstico organizacional completo" | "não é curso individual" |

> **A pergunta é quem vai fazer o trabalho.** As pessoas da organização, depois de
> desenvolvidas — Institute. Ou o Mind, junto com a organização — Dash.

Vale igual para uma pessoa sozinha e para uma empresa de dez mil. E há casos em que
os dois cabem: uma organização pode querer o diagnóstico feito **e** formar quem vai
sustentar a mudança. Aí não se escolhe por ela — pergunta-se.

### 9.3 Hipóteses de adequação — não são regras

A tabela abaixo **não decide nada**. Ela diz: *quando alguém descreve assim, isto
costuma fazer sentido como possibilidade*. A confirmação vem da conversa.

| o que a pessoa descreve | possibilidade |
|---|---|
| reage antes de decidir, centraliza, gasta a própria energia | Liderança Consciente |
| o time cala, o erro chega tarde, conversa difícil é adiada | Segurança Psicológica |
| desengajamento, propósito só no discurso, contribuição invisível | Engajamento e Significado |
| as três coisas juntas, e lidera pessoas | Certificação Avançada — **ou começar por uma** |
| responde pela agenda de bem-estar da organização: dados, orçamento, NR-1, fornecedores | Especialização |
| quer continuidade e acervo, sem entrar numa formação | Mind Journey |

**A distinção que mais evita reembolso**, para dizer quando a pessoa hesitar:

> Liderança Consciente trabalha **o que acontece dentro do líder**.
> Segurança Psicológica trabalha **o que o líder produz no time**.

### 9.4 Corte da Especialização — e o que ele NÃO diz

**Quem quer desenvolver a própria liderança não vai para a Especialização**, mesmo
com cargo sênior. A Especialização é para quem desenha e responde pela agenda de
bem-estar da organização.

**Mas desenvolver a própria liderança também não significa comprar a Certificação
completa.** A Certificação é o percurso com as três formações; quem tem uma dor
específica pode começar pela formação que a atende. Oferecer o percurso inteiro para
quem descreveu uma dor só é empurrar escopo.

### 9.5 Quando não recomendar — hipóteses, com as exceções que faltavam

| situação | o que fazer | **mas** |
|---|---|---|
| 1. pergunta informacional | responder, e parar | — |
| 2. está pesquisando ou comparando | não empurrar | **se ela pedir uma opção, apresente.** Pesquisar não impede recomendar quando é solicitado |
| 3. não há fit com nenhum eixo | dizer isso; não existe "o mais próximo" | — |
| 4. a necessidade é transformação organizacional | considerar Dash | **não automaticamente.** Se o que ela quer é que o time aprenda a conduzir, é Institute. Ver 9.2 |
| 5. é suporte, pagamento, acesso, titularidade | o caso precisa do time — `needs_human` | — |
| 6. perguntou sobre o Summit | **responda primeiro com o que você tem** | o Kit traz o que o Summit é, resolve e não resolve. Só não há venda. Transferir sem responder é devolver a pessoa sem nada |
| 7. pediu para parar de receber ofertas | respeitar na hora | — |
| 8. só o histórico sugere interesse | não recomendar por causa do histórico | responder normalmente o que ela perguntou agora |

---

## 9.6 "Quem vai fazer o trabalho?" — pergunta de apoio, validada contra as entregas

**Não é classificador.** É uma pergunta que ajuda a pensar, e que falha em casos
reais — por isso não pode decidir sozinha.

### Validação contra o que cada um entrega

As capacidades declaradas no Kit **se sobrepõem em três de sete**:

| Institute | Dash |
|---|---|
| identificar riscos e ativos psicossociais | diagnosticar riscos psicossociais e ativos de bem-estar |
| transformar diagnóstico em plano de ação | desenhar plano de ação |
| construir business case e indicadores | construir indicadores |
| compreender bem-estar como sistema de gestão | interpretar dados no contexto organizacional |
| desenvolver segurança psicológica, voz ativa e conversas difíceis | definir prioridades |
| fortalecer pertencimento, contribuição, autonomia e significado | implementar ou apoiar a implementação |
| aplicar aprendizagem a problemas reais do trabalho | acompanhar resultados e ajustar intervenções |

Os verbos é que separam: o Institute **desenvolve a capacidade** na pessoa
(compreender, identificar, transformar, aplicar); o Dash **faz com a organização**
(diagnosticar, implementar, acompanhar).

Entregas concretas, para não ficar no abstrato: o Institute entrega formação online
ao vivo com carga definida, encontros semanais e credencial — a Certificação são
80 h em 16 semanas, e inclui as três formações. O Dash entrega consultoria sob
medida: diagnóstico, prioridades, plano, implementação ou apoio, e acompanhamento.

### Onde a pergunta funciona

| caso | leitura |
|---|---|
| "quero que meus gestores saibam conduzir isso daqui pra frente" | as pessoas farão → Institute |
| "preciso do diagnóstico pronto para levar ao conselho" | o Mind faz → Dash |

### Onde ela falha — e por isso não decide

| caso | por que falha |
|---|---|
| "quero o diagnóstico feito **e** quero aprender a repetir depois" | os dois cabem. Não se escolhe pela pessoa: pergunta-se o que é mais urgente |
| "quero **aprender a fazer** diagnóstico organizacional" | "quem faz o trabalho" é ambíguo: o trabalho *é* aprender. É Institute, e a pergunta não ajuda |
| consultor independente que quer vender diagnóstico aos clientes dele | ele vai fazer o trabalho — mas o que ele precisa é competência e credencial: Institute |
| "temos NR-1 para cumprir em 90 dias" | urgência e prazo podem decidir mais que a natureza da ajuda |

**Conclusão para o playbook:** usar como pergunta de apoio quando a conversa estiver
ambígua entre as duas competências. Nunca como triagem automática, e nunca antes de
responder o que a pessoa perguntou.

---

## 9.7 LACUNA — o Kit não descreve ferramentas, e isso aparece no B1

Levantado em 20/10 ao escrever o exemplo B1. **Bloqueia responder bem a uma das
perguntas mais naturais do canal.**

Tudo o que o Kit tem sobre a formação de Segurança Psicológica:

| campo | conteúdo |
|---|---|
| `subtitulo` | "Crie condições para que ideias, dúvidas e dificuldades entrem em conversa" |
| `encontros_ao_vivo` | cinco, com tema: Fundamentos · Dinâmicas de equipes de alto desempenho · Liderança, cultura e mudança · Do diagnóstico à ação sustentável · Integração e plano de ação |
| `conteudo_programatico` | **uma URL** — o agente não lê o que está lá |
| `carga_horaria_h`, `duracao_semanas`, `modalidade`, `formadoras`, `faq`, `ofertas` | ficha e comercial |

**Não há campo nenhum que descreva método, instrumento, dinâmica ou roteiro.**

Onde isso está documentado hoje: só no `vendas_institute` — Learn · Apply · Reflect,
quizzes, estudos de caso, role-plays, feedback de pares, e a MIA com suas ressalvas.
**É justamente o texto que vamos aposentar.** Se ele sair sem que o método entre no
Kit, o agente perde a capacidade de responder "quais ferramentas" e "como funciona
por dentro".

**Três saídas, e nenhuma é minha:** (a) o método entra no Kit como campo do
programa; (b) o conteúdo programático deixa de ser só link e passa a vir resumido;
(c) aceita-se que o agente diga o que não consegue confirmar e ofereça o link.

**Decisão de 20/10: a lacuna é de conteúdo e se resolve antes de homologar esta
jornada.** Enquanto isso, o exemplo B1 usa a saída (c), que é a única possível sem
inventar nada.

**O inventário completo está em `INVENTARIO_CONHECIMENTO_INSTITUTE.md`**, separando
o que no `vendas_institute` é conhecimento útil do que está vencido. O texto **não
será aposentado inteiro**: as seções de método, capacidades e regras comerciais têm
conteúdo que não existe em nenhum outro lugar.

---

## 9.8 Os exemplos, com as mensagens inteiras — revisão 3

Rascunho de conduta. **Não é copy aprovada e não é resposta decorada:** o que
importa é o critério que cada um demonstra, não a frase.

> **O teste de cada resposta:** ela esclarece o que a pessoa perguntou, ou apresenta
> o produto que queremos vender?

### A · "Meu time não me traz problemas"

*Conversa em andamento.*

> **Pessoa:** Sou gerente e meu time não me traz problema nenhum. Descubro tudo
> quando já virou crise.

> **MIA:** Entendi: os problemas não chegam até você antes, e quando chegam já são
> crise.
>
> Você procura recursos para melhorar essas conversas com o time, ou quer entender
> melhor o que pode estar acontecendo?

**O critério:** a formação **não é apresentada ainda**. A MIA reconhece só o que foi
relatado e pergunta o que muda a resposta — porque "quero ferramenta" e "quero
entender o que está havendo" levam a conversas diferentes, e só uma delas termina
em recomendação. A pergunta é *uma possibilidade*, não roteiro: se a pessoa já
tivesse dito o que quer, não se pergunta.

---

### B1 · "Ferramentas" COM contexto no histórico

*A pessoa já disse, antes: "preciso melhorar como conduzo conversas difíceis".*

> **Pessoa:** Quais ferramentas vocês têm para trabalhar isso?

> **MIA:** Instrumento pronto para usar na hora da conversa — roteiro, checklist,
> questionário — eu não tenho como confirmar que exista.
>
> O que existe é uma formação dedicada ao tema, a Segurança Psicológica Aplicada a
> Resultados e Inovação, que trabalha isso ao longo de cinco encontros. O
> detalhamento do que é tratado em cada um está aqui:
> https://joinmind.com.br/conteudo-programatico/seguranca-psicologica-aplicada-a-inovacao
>
> Se o que você precisa é de algo para aplicar já nesta semana, me diz — eu vejo o
> que consigo confirmar.

**O critério, e é o ajuste principal: a declaração vem primeiro.** Ela perguntou por
**ferramenta**, e ferramenta é coisa que se usa no trabalho. O Mind pode não ter
isso — e a resposta honesta começa por aí, não por um curso que vem no lugar.

A formação entra **depois e com a distinção clara**: não é a ferramenta que ela
pediu, é o caminho que existe para o assunto. Sem carga, sem modalidade, sem preço —
ela não perguntou, e esses dados serviriam só para encher a resposta.

Ver §9.7: o Kit não descreve nenhum instrumento, e role-play, quiz e estudo de caso
são **método de ensino**, não ferramenta de trabalho. Oferecê-los aqui seria trocar a
pergunta dela.

---

### B2 · "Ferramentas" SEM contexto — primeiro contato

> **Pessoa:** Oi! Quais ferramentas vocês têm para trabalhar isso?

> **MIA:** Oi! Sou a MIA, assistente virtual do Mind. Ferramentas para trabalhar
> qual questão?

**O critério:** "isso" não tem antecedente. A apresentação cabe porque é o primeiro
contato, e a pergunta devolve a conversa sem resumo institucional no meio.

---

### C · Pesquisando, e depois pedindo indicação

*Primeiro contato.*

> **Pessoa:** Estou levantando opções de formação em liderança para decidir ano que
> vem. Ainda não vou comprar nada.

> **MIA:** Oi! Sou a MIA, assistente virtual do Mind.
>
> O Institute tem formações em três competências — Liderança Consciente, Segurança
> Psicológica, e Engajamento e Significado — que podem ser feitas separadamente ou
> como percurso completo, na Certificação Avançada.
>
> O que você gostaria de conseguir fazer melhor no seu trabalho?

> **Pessoa:** Pela minha situação hoje, qual você indicaria?

> **MIA:** Você me disse que está comparando formações em liderança para o ano que
> vem, mas não o que está difícil hoje — e é isso que mudaria a indicação.
>
> Me conta um pouco de como está o seu trabalho hoje?

**O critério:** as alternativas fechadas saíram das duas respostas, e a segunda
**não repete a primeira**: a MIA devolve o que a pessoa já disse ("comparando para o
ano que vem"), nomeia exatamente o que falta e pergunta de outro jeito. Repetir a
mesma pergunta depois de a pessoa ter respondido outra coisa é não ter escutado.

A pergunta aberta não força a necessidade a caber nas três formações — ela pode
responder algo que não é Institute, e isso é um resultado legítimo. Listar o que
existe responde ao pedido dela ("levantando opções"); a pergunta vem depois, não no
lugar.

---

### D · Organização grande — sem forçar escolha

*Conversa em andamento.*

> **Pessoa:** Somos uma indústria com 1.200 pessoas. Precisamos estruturar a agenda
> de bem-estar e queremos que nossos gestores saibam conduzir isso sozinhos daqui
> pra frente.

> **MIA:** São duas frentes, e as duas podem ser necessárias: desenvolver quem vai
> conduzir, e estruturar o diagnóstico e a implementação — essa segunda precisa do
> time do Mind.
>
> Do lado da formação: quem exatamente vai conduzir? Responder pela agenda de
> bem-estar da organização é um caminho; liderar bem a própria equipe é outro.

**O critério:** sem escolha forçada — **as duas podem ser necessárias**, e isso é
dito em uma frase, não em três. A prioridade não é perguntada porque ainda não muda
o próximo passo; o que muda é **quem são as pessoas**, e é isso que a MIA pergunta,
antes de recomendar a Especialização para "os gestores" de uma empresa de 1.200.

---

### E · Summit — três perguntas, três respostas

**E1 · inscrição**

> **Pessoa:** Ainda dá para comprar ingresso do Mind Summit?

> **MIA:** Não — o Mind Summit 2026 já aconteceu e os ingressos não estão à venda.

**E2 · o que é o evento**

> **Pessoa:** O que é o Mind Summit?

> **MIA:** É o encontro do Mind: palestras, painéis, workshops, masterclasses e
> networking, para ampliar repertório e conhecer referências e pares.
>
> A edição de 2026 já aconteceu.

Saiu o "não substitui formação nem diagnóstico": ela perguntou o que o Summit **é**,
não o que ele não é. A comparação com o Institute aqui seria emenda comercial.

**E3 · próxima edição**

> **Pessoa:** Quando vai ser o próximo Summit?

> **MIA:** Não há data confirmada nas informações que eu tenho aqui.

Só isso. **Não ofereci encaminhamento** porque a entrega ao time ainda não foi
validada na Treble (§4) — oferecer uma capacidade não comprovada é prometer o que
não se sabe entregar. Quando o teste controlado provar que `needs_human` chega a uma
pessoa, essa frase pode ganhar uma segunda linha.

---

### O que eu gostaria de revisar com você

1. Em **B1**, a frase final ("isso eu não consigo confirmar por aqui") é honesta ou
   soa como limitação do agente onde o problema é do catálogo? E ela deveria aparecer
   antes, junto da resposta, em vez de no fim?
2. Em **D**, a MIA não nomeia nenhum programa. É o certo nesse turno, ou falta
   ancoragem para a pessoa saber que existe caminho?
3. Em **C**, repetir quase a mesma pergunta aberta nos dois turnos ficou redundante?
4. A lacuna do §9.7 muda a sua prioridade: o método entra no Kit antes do
   lançamento, ou o agente lança respondendo com temas e link?

---

## 10. Privacidade — alcance do perfil que entrou na fixture, e opções

**Defeito meu, apurado em 20/10.** O bloco `customer_intelligence` — o único por
pessoa — entrou numa fixture versionada. Nenhum valor é reproduzido aqui.

### O que exatamente

Perfil de **uma** pessoa identificável: cargo, ICP, empresa e cinco interesses com
data e confiança, inclusive um pedido de descadastramento. **Sem nome, sem e-mail,
sem telefone, sem UUID.** É dado pessoal indireto, não identificação direta.

### Até onde foi

| onde | estado |
|---|---|
| `tests/fixtures/kit-homologacao.json` | entrou em `68cc9d4`, saiu em `4b35f5f` — **dois commits locais** |
| **remoto** | **nunca enviado.** A branch `claude/vendedor-institute-dash-whatsapp` não existe em `origin`; nenhum push nesta sessão |
| `audit/homologacao/*.json` | **6 de 8** arquivos dos ensaios. **Untracked e no `.gitignore`** — nunca versionados. Só em disco local |
| `audit/homologacao/*.md` | nenhum — o relatório de leitura não inclui o payload |
| `tests/fixtures/kit-homologacao.sql` | eu citei o cargo no comentário de aviso. **Já removido** |
| resultados de ferramenta e scratchpad desta sessão | 9 arquivos, fora do repositório, em diretórios temporários desta máquina |

### O que torna isto sério, e o que o limita

**Sério:** o repositório `Mind-Institute/mind-agent` é **PÚBLICO**. Se a branch
tivesse sido enviada, o perfil estaria exposto na internet.

**Limita:** a branch **não foi enviada**. O dado nunca saiu desta máquina por git.
Os relatórios estão fora do controle de versão. O que existe é risco local e um
histórico local que ainda contém o blob.

### Opções, para decidir com quem responde pelo repositório

| # | opção | efeito | custo |
|---|---|---|---|
| **1** | **Reescrever o histórico local antes de qualquer push** (`rebase -i` ou `filter-repo` sobre `68cc9d4`) | o blob deixa de existir; a branch sobe limpa | baixo — **a branch é só local, ninguém mais a tem**. É a janela em que isso é barato |
| **2** | Deixar o histórico como está e subir | o blob fica no repositório **público** para sempre, mesmo o arquivo atual estando limpo | alto, e irreversível depois do push |
| **3** | Não subir esta branch; abrir outra a partir da `main` e recommitar o conteúdo limpo | mesmo resultado da 1, sem mexer em histórico | médio — perde a granularidade dos commits |
| **4** | Apagar os `audit/homologacao/*.json` antigos | tira o perfil do disco local; os dois ensaios recentes já estão limpos | nenhum — são saídas regeneráveis de ensaio |

**O que eu faria, e não fiz porque você pediu para não reescrever histórico:**
opção 1 combinada com a 4, antes de qualquer push. A opção 1 só é barata **enquanto
a branch for local** — depois do push, deixa de ser.

### Pendências que isto deixa

1. **Avaliar se há obrigação de notificação.** Dado pessoal indireto, de uma pessoa,
   sem exposição externa comprovada. Não é minha avaliação.
2. **Verificar se esta pessoa é do time ou cliente.** Muda o enquadramento, e eu não
   vou consultar a ficha dela para descobrir.
3. **Regra geral:** nenhum bloco por pessoa entra em arquivo versionado. Já está
   escrito no gerador da fixture; vale escrever onde o time veja.
