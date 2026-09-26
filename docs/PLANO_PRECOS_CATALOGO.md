# Plano: preços e ofertas do Mind no schema catalogo

26/09/2026 · Status: proposta, aguarda aprovação da Adriana (D2)

*Esta auditoria só leu dados, no projeto `ymnmotgglsrxmjmonwjz` e no repositório (HEAD `def4bd2`). Nada foi alterado no banco nem no repositório. O documento propõe; quem aprova as mudanças estruturais é a Adriana (regra D2). A decisão dela de 26/09 fecha a "D2 da casa das ofertas": a casa é o `catalogo`, e não uma `institute.ofertas` generalizada.*

*O repositório é público: achados de segurança e números de venda desta auditoria foram entregues à Adriana à parte e não constam aqui. Companheiro deste plano: [`FONTE_DA_VERDADE_SITES.md`](FONTE_DA_VERDADE_SITES.md), de onde cada site lê cada informação.*

**Termos usados**
- **Autoridade**: o lugar que decide o valor verdadeiro.
- **View de compatibilidade**: uma "janela" com o mesmo nome e o mesmo formato da tabela antiga, que passa a mostrar os dados da casa nova. Quem lê não percebe a troca.
- **FK (amarração)**: uma regra do banco que liga uma linha a outra e impede apagar o que ainda está em uso.
- **Código vendável (SKU)**: o código de cada item que se compra, por exemplo "formação X, condição de balcão".
- **Porta**: a função ou view por onde o site, o agente ou o painel leem ou escrevem.
- **Paridade**: a saída depois da troca é idêntica à de antes, linha a linha.
- **Rollback**: como desfazer uma etapa.

---

## 1. Estado atual

Hoje o preço do Mind está espalhado por 5 lugares:

1. **Institute: `institute.ofertas` e mais 2 tabelas.** É a única casa que vende agora.
   - O site do Institute, que fica em outro repositório, a lê pelas views `api.*` milhares de vezes por dia.
   - O agente também a usa, pelo bloco `institute_catalogo`.
   - O checkout próprio também a usa, mas está desligado desde 16/09.
2. **Summit: `summit_2026.offers` e mais 2 tabelas.** É uma cópia do projeto `mind-summit-propostas`.
   - A cópia foi desligada em 25/09: os jobs 1 e 15 já estão inativos, e nenhuma oferta está ativa.
   - **Mesmo assim, a tabela ainda tem leitor vivo.** A rota `cliente_suporte`, ativa no WhatsApp e no web, lê essa tabela pelo bloco obrigatório `inclusoes`.
   - A busca `mindagent_chat_search` também a lê, e roda em todo turno do WhatsApp.
3. **Cupons do checkout próprio, `checkout.cupons`.** Está vazia.
4. **O `catalogo`.** As 4 tabelas de oferta foram desenhadas com a Adriana em 13/09 exatamente para isso, mas estão vazias e ninguém as lê.
5. **Fora do banco.**
   - A Eduzz, que é quem cobra de fato.
   - O projeto `mind-summit-propostas`: o site do Summit ainda lê preço dali.
   - Textos: só o playbook de vendas do Institute tem 39 valores em reais escritos à mão.

**O problema:** o mesmo preço chega a existir em até 5 cópias, e nenhuma garante que as outras estejam certas.
- O site mostra um número e quem cobra é outro sistema.
- Exemplo concreto: os 7 produtos Eduzz de 2027 fora do Summit estão cadastrados com o preço da Condição Summit (7 de 7). Em 01/10 o site e o agente passam ao preço de balcão, mas a Eduzz continua cobrando a Condição se ninguém mudar o preço lá.

Além disso, `catalogo.produtos` mistura três níveis:
- a **empresa**: `mind`, do tipo `empresa`;
- as **verticais**: `mind-institute`, do tipo `formacao`, e `mind-dash`, do tipo `outro`;
- os **produtos de verdade**.

Por causa disso, o Institute aparece como "não vendável" mesmo tendo 6 produtos à venda.

---

## 2. O que existe hoje

