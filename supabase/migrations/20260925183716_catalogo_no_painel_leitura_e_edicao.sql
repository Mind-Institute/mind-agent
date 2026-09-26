-- O CATÁLOGO NO PAINEL: ler e editar `catalogo.produtos` pelo admin do agente.
--
-- Pedido da Adriana, 25/09/2026: começar o painel pelo catálogo, "que é a
-- origem de tudo", com leitura e escrita: editar no painel e a edição ir para
-- o banco quando ela salvar. CRM, conhecimento e agentes referenciam os
-- códigos daqui.
--
-- DUAS FUNÇÕES, no molde das portas da Home V3:
--   mind_admin_read_catalogo(p_id)    lista (p_id nulo) ou um produto
--   mind_admin_mutate_catalogo(...)   edição de um produto que já existe
-- As duas são SECURITY DEFINER e só o `service_role` executa. Quem chama é a
-- Edge Function `mindagent-catalogo`, depois de validar a sessão e o papel.
--
-- O QUE A EDIÇÃO NÃO TOCA
--   · `codigo`: é a chave primária, e 13 tabelas de outros schemas apontam
--     para ela. Renomear é migração, não formulário; mandar um código
--     diferente é recusado, para ninguém achar que renomeou.
--   · `id` e `atualizado_em`: do sistema.
--   · `schema_dados`: diz onde mora a base de conhecimento do produto; mudar
--     é religar o produto a outro lugar.
-- Nada é criado nem apagado por aqui.
--
-- AS MESMAS REGRAS DAS OUTRAS ESCRITAS DO PAINEL: o papel é conferido de novo
-- aqui (administrador, editor e aprovador editam), a versão é obrigatória —
-- quem salva por cima de versão velha leva conflito — e o antes/depois vai
-- para `public.mind_admin_audit`.
--
-- Contrato: tests/catalogo_painel_contract.sql (termina em CATALOGO_OK).

