# Fonte da verdade dos sites do Join e do Institute

26/09/2026 · Mapa feito só com leituras (banco, logs e os dois repositórios dos sites, nos HEADs de 21/09).

Pergunta da Adriana: *"sites do Join e Institute não são um único projeto mas se alimentam do mesmo banco — preciso saber qual a fonte da verdade"*. Companheiro deste mapa: [`PLANO_PRECOS_CATALOGO.md`](PLANO_PRECOS_CATALOGO.md), o plano para levar preço e oferta ao `catalogo`.

*O repositório é público: achados de segurança e números de venda ficaram fora deste documento e foram entregues à Adriana à parte.*

## 1. Resposta curta: qual é a fonte da verdade dos sites

- **Tudo o que muda na vitrine tem uma fonte só: a área `institute` do banco Supabase.** Isso vale para preço, parcelas, prazo, bônus, datas, encontros, FAQ e composição.
  - Os dois sites leem essas informações pelas mesmas 6 "janelas" de leitura do banco: as views `api.programas`, `api.ofertas`, `api.encontros`, `api.condicoes`, `api.faq` e `api.programa_composicao`. O código que faz essa leitura é o mesmo nos dois.
  - Nas últimas 24 h foram umas 24.800 leituras, todas de servidores na Cloudflare, com supabase-js e a chave publicável.
  - Os dois sites usam a mesma chave e a mesma versão do supabase-js (2.116.0). Por isso os logs não mostram qual site fez cada leitura.
- **Quem escreve na área `institute`:** só a tela `/admin` do site do Join e os comandos SQL da pasta `db/` do repositório do Join.
  - `/admin/precos` escreve as ofertas e `/admin/bumps` escreve os bumps. `/admin/cupons` também é do Join, mas grava em `checkout.cupons`, fora da área `institute`.
  - O site do Institute não escreve nada.
  - Nenhuma outra função do banco escreve em `institute.*`.
- **Três coisas ficam fora da área `institute`:**
  - o link de compra e o preço cobrado, que estão na Eduzz. O banco já tem a coluna `checkout_url` nas ofertas, mas ela está vazia nas 16;
  - vários fatos comerciais escritos direto no código: dias e horários dos encontros, "60 dias", professoras, listas do que está incluído e a data em que o site muda depois da condição;
  - uma segunda cópia do catálogo, no mesmo banco (`catalogo.produtos`). O painel do Mind edita essa cópia (no Institute, menos as datas: ele mostra as da turma e não as deixa editar), e as datas guardadas nela não batem com as da turma.
- **Os dois sites usam o mesmo código copiado.** São idênticos, só mudando o caminho das importações:
  - `queries.ts`, `checkouts.ts` (os 6 links da Eduzz) e `evento.ts`;
  - os sílabos;
  - os textos da Certificação, da Especialização e do Journey.

  O que muda entre os dois é o menu, as rotas e partes do layout. Qualquer mudança comercial no código precisa ser feita duas vezes.

## 2. Tabela

