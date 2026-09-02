-- ============================================================
-- 04 · Visualização — qual home está no ar, e as trocas programadas
-- ============================================================
-- Projeto: mind-agent (ymnmotgglsrxmjmonwjz)
-- Depende de: nada. Pode ser aplicado antes ou depois do 01.
--
-- POR QUE NÃO TEM TABELA NOVA AQUI
-- O momento da home é configuração: uma escolha entre quatro
-- composições, com uma agenda de trocas. `concierge.config` existe para
-- exatamente isso — chave, valor jsonb, e um gatilho de revisão que já
-- guarda o histórico. Vinte e três chaves já moram lá (`evento`,
-- `jornada`, `proativo`, `vagas_limitadas`…). Criar duas tabelas para
-- uma linha de configuração seria inventar casa onde já tem.
--
-- A chave é `home`, no singular, como as outras:
--
--   {
--     "momento": "antes",
--     "modo": "manual",
--     "trocas": [
--       { "id": "...", "quando": "2026-09-16T07:00", "momento": "no-evento",
--         "nota": "abertura", "arquivada": false, "atualizadoEm": "..." }
--     ]
--   }
--
-- SEM CRON: em `modo = 'programado'`, quem lê aplica a regra — vale a
-- última troca cujo horário já passou. É a mesma decisão dos avisos.
-- `aplicada` não é guardada, é calculada: guardar exigiria alguém para
-- escrever, e esse alguém seria um job que pode não rodar.
--
-- Reversível: `drop function` nas duas e `delete from concierge.config
-- where chave = 'home'`.

insert into concierge.config (chave, valor, descricao)
values (
  'home',
  jsonb_build_object('momento', 'antes', 'modo', 'manual', 'trocas', '[]'::jsonb),
  'Home V3 do participante: qual das quatro composições está no ar e as trocas programadas. Escrita pelo painel (Home V3 › Visualização), leitura pelo bootstrap do app.'
)
on conflict (chave) do nothing;

-- ------------------------------------------------------------
-- Leitura — serve `home_state` e `home_schedule`
-- ------------------------------------------------------------
create or replace function public.mind_admin_read_home_config(
  p_resource text,
  -- text, não uuid: o registro de estado se chama 'home', e é esse o id
  -- que o painel coloca na URL.
  p_id text default null
)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'pg_catalog', 'public', 'summit_2026'
as $function$
declare
  v jsonb;
  v_quando timestamptz;
  v_fuso text;
  v_result jsonb;
begin
  select coalesce(c.valor, '{}'::jsonb), coalesce(c.atualizado_em, now())
    into v, v_quando
  from concierge.config c where c.chave = 'home';

  if v is null then
    v := jsonb_build_object('momento','antes','modo','manual','trocas','[]'::jsonb);
    v_quando := now();
  end if;

  select coalesce(e.fuso, 'America/Sao_Paulo') into v_fuso
  from summit_2026.events e order by e.ativo desc, e.atualizado_em desc limit 1;
  v_fuso := coalesce(v_fuso, 'America/Sao_Paulo');

  if p_resource = 'home_state' then
    -- Registro único, como `event`: id fixo para o painel ter o que editar.
    return jsonb_build_array(jsonb_build_object(
      'id', 'home',
      'criadoEm', v_quando,
      'atualizadoEm', v_quando,
      'atualizadoPor', null,
      'momento', coalesce(v->>'momento', 'antes'),
      'modo', coalesce(v->>'modo', 'manual')
    ));

  elsif p_resource = 'home_schedule' then
    select coalesce(jsonb_agg(x.obj order by x.quando), '[]'::jsonb)
      into v_result
    from (
      select troca->>'quando' as quando,
        jsonb_build_object(
          'id', troca->>'id',
          'criadoEm', coalesce(troca->>'criadoEm', v_quando::text),
          'atualizadoEm', coalesce(troca->>'atualizadoEm', v_quando::text),
          'atualizadoPor', troca->>'atualizadoPor',
          'quando', troca->>'quando',
          'momento', troca->>'momento',
          'nota', coalesce(troca->>'nota', ''),
          -- Calculada, não guardada: a troca "já aconteceu" quando o
          -- horário dela passou, e é isso que o app também enxerga.
          'aplicada', (replace(troca->>'quando','T',' ')::timestamp at time zone v_fuso) <= now()
        ) as obj
      from jsonb_array_elements(coalesce(v->'trocas', '[]'::jsonb)) troca
      where coalesce((troca->>'arquivada')::boolean, false) is false
        and (p_id is null or troca->>'id' = p_id)
    ) x;
    return v_result;
  end if;

  raise exception using errcode = '22023', message = 'admin_validation:recurso_nao_suportado';
end;
$function$;

comment on function public.mind_admin_read_home_config(text, text) is
  'Momento da home e trocas programadas, no formato do painel administrativo.';