| Objeto | Vertical | Papel hoje | Linhas | Destino proposto |
|---|---|---|---|---|
| `catalogo.produtos` | todas | Autoridade do vocabulário de produto e da janela de venda (não guarda preço) | 17 (6 à venda, todos do Institute 2027) | **Fica.** Perde `mind` e `mind-institute`. `mind-dash` fica enquanto o perfil e o HubSpot dependerem dele (§3.1). Ganha as categorias do Summit 2027 quando ele for definido |
| `catalogo.ofertas` | todas | Casa desenhada para a condição comercial (base, período, combo) | 0 | **Fica e vira a autoridade.** Recebe as colunas que faltam (§3.2) |
| `catalogo.oferta_precos` | todas | Casa desenhada para o preço de cada produto dentro de uma oferta | 0 | **Fica e vira a autoridade.** Ganha código vendável, link de checkout, sobrescrita opcional do código na Eduzz e preço riscado explícito |
| `catalogo.oferta_inclui` | todas | Casa desenhada para bônus e brindes (o item incluído tem de ser um produto) | 0 | **Fica e vira a autoridade** |
| `catalogo.oferta_requer` | todas | Casa desenhada para bump e upgrade | 0 | **Fica e vira a autoridade.** Ganha modo, prioridade, grupo exclusivo e janela |
| `institute.ofertas` | institute | **Autoridade de fato hoje** (site, agente, checkout) | 16: 14 ativas e públicas, 3 bumps, 5 de período que vencem em 30/09, 2 de teste. `produto_codigo` está vazio nas 16; o produto vem pelo programa (15 de 16; a 16ª é de teste e não tem programa) | **Migrar os 15 códigos com programa**, inclusive os inativos e os de período. Depois congelar e aposentar |
| `institute.oferta_bonus` | institute | Bônus por oferta | 8, todos com janela que termina até 30/09. 2 liberam um programa. 6 são "ingresso Summit 2027", que não existe como produto | Os 2 com programa vão para `oferta_inclui`. Os 6 que são só texto viram exceção de paridade ou produto (§8). Depois aposentar |
| `institute.bump_regras` | institute | Order bump | 5 | **Migrar** para `oferta_requer`, depois aposentar |
| `api.ofertas`, `api.bump_regras`, `api.oferta_inclui` | institute | Portas do site, do agente e do checkout. `api.oferta_inclui` é usada por `institute.abrir_acessos` quando um pedido é pago | views | **View de compatibilidade** sobre o catálogo, com as mesmas colunas **e os mesmos tipos** |
| `api.admin_ofertas`, `admin_bumps`, `admin_ofertas_para_bump`, `admin_cupons` | institute | Painel antigo do joinmind, sem uso. Dependem de `institute.*`, de `api.oferta_inclui` e de `checkout.cupons` | views | **Aposentar primeiro** (antes da E6 ou nela) |
| `api.criar_oferta`, `salvar_oferta`, `criar_bump`, `salvar_bump`, `remover_bump`, `salvar_cupom` | institute | Escritores antigos, sem auditoria | funções | **Aposentar** (revogar na virada, para não haver duas autoridades) |
| `api.criar_pedido`, `validar_cupom`, `cadastrar_compra_manual`, `institute.calcular_desconto` | institute | Calculam o valor cobrado no checkout próprio (desligado desde 16/09) | funções | **Reescrever** para ler do catálogo, ou aposentar se o checkout próprio não voltar |
| `summit_2026.offers` | summit | Cópia do projeto externo, com 0 ativas, mas **lida pela rota viva `cliente_suporte` e pela busca do WhatsApp** | 28 (todas com `procura`; 4 de grupo com mínimo e máximo) | **Congelar como histórico.** Só carregar no catálogo se forem criados produtos por categoria de 2026 (§8). **O Summit 2027 nasce no catálogo** |
| `summit_2026.commercial_rules` | summit | 4 regras de preço, disponibilidade e upgrade + 3 de conduta do agente | 7 (todas ativas) | **Dividir:** a parte de preço vai para o catálogo; a conduta fica com o agente |
| `summit_2026.coupons` | summit | Cupom sem nenhum leitor | 3 (ativos com o Summit fora de venda) | **Desativar já** (E0) e migrar inativos para a casa de cupom (§3.3) |
| `summit_2026.experiencias` | summit | O que cada categoria de ingresso inclui (também lida por `mind_kit_inclusoes`) | 4 | **Fica.** Cada categoria vira produto no catálogo a partir de 2027 |
| `checkout.cupons` | institute | Definição de cupom do checkout próprio | 0 | **Mover para o `catalogo`** como a casa única de cupom (§3.3), sem a regra de acesso da equipe |
| `checkout.produto_externo` | várias | De-para (sistema, código externo) → produto do catálogo; sem leitores | 0 | **Fica e passa a ser usada.** O código Eduzz do Institute é por produto e tem o preço trocado ao longo do tempo, não por oferta |
| `mindagent_sync_offers`, `mindagent_sync_disponibilidade`, 2 Edge Functions e os jobs 1 e 15 (já inativos) | summit | Copiavam preço e disponibilidade de fora | — | **Neutralizar já pelo banco** (E0), depois aposentar |
| Kits do Summit: `mind_kit_ofertas(_b2b)`, `mind_kit_inclusoes(_b2b/_b2c)`, `mind_precos_por_volume` e `mind_kit_precos_por_volume(_b2b)`, `mind_kit_regras_comerciais(_b2b)`, `mindagent_chat_search`, `mind_checkout_url` | summit | Levam preço ao agente. `mind_kit_inclusoes` e `mindagent_chat_search` estão em uso vivo | funções | **Repontar** para o catálogo mantendo as chaves que os consumidores leem (E5) |
| `mind_kit_institute_catalogo` | institute | Leva preço ao agente | função | **Fica** (segue `api.ofertas`). Mas o guardrail de preço não reconhece os valores dela (§7) |
| `treble_agent_context(_base)`, `mind_virada_de_lote`, `api.treble_event_bundle`, `mind_admin_dashboard_counts` | summit | Portas legadas. As 2 últimas estão quebradas: leem o schema `summit`, que não existe | funções | **Aposentar** |
| `mind.produtos` | várias | View antiga do catálogo | view | **Aposentar** depois de repontar os 2 leitores |
| Projeto externo `mind-summit-propostas` | summit | Antiga autoridade de preço do Summit; o site ainda lê dali | externo | **Deixa de ser fonte** (troca de autoridade, D2) |
| `eduzz.produtos`, `eduzz.produto_catalogo` | várias | Cópia do que a Eduzz tem cadastrado | 342 / 192 | **Fica** como cópia. Liga ao catálogo pelo de-para por produto |
| `mind.policies`, `institute.condicoes`, `institute.faq` | — | Textos, não preço (o FAQ já puxa o preço do banco) | 6 / 11 / 31 | **Fica** |

**Dash:** não existe preço, oferta nem proposta do Dash em lugar nenhum do banco. Não há nada a migrar.

---

## 3. Modelo alvo no `catalogo`

Não precisa de schema novo. As 4 tabelas já existem e o que falta são colunas nelas. A única tabela nova é uma tabela pequena de faixas de volume, e só quando o Summit 2027 tiver preço (D2).

### 3.1 Empresa, vertical e produto: separar os níveis

**Regra:** oferta e preço são sempre de um **produto real**, nunca da empresa nem de uma vertical.

**Os agentes não precisam encontrar a empresa ou as verticais no catálogo para vender.** Todos os usos foram conferidos, e nenhum é de preço:
1. **Rótulo do playbook da rota.** O playbook do Institute aponta para a linha `mind-institute`.
2. **Texto de posicionamento.** O bloco `product_intelligence` lê a descrição de `mind`, `mind-institute` e `mind-dash`.
3. **Aviso de lead.** Uma função grava `mind-institute` ou `mind-dash` num sinal comercial.
4. **Perfil e HubSpot.** `intelligence.jtbd.produtos` guarda `mind-dash` em 7 de 28 linhas, como texto e sem amarração. `intelligence.perfil_resumo` cruza essa lista com os produtos ativos do catálogo para montar os "produtos com fit". Esse resultado alimenta o write-back diário do perfil no HubSpot (job 23).

