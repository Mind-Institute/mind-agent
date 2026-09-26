# Plano passo a passo: todas as ofertas no catalogo, editáveis no painel

26/09/2026 · Status: em execução — Passo 3 aplicado em 26/09 (ver a atualização abaixo)

## Atualização de 26/09, noite: as respostas da Adriana

O que ela decidiu, e o que muda neste plano:

- **Tudo no `catalogo`:** *"no schema catálogo deve organizar as tabelas de preço, oferta, order bump, cupom — todas devem estar neste schema, embora não necessariamente na mesma tabela"*, e *"todas as infos importantes deste schema devem ser espelhadas e editáveis via painel"* — o painel é o controle do schema.
- **Checkout próprio (InfinitePay) não prende nada:** *"não tem nada relevante ainda ... podemos migrar qualquer coisa relacionada sem medo de quebrar ou deletar para reconstruir do zero"*. As funções do checkout próprio não precisam mais de paridade; o que for do catálogo (cupons, bumps) muda de casa sem esperar.
- **Bumps não saem do ar:** *"não tira bumps do ar mas ... vamos aproveitar para migrar pro lugar certo"*. A decisão 1 (desligar os 3 bumps) cai.
- **Nada é desligado à mão; a virada vem antes de 30/09:** *"não acho que temos que desligar nada, vamos ter migrado antes disso"*. A decisão 2 (agendamento às 00h00) cai; o Passo 5 é antecipado para antes de 30/09 23h59.
- **Eduzz:** ela troca os preços lá (decisão 3).
- **Agente sem preço escrito:** *"nunca agentes devem ter preços escritos hard coded, mas sempre apontar para onde estão preços e ofertas atuais"* — decisão 4 aprovada, e virou regra no `CLAUDE.md`.
- **Passo 3 aprovado** ("3- ok"); **histórico importante** (Passos 6 e 7 entram); **Passo 8 ok**.
- **Os sites leem direto, sem cópia por cron:** na virada, as mesmas views `api.*` passam a ler o `catalogo`, numa transação só, com a paridade conferida. Uma cópia por cron atrasaria e poderia divergir sem aviso.

**Ainda com ela, para a virada:** (a) dar "vale até" aos 4 textos e às 4 perguntas do FAQ da Condição Summit, para saírem sozinhos às 23h59 de 30/09; (b) tirar o bump da lista de preços da página (ele continua disponível ao checkout pela view de bumps), para a seção "Avulsas" não mostrar o bump como preço depois de 30/09.

**Feito em 26/09 (Passo 3, com os cupons):** migration `20260926201053_catalogo_ofertas_forma_historico_e_cupons` — a forma das 4 tabelas de oferta, `checkout.cupons` → `catalogo.cupons` (as 3 funções que citavam a tabela pelo nome foram regravadas), 3 produtos de categoria do Summit 2026 e 2 do Summit 2027 (desligados, sem venda, sem funil), e o histórico do Summit 2026: 14 ofertas, 28 preços, 3 upgrades e 3 cupons, copiados dentro do banco. Contratos `CATALOGO_OFERTAS_OK` e `CATALOGO_OK` em produção, sem rastro. O site e o agente não mudaram (`api.ofertas` segue com as mesmas 14 linhas).

**Cronograma novo:** Passo 2 (tela "Ofertas" lendo o `catalogo`) em 27/09; Passo 4 (edição) em 28/09; ensaio da virada em 28/09; Passo 5 (virada) na madrugada de 29/09; Passos 6 e 7 depois.

*Este plano saiu só de leituras. Rodei SELECT no banco `ymnmotgglsrxmjmonwjz` e li este repositório em `d75588e` e os dois sites em `238c313` (Institute) e `acbbd01` (Join). Nada foi alterado. Documentos que acompanham este: o plano anterior, [`PLANO_PRECOS_CATALOGO.md`](PLANO_PRECOS_CATALOGO.md), e o mapa dos sites, [`FONTE_DA_VERDADE_SITES.md`](FONTE_DA_VERDADE_SITES.md).*

## É possível, sim

Todas as ofertas do Mind cabem nas 4 tabelas de oferta do `catalogo` que você desenhou em 13/09, inclusive as do Institute e as antigas. Conferi hoje três coisas:
- as 4 tabelas estão vazias;
- nenhuma view nem função lê delas;
- o schema `catalogo` não é aberto a quem visita os sites.

Por isso dá para carregar tudo ali sem risco. O único cuidado de verdade é o site do Institute. Ele lê preço o tempo todo e, durante a troca, não pode sair do ar nem mudar de preço.

O plano de ontem (etapas E0 a E9) já levava as ofertas do Institute para o catálogo, mas deixava a edição pelo painel para o fim. Com o seu pedido de hoje, mudam três coisas:

1. **O histórico entra.** As 28 ofertas do Summit 2026 e as ofertas do Institute que vencem em 30/09 ficam no catálogo, só para consulta. Os cadastros antigos da Eduzz também podem ser ligados ao histórico, se você quiser.
2. **O painel vem primeiro e vira o lugar de editar.** Você vê o que está no ar antes de qualquer mudança de estrutura. Na virada, o `/admin` do Join deixa de editar ofertas.
3. **A mudança de estrutura é pequena.** Depois de 30/09, os bumps e a condição viram passado, e os detalhes deles cabem no registro de origem de cada linha. A aprovação D2 fica em 4 mudanças pequenas, mais o bônus editável, se você quiser.

**O painel não muda o preço cobrado.** Quem cobra é a Eduzz, e o link de compra de cada produto está fixo no código dos dois sites. O painel controla o que o site e o agente mostram. O preço na Eduzz continua sendo trocado à mão, e o painel avisa quando os dois diferem.

Três fatos conferidos hoje põem a virada de 30/09 na frente de tudo:

- **Seção "Avulsas".** A partir de 30/09 às 23h59, a seção "Avulsas" da página da Certificação passa a mostrar preço errado nos dois sites, se nada for feito. Sem condição valendo, o código pega a oferta mais barata da lista:
  - na Liderança Consciente, pega um bump (R$ 1.497);
  - nas outras duas formações, pega a condição vencida, com o bônus e o prazo de 30/09.
