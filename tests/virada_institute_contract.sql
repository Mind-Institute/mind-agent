-- Contrato da virada do Passo 5: o site do Institute lê o catálogo (a migration *_virada_institute_le_o_catalogo
-- e, logo depois dela, *_bump_fora_da_lista_de_precos). Roda depois das duas e sempre termina em
-- rollback: a exceção VIRADA_OK é o resultado. Usa o administrador ativo de mind_admin_users como autor das
-- edições pelo painel e a pessoa de seguranca.equipe para falar com o /admin do Join; tudo desfeito no fim.
begin;

-- A recusa esperada pelo painel, com o motivo exato.
create function pg_temp.recusa(p_action text, p_id uuid, p_payload jsonb, p_versao text, p_ator uuid, p_motivo text)
returns void
language plpgsql
as $f$
declare
  v_msg text;
begin
  begin
    perform public.mind_admin_mutate_ofertas(p_action, p_id, p_payload, p_versao, p_ator, gen_random_uuid());
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg is distinct from p_motivo then
      raise exception '% %: esperava %, veio %', p_action, p_payload, p_motivo, v_msg;
    end if;
    return;
  end;
  raise exception '% %: esperava a recusa %, e passou', p_action, p_payload, p_motivo;
end
$f$;

-- A casa antiga recusa a escrita com a mensagem de onde editar agora.
create function pg_temp.congelada(p_sql text)
returns void
language plpgsql
as $f$
declare
  v_estado text;
  v_msg text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    if v_estado <> '42501'
       or v_msg <> 'Preços, ofertas e bumps agora se editam no painel do Mind. Nada foi alterado.' then
      raise exception '%: esperava a casa congelada, veio % %', p_sql, v_estado, v_msg;
    end if;
    return;
  end;
  raise exception '%: a casa antiga aceitou a escrita', p_sql;
end
$f$;

do $$
declare
  v_ator uuid;
  v_equipe uuid;
  v_codigo text;
  v_id uuid;
  v_versao text;
  v_prod_a text;
  v_prod_journey text;
  v_prog_a text;
  v_prog_journey text;
  r jsonb;
  v_valendo uuid;
  v_agendada uuid;
  v_rascunho uuid;
  v_upgrade uuid;
  v_bump uuid;
  v_bloco text;