**A incoerência explicada.** `mind_produto_da_rota_status('institute')` pega o produto do playbook, que é a linha da vertical (vende=false), e por isso responde "não vendável". Hoje ela só é chamada para `summit_b2c`, então nenhum agente está sendo bloqueado. Mas o caso mostra por que a rota tem de apontar para a vertical.

**Desenho proposto (o da Adriana):**
- a rota do agente aponta para a **vertical**;
- os produtos da vertical são os de `catalogo.produtos` com aquela vertical (a coluna `vertical` já existe e a regra dela já limita os valores aceitos);
- o contexto da vertical vem do schema da vertical (`institute`, `dash`, `summit_2026`);
- o contexto da empresa vem de `mind.*`.

**Tudo o que aponta hoje para as 3 linhas, e para onde vai** (conferido no banco):

| Referência | Aponta para | Vai para |
|---|---|---|
| `agentes.prompts` `playbook_institute` e `vendas_institute` (amarração) | `mind-institute` | Nova coluna `vertical = 'institute'`; o produto fica vazio |
| `agentes.prompts` `playbook_dash` (amarração) | `mind-dash` | `vertical = 'dash'` |
| `mind_kit_product_intelligence` (rotas institute, dash, cliente_suporte e concierge_summit) | Descrição de `mind`, `mind-institute`, `mind-dash` e de `mind-summit-2026` | **Empresa:** `mind.organization_content`, que existe, está vazia e já tem índice único por `slug` quando não há evento. Seu único leitor hoje, `api.treble_event_bundle`, é aposentado antes de a tabela ser preenchida. **Vertical:** o documento de posicionamento no schema dela. **Summit:** continua no produto real da edição |
| `mind_produto_da_rota_status` | Produto do playbook | Devolve a vertical e os produtos à venda dela |
| `intelligence.lead_aviso_detectar` (gatilho) | Grava `mind-institute`/`mind-dash` em `intelligence.sinais_comerciais` | Grava só a vertical, coluna que já existe |
| `intelligence.jtbd.produtos` → `perfil_resumo` → write-back HubSpot | `mind-dash` (7 linhas) | **Enquanto o perfil não usar a vertical, `mind-dash` fica.** Trocar exige mexer no write-back do HubSpot (gate) |
| `institute.knowledge_documents` (1) e `dash.knowledge_documents` (1) | Código da vertical, como texto | Ficam sem produto |
| `intelligence.vertical_da_entrada` | Só o comentário cita uma tabela de domínios | **Fora do escopo:** não tem chamador no banco nem no repositório |
| Painel `/catalogo` (`admin/`), testes e dados de teste | Listam `mind` e `mind-dash` | Ajustados junto |
| Regra de tipo de `catalogo.produtos` | Aceita `empresa` | `empresa` sai da lista quando `mind` sair |
| CRM, NPS, checkout, institute, summit, origens | — | Nenhuma amarração aponta para essas 3 linhas (0 linhas) |

**Consequência para o Dash:** `mind-dash` é a única linha da vertical dash. Se sair, o Dash fica com zero produtos e some dos "produtos com fit" no HubSpot.

**Produtos já vendidos e hoje inativos** (edições 2025): `mind-summit-2025` tem negócios históricos no CRM. As formações, a certificação e o Journey de 2025 têm ligações com o HubSpot e com a Eduzz. **Recomendação:** ficam como "inativo e não vende", e o painel abre filtrado por "à venda".

### 3.2 Colunas que faltam (todas em tabelas que já existem)

| Tabela | Coluna nova | Para quê |
|---|---|---|
| `ofertas` | `publico` | Separar "aparece no site" de "vale por link direto" (`api.ofertas` filtra por ativo e público) |
| `ofertas` | `meios_pagamento` | As 14 ativas usam cartão+pix+boleto; as 2 inativas têm cartão+pix e vazio |
| `ofertas` | tipo `condicional` (amplia a regra de tipos) | Bump e upgrade são ofertas que só valem com um requisito |
| `oferta_precos` | `codigo` único (o código vendável) | **Preserva os códigos antigos**, que pedidos, acessos, relatórios e UTMs usam como texto. No Summit, os códigos `mind\|vip\|prime-lote-N` são lidos pela atribuição de checkout (E5) |
| `oferta_precos` | `checkout_url`, `sistema_externo`, `sku_externo` | Link por linha. O código externo aqui é **só sobrescrita**: o de-para normal é por produto, em `checkout.produto_externo` |
| `oferta_precos` | `valor_riscado` (pode ficar vazio) | Mantém a paridade na virada: dos 3 bumps, 1 não tem riscado e 1 tem um riscado que não bate com nenhuma oferta. A derivação vem depois (§6) |
| `oferta_requer` | `modo` (`carrinho` ou `posse`), `prioridade`, `grupo_exclusivo`, `ativo`, janela, `tela`, `observacao` | Absorve as 5 regras de bump e os upgrades. Várias linhas na mesma oferta significam "OU". **O modo `posse` depende de uma fonte de posse:** `crm.pessoa_produtos` (a casa da D1) tem 0 linhas, e o fato hoje está em `eduzz.ingressos`. Até lá, só `carrinho` se avalia |
| `produtos` | `produto_pai` (a edição) e colunas de **decisão** de disponibilidade (pode vender, esgotado, override) | As categorias do Summit 2027 viram produtos filhos da edição. A coluna `categoria` já existe e está vazia |

**O que não ganha coluna:**
- **Condições de pagamento, valor de referência e economia:** estão vazios nas 16 ofertas do Institute. A view de compatibilidade continua devolvendo vazio, como hoje. A porta nova pode calcular esses valores depois.
- **Procura, nota de procura e percentual vendido:** são fato derivado das vendas, gravado hoje pela cópia. Calculam-se a partir de `eduzz.ingressos` e `eduzz.vendas`, e não moram no catálogo.
- **Janela própria de bônus:** vira uma oferta de período.
- **Oferta de grupo com mínimo e máximo** (4 em 2026): vira faixa de volume.

### 3.3 Cupons, bumps e descontos por volume

