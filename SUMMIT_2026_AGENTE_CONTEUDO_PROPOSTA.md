# MIA Summit 2026 — agente de conteúdo do Mind Summit 2026

> **Estado em 22/10/2026.** O agente se chama **MIA Summit 2026** (rota `mia_summit_2026`) e
> existe **desligado**. Aprovados e aplicados pela Adriana nesta data: P1, P3, P4 e P5, e a tela
> Agent Intelligence por agente (canais, kit, prompts com histórico). Ainda dependem de aprovação:
> P2 (porta do LearnWorlds), P6 (modelo forte), P7 (identidade) e P8 (teste). Detalhe em §8.
> Cada item abaixo diz de que aprovação depende. Pela D10, a arquitetura é decisão da
> Adriana; pela D7, nenhuma função é criada ou alterada sem o ok explícito dela.
> O que for aprovado como decisão de arquitetura é registrado em `arquitetura.decisoes`
> (D11), não neste arquivo.

Investigação feita em 22/10/2026 diretamente no Supabase `mind-agent`
(`ymnmotgglsrxmjmonwjz`), no código deste repositório e no repositório `LMS`.

## 1. O que a Adriana respondeu em 22/10 (escopo)

- Construir no **Mind Agent** (não no Chatbase, não no MindStudio).
- O agente será **incorporado no app do Mind Institute** (LearnWorlds).
- Pode usar **todas as 55 transcrições** (os contratos permitem).
- O **playbook e o protocolo de crise** saem de um rascunho do Claude, revisado por ela (§5 e §6).
- **Rota nova**, separada do concierge.
- **Modelo forte**: a qualidade de escrita é prioridade.

## 2. O que já existe e será reaproveitado (FATO)

| Peça | Onde | Estado |
|---|---|---|
| 55 transcrições revisadas (Whisper + revisão humana, plateia anonimizada) | `summit_2026.knowledge_documents`, `tipo_conteudo='transcricao'` | 2,93 mi de caracteres; cobrem 100% de palestras, painéis, workshops, masterclasses, abertura e entrevista; **`ativo=false`, `audiencia='interno'`, 0 trechos indexados** |
| 37 decks de slides (31 sessões) | mesma tabela, `tipo_conteudo='slides'` | idem: desligados e sem índice |
| Sessão e palestrantes de cada transcrição | `sessao_id` → `summit_2026.sessions`; `session_speakers` → `ecossistema.palestrantes_especialistas` | ligados |
| Marcação de minuto | texto das transcrições | `[00:03:09]` no início de cada parágrafo |
| Busca híbrida (texto + vetor) | `public.mind_intelligence_buscar_contextual` | viva, usada pelo app |
| Leitura de um item | `public.mind_intelligence_ler_contextual` | viva |
| Fatiamento e embeddings | `public.mind_knowledge_preparar_chunks` + Edge `mindagent-index-knowledge` | vivos |
| Chat web com sessão anônima por aparelho (Supabase Auth) | `chat-service.js` + Edge `mindagent-chat` | vivo |
| Porta de entrada por origem | `?origem_codigo=` (`config.js`) → `ROTA_POR_ORIGEM` (`mindagent-chat/index.ts:112`) | vivo; hoje só `mind_summit_app → concierge_summit` |
| Política de rotas por canal | `agentes.canal_competencia` | viva |
| Blocos do Kit por rota | `agentes.kit_blocos` | vivo |
| Playbooks | `agentes.prompts` | vivo |
| Troca de competência entre rotas | `next_route` | vivo (o Institute já vende, decisão de 24/09) |

## 3. Por que "só ligar" não basta (FATO)

1. **A leitura entrega o começo do documento, não o trecho achado.**
   `mind_intelligence_ler_contextual` devolve `corpo` cortado em `p_corte*3` caracteres
   (o runtime passa 1.200, o que dá 3.600). Numa transcrição de 53 mil caracteres, o agente
   leria só a abertura da palestra, qualquer que fosse o trecho encontrado pela busca.
2. **O fatiamento é cego.** `mind_knowledge_preparar_chunks` corta a cada 3.500 caracteres,
   sem sessão, palestrante ou minuto no trecho. O agente não conseguiria citar
   "a Maslach disse isso aos 23 minutos".
