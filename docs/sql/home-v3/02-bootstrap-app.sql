-- ============================================================
-- 02 · api.mindagent_bootstrap — reparo + `avisos` + `home`
-- ============================================================
-- Projeto: mind-agent (ymnmotgglsrxmjmonwjz)
-- Depende de: 01 (avisos), 04 (visualização) e 05 (temas) aplicados.
--
-- Este arquivo faz TRÊS coisas ao mesmo tempo, e é preciso saber disso
-- antes de rodar:
--
--   1. CONSERTA a função. Ela responde 503 desde 24/08 porque lê de
--      `summit.*` e `comum.*`, schemas renomeados naquele dia. O app
--      vive de `dados/summit.json` desde então.
--   2. Acrescenta `avisos` — o que o painel dispara.
--   3. Acrescenta `home` — qual das quatro composições está no ar.
--
-- É um arquivo só porque é uma função só: dois arquivos dando
-- `create or replace` na mesma função é o segundo apagando o primeiro.
--
-- ============================================================
-- O QUE MUDA PARA O PARTICIPANTE
-- ============================================================
-- O app troca o arquivo local pela grade viva. Não é a mesma coisa:
--
--   arquivo local          grade viva
--   53 sessões             77 (inclui credenciamento, intervalo, almoço)
--   49 com tema            35, depois do 05
--   39 palestrantes        63
--   com foto               SEM FOTO
--   com destaque           SEM DESTAQUE
--
-- Foto e destaque não existem em `ecossistema.palestrantes_especialistas`
-- e não foram inventados aqui: `foto` vai nula e `destaque` vai `false`.
-- O app precisa saber desenhar palestrante sem retrato — `cardPessoa()`
-- já foi ajustado para isso.
--
-- Os temas do palestrante passam a ser DERIVADOS das sessões em que ele
-- fala, que é a única fonte que sobrou. Muda o significado: antes era
-- "sobre o que essa pessoa trabalha", agora é "sobre o que ela fala
-- neste evento". Para recomendar dentro do Summit, serve melhor.
--
-- Sessão sem tema não é recomendada — `afinidade()` devolve null e ela
-- fica de fora. Por isso o 05 vem antes: sem ele, 0 de 59 sessões de
-- conteúdo teriam tema, e o Concierge ficaria mudo.
--
-- ============================================================
-- REGRAS APLICADAS NA LEITURA (sem cron, sem job)
-- ============================================================
-- AVISOS   `no-ar` está na rua agora; `agendado` entra sozinho quando
--          `disparo_em` chega; `rascunho` e `encerrado` não saem.
-- HOME     em `modo = 'programado'`, vale a última troca cujo horário já
--          passou.
-- O app aplica as mesmas regras em `home/estado.js`, para a origem local
-- se comportar igual à do banco.

