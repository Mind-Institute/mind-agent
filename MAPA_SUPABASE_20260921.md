# Mapa do Supabase — inventário real de 21/09/2026

> **Inventário factual**, levantado direto do projeto `ymnmotgglsrxmjmonwjz` em
> 21/09/2026 às 15h35 UTC e cruzado com os 29 documentos da raiz e os 5 de `docs/`.
>
> Não substitui [`MAPA_DO_SISTEMA.md`](MAPA_DO_SISTEMA.md), que descreve o modelo
> mental e o fluxo. Este arquivo responde outra pergunta: **o que existe no banco,
> para que cada coisa serve, e o que tem dado dentro.**
>
> Contagens são `count(*)` exato, não estimativa do planejador. "Último" usa a coluna
> de tempo mais recente de cada tabela; `—` significa que a tabela não tem coluna de
> tempo, não que esteja parada.
>
> Versão navegável, com busca e filtro: <https://claude.ai/artifact/NKJykiXkcibPM22GJURvVG>

## Números

| | |
|---|---:|
| schemas de negócio | 21 |
| tabelas | 160 |
| views | 41 |
| funções de produto | 241 |
| funções das extensões `pgvector`/`pg_trgm` | 122 |
| Edge Functions ativas | 28 |
| cron jobs | 13 (12 ativos) |
| linhas no total | 257.879 |

Estado das 160 tabelas:

| estado | quantas | o que significa |
|---|---:|---|
| **vivo** | 31 | recebeu escrita nas últimas 48h |
| populada | 85 | tem dado, sem escrita recente — inclui tabela de referência/config |
| vazia — gate | 7 | vazia porque algo está deliberadamente desligado |
| vazia | 37 | casa criada e nunca ocupada |

## Objetivo de cada tabela, e de onde ele vem

Cada tabela abaixo carrega o objetivo que ela serve. A coluna `fonte` diz de onde esse
objetivo veio, e a diferença importa:

| fonte | quantas | o que é |
|---|---:|---|
| **declarado** | 71 | o objetivo está escrito como `COMMENT ON TABLE` na própria tabela, dentro do banco |
| **derivado** | 89 | não há comentário; o objetivo foi lido das colunas, das chaves e da migration que criou a tabela |

> **Ressalva de leitura.** O texto das 71 declaradas foi condensado para caber na
> tabela. O comentário dentro do banco costuma ser mais longo e às vezes carrega a
> razão da decisão; quando a diferença importar, `\d+` na tabela mostra o original.

As 89 derivadas são leitura, não declaração — podem estar certas e mesmo assim não
serem oficiais. O `COMMENT ON TABLE` é o único lugar onde a documentação não consegue se
separar do banco, e é por isso que fechar essas 89 é o primeiro passo da governança.

## A leitura em uma frase

O que está vivo hoje é **um eixo só**: WhatsApp/Treble entrando, identidade resolvendo,
espelhos do HubSpot girando e memória sendo escrita. Tudo que o Summit deixou para trás
está populado e parado. Das 44 tabelas vazias, 7 são decisão e 37 são capacidade que
nunca foi entregue.

## Critério de classificação

`vazia — gate` é reservado para tabela cujo vazio é consequência de uma decisão
registrada: uma flag em `concierge.feature_flags`, uma variável de ambiente ou um
dispatcher desligado. São sete:

| tabela | o que a mantém vazia |
|---|---|
| `crm.hubspot_commercial_writeback` | `HUBSPOT_COMMERCIAL_WRITEBACK_ENABLED` desligado |
| `engagement.recovery_dispatch_queue` | dispatcher com `enabled=false` e `dry_run=true` |
| `engagement.verificacoes_email` | flag `verificacao_email` |
| `engagement.contatos` | flag `oferecer_contato` |
| `concierge.proativo_fila` | flag `proativo` |
| `concierge.ciclo_estado` | flags `ciclo_briefing` / `ciclo_debrief` / `ciclo_objetivo` |
| `checkout.conversoes_enviadas` | envio de conversão para plataforma de anúncio |

As outras 37 vazias não têm gate: ou a lane nunca fechou (Play e memória segura), ou a
casa foi criada e o dado real acabou morando em outro lugar.

---

## Tabelas, por schema

### `engagement` — conversa, identidade, sessão e avaliações — o eixo de tudo

