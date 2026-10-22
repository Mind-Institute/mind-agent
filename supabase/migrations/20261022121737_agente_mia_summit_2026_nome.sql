-- O agente de conteúdo do Summit 2026 se chama MIA Summit 2026 (Adriana, 22/10/2026).
-- O identificador acompanha o nome: conteudo_summit vira mia_summit_2026 em todas as
-- casas onde ele foi cadastrado em 20261022120512. Nada usava o nome antigo: o agente
-- nasceu desligado e nenhuma conversa passou por ele. Renomeia, não apaga.

set lock_timeout = '10s';

alter table agentes.kit_blocos drop constraint kit_blocos_rota_canonica;

update agentes.kit_blocos set rota = 'mia_summit_2026' where rota = 'conteudo_summit';
update agentes.canal_competencia set rota = 'mia_summit_2026',
       observacao = replace(observacao, 'Orientador de conteúdo do Summit 2026', 'MIA Summit 2026, orientadora de conteúdo do Summit 2026')
 where rota = 'conteudo_summit';

alter table agentes.kit_blocos add constraint kit_blocos_rota_canonica
  check (rota = any (array['summit_b2c','summit_b2b','institute','dash',
                           'cliente_suporte','concierge_summit','mia_summit_2026']));

update agentes.prompts
   set chave = 'playbook_mia_summit_2026',
       titulo = 'Playbook — MIA Summit 2026 (RASCUNHO para revisão da Adriana)',
       conteudo = replace(conteudo,
               'VOCÊ É O ORIENTADOR DE CONTEÚDO DO MIND SUMMIT 2026',
               'VOCÊ É A MIA SUMMIT 2026, A ORIENTADORA DE CONTEÚDO DO MIND SUMMIT 2026'),
       atualizado_em = now()
 where chave = 'playbook_conteudo_summit'
   and not exists (select 1 from agentes.prompts where chave = 'playbook_mia_summit_2026');

update agentes.knowledge_access
   set agent_key = 'mia_summit_2026',
       metadata = metadata || jsonb_build_object('origem', 'criado com o agente MIA Summit 2026 em 22/10/2026')
 where agent_key = 'conteudo_summit';
update ecossistema.agent_knowledge_access
   set agent_key = 'mia_summit_2026',
       metadata = metadata || jsonb_build_object('origem', 'criado com o agente MIA Summit 2026 em 22/10/2026')
 where agent_key = 'conteudo_summit';

CREATE OR REPLACE FUNCTION public.mind_kit_meta(p_rota text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'agentes'
AS $function$
declare
  v_rota         text    := nullif(btrim(p_rota), '');
  v_configurado  boolean;
  v_obrigatorios text[]  := array[]::text[];
  v_ausentes     text[]  := array[]::text[];
  v_payload      jsonb;
  r              record;
begin
  if v_rota is null or v_rota not in (
       'summit_b2c','summit_b2b','institute','dash','cliente_suporte','concierge_summit','mia_summit_2026') then
    return jsonb_build_object('ok', false, 'motivo', 'rota_invalida');
  end if;

  select exists (
    select 1 from agentes.kit_blocos k
     where k.rota = v_rota and k.ativo and k.secao = 'structured')
    into v_configurado;

  for r in
    select k.bloco, n.nspname as sch, p.proname as fn
    from agentes.kit_blocos k
    left join pg_proc p
      on p.oid = to_regprocedure(
           case when k.provider ~ '^[a-z_][a-z0-9_$]*\.[a-z_][a-z0-9_$]*$'
                then k.provider || '(uuid,jsonb)'
           end)
     and p.prokind = 'f' and p.pronargs = 2
     and p.proargtypes[0] = 'uuid'::regtype and p.proargtypes[1] = 'jsonb'::regtype
     and p.prorettype = 'jsonb'::regtype and not p.proretset
     and p.provolatile = 's' and p.prosecdef
    left join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
    where k.rota = v_rota and k.ativo and k.obrigatorio and k.secao = 'structured'
    order by k.bloco
  loop
    v_obrigatorios := v_obrigatorios || r.bloco;
    if r.sch is null or r.fn is null then
      v_ausentes := v_ausentes || r.bloco;
    else
      execute format('select %I.%I($1::uuid, $2::jsonb)', r.sch, r.fn)
        into v_payload using null::uuid, null::jsonb;
      if v_payload is null then v_ausentes := v_ausentes || r.bloco; end if;
    end if;
  end loop;

  return jsonb_build_object(
    'ok',                  true,
    'rota',                v_rota,
    'kit_configurado',     v_configurado,
    'kit_disponivel',      v_configurado and cardinality(v_ausentes) = 0,
    'blocos_obrigatorios', to_jsonb(v_obrigatorios),
    'blocos_ausentes',     to_jsonb(v_ausentes));
end;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_rota_capacidade(p_rota text, p_canal text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'agentes'
AS $function$
with entrada as (
  select nullif(btrim(p_rota), '')  as rota,
         nullif(btrim(p_canal), '') as canal
),
rota_valida as (
  select e.rota
    from entrada e
   where e.rota in ('summit_b2c','summit_b2b','institute','dash',
                    'cliente_suporte','concierge_summit','mia_summit_2026')
),
canal_valido as (
  select e.canal
    from entrada e
   where exists (select 1 from agentes.canal_competencia cc where cc.canal = e.canal)
),
playbook as (
  select exists (
    select 1 from agentes.prompts pr, entrada e
     where pr.chave = 'playbook_' || e.rota
       and pr.ativo
       and btrim(coalesce(pr.conteudo, '')) <> ''
  ) as tem
),
kit as (
  select coalesce(
           (public.mind_kit_meta((select rota from rota_valida))
              ->> 'kit_disponivel')::boolean,
           false) as tem
),
canal_executa as (
  select exists (
    select 1
      from agentes.canal_competencia cc
     where cc.canal = (select canal from canal_valido)
       and cc.rota  = (select rota  from rota_valida)
       and cc.ativo
  ) as tem
),
avaliado as (
  select case
           when not (select tem from playbook)      then 'missing_playbook'
           when not (select tem from kit)           then 'missing_kit'
           when not (select tem from canal_executa) then 'canal_incompativel'
         end as reason
)
select case
  when (select count(*) from rota_valida)  = 0 then jsonb_build_object('ok', false, 'motivo', 'rota_invalida')
  when (select count(*) from canal_valido) = 0 then jsonb_build_object('ok', false, 'motivo', 'canal_invalido')
  else jsonb_build_object(
    'ok',    true,
    'rota',  (select rota  from rota_valida),
    'canal', (select canal from canal_valido),
    'pode_executar', (select reason from avaliado) is null,
    'needs_human',   (select reason from avaliado) is not null,
    'reason',        (select reason from avaliado))
end;
$function$
;

revoke all on function public.mind_kit_meta(text) from public, anon, authenticated;
revoke all on function public.mind_rota_capacidade(text, text) from public, anon, authenticated;
grant execute on function public.mind_kit_meta(text) to service_role;
grant execute on function public.mind_rota_capacidade(text, text) to service_role;
