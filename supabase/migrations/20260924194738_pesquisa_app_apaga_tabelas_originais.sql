-- Saem as tabelas da pesquisa do app (Adriana, 24/09/2026: "depois de migrar apague as tabelas originais").
-- Tudo já está em engagement.pesquisa_summit_2026 (migration 20260924194631): a linha original inteira em respostas
-- e as notas por palestra em notas_atividades. A guarda abaixo confere isso antes de apagar.
-- Saem junto as 8 funções que só serviam a essas tabelas. O app já trata a falta: sem estado, a home não mostra o card
-- da pesquisa (avaliacao/servico.js), e a pesquisa já estava desligada.
-- DESFAZER: recriar pelas migrations 20260916210000_avaliacao_do_dia, 20260918120000_avaliacao_do_evento e
-- 20260918180000_avaliacao_do_evento_atividades, e recarregar a partir de pesquisa_summit_2026 (origem app_evento/app_dia).
do $$
declare falta int;
begin
  select count(*) into falta from (
    select 'app_evento:' || a.id ref, (select count(*) from engagement.avaliacao_do_evento_atividade t where t.avaliacao_id = a.id) n
      from engagement.avaliacao_do_evento a
    union all
    select 'app_dia:' || a.id, (select count(*) from engagement.avaliacao_do_dia_atividade t where t.avaliacao_id = a.id)
      from engagement.avaliacao_do_dia a) o
  left join engagement.pesquisa_summit_2026 p on p.resposta_ref = o.ref
  where p.id is null or coalesce(jsonb_array_length(p.notas_atividades), 0) <> o.n;
  if falta > 0 then raise exception '% respostas do app não estão completas em pesquisa_summit_2026', falta; end if;
end $$;

drop function public.mind_avaliacao_do_dia_estado(uuid, text, date);
drop function public.mind_avaliacao_do_dia_registrar(uuid, text, date, jsonb);
drop function public.mind_avaliacao_do_dia_relatorio(text, date, text);
drop function public.mind_avaliacao_do_dia_respostas(text, date, text, uuid, integer, integer);
drop function public.mind_avaliacao_do_evento_estado(uuid, text);
drop function public.mind_avaliacao_do_evento_registrar(uuid, text, jsonb);
drop function public.mind_avaliacao_do_evento_relatorio(text, text);
drop function public.mind_avaliacao_do_evento_respostas(text, text, integer, integer);

drop table engagement.avaliacao_do_dia_atividade;
drop table engagement.avaliacao_do_evento_atividade;
drop table engagement.avaliacao_do_dia;
drop table engagement.avaliacao_do_evento;