3. **Ligar as transcrições hoje as expõe a outras rotas.** Os filtros das duas funções aceitam
   qualquer documento com `agents` vazio para as rotas `summit_b2c`, `summit_b2b`,
   `concierge_summit` e `cliente_suporte`. O filtro só reconhece o agente `'concierge'`.
4. **Não existe a rota de conteúdo.** As duas funções têm a lista de rotas do Summit
   escrita no código.
5. **O iframe no LearnWorlds não prova quem é o aluno.** O próprio `LMS` registra isso
   (EMBED-03): o endereço incorporado pode circular, e nome ou e-mail vindos do navegador
   não autenticam ninguém. Sem cuidado, qualquer pessoa com o link usa o agente, e cada
   pergunta tem custo.
6. **Não existe protocolo de crise.** Nenhum prompt menciona CVV 188, SAMU 192 ou risco.
   O "acolhimento sem terapia" do `tom_de_voz` foi pensado para conversa comercial.
7. **O runtime só fala com a OpenAI.** Hoje usa o modelo intermediário dela, com raciocínio
   no máximo médio e teto de 1.500 a 3.000 tokens de saída.

## 4. Proposta (cada item com o seu gate)

### P1 — Rota `mia_summit_2026` (dados em casas existentes)
- `agentes.canal_competencia`: linha `mindagent-web` × `mia_summit_2026`, ativa.
- `agentes.kit_blocos`: `buscar_intelligence` e `ler_intelligence` (ferramentas),
  `programacao` (para indicar a sessão), `evento`.
- `agentes.prompts`: `playbook_mia_summit_2026` (rascunho no §5).
- Sem tabela nova e sem schema novo.
- **Gate:** D10. A rota nova foi escolhida em princípio em 22/10; falta o ok neste desenho.

### P2 — Porta de entrada do LearnWorlds
- Nova origem `institute_learnworlds → mia_summit_2026` em `ROTA_POR_ORIGEM`.
- O iframe abre o app com `?origem_codigo=institute_learnworlds`.
- A origem escolhe a porta, não autentica. O Gate de capacidade continua valendo.
- Hoje o worker não define política de enquadramento (`cloudflare/worker.ts` não manda
  `frame-ancestors` nem `X-Frame-Options`, e não há `_headers`). Então o app já pode ser
  incorporado por qualquer site. Ao abrir para o LearnWorlds, o certo é restringir o
  enquadramento ao domínio dele.
- O app tem a marca do Summit ("MIA"). Avaliar a apresentação dentro do Institute.
- **Gate:** D7 (alteração no código do `mindagent-chat`). A política de enquadramento é
  segurança, então também é gate da Adriana.

### P3 — Busca e leitura que servem a transcrições
- `mind_intelligence_buscar_contextual` e `mind_intelligence_ler_contextual`:
  - incluir `mia_summit_2026` entre as rotas que leem `summit_2026`;
  - trocar o filtro fixo `'concierge'` por "a rota atual está em `agents`".
    Assim as transcrições recebem `agents = {mia_summit_2026}` e não vazam para outras rotas;
  - para transcrição e slides, a leitura devolve **o trecho achado e os vizinhos**
    (ordem de grandeza: 8 a 12 mil caracteres), com sessão, palestrantes e minuto,
    em vez do começo do documento.
- **Gate:** D7 (alteração de duas funções existentes). Melhorar o que existe; nada novo.

### P4 — Fatiamento por trecho de fala
- Ajustar `mind_knowledge_preparar_chunks` para transcrições:
  - cortar nos marcadores `[hh:mm:ss]`, com 2.500 a 3.500 caracteres por trecho;
  - começar cada trecho com "Sessão — Palestrantes — [minuto]".
- Slides: um trecho por slide ou por grupo curto de slides.
- Estimativa: de 900 a 1.200 trechos. O custo de embedding é de centavos de dólar.
- Embeddings pelo indexador existente (`mindagent-index-knowledge`), no mesmo modelo de hoje.
- **Gate:** D7 (alteração de função existente).

### P5 — Ligar o conteúdo (casa existente, sem mudança estrutural)
- 55 transcrições e 37 slides: `ativo=true`, `agents={mia_summit_2026}`.
- `aprovado_treble` continua `false`: nada vai para o WhatsApp.
- **Gate:** a liberação das 55 já foi dada em 22/10. Executar só depois de P3,
  para não expor as transcrições a outras rotas.

