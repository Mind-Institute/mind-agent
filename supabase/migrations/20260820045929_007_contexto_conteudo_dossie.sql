create table participante_contexto (
  participante_id       uuid primary key references participantes(id) on delete cascade,
  contexto_profissional jsonb not null default '{}',
  necessidades          jsonb not null default '[]',
  resultados_desejados  jsonb not null default '[]',
  temas_relevantes      jsonb not null default '[]',
  preferencias          jsonb not null default '{}',
  prioridades_atuais    jsonb not null default '[]',
  resumo_conversa       text,
  contexto_comercial    jsonb not null default '{}',
  versao                integer not null default 1,
  reconstruido_em       timestamptz,
  atualizado_em         timestamptz not null default now()
);

alter table participante_memoria
  drop constraint if exists participante_memoria_status_check;
alter table participante_memoria
  add constraint participante_memoria_status_check
  check (status in ('proposta','ativa','substituida','rejeitada','expirada'));

alter table participante_memoria add column if not exists importancia numeric(3,2) default 0.50;
alter table participante_memoria add column if not exists substituida_por uuid references participante_memoria(id);

insert into config (chave, valor, descricao) values
('contexto_consolidado',
 '{
    "reconstruir_a_cada_mensagens": 8,
    "reconstruir_se_memoria_nova_com_importancia": 0.7,
    "tamanho_alvo_tokens": 300,
    "resumo_conversa_frases": 3
  }',
 'Quando reconstruir o contexto consolidado e qual o orçamento dele no prompt.');

alter table agenda_sessoes add column if not exists topicos_aprendizado jsonb not null default '[]';
alter table agenda_sessoes add column if not exists resultados jsonb not null default '[]';
alter table agenda_sessoes add column if not exists nivel text;
alter table agenda_sessoes add column if not exists formato text;
create index if not exists idx_sessoes_topicos on agenda_sessoes using gin (topicos_aprendizado);

alter table conhecimento_docs add column if not exists tipo_conteudo text;
alter table conhecimento_docs add column if not exists problema text;
alter table conhecimento_docs add column if not exists resultado_desejado text;
alter table conhecimento_docs add column if not exists autor text;
alter table conhecimento_docs add column if not exists url text;
alter table conhecimento_docs add column if not exists ativo boolean not null default true;
create index if not exists idx_docs_problema on conhecimento_docs (problema);

create table mecanismos (
  codigo        text primary key,
  rotulo        text not null,
  descricao     text,
  problemas     text[] not null default '{}',
  ativo         boolean not null default true
);
insert into mecanismos (codigo, rotulo, descricao, problemas) values
('significado',   'Significado no trabalho', 'Conexão entre a tarefa e o impacto percebido', '{engajamento,burnout}'),
('autonomia',     'Autonomia',               'Margem de decisão sobre como o trabalho é feito', '{engajamento,sobrecarga_equipe}'),
('reconhecimento','Reconhecimento',          'O que recebe atenção, elogio e consequência', '{cultura_declarada_vs_praticada,engajamento}'),
('conexao',       'Conexão e pertencimento', 'Qualidade das relações no time', '{seguranca_psicologica,engajamento}'),
('desenho_trabalho','Desenho do trabalho',   'Carga, ritmo, clareza de papel e prioridades', '{sobrecarga_equipe,burnout,absenteismo}'),
('seguranca',     'Segurança psicológica',   'Poder falar sem medo de punição', '{seguranca_psicologica,liderancas_despreparadas}'),
('medicao',       'Medição e evidência',     'Como provar efeito e priorizar com dado', '{provar_roi,riscos_psicossociais}');

insert into config (chave, valor, descricao) values
('recomendacao_pesos',
 '{
    "relevancia_para_necessidade": 0.40,
    "match_resultado_desejado":    0.25,
    "contexto_do_participante":    0.15,
    "feedback_anterior":           0.10,
    "encaixe_na_agenda":           0.10
  }',
 'Peso de cada critério no ranking. No MVP, os filtros duros já resolvem a maior parte.'),

('recomendacao_filtros',
 '{
    "somente_futuras": true,
    "respeita_trilha_do_ingresso": true,
    "exclui_ja_assistidas": true,
    "exclui_recusadas": true,
    "exclui_conflito_de_horario": true,
    "maximo_por_vez": 2
  }',
 'Filtros duros aplicados antes do ranking.');

