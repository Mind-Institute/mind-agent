insert into taxonomia (tipo, codigo, rotulo, sinonimos) values
('area','rh','RH e Pessoas','{"recursos humanos","gente e gestão","people"}'),
('area','lideranca','Liderança','{"gestão","gestores","chefia"}'),
('area','saude_ocupacional','Saúde ocupacional','{"SESMT","medicina do trabalho"}'),
('area','c_level','Alta liderança','{"C-level","diretoria","board"}'),
('area','dei','Diversidade e inclusão','{"DEI","diversidade"}'),
('area','financeiro','Financeiro','{"controladoria","CFO"}'),

('dor','cultura_declarada_vs_praticada','Distância entre cultura declarada e praticada','{"discurso e prática"}'),
('dor','liderancas_despreparadas','Lideranças despreparadas','{"gestores não assumem","liderança fraca"}'),
('dor','burnout','Esgotamento e afastamentos na organização','{"burnout na equipe","afastamento","INSS","estresse crônico"}'),
('dor','absenteismo','Absenteísmo e presenteísmo','{"faltas","presenteísmo","queda de produtividade"}'),
('dor','sobrecarga_equipe','Equipe sobrecarregada','{"time exausto","ritmo insustentável"}'),
('dor','engajamento','Engajamento e retenção','{"turnover","rotatividade"}'),
('dor','provar_roi','Provar o retorno do bem-estar','{"ROI","board não compra","orçamento"}'),
('dor','riscos_psicossociais','Riscos psicossociais e NR-1','{"NR1","PGR","conformidade"}'),
('dor','seguranca_psicologica','Falta de segurança psicológica','{"medo de falar","silêncio"}'),
('dor','sobrecarga','Sobrecarga e ritmo','{"excesso de trabalho","carga"}'),

('tema','cultura','Cultura organizacional','{}'),
('tema','saude_mental','Saúde mental','{}'),
('tema','performance','Performance e alta performance','{}'),
('tema','dados_bem_estar','Dados e medição de bem-estar','{}'),
('tema','regulacao','Regulação e conformidade','{}'),
('tema','lideranca_humana','Liderança humanizada','{}'),

('produto','institute','Mind Institute — formações','{"formação","curso","institute"}'),
('produto','diagnostico','Diagnóstico organizacional','{"pesquisa","medição","assessment"}'),
('produto','consultoria','Consultoria e implementação','{"projeto","implantação"}'),
('produto','palestra','Palestra ou workshop in company','{"palestra na empresa"}'),

('categoria_operacional','alimentacao','Alimentação','{"comida","almoço","café"}'),
('categoria_operacional','acesso','Acesso e credenciamento','{"fila","entrada","credencial"}'),
('categoria_operacional','app','Aplicativo','{"app","sistema"}'),
('categoria_operacional','sinalizacao','Sinalização','{"placas","achar sala","perdido"}'),
('categoria_operacional','equipe','Equipe e atendimento','{"staff","recepção"}'),
('categoria_operacional','espaco','Espaço e conforto','{"cadeira","som","temperatura","ar"}'),
('categoria_operacional','programacao','Programação e horários','{"atraso","mudança"}'),
('categoria_operacional','acessibilidade','Acessibilidade','{"libras","rampa","tradução"}');

insert into config (chave, valor, descricao) values
('conversa',
 '{"perguntas_por_conversa":2,"pergunta_exige_entrega":true,"nao_repetir_pergunta_dias":9999,"uma_pergunta_por_vez":true}',
 'A IA só pergunta quando entrega algo em troca, no máximo duas vezes por conversa, uma de cada vez. Pergunta ignorada não volta.'),

('ciclo',
 '{"briefing_minutos_antes":20,"debrief_minutos_depois":10,"checkin_objetivo_horas":4,"recomendacoes_por_vez":2}',
 'Ritmo do ciclo: quando fazer briefing, debrief e revisar o objetivo.'),

('sinal_comercial',
 '{"exige_evidencia_literal":true,"contato_exige_consentimento":true,"forca_alta_notifica":true}',
 'Nenhum sinal comercial é registrado sem a frase que o sustenta. Pedido de contato só com autorização explícita na conversa.');

update prompts set ativo = false where nome = 'sistema';

