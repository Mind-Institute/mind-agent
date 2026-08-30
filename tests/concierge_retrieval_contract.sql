-- ============================================================================
-- CONTRATO DE public.mindagent_chat_search(text, text, integer) -> jsonb
--
-- Concierge Summit. Este arquivo é TESTE, não SQL de produção: não cria
-- extensão, schema, tabela, função, migration nem fixture. Ele só LÊ a
-- programação real e roda inteiro dentro de uma transação que termina em
-- ROLLBACK. Depois dele nada no banco muda.
--
-- Testa o CONTRATO OBSERVÁVEL do retrieval, não a implementação: quais chaves
-- saem, o que uma pergunta por pessoa devolve, o que um filtro de dia e faixa
-- devolve, e — o mais importante — que pergunta sem lastro na base devolve
-- VAZIO, e não a agenda inteira travestida de resposta.
--
-- As âncoras factuais são as três pessoas nomeadas na issue da lane
-- (Amy Edmondson, Christina Maslach, Sonja Lyubomirsky) e a semântica de
-- dia/período. Contagem absoluta de programação NÃO é assertada: ela muda
-- quando a curadoria muda, e o contrato não é a contagem.
--
-- Qualquer contrato quebrado aborta com uma exception que diz qual.
--
-- Como rodar:  psql "$DATABASE_URL" -f tests/concierge_retrieval_contract.sql
-- ============================================================================

begin;

do $$
declare
  v_slug   constant text := 'mind-summit-2026';
  v        jsonb;
  v_chaves text[];
  v_bloco  text;
  v_perg   text;
  v_pessoa text;
  v_titulo text;
  v_id     uuid;
  v_local  text;
  v_esperado_hora text;
  v_fuso   text;
  v_dia    date;
  v_n      int;