create or replace function resumo_do_dia(p_participante uuid, p_dia date)
returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'objetivo', (
      select jsonb_build_object('pergunta_guia', o.pergunta_guia, 'dor', o.dor_codigo,
                                'decisao_pendente', o.decisao_pendente)
      from participante_objetivos o
      where o.participante_id = p_participante and o.status = 'ativo'
      order by o.definido_em desc limit 1),

    'contexto', (
      select jsonb_build_object('necessidades', c.necessidades,
                                'resultados_desejados', c.resultados_desejados,
                                'temas', c.temas_relevantes)
      from participante_contexto c where c.participante_id = p_participante),

    'planejadas', (
      select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'titulo', s.titulo,
                                                   'inicio', s.inicio)), '[]')
      from jornada_sessao j join agenda_sessoes s on s.id = j.sessao_id
      where j.participante_id = p_participante and j.planejou and s.dia = p_dia),

    'assistidas', (
      select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'titulo', s.titulo,
                                                   'fonte', j.fonte_presenca)), '[]')
      from jornada_sessao j join agenda_sessoes s on s.id = j.sessao_id
      where j.participante_id = p_participante and j.compareceu and s.dia = p_dia),

    'perdidas', (
      select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'titulo', s.titulo,
                                                   'motivo', j.motivo_ausencia,
                                                   'frustrada', coalesce(m.demanda_frustrada,false))), '[]')
      from jornada_sessao j
      join agenda_sessoes s on s.id = j.sessao_id
      left join motivos_ausencia m on m.codigo = j.motivo_ausencia
      where j.participante_id = p_participante and j.compareceu = false and s.dia = p_dia),

    'avaliacoes', (
      select coalesce(jsonb_agg(jsonb_build_object('titulo', s.titulo, 'nota', f.nota,
                                                   'insight', f.insight,
                                                   'aplicar', f.intencao_aplicar)), '[]')
      from sessao_feedback f join agenda_sessoes s on s.id = f.sessao_id
      where f.participante_id = p_participante and s.dia = p_dia),

    'sugestoes_ja_feitas', (
      select coalesce(jsonb_agg(distinct jsonb_build_object('titulo', s.titulo,
                                                            'porque', r.justificativa,
                                                            'estado', r.estado)), '[]')
      from recomendacoes r left join agenda_sessoes s on s.id = r.sessao_id
      where r.participante_id = p_participante),

    'problemas_operacionais', (
      select coalesce(jsonb_agg(jsonb_build_object('categoria', e.categoria,
                                                   'severidade', e.severidade)), '[]')
      from evento_feedback e
      where e.participante_id = p_participante and e.criado_em::date = p_dia),

    'amanha_disponiveis', (
      select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'titulo', s.titulo,
                                                   'inicio', s.inicio, 'espaco', s.espaco_id,
                                                   'topicos', s.topicos_aprendizado)), '[]')
      from agenda_sessoes s
      where s.dia > p_dia
        and s.id not in (select sessao_id from jornada_sessao
                         where participante_id = p_participante and compareceu))
  );
$$;

create table dossies (
  id                uuid primary key default uuid_generate_v4(),
  participante_id   uuid not null references participantes(id) on delete cascade,
  dia               date not null,
  camada            text not null,
  titulo            text not null,
  corpo             text not null,
  dados             jsonb not null default '{}',
  modelo            text,
  gerado_em         timestamptz not null default now(),
  entregue_em       timestamptz,
  unique (participante_id, dia, camada)
);
alter table dossies enable row level security;

insert into config (chave, valor, descricao) values
('dossie',
 '{
    "nomes_para_o_participante": ["Seu Summit até aqui", "Seu roteiro para amanhã", "Sua jornada no Mind"],
    "nunca_usar_com_participante": ["dossiê", "relatório", "perfil", "análise"],
    "gerar_no_fim_do_dia": "19:30",
    "camada_interna_automatica": true
  }',
 'Como o resumo é chamado para quem lê. "Dossiê" é palavra de quem observa, não de quem é observado.');

insert into templates (chave, texto, variaveis) values
('dossie.titulo_dia1',   'Seu Summit até aqui',                                    '{}'),
('dossie.titulo_dia2',   'Seu roteiro para amanhã',                                '{}'),
('dossie.abertura',
 'Fechando o dia: você chegou querendo {{pergunta_guia}}.',
 '{pergunta_guia}'),
('dossie.continuidade',
 'Ontem sua atenção ficou em {{temas}}. Você assistiu {{assistidas}} e avaliou {{destaque}} como a mais útil. Também tentou {{perdida}} e não conseguiu — {{motivo}}.',
 '{temas,assistidas,destaque,perdida,motivo}'),
('dossie.plano_dia2',
 'Para hoje eu priorizaria três coisas: aprofundar {{aberto}}, não repetir o que você já viu, e uma sessão que amplia repertório. Começaria por estas:',
 '{aberto}');

