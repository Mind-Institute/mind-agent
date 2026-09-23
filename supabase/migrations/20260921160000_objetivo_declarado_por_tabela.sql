-- ============================================================
-- O objetivo de cada tabela, declarado dentro do banco
-- ============================================================
-- Projeto: mind-agent (ymnmotgglsrxmjmonwjz)
--
-- O QUE ISTO É
-- 89 `comment on table`, um para cada tabela de negócio que ainda não
-- declara para que serve. Depois desta migration, as 160 tabelas do
-- projeto respondem essa pergunta sozinhas, sem depender de documento
-- ao lado.
--
-- POR QUE COMENTÁRIO, E NÃO UM DOCUMENTO
-- Documento se separa do banco. Uma tabela renomeada, movida ou apagada
-- deixa a linha do documento para trás sem quebrar nada, e ninguém
-- percebe. O `comment on table` viaja dentro do objeto: some junto com
-- ele, é lido por `\d+`, pelo painel do Supabase e por qualquer consulta
-- a `pg_description`, e pode ser exigido por teste. É o único lugar onde
-- a documentação não consegue divergir da coisa documentada.
--
-- DE ONDE VEIO O TEXTO
-- Das colunas, das chaves estrangeiras e da migration que criou cada
-- tabela — leitura da estrutura real em 21/09/2026, registrada em
-- MAPA_SUPABASE_20260921.md com a marca `derivado`. As outras 71 tabelas
-- já tinham comentário e NÃO são tocadas aqui: o texto delas é o
-- original de quem as criou.
--
-- É LEITURA, NÃO DECRETO. Onde o texto estiver errado, o conserto é um
-- `comment on table` novo — não há dado em risco.
--
-- O QUE ISTO NÃO TOCA
-- Nada além de metadado de documentação:
--
--   tabelas ............... 0 criadas, 0 alteradas, 0 removidas
--   colunas ............... nenhuma
--   funções/triggers ...... nenhuma
--   policies/permissões ... nenhuma
--   dados ................. nenhuma linha lida, escrita ou apagada
--   comentários ........... 89 definidos, todos hoje nulos
--
-- Nenhum `comment` existente é sobrescrito: a migration cobre apenas as
-- tabelas cujo comentário é nulo hoje, e o bloco de verificação no fim
-- falha se esse número não for exatamente 89.
--
-- QUEM RESPONDE
-- Ninguém em runtime. Nenhuma função, Edge ou agente lê `pg_description`.
-- Os leitores são humanos, o painel do Supabase e o teste de gate que
-- acompanha esta frente.
--
-- DESFAZER
--   No fim do arquivo, bloco DESFAZER: devolve a nulo exatamente as 89.
--
-- SEGURANÇA
-- Comentário de tabela é legível por qualquer papel que já enxergue a
-- tabela. Por isso nenhum texto abaixo cita segredo, credencial, host
-- interno, nome de variável de ambiente ou dado de pessoa.
-- ============================================================

begin;

do $$
declare
  n_antes int;
begin
  select count(*) into n_antes
  from pg_class c
  join pg_namespace ns on ns.oid = c.relnamespace
  left join pg_description d on d.objoid = c.oid and d.objsubid = 0
  where c.relkind = 'r'
    and d.description is null
    and ns.nspname in ('agentes','catalogo','checkout','concierge',
      'credenciamento_summit_2026','crm','dash','ecossistema','eduzz',
      'engagement','eventos','institute','intelligence','learnworlds',
      'mind','pessoas','platform','public','seguranca','summit_2026','treble');

  if n_antes <> 89 then
    raise exception
      'objetivo_declarado_por_tabela: esperava 89 tabelas sem comentario, encontrei %. O banco mudou desde 21/09/2026 — reveja a lista antes de aplicar.', n_antes;
  end if;
end $$;



-- catalogo
comment on table catalogo.oferta_precos is 'O preço de cada produto dentro de uma oferta, com parcelamento e ordem de exibição.';

-- checkout
comment on table checkout.cupom_usos is 'Quem usou qual cupom, em que pedido e com que desconto.';