- **Textos e FAQ da condição.** Continuam ligados depois do prazo.
  - No site, duas respostas do FAQ passam a mostrar "—" no lugar do preço e do prazo.
  - O agente continua recebendo os 4 textos da condição e as respostas que prometem o ingresso de 2027.
- **Eduzz.**
  - São 6 cadastros com preço de condição, porque a Liderança Positiva tem dois. Eles continuam cobrando R$ 4.997 e R$ 1.997 até alguém trocar o preço.
  - A cópia da Eduzz no nosso banco está parada. A última leitura da Eduzz foi em 24/09, às 21h02.

## Como vai ficar no fim

- **Uma casa só.** Toda oferta do Mind, de qualquer vertical, mora nas 4 tabelas de oferta do `catalogo`. Lá ficam preço, parcelas, prazo, liga/desliga, bônus (se você aprovar), o que vem junto e o que a oferta exige. Cada linha guarda de onde veio. As tabelas antigas ficam congeladas e depois saem.
- **O histórico mora junto, só para consulta.** Entram o Summit 2026 (lotes, preços de grupo e upgrades) e as ofertas encerradas do Institute.
- **Quem lê.**
  - Os dois sites e o agente continuam lendo pelas mesmas portas de hoje.
  - A porta de preços (`api.ofertas`) passa a entregar só o que está valendo.
  - A porta que libera o acesso de um pedido pago continua vendo tudo.
  - O histórico nunca chega ao site nem ao agente.
  - O site do Summit fica fora, porque lê outro projeto.
- **Quem edita.** Você e quem você der papel, pelo painel. Dá para criar rascunho, mudar preço e prazo, pôr no ar, tirar do ar, prorrogar e duplicar. Cada salvamento guarda quem mudou, quando, e como estava antes e depois. O `/admin` do Join deixa de editar ofertas.
- **O que você vê.**
  - O bloco "Agora no site", com o preço que o site mostra para cada produto, até quando vale, o que entra depois e o bônus.
  - A lista de ofertas, com filtros por situação, vertical e produto.
  - A Eduzz ao lado, com a hora da última leitura, e avisos quando algo diverge.
- **O que continua à mão:** o preço cobrado na Eduzz.
- **O Summit 2027** nasce direto no catálogo quando você abrir a venda.

### Palavras deste plano

- **Porta:** a view ou função por onde o site ou o agente lê o banco. Exemplo: `api.ofertas`.
- **Bump:** oferta extra que aparece dentro do checkout de outro produto.
- **Código vendável:** o código que links, pedidos e acessos usam para identificar um item.
- **Veio de:** o registro, em cada linha, de onde ela veio. Guarda a linha original inteira.
- **Casa:** a tabela onde a oferta mora, seja a antiga do Institute, seja o catálogo.
- **Contrato:** teste que roda no banco real e desfaz tudo no fim, sem deixar rastro.
- **Transação:** um pacote de mudanças que entra inteiro ou não entra.
- **D2:** a sua aprovação para mudança de estrutura do banco.

### O que cada situação quer dizer (depois da virada do Passo 5)

| Situação | O que é | O site mostra? | O agente recebe? (chat da web) | Dá para mexer no painel? |
|---|---|---|---|---|
| No ar | Ligada e dentro do prazo | Sim | Sim | Sim, com confirmação |
| Agendada | Ligada, mas o prazo ainda não começou | Não | Não | Sim |
| Encerrada | Ligada, mas o prazo já passou | Não | Não | Sim, inclusive prorrogar |
| Desligada | Tirada do ar, ou rascunho que nunca foi ao ar | Não | Não | Sim |
| Histórico | Importada do Summit 2026, ou oferta de teste | Não | Não | Não; só duplicar |

Até a virada, ofertas agendadas e encerradas ainda chegam ao site, e cada parte da página decide sozinha o que mostrar. É daí que vem o erro da "Avulsas".

## Os passos num relance

| # | O que você ganha | Precisa do seu OK? | Quando |
|---|---|---|---|
| 1 | A virada de 30/09 sem preço nem texto errado | Sim (comercial e conteúdo) | Já; a parte agendada roda às 00h00 de 01/10 |
| 2 | Tela "Ofertas" com o que está no ar e a Eduzz ao lado (só leitura) | Não | Já, antes de 30/09 |
| 3 | A casa nova com forma e com o histórico do Summit 2026 | Sim (D2 e 3 produtos) | Já |
| 4 | O painel pronto para editar | Não para construir | Já |
| 5 | A virada: o Institute passa a ler o catálogo e você edita | Sim (D2 e site) | Depois de 01/10 |
| 6 | Cadastros antigos da Eduzz no histórico (opcional) | Sim | Quando você quiser |
| 7 | Setembro reconstruído (opcional) | Sim | Recomendo não agora |
| 8 | O Summit 2027 no catálogo | Sim (D2) | Antes de abrir a venda de 2027 |
| 9 | Aposentar as tabelas velhas | Sim (apaga dados) | Uns 30 dias depois do Passo 5 |

Cada passo é um PR próprio e segue esta ordem:
1. testes e build verdes;
2. merge, que aplica a migration e publica o painel;
3. o contrato roda no banco real, contra o que foi aplicado;
4. se a função do painel mudou, publicação à mão, comparada com a versão no ar;
5. checkpoint registrado;
6. só então começa o próximo passo.

O que mexe no agente do Institute é avisado na issue #40.

## Passos

### Passo 1: A virada de 30/09 sem preço nem texto errado

