# Mapa do Supabase — inventário real de 21/09/2026

> **Inventário factual**, levantado direto do projeto `ymnmotgglsrxmjmonwjz` em
> 21/09/2026 às 15h35 UTC e cruzado com os 29 documentos da raiz e os 5 de `docs/`.
>
> Não substitui [`MAPA_DO_SISTEMA.md`](MAPA_DO_SISTEMA.md), que descreve o modelo
> mental e o fluxo. Este arquivo responde outra pergunta: **o que existe no banco,
> o que tem dado dentro e o que nunca recebeu uma linha.**
>
> Contagens são `count(*)` exato, não estimativa do planejador. "Último registro"
> usa a coluna de tempo mais recente de cada tabela; `—` significa que a tabela não
> tem coluna de tempo, não que esteja parada.
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

## A leitura em uma frase

O que está vivo hoje é **um eixo só**: WhatsApp/Treble entrando, identidade
resolvendo, espelhos do HubSpot girando e memória sendo escrita. Tudo que o Summit
deixou para trás está populado e parado. Das 44 tabelas vazias, 7 são decisão e
37 são capacidade que nunca foi entregue.

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

As outras 37 vazias não têm gate: ou a lane nunca fechou (Play e memória segura),
ou a casa foi criada e o dado real acabou morando em outro lugar.

---

## Tabelas, por schema

### `engagement` — conversa, identidade, sessão e avaliações — o eixo de tudo

29 tabelas · 161.686 linhas · 9 viva(s) · 12 vazia(s)

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `mensagens` | 48.815 | **vivo** | 2026-09-21 | cada fala persistida antes de qualquer etapa que possa falhar |
| `treble_eventos` | 42.958 | **vivo** | 2026-09-21 | ledger bruto do webhook do WhatsApp |
| `conversas` | 38.255 | **vivo** | 2026-09-21 |  |
| `identidades` | 18.386 | **vivo** | 2026-09-21 | e-mail, WhatsApp, HubSpot e auth apontando para a mesma pessoa |
| `agent_sessions` | 5.648 | **vivo** | 2026-09-21 |  |
| `session_interests` | 4.337 | **vivo** | 2026-09-21 | interesses com marca de sensibilidade |
| `identidade_fusoes` | 1.604 | **vivo** | 2026-09-21 | fusões registradas; conflito nunca faz merge automático |
| `dispositivos` | 954 | **vivo** | 2026-09-21 |  |
| `avaliacao_do_dia_atividade` | 320 | populada | — | notas por sessão dos dois dias do Summit |
| `avaliacao_do_evento_atividade` | 316 | populada | — | existe e tem dado — o checkpoint diz que esta pesquisa é sem nota por atividade |
| `avaliacao_do_dia` | 39 | populada | 2026-09-18 | fechou com o evento |
| `avaliacao_do_evento` | 18 | **vivo** | 2026-09-21 | pesquisa aberta até 02/10 |
| `avaliacoes` | 14 | populada | — |  |
| `agente_eventos` | 9 | populada | 2026-09-05 |  |
| `origens` | 8 | populada | 2026-08-28 |  |
| `checkout_clicks` | 3 | populada | 2026-09-04 | 3 cliques, sendo 2 do E2E controlado |
| `utm_sessoes` | 2 | populada | 2026-08-22 |  |
| `recovery_dispatch_queue` | 0 | vazia — gate | — | dispatcher com enabled=false e dry_run=true |
| `verificacoes_email` | 0 | vazia — gate | — | flag verificacao_email desligada |
| `contatos` | 0 | vazia — gate | — | flag oferecer_contato desligada — exige consentimento |
| `nps` | 0 | vazia | — | Lane E / Play: o executor existe, o writer nunca entrou |
| `sessao_feedback` | 0 | vazia | — | Lane E / Play |
| `evento_feedback` | 0 | vazia | — | Lane E / Play |
| `feedbacks` | 0 | vazia | — | Lane E / Play |
| `jornada_sessao` | 0 | vazia | — | Lane E / Play |
| `jornada_eventos` | 0 | vazia | — | Lane E / Play |
| `pessoa_perfil` | 0 | vazia | — |  |
| `avaliacao_execucoes` | 0 | vazia | — |  |
| `data_requests` | 0 | vazia | — | LGPD: nenhum pedido de titular até hoje |

### `crm` — espelho local do HubSpot; mirror, nunca fonte autoral

