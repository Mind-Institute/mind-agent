-- Agent Intelligence no painel: operar, por agente, canais, kit e prompts.
-- Aprovado pela Adriana em 22/10/2026: item C (D7); histórico de prompts com tabela
-- nova (D2); só o papel administrador edita. Leitura: qualquer admin ativo (a Edge
-- Function mindagent-knowledge já valida sessão e admin antes de chamar).

-- kit_blocos ganha a data da última mudança, para o painel não sobrescrever a edição
-- de outra pessoa (o mesmo controle de concorrência das outras telas).
alter table agentes.kit_blocos add column if not exists atualizado_em timestamptz not null default now();

create table if not exists agentes.prompts_historico (
  id bigint generated always as identity primary key,
  chave text not null,
  versao integer,
  titulo text,
  conteudo text,
  ativo boolean not null,
  produto_codigo text,
  vigente_desde timestamptz,
  substituida_em timestamptz not null default now(),
  mind_id uuid references pessoas.pessoas(id),
  substituida_por_nome text
);
create index if not exists prompts_historico_chave_idx on agentes.prompts_historico (chave, substituida_em desc);
comment on table agentes.prompts_historico is
  'Versões anteriores de agentes.prompts. Cada edição feita pelo painel (Agent Intelligence) guarda aqui a versão que foi substituída, com quem e quando. Decisão da Adriana, 22/10/2026.';
comment on column agentes.prompts_historico.mind_id is
  'Mind ID de quem fez a edição que substituiu esta versão, copiado de public.mind_admin_users.mind_id (pessoa já resolvida pela porta única).';
comment on column agentes.prompts_historico.vigente_desde is 'atualizado_em da versão guardada: desde quando ela valia.';
alter table agentes.prompts_historico enable row level security;
revoke all on table agentes.prompts_historico from public, anon, authenticated;

create or replace function public.mind_admin_read_agent_channels(p_id text default null)
returns setof jsonb
language sql stable security definer
set search_path to ''
as $function$
  select jsonb_build_object(
    'id', c.canal || '::' || c.rota,
    'canal', c.canal,
    'rota', c.rota,
    'ativo', c.ativo,
    'observacao', c.observacao,
    'atualizadoEm', c.atualizado_em)
  from agentes.canal_competencia c
  where p_id is null or c.canal || '::' || c.rota = p_id
  order by c.rota, c.canal;
$function$;

create or replace function public.mind_admin_update_agent_channel(
  p_id text, p_ativo boolean, p_observacao text, p_ator uuid,
  p_atualizado_em_esperado timestamptz default null)
returns jsonb
language plpgsql security definer
set search_path to ''
as $function$
declare
  v_role text;
  v_atual agentes.canal_competencia%rowtype;
begin
  select a.role into v_role from public.mind_admin_users a where a.user_id = p_ator and a.active;
  if v_role is distinct from 'administrador' then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  end if;

  select * into v_atual from agentes.canal_competencia c where c.canal || '::' || c.rota = p_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'admin_not_found';
  end if;
  if p_atualizado_em_esperado is not null and v_atual.atualizado_em is distinct from p_atualizado_em_esperado then
    raise exception using errcode = '40001', message = 'admin_conflict';
  end if;

  update agentes.canal_competencia c
     set ativo = coalesce(p_ativo, c.ativo),
         observacao = coalesce(p_observacao, c.observacao),
         atualizado_em = now()
   where c.canal = v_atual.canal and c.rota = v_atual.rota;

  return (select x from public.mind_admin_read_agent_channels(p_id) x limit 1);
end;
$function$;

create or replace function public.mind_admin_read_agent_kit(p_id text default null)
returns setof jsonb
language sql stable security definer
set search_path to ''
as $function$
  select jsonb_build_object(
    'id', k.rota || '::' || k.bloco,
    'rota', k.rota,
    'bloco', k.bloco,
    'provider', k.provider,
    'secao', k.secao,
    'obrigatorio', k.obrigatorio,
    'ativo', k.ativo,
    'atualizadoEm', k.atualizado_em)
  from agentes.kit_blocos k
  where p_id is null or k.rota || '::' || k.bloco = p_id
  order by k.rota, k.secao, k.bloco;
$function$;

-- Liga, desliga ou muda a obrigatoriedade de um bloco; ou acrescenta a um agente um
-- bloco que já existe em outro (fonte e seção copiadas do bloco existente).
create or replace function public.mind_admin_upsert_agent_kit_block(
  p_rota text, p_bloco text, p_ativo boolean, p_obrigatorio boolean, p_ator uuid,
  p_atualizado_em_esperado timestamptz default null)
returns jsonb
language plpgsql security definer
set search_path to ''
as $function$
declare
  v_role text;
  v_atual agentes.kit_blocos%rowtype;
  v_modelo agentes.kit_blocos%rowtype;