insert into prompts (nome, versao, conteudo, ativo, notas) values
('sistema', 2,
$$Você é o Mind Agent, o concierge de aprendizado do Mind Summit.

Seu trabalho não é responder perguntas: é fazer a pessoa sair daqui com algo mais concreto do que uma coleção de boas ideias. Você faz quatro coisas ao mesmo tempo — entender quem é a pessoa, ensinar ela a extrair mais do evento, montar e adaptar a agenda dela, e recolher o que ela achou.

O ciclo que você segue:
entender a dor real → ajudar a pensar melhor sobre ela → conectar com a palestra, pessoa ou experiência certa → encaixar na agenda → acompanhar → perguntar o que ficou → recomendar de novo, melhor.

Como você aprende sobre a pessoa:
- Nunca faça interrogatório. Toda pergunta vem acompanhada de algo que você já entregou: uma leitura, uma sugestão, um recorte útil.
- Uma pergunta por vez, e só quando a resposta muda o que você vai recomendar.
- Quando ela responder vago, ofereça alternativas concretas em vez de repetir a pergunta.
- Se ela ignorar uma pergunta, não insista. Siga entregando.
- Registre o que aprender com propor_memoria, sempre usando os códigos do vocabulário — não invente rótulo novo.

Como você ensina:
- Antes de recomendar, dê uma leitura própria do problema. Uma ideia que ajuda a pessoa a pensar vale mais que três títulos de palestra.
- Antes de uma sessão que ela vai assistir, diga o que vale observar naquele conteúdo para o problema dela.
- Depois, pergunte o que conversou com o problema — não "gostou?".

Como você recomenda:
- No máximo duas opções por vez, e sempre com o porquê explícito, ligado ao que ela te contou.
- Se ela ainda não te disse nada, recomende pelo que a trilha do ingresso libera e pelo horário — e aproveite para entender.

Fatos do evento (horário, sala, vaga, reserva, benefício) vêm sempre de ferramenta. Se a ferramenta falhar, diga que não consegue confirmar agora. Nunca estime.

Sinal comercial: se a pessoa demonstrar interesse em levar algo para a empresa dela, registre com a frase dela como evidência. Só ofereça contato do time do Mind se ela pedir ou aceitar claramente — e nunca transforme conversa técnica em abordagem de venda.

Tom: português do Brasil, direto e caloroso. Respostas curtas por padrão; detalhe quando pedirem. Não invente número, horário ou nome. Quando não souber, diga e aponte quem sabe.$$,
 true, 'Versão do concierge: ciclo, reciprocidade e vocabulário controlado.');

insert into ferramentas (nome, descricao, json_schema, tipo_exec, destino, escrita, requer_confirmacao) values
('definir_objetivo',
 'Registra a pergunta profissional que a pessoa quer responder até o fim do evento. Use quando ela contar um problema concreto.',
 '{"type":"object","properties":{"pergunta_guia":{"type":"string"},"dor_codigo":{"type":"string"},"area_codigo":{"type":"string"},"decisao_pendente":{"type":"string"},"prazo":{"type":"string"}},"required":["pergunta_guia"],"additionalProperties":false}',
 'interna', 'ciclo.objetivo', true, false),

('recomendar_sessoes',
 'Sugere até duas sessões para o objetivo do participante, considerando horário, trilha do ingresso e o que ele já reservou. Devolve as opções e a justificativa de cada uma.',
 '{"type":"object","properties":{"objetivo_id":{"type":"string"},"a_partir_de":{"type":"string"},"limite":{"type":"integer"}},"additionalProperties":false}',
 'interna', 'ciclo.recomendar', false, false),

('registrar_recomendacao',
 'Grava o que foi recomendado e por quê, para acompanhar se virou agenda e se a pessoa foi.',
 '{"type":"object","properties":{"sessao_id":{"type":"string"},"justificativa":{"type":"string"},"estado":{"type":"string"}},"required":["justificativa"],"additionalProperties":false}',
 'interna', 'ciclo.registrar_recomendacao', true, false),

('registrar_feedback_sessao',
 'Guarda o que a pessoa achou de uma sessão: nota, o que ficou, o que pretende aplicar e o que faltou. Pode ser preenchido aos poucos, em turnos diferentes.',
 '{"type":"object","properties":{"sessao_id":{"type":"string"},"nota":{"type":"integer"},"relevancia":{"type":"string"},"insight":{"type":"string"},"intencao_aplicar":{"type":"string"},"o_que_faltou":{"type":"string"},"comentario":{"type":"string"}},"required":["sessao_id"],"additionalProperties":false}',
 'interna', 'ciclo.feedback_sessao', true, false),

('registrar_feedback_evento',
 'Guarda percepção sobre a operação do evento: alimentação, acesso, sinalização, espaço, equipe. Use quando a pessoa reclamar ou elogiar algo da experiência.',
 '{"type":"object","properties":{"categoria":{"type":"string"},"sentimento":{"type":"string"},"severidade":{"type":"integer"},"comentario":{"type":"string"},"local":{"type":"string"}},"required":["categoria","sentimento"],"additionalProperties":false}',
 'interna', 'ciclo.feedback_evento', true, false),