- **O que muda**
  - **Banco, logo no merge:** desligar os 3 bumps:
    - o Journey dentro do checkout da Certificação;
    - o Journey dentro do checkout de formação;
    - a Liderança Consciente dentro do checkout do Journey.

    Só o checkout próprio usava os bumps, e ele não recebe pedido desde 17/09. Hoje nenhuma página os mostra como preço.
  - **Banco, às 00h00 de 01/10 (horário de Brasília):** um agendamento que roda uma vez só desliga:
    - as 5 ofertas da Condição Summit;
    - os 4 textos da condição (`oferta.condicao-summit`, `oferta.duas-faixas`, `oferta.journey-e-bonus` e `oferta.prazo`);
    - as 4 perguntas do FAQ da Certificação que falam da condição:
      - "Posso fazer somente uma formação?";
      - "O Journey está incluído na formação avulsa?";
      - "O Unpacking é uma aula da Certificação?";
      - "Qual ingresso recebo?".

      As três primeiras continuam sendo boas perguntas. Se você mandar o texto novo delas até 29/09, elas voltam reescritas no mesmo horário. Se não mandar, voltam quando você mandar.
    - **Proteções do agendamento:**
      - O relógio do agendador do banco está em UTC, então a hora vai escrita como 03h00 UTC. Escrita como 00h00, ele dispararia às 21h de 30/09.
      - Ele só age se as ofertas já tiverem vencido. Se você prorrogar a condição antes, o agendamento é refeito junto com a prorrogação.
      - Ele grava a hora da mudança, porque a tabela não tem gatilho que faça isso sozinho.
      - Ele se apaga depois de rodar, porque o agendador não tem ano e rodaria de novo em 2027.
      - Se o PR entrar depois da hora, a própria migration desliga tudo na hora.
  - **Agente (decisão 4):** tirar do playbook `vendas_institute` a tabela de preços, que o próprio playbook chama de "retrato de 17/09", e o trecho da condição. No lugar fica "use o bloco do catálogo". O texto é seu.
  - **Eduzz, fora do banco (decisão 3):** trocar o preço dos 6 cadastros para o de balcão.
  - **Documentos:** corrigir a frase do mapa dos sites que diz que o site passa sozinho ao preço de balcão.
  - **Site:** a partir de 00h00, o preço de balcão aparece em todas as partes, inclusive na "Avulsas", e o FAQ deixa de mostrar "—".
    - Há um custo. Um link antigo de e-mail com o código da condição (`/checkout/<código>` do Join) passa a abrir a página inicial do Join em vez do checkout. É o que o site faz com qualquer oferta desligada.
  - **Agente (chat da web):** deixa de receber os textos e as perguntas da condição. O bloco do catálogo já passa sozinho ao preço de balcão. No WhatsApp, a rota do Institute ainda transfere a conversa para o time.
- **O que você vê depois:** em 01/10, os preços ficam assim:
  - Certificação e Especialização: R$ 5.997;
  - formações: R$ 2.497;
  - Journey: R$ 1.997, sem bônus.

  Se o Passo 2 já estiver no ar, o painel mostra as 5 condições e os 3 bumps como "Desligada".
- **Precisa do seu OK?** Sim. O passo mexe em oferta e preço (gate comercial) e em conteúdo seu (textos, FAQ e playbook). São as decisões 1 a 4.
- **Depende de:** nada. Só tem prazo: o merge precisa acontecer antes de 30/09 às 23h59.
- **Quando:** já. A parte agendada roda às 00h00 de 01/10.
- **Como conferimos**
  - **No PR:** um contrato confere duas coisas:
    - existe exatamente um agendamento, na hora certa e com o comando certo;
    - a porta do site passou de 14 para 11 ofertas, sem os bumps.
  - **Às 00h05 de 01/10, pela porta real** (não pela simulação):
    - são 6 ofertas, uma por produto, todas valendo e nenhuma com prazo;
    - em cada formação, a primeira da lista é a oferta de balcão;
    - os textos e as perguntas estão desligados;
    - o agendamento sumiu.

    A Eduzz é conferida na própria Eduzz, porque a nossa cópia está parada.
- **Como desfaz**
  - Antes da hora: apagar o agendamento, com um comando só. Cada bump volta a ligar com uma linha.
  - Depois da hora: religar as ofertas (elas voltam já vencidas), os textos e as perguntas.

### Passo 2: "Ofertas" no painel, só leitura, com a Eduzz ao lado

- **O que muda**
  - **Banco:** uma função nova, só de leitura e fechada: só o sistema chama.
    - Ela junta as 16 ofertas do Institute, as 28 do Summit 2026 e a casa nova, que hoje está vazia.
    - O que está valendo vem da própria porta do site, lida dentro da função.
  - **Banco, dados:** 7 linhas na tabela de ligação `checkout.produto_externo`, que já existe, está vazia e ninguém lê.
    - Elas ligam os 6 produtos do Institute 2027 aos 7 cadastros da Eduzz.
    - A Liderança Positiva tem dois cadastros, e os dois ficam ligados. Quando os preços deles diferirem, a coluna mostra "vários".
  - **Painel:** um item "Ofertas" no menu (decisão 9). Diferente da tela de demonstração retirada em 26/09, esta só mostra dado real. Ela tem:
    - **o bloco "Agora no site":** para cada produto, o preço que o site mostra, até quando vale, o que entra depois, o bônus e o prazo dele. Ao lado, o preço de lista na Eduzz, com a hora da última leitura da Eduzz;
    - **a lista**, com filtros por vertical, produto, situação e casa, e o detalhe de cada oferta, com a linha como está no banco;
    - **uma simulação de 01/10 às 00h01**, marcada como simulação;
    - **avisos para estes casos:**
      - a "Avulsas" vai mostrar outra oferta;
      - texto ou pergunta do FAQ da condição continua ligado depois do prazo;
      - há preço escrito no playbook do agente;
      - a Eduzz difere do site, agora ou depois do prazo;
      - a última leitura da Eduzz tem mais de um dia;
      - houve venda paga abaixo do preço de lista e sem cupom. O aviso só diz sim ou não, sem dado de venda.
  - **Função do painel (`mindagent-catalogo`):** passa a servir ofertas. É publicada à mão depois do merge e comparada com a versão no ar.
  - **Site e agente:** nada muda.
- **O que você vê depois**
  - **Hoje:**
    - Certificação e Especialização a R$ 4.997 e formações a R$ 1.997, todas na Condição Summit até 30/09 às 23h59;
    - Journey a R$ 1.997, com o ingresso do Summit 2027 como bônus até a mesma hora;
    - Eduzz "igual" nos 6 produtos.
  - **Na simulação de 01/10:** R$ 5.997, R$ 2.497 e R$ 1.997. Se ninguém trocar o preço na Eduzz, aparece "Eduzz diferente" em 5 produtos (6 cadastros).
  - **Summit 2026:** aparece como histórico, com as 28 ofertas desligadas.
  - **Leitura da Eduzz:** a de 24/09 às 21h02, já com o aviso de que está velha.