-- concierge
comment on table concierge.ciclo_estado is 'Em que etapa do ciclo briefing e debrief cada participante está.';
comment on table concierge.config is 'Chave e valor de configuração do agente — é aqui que mora a janela da avaliação do evento.';
comment on table concierge.config_auditoria is 'Trilha de quem mudou qual config, com o antes e o depois.';
comment on table concierge.config_revisao is 'O número de revisão da config, para o app saber quando recarregar.';
comment on table concierge.feature_flags is 'Liga e desliga capacidade do agente sem deploy.';
comment on table concierge.ferramenta_chamadas is 'Ledger de cada chamada de ferramenta, com entrada, saída, latência e chave de idempotência.';
comment on table concierge.ferramentas is 'Catálogo do que o agente pode chamar: schema, destino, timeout, se escreve e se exige confirmação.';
comment on table concierge.integracao_logs is 'Log de chamada a sistema externo por participante: payload, resposta, status e latência.';
comment on table concierge.proativo_fila is 'Fila de mensagem proativa agendada, com canal e chave de dedupe.';
comment on table concierge.prompts is 'Prompts históricos do Concierge, versionados.';
comment on table concierge.regras_proativas is 'As regras que decidiriam quando falar primeiro: gatilho, condição, cooldown e janela silenciosa.';
comment on table concierge.templates is 'Texto pronto por chave, idioma e canal, com as variáveis que aceita.';
comment on table concierge.tutorial_passos is 'Os passos do tutorial do app: título, tela e alvo de cada um.';

-- credenciamento_summit_2026
comment on table credenciamento_summit_2026.yazo_envio_fila is 'Fila do que precisa voltar para a Yazo, uma linha por operação.';
comment on table credenciamento_summit_2026.yazo_espelho is 'Espelho cru do participante na Yazo, com o que ela devolve e quando ele sumiu de lá.';

-- crm
comment on table crm.contato_espelho is 'Espelho do Contact do HubSpot, com as ~170 propriedades do portal. Mirror, nunca fonte autoral.';
comment on table crm.hubspot_commercial_writeback is 'Fila da escrita comercial de volta no HubSpot, com hash de payload, tentativas e retry.';

-- dash
comment on table dash.knowledge_chunks is 'Os pedaços pesquisáveis desses documentos, com embedding e índice lexical.';
comment on table dash.knowledge_documents is 'Documentos de conhecimento do Mind Dash, com hash para detectar mudança.';

-- eduzz
comment on table eduzz.hubspot_stage_config is 'De-para entre evento da Eduzz e estágio do pipeline no HubSpot.';
comment on table eduzz.ingressos is 'O ingresso emitido: participante, lote, status, check-in e quem comprou.';
comment on table eduzz.produto_catalogo is 'A tradução curada do produto Eduzz para a linguagem do Mind: ano, categoria, lote, modalidade.';
comment on table eduzz.produtos is 'O catálogo bruto de produtos da Eduzz, como a API devolve.';
comment on table eduzz.vendas is 'A venda crua da Eduzz: fatura, produto, valores, taxas, cliente e UTMs.';

