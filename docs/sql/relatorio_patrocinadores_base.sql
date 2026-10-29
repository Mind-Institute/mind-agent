-- Relatório de patrocinadores (Summit 2026): base comum a todas as seções da página.
-- Uma linha por PRESENTE. Empresa agrupada: nomes da mesma empresa somados pelo domínio de e-mail
-- corporativo (o mais comum entre as pessoas que declararam aquele nome) + regras de unidade/sigla.
-- Porte e setor da pessoa = porte (maior) e setor (mais comum) do grupo. Patrocinador = grupo cuja
-- empresa é patrocinadora (Beiersdorf entra como delegação, pedido da Adriana).
set statement_timeout = '55s';
create temp table aud on commit drop as
with a as (
  select v.*, nullif(lower(split_part(p.email, '@', 2)), '') dom
    from intelligence.v_relatorio_patrocinador_audiencia v
    join pessoas.pessoas p on p.id = v.mind_id
   where v.presente),
b as (
  select a.*,
         case when empresa is null or empresa ~* '^(aut[oô]nom[oa]|freelancer?|nenhuma?|sem empresa)$' then null else empresa end emp,
         case when dom ~ '(gmail|gmai\.|hotmail|hotmai\.|outlook|outlok|yahoo|icloud|live|uol|bol|terra|msn|me\.com|protonmail|globo\.com|ig\.com|joinmind)' then null else dom end cdom
    from a),
nd as (select emp, mode() within group (order by cdom) d from b where emp is not null and cdom is not null group by 1)
select b.*,
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
  from b left join nd using (emp);
create temp table grp on commit drop as
select k, count(*) n, mode() within group (order by emp) nome, max(porte) porte, mode() within group (order by setor) setor,
       bool_or(k in ('heineken.com.br', 'vale.com', 'bwg.com.br', 'bp.org.br', 'natura.net', 'wellhub', 'haleon.com',
                     'sextante.com.br', 'blumaoficial.com.br', 'maisdiversidade.com.br', 'mindself.com.br')
               or emp ~* '^(profera|chilli beans)') patrocinador
  from aud where k is not null group by k;
