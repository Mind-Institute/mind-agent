-- ============================================================
-- Concierge Summit — retrieval de programação e palestrantes
-- ------------------------------------------------------------
-- O QUE ESTA MIGRATION FAZ
--   Substitui o corpo de public.mindagent_chat_search. Mesma assinatura,
--   mesmas chaves de saída, mesmos consumidores. Só a seleção muda.
--
-- POR QUE — quatro defeitos medidos contra a produção de hoje (77 sessões,
-- 81 vínculos, 64 pessoas), não hipóteses:
--
--   1. NOME PRÓPRIO PARCIAL NÃO ACHA A PESSOA.
--      "onde é a sessão da Sonja?" devolvia speakers=[]. O casamento por nome
--      exigia o nome INTEIRO na pergunta ("sonja lyubomirsky") ou o último
--      token. Primeiro nome sozinho — que é como as pessoas perguntam — não
--      identificava ninguém.
--
--   2. O PISO DE RELEVÂNCIA REJEITAVA O ACERTO LITERAL.
--      piso = 0.1 × least(2, nº de lexemas DA PERGUNTA INTEIRA). Em
--      "conteúdos sobre burnout" a pergunta tem 3 lexemas (burnout, conteúd,
--      sobr) ⇒ piso 0.2. "Os 6 desalinhamentos do burnout" e "Cultura
--      emocional: entre o engajamento e o burnout" pontuam 0.1 cada — as duas
--      sessões que trazem burnout NO TÍTULO ficavam de fora de uma pergunta
--      sobre burnout. O erro é contar `conteúd` e `sobr` como se fossem
--      assunto: elas são andaime da pergunta, aparecem em qualquer pergunta e
--      não existem em registro nenhum. Só o que é assunto entra na conta.
--
--   3. O GATILHO DE CATEGORIA INUNDAVA A RESPOSTA.
--      `q ~ '(programa|agenda|horario|sessao|palestra)'` admitia TODAS as
--      sessões, com score zero, sempre que uma dessas palavras aparecesse —
--      inclusive em "tem sessão sobre criptomoedas e blockchain?", que
--      devolvia 8 sessões reais como OFFICIAL_CONTEXT de uma pergunta sobre
--      cripto. Superfície de invenção criada pelo próprio retrieval. Agora
--      listar a agenda é para quem pediu a agenda: o gatilho só vale quando a
--      pergunta NÃO tem assunto próprio.
--
--   4. NÃO HAVIA FILTRO DE DIA NEM DE HORÁRIO.
--      "o que tem na programação do dia 17 à tarde?" devolvia Credenciamento
--      e Abertura — manhã do dia 16. Dia e faixa saem da própria pergunta e
--      são deterministicos: os dias vêm de summit_2026.sessions, não de
--      constante.
--
--   5. O HORÁRIO CHEGAVA AO MODELO EM UTC.
--      `starts_at` é timestamptz e sai serializado como `...T22:00:00+00:00`.
--      A sessão das 19:00 em São Paulo vira 22:00 na resposta — a instrução do
--      concierge pede "HH:MM–HH:MM" e o modelo escreve o que recebeu.
--      Acrescentar um campo local não bastava: nada dizia ao modelo qual dos
--      dois vence, e o bloco de agenda do Treble nem recebe o `official_note`.
--      Então o UTC deixa de existir na saída.
--
--   6. NÚMERO SOLTO VIRAVA DATA.
--      `dia_pedido` aceitava o 16/17 solto, e o mesmo retrieval serve o bloco
--      de agenda do Treble, onde "somos 17 pessoas" e "quero 17 ingressos" são
--      o dia a dia. Data agora exige sinal inequívoco: a palavra `dia`
--      governando o número, data escrita ou mês por extenso.
--
--   7. O RECORTE VALIA SÓ NA METADE DA RESPOSTA.
--      `sessions` aplicava dia/faixa; `speakers[].sessions` devolvia todas as
--      sessões da pessoa. "Amy no dia 17" entregava as sessões do dia 16 dela
--      dentro do bloco da pessoa — duas verdades sobre a mesma pergunta, na
--      mesma resposta.
--
-- A MUDANÇA EM UMA FRASE
--   O piso passa a ser calculado sobre os lexemas de ASSUNTO da pergunta, e
--   nome próprio identifica a pessoa e traz as sessões dela.
--
-- CONTRATO PRESERVADO — verificado nos dois consumidores vivos
--   mindagent-chat lê `event` (não-nulo) e conta as chaves locations,
--   sessions, speakers, mind, exhibitors, offers.
--   treble-inbound-agent filtra a saída para sessions, speakers, locations,
--   exhibitors, mind (agendaSegura). Todas as chaves continuam existindo com
--   o mesmo nome e o mesmo formato. Campos novos são ADITIVOS.
--
-- CAMPOS DE SAÍDA — nada foi removido nem renomeado; `starts_at`/`ends_at`
-- mudam de FUSO, não de nome: saem no fuso do evento, sem offset, e passam a
-- concordar com `*_local`. Nenhum consumidor os lê programaticamente — o chat
-- só conta arrays, o Treble filtra chaves e varre números >= 100 no guardrail
-- de preço —, então a troca não muda contrato de código: ela só remove a
-- leitura errada de horário.
--   sessions[].starts_at / ends_at              — timestamp local, sem UTC
--   sessions[].timezone                         — o fuso, dentro do item, para
--                                                 ele se explicar sozinho
--                                                 mesmo depois de filtrado
--   sessions[].starts_at_local / ends_at_local  — HH:MM no fuso do evento
--   sessions[].type                             — tipo da sessão, inclusive
--                                                 `em-curadoria`, para o
--                                                 concierge não apresentar
--                                                 como fechado o que não é
--   sessions[].limited_seats / reservation_recommended
--                                               — os flags canônicos da #37;
--                                                 `requires_reservation`
--                                                 (legado) continua saindo
--   sessions[].speakers[].participation         — papel do vínculo
--   speakers[].sessions[]                       — as sessões da pessoa, com
--                                                 hora local, local e papel
--   sessions_total (topo)                       — quantas sessões atendem à
--                                                 pergunta ANTES do limite
--
-- BLOCOS NÃO TOCADOS
--   mind, exhibitors, offers, locations e event continuam com a mesma
--   seleção de hoje, contra a pergunta inteira (`q_or`/`piso_amplo`). Ofertas
--   e regra comercial são caminho do vendedor; nada aqui os altera.
-- ============================================================