-- engagement
comment on table engagement.agent_sessions is 'A sessão do app: token, origem da identidade, confiança e expiração.';
comment on table engagement.agente_eventos is 'Evento do agente por conversa: tipo, intenção e dados.';
comment on table engagement.avaliacao_execucoes is 'O resultado de rodar cada caso contra um modelo: passou, custo e latência.';
comment on table engagement.avaliacoes is 'Casos de teste do agente: pergunta, contexto e o que se espera da resposta.';
comment on table engagement.checkout_clicks is 'Um clique no link de checkout, ligado a evento, conversa e pessoa.';
comment on table engagement.contatos is 'Pedido de contato com o time do Mind, com estado e resposta.';
comment on table engagement.conversas is 'Uma linha por conversa, em qualquer canal. Carrega rota, audiência, origem e UTM.';
comment on table engagement.data_requests is 'Pedido de titular de dado pessoal: acesso, correção ou exclusão.';
comment on table engagement.dispositivos is 'O navegador que acessou, por chave e user agent.';
comment on table engagement.evento_feedback is 'Reclamação ou elogio sobre o evento, com categoria, sentimento e severidade.';
comment on table engagement.feedbacks is 'Feedback genérico em chave e valor, sem contrato fixo.';
comment on table engagement.identidade_fusoes is 'Registro de fusão de identidade, com motivo e status.';
comment on table engagement.jornada_eventos is 'Os eventos brutos dessa jornada, por sessão.';
comment on table engagement.jornada_sessao is 'O que a pessoa pretendia e o que de fato fez em cada sessão.';
comment on table engagement.mensagens is 'Cada fala, de pessoa ou de agente, persistida antes de qualquer etapa que possa falhar.';
comment on table engagement.nps is 'Nota e comentário de NPS por participante.';
comment on table engagement.pessoa_perfil is 'Preferência de idioma e escolha de anonimato da pessoa.';
comment on table engagement.recovery_dispatch_queue is 'A fila de envio da retomada: mensagem, horário, tentativas e lock.';
comment on table engagement.sessao_feedback is 'Feedback estruturado de uma sessão: nota, relevância, insight e o que faltou.';
comment on table engagement.session_interests is 'Interesse detectado na sessão, com confiança, evidência e quantas vezes apareceu.';
comment on table engagement.verificacoes_email is 'Código de verificação por e-mail, com hash, tentativas e expiração.';

-- eventos
comment on table eventos.knowledge_chunks is 'Os pedaços pesquisáveis desses documentos.';
comment on table eventos.knowledge_documents is 'Mesma estrutura de conhecimento dos outros produtos, para eventos genéricos.';

-- institute
comment on table institute.faq is 'Pergunta e resposta por escopo, ordenadas.';
comment on table institute.knowledge_chunks is 'Os pedaços pesquisáveis dos documentos do Institute, com embedding e índice lexical.';
comment on table institute.knowledge_documents is 'Os documentos de conhecimento do Institute, com hash para detectar mudança na origem.';
comment on table institute.oferta_bonus is 'Os bônus de cada oferta, com valor de referência e se é gratuito.';
comment on table institute.ofertas is 'A oferta comercial do programa: valor, parcelas, meios de pagamento, checkout e janela.';
comment on table institute.programa_inclusoes is 'O que está incluído no programa, como texto ordenado.';
comment on table institute.programas is 'Um registro por programa: tipo, carga horária, duração, modalidade e janela.';

-- intelligence
comment on table intelligence.acessos_dado_pessoal is 'Trilha de quem acessou dado pessoal: quem, qual função, sobre quem, por qual agente.';
comment on table intelligence.analise_conversa is 'A análise assíncrona de cada conversa: o que o modelo concluiu, com qual prompt e até qual mensagem.';
comment on table intelligence.config is 'Chave e valor da Intelligence, incluindo o token que os crons usam.';
comment on table intelligence.dossies is 'Dossiê gerado por dia e camada, com corpo e quando foi entregue.';
comment on table intelligence.intencoes is 'Padrões que mapeiam uma fala para rota, ferramenta e esforço de raciocínio.';
comment on table intelligence.memoria_bloqueios is 'A taxonomia do que nunca pode ser lembrado, com exemplo bloqueado e exemplo liberado.';
comment on table intelligence.memoria_regras is 'Por tipo de memória: se pode inferir, confiança mínima e prazo de validade.';
comment on table intelligence.participante_contexto is 'O contexto reconstruído da pessoa: necessidades, resultados desejados, temas e prioridades.';
comment on table intelligence.participante_memoria is 'A memória da pessoa, fato a fato, com confiança, origem, evidência e validade.';
comment on table intelligence.participante_objetivos is 'A pergunta-guia da pessoa no evento, com dor, área e decisão pendente.';
comment on table intelligence.perguntas_feitas is 'Quais perguntas já foram feitas a esta pessoa, e se ela respondeu ou recusou.';
comment on table intelligence.recomendacoes is 'O que foi recomendado, por quê, com que origem e em que estado.';
comment on table intelligence.recovery_inbox is 'A caixa de retomada: estado, calor, objeção, janela do WhatsApp e rascunho de mensagem.';
comment on table intelligence.sinais_comerciais is 'Sinal de interesse comercial detectado na conversa, com evidência e consentimento.';

