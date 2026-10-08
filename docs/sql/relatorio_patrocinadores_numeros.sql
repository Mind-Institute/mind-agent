-- Relatório de patrocinadores (Summit 2026): todos os números da página, depois de rodar
-- relatorio_patrocinadores_base.sql na mesma transação (temp tables aud e grp).
-- Pelo MCP (limite de 60 s) roda em três partes: (1) base + blocos de aud/grp; (2) 'insc' e 'pat' só com a view;
-- (3) 'sessoes' e 'persona' com a view + chk. 'pat' exclui Imprensa, Beiersdorf (delegação), SME e Brascorp na página.
create temp table chk on commit drop as
select distinct public.mind_pessoa_canonica(c.mind_id) mind_id, s.id sessao_id, s.tipo, s.titulo, s.dia
  from credenciamento_summit_2026."Check Ins Summit" c
  join summit_2026.sessions s on s.id = c.sessao_id
 where c.mind_id is not null
   and s.tipo in ('palestra', 'painel', 'workshop', 'masterclass', 'experiencia', 'alumni-talk', 'entrevista', 'abertura');
create temp table ap on commit drop as
select a.*, g.porte gporte, g.setor gsetor, coalesce(g.patrocinador, false) patroc, g.nome gnome
  from aud a left join grp g using (k);