29 tabelas · 161.686 linhas · 8/29 com objetivo declarado no banco · 9 viva(s) · 12 vazia(s)

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `mensagens` | Cada fala, de pessoa ou de agente, persistida antes de qualquer etapa que possa falhar. | 48.815 | **vivo** | 2026-09-21 | derivado |
| `treble_eventos` | Eventos crus do webhook da Treble. É a fonte da janela de 24h do WhatsApp. | 42.958 | **vivo** | 2026-09-21 | declarado |
| `conversas` | Uma linha por conversa, em qualquer canal. Carrega rota, audiência, origem e UTM. | 38.255 | **vivo** | 2026-09-21 | derivado |
| `identidades` | Resolve telefone, id do Treble, e-mail do HubSpot, id da Eduzz e dispositivo para UMA pessoa. | 18.386 | **vivo** | 2026-09-21 | declarado |
| `agent_sessions` | A sessão do app: token, origem da identidade, confiança e expiração. | 5.648 | **vivo** | 2026-09-21 | derivado |
| `session_interests` | Interesse detectado na sessão, com confiança, evidência e quantas vezes apareceu. | 4.337 | **vivo** | 2026-09-21 | derivado |
| `identidade_fusoes` | Registro de fusão de identidade, com motivo e status. | 1.604 | **vivo** | 2026-09-21 | derivado |
| `dispositivos` | O navegador que acessou, por chave e user agent. | 954 | **vivo** | 2026-09-21 | derivado |
| `avaliacao_do_dia_atividade` | Nota de 0 a 5 por atividade. Ausência de linha é ausência de avaliação, nunca zero. | 320 | populada | — | declarado |
| `avaliacao_do_evento_atividade` | Nota por atividade dada na avaliação do evento. — *existe e tem dado — o checkpoint diz que esta pesquisa é sem nota por atividade* | 316 | populada | — | declarado |
| `avaliacao_do_dia` | Uma resposta por participante por dia do Summit, notas de 0 a 5. Não é NPS. — *fechou com o evento* | 39 | populada | 2026-09-18 | declarado |
| `avaliacao_do_evento` | Uma resposta por participante sobre o evento inteiro, aberta depois que ele acaba. — *pesquisa aberta até 02/10* | 18 | **vivo** | 2026-09-21 | declarado |
| `avaliacoes` | Casos de teste do agente: pergunta, contexto e o que se espera da resposta. | 14 | populada | — | derivado |
| `agente_eventos` | Evento do agente por conversa: tipo, intenção e dados. | 9 | populada | 2026-09-05 | derivado |
| `origens` | Os botões de entrada por site — fonte única do utm_source e da mensagem de abertura do bot. | 8 | populada | 2026-08-28 | declarado |
| `checkout_clicks` | Um clique no link de checkout, ligado a evento, conversa e pessoa. — *3 cliques, sendo 2 do E2E controlado* | 3 | populada | 2026-09-04 | derivado |
| `utm_sessoes` | Ponte de atribuição do site para o WhatsApp: o site registra a UTM e recebe um token curto. | 2 | populada | 2026-08-22 | declarado |
| `recovery_dispatch_queue` | A fila de envio da retomada: mensagem, horário, tentativas e lock. — *dispatcher com enabled=false e dry_run=true* | 0 | vazia — gate | — | derivado |
| `verificacoes_email` | Código de verificação por e-mail, com hash, tentativas e expiração. — *flag verificacao_email desligada* | 0 | vazia — gate | — | derivado |
| `contatos` | Pedido de contato com o time do Mind, com estado e resposta. — *flag oferecer_contato desligada — exige consentimento* | 0 | vazia — gate | — | derivado |
| `nps` | Nota e comentário de NPS por participante. — *Lane E / Play: o executor existe, o writer nunca entrou* | 0 | vazia | — | derivado |
| `sessao_feedback` | Feedback estruturado de uma sessão: nota, relevância, insight e o que faltou. — *Lane E / Play* | 0 | vazia | — | derivado |
| `evento_feedback` | Reclamação ou elogio sobre o evento, com categoria, sentimento e severidade. — *Lane E / Play* | 0 | vazia | — | derivado |
| `feedbacks` | Feedback genérico em chave e valor, sem contrato fixo. — *Lane E / Play* | 0 | vazia | — | derivado |
| `jornada_sessao` | O que a pessoa pretendia e o que de fato fez em cada sessão. — *Lane E / Play* | 0 | vazia | — | derivado |
| `jornada_eventos` | Os eventos brutos dessa jornada, por sessão. — *Lane E / Play* | 0 | vazia | — | derivado |
| `pessoa_perfil` | Preferência de idioma e escolha de anonimato da pessoa. | 0 | vazia | — | derivado |
| `avaliacao_execucoes` | O resultado de rodar cada caso contra um modelo: passou, custo e latência. | 0 | vazia | — | derivado |
| `data_requests` | Pedido de titular de dado pessoal: acesso, correção ou exclusão. — *LGPD: nenhum pedido de titular até hoje* | 0 | vazia | — | derivado |

### `crm` — espelho local do HubSpot; mirror, nunca fonte autoral

15 tabelas · 27.216 linhas · 13/15 com objetivo declarado no banco · 7 viva(s) · 6 vazia(s)

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `contato_espelho` | Espelho do Contact do HubSpot, com as ~170 propriedades do portal. Mirror, nunca fonte autoral. | 13.321 | **vivo** | 2026-09-20 | derivado |
| `vendas_historicas_mind_summit` | Deals do pipeline Vendas Históricas Mind Summit. | 7.408 | **vivo** | 2026-09-21 | declarado |
| `pipeline_leads_inbound` | Objetos Lead, não Deal, do pipeline de leads inbound. | 3.415 | **vivo** | 2026-09-21 | declarado |
| `pipeline_de_vendas_summit` | Deals do pipeline de vendas do Summit. Guarda negócios, não leads. | 2.690 | **vivo** | 2026-09-21 | declarado |
| `status_summit_hs` | Trava de idempotência do write-back de status_summit_2026: só reescreve quando muda. | 340 | **vivo** | 2026-09-21 | declarado |
| `empenho_summit_2026` | Deals do pipeline Empenho Summit 2026 — compra pública por empenho. | 25 | **vivo** | 2026-09-21 | declarado |
| `mapa_produtos` | Traduz propriedade e valor do contato HubSpot para código canônico de catalogo.produtos. | 11 | populada | — | declarado |
| `sync_estado` | Marca d'água e resultado da última sincronização, por fonte. | 5 | **vivo** | 2026-09-21 | declarado |
| `acessos` | Trilha de quem consultou dado individual do espelho: qual função, sobre quem, por qual agente. | 1 | populada | 2026-08-25 | declarado |
| `hubspot_commercial_writeback` | Fila da escrita comercial de volta no HubSpot, com hash de payload, tentativas e retry. — *HUBSPOT_COMMERCIAL_WRITEBACK_ENABLED desligado — escrita real no CRM nunca aconteceu* | 0 | vazia — gate | — | derivado |
| `leads_capturados` | Landing dos leads do formulário do site, até casarem no espelho do HubSpot. — *mind_lead_capturar não existe mais no banco* | 0 | vazia | — | declarado |
| `consents` | Consentimento por finalidade, com a versão da política e o texto exibido. | 0 | vazia | — | declarado |
| `pessoa_produtos` | O que cada pessoa já adquiriu, um registro por produto do catálogo. | 0 | vazia | — | declarado |
| `pessoa_nps` | NPS por pessoa e por produto. | 0 | vazia | — | declarado |
| `pessoas_interno` | Sinais internos por pessoa: origem, dono, estágio, engajamento. Orienta o tom; nunca é recitado. | 0 | vazia | — | declarado |

### `credenciamento_summit_2026` — participantes do Summit e fila da Yazo

4 tabelas · 16.740 linhas · 2/4 com objetivo declarado no banco · 3 viva(s)

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `yazo_envio_fila` | Fila do que precisa voltar para a Yazo, uma linha por operação. — *fila de envio da Yazo, ainda girando* | 11.252 | **vivo** | 2026-09-21 | derivado |
| `yazo_espelho` | Espelho cru do participante na Yazo, com o que ela devolve e quando ele sumiu de lá. | 2.909 | **vivo** | 2026-09-20 | derivado |
| `participantes` | Quem esteve no Summit, vindo da Yazo. A senha da origem não é trazida de propósito. | 2.577 | **vivo** | 2026-09-21 | declarado |
| `yazo_sync_state` | Estado do sync da Yazo na origem. Aqui é só leitura — serve para saber se lá está rodando. | 2 | populada | — | declarado |

### `treble` — estado da conversa de WhatsApp e escrita de volta no HubSpot

