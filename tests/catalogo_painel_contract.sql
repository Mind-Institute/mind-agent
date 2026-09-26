-- Contrato do catálogo no painel: mind_admin_read_catalogo e mind_admin_mutate_catalogo
-- (migrations 20260925183716_catalogo_no_painel_leitura_e_edicao e
-- 20260926153820_catalogo_datas_da_turma_no_painel). Sempre termina em rollback:
-- a exceção CATALOGO_OK é o resultado. Usa um administrador ativo de mind_admin_users como
-- autor e não cria pessoa nem produto.
begin;
do $$
declare
  v_ator uuid;
  v_prod catalogo.produtos%rowtype;
  v_inst catalogo.produtos%rowtype;
  v_turma institute.programas%rowtype;
  v_obj jsonb;
  v_lista jsonb;
  v_um jsonb;
  r jsonb;
  n int;
  n_audit int;
  v_versao text;
  v_versao_nova text;
  v_estado text;
  v_msg text;
begin
  select user_id into v_ator from public.mind_admin_users
   where active and role in ('administrador', 'editor', 'aprovador') limit 1;
  if v_ator is null then raise exception 'sem administrador ativo em mind_admin_users para o teste'; end if;

  -- leitura: todos, no formato do contrato
  v_lista := public.mind_admin_read_catalogo();
  select count(*) into n from catalogo.produtos;
  if jsonb_array_length(v_lista) <> n then
    raise exception 'leitura: % itens, o catálogo tem %', jsonb_array_length(v_lista), n; end if;
  if exists (select 1 from jsonb_array_elements(v_lista) e
              where e->>'id' is null or e->>'codigo' is null or e->>'nome' is null or e->>'tipo' is null
                 or e->>'atualizadoEm' is null
                 or jsonb_typeof(e->'ativo') <> 'boolean' or jsonb_typeof(e->'vende') <> 'boolean'
                 or jsonb_typeof(e->'pipelinesHubspot') <> 'array') then
    raise exception 'leitura: item fora do contrato'; end if;

  -- leitura: um, e o inexistente vem vazio
  select * into v_prod from catalogo.produtos order by codigo limit 1;
  v_um := public.mind_admin_read_catalogo(v_prod.id);
  if jsonb_array_length(v_um) <> 1 or v_um->0->>'codigo' <> v_prod.codigo then raise exception 'leitura por id'; end if;
  if jsonb_array_length(public.mind_admin_read_catalogo(gen_random_uuid())) <> 0 then
    raise exception 'id inexistente devia voltar vazio'; end if;

  v_versao := v_um->0->>'atualizadoEm';
  select count(*) into n_audit from public.mind_admin_audit where resource = 'products';

  -- edição válida: só o que veio muda; código igual é aceito; texto aparado; pipeline vazio sai
  r := public.mind_admin_mutate_catalogo('atualizar', v_prod.id,
         jsonb_build_object('codigo', v_prod.codigo, 'descricaoCurta', '  Teste do contrato  ',
                            'pipelinesHubspot', jsonb_build_array('123', ' ', '456')),
         v_versao, v_ator, gen_random_uuid());
  if r->>'descricaoCurta' <> 'Teste do contrato' then raise exception 'edição: descricaoCurta = %', r->>'descricaoCurta'; end if;
  if r->'pipelinesHubspot' <> '["123", "456"]'::jsonb then raise exception 'edição: pipelines = %', r->'pipelinesHubspot'; end if;
  if r->>'nome' <> v_prod.nome or (r->>'ativo')::boolean <> v_prod.ativo or (r->>'vende')::boolean <> v_prod.vende then
    raise exception 'edição mexeu no que não veio no corpo'; end if;
  if (r->>'atualizadoEm')::timestamptz <= v_versao::timestamptz then raise exception 'edição: a versão não andou'; end if;
  v_versao_nova := r->>'atualizadoEm';

  select count(*) into n from public.mind_admin_audit where resource = 'products';
  if n <> n_audit + 1 then raise exception 'auditoria: esperava 1 linha nova, vieram %', n - n_audit; end if;
  if not exists (select 1 from public.mind_admin_audit
                  where resource = 'products' and action = 'atualizar' and record_id = v_prod.id::text
                    and actor_user_id = v_ator
                    and before_data->>'descricaoCurta' is not distinct from v_prod.descricao_curta
                    and after_data->>'descricaoCurta' = 'Teste do contrato') then
    raise exception 'auditoria sem o antes/depois'; end if;

  -- versão velha: conflito
  begin
    perform public.mind_admin_mutate_catalogo('atualizar', v_prod.id, '{"nome":"X"}', v_versao, v_ator, gen_random_uuid());
    raise exception 'versão velha devia ser recusada';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    if v_estado <> '40001' then raise exception 'conflito: veio % %', v_estado, v_msg; end if;
  end;

  -- sem versão
  begin
    perform public.mind_admin_mutate_catalogo('atualizar', v_prod.id, '{"nome":"X"}', null, v_ator, gen_random_uuid());
    raise exception 'sem versão devia ser recusado';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    if v_msg <> 'admin_validation:versao_obrigatoria' then raise exception 'sem versão: veio % %', v_estado, v_msg; end if;
  end;

  -- código não se edita
  begin
    perform public.mind_admin_mutate_catalogo('atualizar', v_prod.id, '{"codigo":"outro-codigo"}', v_versao_nova, v_ator, gen_random_uuid());
    raise exception 'troca de código devia ser recusada';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    if v_msg <> 'admin_validation:codigo_nao_editavel' then raise exception 'código: veio % %', v_estado, v_msg; end if;
  end;

  -- schema_dados não se edita
  begin
    perform public.mind_admin_mutate_catalogo('atualizar', v_prod.id, '{"schemaDados":"outro_schema"}', v_versao_nova, v_ator, gen_random_uuid());
    raise exception 'troca de schema_dados devia ser recusada';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    if v_msg <> 'admin_validation:schema_dados_nao_editavel' then raise exception 'schema_dados: veio % %', v_estado, v_msg; end if;
  end;

  -- vertical fora do CHECK
  begin
    perform public.mind_admin_mutate_catalogo('atualizar', v_prod.id, '{"vertical":"marte"}', v_versao_nova, v_ator, gen_random_uuid());
    raise exception 'vertical inválida devia ser recusada';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    if v_msg <> 'admin_validation:dados_invalidos' then raise exception 'vertical: veio % %', v_estado, v_msg; end if;
  end;

  -- nome vazio
  begin
    perform public.mind_admin_mutate_catalogo('atualizar', v_prod.id, '{"nome":"   "}', v_versao_nova, v_ator, gen_random_uuid());
    raise exception 'nome vazio devia ser recusado';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    if v_msg <> 'admin_validation:nome_obrigatorio' then raise exception 'nome: veio % %', v_estado, v_msg; end if;
  end;

  -- ativo nulo
  begin
    perform public.mind_admin_mutate_catalogo('atualizar', v_prod.id, '{"ativo":null}', v_versao_nova, v_ator, gen_random_uuid());
    raise exception 'ativo nulo devia ser recusado';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    if v_msg <> 'admin_validation:dados_invalidos' then raise exception 'ativo nulo: veio % %', v_estado, v_msg; end if;
  end;

  -- janela de venda invertida
  begin
    perform public.mind_admin_mutate_catalogo('atualizar', v_prod.id,
      '{"vendeDe":"2026-12-01T00:00:00-03:00","vendeAte":"2026-11-01T00:00:00-03:00"}', v_versao_nova, v_ator, gen_random_uuid());
    raise exception 'janela invertida devia ser recusada';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    if v_msg <> 'admin_validation:janela_de_venda_invertida' then raise exception 'janela: veio % %', v_estado, v_msg; end if;
  end;

  -- quem não está no painel não edita
  begin
    perform public.mind_admin_mutate_catalogo('atualizar', v_prod.id, '{"nome":"X"}', v_versao_nova, gen_random_uuid(), gen_random_uuid());
    raise exception 'autor fora do painel devia ser recusado';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    if v_estado <> '42501' then raise exception 'papel: veio % %', v_estado, v_msg; end if;
  end;

  -- produto inexistente
  begin
    perform public.mind_admin_mutate_catalogo('atualizar', gen_random_uuid(), '{"nome":"X"}', v_versao_nova, v_ator, gen_random_uuid());
    raise exception 'produto inexistente devia dar não encontrado';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    if v_estado <> 'P0002' then raise exception 'inexistente: veio % %', v_estado, v_msg; end if;
  end;

  -- só edição: criar não existe por aqui
  begin
    perform public.mind_admin_mutate_catalogo('criar', null, '{"nome":"X"}', null, v_ator, gen_random_uuid());
    raise exception 'criar devia ser recusado';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    if v_msg <> 'admin_validation:acao_invalida' then raise exception 'criar: veio % %', v_estado, v_msg; end if;
  end;

  -- nenhuma recusa deixou rastro
  if (select descricao_curta from catalogo.produtos where id = v_prod.id) <> 'Teste do contrato'
     or (select nome from catalogo.produtos where id = v_prod.id) <> v_prod.nome then
    raise exception 'uma escrita recusada mudou o produto'; end if;
  select count(*) into n from public.mind_admin_audit where resource = 'products';
  if n <> n_audit + 1 then raise exception 'uma escrita recusada deixou auditoria'; end if;

  -- só o service_role executa as duas portas
  if has_function_privilege('anon', 'public.mind_admin_read_catalogo(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.mind_admin_read_catalogo(uuid)', 'execute')
     or has_function_privilege('anon', 'public.mind_admin_mutate_catalogo(text,uuid,jsonb,text,uuid,uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.mind_admin_mutate_catalogo(text,uuid,jsonb,text,uuid,uuid)', 'execute') then
    raise exception 'anon/authenticated não podem executar as portas do catálogo'; end if;
  if not has_function_privilege('service_role', 'public.mind_admin_mutate_catalogo(text,uuid,jsonb,text,uuid,uuid)', 'execute') then
    raise exception 'service_role precisa executar a edição'; end if;

  -- No Institute, as datas são as da turma: a leitura mostra as da turma e a edição delas é recusada.
  select p.* into v_inst from catalogo.produtos p
   where exists (select 1 from institute.programas pr where pr.produto_codigo = p.codigo)
   order by p.codigo limit 1;
  if v_inst.id is null then raise exception 'sem produto com turma em institute.programas para o teste'; end if;
  select pr.* into v_turma from institute.programas pr where pr.produto_codigo = v_inst.codigo
   order by pr.ativo desc, pr.inicia_em nulls last, pr.ordem nulls last, pr.codigo limit 1;
  v_obj := public.mind_admin_read_catalogo(v_inst.id)->0;
  if v_obj->>'comecaEm' is distinct from v_turma.inicia_em::text
     or v_obj->>'encerraEm' is distinct from v_turma.encerra_em::text
     or v_obj->'datasDaTurma'->>'programa' is distinct from v_turma.codigo
     or (v_obj->'datasDaTurma'->>'inicioPrevisto')::boolean is distinct from v_turma.inicio_previsto then
    raise exception 'datas da turma: a leitura trouxe %', v_obj; end if;
  begin
    perform public.mind_admin_mutate_catalogo('atualizar', v_inst.id, '{"comecaEm":"2030-01-01"}',
      v_obj->>'atualizadoEm', v_ator, gen_random_uuid());
    raise exception 'editar a data de produto com turma devia ser recusado';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    if v_msg <> 'admin_validation:datas_da_turma' then raise exception 'datas da turma: veio % %', v_estado, v_msg; end if;
  end;
  begin
    perform public.mind_admin_mutate_catalogo('atualizar', v_inst.id, '{"encerraEm":null}',
      v_obj->>'atualizadoEm', v_ator, gen_random_uuid());
    raise exception 'apagar a data de produto com turma devia ser recusado';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    if v_msg <> 'admin_validation:datas_da_turma' then raise exception 'datas da turma (fim): veio % %', v_estado, v_msg; end if;
  end;
  -- o resto do produto com turma continua editável, e a cópia guardada não muda
  r := public.mind_admin_mutate_catalogo('atualizar', v_inst.id, '{"descricaoCurta":"Teste das datas da turma"}',
         v_obj->>'atualizadoEm', v_ator, gen_random_uuid());
  if r->>'descricaoCurta' <> 'Teste das datas da turma' or r->'datasDaTurma' is null
     or r->>'comecaEm' is distinct from v_turma.inicia_em::text then
    raise exception 'produto com turma: %', r; end if;
  if (select comeca_em from catalogo.produtos where id = v_inst.id) is distinct from v_inst.comeca_em
     or (select encerra_em from catalogo.produtos where id = v_inst.id) is distinct from v_inst.encerra_em then
    raise exception 'a leitura pela turma não pode reescrever a cópia guardada'; end if;
  -- produto sem turma: sem datasDaTurma, datas do próprio catálogo
  if (public.mind_admin_read_catalogo(v_prod.id)->0->'datasDaTurma') <> 'null'::jsonb
     and not exists (select 1 from institute.programas where produto_codigo = v_prod.codigo) then
    raise exception 'produto sem turma não pode trazer datasDaTurma'; end if;

  raise exception 'CATALOGO_OK: leitura (todos, um, inexistente), edição parcial com auditoria, conflito, versão obrigatória, código e schema_dados travados, CHECK, nome, nulo, janela, papel, inexistente, criar recusado, recusa sem rastro, permissões e datas da turma no Institute conferem';
end $$;
rollback;