- **Precisa do seu OK?** Não. A tela só lê, a função nasce fechada e as 7 ligações ficam numa tabela que existe e que ninguém lê. Só o lugar no menu é escolha sua (decisão 9).
- **Depende de:** nada. Para você ver a tela em `admin.minddash.pro`, falta a configuração de origem e de login que está com você desde 26/09. Não conferi se ela já foi feita.
- **Quando:** já, logo depois do Passo 1. O ideal é antes de 30/09, para você acompanhar a virada.
- **Como conferimos**
  - Um contrato no banco compara sempre com as tabelas de origem, nunca com valores escritos no arquivo. Ele confere:
    1. as contagens batem com as fontes: 16, 28 e 0;
    2. a situação de cada oferta é igual à da porta do site;
    3. há uma linha "o site usa esta" por produto;
    4. o número de ofertas que o agente recebe por programa é igual ao do bloco do agente;
    5. a coluna Eduzz é igual ao preço da cópia, cadastro a cadastro;
    6. com o relógio simulado em 01/10 às 00h01, as 5 condições aparecem encerradas e o aviso da "Avulsas" acende;
    7. só o sistema executa a função.
  - Os testes do painel e da função passam, e o build fica verde. Entram também:
    - a semente de demonstração, com valores inventados;
    - a troca do teste que hoje exige que `/ofertas` não exista.
  - O preview abre em modo demonstração, então a conferência com dado real é feita em produção.
- **Como desfaz:** reverter o PR (a tela some), voltar a função à versão anterior e apagar as 7 ligações.

### Passo 3: A casa nova ganha forma e recebe o histórico do Summit 2026

- **O que muda**
  - **Banco, estrutura (D2, decisão 5)**, nas 4 tabelas vazias:
    1. **Código vendável em cada linha de preço, único.** Assim uma oferta pode cobrir vários produtos, como você pediu em 13/09: *"são 3 produtos diferentes sendo ofertados na mesma oferta que o Lote 7"*. E cada item continua com o código que links, pedidos e acessos usam.
    2. **"Veio de" em cada linha.** Guarda a linha original inteira e de onde ela veio. Cada linha antiga entra uma vez só. É também a cópia que permite aposentar as tabelas antigas no Passo 9 sem perder nada.
    3. **Tipo "condicional"**, para bump e upgrade. A exigência ("só vale se tiver X") já tem casa, a tabela `oferta_requer`.
    4. **Produto com preço não pode ser apagado.** Hoje, apagar um produto apagaria os preços dele junto, inclusive o histórico.
    5. **Bônus editável, se você aprovar:** nome, descrição, detalhe, nota, valor de referência, início e fim do bônus.
       - É o que o site mostra no cartão do bônus e o que comanda a contagem regressiva.
       - O bônus continua tendo de ser um produto do catálogo. Um bônus que ainda não é produto, como o ingresso do Summit 2027, precisa virar produto antes.
    - **Arrumação opcional, sem efeito visível:** limpar permissões antigas dessas tabelas. Hoje essas permissões não alcançam ninguém, porque o schema não é aberto a visitantes.
  - **Banco, dados:**
    - **3 produtos novos, de histórico:** Mind Summit 2026 Mind, VIP e Prime.
      - Entram desligados, sem venda e com a categoria preenchida.
      - Entram sem ligação com o funil do HubSpot. Sem esse cuidado, negócios do HubSpot do Summit passariam a cair neles.
    - **As 28 ofertas de 2026 viram 14 ofertas com 28 linhas de preço**, todas desligadas:
      - 7 lotes, cada um com Mind, VIP e Prime (conferi que, em cada lote, as 3 categorias têm o mesmo prazo);
      - 4 preços de grupo do VIP;
      - 3 upgrades, cada um exigindo a categoria de origem.
    - **Os códigos ganham o final "-2026".** Assim os códigos de lote ficam livres para 2027.
    - **O parcelamento de 2026 fica só como texto, no "Veio de".** Em 10 dos 21 textos, o "12x de R$ …" dá menos que o preço à vista, e o catálogo recusa isso.
    - **A carga é copiada direto da tabela antiga, dentro do banco.** Nenhum valor fica escrito no arquivo, que vai para um repositório público. As notas de procura dessa tabela falam de vendas.
  - **Painel:**
    - o Summit 2026 passa a vir do catálogo, marcado como histórico;
    - o Catálogo mostra os 3 produtos novos, desligados;
    - aparece um aviso se a tabela antiga do Summit mudar depois da cópia. A função que a regravava a cada 30 minutos está desligada, mas continua publicada.
  - **Site e agente:** nada muda. O agente do Summit continua lendo a tabela antiga, que não tem oferta ativa.
- **O que você vê depois:** no filtro "Histórico", o Summit 2026 lote a lote, com Mind, VIP e Prime, preço e prazo. No detalhe de cada oferta, a linha como estava no banco.
- **Precisa do seu OK?** Sim. É estrutura nova (D2, decisão 5) e são três produtos novos no seu vocabulário (decisão 6).
- **Depende de:** nada.
- **Quando:** já.
- **Como conferimos**
  - **Contrato de forma:** o que é proibido é recusado. Isso inclui:
    - código vendável repetido;
    - apagar produto que tem preço;
    - parcelado abaixo do à vista;
    - oferta base com prazo;
    - a mesma linha antiga entrando duas vezes.
  - **Contrato de carga**, comparando com a tabela antiga:
    - as 28 linhas viram 28 preços, com valor e prazo iguais;
    - nenhuma oferta fica ativa;
    - os produtos novos ficam desligados e sem funil.
  - Nenhuma view nem função lê as 4 tabelas, a não ser a leitura do painel.
  - O contrato de permissões das funções passa.
- **Como desfaz:** apagar o que veio do Summit 2026 e os 3 produtos, já que nada mais aponta para eles. Depois, tirar as colunas e voltar as regras. As tabelas voltam a ficar vazias.

### Passo 4: O painel pronto para editar