5 tabelas · 14.788 linhas · 5/5 com objetivo declarado no banco · 3 viva(s)

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `status_hs_contatos` | Trava de idempotência do write-back do status no Contato do HubSpot. | 6.127 | **vivo** | 2026-09-21 | declarado |
| `status_da_conversa` | Status da janela de 24h por telefone: aberta ou fechada. Checar antes de disparar. — *a tabela com a escrita mais recente do banco inteiro* | 5.605 | **vivo** | 2026-09-21 | declarado |
| `status_hs_leads` | Trava de idempotência do write-back do status no Lead do HubSpot. | 3.012 | **vivo** | 2026-09-21 | declarado |
| `polls` | Catálogo dos fluxos da Treble, com id, tipo e snapshot de uso. | 34 | populada | 2026-08-25 | declarado |
| `config` | Configuração do agente, como o token do webhook. Só service role. | 10 | populada | 2026-08-31 | declarado |

### `eduzz` — vendas e ingressos; prova de compra vence inferência do modelo

5 tabelas · 10.051 linhas · 0/5 com objetivo declarado no banco · 2 viva(s)

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `ingressos` | O ingresso emitido: participante, lote, status, check-in e quem comprou. — *parou junto com a venda do Summit* | 4.765 | populada | 2026-09-17 | derivado |
| `vendas` | A venda crua da Eduzz: fatura, produto, valores, taxas, cliente e UTMs. — *sincroniza a cada 30 min* | 4.731 | **vivo** | 2026-09-21 | derivado |
| `produtos` | O catálogo bruto de produtos da Eduzz, como a API devolve. | 342 | **vivo** | 2026-09-20 | derivado |
| `produto_catalogo` | A tradução curada do produto Eduzz para a linguagem do Mind: ano, categoria, lote, modalidade. | 192 | populada | 2026-09-09 | derivado |
| `hubspot_stage_config` | De-para entre evento da Eduzz e estágio do pipeline no HubSpot. | 21 | populada | 2026-07-19 | derivado |

### `pessoas` — a pessoa canônica — um id permanente para todos os canais

1 tabelas · 9.435 linhas · 1/1 com objetivo declarado no banco · 1 viva(s)

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `pessoas` | Espelho de leitura das pessoas do HubSpot, para todos os agentes. Campos internos ficam em crm.pessoas_interno. — *pessoa_id canônico e permanente — o centro do sistema* | 9.435 | **vivo** | 2026-09-21 | declarado |

### `intelligence` — o que é verdade agora: análise pós-turno, memória, retomada

15 tabelas · 16.915 linhas · 1/15 com objetivo declarado no banco · 3 viva(s) · 6 vazia(s)

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `participante_memoria` | A memória da pessoa, fato a fato, com confiança, origem, evidência e validade. | 8.930 | **vivo** | 2026-09-21 | derivado |
| `analise_conversa` | A análise assíncrona de cada conversa: o que o modelo concluiu, com qual prompt e até qual mensagem. — *análise assíncrona, a cada 15 min* | 4.850 | **vivo** | 2026-09-21 | derivado |
| `continuidade_comercial` | Estado do Silence Engine por conversa. next_review_at diz quando reavaliar, não quando mandar mensagem. | 2.279 | **vivo** | 2026-09-21 | declarado |
| `recovery_inbox` | A caixa de retomada: estado, calor, objeção, janela do WhatsApp e rascunho de mensagem. — *520 acionáveis; nada foi enviado* | 815 | populada | 2026-09-03 | derivado |
| `memoria_bloqueios` | A taxonomia do que nunca pode ser lembrado, com exemplo bloqueado e exemplo liberado. | 10 | populada | — | derivado |
| `memoria_regras` | Por tipo de memória: se pode inferir, confiança mínima e prazo de validade. | 10 | populada | — | derivado |
| `intencoes` | Padrões que mapeiam uma fala para rota, ferramenta e esforço de raciocínio. | 10 | populada | — | derivado |
| `config` | Chave e valor da Intelligence, incluindo o token que os crons usam. | 10 | populada | — | derivado |
| `sinais_comerciais` | Sinal de interesse comercial detectado na conversa, com evidência e consentimento. — *flag sinal_comercial desligada* | 1 | populada | 2026-08-25 | derivado |
| `participante_contexto` | O contexto reconstruído da pessoa: necessidades, resultados desejados, temas e prioridades. — *Lane D / memória segura* | 0 | vazia | — | derivado |
| `participante_objetivos` | A pergunta-guia da pessoa no evento, com dor, área e decisão pendente. — *Lane D / memória segura* | 0 | vazia | — | derivado |
| `perguntas_feitas` | Quais perguntas já foram feitas a esta pessoa, e se ela respondeu ou recusou. — *Lane D / memória segura* | 0 | vazia | — | derivado |
| `recomendacoes` | O que foi recomendado, por quê, com que origem e em que estado. — *Lane D / memória segura* | 0 | vazia | — | derivado |
| `dossies` | Dossiê gerado por dia e camada, com corpo e quando foi entregue. | 0 | vazia | — | derivado |
| `acessos_dado_pessoal` | Trilha de quem acessou dado pessoal: quem, qual função, sobre quem, por qual agente. — *ledger de acesso a dado pessoal nunca gravou uma linha* | 0 | vazia | — | derivado |

### `summit_2026` — Product Intelligence do Summit: grade, ofertas, regras, RAG

15 tabelas · 324 linhas · 3/15 com objetivo declarado no banco · 2 viva(s) · 2 vazia(s)

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `session_speakers` | Quem fala em cada sessão do Summit e com que papel — o vínculo canônico entre sessão e palestrante. — *81/81 vínculos canônicos* | 81 | populada | — | derivado |
| `sessions` | A grade: título, dia, horário, espaço, trilha, vagas e quais ingressos entram. | 77 | populada | 2026-09-06 | derivado |
| `knowledge_chunks` | Os pedaços pesquisáveis dessa base, com embedding e índice lexical. — *29 de 29 com embedding gerado* | 29 | populada | — | derivado |
| `knowledge_documents` | A base de conhecimento do Summit, com hash para detectar mudança. | 29 | populada | 2026-09-03 | derivado |
| `offers` | A oferta do Summit: código, valor, condições, checkout, elegibilidade e janela. — *preço sincronizado a cada 30 min* | 28 | **vivo** | 2026-09-21 | derivado |
| `locations` | Cada espaço dentro do local, com hierarquia, apelidos e como chegar. | 27 | populada | 2026-09-02 | derivado |
| `route_edges` | Como ir de um espaço a outro: instruções, distância, minutos e se é acessível. | 21 | populada | 2026-08-20 | derivado |
| `event_rules` | Regras do evento por chave, com onde se aplicam e prioridade. | 16 | populada | 2026-09-06 | derivado |
| `commercial_rules` | Regras que o agente consulta antes de agir. O campo config é o contrato legível por máquina. | 7 | **vivo** | 2026-09-21 | declarado |
| `experiencias` | As experiências do Summit e suas inclusões. Mirror local de uma fonte congelada no design. | 4 | populada | — | declarado |
| `coupons` | Cupons que o agente pode validar. Nasce inativo, para nunca valer por acidente. | 3 | populada | 2026-09-05 | declarado |
| `events` | O evento: slug, dias, local, cidade e fuso. | 1 | populada | 2026-08-22 | derivado |
| `venues` | O local físico, com endereço, transporte, acessibilidade e mapa. | 1 | populada | 2026-08-29 | derivado |
| `registrations` | Inscrição de uma pessoa no evento, com categoria de ingresso. — *a inscrição real mora em credenciamento e eduzz.ingressos* | 0 | vazia | — | derivado |
| `exhibitors` | Expositores, com local, categoria e contato. — *expositores nunca cadastrados* | 0 | vazia | — | derivado |