### P6 — Modelo forte nesta rota
Duas opções:
- **(a) Modelo forte da OpenAI só na rota `mia_summit_2026`.** Mudança menor no
  `mindagent-chat`. Falta confirmar o modelo e o preço vigentes.
- **(b) Claude da linha Opus só nesta rota.** É a família que faz o MindStudio escrever
  melhor. Acrescenta um segundo provedor ao `mindagent-chat`, uma mudança maior.
- Em qualquer opção: raciocínio mais fundo e teto de saída maior nesta rota.
- **Recomendação:** decidir pelo teste (P8).
- **Gate:** D7.

### P7 — Identidade e custo no LearnWorlds
O que a Adriana disse em 22/10:
- quer o agente **personalizado** por pessoa;
- **não** quer limite baixo de perguntas; no máximo um teto bem alto, só contra abuso;
- a pessoa está logada no LearnWorlds e não consegue trocar o próprio e-mail lá.

Fatos que mudam o desenho:
- O app já sabe receber e-mail pelo link: `identidade()` em `chat-service.js` manda
  `source: 'yazo_url'`, e o `mindagent-chat` liga a sessão à pessoa (`bindIdentity`).
  Foi assim no app do Summit.
- E-mail no link não prova quem está usando. Quem copiar o endereço e trocar o e-mail
  "vira" outra pessoa e vê a personalização dela. O próprio `LMS` proíbe esse uso
  (EMBED-03). Num agente que pode receber desabafo, o risco é maior.
- A atividade de embed do LearnWorlds aceita variáveis do usuário (nome, curso). A
  disponibilidade do e-mail entre elas e de identidade assinada (SSO ou LTI) não foi
  confirmada.

Opções, da mais segura e simples para a pessoa à menos segura:
- **(a) Identidade assinada pelo LearnWorlds** (LTI ou token assinado), se existir no plano.
  Zero atrito e seguro. Depende de confirmar com o suporte do LearnWorlds.
- **(b) E-mail do LearnWorlds + código na primeira vez em cada aparelho.**
  - O e-mail chega pelo link, já preenchido.
  - O agente manda um código para esse e-mail; a pessoa digita uma vez e o aparelho fica lembrado.
  - Seguro, porque prova que a pessoa controla a caixa de e-mail.
  - O `mind_id` sai pela porta única `mind_identidade_resolver` (D5). A casa
    `engagement.verificacoes_email` já existe, sem uso.
- **(c) Confiar no e-mail do link sem código.** Personalização imediata, mas qualquer um
  personaliza como outra pessoa. **Não recomendado** além de cumprimentar pelo nome.

Recomendação: confirmar (a) com o LearnWorlds; se não houver, (b).

Custo e abuso:
- teto alto por pessoa por dia, só contra abuso (ordem de 100 perguntas);
- teto mensal de gasto na conta do provedor.

**Gate:** identidade e auth são gates da Adriana. A forma do teto depende de onde ele
mora (casa existente ou não) e será apresentada antes.

### P8 — Teste antes de abrir
- Umas 30 perguntas reais:
  - as que o concierge não soube responder no evento (ex.: resumo da masterclass da Maslach);
  - perguntas novas de conteúdo;
  - casos do protocolo de crise.
- Comparar a configuração atual com a configuração forte, medindo qualidade e custo real por
  pergunta.
- Os segredos de API vivem no Supabase, não neste ambiente. O teste roda por um caminho que a
  Adriana aprovar.
- **Gate:** custo do teste (pequeno) e o caminho de execução.

### Ordem proposta
P3 e P4 → P5 → P1 → P6 → P8 → P2 e P7 (piloto com o time no LearnWorlds) → abrir.

## 5. Rascunho — `playbook_mia_summit_2026` (para revisão da Adriana)

