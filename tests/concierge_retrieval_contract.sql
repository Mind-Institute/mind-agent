-- ============================================================================
-- CONTRATO DE public.mindagent_chat_search(text, text, integer) -> jsonb
--
-- Concierge Summit. Este arquivo é TESTE, não SQL de produção: não cria
-- extensão, schema, tabela, função, migration nem fixture. Ele só LÊ a
-- programação real e roda inteiro dentro de uma transação que termina em
-- ROLLBACK. Depois dele nada no banco muda.
--
-- Testa o CONTRATO OBSERVÁVEL do retrieval e do Kit da rota, não a
-- implementação: quais chaves
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
  v_dia1   date;
  v_n      int;
  v_m      int;
  v_conv   uuid;
  v_a      jsonb;
  v_b      jsonb;
  v_dd1    text;
  v_dd2    text;
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

  -- ------------------------------------------------------------ CONTRATO 8
  -- NÚMERO SOLTO NÃO É DATA. O mesmo retrieval serve o bloco de agenda do
  -- Treble, onde "somos 17 pessoas" e "quero 17 ingressos" são o dia a dia.
  -- Tratar o 17 como dia 17 devolveria a programação de um dia inteiro para
  -- uma pergunta sobre tamanho de grupo.
  select min(s.dia), max(s.dia) into v_dia1, v_dia
  from summit_2026.sessions s
  join summit_2026.events e on e.id = s.event_id and e.slug = v_slug;

  for v_perg in
    select * from (values
      (format('somos %s pessoas, o que vocês recomendam?', to_char(v_dia, 'FMDD'))),
      (format('quero %s ingressos', to_char(v_dia, 'FMDD'))),
      (format('%s pessoas do meu time vão', to_char(v_dia1, 'FMDD')))
    ) t(pergunta)
  loop
    v := public.mindagent_chat_search(v_slug, v_perg, 8);
    if exists (
      select 1 from jsonb_array_elements(v->'sessions') x
      group by 1 = 1
      having count(*) > 0 and count(distinct (x->>'date')) = 1
    ) and (v->>'sessions_total')::int > 12 then
      raise exception 'CONTRATO 8: "%" foi lido como filtro de dia (% sessões de um único dia)',
        v_perg, v->>'sessions_total';
    end if;
  end loop;

  -- E a forma inequívoca continua filtrando.
  v := public.mindagent_chat_search(
         v_slug, format('programação do dia %s', to_char(v_dia, 'FMDD')), 8);
  if jsonb_array_length(v->'sessions') = 0
     or exists (select 1 from jsonb_array_elements(v->'sessions') x
                where (x->>'date')::date <> v_dia) then
    raise exception 'CONTRATO 8: "dia %" deixou de filtrar o dia', v_dia;
  end if;

  -- ------------------------------------------------------------ CONTRATO 9
  -- O RECORTE DA PERGUNTA VALE NOS DOIS BLOCOS. Sem isto, "Amy no dia 17" traz
  -- as sessões do dia 16 dela dentro do bloco da pessoa, e a mesma resposta
  -- carrega duas verdades sobre a mesma pergunta.
  v := public.mindagent_chat_search(
         v_slug, format('que horas fala a Amy Edmondson no dia %s?', to_char(v_dia, 'FMDD')), 8);
  if exists (
    select 1 from jsonb_array_elements(v->'speakers') s,
                  jsonb_array_elements(s->'sessions') ss
    where (ss->>'date')::date <> v_dia
  ) then
    raise exception 'CONTRATO 9: speakers[].sessions trouxe sessão fora do dia %', v_dia;
  end if;

  -- ----------------------------------------------------------- CONTRATO 10
  -- NENHUM HORÁRIO EM UTC. `starts_at` e `starts_at_local` têm de concordar:
  -- é o que impede o modelo de escrever 22:00 para uma sessão das 19:00.
  v := public.mindagent_chat_search(v_slug, 'me mostra a programação', 12);
  if exists (
    select 1 from jsonb_array_elements(v->'sessions') x
    where substring(x->>'starts_at' from 12 for 5) is distinct from x->>'starts_at_local'
       or substring(x->>'ends_at'   from 12 for 5) is distinct from x->>'ends_at_local'
       or x->>'starts_at' like '%+00:00'
       or x->>'timezone' is null
  ) then
    raise exception 'CONTRATO 10: sessão com horário em UTC ou divergente do local';
  end if;

  -- ----------------------------------------------------------- CONTRATO 11
  -- O GATE ABRE PARA A ROTA. Playbook na casa canônica e Kit disponível.
  v := public.mind_rota_capacidade('concierge_summit', 'mindagent-web');
  if coalesce((v->>'pode_executar')::boolean, false) is not true then
    raise exception 'CONTRATO 11: Gate segue fechado para concierge_summit/mindagent-web: %', v;
  end if;

  v := public.mind_kit_meta('concierge_summit');
  if coalesce((v->>'kit_disponivel')::boolean, false) is not true then
    raise exception 'CONTRATO 11: kit de concierge_summit indisponível: %', v;
  end if;

  -- ----------------------------------------------------------- CONTRATO 12
  -- O KIT ENTREGA PLAYBOOK E PROGRAMAÇÃO PELA NECESSIDADE ATUAL.
  select c.id into v_conv from engagement.conversas c limit 1;
  if v_conv is not null then
    v := public.mind_agent_kit('concierge_summit', v_conv,
           jsonb_build_object('pergunta', 'que horas fala a Amy Edmondson?'));

    if coalesce(length(v->>'playbook'), 0) = 0 then
      raise exception 'CONTRATO 12: kit veio sem playbook';
    end if;
    if v->'structured'->'programacao' is null or v->'structured'->'evento' is null then
      raise exception 'CONTRATO 12: kit veio sem os blocos evento/programacao: %',
        (select string_agg(k, ', ') from jsonb_object_keys(v->'structured') k);
    end if;
    if jsonb_array_length(v->'structured'->'programacao'->'sessions') = 0 then
      raise exception 'CONTRATO 12: bloco programacao não respondeu a necessidade atual';
    end if;

    -- --------------------------------------------------------- CONTRATO 13
    -- MEMÓRIA NÃO ENTRA NA NECESSIDADE ATUAL. Interesse só reordena: o
    -- CONJUNTO devolvido tem de ser idêntico com e sem interesse.
    v_a := public.mind_agent_kit('concierge_summit', v_conv,
             jsonb_build_object('pergunta', 'o que tem na programação do dia 17 à tarde?'));
    v_b := public.mind_agent_kit('concierge_summit', v_conv,
             jsonb_build_object('pergunta', 'o que tem na programação do dia 17 à tarde?',
                                'interesses', jsonb_build_array('Liderança', 'Saúde mental')));

    if (v_a->'structured'->'programacao'->>'sessions_total')
       is distinct from (v_b->'structured'->'programacao'->>'sessions_total') then
      raise exception 'CONTRATO 13: interesse mudou o total de sessões (% vs %)',
        v_a->'structured'->'programacao'->>'sessions_total',
        v_b->'structured'->'programacao'->>'sessions_total';
    end if;

    if (select count(*) from (
          select x->>'id' from jsonb_array_elements(v_a->'structured'->'programacao'->'sessions') x
          except
          select x->>'id' from jsonb_array_elements(v_b->'structured'->'programacao'->'sessions') x
          union all
          select x->>'id' from jsonb_array_elements(v_b->'structured'->'programacao'->'sessions') x
          except
          select x->>'id' from jsonb_array_elements(v_a->'structured'->'programacao'->'sessions') x
        ) d) <> 0 then
      raise exception 'CONTRATO 13: interesse mudou a SELEÇÃO de sessões, não só a ordem';
    end if;

    if jsonb_array_length(v_a->'structured'->'programacao'->'sessions') = 0 then
      raise exception 'CONTRATO 13: pergunta de agenda com dia/faixa devolveu vazio';
    end if;

    -- E pergunta sem lastro continua vazia mesmo com interesse anexado.
    v_b := public.mind_agent_kit('concierge_summit', v_conv,
             jsonb_build_object('pergunta', 'tem sessão sobre criptomoedas e blockchain?',
                                'interesses', jsonb_build_array('Liderança', 'Saúde mental')));
    if jsonb_array_length(v_b->'structured'->'programacao'->'sessions') <> 0 then
      raise exception 'CONTRATO 13: interesse fabricou sessão para pergunta sem lastro';
    end if;
  end if;

  -- ----------------------------------------------------------- CONTRATO 14
  -- DIA MÚLTIPLO SEM CONFUNDIR COM QUANTIDADE. A região de data começa em
  -- `dia`/`dias` e termina na primeira letra que não é conector: é isso que
  -- separa "dias 16 e 17" (dois dias) de "dia 16, somos 17 pessoas" (um dia,
  -- porque o `s` de "somos" fechou a região antes do 17).
  select to_char(min(s.dia), 'FMDD'), to_char(max(s.dia), 'FMDD') into v_dd1, v_dd2
  from summit_2026.sessions s
  join summit_2026.events e on e.id = s.event_id and e.slug = v_slug;

  -- A asserção é sobre o FILTRO, não sobre a página. A lista sai em ordem
  -- cronológica e o limite corta antes de virar o dia: os dois dias entram no
  -- escopo, e é `sessions_total` que diz isso — a página mostrar só o primeiro
  -- dia é truncamento honesto, não filtro perdido.
  select count(*) into v_n from summit_2026.sessions s
  join summit_2026.events e on e.id = s.event_id and e.slug = v_slug
  where to_char(s.dia, 'FMDD') in (v_dd1, v_dd2);

  v := public.mindagent_chat_search(
         v_slug, format('programação dos dias %s e %s', v_dd1, v_dd2), 12);
  if (v->>'sessions_total')::int <> v_n then
    raise exception 'CONTRATO 14: "dias % e %" alcançou % sessões, esperado % (os dois dias)',
      v_dd1, v_dd2, v->>'sessions_total', v_n;
  end if;
  if exists (select 1 from jsonb_array_elements(v->'sessions') x
             where to_char((x->>'date')::date, 'FMDD') not in (v_dd1, v_dd2)) then
    raise exception 'CONTRATO 14: "dias % e %" devolveu sessão de um terceiro dia', v_dd1, v_dd2;
  end if;

  -- E um dia só continua sendo um dia só.
  v := public.mindagent_chat_search(v_slug, format('programação do dia %s', v_dd2), 12);
  if (v->>'sessions_total')::int >= v_n then
    raise exception 'CONTRATO 14: "dia %" alcançou % sessões — não separou do pedido de dois dias',
      v_dd2, v->>'sessions_total';
  end if;

  v := public.mindagent_chat_search(
         v_slug, format('dia %s, somos %s pessoas', v_dd1, v_dd2), 12);
  if exists (select 1 from jsonb_array_elements(v->'sessions') x
             where to_char((x->>'date')::date, 'FMDD') <> v_dd1) then
    raise exception 'CONTRATO 14: "dia %, somos % pessoas" vazou para outro dia', v_dd1, v_dd2;
  end if;
  if jsonb_array_length(v->'sessions') = 0 then
    raise exception 'CONTRATO 14: "dia %, somos % pessoas" perdeu o filtro do dia %', v_dd1, v_dd2, v_dd1;
  end if;

  -- ----------------------------------------------------------- CONTRATO 15
  -- HORA COM MINUTO É INSTANTE. Uma sessão que terminou 14:10, ou que só
  -- começa 14:50, não está acontecendo às 14:30.
  v := public.mindagent_chat_search(v_slug, 'o que está acontecendo às 14:30?', 12);
  if exists (
    select 1 from jsonb_array_elements(v->'sessions') x
    where (x->>'starts_at_local')::time >  time '14:30'
       or (x->>'ends_at_local')::time   <= time '14:30'
  ) then
    raise exception 'CONTRATO 15: "14:30" devolveu sessão que não está acontecendo no instante';
  end if;

  -- E o instante é subconjunto da hora cheia: quem responde 14:30 responde 14h.
  v_a := public.mindagent_chat_search(v_slug, 'o que está acontecendo às 14:30?', 12);
  v_b := public.mindagent_chat_search(v_slug, 'o que está acontecendo às 14h?', 12);
  if exists (
    select 1 from jsonb_array_elements(v_a->'sessions') x
    where not exists (select 1 from jsonb_array_elements(v_b->'sessions') y
                      where y->>'id' = x->>'id')
  ) then
    raise exception 'CONTRATO 15: 14:30 devolveu sessão que 14h não devolve';
  end if;

  -- ----------------------------------------------------------- CONTRATO 16
  -- `event_slug` RESOLVE O ESCOPO, E SLUG DESCONHECIDO FALHA FECHADO.
  -- O provider não pode escolher "o primeiro evento ativo": hoje há um só, e
  -- isso faria o teste passar por coincidência.
  if v_conv is not null then
    v := public.mind_agent_kit('concierge_summit', v_conv,
           jsonb_build_object('pergunta', 'me mostra a programação', 'event_slug', v_slug));
    if v->'structured'->'programacao'->>'event_slug' is distinct from v_slug then
      raise exception 'CONTRATO 16: bloco resolveu o evento % em vez de %',
        v->'structured'->'programacao'->>'event_slug', v_slug;
    end if;

    v := public.mind_agent_kit('concierge_summit', v_conv,
           jsonb_build_object('pergunta', 'me mostra a programação',
                              'event_slug', 'evento-que-nao-existe'));
    if v->'structured' ? 'programacao' then
      raise exception 'CONTRATO 16: slug inexistente devolveu bloco programacao em vez de indisponivel';
    end if;

    -- ---------------------------------------------------------- CONTRATO 17
    -- FAIL-CLOSED DO EXECUTOR. É exatamente o que a Edge tem de exigir antes
    -- de chamar o modelo: kit sem erro, kit disponível, playbook não-vazio e
    -- os dois blocos presentes. Com slug inexistente, `programacao` some — e
    -- é essa ausência que impede a resposta.
    v_a := public.mind_agent_kit('concierge_summit', v_conv,
             jsonb_build_object('pergunta', 'me mostra a programação', 'event_slug', v_slug));
    if (v_a ? 'ok' and (v_a->>'ok')::boolean is false)
       or coalesce((v_a->'meta'->>'kit_disponivel')::boolean, false) is not true
       or coalesce(length(v_a->>'playbook'), 0) = 0
       or v_a->'structured'->'evento' is null
       or v_a->'structured'->'programacao' is null then
      raise exception 'CONTRATO 17: kit valido reprovou no fail-closed do executor';
    end if;

    v_b := public.mind_agent_kit('rota_que_nao_existe', v_conv, '{}'::jsonb);
    if (v_b->>'ok')::boolean is not false or v_b->>'motivo' <> 'rota_invalida' then
      raise exception 'CONTRATO 17: rota invalida nao devolveu rota_invalida: %', v_b;
    end if;
    v_b := public.mind_agent_kit('concierge_summit', null, '{}'::jsonb);
    if (v_b->>'ok')::boolean is not false or v_b->>'motivo' <> 'sem_conversa' then
      raise exception 'CONTRATO 17: conversa nula nao devolveu sem_conversa: %', v_b;
    end if;
  end if;

  raise notice 'concierge_summit: 17 contratos OK';
end $$;

rollback;