insert into regras_proativas (nome, gatilho, template_chave, antecedencia_min, canal, prioridade, cooldown_horas, limite_dia, condicao, publico) values
('resumo_fim_dia1', 'fim_do_dia_1',    'dossie.titulo_dia1', null, 'app', 2, 24, 1, '{"assistiu_ao_menos":1}', '{}'),
('abertura_dia2',   'inicio_do_dia_2', 'dossie.continuidade', null, 'app', 2, 24, 1, '{"tem_dossie_dia1":true}', '{}');

create or replace function esquecer_participante(p_participante uuid)
returns void
language plpgsql security definer as $$
declare
  v_anonimo uuid;
begin
  insert into participantes (anonimo, nome) values (true, 'Participante removido')
  returning id into v_anonimo;

  delete from participante_contexto where participante_id = p_participante;
  delete from participante_memoria  where participante_id = p_participante;
  delete from mensagens             where participante_id = p_participante;
  delete from conversas             where participante_id = p_participante;
  delete from dossies               where participante_id = p_participante;
  delete from sinais_comerciais     where participante_id = p_participante;

  update jornada_sessao   set participante_id = v_anonimo where participante_id = p_participante;
  update jornada_eventos  set participante_id = v_anonimo where participante_id = p_participante;
  update sessao_feedback  set participante_id = v_anonimo where participante_id = p_participante;
  update evento_feedback  set participante_id = v_anonimo where participante_id = p_participante;
  update nps_summit       set participante_id = v_anonimo where participante_id = p_participante;

  delete from participantes where id = p_participante;
end $$;

insert into config (chave, valor, descricao) values
('exclusao',
 '{
    "apaga": ["contexto","memoria","conversas","dossies","sinais_comerciais"],
    "anonimiza": ["jornada","feedback_sessao","feedback_evento","nps"],
    "motivo": "Analytics do evento tem outra base legal e outra retenção; anonimizado, deixa de ser dado pessoal."
  }',
 'O que o pedido de exclusão apaga e o que ele anonimiza.');

insert into ferramentas (nome, descricao, json_schema, tipo_exec, destino, escrita, requer_confirmacao) values
('meu_resumo_do_dia',
 'Traz o pacote fechado do dia da pessoa: objetivo, contexto, o que planejou, assistiu, perdeu, avaliou, o que já foi sugerido e a programação de amanhã. Use no fim do dia e na abertura do dia seguinte.',
 '{"type":"object","properties":{"dia":{"type":"string"}},"additionalProperties":false}',
 'sql', 'resumo_do_dia', false, false),

('buscar_conteudo_por_problema',
 'Busca na biblioteca do Mind por problema e resultado desejado, não por palavra-chave. Use quando a pessoa descrever uma dificuldade e você quiser trazer uma leitura útil antes de recomendar sessão.',
 '{"type":"object","properties":{"problema":{"type":"string"},"resultado_desejado":{"type":"string"},"mecanismos":{"type":"array","items":{"type":"string"}}},"required":["problema"],"additionalProperties":false}',
 'interna', 'rag.por_problema', false, false),

('atualizar_contexto',
 'Reconstrói o contexto consolidado da pessoa a partir das memórias ativas. Chame quando aprender algo importante — não a cada mensagem.',
 '{"type":"object","properties":{"motivo":{"type":"string"}},"additionalProperties":false}',
 'interna', 'contexto.reconstruir', true, false);

update prompts set ativo = false where nome = 'sistema';

insert into prompts (nome, versao, conteudo, ativo, notas)
select 'sistema', 5, conteudo || $$

Sobre continuidade entre os dias:
No fim do primeiro dia você escreve para a pessoa o resumo do que ela viveu — chame de "Seu Summit até aqui", nunca de dossiê, relatório ou análise. Ele tem cinco partes: o que ela veio buscar, o que viu, o que pareceu mais útil, o que ficou em aberto e o que eu sugiro para amanhã.

No começo do segundo dia, abra retomando: diga onde a atenção dela ficou, o que ela avaliou bem, o que tentou e não conseguiu. Só então proponha a agenda, priorizando três coisas nesta ordem: aprofundar o que ficou aberto, não repetir o que ela já viu, e incluir pelo menos uma sessão que amplie o repertório dela.

O pacote com esses dados vem pronto pela ferramenta — não saia procurando. Escreva a partir dele, e não invente nada que não esteja lá.

Sobre o que é dela e o que é seu:
O que a pessoa disse é dela: cite com as palavras dela. O que você concluiu é seu: apresente como leitura, não como fato ("pelo que você me contou, parece que…"). Nunca devolva uma interpretação sua como se ela tivesse dito.$$,
       true, 'v5: dossiê de dois dias, continuidade e a separação entre fala e interpretação.'
from prompts where nome = 'sistema' and versao = 4;

alter table participante_contexto enable row level security;