-- ------------------------------------------------------------
-- Escrita
-- ------------------------------------------------------------
create or replace function public.mind_admin_mutate_home_config(
  p_action text,
  p_resource text,
  p_id text,
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
  v jsonb;
  v_quando timestamptz;
  v_before jsonb;
  v_after jsonb;
  v_trocas jsonb;
  v_id text := p_id;
  v_momento text;
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
  elsif p_action not in ('criar','atualizar','arquivar') then
    raise exception using errcode = '22023', message = 'admin_validation:acao_invalida';
  end if;

  select coalesce(c.valor, '{}'::jsonb), coalesce(c.atualizado_em, now())
    into v, v_quando
  from concierge.config c where c.chave = 'home';
  if v is null then
    v := jsonb_build_object('momento','antes','modo','manual','trocas','[]'::jsonb);
  end if;
  v_trocas := coalesce(v->'trocas', '[]'::jsonb);

  -- Trocar a composição no ar e arquivar uma troca são ações de um
  -- clique, sem formulário — e a tela não manda versão nelas.
  --
  -- `home_state` inteiro são dois campos de chave: não há texto para
  -- duas pessoas escreverem por cima uma da outra, e o último clique
  -- ganhar é o comportamento certo para um interruptor.
  v_so_estado := p_action = 'arquivar' or p_resource = 'home_state';

  -- Travamento otimista, só para quem reescreve conteúdo — que aqui é a
  -- edição de uma troca programada (horário, momento e nota).
  if p_action <> 'criar' then
    v_before := public.mind_admin_read_home_config(p_resource, v_id)->0;
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

  if p_resource = 'home_state' then
    if p_action <> 'atualizar' then
      raise exception using errcode = '22023', message = 'admin_validation:acao_nao_suportada';
    end if;
    v_momento := coalesce(p_payload->>'momento', v->>'momento', 'antes');
    if v_momento not in ('antes','no-evento','entre-dias','depois') then
      raise exception using errcode = '22023', message = 'admin_validation:momento_invalido';
    end if;
    v := v || jsonb_build_object(
      'momento', v_momento,
      'modo', coalesce(p_payload->>'modo', v->>'modo', 'manual')
    );

  elsif p_resource = 'home_schedule' then
    if p_action = 'criar' then
      if nullif(btrim(p_payload->>'quando'), '') is null then
        raise exception using errcode = '22023', message = 'admin_validation:horario_obrigatorio';
      end if;
      v_momento := p_payload->>'momento';
      if v_momento not in ('antes','no-evento','entre-dias','depois') then
        raise exception using errcode = '22023', message = 'admin_validation:momento_invalido';
      end if;
      v_id := gen_random_uuid()::text;
      v_trocas := v_trocas || jsonb_build_array(jsonb_build_object(
        'id', v_id,
        'quando', p_payload->>'quando',
        'momento', v_momento,
        'nota', coalesce(p_payload->>'nota',''),
        'arquivada', false,
        'criadoEm', clock_timestamp(),
        'atualizadoEm', clock_timestamp(),
        'atualizadoPor', p_actor_id::text
      ));

    elsif p_action in ('atualizar','arquivar') then
      -- Reescreve a lista inteira trocando só a que tem este id.
      -- Arquivar guarda em vez de apagar: o histórico continua auditável.
      select coalesce(jsonb_agg(
        case when troca->>'id' = v_id then
          troca || case when p_action = 'arquivar'
            then jsonb_build_object('arquivada', true)
            else jsonb_build_object(
              'quando', coalesce(p_payload->>'quando', troca->>'quando'),
              'momento', coalesce(p_payload->>'momento', troca->>'momento'),
              'nota', coalesce(p_payload->>'nota', troca->>'nota'))
          end || jsonb_build_object(
            'atualizadoEm', clock_timestamp(),
            'atualizadoPor', p_actor_id::text)
        else troca end
      ), '[]'::jsonb)
        into v_trocas
      from jsonb_array_elements(v_trocas) troca;
    end if;

    v := v || jsonb_build_object('trocas', v_trocas);

  else
    raise exception using errcode = '22023', message = 'admin_validation:recurso_nao_suportado';
  end if;

  insert into concierge.config (chave, valor, descricao, atualizado_em, atualizado_por)
  values ('home', v, 'Home V3 do participante: composição no ar e trocas programadas.',
          clock_timestamp(), p_actor_id::text)
  on conflict (chave) do update set
    valor = excluded.valor,
    atualizado_em = excluded.atualizado_em,
    atualizado_por = excluded.atualizado_por;

  v_after := public.mind_admin_read_home_config(p_resource, v_id)->0;
  if v_after is null and p_action <> 'arquivar' then
    raise exception using errcode = 'P0002', message = 'admin_not_found';
  end if;

  insert into public.mind_admin_audit(
    actor_user_id, action, resource, record_id, record_label, before_data, after_data, request_id
  ) values (
    p_actor_id, p_action, p_resource, coalesce(v_id, 'home'),
    coalesce(v_after->>'momento', v->>'momento'), v_before, v_after, p_request_id
  );

  -- Arquivar devolve o registro que saiu de circulação, para o painel
  -- ter o que mostrar em vez de um corpo vazio.
  return coalesce(v_after, v_before);
exception
  when invalid_text_representation or datetime_field_overflow
    or check_violation or not_null_violation then
    raise exception using errcode = '22023', message = 'admin_validation:dados_invalidos';
end;
$function$;

comment on function public.mind_admin_mutate_home_config(text,text,text,jsonb,text,uuid,uuid) is
  'Escrita do momento da home e das trocas programadas, com as regras de papel, travamento e auditoria dos outros recursos.';

-- Quem chama é a Edge Function `mindagent-admin`, com a chave secreta.
revoke all on function public.mind_admin_read_home_config(text,text) from public;
revoke all on function public.mind_admin_mutate_home_config(text,text,text,jsonb,text,uuid,uuid) from public;
grant execute on function public.mind_admin_read_home_config(text,text) to service_role;
grant execute on function public.mind_admin_mutate_home_config(text,text,text,jsonb,text,uuid,uuid) to service_role;
