-- Contrato observavel da memoria em camadas do Concierge.
-- Somente leitura; termina em rollback.
-- Como rodar:
--   psql "$DATABASE_URL" -f tests/concierge_intelligence_unificada_contract.sql

begin;

do $test$
declare
  b jsonb;
  k jsonb;
begin
  b := public.mind_intelligence_buscar(
    'livros para autografos dos Legends disponibilidade Livraria da Vila', 10
  );
  if not (b->'candidatos' @> '[{"tipo":"regra_evento","id":"livros-autografos"}]'::jsonb) then
    raise exception 'a busca nao encontrou a regra de livros: %', b;
  end if;
  if not exists (
    select 1 from jsonb_array_elements(b->'candidatos') c
    where c->>'tipo' = 'aviso' and c->>'titulo' ilike '%livro%'
  ) then
    raise exception 'a busca nao encontrou o aviso de livros: %', b;
  end if;

  b := public.mind_intelligence_buscar('Rhino transporte cupom', 6);
  if not exists (
    select 1 from jsonb_array_elements(b->'candidatos') c
    where c->>'tipo' in ('regra_evento','aviso') and lower(c->>'titulo') like '%rhino%'
  ) then
    raise exception 'a busca nao encontrou Rhino: %', b;
  end if;

  b := public.mind_intelligence_buscar('Christina Maslach burnout', 6);
  if not exists (
    select 1 from jsonb_array_elements(b->'candidatos') c
    where c->>'tipo' = 'palestrante' and lower(c->>'titulo') like '%maslach%'
  ) then
    raise exception 'regressao na busca de palestrante: %', b;
  end if;

  b := public.mind_intelligence_buscar('Prime Lounge networking lideres executivos', 6);
  if not exists (
    select 1 from jsonb_array_elements(b->'candidatos') c
    where c->>'tipo' = 'conhecimento'
  ) then
    raise exception 'regressao na busca de Knowledge Document: %', b;
  end if;

  k := public.mind_intelligence_ler('regra_evento', 'livros-autografos', 1200);
  if k->>'texto' not ilike '%proprios exemplares%' then
    raise exception 'a leitura profunda da regra esta incompleta: %', k;
  end if;

  k := public.mind_kit_evento(null, '{"event_slug":"mind-summit-2026"}'::jsonb);
  if k->>'event_slug' <> 'mind-summit-2026' then
    raise exception 'o kit resolveu o evento errado: %', k;
  end if;
  if not (k->'regras_criticas' @> '[{"chave":"livros-autografos"}]'::jsonb) then
    raise exception 'o kit nao recebeu a regra critica de livros: %', k;
  end if;
  if not (k->'avisos_importantes' @> '[{"chave":"livros_autografos"}]'::jsonb) then
    raise exception 'o kit nao recebeu o aviso de livros: %', k;
  end if;

  if public.mind_kit_evento(null, '{"event_slug":"evento-inexistente"}'::jsonb) is not null then
    raise exception 'o kit fez fallback indevido para outro evento';
  end if;

  if has_function_privilege(
       'anon', 'public.mind_intelligence_buscar(text,integer)', 'execute'
     ) or has_function_privilege(
       'authenticated', 'public.mind_intelligence_buscar(text,integer)', 'execute'
     ) or has_function_privilege(
       'anon', 'public.mind_intelligence_ler(text,text,integer)', 'execute'
     ) or has_function_privilege(
       'authenticated', 'public.mind_intelligence_ler(text,text,integer)', 'execute'
     ) then
    raise exception 'as tools abriram execucao direta para cliente';
  end if;
end
$test$;

rollback;
