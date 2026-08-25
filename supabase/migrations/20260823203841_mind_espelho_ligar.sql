-- Depois de gravar, amarrar o espelho na identidade canonica.
--
-- O espelho e do HubSpot; a pessoa e nossa. Esta funcao so liga -- nunca cria
-- pessoa, nunca sobrescreve. Quem cria pessoa e mind_identificar_pessoa, com as
-- duas buscas e a pergunta de desempate.
create or replace function public.mind_espelho_ligar()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'crm', 'catalogo'
as $function$
declare
  v_contatos int := 0;
  v_neg int := 0;
  v_hist int := 0;
  v_prod int := 0;
  v_tmp int := 0;
begin
  -- Contato -> pessoa: e-mail primeiro (chave forte no HubSpot, que deduplica por
  -- ele), WhatsApp depois. So preenche o que esta vazio.
  with casado as (
    select e.id as espelho_id, min(p.id::text)::uuid as pessoa_id
    from crm.contato_espelho e
    join crm.pessoas p on lower(p.email) = lower(nullif(e.email, ''))
    where e.pessoa_id is null and nullif(e.email, '') is not null
    group by e.id
    having count(distinct p.id) = 1
  )
  update crm.contato_espelho e set pessoa_id = c.pessoa_id, atualizado_em = now()
  from casado c where e.id = c.espelho_id;
  get diagnostics v_contatos = row_count;

  with casado as (
    select e.id as espelho_id, min(p.id::text)::uuid as pessoa_id
    from crm.contato_espelho e
    join crm.pessoas p
      on regexp_replace(coalesce(p.whatsapp, ''), '\D', '', 'g') =
         regexp_replace(coalesce(e.hs_whatsapp_phone_number, e.phone, ''), '\D', '', 'g')
    where e.pessoa_id is null
      and length(regexp_replace(coalesce(e.hs_whatsapp_phone_number, e.phone, ''), '\D', '', 'g')) >= 10
    group by e.id
    having count(distinct p.id) = 1
  )
  update crm.contato_espelho e set pessoa_id = c.pessoa_id, atualizado_em = now()
  from casado c where e.id = c.espelho_id;
  get diagnostics v_tmp = row_count;
  v_contatos := v_contatos + v_tmp;

  -- Negocio -> pessoa: pelo contato associado, que a Edge Function guarda em
  -- propriedades->'_contatos'. So amarra quando ha UM contato -- negocio com
  -- varios contatos nao tem dono obvio, e chutar aqui e pior que deixar nulo.
  with casado as (
    select n.id as neg_id, min(e.pessoa_id::text)::uuid as pessoa_id
    from crm.summit_em_andamento n
    join lateral jsonb_array_elements_text(coalesce(n.propriedades->'_contatos', '[]'::jsonb)) c(hid) on true
    join crm.contato_espelho e on e.hubspot_id = c.hid and e.pessoa_id is not null
    where n.pessoa_id is null
    group by n.id
    having count(distinct e.pessoa_id) = 1
  )
  update crm.summit_em_andamento n set pessoa_id = c.pessoa_id, atualizado_em = now()
  from casado c where n.id = c.neg_id;
  get diagnostics v_neg = row_count;

  with casado as (
    select n.id as neg_id, min(e.pessoa_id::text)::uuid as pessoa_id
    from crm.negocios_historicos n
    join lateral jsonb_array_elements_text(coalesce(n.propriedades->'_contatos', '[]'::jsonb)) c(hid) on true
    join crm.contato_espelho e on e.hubspot_id = c.hid and e.pessoa_id is not null
    where n.pessoa_id is null
    group by n.id
    having count(distinct e.pessoa_id) = 1
  )
  update crm.negocios_historicos n set pessoa_id = c.pessoa_id, atualizado_em = now()
  from casado c where n.id = c.neg_id;
  get diagnostics v_hist = row_count;

  -- Negocio -> produto. No pipeline vivo, quem diz e o catalogo: o mesmo ponteiro
  -- que impede o agente de enxergar pipeline que nao foi autorizado.
  update crm.summit_em_andamento n
     set produto_codigo = p.codigo, atualizado_em = now()
    from catalogo.produtos p
   where n.produto_codigo is null and p.pipeline_hubspot = n.pipeline;
  get diagnostics v_prod = row_count;

  -- No historico o ano do Summit e que diz qual edicao foi.
  update crm.negocios_historicos n
     set produto_codigo = p.codigo, atualizado_em = now()
    from catalogo.produtos p
   where n.produto_codigo is null
     and p.codigo = 'mind-summit-' || regexp_replace(coalesce(n.summit_year, ''), '\D', '', 'g');
  get diagnostics v_tmp = row_count;
  v_prod := v_prod + v_tmp;

  return jsonb_build_object(
    'contatos_ligados', v_contatos,
    'negocios_ligados', v_neg,
    'historicos_ligados', v_hist,
    'produtos_ligados', v_prod);
end;
$function$;

comment on function public.mind_espelho_ligar() is
  'Amarra o espelho do HubSpot na identidade canonica: contato -> crm.pessoas por e-mail e depois WhatsApp, negocio -> pessoa pelo contato associado (so quando ha um so), negocio -> produto pelo ponteiro do catalogo. Nunca cria pessoa e nunca sobrescreve o que ja esta ligado.';

revoke all on function public.mind_espelho_ligar() from public, anon, authenticated;