-- mind
comment on table mind.organization_content is 'Conteúdo institucional por categoria e slug, com janela de validade.';
comment on table mind.policies is 'Termos legais versionados, por chave e versão.';

-- platform
comment on table platform.embeddings_config is 'Qual provedor, modelo e dimensão usar para gerar embedding.';
comment on table platform.llm_calls is 'Uma linha por chamada de LLM: tokens, cache, custo, latência e motivo de parada.';
comment on table platform.llm_models is 'Cada modelo: papel, janela de contexto, custo por milhão de tokens e capacidades.';
comment on table platform.llm_providers is 'Os provedores de modelo disponíveis, com referência ao segredo e URL base.';
comment on table platform.llm_routes is 'Por rota: qual papel de modelo usar, fallback, esforço, streaming e cache de prompt.';

-- summit_2026
comment on table summit_2026.event_rules is 'Regras do evento por chave, com onde se aplicam e prioridade.';
comment on table summit_2026.events is 'O evento: slug, dias, local, cidade e fuso.';
comment on table summit_2026.exhibitors is 'Expositores, com local, categoria e contato.';
comment on table summit_2026.knowledge_chunks is 'Os pedaços pesquisáveis dessa base, com embedding e índice lexical.';
comment on table summit_2026.knowledge_documents is 'A base de conhecimento do Summit, com hash para detectar mudança.';
comment on table summit_2026.locations is 'Cada espaço dentro do local, com hierarquia, apelidos e como chegar.';
comment on table summit_2026.offers is 'A oferta do Summit: código, valor, condições, checkout, elegibilidade e janela.';
comment on table summit_2026.registrations is 'Inscrição de uma pessoa no evento, com categoria de ingresso.';
comment on table summit_2026.route_edges is 'Como ir de um espaço a outro: instruções, distância, minutos e se é acessível.';
comment on table summit_2026.session_speakers is 'Quem fala em cada sessão do Summit e com que papel — o vínculo canônico entre sessão e palestrante.';
comment on table summit_2026.sessions is 'A grade: título, dia, horário, espaço, trilha, vagas e quais ingressos entram.';
comment on table summit_2026.venues is 'O local físico, com endereço, transporte, acessibilidade e mapa.';

-- prova: nenhuma tabela de negócio pode sair daqui sem objetivo declarado
do $$
declare
  n_sem int;
  exemplo text;
begin
  select count(*), min(ns.nspname || '.' || c.relname) into n_sem, exemplo
  from pg_class c
  join pg_namespace ns on ns.oid = c.relnamespace
  left join pg_description d on d.objoid = c.oid and d.objsubid = 0
  where c.relkind = 'r'
    and d.description is null
    and ns.nspname in ('agentes','catalogo','checkout','concierge',
      'credenciamento_summit_2026','crm','dash','ecossistema','eduzz',
      'engagement','eventos','institute','intelligence','learnworlds',
      'mind','pessoas','platform','public','seguranca','summit_2026','treble');

  if n_sem > 0 then
    raise exception
      'objetivo_declarado_por_tabela: % tabela(s) continuam sem objetivo, a comecar por %.', n_sem, exemplo;
  end if;

  raise notice 'objetivo_declarado_por_tabela: 160 de 160 tabelas com objetivo declarado.';
end $$;

commit;

-- ============================================================
-- DESFAZER
-- ============================================================
-- Devolve a nulo exatamente as 89 que esta migration definiu, sem tocar
-- nas 71 que já tinham comentário antes dela.
--
-- do $$
-- declare r record;
-- begin
--   for r in
--     select unnest(string_to_array($lista$catalogo.oferta_precos,checkout.cupom_usos$lista$, ',')) as alvo
--   loop
--     execute format('comment on table %s is null', r.alvo);
--   end loop;
-- end $$;
--
-- A lista completa das 89 está em MAPA_SUPABASE_20260921.md, coluna
-- `fonte` = derivado. Gerar com:
--
--   select string_agg(format('comment on table %I.%I is null;', table_schema, table_name), E'\n')
--   from ... (as 89 marcadas como derivado)
-- ============================================================