### `institute` — programas, ofertas e FAQ do braço de capacitação

13 tabelas · 126 linhas · 6/13 com objetivo declarado no banco · 1 vazia(s)

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `faq` | Pergunta e resposta por escopo, ordenadas. | 31 | populada | — | derivado |
| `programa_encontros` | Um registro por encontro ao vivo. É daqui que as datas da turma são derivadas. | 28 | populada | 2026-09-13 | declarado |
| `ofertas` | A oferta comercial do programa: valor, parcelas, meios de pagamento, checkout e janela. — *a escrita mais recente do Institute* | 16 | populada | 2026-09-18 | derivado |
| `condicoes` | Condições comerciais exibidas no site. Termos legais versionados ficam em mind.policies. | 11 | populada | 2026-09-13 | declarado |
| `programa_pessoas` | Vínculo pessoa e programa com papel. A pessoa vem sempre de pessoas.pessoas. | 9 | populada | 2026-09-08 | declarado |
| `oferta_bonus` | Os bônus de cada oferta, com valor de referência e se é gratuito. | 8 | populada | — | derivado |
| `programa_inclusoes` | O que está incluído no programa, como texto ordenado. | 7 | populada | — | derivado |
| `programas` | Um registro por programa: tipo, carga horária, duração, modalidade e janela. | 6 | populada | 2026-09-13 | derivado |
| `bump_regras` | Se o programa X está no carrinho, ofereça a oferta Y. Uma linha por par. | 5 | populada | 2026-09-11 | declarado |
| `programa_composicao` | A Certificação contém as três formações; incluso=false permite exibir item não incluído. | 3 | populada | — | declarado |
| `knowledge_chunks` | Os pedaços pesquisáveis dos documentos do Institute, com embedding e índice lexical. — *1 chunk, sem embedding — a busca vetorial do Institute não existe* | 1 | populada | — | derivado |
| `knowledge_documents` | Os documentos de conhecimento do Institute, com hash para detectar mudança na origem. | 1 | populada | 2026-09-02 | derivado |
| `programa_material` | Documentos públicos de cada programa. Guarda a URL, nunca o arquivo. | 0 | vazia | — | declarado |

### `concierge` — config, flags, avisos e ferramentas do agente do app

14 tabelas · 177 linhas · 1/14 com objetivo declarado no banco · 3 vazia(s)

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `templates` | Texto pronto por chave, idioma e canal, com as variáveis que aceita. | 40 | populada | — | derivado |
| `ferramentas` | Catálogo do que o agente pode chamar: schema, destino, timeout, se escreve e se exige confirmação. | 30 | populada | — | derivado |
| `avisos` | Avisos da home do participante. Escritos pelo painel admin, lidos pelo bootstrap do app. | 27 | populada | 2026-09-07 | declarado |
| `config` | Chave e valor de configuração do agente — é aqui que mora a janela da avaliação do evento. — *janela da avaliação do evento mora aqui* | 26 | populada | 2026-09-18 | derivado |
| `regras_proativas` | As regras que decidiriam quando falar primeiro: gatilho, condição, cooldown e janela silenciosa. — *18 regras escritas, motor desligado* | 18 | populada | — | derivado |
| `feature_flags` | Liga e desliga capacidade do agente sem deploy. — *13 flags: 1 ligada, 12 desligadas* | 13 | populada | — | derivado |
| `tutorial_passos` | Os passos do tutorial do app: título, tela e alvo de cada um. | 9 | populada | — | derivado |
| `prompts` | Prompts históricos do Concierge, versionados. — *histórico — a casa canônica hoje é agentes.prompts* | 7 | populada | 2026-08-20 | derivado |
| `integracao_logs` | Log de chamada a sistema externo por participante: payload, resposta, status e latência. | 5 | populada | 2026-09-02 | derivado |
| `ferramenta_chamadas` | Ledger de cada chamada de ferramenta, com entrada, saída, latência e chave de idempotência. — *ledger do executor Play: uma única chamada em toda a história* | 1 | populada | 2026-09-02 | derivado |
| `config_revisao` | O número de revisão da config, para o app saber quando recarregar. | 1 | populada | 2026-09-18 | derivado |
| `proativo_fila` | Fila de mensagem proativa agendada, com canal e chave de dedupe. — *flag proativo desligada* | 0 | vazia — gate | — | derivado |
| `ciclo_estado` | Em que etapa do ciclo briefing e debrief cada participante está. — *flags ciclo_briefing / ciclo_debrief / ciclo_objetivo desligadas* | 0 | vazia — gate | — | derivado |
| `config_auditoria` | Trilha de quem mudou qual config, com o antes e o depois. — *auditoria de mudança de config nunca gravou* | 0 | vazia | — | derivado |

### `checkout` — checkout próprio — hoje só o Institute passa por aqui

9 tabelas · 34 linhas · 8/9 com objetivo declarado no banco · 5 vazia(s)

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `pedidos` | Uma linha por tentativa de compra. Nasce aguardando; o webhook é que promove para pago. | 11 | populada | 2026-09-17 | declarado |
| `pedido_itens` | O que foi comprado, com nome e valor copiados da oferta no instante da compra. | 11 | populada | — | declarado |
| `compradores` | Quem comprou pelo site, sem login. E-mail é a chave natural. | 6 | populada | 2026-09-17 | declarado |
| `gateway_eventos` | Tudo que o gateway enviou ou respondeu, cru. O webhook da InfinitePay não é assinado: este log é a prova. | 6 | populada | 2026-09-12 | declarado |
| `conversoes_enviadas` | Uma linha por pedido já enviado ao GA4 e ao Meta. Garante que webhook reenviado não duplique conversão. — *envio de conversão para plataforma de anúncio desligado* | 0 | vazia — gate | — | declarado |
| `cupons` | Cupons de desconto. O desconto é calculado dentro de api.criar_pedido, nunca no navegador. — *cupom do Summit vive em summit_2026.coupons* | 0 | vazia | — | declarado |
| `cupom_usos` | Quem usou qual cupom, em que pedido e com que desconto. | 0 | vazia | — | derivado |
| `pedido_tracking` | Identificadores de origem por pedido: UTMs, click ids e cookies de GA4, Meta e HubSpot. | 0 | vazia | — | declarado |
| `produto_externo` | De-para entre o identificador que o gateway usa e o produto do Mind. | 0 | vazia | — | declarado |

