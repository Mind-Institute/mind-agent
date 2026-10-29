-- Pesquisa 2026 num lugar só (Adriana, 24/09/2026).
-- As respostas de 2026 estavam espalhadas em quatro tabelas do app: engagement.avaliacao_do_evento (29),
-- avaliacao_do_evento_atividade (478 notas por palestra), avaliacao_do_dia (39) e avaliacao_do_dia_atividade (320).
-- Todas passam para engagement.pesquisa_summit_2026, uma linha por resposta:
--   origem 'app_evento' ou 'app_dia' (e 'externa' para a pesquisa nova, da outra ferramenta);
--   as perguntas do app ganham coluna; as notas por palestra vão em notas_atividades (sessão, título, dia, nota);
--   respostas guarda a linha original inteira.
-- mind_id: o app já gravou a pessoa pela porta de identidade (todas canônicas, conferido). A cópia passa com a chave
-- de manutenção mind.d5_pular_trigger, para o gatilho não refazer a resolução sem e-mail e apagar o mind_id.
-- As tabelas do app ficam como estão: as funções do app e o painel ainda as leem. A pesquisa do app está desligada.
-- Sai a visão engagement.avaliacao_app_2026, que ficou redundante.
-- DESFAZER:
--   delete from engagement.pesquisa_summit_2026 where origem in ('app_evento', 'app_dia');
--   alter table engagement.pesquisa_summit_2026 drop column origem, drop column dia, drop column expectativas,
--     drop column nota_relevancia, drop column nota_programacao, drop column mais_gostou, drop column melhorar,
--     drop column comentario, drop column notas_atividades;
--   (a visão avaliacao_app_2026: ver 20260924193724_pesquisas_organizacao_2026.sql e a migration original do app)

alter table engagement.pesquisa_summit_2026
  add column origem text not null default 'externa' check (origem in ('externa', 'app_evento', 'app_dia')),
  add column dia date,                                  -- só na avaliação do dia
  add column expectativas text,
  add column nota_relevancia smallint check (nota_relevancia between 0 and 5),
  add column nota_programacao smallint check (nota_programacao between 0 and 5),
  add column mais_gostou text,
  add column melhorar text,
  add column comentario text,
  add column notas_atividades jsonb;                    -- [{sessao_id, titulo, dia, nota}]
create index on engagement.pesquisa_summit_2026 (origem);

drop view engagement.avaliacao_app_2026;

select set_config('mind.d5_pular_trigger', '1', true);

insert into engagement.pesquisa_summit_2026 (resposta_ref, origem, dia, respondido_em, mind_id, mind_id_criterio, mind_id_resolvido_em,
       experiencia, profissao, expectativas, nota_relevancia, nota_programacao, mais_gostou, melhorar, comentario,
       notas_atividades, respostas)
select 'app_evento:' || a.id, 'app_evento', null::date, a.enviado_em, a.mind_id, 'app: pessoa da sessão do app', a.enviado_em,
       a.experiencia, a.profissao, a.expectativas, a.nota_relevancia, a.nota_programacao, a.mais_gostou, a.melhorar, a.comentario,
       (select jsonb_agg(jsonb_build_object('sessao_id', t.sessao_id, 'titulo', s.titulo, 'dia', s.dia, 'nota', t.nota)
                         order by s.dia, s.inicio, s.titulo)
          from engagement.avaliacao_do_evento_atividade t join summit_2026.sessions s on s.id = t.sessao_id
         where t.avaliacao_id = a.id),
       to_jsonb(a)
  from engagement.avaliacao_do_evento a
union all
select 'app_dia:' || a.id, 'app_dia', a.dia, a.enviado_em, a.mind_id, 'app: pessoa da sessão do app', a.enviado_em,
       a.experiencia, a.profissao, a.expectativas, a.nota_relevancia, a.nota_programacao, a.mais_gostou, a.melhorar, a.comentario,
       (select jsonb_agg(jsonb_build_object('sessao_id', t.sessao_id, 'titulo', s.titulo, 'dia', s.dia, 'nota', t.nota)
                         order by s.dia, s.inicio, s.titulo)
          from engagement.avaliacao_do_dia_atividade t join summit_2026.sessions s on s.id = t.sessao_id
         where t.avaliacao_id = a.id),
       to_jsonb(a)
  from engagement.avaliacao_do_dia a;

select set_config('mind.d5_pular_trigger', '', true);