('registrar_sinal_comercial',
 'Registra interesse em levar algo do Mind para a empresa. Exige a frase literal da pessoa como evidência. Só marque contato solicitado se ela pedir ou aceitar.',
 '{"type":"object","properties":{"area_codigo":{"type":"string"},"produto_codigo":{"type":"string"},"forca":{"type":"string"},"evidencia_texto":{"type":"string"},"contato_solicitado":{"type":"boolean"},"canal_preferido":{"type":"string"}},"required":["forca","evidencia_texto"],"additionalProperties":false}',
 'interna', 'ciclo.sinal_comercial', true, false);

insert into intencoes (nome, padroes, rota, ferramenta, effort, exige_ferramenta) values
('desabafo_profissional', '{"não sei por onde começar","estou tentando","meu problema é","minha empresa"}', 'llm', null, 'high', false),
('feedback_espontaneo',   '{"achei ruim","achei ótimo","fila","demorou","não achei","difícil de"}',        'llm', null, 'medium', false),
('interesse_comercial',   '{"vocês fazem","tem formação","levar para minha empresa","quero falar com"}',   'llm', null, 'high', false);

insert into templates (chave, texto, variaveis) values
('ciclo.abertura',
 'Quero te ajudar a sair do Summit com algo mais concreto do que boas ideias. Qual é uma questão profissional que você gostaria de entender melhor até o fim do dia?',
 '{}'),
('ciclo.contrato',
 'Ótimo. Vou usar isso como filtro: quando eu sugerir palestra, pessoa ou conteúdo, é sempre pensando em {{pergunta_guia}}.',
 '{pergunta_guia}'),
('ciclo.briefing',
 'Daqui a pouco começa "{{titulo}}". Você me disse que sua dificuldade é {{dor}}. Nessa sessão eu prestaria atenção em duas coisas: {{focos}}.',
 '{titulo,dor,focos}'),
('ciclo.debrief',
 'E aí, o que de "{{titulo}}" conversou com o que você está tentando resolver?',
 '{titulo}'),
('ciclo.nota',
 'De 0 a 10, quanto essa sessão foi útil para você?',
 '{}'),
('ciclo.aplicar',
 'Tem alguma coisa dali que você pretende aplicar quando voltar?',
 '{}'),
('ciclo.recomendacao',
 'Duas opções que fazem sentido para {{pergunta_guia}}: {{opcoes}}. Quer que eu reserve alguma?',
 '{pergunta_guia,opcoes}'),
('ciclo.checkin_objetivo',
 'Você chegou aqui querendo entender {{pergunta_guia}}. Já apareceu alguma resposta, ou a pergunta mudou?',
 '{pergunta_guia}'),
('ciclo.experiencia_evento',
 'Fora o conteúdo: como está sendo a sua experiência com a organização até agora?',
 '{}'),
('comercial.oferecer_contato',
 'Isso é exatamente o tipo de trabalho que o Mind faz dentro das empresas. Quer que alguém do time entre em contato para conversar sobre {{area}}?',
 '{area}'),
('comercial.confirmar',
 'Combinado. Vou registrar seu interesse em {{area}} e alguém do Mind fala com você. Prefere por e-mail ou WhatsApp?',
 '{area}');

insert into regras_proativas (nome, gatilho, template_chave, antecedencia_min, canal, prioridade, cooldown_horas, limite_dia, condicao, publico) values
('abertura_objetivo', 'primeiro_acesso',   'ciclo.abertura',            null, 'app', 2, 24, 1, '{}',                               '{}'),
('briefing_sessao',   'reserva_proxima',   'ciclo.briefing',              20, 'app', 3,  1, 3, '{"tem_objetivo":true}',            '{}'),
('debrief_sessao',    'sessao_terminou',   'ciclo.debrief',              -10, 'app', 4,  2, 3, '{"compareceu":true}',              '{}'),
('checkin_objetivo',  'meio_do_dia',       'ciclo.checkin_objetivo',    null, 'app', 6,  6, 1, '{"tem_objetivo":true}',            '{}'),
('experiencia_evento','pos_almoco',        'ciclo.experiencia_evento',  null, 'app', 7, 24, 1, '{}',                               '{}');

insert into feature_flags (chave, ativo, publico, descricao) values
('ciclo_objetivo',     false, '{}', 'Pedir e usar a pergunta-guia do participante'),
('ciclo_briefing',     false, '{}', 'Briefing antes da sessão'),
('ciclo_debrief',      false, '{}', 'Debrief e nota depois da sessão'),
('sinal_comercial',    false, '{}', 'Registrar interesse comercial a partir da conversa'),
('oferecer_contato',   false, '{}', 'Oferecer contato do time do Mind (exige consentimento)');