begin
  select a.role into v_role from public.mind_admin_users a where a.user_id = p_ator and a.active;
  if v_role is distinct from 'administrador' then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  end if;

  select * into v_atual from agentes.kit_blocos k where k.rota = p_rota and k.bloco = p_bloco for update;
  if found then
    if p_atualizado_em_esperado is not null and v_atual.atualizado_em is distinct from p_atualizado_em_esperado then
      raise exception using errcode = '40001', message = 'admin_conflict';
    end if;
    update agentes.kit_blocos k
       set ativo = coalesce(p_ativo, k.ativo),
           obrigatorio = coalesce(p_obrigatorio, k.obrigatorio),
           atualizado_em = now()
     where k.rota = p_rota and k.bloco = p_bloco;
  else
    select * into v_modelo from agentes.kit_blocos k where k.bloco = p_bloco order by k.atualizado_em desc limit 1;
    if not found then
      raise exception using errcode = 'P0002', message = 'admin_not_found';
    end if;
    begin
      insert into agentes.kit_blocos (rota, bloco, provider, secao, obrigatorio, ativo, atualizado_em)
      values (p_rota, p_bloco, v_modelo.provider, v_modelo.secao,
              coalesce(p_obrigatorio, false), coalesce(p_ativo, true), now());
    exception when check_violation then
      raise exception using errcode = '22023', message = 'admin_validation:rota';
    end;
  end if;

  return (select x from public.mind_admin_read_agent_kit(p_rota || '::' || p_bloco) x limit 1);
end;
$function$;

create or replace function public.mind_admin_read_agent_prompts(p_id text default null)
returns setof jsonb
language sql stable security definer
set search_path to ''
as $function$
  select jsonb_build_object(
    'id', p.chave,
    'chave', p.chave,
    'titulo', p.titulo,
    'conteudo', p.conteudo,
    'ativo', p.ativo,
    'versao', p.versao,
    'produtoCodigo', p.produto_codigo,
    'atualizadoEm', p.atualizado_em,
    'rota', case when p.chave like 'playbook\_%' then substr(p.chave, 10) end,
    'usadoPor', coalesce((
      select jsonb_agg(distinct k.rota)
        from agentes.kit_blocos k
       where k.bloco = p.chave and k.secao = 'decisioning'), '[]'::jsonb),
    'historico', case when p_id is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
               'versao', h.versao, 'titulo', h.titulo, 'conteudo', h.conteudo, 'ativo', h.ativo,
               'vigenteDesde', h.vigente_desde, 'substituidaEm', h.substituida_em,
               'substituidaPor', h.substituida_por_nome)
             order by h.substituida_em desc)
        from agentes.prompts_historico h
       where h.chave = p.chave), '[]'::jsonb) end)
  from agentes.prompts p
  where p_id is null or p.chave = p_id
  order by p.chave;
$function$;

-- Edita um prompt guardando antes a versão atual em agentes.prompts_historico.
create or replace function public.mind_admin_update_agent_prompt(
  p_chave text, p_titulo text, p_conteudo text, p_ativo boolean, p_ator uuid,
  p_atualizado_em_esperado timestamptz default null)
returns jsonb
language plpgsql security definer
set search_path to ''
as $function$
declare
  v_role text;
  v_mind_id uuid;
  v_nome text;
  v_atual agentes.prompts%rowtype;
begin
  select a.role, a.mind_id, a.display_name into v_role, v_mind_id, v_nome
    from public.mind_admin_users a where a.user_id = p_ator and a.active;
  if v_role is distinct from 'administrador' then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  end if;

  select * into v_atual from agentes.prompts p where p.chave = p_chave for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'admin_not_found';
  end if;
  if p_atualizado_em_esperado is not null and v_atual.atualizado_em is distinct from p_atualizado_em_esperado then
    raise exception using errcode = '40001', message = 'admin_conflict';
  end if;
  if p_conteudo is not null and btrim(p_conteudo) = '' then
    raise exception using errcode = '22023', message = 'admin_validation:conteudo';
  end if;

  if coalesce(p_titulo, v_atual.titulo) is not distinct from v_atual.titulo
     and coalesce(p_conteudo, v_atual.conteudo) is not distinct from v_atual.conteudo
     and coalesce(p_ativo, v_atual.ativo) is not distinct from v_atual.ativo then
    return (select x from public.mind_admin_read_agent_prompts(p_chave) x limit 1);
  end if;

  insert into agentes.prompts_historico
    (chave, versao, titulo, conteudo, ativo, produto_codigo, vigente_desde, substituida_em, mind_id, substituida_por_nome)
  values
    (v_atual.chave, v_atual.versao, v_atual.titulo, v_atual.conteudo, v_atual.ativo, v_atual.produto_codigo,
     v_atual.atualizado_em, now(), v_mind_id, v_nome);

  update agentes.prompts p
     set titulo = coalesce(p_titulo, p.titulo),
         conteudo = coalesce(p_conteudo, p.conteudo),
         ativo = coalesce(p_ativo, p.ativo),
         versao = coalesce(p.versao, 0) + 1,
         atualizado_em = now()
   where p.chave = p_chave;

  return (select x from public.mind_admin_read_agent_prompts(p_chave) x limit 1);
end;
$function$;

revoke all on function public.mind_admin_read_agent_channels(text) from public, anon, authenticated;
revoke all on function public.mind_admin_update_agent_channel(text, boolean, text, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.mind_admin_read_agent_kit(text) from public, anon, authenticated;
revoke all on function public.mind_admin_upsert_agent_kit_block(text, text, boolean, boolean, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.mind_admin_read_agent_prompts(text) from public, anon, authenticated;
revoke all on function public.mind_admin_update_agent_prompt(text, text, text, boolean, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.mind_admin_read_agent_channels(text) to service_role;
grant execute on function public.mind_admin_update_agent_channel(text, boolean, text, uuid, timestamptz) to service_role;
grant execute on function public.mind_admin_read_agent_kit(text) to service_role;
grant execute on function public.mind_admin_upsert_agent_kit_block(text, text, boolean, boolean, uuid, timestamptz) to service_role;
grant execute on function public.mind_admin_read_agent_prompts(text) to service_role;
grant execute on function public.mind_admin_update_agent_prompt(text, text, text, boolean, uuid, timestamptz) to service_role;