- **O que muda**
  - **Banco:** uma função nova de escrita, fechada (só o sistema chama), no mesmo molde da do Catálogo:
    - confere o seu papel de novo a cada salvamento;
    - tem trava de versão: se duas pessoas salvarem ao mesmo tempo, a segunda é avisada. Mexer num preço também conta como mudança da oferta;
    - grava o antes e o depois no registro de auditoria que já existe;
    - nunca apaga nada.
  - **Ações:**
    - criar: a oferta nasce desligada, como rascunho;
    - editar;
    - pôr no ar;
    - tirar do ar;
    - prorrogar, inclusive oferta vencida, com confirmação, como foi feito em 18/09;
    - duplicar: copia preços, bônus e exigências; prazo e códigos ficam em branco.
  - **Regras.** Cada uma recusa com uma frase clara:
    - o preço não pode ser negativo, a parcela tem de fechar com o preço à vista, o prazo tem de ser coerente e oferta base não tem prazo;
    - só vai ao ar oferta com preço e com prazo aberto;
    - histórico importado é só leitura por uma marca explícita, e não por estar encerrado. Uma oferta sua que venceu continua editável;
    - um código novo não pode repetir código de oferta, programa ou produto do Institute, porque a virada vai carregá-los;
    - **por produto**, três regras:
      - no máximo uma oferta sem prazo no ar. Com duas, a página mostra a mais cara e o agente cita a mais barata;
      - nenhuma oferta condicional no ar enquanto nenhuma página usar bump;
      - um aviso se duas ofertas com prazo valerem ao mesmo tempo;
    - "Pôr no ar" só destrava para produto que alguém lê: os do Institute depois do Passo 5, os do Summit 2027 depois do Passo 8. Antes disso, pôr no ar não chegaria a ninguém.
  - **Painel:**
    - formulário de edição;
    - confirmação com o antes e o depois: "o site passa a mostrar R$ X no lugar de R$ Y em até 1 minuto; a Eduzz continua cobrando R$ Z";
    - botões de ação;
    - histórico de alterações de cada oferta.
  - **Função do painel:** passa a aceitar criar, pôr no ar e tirar do ar. É publicada à mão.
  - **Site e agente:** nada muda.
- **O que você vê depois:** os botões Criar, Editar, Duplicar e Prorrogar. Já dá para preparar rascunhos, como a próxima condição do Institute cobrindo vários produtos numa oferta só. O botão "Pôr no ar" aparece travado, com o motivo, até a virada.
- **Precisa do seu OK?** Não para construir: é uma função nova e fechada, numa casa que já existe. Quem pode fazer o quê é decisão sua (decisão 7).
- **Depende de:** Passo 3.
- **Quando:** já.
- **Como conferimos**
  - **Contrato:** cada tentativa proibida é recusada com a frase certa, sem deixar rastro nem registro. Isso vale para:
    - código repetido ou reservado;
    - prazo invertido;
    - parcela que não fecha;
    - oferta base com prazo;
    - pôr no ar sem preço ou já vencida;
    - editar histórico;
    - segunda oferta sem prazo no ar;
    - conflito de versão;
    - papel sem permissão.
  - **Testes do painel:**
    - o rascunho não sai ligado;
    - o painel manda só o que mudou;
    - pede confirmação antes de salvar;
    - num conflito, abre o aviso.
  - A função também tem testes próprios.
- **Como desfaz:** reverter o PR e voltar a função. Os rascunhos ficam desligados e não chegam a ninguém.

### Passo 5: A virada: o Institute passa a ler o catálogo e você edita no painel

- **O que muda.** Tudo acontece no banco, numa transação só: entra tudo ou nada.
  - **Carga das 16 ofertas do Institute, uma por código antigo**, com o mesmo nome, descrição, preço, parcelas, prazo e liga/desliga. É o jeito de a troca sair idêntica para o site:
    - 6 no ar: os preços de balcão e o Journey;
    - 8 desligadas: as 5 condições e os 3 bumps;
    - 2 testes, como histórico. O de R$ 1 do Journey entra assim para ninguém pô-lo no ar por engano, porque a página do Journey mostraria R$ 1. O teste sem produto entra só como registro.
    - Entram também:
      - os 2 bônus que liberam o Journey, com o texto, se o bônus editável for aprovado;
      - as 5 regras dos bumps, como exigência de carrinho.
    - Os 6 bônus do ingresso 2027 ficam no "Veio de", porque o ingresso não é produto e todos esses bônus já venceram.
  - **As 3 portas do site passam a ler o catálogo**, com as mesmas colunas e os mesmos tipos:
    - `api.ofertas` passa a entregar só o que está valendo (decisão 8);
    - `api.bump_regras` não muda de regra;
    - `api.oferta_inclui` continua sem filtro, porque é por ela que um pedido pago libera o acesso. Há um pedido antigo do checkout próprio ainda aguardando pagamento, com item da condição.
    - As portas só alcançam produtos que têm programa no Institute. Oferta de outra vertical nunca chega a esses sites.
  - **As 3 funções que leem oferta passam a ler o catálogo:** `api.criar_pedido`, `api.validar_cupom` e `api.cadastrar_compra_manual`. As duas primeiras são do checkout próprio, que está parado; a última é a compra manual do `/admin` do Join. As três mantêm as mesmas permissões e o mesmo modo de segurança.
  - **As 3 tabelas antigas ficam congeladas:** recusam qualquer escrita.
  - **O `/admin` do Join deixa de editar.** As 5 funções de oferta e bump passam a responder: "Preços, ofertas e bumps agora se editam no painel do Mind. Nada foi alterado." A função de cupom não muda.
  - **Site:** nada muda na tela.
  - **Agente:** recebe o mesmo bloco de antes.
  - **Painel:** as ofertas do Institute passam a mostrar "Casa: catálogo", e "Pôr no ar" destrava para os produtos do Institute.
- **O que você vê depois**
  - Você muda algo pequeno, por exemplo o nome de uma oferta. Em até 1 minuto, a mudança aparece:
    - na linha da porta do site, que o painel mostra;
    - no bloco do agente, que traz o nome;
    - no histórico de alterações.
  - Na página em si, só o preço aparece. A descrição da oferta não aparece em nenhuma página dos dois sites. No site do Institute, o nome só aparece nos blocos da condição. Uma mudança visível na página é mudança de preço, que é decisão comercial e vai junto com a troca na Eduzz.
  - Os rascunhos do Passo 4 já podem ir ao ar.