| Informação | Fonte da verdade | Quem escreve nela | Site do Institute lê por | Site do Join lê por | Cópias em outros lugares e se batem |
|---|---|---|---|---|---|
| Programa (nome, tipo, carga, duração, modalidade) | `institute.programas` (6) | Só SQL; não há tela | `api.programas` | `api.programas` | `catalogo.produtos` (painel do Mind): o nome bate em 5 de 6. A Liderança Consciente aparece lá como "Formação Liderança Consciente" |
| Datas da turma (início e fim) | `api.programas`: usa a coluna própria de `institute.programas` quando está preenchida (Journey e Especialização). Quando está vazia, calcula pelo primeiro e último encontro (nos outros 4; a Certificação soma as três formações). A coluna própria está vazia em 4 de 6 | Só SQL | `api.programas` | `api.programas` | `catalogo.produtos`: **só 1 de 12 datas bate**. Ninguém lê essa cópia. O painel do Mind mostra as datas de `api.programas` desde o PR #143 (26/09; antes mostrava a coluna crua, vazia em 4 de 6). O Agent lê `api.programas` e vê as datas certas |
| Encontros (calendário, .ics) | `institute.programa_encontros` (28): Journey 12, Liderança Consciente 6, Significado 5, Segurança Psicológica 5. **A Especialização não tem nenhum** | Só SQL. Existe uma regra de "equipe edita", mas o usuário logado só tem permissão de leitura, e esse schema nem é exposto | `api.encontros` | `api.encontros` | Textos do código contra o banco:<br>• Certificação, "16 encontros às terças, 19h às 20h30": bate (16 terças, 19h, 90 min).<br>• Journey, "primeiras segundas, 19h às 20h30": bate com a ressalva que o próprio texto faz; 9 de 12 caem na primeira segunda, e 09/11, 11/01 e 13/09 não.<br>• Especialização: as 12 quartas só estão escritas em `joinmind.com.br/ANTES-DE-PUBLICAR.md`, não no banco.<br>• O FAQ da Certificação escreve "05/10, a confirmar" como primeiro encontro do Journey: bate |
| Preço, parcelas, prazo da condição | `institute.ofertas` (16; 14 ativas e públicas, todas vigentes) | Join `/admin/precos`: `salvar_oferta` muda valor, nome, prazo e publicação, mas **não mexe nas parcelas**; `criar_oferta` define as parcelas só na criação. Também SQL | `api.ofertas` | `api.ofertas` | **Eduzz: é o preço cobrado, e nada sincroniza os dois.** O espelho `eduzz.produtos`, sincronizado hoje, tem preço-base igual ao da Condição Summit nos 6 produtos. A data de encerramento repetida no código dos dois sites (`evento.ts`) bate: 30/09, 23h59. `checkout.pedido_itens` só tem pedidos de teste e 1 pedido não pago |
| Bônus da condição | `institute.oferta_bonus` (8) | Só SQL | `api.ofertas` (campo `bonus`) | `api.ofertas` | O prazo bate com o da oferta em 7 de 8. O do Journey anual difere de propósito |
| Rótulo "Condição Summit" e avisos | `institute.condicoes` (11) | Só SQL | `api.condicoes` | `api.condicoes` | Os dois têm no código um texto reserva, usado se a linha sumir do banco |
| FAQ | `institute.faq` (31: Certificação 10, Especialização 8, Journey 13) | Só SQL | `api.faq` | `api.faq` | Nenhum preço escrito no texto: preço, prazo, período, parcelamento e primeiro encontro entram por marcadores preenchidos pelo banco. **Mas o FAQ da Certificação traz escrito "05/10, a confirmar" e "60 dias"** |
| Composição da Certificação | `institute.programa_composicao` (3) | Só SQL | `api.programa_composicao` | `api.programa_composicao` | Professoras e imagens ficam no código e são casadas com o banco pela posição na lista |
| O que o programa inclui (lista de texto) | `institute.programa_inclusoes` (7: 2 da Especialização, 5 do Journey; os outros 4 programas não têm), exposta em `api.programa_inclusoes` | Só SQL | **Não lê**: lista fixa no código | **Não lê**: lista fixa no código | **Ninguém lê essa tabela, nem o Agent.** O código tem outra redação e há um fato em conflito: o banco diz "12 encontros de 2 horas" no Journey, mas os encontros no banco têm 90 min e o site diz "19h às 20h30" |
| O que a oferta entrega junto (programas) | Calculado a partir dos bônus e da composição: `api.oferta_inclui` (8) | Muda junto com bônus e composição | Não lê | Não lê | Lido pelo Agent e por `criar_pedido`. `catalogo.oferta_inclui` está vazia |
| Professoras | `institute.programa_pessoas` (9) | Só SQL | **Não lê**: nomes fixos no código | **Não lê**: nomes fixos no código | O Agent lê o banco (`api.programa_pessoas`). Código contra banco, programa a programa: **bate hoje** |
| Link de compra | **Nenhum banco**: 6 links da Eduzz fixos em `checkouts.ts`. A coluna `institute.ofertas.checkout_url` existe e `api.ofertas` a mostra, mas está vazia (0 de 16) | Desenvolvedor, a cada publicação | Código | Código (igual) | Idêntico nos dois repositórios |
| Order bump | `institute.bump_regras` (5) | Join `/admin/bumps` | Não usa | Nenhuma página no ar usa: `/carrinho` redireciona para `/` e `/checkout/<código>` para a Eduzz. Só `criar_pedido` lê | Não se aplica |
| Cupom | `checkout.cupons` (0 linhas) | Join `/admin/cupons` | Não usa | Só no checkout próprio (`/checkout/<código>`), que redireciona para a Eduzz. `/inscricao` não usa cupom | Cupom da Eduzz: **não comprovado** |
| Pedidos e vendas | Vendas reais: **Eduzz**. O espelho `eduzz.vendas` é atualizado pelo job `eduzz_espelho_sync` a cada 30 min; a última sincronização foi hoje às 13h22. `checkout.pedidos` só tem pedidos de teste e 1 pedido real não pago, de 12/09 | Eduzz. No Join, cadastro manual (`cadastrar_compra_manual`) | Não lê | `/inscricao` está no ar, mas nenhuma página aponta para ela | `api.criar_pedido`: **0 chamadas de 18/09 até hoje**. As últimas (7, em 17/09) vieram de provedores de internet residenciais, ou seja, de navegadores |
| Acesso do aluno | LearnWorlds (externo) | LearnWorlds. A fila de acessos do Join está desligada desde 17/09 | Link fixo no menu | Link fixo e painel `/admin/acessos` | `learnworlds.acessos`: 2 linhas |
| Sílabo (texto dos módulos) e textos comerciais | Arquivos `.ts` em cada repositório | Desenvolvedor | Arquivo próprio | Arquivo próprio | Hoje idênticos nos dois (só muda o caminho das importações). O Join ainda guarda arquivos antigos com preços velhos (`content/precos.ts`, `programas.ts`, `catalogo.ts`, `comparacao.ts`, `oferta.ts`), mas nenhuma página os mostra |
| "Pode vender" (libera o Agent a oferecer) | `catalogo.produtos.vende` | Painel do Mind (`mindagent-catalogo`) | Não lê | Não lê | Está ligado nos 6 e todos têm oferta vigente, então bate. Mas é um interruptor separado |