create or replace function public.mindagent_chat_search(
  p_event_slug text,
  p_query text,
  p_limit integer default 8
)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'summit_2026', 'ecossistema', 'engagement', 'intelligence', 'mind'
as $function$
with
bruto as (
  select
    lower(btrim(left(p_query, 500))) as q,
    least(12, greatest(1, coalesce(p_limit, 8))) as lim,
    lower(translate(left(p_query, 500),
      'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
      'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc')) as qn
),
-- A pergunta em palavras: sem acento, pontuação virando separador e as bordas
-- explícitas. Casar nome próprio vira `like '% palavra %'` — palavra inteira,
-- sem regex e sem escapar nome de pessoa.
palavras as (
  select b.*, ' ' || regexp_replace(b.qn, '[^a-z0-9]+', ' ', 'g') || ' ' as qp
  from bruto b
),
lexemas as (
  select l.lexeme from unnest(to_tsvector('portuguese', left(p_query, 500))) l
),
-- ANDAIME DA PERGUNTA. Palavras que estruturam a pergunta em vez de dizer o
-- assunto dela: interrogativos, "programação", "sessão", "horário", "dia",
-- "manhã/tarde/noite", "sobre", "conteúdo". Aparecem em quase toda pergunta e
-- em quase nenhum registro — contá-las como assunto só inflava o piso.
-- Número nunca é assunto neste domínio: é dia ou hora, e tem filtro próprio.
foco_lex as (
  select lexeme from lexemas
  -- Número não é assunto neste domínio: é dia ("17") ou hora ("14h", "14:30"),
  -- e cada um tem filtro próprio abaixo.
  where lexeme !~ '^[0-9]+(h([0-9]{2})?)?$'
    and lexeme !~ '^[0-9]{1,2}:[0-9]{2}$'
    -- A lista abaixo NÃO foi escrita à mão: são os lexemas que o próprio
    -- to_tsvector('portuguese', ...) produz para as palavras de andaime, nas
    -- formas com e sem acento — "programação" vira `program` e "programacao"
    -- vira `programaca`, e as duas precisam estar aqui porque quem digita no
    -- chat escreve das duas maneiras.
    and lexeme <> all (array[
      'acontec','agend','ajud','algo','algum','amanh','amanhã','apresent','cois','comec',
      'conteud','conteúd','cronogram','dia','dias','duraca','duraçã','é','espac','esta',
      'event','fal','gost','grad','hav','hoj','hor','horari','horári','indic','inform',
      'informaca','informaco','lineup','list','loc','local','manh','manhã','mind','minut',
      'mostr','noit','onde','palestr','particip','pod','program','programaca','qua','quant',
      'quer','recomend','recomendaca','rol','sab','sal','sao','sei','ser','sessa','sessã',
      'sesso','sessõ','sobr','suger','sugesta','sugestã','summit','tard','ter','termin',
      'vai','ver'
    ])
),
params as (
  select b.q, b.qn, b.qp, b.lim,
    (select nullif(string_agg(lexeme, ' | '), '') from lexemas)::tsquery as q_or,
    (select nullif(string_agg(lexeme, ' | '), '') from foco_lex)::tsquery as q_foco,
    (select count(*) from foco_lex) as n_foco,
    -- piso do ASSUNTO (novo) e piso da pergunta inteira (o de hoje, preservado
    -- para os blocos que esta migration não mexe).
    0.1 * least(2, greatest(1, (select count(*) from foco_lex))) as piso,
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
-- ---------------------------------------------------------------- DIA
-- O dia sai da pergunta contra os dias que o evento REALMENTE tem. Nada de
-- data em constante.
--
-- NÚMERO SOLTO NÃO É DATA. "somos 17 pessoas" e "quero 17 ingressos" citam o
-- 17 sem falar do dia 17 — e o Treble, que consome este mesmo retrieval, vive
-- de perguntas com quantidade. Por isso o número só vira data quando a própria
-- pergunta diz que é data: a palavra `dia` governando o número, uma data
-- escrita (17/09, 17-9, 2026-09-17) ou o mês por extenso.
-- `16h` e `16:00` também não são dia: são hora, e têm filtro próprio.
meses_pt as (
  select array['janeiro','fevereiro','marco','abril','maio','junho',
               'julho','agosto','setembro','outubro','novembro','dezembro']::text[] as m
),
-- A REGIÃO DE DATA. Tudo que vem depois de `dia`/`dias` enquanto forem números
-- e conectores (espaço, vírgula, "e", barra, hífen). A primeira letra fora
-- desse conjunto encerra a região — e é isso que separa "dias 16 e 17", que
-- pede os dois dias, de "dia 16, somos 17 pessoas", onde o 17 já está fora da
-- região porque o `s` de "somos" a fechou.
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
    -- "dia 17", "no dia 17", "dias 16 e 17"
    rd.reg ~ ('(^|[^0-9])' || to_char(d.dia, 'FMDD') || '([^0-9]|$)')
    -- data escrita: 17/09, 17/9, 17-09
    or p.qn ~ ('(^|[^0-9])' || to_char(d.dia, 'FMDD') || '[/-]0?' || to_char(d.dia, 'FMMM') || '([^0-9]|$)')
    -- ISO
    or p.qn like '%' || to_char(d.dia, 'YYYY-MM-DD') || '%'
    -- "17 de setembro"
    or p.qn ~ ('(^|[^0-9])' || to_char(d.dia, 'FMDD') || '\s+de\s+' ||
               mp.m[extract(month from d.dia)::int])
),
-- ------------------------------------------------------------- HORÁRIO
-- Convenção de leitura da pergunta, não regra de negócio: manhã < 12h,
-- tarde 12h–18h, noite >= 18h, no fuso do próprio evento. Hora explícita
-- ("às 14h", "14:30") vale a hora cheia. As duas se combinam por interseção.
--
-- PERÍODO E HORA NÃO PERGUNTAM A MESMA COISA.
--   "o que tem à tarde"   = o que COMEÇA à tarde. Por sobreposição, a lista
--                           enche de sessões das 11:30 que só encostam nos
--                           primeiros minutos do período e empurram para fora
--                           a tarde de verdade.
--   "o que acontece às 14h" = o que ESTÁ ACONTECENDO às 14h, e aí a sessão que
--                           começou 13:30 e termina 15:00 é exatamente o que a
--                           pessoa quer saber.
-- Por isso hora explícita filtra por sobreposição; período, por início.
-- HORA COM MINUTO É INSTANTE, HORA CHEIA É HORA.
--   "às 14h"    = a hora das 14. Sessão que roda dentro dela conta.
--   "às 14:30"  = aquele instante. Uma sessão que terminou 14:10 ou que só
--                 começa 14:50 não está acontecendo às 14:30, e devolvê-la
--                 seria responder outra pergunta.
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
-- ---------------------------------------------------------- PALESTRANTES
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
-- NOME PRÓPRIO IDENTIFICA A PESSOA. Nome inteiro na pergunta vale 1.0;
-- qualquer token do nome com 4+ letras, como palavra inteira, vale 0.5 —
-- é assim que "Sonja", "Maslach" e "Amy" acham a pessoa certa. Token curto
-- fica de fora para não transformar preposição em identidade. Homônimo de
-- primeiro nome devolve as duas pessoas, e isso é honesto: o dado não diz
-- qual delas a pergunta quis.
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
-- -------------------------------------------------------------- SESSÕES
sessao_base as (
  select s.id, s.titulo, s.descricao, s.dia, s.inicio, s.fim, s.tipo,
         s.precisa_reserva, s.lugares_limitados, s.reserva_recomendada,
         s.vagas_disponiveis, s.espaco_id,
         to_tsvector('portuguese',
           coalesce(s.titulo, '') || ' ' || coalesce(s.descricao, '') || ' ' ||
           array_to_string(coalesce(s.trilhas, '{}'::text[]), ' ') || ' ' ||
           coalesce(s.tipo, '') || ' ' ||
           -- O stemmer português não liga "workshops" a "workshop": tipo
           -- estrangeiro fica fora da flexão. O plural entra indexado.
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
  left join summit_2026.locations l on l.id = sb.espaco_id
  where (
      -- casou com o assunto da pergunta
      (p.q_foco is not null and ts_rank_cd(sb.tsv, p.q_foco) >= p.piso)
      -- ou é sessão de alguém que a pergunta nomeou
      or exists (select 1 from summit_2026.session_speakers ss
                 join pessoa_nomeada pn on pn.id = ss.speaker_id
                 where ss.sessao_id = sb.id)
      -- ou a pergunta pede a agenda e não tem assunto próprio
      or ((p.listar or dp.dias is not null or fx.modo is not null) and p.n_foco = 0)
    )
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
    -- NÃO SAI UTC DAQUI. `s.inicio` é timestamptz e serializava como
    -- `...T22:00:00+00:00`: a sessão das 19:00 em São Paulo chegava ao modelo
    -- como 22:00, e a instrução do concierge pede "HH:MM–HH:MM". Não bastava
    -- acrescentar um campo local — nada dizia ao modelo qual dos dois vence, e
    -- o bloco de agenda do Treble nem recebe o `official_note`. Então o UTC
    -- deixa de existir na saída: `starts_at`/`ends_at` saem no fuso do evento,
    -- sem offset, e concordam com `*_local`. `timezone` acompanha cada sessão
    -- para o item se explicar sozinho mesmo depois de filtrado.
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
      or (p.listar_pessoas and p.n_foco = 0)
    )
    -- Quem a pergunta recortou por dia/faixa só entra se realmente fala nesse
    -- recorte. Mesmo predicado do bloco de sessões, para os dois não
    -- discordarem dentro da mesma resposta.
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
-- A pessoa vem com as sessões dela. "Que horas fala a Amy" e "onde é a sessão
-- da Sonja" passam a ter resposta determinística num bloco só, em vez de
-- depender de o modelo cruzar dois blocos por conta própria.
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
        -- MESMO RECORTE DO BLOCO DE SESSÕES. Sem isto, "Amy no dia 17" traz as
        -- sessões do dia 16 dela dentro do bloco da pessoa, e o modelo lê duas
        -- verdades diferentes sobre a mesma pergunta na mesma resposta.
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
-- ------------------------------ BLOCOS PRESERVADOS (seleção idêntica à de hoje)
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
  -- Quantas sessões atendem à pergunta ANTES do limite. Sem isso, uma lista
  -- truncada de 8 entre 24 é lida como se fosse a programação inteira — e a
  -- omissão vira erro factual.
  'sessions_total', (select count(*) from session_ranked),
  'speakers', (select items from speaker_items),
  'mind', (select items from mind_items),
  'exhibitors', (select items from exhibitor_items),
  'offers', (select items from offer_items),
  'official_note', 'Use somente estes dados oficiais. Se algo não estiver presente, informe que ainda não está disponível. Horário apresentado à pessoa é sempre starts_at_local/ends_at_local, no fuso indicado em timezone; nenhum horário desta resposta está em UTC.'
);
$function$;

comment on function public.mindagent_chat_search(text, text, integer) is
  'Retrieval estruturado do Summit para o concierge (mindagent-web) e para o bloco de agenda do WhatsApp. Piso de relevância sobre os lexemas de ASSUNTO da pergunta; nome próprio (inteiro ou token de 4+ letras) identifica a pessoa e traz as sessões dela; dia e faixa de horário saem da própria pergunta contra os dias reais do evento; listagem da agenda só quando a pergunta não tem assunto próprio.';