15 tabelas · 27.216 linhas · 7 viva(s) · 6 vazia(s)

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `contato_espelho` | 13.321 | **vivo** | 2026-09-20 | espelho dos Contacts do HubSpot |
| `vendas_historicas_mind_summit` | 7.408 | **vivo** | 2026-09-21 |  |
| `pipeline_leads_inbound` | 3.415 | **vivo** | 2026-09-21 |  |
| `pipeline_de_vendas_summit` | 2.690 | **vivo** | 2026-09-21 |  |
| `status_summit_hs` | 340 | **vivo** | 2026-09-21 |  |
| `empenho_summit_2026` | 25 | **vivo** | 2026-09-21 |  |
| `mapa_produtos` | 11 | populada | — |  |
| `sync_estado` | 5 | **vivo** | 2026-09-21 |  |
| `acessos` | 1 | populada | 2026-08-25 |  |
| `hubspot_commercial_writeback` | 0 | vazia — gate | — | HUBSPOT_COMMERCIAL_WRITEBACK_ENABLED desligado — escrita real no CRM nunca aconteceu |
| `leads_capturados` | 0 | vazia | — | mind_lead_capturar não existe mais no banco |
| `consents` | 0 | vazia | — |  |
| `pessoa_produtos` | 0 | vazia | — |  |
| `pessoa_nps` | 0 | vazia | — |  |
| `pessoas_interno` | 0 | vazia | — |  |

### `credenciamento_summit_2026` — participantes do Summit e fila da Yazo

4 tabelas · 16.740 linhas · 3 viva(s)

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `yazo_envio_fila` | 11.252 | **vivo** | 2026-09-21 | fila de envio da Yazo, ainda girando |
| `yazo_espelho` | 2.909 | **vivo** | 2026-09-20 |  |
| `participantes` | 2.577 | **vivo** | 2026-09-21 | quem esteve no Summit, por categoria de ingresso |
| `yazo_sync_state` | 2 | populada | — |  |

### `treble` — estado da conversa de WhatsApp e escrita de volta no HubSpot

5 tabelas · 14.788 linhas · 3 viva(s)

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `status_hs_contatos` | 6.127 | **vivo** | 2026-09-21 |  |
| `status_da_conversa` | 5.605 | **vivo** | 2026-09-21 | a tabela com a escrita mais recente do banco inteiro |
| `status_hs_leads` | 3.012 | **vivo** | 2026-09-21 |  |
| `polls` | 34 | populada | 2026-08-25 |  |
| `config` | 10 | populada | 2026-08-31 |  |

### `eduzz` — vendas e ingressos; prova de compra vence inferência do modelo

5 tabelas · 10.051 linhas · 2 viva(s)

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `ingressos` | 4.765 | populada | 2026-09-17 | parou junto com a venda do Summit |
| `vendas` | 4.731 | **vivo** | 2026-09-21 | sincroniza a cada 30 min |
| `produtos` | 342 | **vivo** | 2026-09-20 |  |
| `produto_catalogo` | 192 | populada | 2026-09-09 |  |
| `hubspot_stage_config` | 21 | populada | 2026-07-19 |  |

### `pessoas` — a pessoa canônica — um id permanente para todos os canais

1 tabelas · 9.435 linhas · 1 viva(s)

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `pessoas` | 9.435 | **vivo** | 2026-09-21 | pessoa_id canônico e permanente — o centro do sistema |

### `intelligence` — o que é verdade agora: análise pós-turno, memória, retomada

15 tabelas · 16.915 linhas · 3 viva(s) · 6 vazia(s)

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `participante_memoria` | 8.930 | **vivo** | 2026-09-21 | memória e interesses do pós-turno |
| `analise_conversa` | 4.850 | **vivo** | 2026-09-21 | análise assíncrona, a cada 15 min |
| `continuidade_comercial` | 2.279 | **vivo** | 2026-09-21 |  |
| `recovery_inbox` | 815 | populada | 2026-09-03 | 520 acionáveis; nada foi enviado |
| `memoria_bloqueios` | 10 | populada | — | taxonomia canônica de sensibilidade |
| `memoria_regras` | 10 | populada | — |  |
| `intencoes` | 10 | populada | — |  |
| `config` | 10 | populada | — |  |
| `sinais_comerciais` | 1 | populada | 2026-08-25 | flag sinal_comercial desligada |
| `participante_contexto` | 0 | vazia | — | Lane D / memória segura |
| `participante_objetivos` | 0 | vazia | — | Lane D / memória segura |
| `perguntas_feitas` | 0 | vazia | — | Lane D / memória segura |
| `recomendacoes` | 0 | vazia | — | Lane D / memória segura |
| `dossies` | 0 | vazia | — |  |
| `acessos_dado_pessoal` | 0 | vazia | — | ledger de acesso a dado pessoal nunca gravou uma linha |

