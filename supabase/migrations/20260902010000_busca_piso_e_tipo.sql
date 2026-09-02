-- O termo a mais parava de somar e passava a EXIGIR. Medido em produção.
--
-- O SINTOMA, com 12 workshops cadastrados, completos:
--   'workshop'                                     -> 12
--   'workshop liderança'                           ->  3
--   'workshop RH'                                  ->  0
--   'workshop xpto'                                ->  0
--   'workshops recursos humanos liderança cultura' ->  3
-- Uma pergunta real ("Me indique workshops relacionados à RH") devolveu ZERO sessão,
-- e o Concierge respondeu com um workshop e um texto genérico. O dado nunca faltou.
--
-- A CAUSA NÃO ERA O `OR`. `q_foco` já é `lexema | lexema`. O que quebrava era o piso:
--
--     piso = 0.1 * least(2, greatest(1, n_foco))
--
-- `ts_rank_cd` sem normalização dá exatamente 0.1 para um lexema de peso D — que é o
-- peso de tudo aqui. Então:
--   n_foco = 1 -> piso 0.1 -> quem casa com um termo passa;
--   n_foco = 2 -> piso 0.2 -> quem casa com UM termo NÃO passa mais.
-- Ou seja: a partir do segundo termo, o piso passa a exigir cobertura, e a busca se
-- comporta como AND. Uma palavra que não existe no índice ("RH") não só não ajuda:
-- ela apaga todos os candidatos que casavam bem com a outra metade da pergunta.
--
-- A CORREÇÃO: o piso vira CONSTANTE. Ele volta a significar o que deveria — "este
-- registro casou com pelo menos um termo de assunto" — e a ordenação passa a ser
-- trabalho do `score`, não do filtro. Termo a mais volta a SOMAR relevância.
--
-- MAS TIPO DE SESSÃO NÃO É PALAVRA DE RELEVÂNCIA. Com o piso constante, "workshop
-- liderança" passaria a devolver palestra e painel que falam de liderança — e quem
-- pediu workshop quer workshop. `summit_2026.sessions.tipo` é verdade ESTRUTURAL:
-- quando a pergunta nomeia um tipo, ele filtra; dentro dele, o lexical ordena.
--
--     filtro estrutural + matching lexical amplo + ranking
--
-- A lista de tipos NÃO é escrita à mão: sai de `select distinct tipo from sessions`.
-- Um tipo novo no evento passa a valer sozinho.
--
-- E 'palestra' fica de fora de propósito. O andaime da pergunta — que esta função já
-- mantinha para não inflar o piso — classifica `palestr` como estrutura de pergunta,
-- não assunto, porque em português "palestra" é como as pessoas chamam qualquer
-- sessão. O mesmo julgamento vale aqui: o que já não conta como assunto também não
-- pode virar filtro. Por isso o andaime virou CTE, para as duas regras lerem a mesma
-- lista em vez de duas cópias que divergem.
--
-- FALLBACK. Tipo pedido e nenhuma sessão daquele tipo casando lexicalmente devolve as
-- sessões DAQUELE TIPO, em vez de zero. Dizer "não há programação" com 12 workshops
-- cadastrados é pior que entregar 12 títulos e deixar o Agent escolher.
--
-- NÃO MUDA: dia, faixa de horário, nome próprio, bloco de palestrantes, local,
-- `sessions_total`, fuso/horário local, e o `piso_amplo` dos blocos de conhecimento,
-- expositores e ofertas — que usam outro mecanismo e não são a causa medida aqui.