### `ecossistema` — inteligência perene de palestrantes e organizações

6 tabelas · 126 linhas · 6/6 com objetivo declarado no banco

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `palestrantes_especialistas` | Palestrantes e especialistas do ecossistema. A mesma pessoa palestra no Summit e pode dar aula no Institute. | 64 | populada | 2026-09-03 | declarado |
| `organizacoes` | Uma organização existe uma vez — antes as marcas apareciam repetidas em Summit, Institute e Dash. | 19 | populada | 2026-09-08 | declarado |
| `organizacao_verticais` | Onde cada organização aparece. Vertical ecossistema significa marca-mãe, sem frente atribuída. | 19 | populada | — | declarado |
| `afirmacoes` | Par afirmação e fonte. Referência nula é afirmação publicada sem fonte declarada. | 10 | populada | — | declarado |
| `perfis_publicos` | A camada editorial pública de uma pessoa. A identidade canônica continua em pessoas.pessoas. | 9 | populada | 2026-09-08 | declarado |
| `referencias` | Citação verbatim como o site publica. | 5 | populada | — | declarado |

### `agentes` — a casa canônica dos playbooks e dos blocos do Kit

3 tabelas · 72 linhas · 3/3 com objetivo declarado no banco

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `kit_blocos` | Qual bloco entra no Kit de cada rota, qual provider o serve e em que seção aparece. | 37 | populada | — | declarado |
| `prompts` | Os blocos do prompt, um por linha. Trocar comportamento aqui é UPDATE, não deploy. — *casa canônica dos playbooks, incluindo router_universal v4* | 23 | populada | 2026-09-17 | declarado |
| `canal_competencia` | Quais competências o Router pode escolher em cada canal. Não decide qual rota — só quais são possíveis. | 12 | populada | — | declarado |

### `catalogo` — vocabulário canônico de produto

5 tabelas · 17 linhas · 4/5 com objetivo declarado no banco · 4 vazia(s)

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `produtos` | Um registro por produto do Mind. Fonte única do vocabulário que CRM, conhecimento e agentes referenciam. | 17 | populada | 2026-09-13 | declarado |
| `ofertas` | A condição comercial: nome, janela, liga e desliga. Uma oferta cobre vários produtos — por isso lote não é tabela. — *a oferta real vive em summit_2026.offers e institute.ofertas* | 0 | vazia | — | declarado |
| `oferta_precos` | O preço de cada produto dentro de uma oferta, com parcelamento e ordem de exibição. | 0 | vazia | — | derivado |
| `oferta_inclui` | Os bônus como linhas, não colunas fixas. Pendura no par (oferta, produto). | 0 | vazia | — | declarado |
| `oferta_requer` | A oferta só aparece se o carrinho já contém este produto. Condição de carrinho, não de tempo. | 0 | vazia | — | declarado |

### `public` — painel admin e estado dos espelhos

5 tabelas · 145 linhas · 5/5 com objetivo declarado no banco · 1 viva(s)

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `mind_admin_editorial` | O fluxo editorial dos recursos do painel. | 111 | populada | 2026-08-20 | declarado |
| `mind_admin_audit` | Trilha append-only das ações administrativas autenticadas. | 23 | populada | 2026-09-02 | declarado |
| `espelho_estado` | Uma linha por fonte espelhada de outro projeto Supabase. — *estado dos 5 espelhos do HubSpot* | 9 | **vivo** | 2026-09-21 | declarado |
| `mind_admin_event_details` | Campos do evento que só o admin vê, fora da tabela operacional. | 1 | populada | 2026-08-21 | declarado |
| `mind_admin_users` | Quem pode entrar no painel administrativo. | 1 | populada | 2026-08-20 | declarado |

### `platform` — provedores de LLM e observabilidade

6 tabelas · 10 linhas · 1/6 com objetivo declarado no banco · 2 vazia(s)

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `llm_routes` | Por rota: qual papel de modelo usar, fallback, esforço, streaming e cache de prompt. | 4 | populada | — | derivado |
| `integracoes` | Como o Mind fala com sistemas de fora. secret_ref é o NOME da variável — o valor nunca entra no banco. | 3 | populada | 2026-08-23 | declarado |
| `llm_models` | Cada modelo: papel, janela de contexto, custo por milhão de tokens e capacidades. | 2 | populada | — | derivado |
| `llm_providers` | Os provedores de modelo disponíveis, com referência ao segredo e URL base. | 1 | populada | — | derivado |
| `llm_calls` | Uma linha por chamada de LLM: tokens, cache, custo, latência e motivo de parada. — *zero registro de chamada de LLM — não há observabilidade de custo ou latência* | 0 | vazia | — | derivado |
| `embeddings_config` | Qual provedor, modelo e dimensão usar para gerar embedding. | 0 | vazia | — | derivado |

### `dash` — base de conhecimento do Mind Dash

2 tabelas · 2 linhas · 0/2 com objetivo declarado no banco

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `knowledge_chunks` | Os pedaços pesquisáveis desses documentos, com embedding e índice lexical. — *1 chunk, sem embedding* | 1 | populada | — | derivado |
| `knowledge_documents` | Documentos de conhecimento do Mind Dash, com hash para detectar mudança. | 1 | populada | 2026-09-02 | derivado |

### `learnworlds` — produtos e acessos da plataforma de curso

2 tabelas · 6 linhas · 2/2 com objetivo declarado no banco

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `produtos` | Em que curso ou bundle do LearnWorlds cada programa matricula. Dado, não código. | 4 | populada | 2026-09-12 | declarado |
| `acessos` | O que cada comprador tem direito de acessar no LMS. A fila é o contrato entre a venda e o LMS. | 2 | populada | 2026-09-12 | declarado |

### `mind` — políticas e conteúdo institucional

2 tabelas · 6 linhas · 0/2 com objetivo declarado no banco · 1 vazia(s)

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `policies` | Termos legais versionados, por chave e versão. | 6 | populada | 2026-08-20 | derivado |
| `organization_content` | Conteúdo institucional por categoria e slug, com janela de validade. | 0 | vazia | — | derivado |

### `seguranca` — equipe e segredos

