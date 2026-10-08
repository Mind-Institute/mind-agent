-- Relatório de valor — seções 11 a 14 (24/09/2026): Mind Summit 2024, comparação 2024 × 2025 × 2026,
-- pesquisas dos três anos e convidados Vale/Heineken presentes em 16 e 17/09.
-- Mesma régua para os três anos: INSCRITOS = ingresso "Atribuído" em eduzz.ingressos (pessoa canônica),
-- sem staff e palestrantes (pessoas.relacionamento_mind). Não há check-in de 2024 e 2025 na base.

-- 11 · 2024: o mesmo SQL de docs/sql/relatorio_2025_numeros.sql, trocando 'Mind Summit 2025' por
-- 'Mind Summit 2024' (e a25/g25 por a24/g24); delegações a partir de 3 inscritos (n >= 3), porque em
-- 2024 só três empresas tinham 5 ou mais. Para 2026 na comparação, o mesmo SQL com 'Mind Summit 2026'.

-- 12 · Recorrência entre os anos (pessoas e empresas). Empresa agrupada pela mesma chave k das seções 3 e 9.
set statement_timeout = '55s';
create temp table tri on commit drop as
with t as (
  select distinct substr(i.evento_titulo, 13, 4)::int ano, public.mind_pessoa_canonica(i.mind_id) mind_id
    from eduzz.ingressos i
   where i.evento_titulo in ('Mind Summit 2024', 'Mind Summit 2025', 'Mind Summit 2026') and i.status = 'Atribuído' and i.mind_id is not null),
b as (
  select t.ano, p.id mind_id,
         case when p.empresa is null or p.empresa ~* '^(aut[oô]nom[oa]|freelancer?|nenhuma?|sem empresa)$' then null else p.empresa end emp,
         case when lower(split_part(p.email, '@', 2)) ~ '(gmail|gmai\.|hotmail|hotmai\.|outlook|outlok|yahoo|icloud|live|uol|bol|terra|msn|me\.com|protonmail|globo\.com|ig\.com|joinmind)' then null
              else nullif(lower(split_part(p.email, '@', 2)), '') end cdom
    from t join pessoas.pessoas p on p.id = t.mind_id
   where not (coalesce(p.relacionamento_mind, '{}') && array['staff', 'palestrante'])),
nd as (select ano, emp, mode() within group (order by cdom) d from b where emp is not null and cdom is not null group by 1, 2)
select b.ano, b.mind_id, b.emp,
       case when b.emp is null then null
            when b.emp ~* 'heineken' then 'heineken.com.br'
            when b.emp ~* '^vale( |$)' then 'vale.com'
            when b.emp ~* '^bwg' then 'bwg.com.br'
            when b.emp ~* '(faculdade bp|benefici?encia portuguesa)' then 'bp.org.br'
            when b.emp ~* '^natura( |$)' then 'natura.net'
            when b.emp ~* 'haleon' then 'haleon.com'
            when b.emp ~* '(sextante|gmt editores)' then 'sextante.com.br'
            when b.emp ~* '^bluma' then 'blumaoficial.com.br'
            when b.emp ~* '^mais diversidade' then 'maisdiversidade.com.br'
            when b.emp ~* 'mindself' then 'mindself.com.br'
            when b.emp ~* 'senac' or nd.d ~ 'senac' then 'senac'
            when b.emp ~* '(sefaz|secretaria da fazenda)' then 'sefaz'
            when nd.d ~ 'beiersdorf' or b.emp ~* '(beiersdorf|bdf nivea)' then 'beiersdorf'
            when b.emp ~* 'sebrae' then 'sebrae'
            when b.emp ~* '^(usp|universidade de s[aã]o paulo)( |$)' then 'usp'
            when b.emp ~* '^(pmsp|prefeitura de s[aã]o paulo)' then 'pmsp'
            when nd.d in ('gympass.com', 'wellhub.com') or b.emp ~* '^(wellhub|wellz)' then 'wellhub'
            else coalesce(nd.d, 'n:' || intelligence.texto_chave(b.emp, true)) end k
  from b left join nd on nd.ano = b.ano and nd.emp = b.emp;
