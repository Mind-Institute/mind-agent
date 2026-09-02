-- ============================================================
-- 03 · O recurso `home_notices` para o painel administrativo
-- ============================================================
-- Projeto: mind-agent (ymnmotgglsrxmjmonwjz)
-- Depende de: 01-concierge-avisos.sql
--
-- POR QUE DUAS FUNÇÕES NOVAS, E NÃO UM RAMO NAS EXISTENTES
-- `mind_admin_read_resource` e `mind_admin_mutate_resource` despacham por
-- recurso e servem event, sessions, speakers, spaces e themes hoje, em
-- produção. Acrescentar um `elsif` obrigaria a reescrever 15 mil
-- caracteres de função viva para mudar oito linhas — risco desproporcional
-- ao ganho. Estas duas ficam ao lado, com as mesmas regras de papel, o
-- mesmo travamento otimista e a mesma auditoria; a Edge Function escolhe
-- qual chamar. As funções antigas não são tocadas.
--
-- Reversível: `drop function` nas duas.
--
-- SCHEMA: usa `summit_2026`, não `summit`. O schema `summit` deixou de
-- existir em 24/08 (migração `summit_vira_summit_2026`), e as funções
-- administrativas vivas ficaram apontando para o nome antigo — é por isso
-- que elas estão quebradas hoje. Ver 00-LEIA-ANTES.md.

-- ------------------------------------------------------------
-- Leitura
-- ------------------------------------------------------------
create or replace function public.mind_admin_read_home_notices(p_id uuid default null)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'pg_catalog', 'public', 'summit_2026'
as $function$
  select coalesce(jsonb_agg(x.obj order by x.ordem desc nulls last), '[]'::jsonb)
  from (
    select a.disparo_em as ordem,
      jsonb_build_object(
        'id', a.id::text,
        'criadoEm', a.criado_em,
        'atualizadoEm', a.atualizado_em,
        'atualizadoPor', a.atualizado_por::text,
        'icone', a.icone,
        'titulo', a.titulo,
        'subtitulo', a.subtitulo,
        'descricao', a.descricao,
        'imediato', a.imediato,
        -- Formato do <input type="datetime-local"> do painel.
        'disparoEm', coalesce(
          to_char(a.disparo_em at time zone coalesce(
            (select e.fuso from summit_2026.events e order by e.ativo desc, e.atualizado_em desc limit 1),
            'America/Sao_Paulo'), 'YYYY-MM-DD"T"HH24:MI'), ''),
        'situacao', a.situacao
      ) obj
    from concierge.avisos a
    where p_id is null or a.id = p_id
  ) x;
$function$;

comment on function public.mind_admin_read_home_notices(uuid) is
  'Avisos da Home V3 no formato do painel administrativo. Mais recente primeiro.';

-- ------------------------------------------------------------
-- Escrita
-- ------------------------------------------------------------
create or replace function public.mind_admin_mutate_home_notice(
  p_action text,
  p_id uuid,
  p_payload jsonb,
  p_expected_updated_at text,
  p_actor_id uuid,
  p_request_id uuid
)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public', 'summit_2026'
as $function$
declare
  v_role text;
  v_before jsonb;
  v_after jsonb;
  v_id uuid := p_id;
  v_fuso text;
  v_imediato boolean;
  v_disparo timestamptz;
  v_situacao text;
  v_so_estado boolean;