- **Precisa do seu OK?** Sim. É troca de autoridade (D2) e mexe na porta do site e na edição do Join (decisão 8). Você avisa a equipe do Join.
- **Depende de:** Passos 1, 3 e 4, do fim da condição e de o ensaio passar.
- **Quando:** depois de 01/10 às 00h00, num horário de pouco movimento.
- **Como conferimos**
  - **Ensaio no banco real, desfeito no fim, feito duas vezes.** Os dois só depois de 01/10 e fora do pico, porque o ensaio também trava a porta por um instante. O primeiro serve para medir. O do dia tem de dar zero diferença.
  - **Dentro da própria transação, com o mesmo relógio antes e depois**, conferimos:
    - as 3 portas iguais linha a linha. Há duas exceções aprovadas:
      - o bônus vencido do Journey sai da lista crua de bônus, que nenhuma tela mostra;
      - o teste sem produto deixa de ter preço para as funções do checkout parado;
    - o bloco do agente igual;
    - os cursos liberados por código iguais;
    - o valor que cada função de pedido cobraria, por código, igual;
    - colunas, tipos, donos, permissões e modo de segurança das funções iguais.

    Qualquer outra diferença desfaz tudo.
  - **Tempo.** A troca das portas vai por último e tem de levar menos de 1 segundo, medido no ensaio. Enquanto ela acontece, as leituras do site esperam, e cada leitura do site tem limite de 3 segundos.
  - **Depois da virada**, o painel avisa se alguma porta ou função deixar de ler o catálogo. Há cerca de dez arquivos antigos do Join (na pasta `db/`) que recriam essas portas e funções em cima das tabelas antigas. Reaplicar qualquer um deles desfaria a virada sem dar erro.
- **Como desfaz.** Um arquivo de volta fica pronto e testado no ensaio, inclusive com dados de mentira: uma oferta nova cobrindo vários produtos, um preço editado e um bônus.
  - As portas e as funções voltam às definições de hoje, guardadas no mesmo PR.
  - As tabelas antigas descongelam e o Join volta a editar.
  - Se você já tiver editado ou criado ofertas no painel, a volta primeiro copia essas edições para as tabelas antigas, uma linha por programa do Institute. Sem isso, a volta desfaria um preço sem avisar.

### Passo 6 (opcional): Os cadastros antigos da Eduzz ligados ao histórico

- **O que muda:** mais linhas na mesma tabela de ligação do Passo 2, ligando cadastros antigos da Eduzz a produtos de histórico que já existem:
  - Institute 2025 (Turma 1): 33 cadastros, 25 deles com preço na cópia;
  - Journey 2025: os planos criados em 12/2025 (mensal, trimestral, anual e pré-venda);
  - Summit 2026 por categoria (Mind, VIP e Prime, que chegam com o Passo 3). Na Eduzz, VIP e Prime têm 8 lotes, contra 7 no nosso banco. Business e Camarote só entram se você quiser criar esses produtos.
  - Site e agente: nada muda.
- **O que você vê depois:** no detalhe de cada produto antigo, os cadastros da Eduzz e o preço de lista **atual** de cada um, marcado assim. Não é o preço da época, porque a cópia regrava sempre o preço de hoje.
- **Precisa do seu OK?** Sim (decisão 10). Dizer qual cadastro corresponde a qual produto é vocabulário seu. A lista vai no PR para você conferir.
- **Depende de:** Passo 2. Para as categorias do Summit 2026, também do Passo 3.
- **Quando:** quando você quiser.
- **Como conferimos:** cada ligação aponta para um cadastro que existe na cópia da Eduzz e para um produto do catálogo. Nada do que o site ou o agente leem muda.
- **Como desfaz:** apagar essas ligações.

### Passo 7 (opcional): O mês de setembro reconstruído

- **O que muda:** as mudanças de preço do Institute de 08 a 21/09 que estão no registro de migrations entram no "Veio de" de cada oferta, como "preços anteriores (reconstruídos)". Site e agente: nada muda.
- **O que você vê depois:** no detalhe de cada oferta, a linha do tempo de setembro, marcada como reconstruída.
- **Precisa do seu OK?** Sim (decisão 10).
- **Depende de:** Passo 5.
- **Quando:** quando você quiser. Recomendo não fazer agora.
- **Como conferimos:** cada valor aponta para a migration de onde saiu.
- **Como desfaz:** limpar esse trecho do "Veio de".

### Passo 8: O Summit 2027 nasce no catálogo

- **O que muda:** quando você definir a venda de 2027:
  - a edição e as categorias viram produtos;
  - as ofertas por lote são criadas no painel;
  - o que faltar para o agente vender volta para a sua aprovação: link da Eduzz por linha de preço e faixas de desconto por volume (tabela nova, D2);
  - os blocos do agente do Summit e a busca do chat passam a ler o catálogo, mantendo as chaves que o agente usa;
  - a atribuição de checkout é conferida: os códigos seguem o padrão `mind|vip|prime-lote-N`, e a campanha deixa de estar fixa em 2026;
  - as regras de conduta do Summit continuam com o agente.
- **O que você vê depois:** as ofertas de 2027 no painel, com "Pôr no ar" destravado para os produtos de 2027.
- **Precisa do seu OK?** Sim. É D2 e é troca de autoridade: o projeto externo deixa de ser a fonte. O site do Summit não é nosso e continua lendo o projeto externo até alguém mudar o código dele.
- **Depende de:** Passos 3 e 4.
- **Quando:** antes de abrir a venda de 2027.
- **Como conferimos**
  - A saída do agente fica igual antes e depois. Hoje ela é vazia.
  - Um exemplo de 2027, numa transação desfeita no fim, passa pela atribuição de checkout e pela trava de preço do agente.
- **Como desfaz:** voltar as funções. A tabela antiga continua lá.

### Passo 9: Aposentar o que ficou velho

- **O que muda:** depois de uns 30 dias sem nenhuma leitura, saem:
  - as telas antigas do `/admin` do Join, ou seja, as views que ainda leem as tabelas congeladas;
  - as 3 tabelas antigas do Institute;
  - depois do Passo 8, a tabela de ofertas do Summit 2026.

  Nada é apagado em cascata. A cópia fica no próprio catálogo, no "Veio de" de cada linha, e não em arquivo do repositório. Ela guarda a linha original inteira, inclusive os bônus que não viraram linha.
- **O que você vê depois:** nada muda no painel. As telas antigas do Join deixam de existir.
- **Precisa do seu OK?** Sim, porque apaga dados.
- **Depende de:** Passo 5. Para o Summit, também do Passo 8.
- **Quando:** uns 30 dias depois do Passo 5.
- **Como conferimos**
  - Uma consulta ao banco mostra zero leituras no período e ninguém dependendo dessas tabelas.
  - Antes de apagar, o contrato confere que toda linha antiga está no "Veio de".