create temp table pres on commit drop as
select distinct public.mind_pessoa_canonica(mind_id) mind_id from intelligence.v_relatorio_patrocinador_audiencia where presente;
with p as (select mind_id, array_agg(distinct ano order by ano) anos from tri group by 1),
e as (select k, array_agg(distinct ano order by ano) anos, mode() within group (order by emp) nome,
             count(*) filter (where ano = 2024) n24, count(*) filter (where ano = 2025) n25, count(*) filter (where ano = 2026) n26
        from tri where k is not null group by 1)
select jsonb_build_object(
  'inscritos', (select jsonb_object_agg(ano, n) from (select ano, count(*) n from tri group by 1) x),
  'empresas', (select jsonb_object_agg(ano, n) from (select ano, count(distinct k) n from tri where k is not null group by 1) x),
  'p_24_25', (select count(*) from p where anos @> '{2024,2025}'),
  'p_24_26', (select count(*) from p where anos @> '{2024,2026}'),
  'p_25_26', (select count(*) from p where anos @> '{2025,2026}'),
  'p_3', (select count(*) from p where anos @> '{2024,2025,2026}'),
  'p24_presentes_26', (select count(*) from p join pres using (mind_id) where anos @> '{2024}'),
  'p25_presentes_26', (select count(*) from p join pres using (mind_id) where anos @> '{2025}'),
  'e_24_25', (select count(*) from e where anos @> '{2024,2025}'),
  'e_24_26', (select count(*) from e where anos @> '{2024,2026}'),
  'e_25_26', (select count(*) from e where anos @> '{2025,2026}'),
  'e_3', (select count(*) from e where anos @> '{2024,2025,2026}'),
  'top3', (select jsonb_agg(jsonb_build_array(nome, n24, n25, n26) order by n24 + n25 + n26 desc)
             from (select * from e where anos @> '{2024,2025,2026}' order by n24 + n25 + n26 desc limit 25) z)
) r;

-- 13 · Pesquisas. 2024, 2025 e 2026: engagement.pesquisa_summit_2024/2025/2026, mesmas perguntas lado a lado em
-- engagement.v_pesquisa_summit_comparativo. Avaliações do app de 2026 (evento + dia), escala 1 a 5, logo abaixo.
select * from engagement.v_pesquisa_summit_comparativo order by ano;
with r as (select mind_id, nota_relevancia, nota_programacao from engagement.pesquisa_summit_2026
            where origem in ('app_evento', 'app_dia'))
select count(*) avaliacoes, count(distinct public.mind_pessoa_canonica(mind_id)) pessoas,
       round(avg(nota_relevancia), 2) relevancia, round(avg(nota_programacao), 2) programacao,
       round(100.0 * count(*) filter (where nota_relevancia >= 4) / nullif(count(nota_relevancia), 0), 1) pct_relevancia_4_5,
       round(100.0 * count(*) filter (where nota_programacao >= 4) / nullif(count(nota_programacao), 0), 1) pct_programacao_4_5
  from r;
-- Média das notas de cada palestra/painel (perguntas "Avalie ..."), por ano.
with r as (
  select 2024 ano, kv.value from engagement.pesquisa_summit_2024 s, jsonb_each_text(s.respostas) kv where kv.key like 'Avalie%'
  union all
  select 2025, kv.value from engagement.pesquisa_summit_2025 s, jsonb_each_text(s.respostas) kv where kv.key like 'Avalie%')
select ano, round(avg(value::numeric), 2) media, round(100.0 * count(*) filter (where value::numeric >= 4) / count(*), 1) pct_4_5
  from r where value ~ '^\s*\d+(\.\d+)?\s*$' group by 1;

-- 14 · Convidados Vale e Heineken presentes (ingresso emitido pelo patrocinador, como na seção 8).
select v.patrocinador_ingresso pat, concat_ws(' ', p.primeiro_nome, p.sobrenome) nome, v.cargo, v.empresa,
       v.dia_16, v.dia_17,
       exists (select 1 from credenciamento_summit_2026.controle_de_inscritos_e_presenca c
                where c.mind_id = v.mind_id and c.confirmado_pela_adriana) confirmado_pela_adriana
  from intelligence.v_relatorio_patrocinador_audiencia v join pessoas.pessoas p on p.id = v.mind_id
 where v.patrocinador_ingresso in ('Vale', 'Heineken') and v.presente
 order by 1, 2;
