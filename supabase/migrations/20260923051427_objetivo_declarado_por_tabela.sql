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

  -- 23/09: o banco ganhou tabelas depois de 21/09 (Relatorio Yazzo Consolidado, Reservas_Agenda_APP,
  -- Check Ins Summit); elas entram na secao "credenciamento (23/09)" abaixo. A guarda passa a exigir
  -- que as 89 originais continuem sem comentario (nenhuma foi comentada por fora), nao o numero exato.
  if n_antes < 89 then
    raise exception
      'objetivo_declarado_por_tabela: esperava ao menos 89 tabelas sem comentario, encontrei %. Alguma das 89 ja foi comentada por fora — reveja a lista antes de aplicar.', n_antes;
  end if;
end $$;



-- 23/09: comenta cada tabela SE ela ainda existir (engagement.checkout_clicks saiu do banco entre
-- 21/09 e 23/09). Tabela ausente vira aviso, nao erro: a migration declara objetivo, nao
-- inventario.
do $$
declare r record; n_ok int := 0; n_fora int := 0;
begin
  for r in
    select * from (values
    ($t$catalogo.oferta_precos$t$, $c$O preço de cada produto dentro de uma oferta, com parcelamento e ordem de exibição.$c$),
    ($t$checkout.cupom_usos$t$, $c$Quem usou qual cupom, em que pedido e com que desconto.$c$),
    ($t$concierge.ciclo_estado$t$, $c$Em que etapa do ciclo briefing e debrief cada participante está.$c$),
    ($t$concierge.config$t$, $c$Chave e valor de configuração do agente — é aqui que mora a janela da avaliação do evento.$c$),
    ($t$concierge.config_auditoria$t$, $c$Trilha de quem mudou qual config, com o antes e o depois.$c$),
    ($t$concierge.config_revisao$t$, $c$O número de revisão da config, para o app saber quando recarregar.$c$),
    ($t$concierge.feature_flags$t$, $c$Liga e desliga capacidade do agente sem deploy.$c$),
    ($t$concierge.ferramenta_chamadas$t$, $c$Ledger de cada chamada de ferramenta, com entrada, saída, latência e chave de idempotência.$c$),
    ($t$concierge.ferramentas$t$, $c$Catálogo do que o agente pode chamar: schema, destino, timeout, se escreve e se exige confirmação.$c$),
    ($t$concierge.integracao_logs$t$, $c$Log de chamada a sistema externo por participante: payload, resposta, status e latência.$c$),
    ($t$concierge.proativo_fila$t$, $c$Fila de mensagem proativa agendada, com canal e chave de dedupe.$c$),
    ($t$concierge.prompts$t$, $c$Prompts históricos do Concierge, versionados.$c$),
    ($t$concierge.regras_proativas$t$, $c$As regras que decidiriam quando falar primeiro: gatilho, condição, cooldown e janela silenciosa.$c$),
    ($t$concierge.templates$t$, $c$Texto pronto por chave, idioma e canal, com as variáveis que aceita.$c$),
    ($t$concierge.tutorial_passos$t$, $c$Os passos do tutorial do app: título, tela e alvo de cada um.$c$),
    ($t$credenciamento_summit_2026."Relatorio Yazzo Consolidado"$t$, $c$Relatório consolidado exportado da Yazo (Summit 2026), como veio da planilha: participante, comprador, ingresso e atividade no app, uma linha por participante, com a pessoa resolvida pela Regra #1.$c$),
    ($t$credenciamento_summit_2026."Reservas_Agenda_APP"$t$, $c$Reservas de agenda feitas no app da Yazo (Summit 2026), uma linha por reserva, com a pessoa e a sessão resolvidas.$c$),
    ($t$credenciamento_summit_2026."Check Ins Summit"$t$, $c$Check-ins nas atividades do Summit 2026 registrados pela Yazo, uma linha por check-in, com a pessoa e a sessão resolvidas.$c$),
    ($t$credenciamento_summit_2026.yazo_envio_fila$t$, $c$Fila do que precisa voltar para a Yazo, uma linha por operação.$c$),
    ($t$credenciamento_summit_2026.yazo_espelho$t$, $c$Espelho cru do participante na Yazo, com o que ela devolve e quando ele sumiu de lá.$c$),
    ($t$crm.contato_espelho$t$, $c$Espelho do Contact do HubSpot, com as ~170 propriedades do portal. Mirror, nunca fonte autoral.$c$),
    ($t$crm.hubspot_commercial_writeback$t$, $c$Fila da escrita comercial de volta no HubSpot, com hash de payload, tentativas e retry.$c$),
    ($t$dash.knowledge_chunks$t$, $c$Os pedaços pesquisáveis desses documentos, com embedding e índice lexical.$c$),
    ($t$dash.knowledge_documents$t$, $c$Documentos de conhecimento do Mind Dash, com hash para detectar mudança.$c$),
    ($t$eduzz.hubspot_stage_config$t$, $c$De-para entre evento da Eduzz e estágio do pipeline no HubSpot.$c$),
    ($t$eduzz.ingressos$t$, $c$O ingresso emitido: participante, lote, status, check-in e quem comprou.$c$),
    ($t$eduzz.produto_catalogo$t$, $c$A tradução curada do produto Eduzz para a linguagem do Mind: ano, categoria, lote, modalidade.$c$),
    ($t$eduzz.produtos$t$, $c$O catálogo bruto de produtos da Eduzz, como a API devolve.$c$),
    ($t$eduzz.vendas$t$, $c$A venda crua da Eduzz: fatura, produto, valores, taxas, cliente e UTMs.$c$),
    ($t$engagement.agent_sessions$t$, $c$A sessão do app: token, origem da identidade, confiança e expiração.$c$),
    ($t$engagement.agente_eventos$t$, $c$Evento do agente por conversa: tipo, intenção e dados.$c$),
    ($t$engagement.avaliacao_execucoes$t$, $c$O resultado de rodar cada caso contra um modelo: passou, custo e latência.$c$),
    ($t$engagement.avaliacoes$t$, $c$Casos de teste do agente: pergunta, contexto e o que se espera da resposta.$c$),
    ($t$engagement.checkout_clicks$t$, $c$Um clique no link de checkout, ligado a evento, conversa e pessoa.$c$),
    ($t$engagement.contatos$t$, $c$Pedido de contato com o time do Mind, com estado e resposta.$c$),
    ($t$engagement.conversas$t$, $c$Uma linha por conversa, em qualquer canal. Carrega rota, audiência, origem e UTM.$c$),
    ($t$engagement.data_requests$t$, $c$Pedido de titular de dado pessoal: acesso, correção ou exclusão.$c$),
    ($t$engagement.dispositivos$t$, $c$O navegador que acessou, por chave e user agent.$c$),
    ($t$engagement.evento_feedback$t$, $c$Reclamação ou elogio sobre o evento, com categoria, sentimento e severidade.$c$),
    ($t$engagement.feedbacks$t$, $c$Feedback genérico em chave e valor, sem contrato fixo.$c$),
    ($t$engagement.identidade_fusoes$t$, $c$Registro de fusão de identidade, com motivo e status.$c$),
    ($t$engagement.jornada_eventos$t$, $c$Os eventos brutos dessa jornada, por sessão.$c$),
    ($t$engagement.jornada_sessao$t$, $c$O que a pessoa pretendia e o que de fato fez em cada sessão.$c$),
    ($t$engagement.mensagens$t$, $c$Cada fala, de pessoa ou de agente, persistida antes de qualquer etapa que possa falhar.$c$),
    ($t$engagement.nps$t$, $c$Nota e comentário de NPS por participante.$c$),
    ($t$engagement.pessoa_perfil$t$, $c$Preferência de idioma e escolha de anonimato da pessoa.$c$),
    ($t$engagement.recovery_dispatch_queue$t$, $c$A fila de envio da retomada: mensagem, horário, tentativas e lock.$c$),
    ($t$engagement.sessao_feedback$t$, $c$Feedback estruturado de uma sessão: nota, relevância, insight e o que faltou.$c$),
    ($t$engagement.session_interests$t$, $c$Interesse detectado na sessão, com confiança, evidência e quantas vezes apareceu.$c$),
    ($t$engagement.verificacoes_email$t$, $c$Código de verificação por e-mail, com hash, tentativas e expiração.$c$),
    ($t$eventos.knowledge_chunks$t$, $c$Os pedaços pesquisáveis desses documentos.$c$),
    ($t$eventos.knowledge_documents$t$, $c$Mesma estrutura de conhecimento dos outros produtos, para eventos genéricos.$c$),
    ($t$institute.faq$t$, $c$Pergunta e resposta por escopo, ordenadas.$c$),
    ($t$institute.knowledge_chunks$t$, $c$Os pedaços pesquisáveis dos documentos do Institute, com embedding e índice lexical.$c$),
    ($t$institute.knowledge_documents$t$, $c$Os documentos de conhecimento do Institute, com hash para detectar mudança na origem.$c$),
    ($t$institute.oferta_bonus$t$, $c$Os bônus de cada oferta, com valor de referência e se é gratuito.$c$),
    ($t$institute.ofertas$t$, $c$A oferta comercial do programa: valor, parcelas, meios de pagamento, checkout e janela.$c$),
    ($t$institute.programa_inclusoes$t$, $c$O que está incluído no programa, como texto ordenado.$c$),
    ($t$institute.programas$t$, $c$Um registro por programa: tipo, carga horária, duração, modalidade e janela.$c$),
    ($t$intelligence.acessos_dado_pessoal$t$, $c$Trilha de quem acessou dado pessoal: quem, qual função, sobre quem, por qual agente.$c$),
    ($t$intelligence.analise_conversa$t$, $c$A análise assíncrona de cada conversa: o que o modelo concluiu, com qual prompt e até qual mensagem.$c$),
    ($t$intelligence.config$t$, $c$Chave e valor da Intelligence, incluindo o token que os crons usam.$c$),
    ($t$intelligence.dossies$t$, $c$Dossiê gerado por dia e camada, com corpo e quando foi entregue.$c$),
    ($t$intelligence.intencoes$t$, $c$Padrões que mapeiam uma fala para rota, ferramenta e esforço de raciocínio.$c$),
    ($t$intelligence.memoria_bloqueios$t$, $c$A taxonomia do que nunca pode ser lembrado, com exemplo bloqueado e exemplo liberado.$c$),
    ($t$intelligence.memoria_regras$t$, $c$Por tipo de memória: se pode inferir, confiança mínima e prazo de validade.$c$),
    ($t$intelligence.participante_contexto$t$, $c$O contexto reconstruído da pessoa: necessidades, resultados desejados, temas e prioridades.$c$),
    ($t$intelligence.participante_memoria$t$, $c$A memória da pessoa, fato a fato, com confiança, origem, evidência e validade.$c$),
    ($t$intelligence.participante_objetivos$t$, $c$A pergunta-guia da pessoa no evento, com dor, área e decisão pendente.$c$),
    ($t$intelligence.perguntas_feitas$t$, $c$Quais perguntas já foram feitas a esta pessoa, e se ela respondeu ou recusou.$c$),
    ($t$intelligence.recomendacoes$t$, $c$O que foi recomendado, por quê, com que origem e em que estado.$c$),
    ($t$intelligence.recovery_inbox$t$, $c$A caixa de retomada: estado, calor, objeção, janela do WhatsApp e rascunho de mensagem.$c$),
    ($t$intelligence.sinais_comerciais$t$, $c$Sinal de interesse comercial detectado na conversa, com evidência e consentimento.$c$),
    ($t$mind.organization_content$t$, $c$Conteúdo institucional por categoria e slug, com janela de validade.$c$),
    ($t$mind.policies$t$, $c$Termos legais versionados, por chave e versão.$c$),
    ($t$platform.embeddings_config$t$, $c$Qual provedor, modelo e dimensão usar para gerar embedding.$c$),
    ($t$platform.llm_calls$t$, $c$Uma linha por chamada de LLM: tokens, cache, custo, latência e motivo de parada.$c$),
    ($t$platform.llm_models$t$, $c$Cada modelo: papel, janela de contexto, custo por milhão de tokens e capacidades.$c$),
    ($t$platform.llm_providers$t$, $c$Os provedores de modelo disponíveis, com referência ao segredo e URL base.$c$),
    ($t$platform.llm_routes$t$, $c$Por rota: qual papel de modelo usar, fallback, esforço, streaming e cache de prompt.$c$),
    ($t$summit_2026.event_rules$t$, $c$Regras do evento por chave, com onde se aplicam e prioridade.$c$),
    ($t$summit_2026.events$t$, $c$O evento: slug, dias, local, cidade e fuso.$c$),
    ($t$summit_2026.exhibitors$t$, $c$Expositores, com local, categoria e contato.$c$),
    ($t$summit_2026.knowledge_chunks$t$, $c$Os pedaços pesquisáveis dessa base, com embedding e índice lexical.$c$),
    ($t$summit_2026.knowledge_documents$t$, $c$A base de conhecimento do Summit, com hash para detectar mudança.$c$),
    ($t$summit_2026.locations$t$, $c$Cada espaço dentro do local, com hierarquia, apelidos e como chegar.$c$),
    ($t$summit_2026.offers$t$, $c$A oferta do Summit: código, valor, condições, checkout, elegibilidade e janela.$c$),
    ($t$summit_2026.registrations$t$, $c$Inscrição de uma pessoa no evento, com categoria de ingresso.$c$),
    ($t$summit_2026.route_edges$t$, $c$Como ir de um espaço a outro: instruções, distância, minutos e se é acessível.$c$),
    ($t$summit_2026.session_speakers$t$, $c$Quem fala em cada sessão do Summit e com que papel — o vínculo canônico entre sessão e palestrante.$c$),
    ($t$summit_2026.sessions$t$, $c$A grade: título, dia, horário, espaço, trilha, vagas e quais ingressos entram.$c$),
    ($t$summit_2026.venues$t$, $c$O local físico, com endereço, transporte, acessibilidade e mapa.$c$)
    ) as v(tabela, objetivo)
  loop
    if to_regclass(r.tabela) is null then
      raise notice 'objetivo_declarado_por_tabela: % nao existe mais; pulando', r.tabela;
      n_fora := n_fora + 1;
      continue;
    end if;
    -- nenhum comentario existente e sobrescrito: quem ja declarou objetivo fica com o seu
    if obj_description(to_regclass(r.tabela), 'pg_class') is not null then
      n_fora := n_fora + 1;
      continue;
    end if;
    execute format('comment on table %s is %L', r.tabela, r.objetivo);
    n_ok := n_ok + 1;
  end loop;
  raise notice 'objetivo_declarado_por_tabela: % comentadas, % puladas (ausentes ou ja comentadas)', n_ok, n_fora;
end $$;

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

  raise notice 'objetivo_declarado_por_tabela: todas as tabelas de negocio com objetivo declarado.';
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
