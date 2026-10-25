-- Agent Intelligence, Fase 2 — Canais e Roteador (aprovado pela Adriana em 22/10/2026).
--
-- O que acontece em cada canal sai do código e vem para o banco, com liga/desliga no painel.
--
-- 1. `agentes.rotas`: o cadastro dos agentes (nome, o que faz e se as conversas dele passam
--    pela análise pós-conversa). Casa nova aprovada (D2); até aqui a lista vivia repetida em
--    constraints, funções e no código.
-- 2. `agentes.canal_competencia` (a casa de "quem atende em qual canal") ganha:
--    - `roteavel`: o roteador pode escolher este agente neste canal. Antes era a lista fixa
--      `ROTAS` no código do `router`. As 6 rotas daquela lista ficam roteáveis onde já
--      estavam; a MIA não. O roteador passa a escolher exatamente entre as mesmas de antes.
--    - `entradas_diretas`: as entradas (`origem_codigo`) deste canal que abrem a conversa
--      direto neste agente, sem roteador. Antes era `ROTA_POR_ORIGEM` no código da
--      `mindagent-chat` (`mind_summit_app → concierge_summit`), que vira dado.
--      Não foi para `engagement.origens`: uma linha do app ali mudaria o `utm_source` dos
--      links de checkout e de material do app e o produto da conversa.
-- 3. `mind_canal_rotas` devolve também `roteaveis`; `mind_origem_rota` diz a porta direta.
-- 4. Portas do painel (só service_role; escrita só do administrador).

set lock_timeout = '10s';

-- ------------------------------------------------------------------ cadastro de agentes
create table if not exists agentes.rotas (
  rota              text primary key check (rota ~ '^[a-z][a-z0-9_]{1,59}$'),
  nome              text not null check (btrim(nome) <> ''),
  descricao         text,
  analisa_conversas boolean not null default true,
  atualizado_em     timestamptz not null default now()
);
comment on table agentes.rotas is
  'Cadastro dos agentes (rotas/competências): nome, o que faz e se as conversas dele passam pela análise pós-conversa. Aprovado pela Adriana em 22/10/2026.';
comment on column agentes.rotas.descricao is 'O que este agente faz, nas palavras da Adriana. Aparece no painel.';
comment on column agentes.rotas.analisa_conversas is 'As conversas atendidas por este agente passam pela análise pós-conversa.';
alter table agentes.rotas enable row level security;
revoke all on table agentes.rotas from public, anon, authenticated;

insert into agentes.rotas (rota, nome) values
  ('concierge_summit', 'Concierge Summit'),
  ('cliente_suporte',  'Suporte ao cliente'),
  ('summit_b2c',       'Summit B2C'),
  ('summit_b2b',       'Summit B2B'),
  ('institute',        'Mind Institute'),
  ('dash',             'Mind Dash'),
  ('mia_summit_2026',  'MIA Summit 2026')
on conflict (rota) do nothing;

-- ------------------------------------------------------------------ canal × agente
alter table agentes.canal_competencia
  add constraint canal_competencia_rota_cadastrada foreign key (rota) references agentes.rotas (rota);
alter table agentes.canal_competencia add column if not exists roteavel boolean not null default false;
alter table agentes.canal_competencia add column if not exists entradas_diretas text[] not null default '{}';
comment on column agentes.canal_competencia.roteavel is
  'O roteador pode escolher este agente neste canal. Só vale com `ativo`.';
comment on column agentes.canal_competencia.entradas_diretas is
  'Entradas (origem_codigo) deste canal que abrem a conversa direto neste agente, sem roteador. Só vale com `ativo`; o Gate continua conferindo.';

update agentes.canal_competencia
   set roteavel = true
 where rota in ('summit_b2c','summit_b2b','institute','dash','cliente_suporte','concierge_summit');

update agentes.canal_competencia
   set entradas_diretas = array['mind_summit_app']
 where canal = 'mindagent-web' and rota = 'concierge_summit';