2 tabelas · 3 linhas · 2/2 com objetivo declarado no banco

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `segredos` | Hashes de segredos do servidor, separados para que conhecer a URL do webhook não autorize confirmar pagamento. | 2 | populada | — | declarado |
| `equipe` | Quem tem acesso ao painel. Revogar é um DELETE, com efeito imediato. | 1 | populada | — | declarado |

### `eventos` — base de conhecimento genérica de eventos

2 tabelas · 0 linhas · 0/2 com objetivo declarado no banco · 2 vazia(s)

| tabela | objetivo | linhas | estado | último | fonte |
|---|---|---:|---|---|---|
| `knowledge_chunks` | Os pedaços pesquisáveis desses documentos. — *schema de conhecimento genérico, nunca ocupado* | 0 | vazia | — | derivado |
| `knowledge_documents` | Mesma estrutura de conhecimento dos outros produtos, para eventos genéricos. | 0 | vazia | — | derivado |
---

## Funções

241 funções de produto. As 122 de `pgvector`/`pg_trgm` instaladas em `public` não
entram nesta conta — são das extensões, não do Mind.

| onde | quantas |
|---|---:|
| `public` | 180 |
| `api` | 36 |
| `institute` | 8 |
| `crm` | 4 |
| `mind`, `concierge` | 3 cada |
| `ecossistema` | 2 |
| `intelligence`, `pessoas`, `credenciamento_summit_2026`, `eduzz`, `seguranca` | 1 cada |

O sistema é quase todo RPC: o Agent não conhece a topologia das tabelas, ele pede
o Kit da rota. Por isso a lista de funções descreve melhor o produto do que a
lista de tabelas.

### Core do runtime — Kit, Gate e Contexto (23)

`mind_agent_context` · `mind_agent_kit` · `mind_rota_capacidade` · `mind_kit_meta` ·
`mind_kit_evento` · `mind_kit_evento_b2b` · `mind_kit_programacao` ·
`mind_kit_programacao_filtrada` · `mind_kit_ofertas` · `mind_kit_ofertas_b2b` ·
`mind_kit_precos_por_volume` · `mind_kit_precos_por_volume_b2b` ·
`mind_kit_regras_comerciais` · `mind_kit_regras_comerciais_b2b` ·
`mind_kit_inclusoes` · `mind_kit_inclusoes_b2b` · `mind_kit_inclusoes_b2c` ·
`mind_kit_product_intelligence` · `mind_kit_product_intelligence_b2b` ·
`mind_kit_product_intelligence_b2c` · `mind_kit_customer_intelligence` ·
`mind_kit_customer_intelligence_contextual` · `mind_kit_delegacao_corporativa`

### Identidade e conversa (8)

`mind_identidade_resolver` · `mind_inbound` · `mind_conversa_resolver` ·
`mind_conversa_estado` · `mind_mensagem_registrar` · `mind_turno_registrar` ·
`mind_pessoa_completar` · `mind_pessoa_fatos`

### App e Concierge (13)

`mindagent_chat_start` · `mindagent_chat_bind_identity` · `mindagent_chat_get_context` ·
`mindagent_chat_save_message` · `mindagent_chat_save_interests` · `mindagent_chat_search` ·
`mindagent_bootstrap` · `mindagent_home_publico` · `mindagent_participante_ingresso` ·
`mindagent_sync_disponibilidade` · `mindagent_sync_offers` ·
`mindagent_treble_claim_event` · `mindagent_treble_complete_event`

### Treble / WhatsApp (24)

`treble_agent_start` · `treble_agent_context` · `treble_agent_context_base` ·
`treble_agent_prompt` · `treble_agent_config` · `treble_agent_identificar` ·
`treble_agent_token` · `treble_agent_resposta_repetida` · `treble_status_ciclo` ·
`treble_status_recompute` · `treble_status_marcar` · `treble_status_confirmar` ·
`treble_status_confirmar_contato` · `treble_status_pendentes` ·
`treble_status_pendentes_contato` · `treble_evento_gravar` · `treble_sessao_backfill` ·
`treble_sessao_encerrada_gravar` · `treble_cta_da_conversa` · `treble_origem_da_cta` ·
`treble_momento` · `treble_materiais` · `treble_find_location` · `treble_poll_sincronizado`

`mind_lead_capturar` **não existe mais** no banco.

### Intelligence e busca híbrida (10)

`mind_intelligence_buscar` · `mind_intelligence_buscar_contextual` ·
`mind_intelligence_ler` · `mind_intelligence_ler_contextual` ·
`mind_intelligence_chunks_pendentes` · `mind_intelligence_embedding_registrar` ·
`mind_knowledge_preparar_chunks` · `mind_customer_intelligence` ·
`mind_credenciamento_fatos` · `mind_engagement_fatos`

### Pós-turno, memória e continuidade (16)

`analise_pendentes` · `analise_montar_contexto` · `analise_gravar` ·
`analise_projetar_memoria` · `analise_prompt` · `analise_config` ·
`silence_claim_pendentes` · `silence_montar_contexto` · `silence_registrar_decisao` ·
`silence_sync_from_analysis` · `silence_calcular_next_review` ·
`silence_compra_summit_2026` · `silence_ultimo_evento` · `silence_chave_timing` ·
`silence_liberar_lock` · `silence_ts`

`public.mind_memoria_fatos` **não existe** — a lane D segue aberta, como o checkpoint diz.

### Espelhos do HubSpot e CRM (20)

`mind_espelho_disparar` · `mind_espelho_ligar` · `mind_espelho_gravar` ·
`mind_espelho_carga_inicial` · `mind_espelho_reconciliar` · `mind_espelho_ids` ·
`mind_espelho_remover` · `mind_espelho_remover_objeto` · `espelho_config` ·
`espelho_gravar` · `espelho_estado_set` · `espelho_para_mind` · `mind_crm_fatos` ·
`mind_crm_comercial` · `mind_crm_vincular_pessoa` · `mind_crm_sync_frescor` ·
`crm.buscar_pessoa` · `crm.contexto_comercial` · `crm.registrar_lead` · `crm.normalizar_pessoa`

### Write-back comercial no HubSpot (5) — desligado

`hubspot_commercial_candidates` · `hubspot_commercial_reserve` ·
`hubspot_commercial_confirm` · `hubspot_commercial_fail` · `pessoa_vincular_hubspot`

### Checkout e retomada (14)

