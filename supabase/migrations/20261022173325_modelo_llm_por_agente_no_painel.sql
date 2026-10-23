-- Modelo (LLM) por agente, editável no painel Agent Intelligence (Adriana, 22/10/2026:
-- "poder trocar o modelo no front end e ver o que faz com a qualidade"). Coluna em casa existente.
-- Nulo = padrão do runtime (OPENAI_MODEL, hoje gpt-5.4). O runtime lê o modelo pelo gate
-- (mind_rota_capacidade) e, se a OpenAI recusar o nome, volta ao padrão e registra na telemetria.
alter table agentes.rotas add column if not exists modelo text;
alter table agentes.rotas drop constraint if exists rotas_modelo_check;
alter table agentes.rotas add constraint rotas_modelo_check
  check (modelo is null or modelo ~ '^[a-z0-9][a-z0-9._-]{1,63}$');
comment on column agentes.rotas.modelo is
  'Modelo da OpenAI que este agente usa (ex.: gpt-5.4). Nulo = padrão do runtime. Editável no painel Agent Intelligence (22/10/2026).';

create or replace function public.mind_admin_read_agents(p_id text default null)
 returns setof jsonb
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select jsonb_build_object(
    'id', r.rota,
    'rota', r.rota,
    'nome', r.nome,
    'descricao', r.descricao,
    'analisaConversas', r.analisa_conversas,
    'modelo', r.modelo,
    'atualizadoEm', r.atualizado_em)
  from agentes.rotas r
  where p_id is null or r.rota = p_id
  order by r.nome;
$function$;

-- 7 parâmetros: p_modelo nulo = não mexe; vazio = volta ao padrão.
create or replace function public.mind_admin_update_agent(
  p_rota text, p_nome text, p_descricao text, p_analisa_conversas boolean, p_modelo text,
  p_ator uuid, p_atualizado_em_esperado timestamp with time zone)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_role  text;
  v_atual agentes.rotas%rowtype;
  v_modelo text := nullif(btrim(coalesce(p_modelo, '')), '');
begin
  select a.role into v_role from public.mind_admin_users a where a.user_id = p_ator and a.active;
  if v_role is distinct from 'administrador' then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  end if;
  select * into v_atual from agentes.rotas r where r.rota = p_rota for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'admin_not_found';
  end if;
  if p_atualizado_em_esperado is not null and v_atual.atualizado_em is distinct from p_atualizado_em_esperado then
    raise exception using errcode = '55000', message = 'admin_conflict';
  end if;
  if p_nome is not null and btrim(p_nome) = '' then
    raise exception using errcode = '22023', message = 'admin_validation:nome';
  end if;
  if p_descricao is not null and length(p_descricao) > 4000 then
    raise exception using errcode = '22023', message = 'admin_validation:descricao';
  end if;
  if v_modelo is not null and v_modelo !~ '^[a-z0-9][a-z0-9._-]{1,63}$' then
    raise exception using errcode = '22023', message = 'admin_validation:modelo';
  end if;

  update agentes.rotas r
     set nome = coalesce(btrim(p_nome), r.nome),
         descricao = case when p_descricao is null then r.descricao else nullif(btrim(p_descricao), '') end,
         analisa_conversas = coalesce(p_analisa_conversas, r.analisa_conversas),
         modelo = case when p_modelo is null then r.modelo else v_modelo end,
         atualizado_em = now()
   where r.rota = p_rota;

  return (select x from public.mind_admin_read_agents(p_rota) x limit 1);
end;
$function$;
revoke all on function public.mind_admin_update_agent(text, text, text, boolean, text, uuid, timestamp with time zone) from public, anon, authenticated;
grant execute on function public.mind_admin_update_agent(text, text, text, boolean, text, uuid, timestamp with time zone) to service_role;

-- As assinaturas antigas continuam valendo e delegam (não mexem no modelo).
create or replace function public.mind_admin_update_agent(
  p_rota text, p_nome text, p_descricao text, p_analisa_conversas boolean,
  p_ator uuid, p_atualizado_em_esperado timestamp with time zone)
 returns jsonb
 language sql
 security definer
 set search_path to ''
as $function$
  select public.mind_admin_update_agent(p_rota, p_nome, p_descricao, p_analisa_conversas, null, p_ator, p_atualizado_em_esperado);
$function$;

create or replace function public.mind_admin_update_agent(
  p_rota text, p_nome text, p_descricao text, p_ator uuid, p_atualizado_em_esperado timestamp with time zone)
 returns jsonb
 language sql
 security definer
 set search_path to ''
as $function$
  select public.mind_admin_update_agent(p_rota, p_nome, p_descricao, null, null, p_ator, p_atualizado_em_esperado);
$function$;

-- O gate já é consultado a cada turno: devolve também o modelo da rota.
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
  else jsonb_strip_nulls(jsonb_build_object(
    'ok',    true,
    'rota',  (select rota  from rota_valida),
    'canal', (select canal from canal_valido),
    'pode_executar', (select reason from avaliado) is null,
    'needs_human',   (select reason from avaliado) is not null,
    'reason',        (select reason from avaliado),
    'modelo',        (select r.modelo from agentes.rotas r where r.rota = (select rota from rota_valida))))
end;
$function$;