-- ------------------------------------------------------------------ o que o runtime lê
create or replace function public.mind_canal_rotas(p_canal text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public', 'agentes'
as $function$
  with entrada as (
    select nullif(btrim(p_canal), '') as canal
  ),
  canal_valido as (
    select e.canal
      from entrada e
     where exists (select 1 from agentes.canal_competencia cc where cc.canal = e.canal)
  )
  select case
    when (select count(*) from canal_valido) = 0
      then jsonb_build_object('ok', false, 'motivo', 'canal_invalido')
    else jsonb_build_object(
      'ok',    true,
      'canal', (select canal from canal_valido),
      'rotas', coalesce((
        select jsonb_agg(cc.rota order by cc.rota)
          from agentes.canal_competencia cc
         where cc.canal = (select canal from canal_valido)
           and cc.ativo
      ), '[]'::jsonb),
      -- O universo do roteador: ligadas no canal E marcadas como roteáveis.
      'roteaveis', coalesce((
        select jsonb_agg(cc.rota order by cc.rota)
          from agentes.canal_competencia cc
         where cc.canal = (select canal from canal_valido)
           and cc.ativo and cc.roteavel
      ), '[]'::jsonb))
  end;
$function$;

-- A porta direta de uma entrada neste canal, ou nada (o roteador decide).
create or replace function public.mind_origem_rota(p_origem text, p_canal text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select cc.rota
    from agentes.canal_competencia cc
   where cc.canal = nullif(btrim(p_canal), '')
     and cc.ativo
     and nullif(btrim(p_origem), '') = any (cc.entradas_diretas)
   order by cc.rota
   limit 1;
$$;
revoke all on function public.mind_origem_rota(text, text) from public, anon, authenticated;
grant execute on function public.mind_origem_rota(text, text) to service_role;

-- ------------------------------------------------------------------ portas do painel
create or replace function public.mind_admin_read_agent_channels(p_id text default null)
 returns setof jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
  select jsonb_build_object(
    'id', c.canal || '::' || c.rota,
    'canal', c.canal,
    'rota', c.rota,
    'ativo', c.ativo,
    'roteavel', c.roteavel,
    'entradasDiretas', to_jsonb(c.entradas_diretas),
    'observacao', c.observacao,
    'atualizadoEm', c.atualizado_em)
  from agentes.canal_competencia c
  where p_id is null or c.canal || '::' || c.rota = p_id
  order by c.rota, c.canal;
$function$;

-- A escrita ganha `roteavel` e `entradas_diretas` (assinatura nova). A antiga, de 5
-- parâmetros, continua existindo e só repassa: a `mindagent-knowledge` v10 ainda a chama
-- até a v11 subir, e o PostgREST escolhe pelos nomes dos parâmetros.
create or replace function public.mind_admin_update_agent_channel(
  p_id text, p_ativo boolean, p_roteavel boolean, p_entradas_diretas text[], p_observacao text,
  p_ator uuid, p_atualizado_em_esperado timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role     text;
  v_atual    agentes.canal_competencia%rowtype;
  v_entradas text[];
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

  if p_entradas_diretas is not null then
    select coalesce(array_agg(distinct btrim(e) order by btrim(e)), array[]::text[])
      into v_entradas
      from unnest(p_entradas_diretas) e
     where btrim(coalesce(e, '')) <> '';
    if exists (select 1 from unnest(v_entradas) e where e !~ '^[a-z][a-z0-9_]{1,59}$') then
      raise exception using errcode = '22023', message = 'admin_validation:entrada';
    end if;
    -- Uma entrada abre em um agente só, por canal.
    if exists (
      select 1 from agentes.canal_competencia c
       where c.canal = v_atual.canal and c.rota <> v_atual.rota
         and c.entradas_diretas && v_entradas) then
      raise exception using errcode = '22023', message = 'admin_validation:entrada_em_uso';
    end if;
  end if;

  update agentes.canal_competencia c
     set ativo = coalesce(p_ativo, c.ativo),
         roteavel = coalesce(p_roteavel, c.roteavel),
         entradas_diretas = coalesce(v_entradas, c.entradas_diretas),
         observacao = coalesce(p_observacao, c.observacao),
         atualizado_em = now()
   where c.canal = v_atual.canal and c.rota = v_atual.rota;

  return (select x from public.mind_admin_read_agent_channels(p_id) x limit 1);
end;
$$;

create or replace function public.mind_admin_update_agent_channel(
  p_id text, p_ativo boolean, p_observacao text, p_ator uuid, p_atualizado_em_esperado timestamptz default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select public.mind_admin_update_agent_channel(p_id, p_ativo, null, null, p_observacao, p_ator, p_atualizado_em_esperado);
$$;

create or replace function public.mind_admin_read_agents(p_id text default null)
returns setof jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', r.rota,
    'rota', r.rota,
    'nome', r.nome,
    'descricao', r.descricao,
    'analisaConversas', r.analisa_conversas,
    'atualizadoEm', r.atualizado_em)
  from agentes.rotas r
  where p_id is null or r.rota = p_id
  order by r.nome;
$$;

create or replace function public.mind_admin_update_agent(
  p_rota text, p_nome text, p_descricao text, p_ator uuid, p_atualizado_em_esperado timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role  text;
  v_atual agentes.rotas%rowtype;
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
    raise exception using errcode = '40001', message = 'admin_conflict';
  end if;
  if p_nome is not null and btrim(p_nome) = '' then
    raise exception using errcode = '22023', message = 'admin_validation:nome';
  end if;
  if p_descricao is not null and length(p_descricao) > 4000 then
    raise exception using errcode = '22023', message = 'admin_validation:descricao';
  end if;

  update agentes.rotas r
     set nome = coalesce(btrim(p_nome), r.nome),
         descricao = case when p_descricao is null then r.descricao else nullif(btrim(p_descricao), '') end,
         atualizado_em = now()
   where r.rota = p_rota;

  return (select x from public.mind_admin_read_agents(p_rota) x limit 1);
end;
$$;

-- As entradas do WhatsApp (botões do site que abrem a conversa), para a tela mostrar de onde
-- as pessoas chegam. Só leitura.
create or replace function public.mind_admin_read_channel_entries(p_id text default null)
returns setof jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', o.codigo,
    'codigo', o.codigo,
    'canal', 'whatsapp',
    'site', o.site,
    'rotulo', o.botao_rotulo,
    'descricao', o.descricao,
    'audienciaSugerida', o.audiencia_sugerida,
    'ativo', o.ativo,
    'atualizadoEm', o.atualizado_em)
  from engagement.origens o
  where p_id is null or o.codigo = p_id
  order by o.ativo desc, o.botao_rotulo;
$$;

revoke all on function public.mind_admin_update_agent_channel(text, boolean, boolean, text[], text, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.mind_admin_read_agents(text) from public, anon, authenticated;
revoke all on function public.mind_admin_update_agent(text, text, text, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.mind_admin_read_channel_entries(text) from public, anon, authenticated;
grant execute on function public.mind_admin_update_agent_channel(text, boolean, boolean, text[], text, uuid, timestamptz) to service_role;
grant execute on function public.mind_admin_read_agents(text) to service_role;
grant execute on function public.mind_admin_update_agent(text, text, text, uuid, timestamptz) to service_role;
grant execute on function public.mind_admin_read_channel_entries(text) to service_role;