`mind_checkout_url` · `mind_checkout_click_registrar` · `mind_checkout_envio_registrar` ·
`mind_checkout_event_purchase_status` · `mind_checkout_abandonment_refresh` ·
`mind_recovery_refresh` · `mind_recovery_save_draft` · `mind_recovery_claim_drafts` ·
`mind_recovery_purchase_status` · `mind_recovery_delivery_slot` ·
`mind_recovery_prepare_queue` · `mind_recovery_claim_dispatch` · `mind_utm_registrar` ·
`mind_virada_de_lote`

### Avaliação do Summit (9)

`mind_avaliacao_do_dia_estado` · `mind_avaliacao_do_dia_registrar` ·
`mind_avaliacao_do_dia_relatorio` · `mind_avaliacao_do_dia_respostas` ·
`mind_avaliacao_do_evento_estado` · `mind_avaliacao_do_evento_registrar` ·
`mind_avaliacao_do_evento_relatorio` · `mind_avaliacao_do_evento_respostas` ·
`concierge.resumo_do_dia`

Nenhuma função `mind_avaliacao_do_evento_convite_*` existe — o gate da Adriana está intacto.

### Play — executor de ações (2)

`mind_play_chamada_iniciar` · `mind_play_chamada_concluir`

O transporte existe e é idempotente; os writers da lane E nunca entraram. Por isso
`concierge.ferramenta_chamadas` tem uma única linha em toda a história.

### Identidade, pendência e normalização (13)

`mind_identificador_validar` · `mind_identificadores_normalizar` ·
`mind_identificador_declarado_registrar` · `mind_conflito_registrar` ·
`mind_pendencia_resolver` · `mind_pendencias_listar` · `mind_nome_bate` ·
`mind_nome_conflita` · `mind_nome_simples` · `telefone_normalizar` ·
`pessoas.resolver_por_telefone` · `crm.normalizar_pessoa` · `mind.pessoa_atual`

### Sync do Summit e da Eduzz (11)

`summit_sync_programacao` · `summit_status_pendentes` · `summit_status_confirmar` ·
`summit_contato_criar_pendentes` · `summit_motivo_exclusao` · `mind_sync_abrir` ·
`mind_sync_marcar` · `mind_sync_incremental_marcar` · `mind_sync_arquivados_marcar` ·
`mind_sync_reconciliacao_marcar` · `eduzz.normalizar_contato`

### Painel admin e conteúdo do app (14)

`mind_admin_dashboard_counts` · `mind_admin_read_home_config` ·
`mind_admin_mutate_home_config` · `mind_admin_read_home_notices` ·
`mind_admin_mutate_home_notice` · `mind_admin_read_resource` ·
`mind_admin_mutate_resource` · `mind_conteudo` · `mind_calendario` · `mind_foto_url` ·
`mind_material_link` · `mind_materiais_para` · `mind_slug` · `mind_origem`

### Camada `api` — a superfície REST (36)

`me` · `quem_sou` · `my_context` · `my_data` · `contact` · `event` · `sessions` ·
`speakers` · `knowledge` · `mindagent_bootstrap` · `mindagent_home_publico` ·
`mindagent_participante_ingresso` · `criar_pedido` · `confirmar_pagamento` ·
`cadastrar_compra_manual` · `dados_do_pagamento` · `validar_cupom` · `salvar_cupom` ·
`criar_oferta` · `salvar_oferta` · `criar_bump` · `salvar_bump` · `remover_bump` ·
`registrar_link` · `registrar_atribuicao` · `registrar_retorno` ·
`registrar_provisionamento` · `fila_de_provisionamento` · `fila_de_avisos` ·
`marcar_aviso` · `marcar_acesso` · `aviso_do_pedido` · `changed_since` ·
`treble_route` · `treble_event_bundle` · `treble_find_location`

### Institute, LGPD e utilitários (19)

`institute.abrir_acessos` · `institute.abrir_acessos_do_pedido` ·
`institute.calcular_desconto` · `institute.limitar_pedidos` ·
`institute.documento_valido` · `institute.cpf_valido` · `institute.cnpj_valido` ·
`institute.brl` · `mind.esquecer_participante` · `mind.tocar` · `seguranca.eh_equipe` ·
`ecossistema.slugify` · `ecossistema.palestrantes_slug_bi` ·
`intelligence.vertical_da_entrada` · `credenciamento_summit_2026.normalizar_contato` ·
`concierge.aplicar_evento_jornada` · `concierge.bump_config_revisao` ·
`mind_txt_corta` · `mind_urlencode`

### Views (41)

`api` 24 · `concierge` 4 · `intelligence` 4 · `eduzz` 2 · `engagement` 2 ·
`checkout` 1 · `credenciamento_summit_2026` 1 · `crm` 1 · `mind` 1 · `extensions` 2

---

## Edge Functions — 28, todas `ACTIVE`

Neste repositório não há `supabase/config.toml`, então merge em `main` **não**
publica Edge Function. As versões abaixo são as vivas, lidas do projeto.

| função | versão | JWT | papel |
|---|---:|---|---|
| `mindagent-chat` | 44 | sim | Concierge do app + executor das ações de Play |
| `treble-inbound-agent` | 59 | webhook próprio | o cérebro do WhatsApp |
| `mindagent-avaliacao` | 3 | não | as duas pesquisas do Summit; `/convite/*` responde 503 |
| `router` | 7 | não | Router como serviço |
| `mindagent-bootstrap` | 19 | não | conteúdo do app na abertura |
| `mindagent-home` | 4 | não | Home e avisos |
| `mindagent-checkout` | 3 | não | clique, UTMs e redirect para Eduzz oficial |
| `mindagent-recovery` | 4 | sim | refresh do inbox e rascunho; sem envio |
| `mindagent-index-knowledge` | 5 | não | embeddings; só aceita `service_role` |
| `mindagent-admin` | 19 | não | painel administrativo |
| `mindagent-sync-precos` | 8 | não | preço do Summit |
| `mindagent-sync-disponibilidade` | 4 | não | disponibilidade |
| `analisar-conversa` | 12 | não | análise pós-turno |
| `silence-reavaliar` | 5 | não | continuidade; cron desligado |
| `hubspot-sync` | 20 | sim | espelho do HubSpot |
| `hubspot-commercial-writeback` | 5 | sim | escrita comercial; desligada por variável |
| `hubspot-diag` | 10 | sim | diagnóstico |
| `eduzz-espelho-sync` | 8 | não | vendas e ingressos |
| `eduzz-diag` | 11 | não | diagnóstico |
| `summit-programacao-sync` | 8 | não | grade, sessões e palestrantes |
| `treble-agent` | 11 | não | compatibilidade |
| `treble-api` | 8 | não | compatibilidade |
| `treble-webhook` | 6 | não | compatibilidade |
| `treble-sessoes-sync` | 7 | não | sessões |
| `treble-status-hubspot` | 9 | não | status de volta no HubSpot |
| `treble-find-location` | 21 | não | onde é a sala |
| `treble-disparo` | 8 | sim | existe — e existir não autoriza outbound |
| `treble-diag` | 7 | sim | diagnóstico |

