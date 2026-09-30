-- Fumaça pós-rename: chama, dentro da MESMA transação da migration (que será desfeita na
-- prova), as funções e views que citavam as colunas antigas. Referência esquecida a coluna
-- explode como undefined_column (42703: "column ... does not exist" / "record has no field") e
-- derruba a prova. Função já morta antes do rename (relação inexistente: summit.sessions,
-- engagement.checkout_clicks) vira nota, não falha. Termina SEMPRE com exception: o texto
-- "FUMACA_OK" é o resultado da prova e garante o rollback.
do $$
declare
  v_conv uuid; v_pessoa uuid; v_email text; v_auth uuid; v_evento uuid; t text; n int; v_nova uuid;
  stmts text[]; notas text := ''; ok int := 0;
begin
  select c.id, c.mind_id into v_conv, v_pessoa from engagement.conversas c where c.mind_id is not null order by c.ultima_atividade desc nulls last limit 1;
  select p.email into v_email from pessoas.pessoas p where p.email is not null and p.fundida_em is null order by p.criado_em desc limit 1;
  select i.identificador::uuid into v_auth from engagement.identidades i where i.canal = 'auth_user' limit 1;
  if to_regclass('engagement.checkout_eventos') is not null then
    execute 'select id from engagement.checkout_eventos order by 1 limit 1' into v_evento;
  end if;

  stmts := array[
    format('select public.mind_agent_context(%L::uuid)', v_conv),
    format('select public.mind_conversa_estado(%L::uuid)', v_conv),
    format('select public.analise_montar_contexto(%L::uuid)', v_conv),
    format('select public.silence_compra_summit_2026(%L::uuid)', v_conv),
    format('select public.mind_kit_customer_intelligence(%L::uuid, ''{}''::jsonb)', v_conv),
    format('select public.mind_kit_programacao_filtrada(%L::uuid, ''{}''::jsonb)', v_conv),
    format('select public.mind_pessoa_fatos(%L::uuid)', v_pessoa),
    format('select public.mind_engagement_fatos(%L::uuid)', v_pessoa),
    format('select public.mind_crm_fatos(%L::uuid)', v_pessoa),
    format('select public.mind_credenciamento_fatos(%L::uuid)', v_pessoa),
    format('select public.mind_customer_intelligence(%L::uuid)', v_pessoa),
    format('select public.mind_crm_comercial(%L::uuid)', v_pessoa),
    format('select public.mind_crm_vincular_pessoa(%L::uuid)', v_pessoa),
    format('select public.mind_pessoa_enriquecer(%L::uuid)', v_pessoa),
    format('select public.mind_pessoa_completar(%L::uuid, null, null, null)', v_pessoa),
    format('select concierge.resumo_do_dia(%L::uuid, current_date)', v_pessoa),
    format('select crm.buscar_pessoa(%L, null, ''fumaca'')', v_email),
    format('select crm.contexto_comercial(%L, null, ''fumaca'')', v_email),
    'select count(*) from public.mind_pendencias_listar(''pendente'', null, 5, 0)',
    'select count(*) from public.summit_status_pendentes(1)',
    'select count(*) from public.hubspot_commercial_candidates(1, null)',
    'select public.mind_recovery_refresh(1)',
    'select public.mind_checkout_abandonment_refresh()',
    'select count(*) from public.summit_contato_criar_pendentes(1)',
    format('select public.mind_identificador_declarado_registrar(%L::uuid, ''whatsapp'', '''')', v_pessoa),
    format('select public.mind_play_chamada_iniciar(''fumaca'', %L::uuid, %L, ''{}''::jsonb, null)', v_pessoa, 'fumaca-' || v_pessoa::text),
    'select public.mind_identidade_enriquecer_todas(1, true)',
    'select public.mind_identidade_criar_faltantes(''crm.leads_capturados''::regclass, 1, true)'
  ];
  if v_auth is not null then
    stmts := stmts || array[
      format('select public.mindagent_chat_start(%L::uuid, ''fumaca-device'', ''fumaca'', md5(''fumaca''), null)', v_auth),
      format('select api.me(%L)', 'fumaca-token'),
      format('select api.quem_sou(%L)', 'fumaca-token'),
      format('select api.my_context(%L)', 'fumaca-token'),
      format('select api.my_data(%L)', 'fumaca-token')];
  end if;
  if v_evento is not null then
    stmts := stmts || array[format('select public.mind_checkout_event_purchase_status(%L::uuid)', v_evento)];
  end if;
  -- views que citavam as colunas
  foreach t in array array['credenciamento_summit_2026.v_participantes','engagement.v_pessoa','concierge.v_funil_valor','concierge.v_aderencia_por_area',
                           'intelligence.v_recovery_inbox_actionable','api.pessoas_publicas','api.programa_pessoas','eduzz.v_ingressos','eduzz.v_vendas',
                           'intelligence.v_conversoes_agente','api.admin_pessoas','pessoas.v_pessoa_360','credenciamento_summit_2026.v_inscritos_e_presenca'] loop
    if to_regclass(t) is not null then
      stmts := stmts || array[format('select count(*) from (select * from %s limit 5) s', t)];
    end if;
  end loop;

  foreach t in array stmts loop
    begin
      execute t;
      ok := ok + 1;
    exception
      when undefined_column then
        raise exception 'FUMACA_FALHOU coluna: % -> %', t, sqlerrm;
      when undefined_table then
        notas := notas || format(E'\n  ja morta antes do rename (relacao inexistente): %s -> %s', left(t, 70), sqlerrm);
      when others then
        if sqlerrm ~* 'mind_id|pessoa_id|participante_id|participant_id|person_id|has no field' then
          raise exception 'FUMACA_FALHOU (%): % -> %', sqlstate, t, sqlerrm;
        end if;
        notas := notas || format(E'\n  outro erro (%s), nao e de coluna: %s -> %s', sqlstate, left(t, 70), left(sqlerrm, 120));
    end;
  end loop;

  -- o trigger da Regra #1 continua carimbando mind_id
  insert into crm.leads_capturados (firstname, lastname, email) values ('Fumaca', 'Rename', 'fumaca.rename.' || substr(md5(random()::text),1,8) || '@exemplo.invalid')
    returning mind_id into v_nova;
  if v_nova is null then raise exception 'FUMACA_FALHOU: trigger nao carimbou mind_id'; end if;
  -- v_pessoa_360 expõe mind_id e o resolver devolve a chave pessoa_id
  if not exists (select 1 from pessoas.v_pessoa_360 where mind_id = v_nova) then raise exception 'FUMACA_FALHOU: v_pessoa_360 sem a pessoa nova'; end if;
  if (public.mind_identidade_resolver(jsonb_build_object('email', v_email), null, 'fumaca', null, false)->>'pessoa_id') is null then
    raise exception 'FUMACA_FALHOU: resolver nao devolveu a chave pessoa_id';
  end if;

  raise exception 'FUMACA_OK: % chamadas ok, % statements; trigger carimbou %; notas:%', ok, array_length(stmts, 1), v_nova, coalesce(nullif(notas, ''), ' nenhuma');
end $$;