- **Bump e upgrade** vão para `oferta_requer`.
- **Cupom:**
  - **Autoridade (D1).** A tabela D1 do `PROJECT_STATE.md` (21/09) dá a autoridade de "transação, fatura, refund, cupom" à `eduzz`. No checkout Eduzz, o cupom só existe se estiver cadastrado lá. Então o catálogo guarda a **política** do Mind: qual cupom vale para qual oferta, em que janela, e se o agente pode oferecê-lo. **Nunca** guarda a existência nem o valor do cupom na Eduzz. Um teste compara com a Eduzz. Isso **altera a D1** e vai explícito no pacote D2.
  - **A casa de cupom se decide independentemente do checkout próprio.** Proposta: mover `checkout.cupons` (0 linhas) para o `catalogo` e fazer dela a casa única, com uma coluna de sistema (Eduzz ou checkout próprio).
  - Na mudança, remover a regra de acesso `equipe_le_cupons` e o acesso de leitura de usuário logado, que vêm junto com a tabela.
  - `institute.calcular_desconto` continua funcionando, porque o tipo da linha acompanha a tabela.
  - O **uso** (qual pedido usou qual cupom) é fato de venda e fica em `checkout.cupom_usos`.
  - Os 3 cupons do Summit: desativados já (E0) e depois migrados como inativos.
- **Desconto por volume e disponibilidade do Summit:** só quando o Summit 2027 tiver preço. Nessa hora entram a tabela pequena de faixas (D2) e as colunas de decisão no produto. As regras de 2026 são desligadas.

### 3.4 Quem pode ler e escrever

- O schema `catalogo` continua **fechado**.
  - Hoje nem o site nem o usuário logado têm acesso ao schema.
  - Mas as 4 tabelas `oferta*` ainda dão leitura ao site e ao usuário logado.
  - Elas também têm uma regra de leitura pública que mostraria até ofertas inativas, e uma regra de edição da equipe que usa um segundo modelo de permissão.
  - A E2 revoga esses acessos e troca essas regras antes de qualquer carga.
- **Leitura:**
  - o site lê pelas views `api.*`, com acesso aberto de propósito e rodando com os direitos do dono, como hoje;
  - o agente lê por funções só do sistema.
- **Escrita:** só pelo painel `admin/`, por funções novas `mind_admin_read_ofertas` e `mind_admin_mutate_ofertas`, no molde do catálogo de produtos, e que só o sistema chama. Toda função nova nasce fechada.

---

## 4. Ordem de migração, em etapas pequenas e reversíveis

**Caminho crítico:** E0 → E1 → E2 → E4 → E5 → E6 → E9.
- A E3 (níveis) e a E7 (painel) correm em paralelo.
- A E8 vem depois.

Cada etapa é uma migration com a conferência dentro da própria transação: se a conferência falha, nada é gravado.

**E0. Paliativos e preparação.** Cada item tem gate da Adriana.
- **Muda:**
  - **Neutralizar a sincronização do Summit pelo banco**, sem deploy: revogar o direito de execução do sistema em `public.mindagent_sync_offers` e `mindagent_sync_disponibilidade`. As 2 Edges ficam sem efeito. O código da `mindagent-sync-precos` nem está no repositório.
  - Travar `mind_kit_regras_comerciais` por "vendável agora", como a versão B2B já faz.
  - Desativar os 3 cupons do Summit (dentro da casa, gate comercial) e usar códigos fictícios nos exemplos de cupom do código e dos testes.
  - Localizar o repositório do site do Institute para saber quais colunas ele lê e se filtra por `vigente`.
- **Teste:** um contrato de funções **gerado por consulta**, não por lista fixa.
  - Hoje 22 funções citam as tabelas de preço pelo nome.
  - Outras 8 dependem delas de forma indireta: as versões `_b2b` e `_b2c`, `calcular_desconto` pelo tipo de linha, e as 2 funções quebradas pelo schema de busca.
  - O contrato chama cada uma, porque essas funções só quebram quando chamadas.
- **Rollback:** devolver o direito de execução e reativar os cupons.

**E1. Aprovação D2.** Um pacote só:
- forma final das colunas;
- casa de cupom e a mudança da D1;
- categorias do Summit 2027 como produtos;
- troca de autoridade (Institute → catálogo; `mind-summit-propostas` → catálogo);
- separação dos níveis;
- **a lista de exceções de paridade da E6.**

**E2. Forma do catálogo.** Zero consumidores.
- **Muda:**
  - as colunas e regras do §3.2;
  - revogar a leitura do site e do usuário logado nas 4 tabelas `oferta*` e trocar as regras de acesso;
  - porta fechada `mind_catalogo_ofertas_vigentes`, que cruza a janela da oferta com a janela de venda do produto.
- **Teste:** contrato de forma do catálogo e contrato de permissões de funções.
- **Rollback:** remover as colunas (as tabelas estão vazias).

**E3. Separar empresa, verticais e produtos** (§3.1). Paralela e fora do caminho crítico.
- **Muda:**
  - coluna `vertical` nos playbooks;
  - aposentar `api.treble_event_bundle` e só então levar o texto da empresa para `mind.organization_content`; o texto das verticais vai para os documentos delas;
  - reescrever `mind_kit_product_intelligence`, `mind_produto_da_rota_status` e `lead_aviso_detectar`, mantendo o formato do bloco para o agente;
  - apagar `mind` e `mind-institute`. `mind-dash` só sai quando o perfil e o write-back do HubSpot usarem a vertical (gate).
- **Teste:**
  - `vendedor_b2b_prompt_contract.sql`, `product_decisioning_agent_integration.sql` e `agent_intelligence.test.mjs`;
  - os testes do painel `/catalogo`;
  - `perfil_icp_jtbd_contract.sql`, que hoje já falha (ver §7);
  - um caso novo: "institute → vendável agora = verdadeiro".
- **Rollback:** reinserir as linhas a partir de uma cópia feita na própria migration (mesmo código e id) e restaurar as funções.

**E4. Casa de cupom.** 0 linhas. Não depende de o checkout próprio voltar.
- **Muda:**
  - `checkout.cupons` passa para o `catalogo`, sem a regra de acesso da equipe e sem a leitura de usuário logado;
  - `criar_pedido`, `validar_cupom` e `salvar_cupom` são reescritas na mesma migration, ou aposentadas se o checkout próprio não voltar;
  - os 3 cupons do Summit entram como inativos.