---

## Cron — 13 jobs, 12 ativos

| job | quando | o que dispara | estado |
|---|---|---|---|
| `analise_conversas` | a cada 15 min | `analisar-conversa` | ativo |
| `mindagent-sync-precos` | a cada 30 min | `mindagent-sync-precos` | ativo |
| `eduzz_espelho_sync` | aos :20 e :50 | `eduzz-espelho-sync` | ativo |
| `treble_status_dia` | 30 em 30 min, 11h–23h | `treble_status_ciclo()` | ativo |
| `treble_status_noite` | 2 em 2 horas, 0h–10h | `treble_status_ciclo()` | ativo |
| `hubspot-contatos-diario` | 06h17 | espelho de Contacts | ativo |
| `hubspot-leads-inbound-diario` | 06h20 | espelho de Leads | ativo |
| `hubspot-negocios-diario` | 06h23 | espelho de Deals | ativo |
| `hubspot-historicos-diario` | 06h26 | espelho de histórico | ativo |
| `hubspot-empenho-2026-diario` | 06h29 | espelho de empenho | ativo |
| `hubspot-ligacoes-diario` | 06h35 | `mind_espelho_ligar()` | ativo |
| `mindagent-sync-disponibilidade-diaria` | 21h00 | `mindagent-sync-disponibilidade` | ativo |
| `silence_reavaliar` | a cada 5 min | `silence-reavaliar` | **desligado** |

Não existe cron de disparo outbound. O sistema observa, classifica e prepara;
ele não envia.

---

## Divergências entre o sistema real e a documentação

A regra do repositório é **sistema real vence documentação desatualizada**. Isto é
o que o banco disse e os documentos não dizem, em ordem de quanto muda uma decisão.

### 1. A avaliação do evento tem nota por atividade — e o checkpoint diz que não tem

`CHECKPOINT_ATUAL.md` lista, entre as decisões congeladas da lane, "sem nota por
atividade, de propósito". Mas `engagement.avaliacao_do_evento_atividade` existe,
tem colunas `avaliacao_id` / `sessao_id` / `nota` e **316 linhas**. A migration
`20260918180000_avaliacao_do_evento_atividades.sql` está no repositório e foi
aplicada.

São 316 notas por sessão que o documento diz não existirem. Ou a decisão mudou e o
checkpoint não acompanhou, ou a migration subiu sem a decisão. **É gate da Adriana
resolver qual das duas.**

### 2. Os embeddings do Summit existem — o checkpoint diz que são zero

`CHECKPOINT_ATUAL.md` registra "embeddings continuam pendentes: 30 chunks, zero
vetores". Real: `summit_2026.knowledge_chunks` tem **29 chunks e 29 embeddings**.
A busca vetorial do Summit está completa.

O que continua sem vetor é outra coisa: `institute.knowledge_chunks` e
`dash.knowledge_chunks` têm 1 chunk cada, os dois sem embedding. A lupa desses dois
produtos é só lexical.

### 3. 84 das 160 tabelas não aparecem em documento nenhum

Os 29 documentos da raiz e os 5 de `docs/` citam 76 tabelas. As outras 84 existem
e não são nomeadas em lugar algum — entre elas o schema `checkout` inteiro (9
tabelas, com pedidos reais do Institute), o `institute` inteiro (13), os 3 espelhos
da Yazo com 16 mil linhas e `platform.llm_calls`.

Não é dívida de escrita: é capacidade fora do modelo mental de quem retoma o
projeto lendo a raiz. O Institute e o checkout próprio são os maiores ausentes.

### 4. As versões vivas das Edge Functions estão muito à frente dos documentos

`IMPLEMENTATION_STATUS.md` registra `mindagent-chat` v37 e `treble-inbound-agent`
v38; `CHECKPOINT_ATUAL.md` registra a Treble na v41. Real: `mindagent-chat` está na
**44** e `treble-inbound-agent` na **59**. A `mindagent-avaliacao` está na **3**.

São 18 publicações da Treble depois do último número escrito. Como o deploy é
manual neste repositório, o número da Edge é a única prova do que está no ar.

### 5. O banco tem 463 migrations; o repositório tem 370 arquivos

`supabase_migrations.schema_migrations` tem 463 versões, e os carimbos não batem
com os nomes dos arquivos — a avaliação do evento é `20260918120000` no repo e
`20260918202202` no banco.

O repositório não é espelho do banco: migrations foram aplicadas pelo SQL Editor,
como o próprio runbook manda. Consequência prática: **nunca usar `supabase db push`
aqui**, e a lista de arquivos não responde "isto está aplicado?".

### 6. `platform.llm_calls` está vazia — não há observabilidade de custo nem de latência

`platform.llm_providers` tem 1 linha, `llm_models` 2 e `llm_routes` 4.
`platform.llm_calls` tem **zero**.

Cada turno do Concierge e do vendedor chama a OpenAI, e nenhuma dessas chamadas foi
registrada. Hoje não há como responder quanto custou um turno, quanto demorou, ou
qual rota gasta mais — só o que os incidentes mediram à mão.

### 7. O legado `mind_lead_capturar` não existe mais no banco

`MAPA_DO_SISTEMA.md` diz, na seção de legado vivo temporário, que "a Edge Treble
viva v1.3.0 ainda chama `mind_lead_capturar`". A função **não existe** em `public`,
a Edge viva é a v59 e `crm.leads_capturados` tem zero linhas.

Boa notícia, e o mapa antigo deveria dizer isso: o legado que se pedia para não
reconstruir já morreu sozinho.

### 8. O gate do convite por link está intacto

Confirmado: `engagement.avaliacao_do_evento_convite` não existe, e nenhuma função
`mind_avaliacao_do_evento_convite_*` existe. As rotas `/convite/*` da Edge respondem
503, exatamente como o checkpoint descreve.

Registrado aqui porque um gate que aguenta é tão informativo quanto um que vazou.

---

## Observação de segurança, sem ação tomada

RLS está ligado em 135 das 160 tabelas. As 25 sem RLS se concentram em
`crm` (7 de 15), `treble` (4 de 5), `intelligence` (3), `summit_2026` (3),
`dash` (2), `eventos` (2), `institute` (2), `catalogo` (1) e `platform` (1).

Não investiguei se cada uma dessas 25 está exposta via PostgREST ou só alcançável
por `service_role` — isso é auth/RLS e portanto **gate da Adriana**. Fica registrado
como divergência a investigar, não como mudança a fazer.