select jsonb_build_object(
 'dim', (select jsonb_build_object('presentes', count(*), 'd16', count(*) filter (where dia_16), 'd17', count(*) filter (where dia_17),
                                   'dois', count(*) filter (where dois_dias)) from ap),
 'insc', (with o as (select public.mind_pessoa_canonica(c.mind_id) mind_id, bool_and(c.origem_ingresso = 'Cortesia') so_cortesia
                       from credenciamento_summit_2026.controle_de_inscritos_e_presenca c
                      where c.valido_no_mind = 'sim' and c.mind_id is not null group by 1)
          select jsonb_build_object('inscritos', count(*), 'cortesias', count(*) filter (where so_cortesia),
                                    'cortesias_presentes', count(*) filter (where so_cortesia and presente),
                                    'cortesias_ausentes', count(*) filter (where so_cortesia and not presente))
            from intelligence.v_relatorio_patrocinador_audiencia v left join o using (mind_id)),
 'ingresso', (select jsonb_object_agg(coalesce(ingresso, '?'), n) from (select ingresso, count(*) n from ap group by 1) x),
 'senioridade', (select jsonb_object_agg(coalesce(senioridade, '?'), n) from (select senioridade, count(*) n from ap group by 1) x),
 'area', (select jsonb_object_agg(coalesce(area, '?'), n) from (select area, count(*) n from ap group by 1) x),
 'icp', (select jsonb_object_agg(coalesce(icp, '?'), n) from (select icp, count(*) n from ap group by 1) x),
 'cargo_informado', (select count(*) from ap where nullif(btrim(cargo), '') is not null),
 'nao_rh', (select jsonb_build_object('n', count(*), 'sem_area', count(*) filter (where area = 'Liderança sem área informada'),
                                      'outras', count(*) filter (where area in ('Outras funções', 'Não informado')))
              from ap where icp in ('gestor_nao_rh', 'diretor_vp_nao_rh', 'analista_nao_rh')),
 'lideres_rh', (select jsonb_build_object('lideres', count(*), 'rh', count(*) filter (where area = 'RH / Pessoas')) from ap
                 where senioridade in ('C-level / Fundador(a) / Sócio(a)', 'VP / Diretor(a)', 'Head', 'Gerente', 'Coordenação / Liderança')),
 'emp', (select jsonb_build_object('com_empresa', (select count(*) from ap where k is not null), 'grupos', count(*),
                                   'g2', count(*) filter (where n >= 2), 'g5', count(*) filter (where n >= 5), 'g10', count(*) filter (where n >= 10),
                                   'com_porte', count(*) filter (where porte is not null)) from grp),
 'porte_pessoas', (select jsonb_object_agg(gporte, n) from (select gporte, count(*) n from ap where not patroc and gporte is not null group by 1) x),
 'porte_cob', (select jsonb_build_object('com_porte', count(*) filter (where gporte is not null), 'sem_patroc', count(*) filter (where not patroc),
                                         'sem_patroc_com_porte', count(*) filter (where not patroc and gporte is not null)) from ap),
 'porte_emp', (select jsonb_object_agg(porte, n) from (select porte, count(*) n from grp where porte is not null group by 1) x),
 'deleg', (select jsonb_agg(jsonb_build_array(nome, n, porte, setor) order by n desc, nome) from grp where not patrocinador and n >= 4),
 'patroc', (select jsonb_agg(jsonb_build_array(nome, n) order by n desc) from grp where patrocinador),
 'grandes', (select jsonb_agg(jsonb_build_array(porte, nome, n) order by porte desc, n desc, nome) from grp where porte ~ '^(5|6)\.'),
 'setor', (select jsonb_agg(jsonb_build_array(gsetor, n, ex) order by n desc) from (
            select s.gsetor, s.n, (select string_agg(nome, ', ' order by n desc, nome) from (
                      select nome, n from grp where setor = s.gsetor and not patrocinador order by n desc, porte desc nulls last, nome limit 3) z) ex
              from (select gsetor, count(*) n from ap where not patroc and gsetor is not null group by 1) s) x),
 'setor_cob', (select count(*) filter (where gsetor is not null) from ap),
 'app', (select jsonb_build_object('checkin', count(*) filter (where sessoes_checkin > 0), 'ativou', count(*) filter (where app_ativou),
                                   'reservou', count(*) filter (where reservas > 0), 'trocou', count(*) filter (where trocas_contato > 0),
                                   'mensagem', count(*) filter (where mensagens > 0), 'postou', count(*) filter (where postagens > 0),
                                   'reservas_media', round(avg(reservas) filter (where reservas > 0), 1),
                                   'checkin_mediana', percentile_cont(0.5) within group (order by sessoes_checkin) filter (where sessoes_checkin > 0),
                                   'checkin_media', round(avg(sessoes_checkin) filter (where sessoes_checkin > 0), 1),
                                   'trocas_mediana', percentile_cont(0.5) within group (order by trocas_contato) filter (where trocas_contato > 0),
                                   'trocas_por_pessoa', round(sum(trocas_contato)::numeric / count(*), 1)) from ap),
 'sessoes', (select jsonb_agg(jsonb_build_array(tipo, titulo, dia, n) order by tipo, n desc) from (
              select c.tipo, c.titulo, c.dia, count(*) n from chk c join ap using (mind_id) where c.tipo in ('masterclass', 'workshop') group by 1, 2, 3) x),
 'persona', (with gp as (
               select mind_id, 'RH' g from ap where area = 'RH / Pessoas'
               union all select mind_id, 'C-level' from ap where senioridade = 'C-level / Fundador(a) / Sócio(a)'
               union all select mind_id, 'Gestores' from ap where senioridade in ('Head', 'Gerente', 'Coordenação / Liderança')
               union all select mind_id, 'Saúde e bem-estar' from ap where area = 'Saúde e bem-estar'),
             tam as (select g, count(*) t from gp group by 1),
             tot as (select c.sessao_id, c.titulo, count(*) n from chk c join ap using (mind_id) group by 1, 2),
             gs as (select gp.g, c.sessao_id, count(*) gn from chk c join gp using (mind_id) group by 1, 2),
             l as (select gs.g, tam.t, tot.titulo, gs.gn, round((gs.gn::numeric / tam.t) / (tot.n::numeric / (select count(*) from ap)), 2) lift,
                          row_number() over (partition by gs.g order by (gs.gn::numeric / tam.t) / tot.n desc) rn
                     from gs join tam using (g) join tot using (sessao_id) where gs.gn >= 20)
             select jsonb_agg(jsonb_build_array(g, t, titulo, gn, lift) order by g, rn) from l where rn <= 4),
 'pat', (select jsonb_agg(jsonb_build_array(patrocinador_ingresso, ingressos, presentes, lid, rh, app, trocas) order by presentes desc) from (
          select patrocinador_ingresso, count(*) ingressos, count(*) filter (where presente) presentes,
                 count(*) filter (where presente and senioridade in ('C-level / Fundador(a) / Sócio(a)', 'VP / Diretor(a)', 'Head', 'Gerente', 'Coordenação / Liderança')) lid,
                 count(*) filter (where presente and area = 'RH / Pessoas') rh, count(*) filter (where presente and app_ativou) app,
                 coalesce(sum(trocas_contato) filter (where presente), 0) trocas
            from intelligence.v_relatorio_patrocinador_audiencia where patrocinador_ingresso is not null and patrocinador_ingresso not in ('Mind') group by 1) x)
);