create or replace function public.mindagent_chat_search(p_event_slug text, p_query text, p_limit integer default 8)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public', 'summit_2026', 'ecossistema', 'engagement', 'intelligence', 'mind'
as $function$
with
bruto as (
  select
    lower(btrim(left(p_query, 500))) as q,
    -- Teto de 12 subiu para 24: "quais são TODOS os workshops" precisa caber. Quem
    -- pede menos continua recebendo menos; `sessions_total` continua dizendo a verdade
    -- quando a lista é cortada.
    least(24, greatest(1, coalesce(p_limit, 8))) as lim,
    lower(translate(left(p_query, 500),
      'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
      'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc')) as qn
),
palavras as (
  select b.*, ' ' || regexp_replace(b.qn, '[^a-z0-9]+', ' ', 'g') || ' ' as qp
  from bruto b
),
lexemas as (
  select l.lexeme from unnest(to_tsvector('portuguese', left(p_query, 500))) l
),
-- ANDAIME DA PERGUNTA, agora em CTE. Palavras que estruturam a pergunta em vez de
-- dizer o assunto dela. Mesma lista de sempre, um lugar só: `foco_lex` a usa para não
-- inflar o piso, e `tipos_pedidos` a usa para não transformar "palestra" em filtro.
andaime(lex) as (
  select unnest(array[
    'acontec','agend','ajud','algo','algum','amanh','amanhã','apresent','cois','comec',
    'conteud','conteúd','cronogram','dia','dias','duraca','duraçã','é','espac','esta',
    'event','fal','gost','grad','hav','hoj','hor','horari','horári','indic','inform',
    'informaca','informaco','lineup','list','loc','local','manh','manhã','mind','minut',
    'mostr','noit','onde','palestr','particip','pod','program','programaca','qua','quant',
    'quer','recomend','recomendaca','rol','sab','sal','sao','sei','ser','sessa','sessã',
    'sesso','sessõ','sobr','suger','sugesta','sugestã','summit','tard','ter','termin',
    'vai','ver'])
),
foco_lex as (
  select lexeme from lexemas
  where lexeme !~ '^[0-9]+(h([0-9]{2})?)?$'
    and lexeme !~ '^[0-9]{1,2}:[0-9]{2}$'
    and not exists (select 1 from andaime a where a.lex = lexeme)
),
params as (
  select b.q, b.qn, b.qp, b.lim,
    (select nullif(string_agg(lexeme, ' | '), '') from lexemas)::tsquery as q_or,
    (select nullif(string_agg(lexeme, ' | '), '') from foco_lex)::tsquery as q_foco,
    (select count(*) from foco_lex) as n_foco,
    -- PISO CONSTANTE. 0.1 é exatamente o que `ts_rank_cd` dá a um lexema de peso D —
    -- ou seja, "casou com pelo menos um termo de assunto". Escalar isso com a
    -- quantidade de termos era o que transformava OR em AND.
    0.1::real as piso,
    -- Preservado como está: os blocos de conhecimento/expositores/ofertas usam `q_or`
    -- (pergunta inteira), outro mecanismo, e não são a causa medida aqui.
    0.1 * least(2, greatest(1, (select count(*) from lexemas))) as piso_amplo,
    b.qn ~ '(programacao|programa|agenda|grade|cronograma|line ?up|o que tem|o que vai ter|o que acontece|o que rola|quais sessoes|todas as sessoes|sessoes|palestras)' as listar,
    b.qn ~ '(palestrante|speaker|quem vai falar|quem fala|quem sao|line ?up)' as listar_pessoas
  from palavras b
),
ev as (
  select e.* from summit_2026.events e, params p
  where e.slug = p_event_slug and e.ativo limit 1
),
loc as (
  select api.treble_find_location(p_event_slug, p_query) as items
),
-- ------------------------------------------------------- TIPO DE SESSÃO PEDIDO
-- Verdade estrutural, não palavra de relevância. Derivado de `sessions.tipo` — nada
-- escrito à mão, tipo novo no evento passa a valer sozinho. O nome do tipo é
-- normalizado do mesmo jeito que a pergunta ('alumni-talk' -> 'alumni talk'), e o
-- plural entra porque é assim que se pergunta ("quais são os workshops?").
tipos_pedidos as (
  select array_agg(distinct t.tipo) as tipos
  from (
    select distinct s.tipo,
           btrim(regexp_replace(lower(s.tipo), '[^a-z0-9]+', ' ', 'g')) as tipo_n
    from summit_2026.sessions s join ev e on e.id = s.event_id
    where s.tipo is not null and btrim(s.tipo) <> ''
  ) t
  cross join params p
  -- PLURAL SEM STEMMER. Medido: o stemmer português não serve para isto — 'workshops'
  -- vira `workshops`, 'masterclasses' vira `mastercl`, 'painéis' vira `pain`, e nenhum
  -- bate com o lexema do tipo. Então a regra é de prefixo com sufixo curto: a palavra
  -- da pergunta começa com o nome do tipo e admite até duas letras a mais. Cobre
  -- workshop/workshops e masterclass/masterclasses.
  -- GAP CONHECIDO: plural irregular ('painel' -> 'painéis') não casa. Fica registrado
  -- em vez de disfarçado; nenhum caso de uso pediu isso ainda.
  where p.qp ~ ('\m' || t.tipo_n || '[a-z]{0,2}\M')
    -- Tipo que o andaime já classifica como estrutura de pergunta não vira filtro.
    -- Na prática: 'palestra', que em português nomeia qualquer sessão.
    and not exists (
      select 1 from unnest(to_tsvector('portuguese', t.tipo)) lx
      join andaime a on a.lex = lx.lexeme)
),
meses_pt as (
  select array['janeiro','fevereiro','marco','abril','maio','junho',
               'julho','agosto','setembro','outubro','novembro','dezembro']::text[] as m
),
regiao_dia as (
  select coalesce((regexp_match(p.qn, '\mdias?\M([0-9 ,e/-]{0,24})'))[1], '') as reg
  from params p
),
dia_pedido as (
  select array_agg(distinct d.dia) as dias
  from (select distinct s.dia from summit_2026.sessions s join ev e on e.id = s.event_id) d
  cross join params p
  cross join meses_pt mp
  cross join regiao_dia rd
  where
    rd.reg ~ ('(^|[^0-9])' || to_char(d.dia, 'FMDD') || '([^0-9]|$)')
    or p.qn ~ ('(^|[^0-9])' || to_char(d.dia, 'FMDD') || '[/-]0?' || to_char(d.dia, 'FMMM') || '([^0-9]|$)')
    or p.qn like '%' || to_char(d.dia, 'YYYY-MM-DD') || '%'
    or p.qn ~ ('(^|[^0-9])' || to_char(d.dia, 'FMDD') || '\s+de\s+' ||
               mp.m[extract(month from d.dia)::int])
),
hora_dita as (
  select
    coalesce(
      (regexp_match(p.qn, '(?:^|[^0-9])([0-9]{1,2})[:h]([0-9]{2})(?![0-9])'))[1],
      (regexp_match(p.qn, '(?:^|[^0-9])([0-9]{1,2})\s*(?:h|horas)(?![0-9])'))[1]
    )::int as hora,
    (regexp_match(p.qn, '(?:^|[^0-9])([0-9]{1,2})[:h]([0-9]{2})(?![0-9])'))[2]::int as minuto
  from params p
),
faixa as (
  select
    case
      when hd.hora between 0 and 23 and hd.minuto between 0 and 59 then 'instante'
      when hd.hora between 0 and 23                                then 'sobreposicao'
      when p.qn ~ '\m(manha|tarde|noite|noturn)'                   then 'inicio'
    end as modo,
    case
      when hd.hora between 0 and 23 and hd.minuto between 0 and 59
        then make_time(hd.hora, hd.minuto, 0)
      else greatest(
        case when p.qn ~ '\mmanha'          then time '00:00:00'
             when p.qn ~ '\mtarde'          then time '12:00:00'
             when p.qn ~ '\m(noite|noturn)' then time '18:00:00' end,
        case when hd.hora between 0 and 23  then make_time(hd.hora, 0, 0) end)
    end as ini,
    case
      when hd.hora between 0 and 23 and hd.minuto between 0 and 59
        then make_time(hd.hora, hd.minuto, 0)
      else least(
        case when p.qn ~ '\mmanha'          then time '12:00:00'
             when p.qn ~ '\mtarde'          then time '18:00:00'
             when p.qn ~ '\m(noite|noturn)' then time '23:59:59' end,
        case when hd.hora between 0 and 23  then make_time(hd.hora, 59, 59) end)
    end as fim
  from params p cross join hora_dita hd
),
pessoa_evento as (
  select sp.id, sp.nome, sp.cargo_curto, sp.instituicao, sp.quem_e,
    btrim(regexp_replace(
      lower(translate(sp.nome,
        'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
        'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc')),
      '[^a-z0-9]+', ' ', 'g')) as nome_n,
    to_tsvector('portuguese',
      sp.nome || ' ' || coalesce(sp.cargo_curto, '') || ' ' || coalesce(sp.instituicao, '')) as tsv
  from ecossistema.palestrantes_especialistas sp
  where exists (
    select 1 from summit_2026.session_speakers ss
    join summit_2026.sessions s on s.id = ss.sessao_id
    join ev e on e.id = s.event_id
    where ss.speaker_id = sp.id)
),
pessoa_nomeada as (
  select pe.id,
    max(case when p.qp like '% ' || pe.nome_n || ' %' then 1.0 else 0.5 end) as forca
  from pessoa_evento pe
  cross join params p
  where p.qp like '% ' || pe.nome_n || ' %'
     or exists (
       select 1 from unnest(string_to_array(pe.nome_n, ' ')) t
       where length(t) >= 4 and p.qp like '% ' || t || ' %')
  group by pe.id
),
sessao_base as (
  select s.id, s.titulo, s.descricao, s.dia, s.inicio, s.fim, s.tipo,
         s.precisa_reserva, s.lugares_limitados, s.reserva_recomendada,
         s.vagas_disponiveis, s.espaco_id,
         to_tsvector('portuguese',
           coalesce(s.titulo, '') || ' ' || coalesce(s.descricao, '') || ' ' ||
           array_to_string(coalesce(s.trilhas, '{}'::text[]), ' ') || ' ' ||
           coalesce(s.tipo, '') || ' ' ||
           case when s.tipo is not null and right(s.tipo, 1) <> 's'
                then s.tipo || 's ' else '' end ||
           case when s.precisa_reserva     then 'precisa reserva '      else '' end ||
           case when s.lugares_limitados   then 'lugares limitados '    else '' end ||
           case when s.reserva_recomendada then 'reserva recomendada '  else '' end ||
           coalesce((
             select string_agg(sp.nome || ' ' || coalesce(sp.instituicao, ''), ' ')
             from summit_2026.session_speakers ss
             join ecossistema.palestrantes_especialistas sp on sp.id = ss.speaker_id
             where ss.sessao_id = s.id), '')
         ) as tsv
  from summit_2026.sessions s
  join ev e on e.id = s.event_id
),
sessao_foco_n as (
  select count(*) as n
  from sessao_base sb
  cross join params p
  where (p.q_foco is not null and ts_rank_cd(sb.tsv, p.q_foco) >= p.piso)
     or exists (select 1 from summit_2026.session_speakers ss
                join pessoa_nomeada pn on pn.id = ss.speaker_id
                where ss.sessao_id = sb.id)
),
-- Quantas sessões DO TIPO PEDIDO casaram lexicalmente. Zero aqui liga o fallback.
sessao_tipo_n as (
  select count(*) as n
  from sessao_base sb
  cross join params p
  cross join tipos_pedidos tp
  where tp.tipos is not null and sb.tipo = any (tp.tipos)
    and p.q_foco is not null and ts_rank_cd(sb.tsv, p.q_foco) >= p.piso
),
session_ranked as (
  select
    sb.id, sb.titulo, sb.descricao, sb.dia, sb.inicio, sb.fim, sb.tipo,
    sb.precisa_reserva, sb.lugares_limitados, sb.reserva_recomendada,
    sb.vagas_disponiveis,
    l.nome as local,
    e.fuso,
    greatest(
      case when p.q_foco is not null then ts_rank_cd(sb.tsv, p.q_foco) else 0 end,
      coalesce((select max(pn.forca) from summit_2026.session_speakers ss
                join pessoa_nomeada pn on pn.id = ss.speaker_id
                where ss.sessao_id = sb.id), 0)
    ) as score
  from sessao_base sb
  cross join params p
  cross join ev e
  cross join dia_pedido dp
  cross join faixa fx
  cross join tipos_pedidos tp
  left join summit_2026.locations l on l.id = sb.espaco_id
  where (
      (p.q_foco is not null and ts_rank_cd(sb.tsv, p.q_foco) >= p.piso)
      or exists (select 1 from summit_2026.session_speakers ss
                 join pessoa_nomeada pn on pn.id = ss.speaker_id
                 where ss.sessao_id = sb.id)
      or ((p.listar or dp.dias is not null or fx.modo is not null) and (p.n_foco = 0 or (select n from sessao_foco_n) = 0))
      -- FALLBACK DO TIPO. Pediu workshop, nenhum workshop casou lexicalmente:
      -- devolve os workshops. Zero seria mentira — eles existem.
      or (tp.tipos is not null and sb.tipo = any (tp.tipos) and (select n from sessao_tipo_n) = 0)
    )
    -- FILTRO ESTRUTURAL. Pediu workshop, só workshop entra — por mais que uma
    -- palestra fale do mesmo assunto.
    and (tp.tipos is null or sb.tipo = any (tp.tipos))
    and (dp.dias is null or sb.dia = any (dp.dias))
    and (fx.modo is null or (
      case fx.modo
        when 'instante'     then (sb.inicio at time zone e.fuso)::time <= fx.ini
                             and (sb.fim    at time zone e.fuso)::time >  fx.ini
        when 'sobreposicao' then (sb.inicio at time zone e.fuso)::time <  fx.fim
                             and (sb.fim    at time zone e.fuso)::time >  fx.ini
        else                     (sb.inicio at time zone e.fuso)::time >= fx.ini
                             and (sb.inicio at time zone e.fuso)::time <  fx.fim
      end))
),
session_items as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x.id, 'title', x.titulo, 'description', x.descricao,
    'date', x.dia,
    'starts_at', x.inicio at time zone x.fuso,
    'ends_at',   x.fim    at time zone x.fuso,
    'starts_at_local', to_char(x.inicio at time zone x.fuso, 'HH24:MI'),
    'ends_at_local',   to_char(x.fim    at time zone x.fuso, 'HH24:MI'),
    'timezone', x.fuso,
    'type', x.tipo, 'location', x.local,
    'requires_reservation', x.precisa_reserva,
    'limited_seats', x.lugares_limitados,
    'reservation_recommended', x.reserva_recomendada,
    'available_places', x.vagas_disponiveis,
    'speakers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', sp.nome, 'role', sp.cargo_curto,
        'organization', sp.instituicao, 'participation', ss.papel
      ) order by sp.nome)
      from summit_2026.session_speakers ss
      join ecossistema.palestrantes_especialistas sp on sp.id = ss.speaker_id
      where ss.sessao_id = x.id), '[]'::jsonb)
  ) order by x.score desc, x.inicio, x.titulo), '[]'::jsonb) as items
  from (select * from session_ranked order by score desc, inicio, titulo
        limit (select lim from params)) x
),
speaker_foco_n as (
  select count(*) as n
  from pessoa_evento pe
  cross join params p
  left join pessoa_nomeada pn on pn.id = pe.id
  where pn.id is not null
     or (p.q_foco is not null and ts_rank_cd(pe.tsv, p.q_foco) >= p.piso)
),
speaker_ranked as (
  select pe.id, pe.nome, pe.cargo_curto, pe.instituicao, pe.quem_e,
    greatest(
      coalesce(pn.forca, 0),
      case when p.q_foco is not null then ts_rank_cd(pe.tsv, p.q_foco) else 0 end
    ) as score
  from pessoa_evento pe
  cross join params p
  cross join dia_pedido dp
  cross join faixa fx
  left join pessoa_nomeada pn on pn.id = pe.id
  where (
      pn.id is not null
      or (p.q_foco is not null and ts_rank_cd(pe.tsv, p.q_foco) >= p.piso)
      or (p.listar_pessoas and (p.n_foco = 0 or (select n from speaker_foco_n) = 0))
    )
    and ((dp.dias is null and fx.modo is null) or exists (
      select 1 from summit_2026.session_speakers ss
      join summit_2026.sessions s on s.id = ss.sessao_id
      join ev e3 on e3.id = s.event_id
      where ss.speaker_id = pe.id
        and (dp.dias is null or s.dia = any (dp.dias))
        and (fx.modo is null or (
          case fx.modo
            when 'instante'     then (s.inicio at time zone e3.fuso)::time <= fx.ini
                                 and (s.fim    at time zone e3.fuso)::time >  fx.ini
            when 'sobreposicao' then (s.inicio at time zone e3.fuso)::time <  fx.fim
                                 and (s.fim    at time zone e3.fuso)::time >  fx.ini
            else                     (s.inicio at time zone e3.fuso)::time >= fx.ini
                                 and (s.inicio at time zone e3.fuso)::time <  fx.fim
          end))))
),
speaker_items as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x.id, 'name', x.nome, 'role', x.cargo_curto,
    'organization', x.instituicao, 'bio', x.quem_e, 'themes', '[]'::jsonb,
    'sessions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'title', s.titulo, 'date', s.dia,
        'starts_at', s.inicio at time zone e2.fuso,
        'ends_at',   s.fim    at time zone e2.fuso,
        'starts_at_local', to_char(s.inicio at time zone e2.fuso, 'HH24:MI'),
        'ends_at_local',   to_char(s.fim    at time zone e2.fuso, 'HH24:MI'),
        'timezone', e2.fuso,
        'location', l.nome, 'participation', ss.papel
      ) order by s.inicio)
      from summit_2026.session_speakers ss
      join summit_2026.sessions s on s.id = ss.sessao_id
      join ev e2 on e2.id = s.event_id
      cross join dia_pedido dp2
      cross join faixa fx2
      left join summit_2026.locations l on l.id = s.espaco_id
      where ss.speaker_id = x.id
        and (dp2.dias is null or s.dia = any (dp2.dias))
        and (fx2.modo is null or (
          case fx2.modo
            when 'instante'     then (s.inicio at time zone e2.fuso)::time <= fx2.ini
                                 and (s.fim    at time zone e2.fuso)::time >  fx2.ini
            when 'sobreposicao' then (s.inicio at time zone e2.fuso)::time <  fx2.fim
                                 and (s.fim    at time zone e2.fuso)::time >  fx2.ini
            else                     (s.inicio at time zone e2.fuso)::time >= fx2.ini
                                 and (s.inicio at time zone e2.fuso)::time <  fx2.fim
          end))), '[]'::jsonb)
  ) order by x.score desc, x.nome), '[]'::jsonb) as items
  from (select * from speaker_ranked order by score desc, nome
        limit (select lim from params)) x
),
mind_items as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'category', x.tipo_conteudo, 'title', x.titulo, 'body', x.corpo
  ) order by x.score desc, x.titulo), '[]'::jsonb) as items
  from (
    select k.tipo_conteudo, k.titulo, left(k.corpo, 1500) as corpo,
      ts_rank_cd(to_tsvector('portuguese',
        coalesce(k.tipo_conteudo,'') || ' ' || k.titulo || ' ' || k.corpo), p.q_or) as score
    from summit_2026.knowledge_documents k
    cross join params p
    where k.ativo
      and 'concierge' = any(k.agents)
      and (k.event_id is null or k.event_id = (select id from ev))
      and (k.valido_de is null or k.valido_de <= now())
      and (k.valido_ate is null or k.valido_ate > now())
      and (
        (p.q_or is not null and ts_rank_cd(to_tsvector('portuguese',
          coalesce(k.tipo_conteudo,'') || ' ' || k.titulo || ' ' || k.corpo), p.q_or) >= p.piso_amplo)
        or p.q ~ '(sobre a mind|o que e a mind|o que é a mind|empresa mind|institucional)'
      )
    order by score desc, k.titulo
    limit (select lim from params)
  ) x
),
exhibitor_items as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x.id, 'name', x.nome, 'description', x.descricao,
    'category', x.categoria, 'location', x.local_nome, 'website', x.site_url
  ) order by x.score desc, x.nome), '[]'::jsonb) as items
  from (
    select x.*, l.nome as local_nome,
      ts_rank_cd(to_tsvector('portuguese',
        x.nome || ' ' || coalesce(x.descricao,'') || ' ' || coalesce(x.categoria,'')), p.q_or) as score
    from summit_2026.exhibitors x
    join ev e on e.id = x.event_id
    left join summit_2026.locations l on l.id = x.location_id
    cross join params p
    where x.ativo
      and (
        (p.q_or is not null and ts_rank_cd(to_tsvector('portuguese',
          x.nome || ' ' || coalesce(x.descricao,'') || ' ' || coalesce(x.categoria,'')), p.q_or) >= p.piso_amplo)
        or p.q ~ '(estande|stand|expositor|patrocinador)'
      )
    order by score desc, x.nome
    limit (select lim from params)
  ) x
),
offer_items as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', x.codigo, 'name', x.nome, 'description', x.descricao,
    'currency', x.moeda, 'amount', x.valor,
    'payment_terms', x.condicoes_pagamento, 'checkout_url', x.checkout_url,
    'eligibility', x.elegibilidade
  ) order by x.score desc, x.valor), '[]'::jsonb) as items
  from (
    select o.*,
      ts_rank_cd(to_tsvector('portuguese',
        o.codigo || ' ' || o.nome || ' ' || coalesce(o.descricao,'')), p.q_or) as score
    from summit_2026.offers o
    cross join params p
    where o.ativo and o.publico
      and (o.event_id is null or o.event_id = (select id from ev))
      and (o.inicia_em is null or o.inicia_em <= now())
      and (o.encerra_em is null or o.encerra_em > now())
      and (
        (p.q_or is not null and ts_rank_cd(to_tsvector('portuguese',
          o.codigo || ' ' || o.nome || ' ' || coalesce(o.descricao,'')), p.q_or) >= 0.1)
        or p.q ~ '(valor|preço|preco|ingresso|comprar|compra|checkout|pagamento|oferta)'
      )
  ) x
)
select jsonb_build_object(
  'event', (select jsonb_build_object(
      'slug', e.slug, 'name', e.nome, 'dates', e.dias,
      'location', e.local, 'city', e.cidade, 'timezone', e.fuso) from ev e),
  'locations', (select items from loc),
  'sessions', (select items from session_items),
  'sessions_total', (select count(*) from session_ranked),
  'speakers', (select items from speaker_items),
  'mind', (select items from mind_items),
  'exhibitors', (select items from exhibitor_items),
  'offers', (select items from offer_items),
  'official_note', 'Use somente estes dados oficiais. Se algo não estiver presente, informe que ainda não está disponível. Horário apresentado à pessoa é sempre starts_at_local/ends_at_local, no fuso indicado em timezone; nenhum horário desta resposta está em UTC.'
);
$function$;