create or replace function public.mind_admin_read_catalogo(p_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'catalogo'
as $fn$
  select coalesce(jsonb_agg(x.obj order by x.vertical nulls first, x.nome), '[]'::jsonb)
  from (
    select p.vertical, p.nome,
      jsonb_build_object(
        'id', p.id::text,
        'codigo', p.codigo,
        'nome', p.nome,
        'tipo', p.tipo,
        'vertical', p.vertical,
        'categoria', p.categoria,
        'descricaoCurta', p.descricao_curta,
        'descricao', p.descricao,
        'ativo', p.ativo,
        'vende', p.vende,
        'vendeDe', p.vende_de,
        'vendeAte', p.vende_ate,
        'comecaEm', p.comeca_em,
        'encerraEm', p.encerra_em,
        'periodo', p.periodo,
        'schemaDados', p.schema_dados,
        'pipelinesHubspot', coalesce(to_jsonb(p.pipelines_hubspot), '[]'::jsonb),
        'atualizadoEm', p.atualizado_em
      ) as obj
    from catalogo.produtos p
    where p_id is null or p.id = p_id
  ) x;
$fn$;

comment on function public.mind_admin_read_catalogo(uuid) is
  'Porta de leitura do painel para catalogo.produtos: todos (p_id nulo) ou um, no formato do contrato do painel. Só service_role executa; quem chama é a Edge Function mindagent-catalogo.';

create or replace function public.mind_admin_mutate_catalogo(
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
set search_path to 'pg_catalog', 'public', 'catalogo'
as $fn$
declare
  v_role text;
  v_before jsonb;
  v_after jsonb;
  v_atual catalogo.produtos%rowtype;
  v_novo catalogo.produtos%rowtype;
begin
  -- Mesmas regras de papel das outras escritas do painel.
  select role into v_role
  from public.mind_admin_users
  where user_id = p_actor_id and active;

  if v_role is null then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  end if;
  if p_action is distinct from 'atualizar' then
    raise exception using errcode = '22023', message = 'admin_validation:acao_invalida';
  end if;
  if v_role not in ('administrador', 'editor', 'aprovador') then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  end if;
  if p_id is null then
    raise exception using errcode = '22023', message = 'admin_validation:id_obrigatorio';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'admin_validation:corpo_invalido';
  end if;

  -- Trava a linha: entre conferir a versão e gravar, ninguém mais escreve.
  select * into v_atual from catalogo.produtos where id = p_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'admin_not_found';
  end if;

  -- Travamento otimista: quem salva por cima de versão velha leva 409.
  if p_expected_updated_at is null or btrim(p_expected_updated_at) = '' then
    raise exception using errcode = '22023', message = 'admin_validation:versao_obrigatoria';
  end if;
  if v_atual.atualizado_em <> p_expected_updated_at::timestamptz then
    raise exception using errcode = '40001', message = 'admin_conflict';
  end if;

  if p_payload ? 'codigo' and p_payload->>'codigo' is distinct from v_atual.codigo then
    raise exception using errcode = '22023', message = 'admin_validation:codigo_nao_editavel';
  end if;
  if p_payload ? 'schemaDados' and p_payload->>'schemaDados' is distinct from v_atual.schema_dados then
    raise exception using errcode = '22023', message = 'admin_validation:schema_dados_nao_editavel';
  end if;
  if p_payload ? 'pipelinesHubspot'
     and jsonb_typeof(p_payload->'pipelinesHubspot') not in ('array', 'null') then
    raise exception using errcode = '22023', message = 'admin_validation:pipelines_hubspot';
  end if;

  v_before := public.mind_admin_read_catalogo(p_id)->0;

  -- Só o que veio no corpo muda; o resto fica como está. Texto opcional
  -- vazio vira nulo, que é como o catálogo já guarda "não se sabe".
  v_novo := v_atual;
  if p_payload ? 'nome' then
    v_novo.nome := nullif(btrim(p_payload->>'nome'), '');
    if v_novo.nome is null then
      raise exception using errcode = '22023', message = 'admin_validation:nome_obrigatorio';
    end if;
  end if;
  if p_payload ? 'tipo' then v_novo.tipo := nullif(btrim(p_payload->>'tipo'), ''); end if;
  if p_payload ? 'vertical' then v_novo.vertical := nullif(btrim(p_payload->>'vertical'), ''); end if;
  if p_payload ? 'categoria' then v_novo.categoria := nullif(btrim(p_payload->>'categoria'), ''); end if;
  if p_payload ? 'descricaoCurta' then v_novo.descricao_curta := nullif(btrim(p_payload->>'descricaoCurta'), ''); end if;
  if p_payload ? 'descricao' then v_novo.descricao := nullif(btrim(p_payload->>'descricao'), ''); end if;
  if p_payload ? 'periodo' then v_novo.periodo := nullif(btrim(p_payload->>'periodo'), ''); end if;
  if p_payload ? 'ativo' then v_novo.ativo := (p_payload->>'ativo')::boolean; end if;
  if p_payload ? 'vende' then v_novo.vende := (p_payload->>'vende')::boolean; end if;
  if p_payload ? 'vendeDe' then v_novo.vende_de := nullif(btrim(p_payload->>'vendeDe'), '')::timestamptz; end if;
  if p_payload ? 'vendeAte' then v_novo.vende_ate := nullif(btrim(p_payload->>'vendeAte'), '')::timestamptz; end if;
  if p_payload ? 'comecaEm' then v_novo.comeca_em := nullif(btrim(p_payload->>'comecaEm'), '')::date; end if;
  if p_payload ? 'encerraEm' then v_novo.encerra_em := nullif(btrim(p_payload->>'encerraEm'), '')::date; end if;
  if p_payload ? 'pipelinesHubspot' then
    if jsonb_typeof(p_payload->'pipelinesHubspot') = 'array' then
      select nullif(array_agg(btrim(e.v) order by e.o) filter (where btrim(e.v) <> ''), '{}')
        into v_novo.pipelines_hubspot
      from jsonb_array_elements_text(p_payload->'pipelinesHubspot') with ordinality as e(v, o);
    else
      v_novo.pipelines_hubspot := null;
    end if;
  end if;

  -- A janela só é conferida quando a edição mexe nela: dado antigo fora de
  -- ordem não pode travar a correção de um nome.
  if (p_payload ? 'vendeDe' or p_payload ? 'vendeAte')
     and v_novo.vende_de is not null and v_novo.vende_ate is not null
     and v_novo.vende_de > v_novo.vende_ate then
    raise exception using errcode = '22023', message = 'admin_validation:janela_de_venda_invertida';
  end if;
  if (p_payload ? 'comecaEm' or p_payload ? 'encerraEm')
     and v_novo.comeca_em is not null and v_novo.encerra_em is not null
     and v_novo.comeca_em > v_novo.encerra_em then
    raise exception using errcode = '22023', message = 'admin_validation:datas_invertidas';
  end if;

  update catalogo.produtos set
    nome = v_novo.nome,
    tipo = v_novo.tipo,
    vertical = v_novo.vertical,
    categoria = v_novo.categoria,
    descricao_curta = v_novo.descricao_curta,
    descricao = v_novo.descricao,
    periodo = v_novo.periodo,
    ativo = v_novo.ativo,
    vende = v_novo.vende,
    vende_de = v_novo.vende_de,
    vende_ate = v_novo.vende_ate,
    comeca_em = v_novo.comeca_em,
    encerra_em = v_novo.encerra_em,
    pipelines_hubspot = v_novo.pipelines_hubspot,
    atualizado_em = clock_timestamp()
  where id = p_id;

  v_after := public.mind_admin_read_catalogo(p_id)->0;

  insert into public.mind_admin_audit(
    actor_user_id, action, resource, record_id, record_label, before_data, after_data, request_id
  ) values (
    p_actor_id, p_action, 'products', p_id::text, v_after->>'nome', v_before, v_after, p_request_id
  );

  return v_after;
exception
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow
    or check_violation or not_null_violation then
    raise exception using errcode = '22023', message = 'admin_validation:dados_invalidos';
end;
$fn$;

comment on function public.mind_admin_mutate_catalogo(text, uuid, jsonb, text, uuid, uuid) is
  'Edição de um produto de catalogo.produtos pelo painel. Papel conferido em mind_admin_users, versão obrigatória (40001 em conflito), antes/depois em mind_admin_audit. Não edita codigo, id, schema_dados nem atualizado_em; não cria nem apaga. Só service_role executa.';

revoke all on function public.mind_admin_read_catalogo(uuid) from public, anon, authenticated;
revoke all on function public.mind_admin_mutate_catalogo(text, uuid, jsonb, text, uuid, uuid) from public, anon, authenticated;
grant execute on function public.mind_admin_read_catalogo(uuid) to service_role;
grant execute on function public.mind_admin_mutate_catalogo(text, uuid, jsonb, text, uuid, uuid) to service_role;