- **Teste:** criar um pedido e validar um cupom dentro de uma transação desfeita no fim.
- **Rollback:** mover de volta e restaurar as funções.

**E5. Summit. É mudança em rota viva.**
- **Consumidores vivos:**
  - `cliente_suporte`, ativa no WhatsApp e no web, tem o bloco obrigatório `inclusoes`, servido por `mind_kit_inclusoes` (chave `ofertas_vigentes`);
  - `mindagent_chat_search` roda em todo turno do WhatsApp (chave `offers`, exigida por `concierge_retrieval_contract.sql`).
- **Muda:**
  - repontar os Kits do Summit para o catálogo **mantendo as chaves que os consumidores leem**: `ofertas_vigentes`, `offers` e, em cada oferta, `codigo`, `checkout_url` e a categoria no caminho do JSON. `procura` e `procura_nota` passam a ser calculadas das vendas, ou saem com aprovação. Mínimo e máximo de grupo vêm das faixas;
  - dividir `commercial_rules` (a conduta fica);
  - aposentar as funções de sincronização, as 2 Edges e os jobs 1 e 15;
  - revogar os acessos antigos do papel `mind_agent`.
- **`_shared/checkout-attribution.ts` é contrato desta etapa e da E6.** Ele é usado por `treble-inbound-agent`, `mindagent-chat` e `mindagent-checkout`, e:
  - só aceita como checkout oficial um link https em `*.eduzz.com`;
  - classifica o motivo com a regra `^(mind|vip|prime)-lote-\d+$` aplicada ao `codigo` que está no mesmo objeto do `checkout_url`;
  - tira a categoria do caminho no JSON.

  Os códigos vendáveis do Summit 2027 seguem esse padrão, ou o arquivo muda no mesmo PR, com deploy manual das 3 Edges. Mudar o formato sem isso muda a atribuição sem dar erro.
- **Sem carga histórica de 2026.** Ela exigiria produtos por categoria de 2026: só existe `mind-summit-2026`, e a chave (oferta, produto) impede 3 preços no mesmo produto. `summit_2026.offers` fica congelada.
- **Teste:**
  - a saída de hoje (vazia, porque há 0 ofertas ativas) idêntica antes e depois, na mesma transação;
  - um exemplo sintético no formato de 2027, numa transação desfeita, passando pela atribuição e pelo guardrail;
  - os testes `vendedor_guardrail_preco.mjs`, `vendedor_summit_smoke.mjs`, `vendedor_resposta_nao_truncada.mjs`, `mind_agent_context_contract.sql`, `concierge_retrieval_contract.sql`, `checkout_attribution.test.mjs`, `checkout_attribution_runtime.test.mjs`, `checkout_attribution_contract.sql` e `checkout_redirect_contract.test.mjs`.
- **Rollback:** restaurar as funções antigas (as tabelas antigas continuam lá).

**E6. Institute.** Tem o site no ar. **Depois de 30/09 23:59 BRT**, num horário de pouco tráfego.
- **Muda:**
  - **Carregar os 15 códigos com programa**, inclusive os inativos, os de período e o de teste, com os mesmos `ativo` e `publico`. O produto de cada um vem de `institute.programas`.
    - O carregamento completo é necessário porque `api.oferta_inclui` não filtra ativo nem janela, e `institute.abrir_acessos` a usa quando um pedido é pago.
    - Há 1 pedido real aguardando pagamento cuja oferta é de período e libera um programa bônus.
    - `cadastrar_compra_manual` aceita oferta encerrada de propósito.
    - Entram também as 5 regras de bump e os 2 bônus com programa.
    - A 16ª oferta (de teste, sem programa nem produto) não entra e não aparece em nenhuma view.
  - **Recriar `api.ofertas`, `api.bump_regras` e `api.oferta_inclui` com as mesmas colunas e os mesmos tipos:**
    - `moeda` com conversão para `character(3)`, porque o catálogo guarda como `text` e a recriação da view falha com troca de tipo;
    - vazio em valor de referência, economia e condições de pagamento, como hoje;
    - riscado lido da coluna explícita.

    Se for preciso apagar e recriar as views: refazer os acessos do site e do usuário logado, manter a execução com os direitos do dono e aposentar antes `api.admin_bumps` e `api.admin_ofertas_para_bump`, que dependem de `api.oferta_inclui`.
  - reescrever `criar_pedido`, `validar_cupom` e `cadastrar_compra_manual`; revogar os escritores antigos; congelar as 3 tabelas do Institute.
- **Passa a ler do catálogo:** site, agente e checkout, juntos, numa transação só. Por isso **não há janela de quebra**.
- **Paridade:** a saída é comparada antes e depois **dentro da mesma transação**, e não com uma foto tirada dias antes. O campo `agora` do bloco do Kit é ignorado. A diferença tem de ser zero, salvo as exceções aprovadas na E1. Exceções previsíveis:
  - os 6 bônus que são só texto (ingresso Summit 2027, todos vencidos em 30/09) deixam de aparecer no campo `bonus`, a menos que virem produto;
  - depois de 30/09, as 5 ofertas de período continuam na saída de `api.ofertas` com `vigente=false`, porque a view só filtra por ativo e público. Isso vale dos dois lados, então não é diferença. Desativá-las é decisão comercial separada.
- **Teste:**
  - as 3 views idênticas;
  - o bloco `institute_catalogo` idêntico;
  - um pedido de teste com o mesmo total;
  - os cursos liberados idênticos para os 15 códigos, incluindo o pedido pendente.
- **Não muda aqui:** o guardrail de preço. O bloco idêntico mantém a lacuna descrita no §7; a correção é separada (E8).
- **Rollback:** recriar as 3 views sobre as tabelas antigas, que continuam intactas. É imediato.