create or replace function api.mindagent_bootstrap(p_event_slug text default 'mind-summit-2026'::text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'pg_catalog', 'summit_2026', 'ecossistema', 'concierge', 'engagement', 'intelligence', 'mind'
as $function$
with ev as (
  select e.* from summit_2026.events e where e.slug = p_event_slug and e.ativo limit 1
),
-- Configuração da home: uma linha em `concierge.config`, chave `home`.
cfg as (
  select coalesce(c.valor, '{}'::jsonb) as v from concierge.config c where c.chave = 'home'
),
-- Os temas da grade. Não há mais tabela de taxonomia — ela morava em
-- `comum`, que deixou de existir. Os códigos saem das próprias sessões;
-- os rótulos são os que o app já mostrava, preservados aqui para o
-- participante não ver o nome mudar.
temas_da_grade as (
  select t.codigo,
    case t.codigo
      when 'seguranca_psicologica' then 'Segurança psicológica'
      when 'dados_bem_estar'       then 'Dados e ROI do bem-estar'
      when 'regulacao'             then 'NR-1 e riscos psicossociais'
      when 'lideranca_humana'      then 'Liderança'
      when 'cultura'               then 'Cultura organizacional'
      when 'saude_mental'          then 'Saúde mental'
      when 'performance'           then 'Performance sustentável'
      when 'diversidade'           then 'Diversidade e inclusão'
      when 'felicidade'            then 'Felicidade e propósito'
      when 'futuro_trabalho'       then 'Futuro do trabalho'
      else initcap(replace(t.codigo, '_', ' '))
    end as rotulo
  from (
    select distinct jsonb_array_elements_text(coalesce(s.topicos_aprendizado, '[]'::jsonb)) as codigo
    from summit_2026.sessions s join ev e on e.id = s.event_id
  ) t
)
select jsonb_build_object(
  '_meta', jsonb_build_object(
    'schema_version', '1.0',
    'event_slug', p_event_slug,
    'generated_at', now()
  ),
  '_nota', 'Dados oficiais do Supabase. Informações ausentes não devem ser inventadas.',
  'evento', (select jsonb_build_object(
    'nome', e.nome,
    'dias', e.dias,
    'local', e.local,
    'regra_reserva', (select r.texto from summit_2026.event_rules r
                       where r.ativo and r.chave = 'reserva_expira'
                         and (r.event_id is null or r.event_id = e.id)
                       order by r.event_id nulls last limit 1),
    'regra_vagas', (select r.texto from summit_2026.event_rules r
                      where r.ativo and r.chave = 'vagas_limitadas'
                        and (r.event_id is null or r.event_id = e.id)
                      order by r.event_id nulls last limit 1)
  ) from ev e),
  'temas', coalesce((
    select jsonb_agg(jsonb_build_object('codigo', codigo, 'rotulo', rotulo) order by rotulo)
    from temas_da_grade
  ), '[]'::jsonb),
  'sessoes', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', coalesce(s.yazo_id, s.id::text),
      'dia', s.dia,
      'inicio', to_char(s.inicio at time zone e.fuso, 'HH24:MI'),
      'fim', to_char(s.fim at time zone e.fuso, 'HH24:MI'),
      'titulo', s.titulo,
      'descricao', coalesce(s.descricao, ''),
      'quem', coalesce((
        select string_agg(sp.nome, '; ' order by sp.nome)
        from summit_2026.session_speakers ss
        join ecossistema.palestrantes_especialistas sp on sp.id = ss.speaker_id
        where ss.sessao_id = s.id
      ), 'Em breve'),
      'espaco', l.nome,
      'formato', coalesce(s.tipo, s.formato, 'sessao'),
      -- A etiqueta vinha da taxonomia. Sem ela, sai do próprio tipo:
      -- "masterclass" vira "Masterclass", "em-curadoria" vira "Em
      -- Curadoria". Perde-se o "Prime" e o "VIP" que a taxonomia trazia.
      'etiqueta', initcap(replace(coalesce(s.tipo, s.formato, 'sessão'), '-', ' ')),
      'trilhas', coalesce(s.trilhas, '{}'::text[]),
      'vaga_limitada', coalesce(s.precisa_reserva, false),
      'online', lower(coalesce(s.formato, '')) in ('remoto', 'online', 'virtual'),
      'temas', coalesce(s.topicos_aprendizado, '[]'::jsonb)
    ) order by s.inicio, s.titulo)
    from summit_2026.sessions s
    join ev e on e.id = s.event_id
    left join summit_2026.locations l on l.id = s.espaco_id
  ), '[]'::jsonb),
  'pessoas', coalesce((
    select jsonb_agg(jsonb_build_object(
      'nome', sp.nome,
      'credencial', concat_ws(' · ', nullif(sp.cargo_curto, ''), nullif(sp.instituicao, '')),
      'resumo', coalesce(sp.quem_e, ''),
      -- Não existem mais na base. Vão explícitos para o app não ter de
      -- adivinhar a ausência.
      'foto', null::text,
      'destaque', false,
      'na_grade', true,
      -- Derivados das sessões em que a pessoa fala: é a fonte que
      -- sobrou, e é a que interessa para recomendar dentro do evento.
      'temas', coalesce((
        select jsonb_agg(distinct t)
        from summit_2026.session_speakers ss2
        join summit_2026.sessions sx2 on sx2.id = ss2.sessao_id
        join ev e2 on e2.id = sx2.event_id
        cross join lateral jsonb_array_elements_text(coalesce(sx2.topicos_aprendizado, '[]'::jsonb)) t
        where ss2.speaker_id = sp.id
      ), '[]'::jsonb)
    ) order by sp.nome)
    from ecossistema.palestrantes_especialistas sp
    where exists (
      select 1 from summit_2026.session_speakers ss
      join summit_2026.sessions sx on sx.id = ss.sessao_id
      join ev e on e.id = sx.event_id
      where ss.speaker_id = sp.id
    )
  ), '[]'::jsonb),
  -- Os avisos em circulação, mais recente em cima. A chave existir já
  -- diz ao app que o banco responde por avisos — lista vazia é resposta
  -- legítima, e o app respeita.
  'avisos', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', coalesce(a.chave, a.id::text),
      'icone', a.icone,
      'em', to_char(a.disparo_em at time zone coalesce((select fuso from ev), 'America/Sao_Paulo'),
                    'YYYY-MM-DD"T"HH24:MI'),
      'situacao', a.situacao,
      'titulo', a.titulo,
      'resumo', a.subtitulo,
      'mensagem', a.descricao,
      'verNoApp', a.ver_no_app,
      'botaoVerNoApp', a.botao_ver_no_app
    ) order by a.disparo_em desc nulls last)
    from concierge.avisos a
    where (a.situacao = 'no-ar' or (a.situacao = 'agendado' and a.disparo_em <= now()))
      and (a.event_id is null or a.event_id = (select id from ev))
  ), '[]'::jsonb),
  -- Qual das quatro composições da home está no ar.
  'home', coalesce((
    select jsonb_build_object(
      'momento', case
        when v->>'modo' = 'programado' then coalesce((
          select troca->>'momento'
          from jsonb_array_elements(coalesce(v->'trocas', '[]'::jsonb)) troca
          where coalesce((troca->>'arquivada')::boolean, false) is false
            and (replace(troca->>'quando', 'T', ' '))::timestamp
                at time zone coalesce((select fuso from ev), 'America/Sao_Paulo') <= now()
          order by troca->>'quando' desc
          limit 1
        ), v->>'momento', 'antes')
        else coalesce(v->>'momento', 'antes')
      end,
      'modo', coalesce(v->>'modo', 'manual')
    )
    from cfg
  ), jsonb_build_object('momento', 'antes', 'modo', 'manual'))
);
$function$;