- **Como desfaz:** recriar a tabela e copiar os dados de volta a partir do "Veio de", dentro do banco.

## Decisões que só você toma

1. **Desligar os 3 bumps já?** Recomendo sim. Ninguém os usa, e depois de 30/09 o da Liderança Consciente vira o preço dessa formação na "Avulsas". Mantê-los exigiria mais colunas só para eles na forma do catálogo.
2. **Desligar às 00h00 de 01/10, por agendamento, as 5 ofertas da condição, os 4 textos e as 4 perguntas do FAQ que falam dela?** Recomendo sim, e que você mande até 29/09 o texto novo de 3 dessas perguntas. Sem isso, a "Avulsas" mostra a condição vencida, o FAQ mostra "—" e o agente segue falando da condição. O custo é que links antigos com o código da condição passam a abrir a página inicial do Join.
3. **Quem troca o preço dos 6 cadastros na Eduzz, e quando?** Recomendo definir a pessoa até 29/09 e trocar à meia-noite, nunca antes: se for antes, o cliente paga mais do que o site anuncia. Se ninguém puder à meia-noite, logo cedo em 01/10. Recomendo também confirmar pelo link do site que ele abre o cadastro original da Liderança Positiva e então arquivar a cópia de 17/09, que não tem venda.
4. **Tirar do playbook do agente a tabela de preços e o texto da condição?** Recomendo sim, antes de 30/09 se você aprovar o texto a tempo, porque preço escrito em texto não acompanha o que você mudar no painel. Esperar tem risco baixo, porque o playbook já manda seguir o bloco do catálogo.
5. **Aprovar a forma do catálogo (D2), com o bônus editável?** Recomendo sim, com o bônus. As mudanças são em tabelas vazias que ninguém lê, e sem o bônus uma oferta criada no painel não mostra bônus nem contagem regressiva no site.
6. **Mind, VIP e Prime do Summit 2026 viram 3 produtos desligados, de histórico?** Recomendo sim. É o seu desenho de 13/09 (*"é importante colocar categoria Mind porque a gente tem três categorias de ingresso"*), e é o que deixa os upgrades certos.
7. **Quem pode fazer o quê no painel?** Recomendo que o administrador e o aprovador ponham no ar, mudem preço ou prazo do que está no ar e prorroguem oferta vencida, sempre com confirmação e registro. O editor só prepara rascunhos.
8. **Fazer a virada do Institute a partir de 01/10?** Isso inclui o `/admin` do Join recusar edição de oferta e bump, a porta de preços entregar só o que está valendo e as 2 exceções do Passo 5. Recomendo sim. Fica uma autoridade só, o `/admin` do Join não está em uso, e ofertas agendadas ou vencidas nunca mais aparecem antes ou depois da hora.
9. **Onde fica "Ofertas" no menu?** Recomendo um item só, junto do Catálogo, com filtro por vertical. Se você quiser, dá para pôr atalhos dentro de Institute e de Mind Summit 2026.
10. **Que histórico entra além do Summit 2026?** Recomendo:
    - ligar os cadastros antigos da Eduzz (Passo 6), marcados como "preço de lista atual";
    - não reconstruir setembro agora (Passo 7), porque o registro de migrations tem buracos;
    - desativar já os 2 cupons antigos do Summit que não têm validade. O motivo foi explicado à parte.

## O que fica de fora e por quê

- **O site do Summit:** lê outro projeto, que não é nosso. O painel mostra o Summit pelo que o agente vê.
- **Cupons:** quem aplica o cupom é a Eduzz, e a casa de cupom é a etapa E4 do plano anterior.
  - O cupom do parceiro de transporte tem validade e fica a seu critério.
  - No Join, a edição de cupom continua, mas o checkout próprio, que usa cupom, está parado.
- **A regra de desconto da Eduzz:** existe venda paga na Eduzz abaixo do preço de lista e sem cupom. Conferi só que existe; o motivo, não. Essa regra mora na Eduzz e vira oferta no catálogo quando você disser qual é.
- **Regras comerciais do Summit 2026** (volume, disponibilidade e conduta): a conduta fica com o agente; volume e disponibilidade voltam no Passo 8.
- **Ofertas de 2025:** não existem no banco. Há só produtos desligados e a lista da Eduzz (Passo 6).
- **O link de compra:** continua fixo no código dos dois sites.
- **O interruptor "Está à venda" do Catálogo:** ainda não tira preço do site do Institute, porque o site não lê esse campo. O painel avisa quando os dois discordam.
- **O guardrail de preço do WhatsApp:** hoje ele não reconhece o preço do Institute. A correção é da lane #40 e vem antes de o Institute responder preço no WhatsApp. Por enquanto, a rota transfere a conversa para o time.
- **O código dos sites:** é lá que está a raiz do erro da "Avulsas", mas ele não é nosso. O plano contorna o problema pelos dados e pela porta.

## Riscos

- **A Eduzz cobrando a condição a partir de 01/10**, nos 6 cadastros, se ninguém trocar o preço lá. Como a nossa cópia da Eduzz está parada desde 24/09 às 21h02, o painel pode não enxergar a troca. Por isso a conferência é na própria Eduzz.
- **O agendamento das 00h00 não rodar.** Nesse caso, a "Avulsas" mostra a condição vencida até alguém desligar à mão. Conferimos às 00h05.
- **A troca das portas segurar as leituras do site.** Cada leitura do site tem limite de 3 segundos. Por isso a troca vai por último, dura menos de 1 segundo (medido no ensaio), acontece fora do pico e entra inteira ou não entra.
- **Arquivos antigos do Join reaplicados** desfazem a virada sem dar erro. As proteções são as tabelas antigas congeladas, o aviso no painel e avisar a equipe do Join.
- **O `/admin` do Join depois de 01/10:**
  - a tela de preços mostra os preços congelados até o Passo 9;
  - a importação de extrato passa a sugerir o Journey para vendas de R$ 1.997, porque ele é a única oferta com esse valor.

  Ninguém usa essa tela hoje: nenhum pedido foi registrado por ela. Se alguém for usar, precisa conferir a oferta antes de gravar.