**E7. Painel de ofertas.** Pode correr em paralelo a partir da E2.
- **Muda:**
  - `mind_admin_read_ofertas` e `mind_admin_mutate_ofertas` (com criar e arquivar);
  - a rota `/admin/offers` na `mindagent-catalogo` e a tela em `admin/`;
  - `admin/src/test/navegacao.test.tsx`, que hoje exige que `/ofertas` e "Ingressos e ofertas" **não** existam no painel.
- **Pré-requisito já resolvido:** a `mindagent-catalogo` no ar é a versão 5, com health "1.2.0", igual ao repositório.
- **Deploy:** manual, depois do merge, comparando com a versão no ar.
- **Rollback:** desativar a rota.

**E8. Tirar preço de lugar errado** (§6). Gate de conteúdo e de comportamento do agente.
- Inclui derivar o preço riscado da oferta base.
- Inclui fazer o guardrail reconhecer o preço do Institute (§7).

**E9. Aposentar.** Depois de um ciclo (por exemplo, 30 dias) sem leitura das tabelas antigas. **Sem a opção que apaga em cascata**, e nesta ordem:
1. `api.admin_ofertas`, `admin_bumps`, `admin_ofertas_para_bump` e `admin_cupons`, que continuam lendo as casas antigas depois da E6.
2. `institute.oferta_bonus` antes de `institute.ofertas`, porque a regra de acesso `oferta_bonus_leitura_publica` depende de `institute.ofertas`.
3. `institute.bump_regras`, `institute.ofertas` e `summit_2026.coupons`.
4. Os escritores antigos, `mind.produtos` (depois de repontar `crm.buscar_pessoa` e `mind_calendario`), as portas legadas ou quebradas e o schema vazio "Meio de pagamento".

`summit_2026.offers` fica congelada como histórico, salvo decisão em contrário (§8).

Sobre a cascata: antes da E6, apagar `institute.ofertas` em cascata derrubaria 6 views, 3 do site e 3 do painel antigo. Depois da E6, só as do painel antigo que ainda existirem.

---

## 5. O que NÃO migra, e como passa a apontar para o catálogo

| Fica onde está | Por quê | Como se liga ao catálogo |
|---|---|---|
| `checkout.pedidos`, `pedido_itens`, `cupom_usos`, `gateway_eventos`, `vw_institute_vendas_espelho`; `learnworlds.acessos` | Fato de venda: o preço fica congelado no momento da compra | Pelo **código vendável preservado** (E6). Quando houver oferta com vários produtos, `pedido_itens` ganha o produto, o que é mudança dentro da casa |
| `checkout.produto_externo` | De-para (sistema, código externo) → produto | **Passa a ser preenchida** com os códigos Eduzz por produto (dentro da casa). A linha de preço só sobrescreve quando o código muda por oferta, como no Summit |
| `eduzz.produtos`, `produto_catalogo`, `vendas`, `ingressos` | Cópia da Eduzz, que apaga e regrava a cada 30 minutos | Pelo de-para, nunca por amarração. Um teste acusa quando o preço na Eduzz diverge da **linha vigente** do catálogo |
| `crm.vendas_historicas_mind_summit`, `pipeline_de_vendas_summit`, `empenho_summit_2026`, `contato_espelho`; `vendasdiretas.espelho` | Cópia do HubSpot e de vendas diretas; negociação é fato de negócio | Já apontam para o produto. Faltam ligações com o HubSpot para os 6 produtos de 2027 (dentro da casa, sem D2) |
| `credenciamento_summit_2026.*` | Fato de participação | Nenhuma ligação necessária |
| `institute.programas`, `programa_composicao`, `condicoes`, `faq`; `summit_2026.events`, `experiencias`, `sessions`, `event_rules`; `mind.policies` | Produto, turma, composição e textos. Não são preço | Já apontam para o produto (os programas, 6 de 6). A composição continua alimentando `api.oferta_inclui` |
| `summit_2026.offers` | Histórico de 2026, congelado | Nenhuma ligação necessária enquanto não houver produtos por categoria de 2026 |

---

## 6. Preço fora de tabela e como eliminar

| Onde | O que tem | Como eliminar |
|---|---|---|
| Playbook `vendas_institute` | 39 valores em R$ (17 distintos; parte bate com o banco, parte são somas e economias sem correspondência) e a Condição Summit | Trocar os valores por "use o bloco `institute_catalogo`", **depois** de o guardrail reconhecer esse bloco (§7). O texto é da Adriana |
| Playbooks `summit_b2c` e `summit_b2b` | Códigos de cupom escritos no texto | Remover; o cupom vem da casa de cupom |
| Comentários e testes do agente | Exemplos de cupom | Usar códigos fictícios (E0), junto com a desativação dos cupons |
| 2 documentos de conhecimento e 1 trecho vetorizado do Summit | Cupom e valores do parceiro de transporte | Não é produto do Mind. Sair da busca por semelhança, ou ficar como conteúdo do parceiro |
| `commercial_rules.desconto_individual` | "Valor final com cupom" copiado | Calcular na hora, a partir da oferta e do cupom |
| `institute.oferta_bonus` e o preço riscado dos bumps | Valor de referência copiado (6 bônus copiam o preço do Summit lote 7; dos 3 bumps, 1 não tem riscado e 1 tem um que não bate com nenhuma oferta) | Na E6 vira coluna explícita (paridade); na E8 passa a ser derivado da oferta base |
| `mindagent_sync_offers` | 3 links de checkout e "12x" escritos no código | Aposentar (E5) |
| `mind_precos_por_volume` | "12x" fixo | Ler o parcelamento da oferta |
| Texto de parcelamento das ofertas de 2026 | 1 das 21 linhas de lote difere de "valor/12" | Não herdar texto: derivar das colunas de parcelamento |
| `api.criar_oferta` | Calcula a parcela de um jeito diferente das ofertas no ar e tem limites e meios de pagamento fixos | Aposentar (E6) |
| `mind_checkout_url` e `_shared/checkout-attribution.ts` | Campanha padrão fixa do Summit 2026 | Derivar do produto (junto com a E5) |
| Produtos Eduzz de 2027 fora do Summit | Preço cadastrado igual ao da Condição Summit (7 de 7) | Mudar o preço na Eduzz em 01/10 (operacional, fora do banco). O teste de divergência da §5 passa a acusar |
| `institute.condicoes` | 4 textos narram a Condição Summit | Revisar depois de 30/09 (conteúdo da Adriana) |
| Vendas do Institute na Eduzz | Desde 15/09, **parte dos itens pagos saiu a −10% ou −20% do preço de `institute.ofertas`, sem cupom registrado** (números com a Adriana) | A regra não está em lugar nenhum do banco: cadastrar como oferta no catálogo (§8) |

