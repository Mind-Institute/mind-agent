-- ============================================================================
-- D5.3 — a fase A por índice: 12 s por pessoa viraram milissegundos
-- ============================================================================
-- Medido em produção às 04:02 UTC de 23/09: mind_pessoa_enriquecer levava ~12 s
-- por pessoa (31 h para as 9.451). Duas causas:
--   1. os índices de expressão da migration 20260923024555 são PARCIAIS
--      (where email is not null); para um predicado como lower(btrim(email)) = x
--      o planejador não consegue provar o predicado do índice e varre a tabela;
--   2. o enriquecer procurava cada fonte com "or … in (subquery)", que também
--      força varredura.
-- Correção: os mesmos índices sem predicado parcial (tabelas pequenas: 13 mil
-- contatos, 4,7 mil ingressos), um índice novo para o e-mail da Yazo, e o
-- enriquecer procurando cada fonte por união de ramos indexados
-- (coluna = any(array)). A regra do nome/e-mail (D5.2) fica exatamente igual.
-- Idempotente. Provada no Postgres descartável com o mesmo contrato.
-- ============================================================================

drop index if exists crm.contato_espelho_telefone_norm_idx;
drop index if exists crm.contato_espelho_whatsapp_norm_idx;
drop index if exists crm.contato_espelho_email_lower_idx;
drop index if exists credenciamento_summit_2026.participantes_email_lower_idx;
drop index if exists eduzz.ingressos_email_lower_idx;
drop index if exists eduzz.vendas_cliente_email_lower_idx;
drop index if exists pessoas.pessoas_email_lower_idx;
create index if not exists contato_espelho_telefone_norm_idx on crm.contato_espelho (public.telefone_normalizar(phone));
create index if not exists contato_espelho_whatsapp_norm_idx on crm.contato_espelho (public.telefone_normalizar(hs_whatsapp_phone_number));
create index if not exists contato_espelho_email_lower_idx   on crm.contato_espelho (lower(btrim(email)));
create index if not exists participantes_email_lower_idx     on credenciamento_summit_2026.participantes (lower(btrim(email)));
create index if not exists yazo_espelho_email_lower_idx      on credenciamento_summit_2026.yazo_espelho (lower(btrim(email)));
create index if not exists ingressos_email_lower_idx         on eduzz.ingressos (lower(btrim(email)));
create index if not exists vendas_cliente_email_lower_idx    on eduzz.vendas (lower(btrim(cliente_email)));
create index if not exists pessoas_email_lower_idx           on pessoas.pessoas (lower(email));

