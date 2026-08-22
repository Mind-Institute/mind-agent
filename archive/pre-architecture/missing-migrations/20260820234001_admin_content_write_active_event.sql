alter table mind.sessions alter column fim drop not null;

create or replace function public.mind_admin_mutate_resource(
  p_action text,
  p_resource text,
  p_id uuid,
  p_payload jsonb,
  p_expected_updated_at text,
  p_actor_id uuid,
  p_request_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, mind, auth
as $$
declare
  v_role text;
  v_before jsonb;
  v_after jsonb;
  v_id uuid := p_id;
  v_event_id uuid;
  v_venue_id uuid;
  v_timezone text;
  v_day date;
  v_start timestamptz;
  v_end timestamptz;
  v_label text;
  v_status text;
begin
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

  if p_action <> 'criar' then
    if v_id is null then
      raise exception using errcode = '22023', message = 'admin_validation:id_obrigatorio';
    end if;
    v_before := public.mind_admin_read_resource(p_resource, v_id)->0;
    if v_before is null then
      raise exception using errcode = 'P0002', message = 'admin_not_found';
    end if;
    if p_expected_updated_at is null or btrim(p_expected_updated_at) = '' then
      raise exception using errcode = '22023', message = 'admin_validation:versao_obrigatoria';
    end if;
    if (v_before->>'atualizadoEm')::timestamptz <> p_expected_updated_at::timestamptz then
      raise exception using errcode = '40001', message = 'admin_conflict';
    end if;
  end if;

  select id, fuso into v_event_id, v_timezone
  from mind.events
  order by ativo desc, atualizado_em desc
  limit 1;
  if v_event_id is null then
    raise exception using errcode = 'P0002', message = 'admin_not_found:evento_padrao';
  end if;

  if p_resource = 'event' then
    if p_action <> 'atualizar' then
      raise exception using errcode = '22023', message = 'admin_validation:acao_nao_suportada';
    end if;
    if nullif(btrim(p_payload->>'nome'), '') is null
       or nullif(btrim(p_payload->>'slug'), '') is null
       or nullif(btrim(p_payload->>'dataInicio'), '') is null
       or nullif(btrim(p_payload->>'dataFim'), '') is null then
      raise exception using errcode = '22023', message = 'admin_validation:campos_obrigatorios';
    end if;
    update mind.events set
      nome = p_payload->>'nome',
      slug = p_payload->>'slug',
      dias = case when p_payload->>'dataInicio' = p_payload->>'dataFim'
        then array[(p_payload->>'dataInicio')::date]
        else array[(p_payload->>'dataInicio')::date, (p_payload->>'dataFim')::date] end,
      local = p_payload->>'local',
      cidade = p_payload->>'cidade',
      fuso = p_payload->>'fusoHorario',
      ativo = coalesce((p_payload->>'ativo')::boolean, ativo),
      atualizado_em = clock_timestamp()
    where id = v_id;

    insert into public.mind_admin_event_details (
      event_id, descricao, regra_reserva, regra_vagas, updated_by, updated_at
    ) values (
      v_id, coalesce(p_payload->>'descricao',''), coalesce(p_payload->>'regraReserva',''),
      coalesce(p_payload->>'regraVagas',''), p_actor_id, clock_timestamp()
    ) on conflict (event_id) do update set
      descricao = excluded.descricao,
      regra_reserva = excluded.regra_reserva,
      regra_vagas = excluded.regra_vagas,
      updated_by = excluded.updated_by,
      updated_at = excluded.updated_at;

    insert into mind.event_rules (chave,titulo,texto,aplica_em,prioridade,ativo,atualizado_em,event_id)
    values
      ('admin-regra-reserva','Regras de reserva',coalesce(p_payload->>'regraReserva',''),array['reserva'],0,true,clock_timestamp(),v_id),
      ('admin-regra-vagas','Regras de vagas',coalesce(p_payload->>'regraVagas',''),array['vagas'],0,true,clock_timestamp(),v_id)
    on conflict (chave) do update set texto=excluded.texto, ativo=true, atualizado_em=excluded.atualizado_em, event_id=excluded.event_id;

  elsif p_resource = 'sessions' then
    if p_action = 'criar' then
      v_id := gen_random_uuid();
      v_day := (p_payload->>'dia')::date;
      v_start := ((p_payload->>'dia') || ' ' || (p_payload->>'inicio'))::timestamp at time zone v_timezone;
      v_end := case when coalesce(p_payload->>'fim','') = '' then null
        else ((p_payload->>'dia') || ' ' || (p_payload->>'fim'))::timestamp at time zone v_timezone end;
      insert into mind.sessions (
        id,titulo,descricao,dia,inicio,fim,espaco_id,tipo,formato,trilhas,precisa_reserva,
        vagas_total,vagas_disponiveis,topicos_aprendizado,resultados,nivel,event_id,atualizado_em
      ) values (
        v_id,p_payload->>'titulo',coalesce(p_payload->>'descricao',''),v_day,v_start,v_end,
        nullif(p_payload->>'espacoId','')::uuid,
        case when p_payload->>'tipo'='em_curadoria' then 'em-curadoria' else p_payload->>'tipo' end,
        p_payload->>'formato',array(select jsonb_array_elements_text(coalesce(p_payload->'trilhas','[]'::jsonb))),
        coalesce((p_payload->>'necessitaReserva')::boolean,false),
        nullif(p_payload->>'vagasTotais','')::integer,nullif(p_payload->>'vagasDisponiveis','')::integer,
        coalesce(p_payload->'temas','[]'::jsonb),coalesce(p_payload->'resultadosEsperados','[]'::jsonb),
        nullif(p_payload->>'nivel',''),v_event_id,clock_timestamp()
      );
      v_status := coalesce(p_payload->>'status','rascunho');
      insert into public.mind_admin_editorial(resource,record_id,status,updated_by,updated_at)
      values('sessions',v_id,v_status,p_actor_id,clock_timestamp());
    elsif p_action = 'atualizar' then
      v_day := coalesce(nullif(p_payload->>'dia','')::date,(v_before->>'dia')::date);
      v_start := (v_day::text || ' ' || coalesce(nullif(p_payload->>'inicio',''),v_before->>'inicio'))::timestamp at time zone v_timezone;
      v_end := case when p_payload ? 'fim' and coalesce(p_payload->>'fim','') = '' then null
        else (v_day::text || ' ' || coalesce(nullif(p_payload->>'fim',''),v_before->>'fim'))::timestamp at time zone v_timezone end;
      update mind.sessions set
        titulo=coalesce(p_payload->>'titulo',titulo), descricao=coalesce(p_payload->>'descricao',descricao),
        dia=v_day,inicio=v_start,fim=v_end,
        espaco_id=case when p_payload ? 'espacoId' then nullif(p_payload->>'espacoId','')::uuid else espaco_id end,
        tipo=case when p_payload ? 'tipo' then case when p_payload->>'tipo'='em_curadoria' then 'em-curadoria' else p_payload->>'tipo' end else tipo end,
        formato=coalesce(p_payload->>'formato',formato),
        trilhas=case when p_payload ? 'trilhas' then array(select jsonb_array_elements_text(p_payload->'trilhas')) else trilhas end,
        precisa_reserva=case when p_payload ? 'necessitaReserva' then (p_payload->>'necessitaReserva')::boolean else precisa_reserva end,
        vagas_total=case when p_payload ? 'vagasTotais' then nullif(p_payload->>'vagasTotais','')::integer else vagas_total end,
        vagas_disponiveis=case when p_payload ? 'vagasDisponiveis' then nullif(p_payload->>'vagasDisponiveis','')::integer else vagas_disponiveis end,
        topicos_aprendizado=case when p_payload ? 'temas' then p_payload->'temas' else topicos_aprendizado end,
        resultados=case when p_payload ? 'resultadosEsperados' then p_payload->'resultadosEsperados' else resultados end,
        nivel=case when p_payload ? 'nivel' then nullif(p_payload->>'nivel','') else nivel end,
        atualizado_em=clock_timestamp()
      where id=v_id;
      insert into public.mind_admin_editorial(resource,record_id,status,updated_by,updated_at)
      values('sessions',v_id,coalesce(p_payload->>'status',v_before->>'status'),p_actor_id,clock_timestamp())
      on conflict(resource,record_id) do update set status=excluded.status,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
    elsif p_action in ('publicar','arquivar') then
      update public.mind_admin_editorial set
        status=case when p_action='publicar' then 'publicado' else 'arquivado' end,
        published_at=case when p_action='publicar' then clock_timestamp() else published_at end,
        published_by=case when p_action='publicar' then p_actor_id else published_by end,
        updated_by=p_actor_id,updated_at=clock_timestamp()
      where resource='sessions' and record_id=v_id;
    end if;

    if p_action in ('criar','atualizar') and p_payload ? 'palestranteIds' then
      delete from mind.session_speakers where sessao_id=v_id;
      insert into mind.session_speakers(sessao_id,palestrante_id)
      select v_id, value::uuid from jsonb_array_elements_text(p_payload->'palestranteIds') value;
    end if;

  elsif p_resource = 'speakers' then
    if p_action = 'criar' then
      v_id := gen_random_uuid();
      insert into mind.speakers(id,nome,cargo,organizacao,bio,foto_url,destaque,temas,atualizado_em)
      values(v_id,p_payload->>'nome',coalesce(p_payload->>'cargo',''),coalesce(p_payload->>'organizacao',''),
        coalesce(p_payload->>'biografia',''),nullif(p_payload->>'foto',''),coalesce((p_payload->>'destaque')::boolean,false),
        array(select jsonb_array_elements_text(coalesce(p_payload->'temas','[]'::jsonb))),clock_timestamp());
      insert into public.mind_admin_editorial(resource,record_id,status,updated_by,updated_at)
      values('speakers',v_id,coalesce(p_payload->>'status','rascunho'),p_actor_id,clock_timestamp());
    elsif p_action = 'atualizar' then
      update mind.speakers set
        nome=coalesce(p_payload->>'nome',nome),cargo=coalesce(p_payload->>'cargo',cargo),
        organizacao=coalesce(p_payload->>'organizacao',organizacao),bio=coalesce(p_payload->>'biografia',bio),
        foto_url=case when p_payload ? 'foto' then nullif(p_payload->>'foto','') else foto_url end,
        destaque=case when p_payload ? 'destaque' then (p_payload->>'destaque')::boolean else destaque end,
        temas=case when p_payload ? 'temas' then array(select jsonb_array_elements_text(p_payload->'temas')) else temas end,
        atualizado_em=clock_timestamp()
      where id=v_id;
      insert into public.mind_admin_editorial(resource,record_id,status,updated_by,updated_at)
      values('speakers',v_id,coalesce(p_payload->>'status',v_before->>'status'),p_actor_id,clock_timestamp())
      on conflict(resource,record_id) do update set status=excluded.status,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
    elsif p_action in ('publicar','arquivar') then
      update public.mind_admin_editorial set
        status=case when p_action='publicar' then 'publicado' else 'arquivado' end,
        published_at=case when p_action='publicar' then clock_timestamp() else published_at end,
        published_by=case when p_action='publicar' then p_actor_id else published_by end,
        updated_by=p_actor_id,updated_at=clock_timestamp()
      where resource='speakers' and record_id=v_id;
    end if;

  elsif p_resource = 'spaces' then
    if p_action = 'criar' then
      v_id := gen_random_uuid();
      select id into v_venue_id from mind.venues where event_id=v_event_id order by ativo desc limit 1;
      insert into mind.locations(id,nome,slug,tipo,aliases,descricao,como_chegar,event_id,venue_id,parent_id,andar,coordenadas_mapa,acessibilidade,ativo,atualizado_em)
      values(v_id,p_payload->>'nome',p_payload->>'slug',p_payload->>'tipo',
        array(select jsonb_array_elements_text(coalesce(p_payload->'aliases','[]'::jsonb))),coalesce(p_payload->>'descricao',''),
        coalesce(p_payload->>'comoChegar',''),v_event_id,v_venue_id,nullif(p_payload->>'espacoPaiId','')::uuid,
        nullif(p_payload->>'andar',''),jsonb_build_object('x_percent',p_payload->'coordenadaX','y_percent',p_payload->'coordenadaY'),
        jsonb_build_object('acessivel',coalesce((p_payload->>'acessivel')::boolean,false),'observacao',coalesce(p_payload->>'observacaoAcessibilidade',''),'verificada',true),
        coalesce((p_payload->>'ativo')::boolean,true),clock_timestamp());
    elsif p_action = 'atualizar' then
      update mind.locations set
        nome=coalesce(p_payload->>'nome',nome),slug=coalesce(p_payload->>'slug',slug),tipo=coalesce(p_payload->>'tipo',tipo),
        aliases=case when p_payload ? 'aliases' then array(select jsonb_array_elements_text(p_payload->'aliases')) else aliases end,
        descricao=coalesce(p_payload->>'descricao',descricao),como_chegar=coalesce(p_payload->>'comoChegar',como_chegar),
        parent_id=case when p_payload ? 'espacoPaiId' then nullif(p_payload->>'espacoPaiId','')::uuid else parent_id end,
        andar=case when p_payload ? 'andar' then nullif(p_payload->>'andar','') else andar end,
        coordenadas_mapa=case when p_payload ? 'coordenadaX' or p_payload ? 'coordenadaY' then
          jsonb_build_object('x_percent',p_payload->'coordenadaX','y_percent',p_payload->'coordenadaY') else coordenadas_mapa end,
        acessibilidade=case when p_payload ? 'acessivel' or p_payload ? 'observacaoAcessibilidade' then
          jsonb_build_object('acessivel',coalesce((p_payload->>'acessivel')::boolean,false),'observacao',coalesce(p_payload->>'observacaoAcessibilidade',''),'verificada',true)
          else acessibilidade end,
        ativo=case when p_payload ? 'ativo' then (p_payload->>'ativo')::boolean else ativo end,
        atualizado_em=clock_timestamp()
      where id=v_id;
    elsif p_action = 'arquivar' then
      update mind.locations set ativo=false,atualizado_em=clock_timestamp() where id=v_id;
    else
      raise exception using errcode='22023',message='admin_validation:acao_nao_suportada';
    end if;
  else
    raise exception using errcode='22023',message='admin_validation:recurso_nao_suportado';
  end if;

  v_after := public.mind_admin_read_resource(p_resource,v_id)->0;
  if v_after is null then
    raise exception using errcode='P0002',message='admin_not_found';
  end if;
  v_label := coalesce(v_after->>'titulo',v_after->>'nome',v_id::text);

  insert into public.mind_admin_audit(
    actor_user_id,action,resource,record_id,record_label,before_data,after_data,request_id
  ) values (
    p_actor_id,p_action,p_resource,v_id::text,v_label,v_before,v_after,p_request_id
  );

  return v_after;
exception
  when invalid_text_representation or datetime_field_overflow or check_violation or not_null_violation or foreign_key_violation then
    raise exception using errcode='22023',message='admin_validation:dados_invalidos';
end;
$$;

revoke all on function public.mind_admin_mutate_resource(text,text,uuid,jsonb,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.mind_admin_mutate_resource(text,text,uuid,jsonb,text,uuid,uuid) to service_role;