---

## 7. Riscos e gates

- **D2 (aprovação da Adriana):**
  - troca de autoridade: Institute → catálogo, e `mind-summit-propostas` → catálogo para o Summit 2027;
  - **mudança da D1:** a política de cupom passa a morar no catálogo, e a Eduzz continua autoridade da existência e do valor do cupom;
  - mudança de casa: `checkout.cupons`, o texto da empresa e o das verticais;
  - regra de tipo ampliada (`condicional`) e tipo `empresa` retirado;
  - tabela nova de faixas de volume, quando vier;
  - produtos novos: as categorias do Summit 2027 e o ingresso-bônus, se entrar;
  - lista de exceções de paridade da E6.
- **Destrutivo:** apagar as linhas da empresa e das verticais (E3) e as tabelas antigas (E9). Sempre sem cascata, com cópia e conferência antes, na ordem da E9.
- **Segurança e acesso:** as revogações e trocas de regra de acesso de cada etapa estão descritas nela (E0, E2, E4, E5). Toda função nova nasce fechada. Os achados de segurança desta auditoria foram entregues à Adriana à parte, fora deste documento público.
- **Rotas vivas:**
  - `cliente_suporte` (WhatsApp e web) e a busca de todo turno do WhatsApp leem `summit_2026.offers`. A E5 é mudança em rota viva, não em tabela morta;
  - a E3 mexe nas rotas institute e dash, que estão no ar.
- **Guardrail de preço não cobre o Institute** (pela leitura do código, conferida).
  - `guardrail-preco.ts` só reconhece como oficial:
    - `valor` numérico;
    - o texto `condicoes_pagamento`;
    - as linhas de faixa de volume;
    - cupom com desconto.
  - O bloco `institute_catalogo` entrega `a_vista` e `parcelado` como texto "R$ …", sem `valor` numérico.
  - O guardrail roda em todas as rotas, e ele e o teste dele não mencionam o Institute.
  - Na rota institute do WhatsApp, uma resposta com preço tende a ser barrada e virar transferência para humano.
  - A correção (o bloco emite `valor` numérico, ou o guardrail é estendido) muda o comportamento do agente e tem gate (E8).
  - Conferido em 26/09: o bloco de fato só traz `a_vista`/`parcelado` em texto, e o guardrail roda em toda rota (`treble-inbound-agent/index.ts`). Nos logs de 22/09 a 26/09 não houve nenhum `preco_inventado` — mas também nenhuma chamada à `treble-inbound-agent` nesses dias. Ninguém foi barrado ainda porque o agente não foi chamado; quando for, a pergunta de preço do Institute tende a virar transferência.
- **Atribuição de checkout:** `_shared/checkout-attribution.ts` depende do padrão de código, do domínio Eduzz e do formato do JSON. Mudar qualquer um sem mudar o arquivo altera a atribuição sem dar erro (E5).
- **Perfil e HubSpot:** tirar `mind-dash` do catálogo tira o Dash do write-back diário do perfil no HubSpot (gate de write-back).
- **Preço exibido diferente do cobrado:** em 01/10 o site e o agente passam ao preço de balcão, e a Eduzz continua cobrando a Condição se ninguém mudar o preço lá.
- **Site e checkout:** o site do Institute está em outro repositório e lê as views continuamente. Qualquer mudança de coluna ou de tipo o derruba sem aviso, por isso a E6 exige paridade medida na mesma transação. O site do Summit continua lendo preço do `mind-summit-propostas`: haverá duas autoridades até o site do Summit 2027 ler do catálogo (gate de site).
- **Quebra silenciosa:** 22 funções citam as tabelas de preço pelo nome e outras 8 dependem delas de forma indireta. O banco não avisa quando quebram; a proteção é o contrato gerado por consulta (E0).
- **Apagar em cascata:** apagar um programa apaga as ofertas dele; apagar um produto apaga os preços dele.
- **Janela:** a E6 só depois de 30/09 23:59 BRT. A troca é numa transação só, então o site não fica fora do ar.
- **Deploy:** a `mindagent-catalogo` (E7) e as 3 Edges que usam `checkout-attribution.ts` (E5, se o arquivo mudar) são publicadas à mão e comparadas com a versão no ar. A E0 não precisa de deploy.
- **Divergências novas desta rodada:**
  - `cliente_suporte` ativa lendo a tabela de ofertas do Summit, e a busca do WhatsApp também;
  - a lacuna do guardrail no Institute;
  - os produtos Eduzz de 2027 cadastrados com o preço da Condição;
  - o contrato `perfil_icp_jtbd_contract.sql` **já falha hoje**: 3 códigos digitados errado em `intelligence.jtbd` não existem no catálogo (descoberta lateral);
  - `institute.ofertas.produto_codigo` está vazio nas 16 ofertas; o produto só se obtém pelo programa;
  - `intelligence.vertical_da_entrada` não tem chamador e só o comentário cita uma tabela de domínios que não existe no `catalogo`;
  - `ecossistema.organizacao_verticais` (19 linhas, todas "ecossistema") não serve como casa de verticais;
  - `engagement.conversas.produto_codigo` guarda números que não são produtos (cerca de 2 mil conversas, sem amarração; descoberta lateral);
  - os jobs 1 e 15 já estavam inativos;
  - a divergência de versão da `mindagent-catalogo` não existe mais.

---

## 8. Perguntas que só a Adriana responde (com recomendação)