create or replace function public.mind_pessoa_enriquecer(p_pessoa_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, engagement, pessoas
as $function$
declare
  v_emails text[]; v_tels text[]; v_hubs text[]; v_docs text[]; v_yazo text[]; v_cred text[]; v_edz text[]; v_lw text[];
  v_nome text; v_ids jsonb := '{}'::jsonb; v_r jsonb; v_antes int; v_depois int; v_ignoradas int; v_usadas int;
  v_nome_pessoa text;
  a_emails text[]; a_tels text[]; a_hubs text[]; a_cred uuid[]; a_yazo bigint[]; a_edz text[];
begin
  if p_pessoa_id is null then return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa'); end if;
  if exists (select 1 from pessoas.pessoas where id = p_pessoa_id and fundida_em is not null) then
    return jsonb_build_object('ok', false, 'motivo', 'pessoa_fundida');
  end if;

  select count(*) into v_antes from engagement.identidades where pessoa_id = p_pessoa_id;
  select concat_ws(' ', primeiro_nome, sobrenome) into v_nome_pessoa from pessoas.pessoas where id = p_pessoa_id;

  -- identificadores atuais da pessoa, em arrays: cada fonte e procurada por indice
  with atual as (
    select canal, identificador from engagement.identidades where pessoa_id = p_pessoa_id
    union select 'email', lower(email) from pessoas.pessoas where id = p_pessoa_id and email is not null
    union select 'whatsapp', whatsapp from pessoas.pessoas where id = p_pessoa_id and whatsapp is not null
    union select 'hubspot', hubspot_id from pessoas.pessoas where id = p_pessoa_id and hubspot_id is not null
  )
  select coalesce(array_agg(identificador) filter (where canal = 'email'), '{}'),
         coalesce(array_agg(identificador) filter (where canal = 'whatsapp'), '{}'),
         coalesce(array_agg(identificador) filter (where canal = 'hubspot'), '{}'),
         coalesce(array_agg(case when canal = 'credenciamento' and identificador ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then identificador::uuid end)
                  filter (where canal = 'credenciamento' and identificador ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'), '{}'),
         coalesce(array_agg(case when canal = 'yazo' and identificador ~ '^[0-9]{1,18}$' then identificador::bigint end)
                  filter (where canal = 'yazo' and identificador ~ '^[0-9]{1,18}$'), '{}'),
         coalesce(array_agg(identificador) filter (where canal = 'eduzz'), '{}')
    into a_emails, a_tels, a_hubs, a_cred, a_yazo, a_edz
    from atual;

  create temp table if not exists d5_fontes_tmp (
    fonte text, email text, tel text, doc text, id_canal text, id_valor text, nome text,
    via_forte boolean, terceiro boolean, tel_ambiguo boolean) on commit drop;
  delete from d5_fontes_tmp;

  -- HubSpot
  insert into d5_fontes_tmp
  select 'hubspot', lower(btrim(c.email)), t.tel, null, 'hubspot', c.hubspot_id,
         nullif(btrim(concat_ws(' ', c.firstname, c.lastname)), ''),
         (c.pessoa_id = p_pessoa_id or c.hubspot_id = any(a_hubs) or lower(btrim(c.email)) = any(a_emails)),
         false,
         (t.tel is not null and (select count(*) > 1 from crm.contato_espelho d
            where public.telefone_normalizar(d.phone) = t.tel or public.telefone_normalizar(d.hs_whatsapp_phone_number) = t.tel))
    from crm.contato_espelho c
    join (select id from crm.contato_espelho where pessoa_id = p_pessoa_id
          union select id from crm.contato_espelho where hubspot_id = any(a_hubs)
          union select id from crm.contato_espelho where lower(btrim(email)) = any(a_emails)
          union select id from crm.contato_espelho where public.telefone_normalizar(phone) = any(a_tels)
          union select id from crm.contato_espelho where public.telefone_normalizar(hs_whatsapp_phone_number) = any(a_tels)) alvo on alvo.id = c.id
    cross join lateral (select coalesce(public.telefone_normalizar(c.hs_whatsapp_phone_number), public.telefone_normalizar(c.phone)) as tel) t;

  -- credenciamento (o CPF da linha e o do comprador: fora)
  insert into d5_fontes_tmp
  select 'credenciamento', lower(btrim(p.email)), p.telefone_norm, null, 'credenciamento', p.id::text, p.name,
         (p.pessoa_id = p_pessoa_id or lower(btrim(p.email)) = any(a_emails) or p.id = any(a_cred) or p.yazo_user_id = any(a_yazo)),
         (p.buyer_email is not null and lower(btrim(p.buyer_email)) <> lower(btrim(coalesce(p.email,'')))),
         (p.telefone_norm is not null and (select count(distinct lower(btrim(q.email))) > 1
            from credenciamento_summit_2026.participantes q where q.telefone_norm = p.telefone_norm))
    from credenciamento_summit_2026.participantes p
    join (select id from credenciamento_summit_2026.participantes where pessoa_id = p_pessoa_id
          union select id from credenciamento_summit_2026.participantes where lower(btrim(email)) = any(a_emails)
          union select id from credenciamento_summit_2026.participantes where telefone_norm = any(a_tels)
          union select id from credenciamento_summit_2026.participantes where id = any(a_cred)
          union select id from credenciamento_summit_2026.participantes where yazo_user_id = any(a_yazo)) alvo on alvo.id = p.id;

  -- Yazo
  insert into d5_fontes_tmp
  select 'yazo', lower(btrim(y.email)), t.tel, null, 'yazo', y.yazo_id::text, y.name,
         (y.pessoa_id = p_pessoa_id or lower(btrim(y.email)) = any(a_emails) or y.yazo_id = any(a_yazo)),
         (y.attributes->>'text_40' is not null and lower(btrim(y.attributes->>'text_40')) <> lower(btrim(coalesce(y.email,'')))),
         (t.tel is not null and (select count(distinct lower(btrim(z.email))) > 1 from credenciamento_summit_2026.yazo_espelho z
            where public.telefone_normalizar(case when jsonb_typeof(z.attributes->'cellphone') = 'object' then z.attributes->'cellphone'->>'value' else z.attributes->>'cellphone' end) = t.tel))
    from credenciamento_summit_2026.yazo_espelho y
    join (select yazo_id from credenciamento_summit_2026.yazo_espelho where pessoa_id = p_pessoa_id
          union select yazo_id from credenciamento_summit_2026.yazo_espelho where lower(btrim(email)) = any(a_emails)
          union select yazo_id from credenciamento_summit_2026.yazo_espelho where yazo_id = any(a_yazo)
          union select yazo_id from credenciamento_summit_2026.yazo_espelho
                 where public.telefone_normalizar(case when jsonb_typeof(attributes->'cellphone') = 'object' then attributes->'cellphone'->>'value' else attributes->>'cellphone' end) = any(a_tels)) alvo on alvo.yazo_id = y.yazo_id
    cross join lateral (select public.telefone_normalizar(case when jsonb_typeof(y.attributes->'cellphone') = 'object' then y.attributes->'cellphone'->>'value' else y.attributes->>'cellphone' end) as tel) t;

  -- Eduzz: ingressos (participante)
  insert into d5_fontes_tmp
  select 'eduzz', lower(btrim(i.email)), i.telefone_norm, i.cpf_cnpj, 'eduzz', i.cod_participante, i.participante,
         (i.pessoa_id = p_pessoa_id or lower(btrim(i.email)) = any(a_emails) or i.cod_participante = any(a_edz)),
         (i.email_comprador is not null and lower(btrim(i.email_comprador)) <> lower(btrim(coalesce(i.email,'')))),
         (i.telefone_norm is not null and (select count(distinct lower(btrim(j.email))) > 1 from eduzz.ingressos j where j.telefone_norm = i.telefone_norm))
    from eduzz.ingressos i
    join (select uuid from eduzz.ingressos where pessoa_id = p_pessoa_id
          union select uuid from eduzz.ingressos where lower(btrim(email)) = any(a_emails)
          union select uuid from eduzz.ingressos where telefone_norm = any(a_tels)
          union select uuid from eduzz.ingressos where cod_participante = any(a_edz)) alvo on alvo.uuid = i.uuid;

  -- Eduzz: vendas (comprador)
  insert into d5_fontes_tmp
  select 'eduzz_vendas', lower(btrim(v.cliente_email)), v.cliente_telefone_norm, v.cliente_documento, null, null, v.cliente_nome,
         (v.pessoa_id = p_pessoa_id or lower(btrim(v.cliente_email)) = any(a_emails)),
         false,
         (v.cliente_telefone_norm is not null and (select count(distinct lower(btrim(w.cliente_email))) > 1 from eduzz.vendas w where w.cliente_telefone_norm = v.cliente_telefone_norm))
    from eduzz.vendas v
    join (select linha_origem from eduzz.vendas where pessoa_id = p_pessoa_id
          union select linha_origem from eduzz.vendas where lower(btrim(cliente_email)) = any(a_emails)
          union select linha_origem from eduzz.vendas where cliente_telefone_norm = any(a_tels)) alvo on alvo.linha_origem = v.linha_origem;

  -- LearnWorlds (pelo comprador do checkout)
  insert into d5_fontes_tmp
  select 'learnworlds', lower(btrim(k.email)), null, null, 'learnworlds', a.destino_user_id, k.nome, true, false, false
    from learnworlds.acessos a
    join checkout.compradores k on k.id = a.comprador_id
   where a.destino_user_id is not null
     and (k.pessoa_id = p_pessoa_id or lower(btrim(coalesce(k.email,''))) = any(a_emails));

  -- a regra (D5.2): nome compativel sempre; por telefone so quando nada contradiz
  with ok as (
    select * from d5_fontes_tmp f
     where public.mind_nomes_compativeis(v_nome_pessoa, f.nome)
       and (f.via_forte
            or (not f.terceiro and not f.tel_ambiguo
                and (f.email is null or f.email = ''
                     or f.email = any(a_emails)
                     or cardinality(a_emails) = 0)))
  )
  select
    (select array_agg(distinct email) from ok where email is not null and email <> ''),
    (select array_agg(distinct tel) from ok where tel is not null and tel <> '' and not terceiro),
    (select array_agg(distinct id_valor) from ok where id_canal = 'hubspot' and id_valor is not null),
    (select array_agg(distinct doc) from ok where doc is not null and doc <> '' and not terceiro),
    (select array_agg(distinct id_valor) from ok where id_canal = 'yazo' and id_valor is not null),
    (select array_agg(distinct id_valor) from ok where id_canal = 'credenciamento' and id_valor is not null),
    (select array_agg(distinct id_valor) from ok where id_canal = 'eduzz' and id_valor is not null and id_valor <> ''),
    (select array_agg(distinct id_valor) from ok where id_canal = 'learnworlds' and id_valor is not null),
    (select nome from ok where nome is not null and btrim(nome) <> ''
      order by case fonte when 'hubspot' then 1 when 'credenciamento' then 2 when 'yazo' then 3 when 'eduzz' then 4 else 5 end limit 1),
    (select count(*) from ok),
    (select count(*) from d5_fontes_tmp) - (select count(*) from ok)
  into v_emails, v_tels, v_hubs, v_docs, v_yazo, v_cred, v_edz, v_lw, v_nome, v_usadas, v_ignoradas;

  v_ids := jsonb_strip_nulls(jsonb_build_object(
    'emails', to_jsonb(coalesce(v_emails, '{}')),
    'telefones', to_jsonb(coalesce(v_tels, '{}')),
    'hubspot_ids', to_jsonb(coalesce(v_hubs, '{}')),
    'yazo_ids', to_jsonb(coalesce(v_yazo, '{}')),
    'documento', v_docs[1],
    'credenciamento_id', v_cred[1],
    'eduzz_participante', v_edz[1],
    'learnworlds_user_id', v_lw[1]));

  v_r := public.mind_identidade_resolver(v_ids, v_nome, 'enriquecimento', p_pessoa_id);

  update pessoas.pessoas p
     set email = coalesce(p.email, (select i.identificador from engagement.identidades i where i.pessoa_id = p.id and i.canal = 'email'
                                    and not exists (select 1 from pessoas.pessoas q where lower(q.email) = i.identificador) order by i.criado_em limit 1)),
         whatsapp = coalesce(p.whatsapp, (select i.identificador from engagement.identidades i where i.pessoa_id = p.id and i.canal = 'whatsapp'
                                    and not exists (select 1 from pessoas.pessoas q where q.whatsapp = i.identificador) order by i.criado_em limit 1)),
         hubspot_id = coalesce(p.hubspot_id, (select i.identificador from engagement.identidades i where i.pessoa_id = p.id and i.canal = 'hubspot'
                                    and not exists (select 1 from pessoas.pessoas q where q.hubspot_id = i.identificador) order by i.criado_em limit 1)),
         enriquecida_em = now()
   where p.id = p_pessoa_id;

  select count(*) into v_depois from engagement.identidades where pessoa_id = p_pessoa_id;

  return jsonb_build_object('ok', true, 'pessoa_id', p_pessoa_id,
    'identidades_antes', v_antes, 'identidades_depois', v_depois,
    'novas', coalesce(v_r->'identidades', '[]'::jsonb),
    'conflito', v_r->'conflito',
    'linhas_usadas', v_usadas, 'linhas_ignoradas_pela_regra', v_ignoradas,
    'fontes', jsonb_build_object('hubspot', coalesce(array_length(v_hubs,1),0), 'credenciamento', coalesce(array_length(v_cred,1),0),
                                 'yazo', coalesce(array_length(v_yazo,1),0), 'eduzz', coalesce(array_length(v_edz,1),0), 'learnworlds', coalesce(array_length(v_lw,1),0)));
end $function$;

revoke all on function public.mind_pessoa_enriquecer(uuid) from public;
comment on function public.mind_pessoa_enriquecer(uuid) is
  'Fase A da passada D5. Reúne os identificadores que as fontes já ligadas à pessoa conhecem (HubSpot, credenciamento, Yazo, Eduzz, LearnWorlds), procurando cada fonte por índice, e os entrega à porta única com a pessoa ancorada. Regra do nome (Adriana, 23/09): só contribui a linha cujo nome não contradiz o da pessoa; linha achada só por telefone contribui apenas se não é inscrição por terceiro, o e-mail dela não é outro e o telefone aponta para um só e-mail na fonte; linha comprada por terceiro nunca entrega telefone nem CPF. Nunca cria pessoa. Nunca funde.';

do $$
begin
  if exists (select 1 from pg_indexes where indexname in ('contato_espelho_email_lower_idx','participantes_email_lower_idx','ingressos_email_lower_idx','vendas_cliente_email_lower_idx','pessoas_email_lower_idx')
              and indexdef ilike '%where%') then
    raise exception 'd5.3: índice de expressão continua parcial';
  end if;
end $$;