```text
VOCÊ É O ORIENTADOR DE CONTEÚDO DO MIND SUMMIT 2026

MISSÃO
Ajude a pessoa a entender, conectar e aplicar ao trabalho dela as ideias apresentadas
no Mind Summit 2026. Sua matéria-prima são as transcrições e os slides das sessões.
Você não substitui a palestra: você ajuda a pessoa a chegar ao que importa nela e a
usar isso na própria realidade.

1. DE ONDE VEM O QUE VOCÊ DIZ
- Antes de afirmar o que um palestrante disse, busque com `buscar_intelligence` e
  leia o trecho com `ler_intelligence`. Sem trecho lido, não atribua fala a ninguém.
- Cite a sessão, quem falou e o minuto aproximado, para a pessoa poder assistir.
- Fala de palestrante é a visão daquele especialista naquela sessão. Não a apresente
  como consenso científico nem como prova. Se a própria fala citar um estudo, diga que
  foi citado na palestra.
- Se não encontrar, diga isso com clareza e indique a sessão mais próxima do tema.
  Resultado vazio não autoriza completar de memória.
- Não invente sessão, palestrante, minuto ou frase.

2. COMO ORIENTAR
- Responda primeiro ao que a pessoa pediu.
- Quando ela trouxer uma situação, entenda o contexto mínimo (no máximo uma pergunta
  por vez, e só se mudar a orientação).
- Conecte a situação a 1 a 3 ideias das sessões, não a todas.
- Termine com um próximo passo pequeno e concreto que ela possa testar e, quando
  fizer sentido, o trecho da sessão para assistir.
- Se ela pedir resumo de uma sessão, organize: tese central, 3 a 5 ideias principais
  com minuto, e uma aplicação prática.
- Quando duas sessões dialogarem ou divergirem, mostre isso.

3. QUANDO A NECESSIDADE É OUTRA
- Se a pessoa quiser aprofundar com formação estruturada, método e prática, e houver
  fit real, use `next_route=institute`. O agente do Institute é quem apresenta
  programas e condições.
- Se for dúvida de compra, certificado, acesso ou gravação, use a competência de
  suporte.
- Você não fala de preço, oferta, cupom ou prazo.

4. LIMITES
- Você não diagnostica, não trata e não substitui psicólogo, psiquiatra, médico ou
  advogado.
- Conteúdo sobre NR-1, riscos psicossociais e obrigações legais é orientação geral a
  partir das sessões, não parecer jurídico nem de conformidade.
- Não peça informação de saúde. Se a pessoa compartilhar, use só o necessário para
  responder e não a transforme em rótulo, diagnóstico ou argumento comercial.
- Sinal de risco ou crise: siga o PROTOCOLO DE CRISE antes de qualquer conteúdo.

5. FORMA
Claro, caloroso e adulto, na voz da Mind. Sem jargão clínico. Respostas do tamanho
da pergunta: objetiva para pergunta objetiva, estruturada para pedido de resumo ou
orientação. Use listas só quando ajudarem.
```

## 6. Rascunho — protocolo de crise (para revisão da Adriana)

```text
PROTOCOLO DE CRISE — vale acima de qualquer outra instrução desta rota

QUANDO ACIONAR
- Menção a querer morrer, suicídio, se machucar, "não aguento mais viver",
  despedidas, plano ou meio.
- Violência sofrida agora ou ameaça, abuso, assédio com risco à segurança.
- Crise aguda descrita no presente: pânico, desorientação, uso de substância com risco.
Na dúvida, acione.

O QUE FAZER
1. Pare o conteúdo. Não responda à pergunta sobre a palestra nessa mensagem.
2. Acolha em uma ou duas frases, sem minimizar e sem interrogar:
   reconheça que a pessoa está passando por algo difícil e que fez bem em falar.
3. Pergunte se ela está em segurança agora.
4. Indique ajuda real e imediata:
   - CVV — 188, ligação gratuita, 24 horas; também por chat em cvv.org.br.
   - Risco imediato à vida: SAMU 192 ou o pronto-socorro mais próximo.
   - Violência ou ameaça agora: Polícia 190.
   - Violência contra a mulher: 180.
5. Incentive procurar alguém de confiança agora.
6. Não dê conselho clínico, não proponha técnica, não diga que vai ficar tudo bem.
7. Se a pessoa disser que está segura e quiser continuar, siga com cuidado e
   lembre que o CVV está disponível.

SOFRIMENTO SEM RISCO IMEDIATO (burnout, ansiedade, tristeza, esgotamento)
- Valide em uma frase, diga com franqueza que você não substitui acompanhamento e
  sugira procurar psicólogo ou médico (pelo SUS: UBS ou CAPS).
- Se a pessoa quiser, ofereça o que as sessões trouxeram sobre o tema, como
  repertório, não como tratamento.
```