### `summit_2026` — Product Intelligence do Summit: grade, ofertas, regras, RAG

15 tabelas · 324 linhas · 2 viva(s) · 2 vazia(s)

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `session_speakers` | 81 | populada | — | 81/81 vínculos canônicos |
| `sessions` | 77 | populada | 2026-09-06 |  |
| `knowledge_chunks` | 29 | populada | — | 29 de 29 com embedding gerado |
| `knowledge_documents` | 29 | populada | 2026-09-03 |  |
| `offers` | 28 | **vivo** | 2026-09-21 | preço sincronizado a cada 30 min |
| `locations` | 27 | populada | 2026-09-02 |  |
| `route_edges` | 21 | populada | 2026-08-20 |  |
| `event_rules` | 16 | populada | 2026-09-06 |  |
| `commercial_rules` | 7 | **vivo** | 2026-09-21 |  |
| `experiencias` | 4 | populada | — |  |
| `coupons` | 3 | populada | 2026-09-05 |  |
| `events` | 1 | populada | 2026-08-22 |  |
| `venues` | 1 | populada | 2026-08-29 |  |
| `registrations` | 0 | vazia | — | a inscrição real mora em credenciamento e eduzz.ingressos |
| `exhibitors` | 0 | vazia | — | expositores nunca cadastrados |

### `institute` — programas, ofertas e FAQ do braço de capacitação

13 tabelas · 126 linhas · 1 vazia(s)

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `faq` | 31 | populada | — |  |
| `programa_encontros` | 28 | populada | 2026-09-13 |  |
| `ofertas` | 16 | populada | 2026-09-18 | a escrita mais recente do Institute |
| `condicoes` | 11 | populada | 2026-09-13 |  |
| `programa_pessoas` | 9 | populada | 2026-09-08 |  |
| `oferta_bonus` | 8 | populada | — |  |
| `programa_inclusoes` | 7 | populada | — |  |
| `programas` | 6 | populada | 2026-09-13 |  |
| `bump_regras` | 5 | populada | 2026-09-11 |  |
| `programa_composicao` | 3 | populada | — |  |
| `knowledge_chunks` | 1 | populada | — | 1 chunk, sem embedding — a busca vetorial do Institute não existe |
| `knowledge_documents` | 1 | populada | 2026-09-02 |  |
| `programa_material` | 0 | vazia | — |  |

### `concierge` — config, flags, avisos e ferramentas do agente do app

14 tabelas · 177 linhas · 3 vazia(s)

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `templates` | 40 | populada | — |  |
| `ferramentas` | 30 | populada | — |  |
| `avisos` | 27 | populada | 2026-09-07 | os avisos da Home do app |
| `config` | 26 | populada | 2026-09-18 | janela da avaliação do evento mora aqui |
| `regras_proativas` | 18 | populada | — | 18 regras escritas, motor desligado |
| `feature_flags` | 13 | populada | — | 13 flags: 1 ligada, 12 desligadas |
| `tutorial_passos` | 9 | populada | — |  |
| `prompts` | 7 | populada | 2026-08-20 | histórico — a casa canônica hoje é agentes.prompts |
| `integracao_logs` | 5 | populada | 2026-09-02 |  |
| `ferramenta_chamadas` | 1 | populada | 2026-09-02 | ledger do executor Play: uma única chamada em toda a história |
| `config_revisao` | 1 | populada | 2026-09-18 |  |
| `proativo_fila` | 0 | vazia — gate | — | flag proativo desligada |
| `ciclo_estado` | 0 | vazia — gate | — | flags ciclo_briefing / ciclo_debrief / ciclo_objetivo desligadas |
| `config_auditoria` | 0 | vazia | — | auditoria de mudança de config nunca gravou |

### `checkout` — checkout próprio — hoje só o Institute passa por aqui