-- GUARDA. Os casos exatos que foram medidos em produção antes da correção. Falhar
-- aqui é melhor que descobrir num turno com gente do outro lado.
do $$
declare
  n_total int;
  f  jsonb;
  n  int;
  d  int;
begin
  select count(*) into n_total from summit_2026.sessions s
   join summit_2026.events e on e.id = s.event_id and e.slug = 'mind-summit-2026'
   where s.tipo = 'workshop';

  -- 1. termo que não existe no índice não pode mais zerar a busca
  foreach f in array array[
    to_jsonb('workshop'::text), to_jsonb('workshop RH'::text),
    to_jsonb('workshop xpto'::text), to_jsonb('workshop liderança'::text),
    to_jsonb('quais workshops você recomenda para RH?'::text),
    to_jsonb('workshops recursos humanos liderança cultura'::text)]
  loop
    select jsonb_array_length(coalesce(
      public.mindagent_chat_search('mind-summit-2026', f #>> '{}', 24)->'sessions','[]'::jsonb))
      into n;
    if n <> n_total then
      raise exception 'busca de workshop devolveu % (esperado %) para: %', n, n_total, f #>> '{}';
    end if;
  end loop;

  -- 2. tipo pedido não pode trazer outro tipo
  select count(*) into n
  from jsonb_array_elements(
    public.mindagent_chat_search('mind-summit-2026', 'quero workshops sobre liderança', 24)->'sessions') x
  where x->>'type' <> 'workshop';
  if n > 0 then raise exception 'workshop trouxe % sessão de outro tipo', n; end if;

  -- 3. dia continua recortando
  select jsonb_array_length(
    public.mindagent_chat_search('mind-summit-2026', 'quero saber todos os workshops do dia 17', 24)->'sessions')
    into d;
  if d <> 6 then raise exception 'workshops do dia 17 devolveu % (esperado 6)', d; end if;

  -- 4. masterclass é tipo estrutural também, no singular e no plural
  select count(*) into n_total from summit_2026.sessions s
   join summit_2026.events e on e.id = s.event_id and e.slug = 'mind-summit-2026'
   where s.tipo = 'masterclass';
  foreach f in array array[
    to_jsonb('quais são as masterclasses?'::text),
    to_jsonb('masterclass para alguém interessado em burnout'::text)]
  loop
    select jsonb_array_length(
      public.mindagent_chat_search('mind-summit-2026', f #>> '{}', 24)->'sessions') into n;
    if n <> n_total then
      raise exception 'masterclass devolveu % (esperado %) para: %', n, n_total, f #>> '{}';
    end if;
  end loop;

  -- 5. nome próprio preservado
  select jsonb_array_length(
    public.mindagent_chat_search('mind-summit-2026', 'quando fala Christina Maslach?', 12)->'speakers')
    into n;
  if n < 1 then raise exception 'nome proprio regrediu: Christina Maslach nao achou palestrante'; end if;
end $$;