## 3. Divergências e riscos

1. **O preço tem duas fontes, e elas vão se separar em 01/10.**
   - Hoje o preço-base dos 6 produtos no espelho da Eduzz é igual ao da Condição Summit no banco: R$4.997 na Certificação e na Especialização, R$1.997 nas três formações e no Journey.
   - Às 23h59 de 30/09 as ofertas da condição vencem, e o site passa sozinho a mostrar o preço de balcão: R$5.997 e R$2.497. O Journey continua R$1.997.
   - A Eduzz continua cobrando o que estiver cadastrado lá até alguém mudar.
   - O que não confirmei: qual produto da Eduzz cada link abre, e o preço da oferta específica de cada link. A Certificação tem duas versões no espelho, e uma delas está marcada como arquivada.
2. **Mudar o preço em `/admin/precos` não muda a parcela.** A função `salvar_oferta` não mexe em `parcelas` nem em `valor_parcela`, e nenhum gatilho do banco recalcula. Os sites mostram "12x de" usando o `valor_parcela` do banco. Quem trocar o valor pela tela deixa a parcela antiga na página.
3. **As datas têm três versões.**
   - Os sites e o Agent leem `api.programas`, que usa os encontros quando a coluna própria está vazia.
   - A cópia `catalogo.produtos` bate em só 1 de 12 datas.
   - O painel do Mind chegou a mostrar a coluna crua da turma, vazia em 4 de 6, e já foi corrigido (PR #143): agora calcula como `api.programas`, e o contrato `CATALOGO_OK` confere produto a produto.
   - O `criar_pedido` não lê as datas do programa.
   - A Especialização não tem nenhum encontro no banco. Por isso o site não mostra calendário nem gera .ics para ela.
4. **Há fatos comerciais fixos no código, e o banco já tem lugar para parte deles:**
   - professoras (`programa_pessoas`): hoje batem com o banco;
   - "o que inclui" (`programa_inclusoes`): hoje não bate. Só cobre 2 programas e diz "2 horas" onde os encontros têm 90 min;
   - dias e horários dos encontros;
   - "60 dias de acesso", que também está escrito no texto do FAQ;
   - data de encerramento;
   - links da Eduzz.

   Tudo isso está repetido nos dois repositórios e hoje é igual nos dois.
5. **Não há tela para quase nada.** FAQ, condições, encontros, datas, bônus, composição, professoras e parcelas de oferta já criada só mudam por SQL. E há dois painéis mexendo em "catálogo": o do Join edita a fonte (`institute.ofertas`), o do Mind edita uma cópia (`catalogo.produtos`).
6. **A máquina do checkout próprio está no ar e parada.**
   - `/inscricao`, o pagamento e o webhook da InfinitePay continuam no código do Join.
   - `api.registrar_retorno` só pode ser executada pelo dono do banco. A chamada volta com erro que ninguém confere, então falha em silêncio.
   - `/previa/<slug>` no Join continua no ar, fora do Google. Duas das 11 telas mostram R$1.697, que não é nenhum preço atual.
   - Isso vale para o código nos HEADs de 21/09. Não conferi o site no ar.
7. **A premissa sobre o `criar_pedido` não se confirmou.** Não há chamadas desde 18/09.
   - O Institute não tem essa chamada no código.
   - O Join chama pelo navegador (componente de cliente em `/inscricao`), não pelo servidor.
   - As últimas chamadas, em 17/09, vieram de provedores residenciais, não da Cloudflare.
   - As leituras vindas da Cloudflare estão confirmadas, mas pelos logs não dá para separar qual dos dois sites fez cada uma (não comprovado).

## 4. O que decidir

1. **Qual preço manda: banco ou Eduzz? E antes de 30/09 às 23h59, o que acontece na Eduzz quando a condição vencer?** Recomendo:
   - o banco manda no que se mostra;
   - toda mudança em `/admin/precos` vem junto com a mesma mudança na Eduzz;
   - `salvar_oferta` passa a recalcular a parcela;
   - depois, os links da Eduzz passam para a coluna `checkout_url`, que já existe nas ofertas. Não precisa de tabela nova, mas é troca de fonte da verdade, então passa pelo seu gate.
2. **As datas oficiais são as da turma (`api.programas`)?** Recomendo que sim. O painel do Mind já mostra as mesmas datas dos sites (PR #143), e as datas guardadas em `catalogo.produtos` deixam de valer para o Institute (falta decidir se são alinhadas à turma ou apagadas). Também falta decidir se as 12 datas da Especialização entram em `programa_encontros`.
3. **Um painel só para editar catálogo?** Hoje só o `/admin` do Join escreve na fonte (`institute.*`). O plano de preços propõe que a edição passe para o painel do Mind (`admin/`) quando a casa virar o `catalogo` (etapa E7), e que as telas de oferta, bump e cupom do Join se aposentem (pergunta 15 do plano). As duas coisas se decidem juntas; datas e encontros, FAQ e condições continuam só por SQL até lá.
4. **Tirar do código o que o banco já tem lugar para guardar?** Recomendo começar pelas professoras: o Agent já lê `api.programa_pessoas`, e hoje o código bate com o banco. "O que inclui" vem depois: primeiro é preciso corrigir o texto no banco ("2 horas") e completar os programas que faltam, porque hoje ninguém lê essa tabela. O resto fica no código, lembrando de mudar nos dois repositórios.
5. **Desmontar o checkout próprio parado?** Recomendo tirar `/previa` do ar já, por causa do preço antigo visível. `/inscricao` e o fluxo da InfinitePay ficam desligados até você decidir se voltam.


Tudo foi feito só com leituras:
- consultas SELECT e contagens no banco;
- logs de 16/09 até hoje;
- os repositórios nos HEADs `238c313` (Institute) e `acbbd01` (Join), ambos de 21/09.

Nada foi alterado.
