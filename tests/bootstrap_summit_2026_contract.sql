-- ============================================================================
-- CONTRATO DE api.mindagent_bootstrap(p_event_slug) -> jsonb, no schema vivo.
--
-- Este arquivo é TESTE, não SQL de produção. Só lê; roda dentro de uma transação
-- que termina em ROLLBACK e não deixa nada no banco.
--
-- Testa o CONTRATO OBSERVÁVEL que o App consome (data-service.js `conferir()` e
-- app.js): evento com dois dias e regras, dez temas da taxonomia, as sessões do
-- evento com temas em array e etiqueta, e pessoas com credencial, resumo e temas.
-- Também trava os invariantes das migrations de 03/09:
--   20260903070000_temas_do_summit_ganham_casa.sql
--   20260903071000_mindagent_bootstrap_no_schema_vivo.sql
--
-- Qualquer contrato quebrado aborta com uma exception que diz qual.
--
-- Como rodar:  psql "$DATABASE_URL" -f tests/bootstrap_summit_2026_contract.sql
-- ============================================================================

begin;

do $c1$
declare
  j jsonb := api.mindagent_bootstrap('mind-summit-2026');
  n int; txt text;
  n_sessoes_banco int;
begin
  -- 1. A forma que `conferir()` exige: evento.dias, temas, sessoes, pessoas.
  if j is null or j->'evento' is null then
    raise exception 'CONTRATO 1: bootstrap sem evento (o App mostraria "Não consegui carregar a programação")';
  end if;
  if jsonb_typeof(j->'evento'->'dias') <> 'array' or jsonb_array_length(j->'evento'->'dias') <> 2 then
    raise exception 'CONTRATO 1: evento.dias devia ter os dois dias do Summit, veio %', j->'evento'->'dias';
  end if;
  if coalesce(j->'evento'->>'regra_reserva','') = '' or coalesce(j->'evento'->>'regra_vagas','') = '' then
    raise exception 'CONTRATO 1: regra_reserva e regra_vagas vêm de summit_2026.event_rules e não podem faltar';
  end if;
  foreach txt in array array['temas','sessoes','pessoas'] loop
    if jsonb_typeof(j->txt) <> 'array' then
      raise exception 'CONTRATO 1: % devia ser array', txt;
    end if;
  end loop;

  -- 2. Temas: os dez da taxonomia, na ordem dela, com codigo e rotulo.
  select count(*) into n from ecossistema.taxonomy where tipo = 'tema' and ativo;
  if jsonb_array_length(j->'temas') <> n or n < 10 then
    raise exception 'CONTRATO 2: temas devia refletir a taxonomia ativa (% na taxonomia, % no bootstrap)', n, jsonb_array_length(j->'temas');
  end if;
  if exists (select 1 from jsonb_array_elements(j->'temas') t where coalesce(t->>'codigo','') = '' or coalesce(t->>'rotulo','') = '') then
    raise exception 'CONTRATO 2: todo tema precisa de codigo e rotulo';
  end if;

  -- 3. Sessões: todas as do evento, cada uma com id estável, etiqueta, formato do App e temas em array
  --    cujos códigos existem na taxonomia. Só sessão operacional pode ficar sem tema.
  select count(*) into n_sessoes_banco
  from summit_2026.sessions s join summit_2026.events e on e.id = s.event_id where e.slug = 'mind-summit-2026';
  if jsonb_array_length(j->'sessoes') <> n_sessoes_banco then
    raise exception 'CONTRATO 3: bootstrap devolve % sessões, o banco tem %', jsonb_array_length(j->'sessoes'), n_sessoes_banco;
  end if;
  select string_agg(s->>'id', ', ') into txt from jsonb_array_elements(j->'sessoes') s
  where coalesce(s->>'id','') = '' or coalesce(s->>'etiqueta','') = '' or coalesce(s->>'titulo','') = ''
     or s->>'formato' not in ('palestra','painel','masterclass','workshop','experiencia')
     or jsonb_typeof(s->'temas') <> 'array' or jsonb_typeof(s->'trilhas') <> 'array'
     or s->>'inicio' !~ '^\d\d:\d\d$';
  if txt is not null then raise exception 'CONTRATO 3: sessões fora do contrato: %', txt; end if;
  select string_agg(distinct t, ', ') into txt
  from jsonb_array_elements(j->'sessoes') s, jsonb_array_elements_text(s->'temas') t
  where not exists (select 1 from ecossistema.taxonomy x where x.tipo = 'tema' and x.codigo = t and x.ativo);
  if txt is not null then raise exception 'CONTRATO 3: temas de sessão fora da taxonomia: %', txt; end if;
  select string_agg(s->>'id', ', ') into txt from jsonb_array_elements(j->'sessoes') s
  where jsonb_array_length(s->'temas') = 0
    and s->>'tipo' not in ('credenciamento','abertura','intervalo','almoco','em-curadoria');
  if txt is not null then raise exception 'CONTRATO 3: sessão de conteúdo sem tema: %', txt; end if;
  -- Etiqueta carrega o ingresso como o site e o App já fazem.
  if not exists (select 1 from jsonb_array_elements(j->'sessoes') s where s->>'etiqueta' = 'Masterclass Prime')
     or not exists (select 1 from jsonb_array_elements(j->'sessoes') s where s->>'etiqueta' = 'Workshop VIP') then
    raise exception 'CONTRATO 3: etiquetas "Masterclass Prime" e "Workshop VIP" deviam existir';
  end if;

  -- 4. Pessoas: todo palestrante com sessão no evento, com credencial, resumo e temas; os
  --    quatro destaques curados vêm primeiro; foto só quando curada.
  select count(distinct ss.speaker_id) into n
  from summit_2026.session_speakers ss join summit_2026.sessions s on s.id = ss.sessao_id
  join summit_2026.events e on e.id = s.event_id where e.slug = 'mind-summit-2026';
  if jsonb_array_length(j->'pessoas') <> n then
    raise exception 'CONTRATO 4: bootstrap devolve % pessoas, o banco tem % palestrantes com sessão', jsonb_array_length(j->'pessoas'), n;
  end if;
  -- Sem perfil curado e sem cargo/instituição no banco, a credencial fica vazia de propósito:
  -- o App já rotula a pessoa como Palestrante. Resumo e temas nunca podem faltar.
  select string_agg(p->>'nome', ', ') into txt from jsonb_array_elements(j->'pessoas') p
  where coalesce(p->>'nome','') = '' or coalesce(p->>'resumo','') = ''
     or jsonb_typeof(p->'temas') <> 'array' or (p->>'na_grade')::boolean is not true;
  if txt is not null then raise exception 'CONTRATO 4: pessoas fora do contrato: %', txt; end if;
  select string_agg(p->>'nome', ', ') into txt from jsonb_array_elements(j->'pessoas') p
  where p->>'foto' is not null and coalesce(p->>'credencial','') = '';
  if txt is not null then raise exception 'CONTRATO 4: pessoa curada sem credencial: %', txt; end if;
  select count(*) into n from jsonb_array_elements(j->'pessoas') p where coalesce(p->>'credencial','') = '';
  if n > jsonb_array_length(j->'pessoas') - (select count(*) from summit_2026.speaker_profiles) then
    raise exception 'CONTRATO 4: mais pessoas sem credencial (%) do que pessoas sem perfil curado', n;
  end if;
  select count(*) into n from jsonb_array_elements(j->'pessoas') p where (p->>'destaque')::boolean;
  if n <> (select count(*) from summit_2026.speaker_profiles where destaque) then
    raise exception 'CONTRATO 4: destaques do bootstrap (%) diferem dos perfis curados', n;
  end if;
  if (j->'pessoas'->0->>'destaque')::boolean is not true then
    raise exception 'CONTRATO 4: destaques deviam vir primeiro';
  end if;
  if exists (select 1 from jsonb_array_elements(j->'pessoas') p where p->>'foto' is not null and p->>'foto' !~ '^palestrantes/[a-z0-9-]+\.webp$') then
    raise exception 'CONTRATO 4: foto fora do padrão palestrantes/<slug>.webp';
  end if;
end
$c1$;

-- 5. A porta continua aberta para a chave pública que a Edge usa.
do $c5$
declare n int;
begin
  set local role anon;
  select jsonb_array_length(api.mindagent_bootstrap('mind-summit-2026')->'sessoes') into n;
  reset role;
  if n is null or n = 0 then raise exception 'CONTRATO 5: anon devia conseguir ler as sessões pelo bootstrap'; end if;
end
$c5$;

select 'CONTRATOS 1 A 5 PASSARAM' as resultado;

rollback;