1. **Posso tirar do catálogo as linhas `mind` e `mind-institute`**, com o texto da empresa indo para `mind.organization_content` e o de cada vertical para o documento dela? E **`mind-dash`**? Ela é o único código do Dash, e sem ela o Dash fica com zero produtos e sai dos "produtos com fit" no HubSpot. *Recomendo: sim para as duas primeiras, na E3. `mind-dash` fica como "não vende" até o perfil e o write-back usarem a vertical.*
2. **Os produtos já vendidos e inativos (edições 2025) ficam no catálogo como "não vende"?** *Recomendo: sim. O CRM e o HubSpot apontam para eles, e o painel abre filtrado por "à venda".*
3. **Precisa de uma tabela de verticais editável pelo painel?** *Recomendo: agora não. A vertical fica como a lista fixa que já existe.*
4. **O código antigo de cada oferta vira o "código vendável" da linha de preço?** E, no Summit 2027, os códigos seguem o padrão `mind|vip|prime-lote-N`? *Recomendo: sim nos dois casos. Pedidos, acessos, relatórios e a atribuição de checkout dependem deles.*
5. **Migrar o Institute só depois de 30/09, carregando os 15 códigos com programa, inclusive os inativos e os de período?** *Recomendo: sim, a partir de 01/10. Não é opcional: um pedido pendente e a liberação de cursos dependem deles.*
6. **Aprova estas exceções à paridade da E6?** Os 6 bônus que são só texto (ingresso Summit 2027, vencidos em 30/09) deixam de aparecer na lista de bônus do site. *Recomendo: aprovar, a menos que o ingresso-bônus deva virar produto. O riscado e os campos vazios ficam idênticos.*
7. **No Summit 2027, cada categoria (Mind, VIP, Prime, e o Camarote?) vira produto filho da edição?** *Recomendo: sim, criados quando o 2027 for definido.*
8. **As 28 ofertas do Summit 2026 entram no catálogo como histórico?** Isso exige criar produtos por categoria de 2026. *Recomendo: não agora. Ficam congeladas em `summit_2026.offers` como histórico; as portas novas são testadas com um exemplo sintético.*
9. **Onde mora o cupom?** *Recomendo:*
   - *o catálogo é a casa única da política de cupom (mudança da D1, explícita);*
   - *a Eduzz continua autoridade da existência e do valor;*
   - *`checkout.cupons` muda para o `catalogo` mesmo que o checkout próprio não volte;*
   - *se ele não voltar, só as funções do checkout se aposentam.*
10. **Qual regra deu −10% e −20% em parte das vendas pagas do Institute na Eduzz, sem cupom?** *Recomendo: cadastrar como oferta no catálogo.*
11. **Desconto por volume e disponibilidade só quando o Summit 2027 tiver preço?** *Recomendo: sim. Desligar já as regras de 2026 e desativar os 3 cupons.*
12. **Neutralizar hoje a sincronização de preço do Summit** revogando o acesso das funções no banco, sem deploy? *Recomendo: sim.*
13. **Dash: vai ter preço de tabela ou só proposta sob medida?** *Recomendo: proposta é negociação no HubSpot; o catálogo só recebe o Dash quando houver pacote com preço.*
14. **O catálogo passa a mandar no preço do Summit 2027 e o site do Summit passa a ler daqui?** *Recomendo: sim. Esta é a troca de autoridade D2.*
15. **Aposentar as telas de oferta, bump e cupom do `/admin` do joinmind?** *Recomendo: sim. O painel único é o `admin/`, e as views dessas telas são as primeiras a sair.*
16. **Dos 3 bumps, 1 não tem preço riscado e 1 tem um que não bate com nenhuma oferta: qual é o certo?** *Recomendo: manter como está na virada e, na E8, derivar da oferta base, com ela confirmando o número.*
17. **Quem muda o preço dos produtos do Institute na Eduzz em 01/10?** *Recomendo: definir o responsável antes de 30/09. Senão o site mostra o balcão e a Eduzz cobra a Condição.*
18. **Corrigir o guardrail para reconhecer o preço do Institute?** Muda o comportamento do agente no WhatsApp. *Recomendo: sim, na E8, antes de tirar os valores do playbook.*

---

## Como a auditoria foi feita

**Frentes**
1. **Inventário:** objetos com preço, oferta, cupom, bump e disponibilidade em todos os schemas (`information_schema`, `pg_class`, contagens agregadas).
2. **Consumidores no banco:**
   - `pg_proc`, por nome da tabela, por schema de busca e por tipo de argumento;
   - `pg_depend` e `pg_rewrite` para views;
   - `pg_policies` e acessos por papel;
   - `agentes.kit_blocos` e `agentes.canal_competencia`, para saber quais rotas estão ativas e que blocos leem;
   - `cron.job`, só o estado e o comando, sem segredos.
3. **Edge Functions:** lista e versão no ar. Leitura da `mindagent-catalogo` no ar, comparada com o repositório.
4. **Repositório (HEAD `def4bd2`):**
   - `checkout-attribution.ts`, `guardrail-preco.ts` e `treble-inbound-agent`;
   - os testes citados e `admin/src/test/navegacao.test.tsx`;
   - trechos de `PROJECT_STATE.md` (D1) e `CHECKPOINT_ATUAL.md` (D2 da casa das ofertas).
5. **Fatos de venda, só agregados:** `eduzz.vendas` e `eduzz.produtos`; `checkout.pedidos` e `pedido_itens` (contagem por status e tipo de oferta).
6. **Crítica independente:** 16 correções conferidas no banco e no repositório.
   - Confirmadas, algumas com números atualizados: as vendas Eduzz do Institute fora do preço da oferta.
   - A carga do Institute passou a ser de 15 códigos, porque a 16ª oferta não tem programa nem produto.
   - Descartada uma parte: `mind.organization_content` **já tem** índice único parcial por `slug` quando não há evento, então não precisa de índice novo.

**Limites**
- Só SELECT. Nenhuma função que escreve foi chamada, nenhuma chamada HTTP foi feita e nada foi publicado.
- Não foram lidos o código do site do Institute (outro repositório), o projeto `mind-summit-propostas` nem o código no ar da `mindagent-sync-precos` e da `treble-agent`.
- O efeito do guardrail na rota institute foi deduzido pela leitura do código, não por log.
- As contagens são de 26/09 e mudam: a cópia da Eduzz é regravada a cada 30 minutos.
- Nenhum dado pessoal, código de cupom, valor de preço ou segredo foi copiado para este documento.