begin
  select user_id into v_ator from public.mind_admin_users
   where active and role in ('administrador', 'editor', 'aprovador') limit 1;
  select user_id into v_equipe from seguranca.equipe limit 1;
  if v_ator is null or v_equipe is null then
    raise exception 'faltam o administrador do painel ou a equipe do Join para o teste'; end if;

  -- 1. A virada está aplicada: a porta lê o catálogo, a casa antiga congelou, as funções de pedido mudaram.
  if to_regclass('catalogo.institute_ofertas') is null then raise exception 'sem catalogo.institute_ofertas'; end if;
  if not exists (select 1 from pg_depend d join pg_rewrite rw on rw.oid = d.objid
                  where d.classid = 'pg_rewrite'::regclass and d.refclassid = 'pg_class'::regclass
                    and rw.ev_class = 'api.ofertas'::regclass and d.refobjid = 'catalogo.institute_ofertas'::regclass)
     or not exists (select 1 from pg_depend d join pg_rewrite rw on rw.oid = d.objid
                     where d.classid = 'pg_rewrite'::regclass and d.refclassid = 'pg_class'::regclass
                       and rw.ev_class = 'api.bump_regras'::regclass and d.refobjid = 'catalogo.institute_ofertas'::regclass)
     or not exists (select 1 from pg_depend d join pg_rewrite rw on rw.oid = d.objid
                     where d.classid = 'pg_rewrite'::regclass and d.refclassid = 'pg_class'::regclass
                       and rw.ev_class = 'api.oferta_inclui'::regclass and d.refobjid = 'catalogo.institute_ofertas'::regclass)
     or exists (select 1 from pg_depend d join pg_rewrite rw on rw.oid = d.objid join pg_class c on c.oid = d.refobjid
                 where d.classid = 'pg_rewrite'::regclass and d.refclassid = 'pg_class'::regclass
                   and rw.ev_class in ('api.ofertas'::regclass, 'api.bump_regras'::regclass, 'api.oferta_inclui'::regclass)
                   and c.oid in ('institute.ofertas'::regclass, 'institute.oferta_bonus'::regclass, 'institute.bump_regras'::regclass)) then
    raise exception 'uma porta do site ainda lê a casa antiga'; end if;
  if (select count(*) from pg_trigger
       where tgname = 'casa_antiga_congelada' and not tgisinternal
         and tgrelid in ('institute.ofertas'::regclass, 'institute.oferta_bonus'::regclass, 'institute.bump_regras'::regclass)) <> 3 then
    raise exception 'a casa antiga não está congelada nas 3 tabelas'; end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'api' and p.proname in ('criar_pedido', 'validar_cupom', 'cadastrar_compra_manual')
                and (p.prosrc ~ 'institute\.ofertas' or p.prosrc !~ 'catalogo\.institute_ofertas')) then
    raise exception 'função de pedido ainda lê a casa antiga'; end if;

  -- 2. A carga: cada linha antiga no catálogo, com a origem; os 2 testes como histórico; o teste sem
  --    programa sem preço; cada outro código antigo vendável com o mesmo código.
  if (select count(*) from catalogo.ofertas where origem->>'tabela' = 'institute.ofertas')
     <> (select count(*) from institute.ofertas) then raise exception 'carga: ofertas'; end if;
  if (select count(*) from catalogo.ofertas where origem->>'tabela' = 'institute.ofertas' and historico) <> 2
     or exists (select 1 from catalogo.ofertas where origem->>'tabela' = 'institute.ofertas' and historico and ativo) then
    raise exception 'carga: os testes deviam ser histórico desligado'; end if;
  if exists (select 1 from catalogo.oferta_precos where codigo = 'teste-um-centavo') then
    raise exception 'carga: o teste sem programa não devia ter preço'; end if;
  if exists (select 1 from institute.ofertas io
              where io.programa_codigo is not null
                and not exists (select 1 from catalogo.oferta_precos op where op.codigo = io.codigo)) then
    raise exception 'carga: código antigo sem preço no catálogo'; end if;
  if (select count(*) from catalogo.oferta_inclui where origem->>'tabela' = 'institute.oferta_bonus')
     <> (select count(*) from institute.oferta_bonus)
     or (select count(*) from catalogo.oferta_requer where origem->>'tabela' = 'institute.bump_regras')
     <> (select count(*) from institute.bump_regras) then
    raise exception 'carga: bônus ou regras de bump'; end if;
  -- O ingresso do Summit 2027 é bônus, mas não é programa do Institute: não abre acesso a nada.
  if exists (select 1 from api.oferta_inclui i
              where not exists (select 1 from institute.programas pr where pr.codigo = i.programa_codigo)) then
    raise exception 'api.oferta_inclui com algo que não é programa do Institute'; end if;

  -- 3. Quem lê o catálogo: os produtos do Institute, e só eles.
  if exists (select 1 from catalogo.produtos p
              where exists (select 1 from institute.programas pr where pr.produto_codigo = p.codigo)
                and not catalogo.produto_tem_leitor(p.id))
     or exists (select 1 from catalogo.produtos p
                 where not exists (select 1 from institute.programas pr where pr.produto_codigo = p.codigo)
                   and catalogo.produto_tem_leitor(p.id)) then
    raise exception 'leitor: produto do Institute sem leitor, ou outro com'; end if;

  -- 4. A casa antiga não aceita escrita nenhuma, nem pelo /admin do Join.
  perform pg_temp.congelada('update institute.ofertas set nome = nome where false');
  perform pg_temp.congelada('delete from institute.ofertas where false');
  perform pg_temp.congelada('insert into institute.oferta_bonus (oferta_codigo, nome) select codigo, nome from institute.ofertas where false');
  perform pg_temp.congelada('update institute.oferta_bonus set nome = nome where false');
  perform pg_temp.congelada('update institute.bump_regras set ativo = ativo where false');
  perform pg_temp.congelada('truncate institute.bump_regras');
  perform set_config('request.jwt.claims', json_build_object('sub', v_equipe, 'role', 'authenticated')::text, true);
  select codigo into v_codigo from institute.ofertas where programa_codigo is not null order by codigo limit 1;
  perform pg_temp.congelada(format('select api.salvar_oferta(%L, p_nome => %L)', v_codigo, 'Pelo Join'));
  perform pg_temp.congelada(format('select api.criar_oferta(%L, %L, 10)',
    (select programa_codigo from institute.ofertas where codigo = v_codigo), 'contrato-pelo-join'));
  perform pg_temp.congelada(format('select api.salvar_bump(%L::uuid, p_ativo => true)', (select id from institute.bump_regras limit 1)));
  perform pg_temp.congelada(format('select api.remover_bump(%L::uuid)', gen_random_uuid()));
  perform set_config('request.jwt.claims', '', true);

  -- 5. Aceite: o nome de uma oferta no ar, mudado no painel, aparece na porta e no bloco do agente na hora.
  select o.id, o.atualizado_em::text, op.codigo into v_id, v_versao, v_codigo
    from catalogo.ofertas o join catalogo.oferta_precos op on op.oferta_id = o.id
   where o.origem->>'tabela' = 'institute.ofertas' and o.ativo and o.tipo = 'base' order by o.codigo limit 1;
  r := public.mind_admin_mutate_ofertas('atualizar', v_id, '{"nome":"Nome de ensaio do contrato da virada"}', v_versao, v_ator, gen_random_uuid());
  if (select nome from api.ofertas where codigo = v_codigo) is distinct from 'Nome de ensaio do contrato da virada' then
    raise exception 'aceite: a porta não mostrou o nome novo'; end if;
  v_bloco := public.mind_kit_institute_catalogo(null::uuid, '{}'::jsonb)::text;
  if position('Nome de ensaio do contrato da virada' in v_bloco) = 0 then
    raise exception 'aceite: o bloco do agente não mostrou o nome novo'; end if;
  if (r->'alteracoes'->0->'campos') <> '["nome"]'::jsonb or not (r->>'noSite')::boolean then
    raise exception 'aceite: histórico ou selo "no site": %', r; end if;
  -- E o código não muda: links, pedidos e acessos usam.
  perform pg_temp.recusa('atualizar', v_id, '{"codigo":"outro-codigo"}', r->>'atualizadoEm', v_ator, 'admin_validation:codigo_nao_editavel');

  -- 6. Só o que está valendo chega ao site (decisão 8).
  select p.codigo, pr.codigo into v_prod_a, v_prog_a
    from catalogo.produtos p join institute.programas pr on pr.produto_codigo = p.codigo
   where pr.tipo = 'formacao' order by p.codigo limit 1;
  select p.codigo, pr.codigo into v_prod_journey, v_prog_journey
    from catalogo.produtos p join institute.programas pr on pr.produto_codigo = p.codigo
   where pr.codigo = 'mind-journey';
  if v_prod_a is null or v_prod_journey is null then raise exception 'faltam produtos do Institute para o teste'; end if;

  -- Uma condição valendo agora, com preço riscado e dois bônus: o Journey (programa) e o ingresso de 2027 (não).
  r := public.mind_admin_mutate_ofertas('criar', null, jsonb_build_object(
         'codigo', 'contrato-virada-valendo', 'nome', 'Condição do contrato da virada', 'tipo', 'periodo',
         'iniciaEm', now() - interval '1 day', 'encerraEm', now() + interval '1 day',
         'meiosPagamento', jsonb_build_array('cartao', 'pix'),
         'precos', jsonb_build_array(jsonb_build_object('produtoCodigo', v_prod_a, 'codigo', 'contrato-virada-valendo',
                                                        'valor', 1000, 'parcelas', 10, 'valorParcela', 100, 'valorRiscado', 1500)),
         'bonus', jsonb_build_array(
           jsonb_build_object('produtoCodigo', v_prod_a, 'inclusoCodigo', v_prod_journey, 'valorReferencia', 300),
           jsonb_build_object('produtoCodigo', v_prod_a, 'inclusoCodigo', 'mind-summit-2027-mind', 'nome', 'Ingresso do contrato'))),
       null, v_ator, gen_random_uuid());
  v_valendo := (r->>'id')::uuid;
  if r->>'bloqueioPorNoAr' is not null then raise exception 'valendo: bloqueio = %', r->>'bloqueioPorNoAr'; end if;
  if exists (select 1 from api.ofertas where codigo = 'contrato-virada-valendo')
     or exists (select 1 from catalogo.institute_ofertas where codigo = 'contrato-virada-valendo') then
    raise exception 'rascunho apareceu para um leitor antes de ir ao ar'; end if;
  r := public.mind_admin_mutate_ofertas('publicar', v_valendo, '{}', r->>'atualizadoEm', v_ator, gen_random_uuid());
  if not exists (select 1 from api.ofertas
                  where codigo = 'contrato-virada-valendo' and programa_codigo = v_prog_a and vigente
                    and valor = 1000 and parcelas = 10 and valor_parcela = 100 and valor_referencia = 1500
                    and elegibilidade = '{}'::jsonb and meios_pagamento = array['cartao', 'pix']
                    and jsonb_array_length(bonus) = 2 and bonus->0->>'nome' is not null
                    and (bonus->0->>'gratuito')::boolean) then
    raise exception 'valendo: a porta não mostrou a condição como o site lê: %',
      (select to_jsonb(o) from api.ofertas o where codigo = 'contrato-virada-valendo'); end if;
  if (select array_agg(programa_codigo order by programa_codigo) from api.oferta_inclui where oferta_codigo = 'contrato-virada-valendo')
     is distinct from array[v_prog_journey] then
    raise exception 'valendo: o bônus que é programa devia abrir acesso, e só ele'; end if;
  if position('Condição do contrato da virada' in public.mind_kit_institute_catalogo(null::uuid, '{}'::jsonb)::text) = 0 then
    raise exception 'valendo: o bloco do agente não mostrou a condição'; end if;
  -- Vencida: sai do site e do agente, mas continua para a compra manual e para abrir acesso.
  r := public.mind_admin_mutate_ofertas('atualizar', v_valendo, jsonb_build_object('encerraEm', now() - interval '1 minute'),
         r->>'atualizadoEm', v_ator, gen_random_uuid());
  if exists (select 1 from api.ofertas where codigo = 'contrato-virada-valendo')
     or position('Condição do contrato da virada' in public.mind_kit_institute_catalogo(null::uuid, '{}'::jsonb)::text) > 0 then
    raise exception 'vencida: ainda aparece no site ou no agente'; end if;
  if not exists (select 1 from catalogo.institute_ofertas where codigo = 'contrato-virada-valendo' and ativo)
     or not exists (select 1 from api.oferta_inclui where oferta_codigo = 'contrato-virada-valendo') then
    raise exception 'vencida: sumiu da compra manual ou do acesso'; end if;

  -- Agendada: no ar, mas ainda não começou — fora do site.
  r := public.mind_admin_mutate_ofertas('criar', null, jsonb_build_object(
         'codigo', 'contrato-virada-agendada', 'nome', 'Agendada do contrato', 'tipo', 'periodo',
         'iniciaEm', now() + interval '1 day', 'encerraEm', now() + interval '2 days',
         'precos', jsonb_build_array(jsonb_build_object('produtoCodigo', v_prod_a, 'codigo', 'contrato-virada-agendada', 'valor', 900))),
       null, v_ator, gen_random_uuid());
  v_agendada := (r->>'id')::uuid;
  r := public.mind_admin_mutate_ofertas('publicar', v_agendada, '{}', r->>'atualizadoEm', v_ator, gen_random_uuid());
  if r->>'situacao' <> 'agendada' or exists (select 1 from api.ofertas where codigo = 'contrato-virada-agendada') then
    raise exception 'agendada: %', r->>'situacao'; end if;

  -- Rascunho que nunca foi ao ar: nenhum leitor vê, nem a compra manual nem o acesso.
  r := public.mind_admin_mutate_ofertas('criar', null, jsonb_build_object(
         'codigo', 'contrato-virada-rascunho', 'nome', 'Rascunho do contrato', 'tipo', 'base',
         'precos', jsonb_build_array(jsonb_build_object('produtoCodigo', v_prod_a, 'codigo', 'contrato-virada-rascunho', 'valor', 800))),
       null, v_ator, gen_random_uuid());
  v_rascunho := (r->>'id')::uuid;
  -- Base nova de produto que já tem base no ar: o painel avisa e recusa pôr no ar.
  if r->>'bloqueioPorNoAr' <> 'base_duplicada' then raise exception 'rascunho: bloqueio = %', r->>'bloqueioPorNoAr'; end if;
  perform pg_temp.recusa('publicar', v_rascunho, '{}', r->>'atualizadoEm', v_ator, 'admin_validation:base_duplicada');
  if exists (select 1 from catalogo.institute_ofertas where codigo = 'contrato-virada-rascunho')
     or exists (select 1 from api.oferta_inclui where oferta_codigo = 'contrato-virada-rascunho') then
    raise exception 'rascunho: apareceu para um leitor'; end if;

  -- Upgrade (exige ter comprado): o checkout do Institute não sabe conferir posse — nenhum leitor vê.
  r := public.mind_admin_mutate_ofertas('criar', null, jsonb_build_object(
         'codigo', 'contrato-virada-upgrade', 'nome', 'Upgrade do contrato', 'tipo', 'condicional',
         'precos', jsonb_build_array(jsonb_build_object('produtoCodigo', v_prod_a, 'codigo', 'contrato-virada-upgrade', 'valor', 700)),
         'requer', jsonb_build_array(jsonb_build_object('produtoCodigo', v_prod_journey, 'modo', 'posse'))),
       null, v_ator, gen_random_uuid());
  v_upgrade := (r->>'id')::uuid;
  r := public.mind_admin_mutate_ofertas('publicar', v_upgrade, '{}', r->>'atualizadoEm', v_ator, gen_random_uuid());
  if not (r->>'ativo')::boolean
     or exists (select 1 from catalogo.institute_ofertas where codigo = 'contrato-virada-upgrade')
     or exists (select 1 from api.ofertas where codigo = 'contrato-virada-upgrade')
     or exists (select 1 from api.bump_regras where oferta_bump_codigo = 'contrato-virada-upgrade') then
    raise exception 'upgrade: apareceu para um leitor do Institute'; end if;

  -- 7. Order bump criado no painel: chega ao checkout do jeito que o site lê.
  r := public.mind_admin_mutate_ofertas('criar', null, jsonb_build_object(
         'codigo', 'contrato-virada-bump', 'nome', 'Bump do contrato da virada', 'tipo', 'condicional',
         'precos', jsonb_build_array(jsonb_build_object('produtoCodigo', v_prod_journey, 'codigo', 'contrato-virada-bump',
                                                        'valor', 400, 'valorRiscado', 999)),
         'requer', jsonb_build_array(jsonb_build_object('produtoCodigo', v_prod_a, 'grupoExclusivo', 'contrato', 'prioridade', 150))),
       null, v_ator, gen_random_uuid());
  v_bump := (r->>'id')::uuid;
  r := public.mind_admin_mutate_ofertas('publicar', v_bump, '{}', r->>'atualizadoEm', v_ator, gen_random_uuid());
  if not exists (select 1 from api.bump_regras
                  where oferta_bump_codigo = 'contrato-virada-bump' and gatilho_programa_codigo = v_prog_a
                    and prioridade = 150 and grupo_exclusivo = 'contrato' and oferta_valor = 400
                    and oferta_programa_codigo = v_prog_journey and oferta_valor_riscado = 999
                    and oferta_nome = 'Bump do contrato da virada') then
    raise exception 'bump: api.bump_regras'; end if;
  -- Sem programa na porta de preços: fica fora das listas por programa, como a "Avulsas".
  if not exists (select 1 from api.ofertas
                  where codigo = 'contrato-virada-bump' and valor_referencia is null and programa_codigo is null
                    and elegibilidade = jsonb_build_object('tipo', 'order_bump', 'requer_no_carrinho', jsonb_build_array(v_prog_a),
                                                           'valor_riscado', 999)) then
    raise exception 'bump: na porta de preços: %', (select jsonb_build_object('programa', programa_codigo, 'elegibilidade', elegibilidade)
                                                      from api.ofertas where codigo = 'contrato-virada-bump'); end if;
  if position('Bump do contrato da virada' in public.mind_kit_institute_catalogo(null::uuid, '{}'::jsonb)::text) > 0 then
    raise exception 'bump: o agente não cita bump como preço'; end if;
  -- Tirar do ar tira do checkout.
  r := public.mind_admin_mutate_ofertas('arquivar', v_bump, '{}', r->>'atualizadoEm', v_ator, gen_random_uuid());
  if exists (select 1 from api.bump_regras where oferta_bump_codigo = 'contrato-virada-bump')
     or exists (select 1 from api.ofertas where codigo = 'contrato-virada-bump') then
    raise exception 'bump: tirado do ar, continuou no checkout'; end if;

  -- 8. Histórico importado é só leitura; e as peças novas não são porta de ninguém.
  select o.id, o.atualizado_em::text into v_id, v_versao from catalogo.ofertas o
   where o.origem->>'tabela' = 'institute.ofertas' and o.historico order by o.codigo limit 1;
  perform pg_temp.recusa('publicar', v_id, '{}', v_versao, v_ator, 'admin_validation:historico_so_leitura');
  if has_table_privilege('anon', 'catalogo.institute_ofertas', 'select')
     or has_table_privilege('authenticated', 'catalogo.institute_ofertas', 'select')
     or has_table_privilege('service_role', 'catalogo.institute_ofertas', 'select')
     or has_function_privilege('anon', 'institute.casa_antiga_congelada()', 'execute')
     or has_function_privilege('authenticated', 'institute.casa_antiga_congelada()', 'execute')
     or has_function_privilege('service_role', 'institute.casa_antiga_congelada()', 'execute') then
    raise exception 'permissões: a view interna ou o gatilho abertos para fora'; end if;
  if not has_table_privilege('anon', 'api.ofertas', 'select') or not has_table_privilege('anon', 'api.bump_regras', 'select')
     or not has_table_privilege('anon', 'api.oferta_inclui', 'select') then
    raise exception 'permissões: o site perdeu a leitura das portas'; end if;

  raise exception 'VIRADA_OK: portas lendo o catálogo, casa antiga congelada (também pelo /admin do Join), carga com origem, leitor só do Institute, nome mudado no painel na porta e no agente, só o que vale no site (vencida e agendada fora, rascunho e upgrade invisíveis), bônus que é programa abre acesso, bump do painel no checkout, fora das listas por programa e fora ao tirar do ar, histórico só leitura e permissões conferem';
end $$;
rollback;