- **O painel no endereço novo** depende da configuração de origem e de login que está com você.
- **O repositório é público.** Por isso as cargas são copiadas dentro do banco, os contratos comparam com as tabelas e nenhum número de venda vai para arquivo.

## Não conferido

- Qual cadastro da Eduzz o link da Liderança Positiva abre hoje. O código do site registra o título do cadastro original, e só o original tem venda.
- Se a Eduzz permite agendar a troca de preço.
- Por que a leitura da Eduzz parou em 24/09, e se o projeto de onde vem a cópia vai voltar a ler.
- Se a configuração de origem e de login do painel em `admin.minddash.pro` já foi feita.
- Se alguém ainda aplica os arquivos `db/` do Join neste banco.
- Se o pedido antigo que aguarda pagamento ainda pode ser pago.
- O motivo das vendas abaixo do preço de lista sem cupom.
- Se a troca das portas mantém os tipos e o tempo. Só o ensaio prova isso, porque nenhuma mudança de estrutura foi executada nesta análise.
- O código do site do Summit, que é outro repositório e não está clonado aqui.

*Correspondência com o plano anterior:*
- *Passo 1 = parte da E0 e da E8;*
- *Passos 2 e 4 = E7;*
- *Passo 3 = E1 e E2 reduzidas, mais o histórico do Summit;*
- *Passo 5 = E6;*
- *Passo 8 = E5;*
- *Passo 9 = E9;*
- *Passos 6 e 7 são novos e opcionais;*
- *E3, E4 e o restante da E0 e da E8 seguem como estavam, fora deste plano.*

## Conferência

**O que mudou por causa das críticas** (cada ponto foi conferido hoje no banco ou no código):
- **Ordem:** a virada de 30/09 virou o Passo 1, num PR próprio e primeiro da fila, porque é o único passo com prazo.
- **Agendamento:**
  - vai escrito em UTC (03h00), porque o relógio do agendador está em GMT;
  - só age se a condição já venceu;
  - se apaga depois de rodar;
  - se o PR entrar atrasado, a migration age na hora.
- **Textos e FAQ:** o mesmo agendamento desliga 4 textos e 4 perguntas.
  - A porta dos textos não olha prazo, e o bloco do agente leva todos.
  - No site, duas respostas do FAQ viravam "—".
  - A pergunta do Unpacking também fala da condição e não estava nas críticas.
- **Playbook:** virou a decisão 4, e não pré-condição.
  - O próprio playbook se declara "retrato de 17/09" e manda seguir o bloco do catálogo.
  - O guardrail só roda no WhatsApp, onde a rota do Institute ainda transfere para o time.
- **Eduzz:**
  - são 6 cadastros a trocar, e o Passo 2 liga os dois da Liderança Positiva;
  - só o cadastro original tem venda, e a marca de "arquivado" nele vem da regra automática da nossa cópia;
  - a cópia da Eduzz está parada desde 24/09;
  - a troca de preço nunca pode ser antes da meia-noite;
  - o plano agora diz claramente que o painel não muda o preço cobrado.
- **Bônus:** virou opção da D2, e o "Agora no site" mostra o bônus e o prazo dele. O site lê nome, texto, valor e prazo do bônus, e o prazo do bônus comanda a faixa do Journey.
- **Regras do painel:**
  - histórico é só leitura por marca, e não por estar encerrado;
  - oferta vencida pode ser prorrogada, como em 18/09;
  - no máximo uma oferta sem prazo no ar por produto, e nenhuma condicional no ar;
  - códigos que a virada vai carregar ficam reservados;
  - "Pôr no ar" destrava por produto que tem leitor.
- **Virada:**
  - só `api.ofertas` filtra o que está valendo, e a porta de entrega continua sem filtro;
  - os 2 testes entram como histórico;
  - a comparação inclui o valor que as funções de pedido cobrariam;
  - os ensaios acontecem só depois de 01/10 e fora do pico, com a troca por último e em menos de 1 segundo;
  - a volta é ensaiada com uma oferta criada no painel;
  - a lista de arquivos do Join que desfariam a virada foi de 4 para cerca de dez.
- **Teste de aceite:** passou a ser a linha na porta e o bloco do agente, porque a descrição da oferta não aparece em nenhuma página.
- **Produtos novos:** entram desligados, sem venda e sem funil do HubSpot, tudo escrito explicitamente. Os padrões da tabela ligam os dois, e o funil faria negócios do HubSpot caírem nesses produtos.
- **Repositório público:**
  - toda carga é copiada dentro do banco;
  - os contratos comparam com as tabelas de origem;
  - a cópia usada no Passo 9 é o próprio "Veio de".
- **O que entrou de novo:**
  - o Passo 6 (cadastros antigos da Eduzz no histórico);
  - o aviso de mudança na tabela antiga do Summit;
  - a simulação marcada como simulação;
  - "o agente recebe (chat da web)";
  - a legenda das situações e o glossário;
  - os itens de implementação: semente de demonstração, teste de navegação, valores em reais, criação na função do painel e correção do mapa dos sites.
- **Passos juntados:** o painel e a Eduzz ficaram num passo só, e a forma do catálogo e o histórico do Summit em outro, para nenhum passo ficar sem nada visível. A limpeza de permissões virou arrumação opcional.

**O que foi descartado e por quê:**
- **Agendar às 02h59 UTC.** O corte é às 02h59min00s, e com a proteção "só se já venceu" um disparo nesse minuto poderia se apagar sem agir. Às 03h00, a "Avulsas" fica desatualizada por no máximo 1 minuto, mais os 60 segundos de cache do site. É aceitável.
- **"9 notas com números".** São 7 de 21. A correção continua valendo.
- **"3 textos da condição".** São 4, porque `oferta.prazo` também fala da condição.
- **Pôr prazo na porta dos textos.** Seria mudar a porta do site, e desligar os textos resolve só com dados.
- **Carregar 2025 ou a Eduzz antiga como ofertas.** A cópia da Eduzz guarda o preço de hoje, e não o da época. Por isso esses dados entram só como ligação.
- **Deixar procura e disponibilidade fora do "Veio de".** Elas entram. Ficam no banco, que não é aberto a visitantes, e sem elas as tabelas antigas não poderiam sair sem perda.
- **Cupons.** A descoberta lateral sobre cupons foi conferida e fica fora deste documento público.