begin
  -- Mesmas regras de papel do `mind_admin_mutate_resource`.
  select role into v_role
  from public.mind_admin_users
  where user_id = p_actor_id and active;

  if v_role is null then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  end if;

  if p_action = 'criar' and v_role not in ('administrador','editor') then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  elsif p_action = 'atualizar' and v_role not in ('administrador','editor','aprovador') then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  elsif p_action in ('publicar','arquivar') and v_role not in ('administrador','aprovador') then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  elsif p_action not in ('criar','atualizar','publicar','arquivar') then
    raise exception using errcode = '22023', message = 'admin_validation:acao_invalida';
  end if;

  -- Transição de estado: encerrar, colocar no ar, arquivar. Um clique,
  -- sem formulário — e a tela não manda versão neles.
  v_so_estado := p_action = 'arquivar'
    or (p_action = 'atualizar' and (p_payload ? 'situacao') and not (p_payload ? 'titulo'));

  -- Travamento otimista: quem salva por cima de versão velha leva 409.
  -- Só vale para quem REESCREVE CONTEÚDO. Transição de estado é
  -- idempotente — o resultado não depende de qual era o texto —, então
  -- exigir versão ali impediria a ação sem proteger nada.
  if p_action <> 'criar' then
    if v_id is null then
      raise exception using errcode = '22023', message = 'admin_validation:id_obrigatorio';
    end if;
    v_before := public.mind_admin_read_home_notices(v_id)->0;
    if v_before is null then
      raise exception using errcode = 'P0002', message = 'admin_not_found';
    end if;
    if not v_so_estado then
      if p_expected_updated_at is null or btrim(p_expected_updated_at) = '' then
        raise exception using errcode = '22023', message = 'admin_validation:versao_obrigatoria';
      end if;
      if (v_before->>'atualizadoEm')::timestamptz <> p_expected_updated_at::timestamptz then
        raise exception using errcode = '40001', message = 'admin_conflict';
      end if;
    end if;
  end if;

  select coalesce(e.fuso, 'America/Sao_Paulo') into v_fuso
  from summit_2026.events e order by e.ativo desc, e.atualizado_em desc limit 1;
  v_fuso := coalesce(v_fuso, 'America/Sao_Paulo');

  if p_action in ('criar','atualizar') and not v_so_estado then
    if nullif(btrim(p_payload->>'titulo'), '') is null
       or nullif(btrim(p_payload->>'descricao'), '') is null then
      raise exception using errcode = '22023', message = 'admin_validation:campos_obrigatorios';
    end if;

    v_imediato := coalesce((p_payload->>'imediato')::boolean, false);

    -- Imediato entra no ar agora e ignora o horário do formulário; o
    -- resto fica agendado e entra sozinho quando a hora chegar.
    if v_imediato then
      v_disparo := clock_timestamp();
      v_situacao := 'no-ar';
    else
      if nullif(btrim(p_payload->>'disparoEm'), '') is null then
        raise exception using errcode = '22023', message = 'admin_validation:horario_obrigatorio';
      end if;
      v_disparo := (replace(p_payload->>'disparoEm', 'T', ' '))::timestamp at time zone v_fuso;
      v_situacao := 'agendado';
    end if;
  end if;

  if p_action = 'criar' then
    v_id := gen_random_uuid();
    insert into concierge.avisos (
      id, icone, titulo, subtitulo, descricao, imediato, disparo_em, situacao,
      event_id, criado_em, atualizado_em, atualizado_por
    ) values (
      v_id,
      coalesce(nullif(p_payload->>'icone',''), 'megafone'),
      p_payload->>'titulo',
      coalesce(p_payload->>'subtitulo',''),
      p_payload->>'descricao',
      v_imediato, v_disparo, v_situacao,
      (select e.id from summit_2026.events e order by e.ativo desc, e.atualizado_em desc limit 1),
      clock_timestamp(), clock_timestamp(), p_actor_id
    );

  elsif p_action = 'atualizar' and v_so_estado then
    -- Só o estado muda. O texto fica como está.
    v_situacao := p_payload->>'situacao';
    if v_situacao not in ('no-ar','encerrado') then
      -- 'agendado' precisa de horário, e 'rascunho' não tem botão. Quem
      -- quiser essas duas passa pela edição inteira, com formulário.
      raise exception using errcode = '22023', message = 'admin_validation:situacao_invalida';
    end if;
    update concierge.avisos set
      situacao = v_situacao,
      -- Colocar no ar é agora: sem isto o aviso voltaria com o horário
      -- antigo e a lista se ordenaria pelo passado.
      disparo_em = case when v_situacao = 'no-ar' then clock_timestamp() else disparo_em end,
      atualizado_em = clock_timestamp(),
      atualizado_por = p_actor_id
    where id = v_id;

  elsif p_action = 'atualizar' then
    update concierge.avisos set
      icone = coalesce(nullif(p_payload->>'icone',''), icone),
      titulo = p_payload->>'titulo',
      subtitulo = coalesce(p_payload->>'subtitulo', subtitulo),
      descricao = p_payload->>'descricao',
      imediato = v_imediato,
      disparo_em = v_disparo,
      -- Aviso encerrado não volta ao ar por edição de texto.
      situacao = case when situacao = 'encerrado' then 'encerrado' else v_situacao end,
      atualizado_em = clock_timestamp(),
      atualizado_por = p_actor_id
    where id = v_id;

  elsif p_action = 'publicar' then
    update concierge.avisos set
      situacao = 'no-ar',
      disparo_em = coalesce(disparo_em, clock_timestamp()),
      atualizado_em = clock_timestamp(),
      atualizado_por = p_actor_id
    where id = v_id;

  elsif p_action = 'arquivar' then
    update concierge.avisos set
      situacao = 'encerrado',
      atualizado_em = clock_timestamp(),
      atualizado_por = p_actor_id
    where id = v_id;
  end if;

  v_after := public.mind_admin_read_home_notices(v_id)->0;
  if v_after is null then
    raise exception using errcode = 'P0002', message = 'admin_not_found';
  end if;

  insert into public.mind_admin_audit(
    actor_user_id, action, resource, record_id, record_label, before_data, after_data, request_id
  ) values (
    p_actor_id, p_action, 'home_notices', v_id::text, v_after->>'titulo', v_before, v_after, p_request_id
  );

  return v_after;
exception
  when invalid_text_representation or datetime_field_overflow
    or check_violation or not_null_violation or foreign_key_violation then
    raise exception using errcode = '22023', message = 'admin_validation:dados_invalidos';
end;
$function$;

comment on function public.mind_admin_mutate_home_notice(text,uuid,jsonb,text,uuid,uuid) is
  'Escrita de avisos da Home V3 pelo painel: mesmas regras de papel, travamento e auditoria dos outros recursos.';

-- Quem chama é a Edge Function `mindagent-admin`, com a chave secreta.
revoke all on function public.mind_admin_read_home_notices(uuid) from public;
revoke all on function public.mind_admin_mutate_home_notice(text,uuid,jsonb,text,uuid,uuid) from public;
grant execute on function public.mind_admin_read_home_notices(uuid) to service_role;
grant execute on function public.mind_admin_mutate_home_notice(text,uuid,jsonb,text,uuid,uuid) to service_role;