9 tabelas · 34 linhas · 5 vazia(s)

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `pedidos` | 11 | populada | 2026-09-17 | checkout próprio — só o Institute passa por aqui |
| `pedido_itens` | 11 | populada | — |  |
| `compradores` | 6 | populada | 2026-09-17 |  |
| `gateway_eventos` | 6 | populada | 2026-09-12 |  |
| `conversoes_enviadas` | 0 | vazia — gate | — | envio de conversão para plataforma de anúncio desligado |
| `cupons` | 0 | vazia | — | cupom do Summit vive em summit_2026.coupons |
| `cupom_usos` | 0 | vazia | — |  |
| `pedido_tracking` | 0 | vazia | — |  |
| `produto_externo` | 0 | vazia | — |  |

### `ecossistema` — inteligência perene de palestrantes e organizações

6 tabelas · 126 linhas

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `palestrantes_especialistas` | 64 | populada | 2026-09-03 | inteligência perene e curada |
| `organizacoes` | 19 | populada | 2026-09-08 |  |
| `organizacao_verticais` | 19 | populada | — |  |
| `afirmacoes` | 10 | populada | — |  |
| `perfis_publicos` | 9 | populada | 2026-09-08 |  |
| `referencias` | 5 | populada | — |  |

### `agentes` — a casa canônica dos playbooks e dos blocos do Kit

3 tabelas · 72 linhas

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `kit_blocos` | 37 | populada | — | os blocos que o Kit compõe por rota |
| `prompts` | 23 | populada | 2026-09-17 | casa canônica dos playbooks, incluindo router_universal v4 |
| `canal_competencia` | 12 | populada | — | matriz rota × canal que o Capability Gate lê |

### `catalogo` — vocabulário canônico de produto

5 tabelas · 17 linhas · 4 vazia(s)

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `produtos` | 17 | populada | 2026-09-13 | vocabulário canônico de produto |
| `ofertas` | 0 | vazia | — | a oferta real vive em summit_2026.offers e institute.ofertas |
| `oferta_precos` | 0 | vazia | — |  |
| `oferta_inclui` | 0 | vazia | — |  |
| `oferta_requer` | 0 | vazia | — |  |

### `public` — painel admin e estado dos espelhos

5 tabelas · 145 linhas · 1 viva(s)

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `mind_admin_editorial` | 111 | populada | 2026-08-20 |  |
| `mind_admin_audit` | 23 | populada | 2026-09-02 |  |
| `espelho_estado` | 9 | **vivo** | 2026-09-21 | estado dos 5 espelhos do HubSpot |
| `mind_admin_event_details` | 1 | populada | 2026-08-21 |  |
| `mind_admin_users` | 1 | populada | 2026-08-20 |  |

### `platform` — provedores de LLM e observabilidade

6 tabelas · 10 linhas · 2 vazia(s)

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `llm_routes` | 4 | populada | — |  |
| `integracoes` | 3 | populada | 2026-08-23 |  |
| `llm_models` | 2 | populada | — |  |
| `llm_providers` | 1 | populada | — |  |
| `llm_calls` | 0 | vazia | — | zero registro de chamada de LLM — não há observabilidade de custo ou latência |
| `embeddings_config` | 0 | vazia | — |  |

### `dash` — base de conhecimento do Mind Dash

2 tabelas · 2 linhas

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `knowledge_chunks` | 1 | populada | — | 1 chunk, sem embedding |
| `knowledge_documents` | 1 | populada | 2026-09-02 |  |

### `learnworlds` — produtos e acessos da plataforma de curso

2 tabelas · 6 linhas

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `produtos` | 4 | populada | 2026-09-12 |  |
| `acessos` | 2 | populada | 2026-09-12 |  |

### `mind` — políticas e conteúdo institucional

2 tabelas · 6 linhas · 1 vazia(s)

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `policies` | 6 | populada | 2026-08-20 |  |
| `organization_content` | 0 | vazia | — |  |

### `seguranca` — equipe e segredos

2 tabelas · 3 linhas

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `segredos` | 2 | populada | — |  |
| `equipe` | 1 | populada | — |  |

### `eventos` — base de conhecimento genérica de eventos

2 tabelas · 0 linhas · 2 vazia(s)

| tabela | linhas | estado | último registro | nota |
|---|---:|---|---|---|
| `knowledge_chunks` | 0 | vazia | — | schema de conhecimento genérico, nunca ocupado |
| `knowledge_documents` | 0 | vazia | — |  |
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