begin
  select e.fuso into v_fuso from summit_2026.events e where e.slug = v_slug and e.ativo;
  if v_fuso is null then
    raise exception 'PRÉ-CONDIÇÃO: evento % não existe ou não está ativo', v_slug;
  end if;

  -- ------------------------------------------------------------ CONTRATO 1
  -- As chaves do topo são as que os dois consumidores vivos leem.
  -- mindagent-chat exige `event` não-nulo e conta as seis listas;
  -- treble-inbound-agent filtra sessions/speakers/locations/exhibitors/mind.
  -- Perder qualquer uma delas quebra runtime que não é desta lane.
  v := public.mindagent_chat_search(v_slug, 'programação', 8);

  select array_agg(k order by k) into v_chaves from jsonb_object_keys(v) k;
  if v_chaves is distinct from array['event','exhibitors','locations','mind','offers',
                                     'official_note','sessions','sessions_total','speakers'] then
    raise exception 'CONTRATO 1: chaves do topo são %', v_chaves;
  end if;

  if jsonb_typeof(v->'event') <> 'object' then
    raise exception 'CONTRATO 1: `event` precisa ser objeto não-nulo, veio %', jsonb_typeof(v->'event');
  end if;

  foreach v_bloco in array array['sessions','speakers','mind','exhibitors','offers'] loop
    if jsonb_typeof(v->v_bloco) <> 'array' then
      raise exception 'CONTRATO 1: `%` precisa ser array, veio %', v_bloco, jsonb_typeof(v->v_bloco);
    end if;
  end loop;

  -- ------------------------------------------------------------ CONTRATO 2
  -- PERGUNTA SEM LASTRO NA BASE DEVOLVE VAZIO.
  -- É o contrato que impede invenção. A pergunta abaixo carrega a palavra
  -- "sessão" de propósito: era exatamente ela que fazia o gatilho de categoria
  -- despejar a agenda inteira como contexto oficial de uma pergunta sobre
  -- criptomoeda.
  v := public.mindagent_chat_search(v_slug, 'tem sessão sobre criptomoedas e blockchain?', 8);
  if jsonb_array_length(v->'sessions') <> 0 or (v->>'sessions_total')::int <> 0 then
    raise exception 'CONTRATO 2: pergunta sem lastro devolveu % sessões (total %)',
      jsonb_array_length(v->'sessions'), v->>'sessions_total';
  end if;
  if jsonb_array_length(v->'speakers') <> 0 then
    raise exception 'CONTRATO 2: pergunta sem lastro devolveu % palestrantes',
      jsonb_array_length(v->'speakers');
  end if;

  -- ------------------------------------------------------------ CONTRATO 3
  -- NOME PRÓPRIO IDENTIFICA A PESSOA — inteiro, só o primeiro nome ou só o
  -- sobrenome — e a pessoa vem com as sessões dela.
  for v_perg, v_pessoa in
    select * from (values
      ('que horas fala a Amy Edmondson?', 'Amy Edmondson'),
      ('Amy',                             'Amy Edmondson'),
      ('quem é Christina Maslach?',       'Christina Maslach'),
      ('quem é Maslach?',                 'Christina Maslach'),
      ('onde é a sessão da Sonja?',       'Sonja Lyubomirsky')
    ) t(pergunta, pessoa)
  loop
    v := public.mindagent_chat_search(v_slug, v_perg, 8);

    if not exists (select 1 from jsonb_array_elements(v->'speakers') s
                   where s->>'name' = v_pessoa) then
      raise exception 'CONTRATO 3: "%" não identificou %; veio %', v_perg, v_pessoa,
        coalesce((select string_agg(s->>'name', ', ') from jsonb_array_elements(v->'speakers') s), '[]');
    end if;

    select jsonb_array_length(s->'sessions') into v_n
      from jsonb_array_elements(v->'speakers') s where s->>'name' = v_pessoa;
    if coalesce(v_n, 0) = 0 then
      raise exception 'CONTRATO 3: % veio sem as sessões dela em "%"', v_pessoa, v_perg;
    end if;

    -- As sessões da pessoa nomeada entram no bloco de sessões: é de lá que
    -- saem "que horas" e "onde".
    if jsonb_array_length(v->'sessions') = 0 then
      raise exception 'CONTRATO 3: "%" não trouxe nenhuma sessão de %', v_perg, v_pessoa;
    end if;
    if exists (
      select 1 from jsonb_array_elements(v->'sessions') s
      where not exists (select 1 from jsonb_array_elements(s->'speakers') sp
                        where sp->>'name' = v_pessoa)
    ) then
      raise exception 'CONTRATO 3: "%" trouxe sessão que não é de %', v_perg, v_pessoa;
    end if;
  end loop;

  -- ------------------------------------------------------------ CONTRATO 4
  -- BUSCA TEMÁTICA ACHA O ACERTO LITERAL. Sessão com o tema NO TÍTULO não pode
  -- ficar de fora da pergunta sobre o tema — era o efeito de contar "conteúdos"
  -- e "sobre" como se fossem assunto.
  v := public.mindagent_chat_search(v_slug, 'conteúdos sobre burnout', 12);
  for v_titulo in
    select s.titulo from summit_2026.sessions s
    join summit_2026.events e on e.id = s.event_id and e.slug = v_slug
    where s.titulo ilike '%burnout%'
  loop
    if not exists (select 1 from jsonb_array_elements(v->'sessions') x
                   where x->>'title' = v_titulo) then
      raise exception 'CONTRATO 4: "%" tem burnout no título e não saiu na busca por burnout', v_titulo;
    end if;
  end loop;

  -- ------------------------------------------------------------ CONTRATO 5
  -- DIA E PERÍODO SÃO FILTRO, NÃO DECORAÇÃO. Período pergunta o que COMEÇA na
  -- faixa; hora explícita pergunta o que ESTÁ ACONTECENDO na hora.
  select max(s.dia) into v_dia from summit_2026.sessions s
    join summit_2026.events e on e.id = s.event_id and e.slug = v_slug;

  v := public.mindagent_chat_search(
         v_slug, format('o que tem na programação do dia %s à tarde?', to_char(v_dia, 'FMDD')), 8);

  if jsonb_array_length(v->'sessions') = 0 then
    raise exception 'CONTRATO 5: dia % à tarde não devolveu nada', v_dia;
  end if;
  if exists (select 1 from jsonb_array_elements(v->'sessions') x
             where (x->>'date')::date <> v_dia) then
    raise exception 'CONTRATO 5: dia % à tarde devolveu sessão de outro dia', v_dia;
  end if;
  if exists (select 1 from jsonb_array_elements(v->'sessions') x
             where (x->>'starts_at_local')::time <  time '12:00'
                or (x->>'starts_at_local')::time >= time '18:00') then
    raise exception 'CONTRATO 5: "à tarde" devolveu sessão que começa fora de 12:00-18:00';
  end if;

  -- A lista é truncada pelo limite, e o total precisa dizer isso — senão o
  -- agente lê 8 de 24 como se fosse a programação inteira.
  if (v->>'sessions_total')::int < jsonb_array_length(v->'sessions') then
    raise exception 'CONTRATO 5: sessions_total (%) menor que a lista devolvida (%)',
      v->>'sessions_total', jsonb_array_length(v->'sessions');
  end if;

  -- ------------------------------------------------------------ CONTRATO 6
  -- HORA LOCAL. `starts_at` é timestamptz e chega ao modelo em UTC; a hora que
  -- a pessoa vai ler é `starts_at_local`, no fuso do próprio evento.
  v := public.mindagent_chat_search(v_slug, 'me mostra a programação', 8);
  if jsonb_array_length(v->'sessions') = 0 then
    raise exception 'CONTRATO 6: "me mostra a programação" não devolveu nada';
  end if;
  for v_id, v_local in
    select (x->>'id')::uuid, x->>'starts_at_local' from jsonb_array_elements(v->'sessions') x
  loop
    select to_char(s.inicio at time zone v_fuso, 'HH24:MI') into v_esperado_hora
      from summit_2026.sessions s where s.id = v_id;
    if v_local is distinct from v_esperado_hora then
      raise exception 'CONTRATO 6: starts_at_local da sessão % veio %, esperado % (fuso %)',
        v_id, v_local, v_esperado_hora, v_fuso;
    end if;
  end loop;

  -- ------------------------------------------------------------ CONTRATO 7
  -- SESSÃO COM MAIS DE UM PALESTRANTE ENTREGA TODOS, com o papel de cada um.
  -- O vínculo é o canônico speaker_id; `palestrante_id` legado não participa.
  select s.titulo, count(*) into v_titulo, v_n
  from summit_2026.sessions s
  join summit_2026.events e on e.id = s.event_id and e.slug = v_slug
  join summit_2026.session_speakers ss on ss.sessao_id = s.id
  group by s.id, s.titulo
  having count(*) > 1
  order by count(*) desc, s.titulo limit 1;

  if v_titulo is not null then
    v := public.mindagent_chat_search(v_slug, v_titulo, 8);

    if coalesce((select jsonb_array_length(x->'speakers')
                 from jsonb_array_elements(v->'sessions') x
                 where x->>'title' = v_titulo), 0) <> v_n then
      raise exception 'CONTRATO 7: "%" tem % vínculos e o retrieval devolveu %', v_titulo, v_n,
        coalesce((select jsonb_array_length(x->'speakers')
                  from jsonb_array_elements(v->'sessions') x
                  where x->>'title' = v_titulo), 0);
    end if;

    if exists (
      select 1 from jsonb_array_elements(v->'sessions') x,
                    jsonb_array_elements(x->'speakers') sp
      where x->>'title' = v_titulo
        and (sp->>'name' is null or sp->>'participation' is null)
    ) then
      raise exception 'CONTRATO 7: palestrante de "%" veio sem nome ou sem papel', v_titulo;
    end if;
  end if;

  raise notice 'mindagent_chat_search: 7 contratos OK';
end $$;

rollback;