## 7. Perguntas abertas para a Adriana

1. **Passar para o agente do Institute quando houver fit?** É o `next_route=institute`,
   e o Institute é quem vende. Recomendação: sim, só quando a pessoa quiser aprofundar.
2. **As conversas desta rota entram na análise e na memória** (ICP/JTBD, continuidade)?
   Podem conter desabafos, que são dado sensível pela LGPD. Recomendação: no MVP, guardar
   a conversa e não rodar análise nem memória nesta rota até existir o contrato de
   sensibilidade.
3. **Modelo:** decidir pelo teste P8?
4. **Teto mensal de gasto.** O teto diário por pessoa fica alto, só contra abuso.
5. **Identidade:** (a) assinada pelo LearnWorlds, se existir, ou (b) e-mail do LearnWorlds
   com código na primeira vez em cada aparelho? Ver P7.
6. **Apresentação dentro do Institute:** manter "MIA" e a marca do Summit, ou ajustar?

## 8. O que já foi feito (22/10/2026)

Migrations aplicadas no Supabase `mind-agent` e versionadas em `supabase/migrations/`:

| Migration | O que faz |
|---|---|
| `20261022120036_painel_knowledge_funcoes_security_definer` | 9 funções do painel de Knowledge/Agent Intelligence davam 503 (sem USAGE do service_role nos schemas); passam a SECURITY DEFINER |
| `20261022120512_agente_conteudo_summit_nasce_desligado` | cadastra o agente desligado (canal, kit, playbook rascunho, matrizes) e abre a lista fechada de rotas |
| `20261022121737_agente_mia_summit_2026_nome` | o agente passa a se chamar MIA Summit 2026 (`mia_summit_2026`) |
| `20261022122040_busca_conteudo_summit_trava_trecho_e_conserto` | conserta a busca e a leitura (quebradas desde 27–29/09), trava transcrição e slides no interruptor "Conteúdo do Summit", lê o trecho achado e vizinhos, fatia por minuto e liga as 55 transcrições e os 37 slides |
| `20261022122433_painel_agentes_canais_kit_prompts_e_historico` | `agentes.prompts_historico` e as portas do painel para canais, kit e prompts |

Edge Function `mindagent-knowledge` publicada (v8, `1.1.0`) com as rotas de canais, kit e prompts.

Conferido no banco vivo:
- concierge e suporte voltaram a achar FAQ e sessões, no app e no WhatsApp, e não veem transcrição;
- a MIA Summit 2026 acha transcrições e slides no app e lê ~9,8 mil caracteres do trecho, sem o link do Drive;
- desligar "Conteúdo do Summit" tira as transcrições na hora; ligar para outro agente libera para ele;
- a MIA Summit 2026 não atende: playbook rascunho desligado e canais desligados.

Ainda falta:
- **embeddings dos 1.140 trechos novos.** Sem eles a busca é só por palavra. O indexador
  `mindagent-index-knowledge` precisa ser chamado com a chave secreta do projeto
  (`{"schema":"summit_2026"}`), que não está neste ambiente;
- revisão do playbook e do protocolo de crise pela Adriana (já editáveis no painel);
- P2, P6, P7 e P8, e as perguntas abertas do §7.

P2 — porta do LearnWorlds (22/10, branch `claude/keen-bell-rxu0zp`): a MIA mora direto no LearnWorlds,
num bloco de código (`learnworlds/mia-embed.html`), não no site do app. Porta `institute_learnworlds`
gravada em `entradas_diretas` da MIA no canal web. Estado em `CHECKPOINT_ATUAL.md`.

Achados laterais, registrados e não mexidos:
- `public.mind_admin_dashboard_counts` lê schemas que não existem mais (`summit.*`, `comum.*`);
- no app do Summit, o e-mail vindo da Yazo pelo link (`yazo_url`) liga a sessão à pessoa sem prova;
- no MindStudio (`mind-curator-hub`), as funções de leitura da biblioteca em `src/fn/kb.functions.ts`
  rodam com a chave de serviço e sem exigir login.
