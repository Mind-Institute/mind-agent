-- Contrato da edição de ofertas no painel: mind_admin_mutate_ofertas e o que mind_admin_read_ofertas ganhou
-- no Passo 4 (migration 20260926210134_ofertas_edicao_no_painel). Sempre termina em rollback: a exceção
-- OFERTAS_EDICAO_OK é o resultado. Usa um administrador ativo de mind_admin_users como autor, cria ofertas
-- de teste (códigos contrato-*) e, para ensaiar a vida depois da virada, troca por dentro da transação a
-- regra de quem lê o catálogo — tudo desfeito no fim.
begin;

-- A recusa esperada, com o motivo exato, e sem rastro (a escrita recusada é desfeita inteira).
create function pg_temp.recusa(p_action text, p_id uuid, p_payload jsonb, p_versao text, p_ator uuid, p_motivo text)
returns void
language plpgsql
as $f$
declare
  v_estado text;
  v_msg text;
begin
  begin
    perform public.mind_admin_mutate_ofertas(p_action, p_id, p_payload, p_versao, p_ator, gen_random_uuid());
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    if v_msg is distinct from p_motivo then
      raise exception '% %: esperava %, veio % %', p_action, p_payload, p_motivo, v_estado, v_msg;
    end if;
    return;
  end;
  raise exception '% %: esperava a recusa %, e passou', p_action, p_payload, p_motivo;
end
$f$;

do $$
declare
  v_ator uuid;
  v_pa text;
  v_pb text;
  v_px text;
  v_reservado text;
  v_programa text;
  v_base jsonb := '{"codigo":"contrato-b","nome":"Oferta B","tipo":"periodo"}'::jsonb;
  v_preco_pa jsonb;
  r jsonb;
  v_id uuid;
  v_versao text;
  v_b1 uuid;
  v_b2 uuid;
  v_bump uuid;
  v_outra uuid;
  v_hist record;
  n_audit int;
  n int;
begin
  select user_id into v_ator from public.mind_admin_users
   where active and role in ('administrador', 'editor', 'aprovador') limit 1;
  if v_ator is null then raise exception 'sem administrador ativo em mind_admin_users para o teste'; end if;

  -- Dois produtos do Institute (têm programa, então terão leitor depois da virada) e um sem programa.
  select p.codigo into v_pa from catalogo.produtos p
   where exists (select 1 from institute.programas pr where pr.produto_codigo = p.codigo) order by p.codigo limit 1;
  select p.codigo into v_pb from catalogo.produtos p
   where exists (select 1 from institute.programas pr where pr.produto_codigo = p.codigo) and p.codigo <> v_pa
   order by p.codigo limit 1;
  select p.codigo into v_px from catalogo.produtos p
   where not exists (select 1 from institute.programas pr where pr.produto_codigo = p.codigo) order by p.codigo limit 1;
  select codigo into v_reservado from institute.ofertas order by codigo limit 1;
  select codigo into v_programa from institute.programas order by codigo limit 1;
  if v_pa is null or v_pb is null or v_px is null or v_reservado is null or v_programa is null then
    raise exception 'faltam produtos, ofertas ou programas do Institute para o teste'; end if;
  v_preco_pa := jsonb_build_object('produtoCodigo', v_pa, 'codigo', 'contrato-preco-a',
                                   'valor', 1997, 'parcelas', 12, 'valorParcela', 167);

  select count(*) into n_audit from public.mind_admin_audit where resource = 'offers';

  -- 1. Criar: nasce desligada, com preço e bônus; o bônus é grátis por padrão; texto aparado.
  r := public.mind_admin_mutate_ofertas('criar', null, jsonb_build_object(
         'codigo', 'contrato-oferta-a', 'nome', '  Oferta do contrato  ', 'tipo', 'periodo',
         'iniciaEm', '2030-01-01T00:00:00-03:00', 'encerraEm', '2030-01-31T23:59:59-03:00',
         'meiosPagamento', jsonb_build_array('cartao', 'pix'),
         'precos', jsonb_build_array(v_preco_pa),
         'bonus', jsonb_build_array(jsonb_build_object('produtoCodigo', v_pa, 'inclusoCodigo', v_px,
                                                       'nome', 'Bônus do contrato', 'valorReferencia', 100))),
       null, v_ator, gen_random_uuid());
  v_id := (r->>'id')::uuid;
  if (r->>'ativo')::boolean or r->>'situacao' <> 'desligada' or r->>'nome' <> 'Oferta do contrato'
     or (r->>'jaFoiAoAr')::boolean or (r->>'historico')::boolean
     or jsonb_array_length(r->'precos') <> 1 or r->'precos'->0->>'codigo' <> 'contrato-preco-a'
     or (r->'precos'->0->>'valor')::numeric <> 1997 or r->'precos'->0->>'moeda' <> 'BRL'
     or jsonb_array_length(r->'bonus') <> 1 or (r->'bonus'->0->>'valor')::numeric <> 0
     or r->'meiosPagamento' <> '["cartao", "pix"]'::jsonb then
    raise exception 'criar: %', r; end if;
  -- Antes da virada, ninguém lê o catálogo: pôr no ar fica travado, com o motivo.
  if r->>'bloqueioPorNoAr' is distinct from 'sem_leitor' then
    raise exception 'criar: bloqueio antes da virada = %', r->>'bloqueioPorNoAr'; end if;
  if jsonb_array_length(r->'alteracoes') <> 1 or r->'alteracoes'->0->>'acao' <> 'criar' then
    raise exception 'criar: alterações = %', r->'alteracoes'; end if;
  if not exists (select 1 from public.mind_admin_audit
                  where resource = 'offers' and action = 'criar' and record_id = v_id::text
                    and actor_user_id = v_ator and before_data is null
                    and after_data->>'codigo' = 'contrato-oferta-a' and after_data->'alteracoes' is null) then
    raise exception 'criar: auditoria'; end if;
  v_versao := r->>'atualizadoEm';

  -- 2. Recusas na criação, cada uma com o seu motivo, e nada fica.
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object('codigo', v_reservado), null, v_ator, 'admin_validation:codigo_repetido');
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object('codigo', v_programa), null, v_ator, 'admin_validation:codigo_repetido');
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object('codigo', v_pa), null, v_ator, 'admin_validation:codigo_repetido');
  perform pg_temp.recusa('criar', null, v_base || '{"codigo":"contrato-oferta-a"}', null, v_ator, 'admin_validation:codigo_repetido');
  perform pg_temp.recusa('criar', null, v_base || '{"codigo":"contrato-preco-a"}', null, v_ator, 'admin_validation:codigo_repetido');
  perform pg_temp.recusa('criar', null, v_base || '{"codigo":"Com Espaço"}', null, v_ator, 'admin_validation:codigo_invalido');
  perform pg_temp.recusa('criar', null, v_base - 'codigo', null, v_ator, 'admin_validation:codigo_obrigatorio');
  perform pg_temp.recusa('criar', null, v_base || '{"nome":"   "}', null, v_ator, 'admin_validation:nome_obrigatorio');
  perform pg_temp.recusa('criar', null, v_base || '{"tipo":"lote"}', null, v_ator, 'admin_validation:tipo_invalido');
  perform pg_temp.recusa('criar', null, v_base || '{"tipo":"base","encerraEm":"2030-01-01T00:00:00-03:00"}', null, v_ator, 'admin_validation:base_sem_prazo');
  perform pg_temp.recusa('criar', null, v_base || '{"iniciaEm":"2030-02-01T00:00:00-03:00","encerraEm":"2030-01-01T00:00:00-03:00"}', null, v_ator, 'admin_validation:janela_invertida');
  perform pg_temp.recusa('criar', null, v_base || '{"ativo":true}', null, v_ator, 'admin_validation:ativo_pelos_botoes');
  perform pg_temp.recusa('criar', null, v_base || '{"historico":false}', null, v_ator, 'admin_validation:historico_so_leitura');
  perform pg_temp.recusa('criar', null, v_base || '{"meiosPagamento":["cheque"]}', null, v_ator, 'admin_validation:meios_pagamento');
  perform pg_temp.recusa('criar', null, v_base || '{"meiosPagamento":["pix","pix"]}', null, v_ator, 'admin_validation:meios_pagamento');
  perform pg_temp.recusa('criar', null, v_base || '{"iniciaEm":"amanhã"}', null, v_ator, 'admin_validation:dados_invalidos');
  -- preços
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object('precos', jsonb_build_array(
    jsonb_build_object('produtoCodigo', v_pa, 'codigo', 'contrato-b-p', 'valor', 1997, 'parcelas', 12, 'valorParcela', 180))),
    null, v_ator, 'admin_validation:parcela_nao_fecha');
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object('precos', jsonb_build_array(
    jsonb_build_object('produtoCodigo', v_pa, 'codigo', 'contrato-b-p', 'valor', 1997, 'parcelas', 12, 'valorParcela', 166))),
    null, v_ator, 'admin_validation:parcela_nao_fecha');
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object('precos', jsonb_build_array(
    jsonb_build_object('produtoCodigo', v_pa, 'codigo', 'contrato-b-p', 'valor', 1997, 'parcelas', 12))),
    null, v_ator, 'admin_validation:parcelas_incompletas');
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object('precos', jsonb_build_array(
    jsonb_build_object('produtoCodigo', v_pa, 'codigo', 'contrato-b-p', 'valor', -1))),
    null, v_ator, 'admin_validation:preco_negativo');
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object('precos', jsonb_build_array(
    jsonb_build_object('produtoCodigo', v_pa, 'codigo', 'contrato-b-p', 'valor', 10.005))),
    null, v_ator, 'admin_validation:centavos');
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object('precos', jsonb_build_array(
    jsonb_build_object('produtoCodigo', 'produto-que-nao-existe', 'codigo', 'contrato-b-p', 'valor', 10))),
    null, v_ator, 'admin_validation:produto_desconhecido');
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object('precos', jsonb_build_array(
    jsonb_build_object('produtoCodigo', v_pa, 'codigo', 'contrato-b-p', 'valor', 10),
    jsonb_build_object('produtoCodigo', v_pa, 'codigo', 'contrato-b-q', 'valor', 10))),
    null, v_ator, 'admin_validation:preco_repetido');
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object('precos', jsonb_build_array(
    jsonb_build_object('produtoCodigo', v_pa, 'codigo', 'contrato-b-p', 'valor', 10),
    jsonb_build_object('produtoCodigo', v_pb, 'codigo', 'contrato-b-p', 'valor', 10))),
    null, v_ator, 'admin_validation:codigo_repetido');
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object('precos', jsonb_build_array(
    jsonb_build_object('produtoCodigo', v_pa, 'valor', 10))),
    null, v_ator, 'admin_validation:codigo_do_preco_obrigatorio');
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object('precos', jsonb_build_array(
    jsonb_build_object('produtoCodigo', v_pa, 'codigo', v_reservado, 'valor', 10))),
    null, v_ator, 'admin_validation:codigo_repetido');
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object('precos', jsonb_build_array(
    jsonb_build_object('produtoCodigo', v_pa, 'codigo', 'contrato-b-p', 'valor', 10, 'checkoutUrl', 'http://sem-tls.example'))),
    null, v_ator, 'admin_validation:link_invalido');
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object('precos', jsonb_build_array(
    jsonb_build_object('produtoCodigo', v_pa, 'codigo', 'contrato-b-p', 'valor', 10, 'sistemaExterno', 'outro'))),
    null, v_ator, 'admin_validation:sistema_externo');
  -- bônus
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object(
    'precos', jsonb_build_array(jsonb_build_object('produtoCodigo', v_pa, 'codigo', 'contrato-b-p', 'valor', 10)),
    'bonus', jsonb_build_array(jsonb_build_object('produtoCodigo', v_pb, 'inclusoCodigo', v_px))),
    null, v_ator, 'admin_validation:bonus_sem_preco');
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object(
    'precos', jsonb_build_array(jsonb_build_object('produtoCodigo', v_pa, 'codigo', 'contrato-b-p', 'valor', 10)),
    'bonus', jsonb_build_array(jsonb_build_object('produtoCodigo', v_pa, 'inclusoCodigo', v_pa))),
    null, v_ator, 'admin_validation:bonus_de_si_mesmo');
  -- exigências
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object(
    'requer', jsonb_build_array(jsonb_build_object('produtoCodigo', v_pb))),
    null, v_ator, 'admin_validation:requer_so_condicional');
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object('tipo', 'condicional',
    'requer', jsonb_build_array(jsonb_build_object('produtoCodigo', v_pb, 'modo', 'sempre'))),
    null, v_ator, 'admin_validation:requer_modo');
  perform pg_temp.recusa('criar', null, v_base || jsonb_build_object('tipo', 'condicional',
    'requer', jsonb_build_array(jsonb_build_object('produtoCodigo', v_pb), jsonb_build_object('produtoCodigo', v_pb))),
    null, v_ator, 'admin_validation:requer_repetido');

  if exists (select 1 from catalogo.ofertas where codigo like 'contrato-b%')
     or exists (select 1 from catalogo.oferta_precos where codigo like 'contrato-b%') then
    raise exception 'recusa na criação deixou rastro'; end if;
  select count(*) into n from public.mind_admin_audit where resource = 'offers';
  if n <> n_audit + 1 then raise exception 'recusa deixou auditoria: % linhas novas', n - n_audit; end if;

  -- 3. Atualizar: versão obrigatória e conferida; só o que veio muda; mexer num preço é versão nova.
  perform pg_temp.recusa('atualizar', v_id, '{"nome":"Y"}', null, v_ator, 'admin_validation:versao_obrigatoria');
  perform pg_temp.recusa('atualizar', v_id, '{"nome":"Y"}', '2000-01-01T00:00:00Z', v_ator, 'admin_conflict');
  r := public.mind_admin_mutate_ofertas('atualizar', v_id, '{"descricao":"  Descrição do contrato "}', v_versao, v_ator, gen_random_uuid());
  if r->>'descricao' <> 'Descrição do contrato' or r->>'nome' <> 'Oferta do contrato'
     or r->>'codigo' <> 'contrato-oferta-a' or jsonb_array_length(r->'precos') <> 1
     or (r->>'atualizadoEm')::timestamptz <= v_versao::timestamptz then
    raise exception 'atualizar: %', r; end if;
  v_versao := r->>'atualizadoEm';
  r := public.mind_admin_mutate_ofertas('atualizar', v_id, jsonb_build_object('precos', jsonb_build_array(
         v_preco_pa || '{"valor":1497,"valorParcela":125}')), v_versao, v_ator, gen_random_uuid());
  if (r->'precos'->0->>'valor')::numeric <> 1497 or (r->'precos'->0->>'valorParcela')::numeric <> 125
     or jsonb_array_length(r->'bonus') <> 1 or (r->>'atualizadoEm')::timestamptz <= v_versao::timestamptz then
    raise exception 'mudar o preço: %', r; end if;
  if not exists (select 1 from public.mind_admin_audit
                  where resource = 'offers' and action = 'atualizar' and record_id = v_id::text
                    and (before_data->'precos'->0->>'valor')::numeric = 1997
                    and (after_data->'precos'->0->>'valor')::numeric = 1497) then
    raise exception 'auditoria do preço sem o antes e o depois'; end if;
  v_versao := r->>'atualizadoEm';

  -- Rascunho que nunca foi ao ar: troca código e perde linha (o bônus do produto que saiu vai junto).
  r := public.mind_admin_mutate_ofertas('atualizar', v_id, jsonb_build_object('codigo', 'contrato-oferta-a2',
         'precos', jsonb_build_array(v_preco_pa || '{"valor":1497,"valorParcela":125}',
                                     jsonb_build_object('produtoCodigo', v_pb, 'codigo', 'contrato-preco-b', 'valor', 997))),
       v_versao, v_ator, gen_random_uuid());
  if r->>'codigo' <> 'contrato-oferta-a2' or jsonb_array_length(r->'precos') <> 2 or jsonb_array_length(r->'bonus') <> 1 then
    raise exception 'rascunho: troca de código e preço novo: %', r; end if;
  v_versao := r->>'atualizadoEm';
  r := public.mind_admin_mutate_ofertas('atualizar', v_id, jsonb_build_object('precos', jsonb_build_array(
         jsonb_build_object('produtoCodigo', v_pb, 'codigo', 'contrato-preco-b', 'valor', 997))),
       v_versao, v_ator, gen_random_uuid());
  if jsonb_array_length(r->'precos') <> 1 or r->'precos'->0->>'produtoCodigo' <> v_pb or jsonb_array_length(r->'bonus') <> 0 then
    raise exception 'rascunho: tirar a linha: %', r; end if;
  v_versao := r->>'atualizadoEm';

  -- 4. Pôr no ar antes da virada: ninguém lê o catálogo, e a recusa não deixa rastro.
  perform pg_temp.recusa('publicar', v_id, '{}', v_versao, v_ator, 'admin_validation:sem_leitor');
  if (select atualizado_em from catalogo.ofertas where id = v_id) <> v_versao::timestamptz
     or (select ativo from catalogo.ofertas where id = v_id) then
    raise exception 'recusa de pôr no ar mexeu na oferta'; end if;

  -- 5. Depois da virada, ensaiado aqui dentro: api.ofertas lendo o catálogo. Produto sem programa no
  --    Institute continua sem leitor.
  create or replace function catalogo.produto_tem_leitor(p_produto_id uuid)
  returns boolean language sql stable set search_path to 'pg_catalog', 'public'
  as $f$ select exists (select 1 from catalogo.produtos p join institute.programas pr on pr.produto_codigo = p.codigo
                         where p.id = p_produto_id) $f$;

  if public.mind_admin_read_ofertas(v_id)->0->>'bloqueioPorNoAr' is not null then
    raise exception 'depois da virada, nada devia bloquear: %', public.mind_admin_read_ofertas(v_id)->0->>'bloqueioPorNoAr'; end if;
  r := public.mind_admin_mutate_ofertas('publicar', v_id, '{}', v_versao, v_ator, gen_random_uuid());
  if not (r->>'ativo')::boolean or r->>'situacao' <> 'agendada' or not (r->>'jaFoiAoAr')::boolean
     or r->>'bloqueioPorNoAr' is not null then
    raise exception 'pôr no ar: %', r; end if;
  v_versao := r->>'atualizadoEm';
  -- Já no ar: pôr de novo não muda nada, nem a versão.
  r := public.mind_admin_mutate_ofertas('publicar', v_id, '{}', v_versao, v_ator, gen_random_uuid());
  if r->>'atualizadoEm' <> v_versao then raise exception 'pôr no ar de novo mudou a versão'; end if;

  -- No ar: código não muda, linha não sai, preço muda.
  perform pg_temp.recusa('atualizar', v_id, '{"codigo":"contrato-oferta-a3"}', v_versao, v_ator, 'admin_validation:codigo_nao_editavel');
  perform pg_temp.recusa('atualizar', v_id, '{"precos":[]}', v_versao, v_ator, 'admin_validation:linha_nao_se_remove');
  perform pg_temp.recusa('atualizar', v_id, jsonb_build_object('precos', jsonb_build_array(
    jsonb_build_object('produtoCodigo', v_pb, 'codigo', 'contrato-preco-b2', 'valor', 997))),
    v_versao, v_ator, 'admin_validation:codigo_nao_editavel');
  perform pg_temp.recusa('atualizar', v_id, jsonb_build_object('precos', jsonb_build_array(
    jsonb_build_object('produtoCodigo', v_pb, 'codigo', 'contrato-preco-b'))),
    v_versao, v_ator, 'admin_validation:sem_preco');
  r := public.mind_admin_mutate_ofertas('atualizar', v_id, jsonb_build_object('precos', jsonb_build_array(
         jsonb_build_object('produtoCodigo', v_pb, 'codigo', 'contrato-preco-b', 'valor', 897))),
       v_versao, v_ator, gen_random_uuid());
  if (r->'precos'->0->>'valor')::numeric <> 897 or not (r->>'ativo')::boolean then raise exception 'no ar: mudar o preço: %', r; end if;
  v_versao := r->>'atualizadoEm';

  -- O que impede pôr no ar, um motivo de cada vez.
  r := public.mind_admin_mutate_ofertas('criar', null, v_base || jsonb_build_object('codigo', 'contrato-sem-valor',
         'precos', jsonb_build_array(jsonb_build_object('produtoCodigo', v_pa, 'codigo', 'contrato-sem-valor'))),
       null, v_ator, gen_random_uuid());
  perform pg_temp.recusa('publicar', (r->>'id')::uuid, '{}', r->>'atualizadoEm', v_ator, 'admin_validation:sem_preco');
  r := public.mind_admin_mutate_ofertas('criar', null, v_base || '{"codigo":"contrato-sem-linha"}', null, v_ator, gen_random_uuid());
  perform pg_temp.recusa('publicar', (r->>'id')::uuid, '{}', r->>'atualizadoEm', v_ator, 'admin_validation:sem_preco');
  r := public.mind_admin_mutate_ofertas('criar', null, v_base || jsonb_build_object('codigo', 'contrato-vencida',
         'iniciaEm', '2020-01-01T00:00:00-03:00', 'encerraEm', '2020-01-31T23:59:59-03:00',
         'precos', jsonb_build_array(jsonb_build_object('produtoCodigo', v_pa, 'codigo', 'contrato-vencida', 'valor', 10))),
       null, v_ator, gen_random_uuid());
  if r->>'bloqueioPorNoAr' <> 'prazo_vencido' then raise exception 'vencida: bloqueio = %', r->>'bloqueioPorNoAr'; end if;
  perform pg_temp.recusa('publicar', (r->>'id')::uuid, '{}', r->>'atualizadoEm', v_ator, 'admin_validation:prazo_vencido');
  -- Prorrogar a vencida (inclusive de oferta encerrada) é editar o fim; depois ela pode ir ao ar.
  r := public.mind_admin_mutate_ofertas('atualizar', (r->>'id')::uuid, '{"encerraEm":"2030-12-31T23:59:59-03:00"}',
         r->>'atualizadoEm', v_ator, gen_random_uuid());
  if r->>'bloqueioPorNoAr' is not null then raise exception 'prorrogada: bloqueio = %', r->>'bloqueioPorNoAr'; end if;
  r := public.mind_admin_mutate_ofertas('criar', null, v_base || jsonb_build_object('codigo', 'contrato-sem-leitor',
         'precos', jsonb_build_array(jsonb_build_object('produtoCodigo', v_px, 'codigo', 'contrato-sem-leitor', 'valor', 10))),
       null, v_ator, gen_random_uuid());
  perform pg_temp.recusa('publicar', (r->>'id')::uuid, '{}', r->>'atualizadoEm', v_ator, 'admin_validation:sem_leitor');

  -- Order bump: condicional só vai ao ar com exigência; no ar, não perde a exigência nem deixa de ser condicional.
  r := public.mind_admin_mutate_ofertas('criar', null, jsonb_build_object('codigo', 'contrato-bump', 'nome', 'Bump do contrato',
         'tipo', 'condicional',
         'precos', jsonb_build_array(jsonb_build_object('produtoCodigo', v_pa, 'codigo', 'contrato-bump', 'valor', 497,
                                                        'valorRiscado', 997))),
       null, v_ator, gen_random_uuid());
  v_bump := (r->>'id')::uuid;
  perform pg_temp.recusa('publicar', v_bump, '{}', r->>'atualizadoEm', v_ator, 'admin_validation:condicional_sem_exigencia');
  r := public.mind_admin_mutate_ofertas('atualizar', v_bump, jsonb_build_object('requer', jsonb_build_array(
         jsonb_build_object('produtoCodigo', v_pb, 'grupoExclusivo', 'contrato', 'observacao', 'no checkout do outro'))),
       r->>'atualizadoEm', v_ator, gen_random_uuid());
  if r->'requer'->0->>'modo' <> 'carrinho' or (r->'requer'->0->>'prioridade')::int <> 100
     or not (r->'requer'->0->>'ativo')::boolean then raise exception 'exigência com os padrões: %', r->'requer'; end if;
  r := public.mind_admin_mutate_ofertas('publicar', v_bump, '{}', r->>'atualizadoEm', v_ator, gen_random_uuid());
  if not (r->>'ativo')::boolean or r->>'situacao' <> 'no_ar' then raise exception 'bump no ar: %', r; end if;
  perform pg_temp.recusa('atualizar', v_bump, '{"requer":[]}', r->>'atualizadoEm', v_ator, 'admin_validation:linha_nao_se_remove');
  perform pg_temp.recusa('atualizar', v_bump, '{"tipo":"periodo"}', r->>'atualizadoEm', v_ator, 'admin_validation:requer_so_condicional');
  perform pg_temp.recusa('atualizar', v_bump, jsonb_build_object('requer', jsonb_build_array(
    jsonb_build_object('produtoCodigo', v_pb, 'ativo', false))), r->>'atualizadoEm', v_ator, 'admin_validation:condicional_sem_exigencia');

  -- Por produto, um preço sem prazo no ar.
  r := public.mind_admin_mutate_ofertas('criar', null, jsonb_build_object('codigo', 'contrato-base-1', 'nome', 'Balcão 1',
         'tipo', 'base', 'precos', jsonb_build_array(jsonb_build_object('produtoCodigo', v_pb, 'codigo', 'contrato-base-1',
                                                                         'valor', 2497, 'parcelas', 12, 'valorParcela', 209))),
       null, v_ator, gen_random_uuid());
  v_b1 := (r->>'id')::uuid;
  r := public.mind_admin_mutate_ofertas('publicar', v_b1, '{}', r->>'atualizadoEm', v_ator, gen_random_uuid());
  if not (r->>'ativo')::boolean then raise exception 'base 1 no ar: %', r; end if;
  r := public.mind_admin_mutate_ofertas('criar', null, jsonb_build_object('codigo', 'contrato-base-2', 'nome', 'Balcão 2',
         'tipo', 'base', 'precos', jsonb_build_array(jsonb_build_object('produtoCodigo', v_pb, 'codigo', 'contrato-base-2',
                                                                         'valor', 2297))),
       null, v_ator, gen_random_uuid());
  v_b2 := (r->>'id')::uuid;
  if r->>'bloqueioPorNoAr' <> 'base_duplicada' then raise exception 'base 2: bloqueio = %', r->>'bloqueioPorNoAr'; end if;
  perform pg_temp.recusa('publicar', v_b2, '{}', r->>'atualizadoEm', v_ator, 'admin_validation:base_duplicada');

  -- Aviso, não recusa: outra oferta com prazo valendo junto para o mesmo produto.
  r := public.mind_admin_mutate_ofertas('criar', null, jsonb_build_object('codigo', 'contrato-outra', 'nome', 'Outra condição',
         'tipo', 'periodo', 'iniciaEm', '2030-01-15T00:00:00-03:00', 'encerraEm', '2030-02-15T23:59:59-03:00',
         'precos', jsonb_build_array(jsonb_build_object('produtoCodigo', v_pb, 'codigo', 'contrato-outra', 'valor', 1797))),
       null, v_ator, gen_random_uuid());
  v_outra := (r->>'id')::uuid;
  if r->'sobrepostas' <> '["contrato-oferta-a2"]'::jsonb or r->>'bloqueioPorNoAr' is not null then
    raise exception 'sobrepostas: %', r->'sobrepostas'; end if;
  if public.mind_admin_read_ofertas(v_id)->0->'sobrepostas' <> '[]'::jsonb then
    raise exception 'a outra ainda não está ligada: não devia aparecer'; end if;

  -- Tirar do ar: desliga, e o código continua travado (já esteve no ar).
  r := public.mind_admin_mutate_ofertas('arquivar', v_id, '{}', v_versao, v_ator, gen_random_uuid());
  if (r->>'ativo')::boolean or r->>'situacao' <> 'desligada' or not (r->>'jaFoiAoAr')::boolean
     or r->>'bloqueioPorNoAr' is not null then
    raise exception 'tirar do ar: %', r; end if;
  v_versao := r->>'atualizadoEm';
  perform pg_temp.recusa('atualizar', v_id, '{"codigo":"contrato-oferta-a3"}', v_versao, v_ator, 'admin_validation:codigo_nao_editavel');
  if (select count(*) from catalogo.ofertas where id = v_id) <> 1 then raise exception 'tirar do ar apagou a oferta'; end if;

  -- O histórico de alterações da oferta, do mais novo para o mais antigo, com quem fez e o que mudou.
  r := public.mind_admin_read_ofertas(v_id)->0;
  if (select array_agg(e->>'acao' order by ord) from jsonb_array_elements(r->'alteracoes') with ordinality as t(e, ord))
     <> array['arquivar', 'atualizar', 'publicar', 'atualizar', 'atualizar', 'atualizar', 'atualizar', 'criar'] then
    raise exception 'alterações: %', r->'alteracoes'; end if;
  if not (r->'alteracoes'->4->'campos' ? 'codigo') or not (r->'alteracoes'->4->'campos' ? 'precos')
     or (r->'alteracoes'->5->'campos') <> '["precos"]'::jsonb
     or (r->'alteracoes'->6->'campos') <> '["descricao"]'::jsonb
     or not (r->'alteracoes'->0 ? 'por') then
    raise exception 'alterações: campos = % / % / %', r->'alteracoes'->4->'campos', r->'alteracoes'->5->'campos',
      r->'alteracoes'->6->'campos'; end if;
  if public.mind_admin_read_ofertas()->0->'alteracoes' <> 'null'::jsonb then
    raise exception 'a lista não traz o histórico de cada oferta'; end if;

  -- 6. Histórico importado: só leitura, pela marca, inclusive para pôr no ar.
  select o.id, o.atualizado_em into v_hist from catalogo.ofertas o where o.historico order by o.codigo limit 1;
  if not found then raise exception 'sem oferta histórica para o teste'; end if;
  perform pg_temp.recusa('atualizar', v_hist.id, '{"nome":"X"}', v_hist.atualizado_em::text, v_ator, 'admin_validation:historico_so_leitura');
  perform pg_temp.recusa('publicar', v_hist.id, '{}', v_hist.atualizado_em::text, v_ator, 'admin_validation:historico_so_leitura');
  perform pg_temp.recusa('arquivar', v_hist.id, '{}', v_hist.atualizado_em::text, v_ator, 'admin_validation:historico_so_leitura');

  -- 7. Quem não está no painel não escreve; oferta inexistente; ação que não existe.
  perform pg_temp.recusa('criar', null, v_base, null, gen_random_uuid(), 'admin_forbidden');
  perform pg_temp.recusa('atualizar', gen_random_uuid(), '{"nome":"X"}', v_versao, v_ator, 'admin_not_found');
  perform pg_temp.recusa('apagar', v_id, '{}', v_versao, v_ator, 'admin_validation:acao_invalida');
  perform pg_temp.recusa('atualizar', v_id, '[1]', v_versao, v_ator, 'admin_validation:corpo_invalido');

  -- 8. Permissões: só o sistema chama; as regras internas não são porta de ninguém.
  if has_function_privilege('anon', 'public.mind_admin_mutate_ofertas(text, uuid, jsonb, text, uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.mind_admin_mutate_ofertas(text, uuid, jsonb, text, uuid, uuid)', 'execute')
     or not has_function_privilege('service_role', 'public.mind_admin_mutate_ofertas(text, uuid, jsonb, text, uuid, uuid)', 'execute')
     or has_function_privilege('anon', 'public.mind_admin_read_ofertas(uuid, timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.mind_admin_read_ofertas(uuid, timestamptz)', 'execute') then
    raise exception 'permissões das portas de ofertas'; end if;
  if exists (select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname = 'catalogo'
                and p.proname in ('produto_tem_leitor', 'codigo_reservado', 'oferta_ja_foi_ao_ar', 'oferta_bloqueio', 'oferta_sobrepostas')
                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                     or has_function_privilege('service_role', p.oid, 'execute'))) then
    raise exception 'regra interna executável de fora'; end if;
  if not (select prosecdef from pg_proc where oid = 'public.mind_admin_mutate_ofertas(text, uuid, jsonb, text, uuid, uuid)'::regprocedure) then
    raise exception 'a porta de escrita devia rodar como dona'; end if;

  raise exception 'OFERTAS_EDICAO_OK: criar (desligada, com preço e bônus), 57 recusas com o motivo certo e sem rastro, versão e conflito, preço muda a versão com antes e depois na auditoria, rascunho troca código e perde linha, pôr no ar travado antes da virada e liberado depois, no ar sem troca de código nem perda de linha, sem preço, vencida e prorrogada, sem leitor, bump com exigência, base única por produto, sobrepostas, tirar do ar, histórico de alterações, histórico importado só leitura, papel, inexistente e permissões conferem';
end $$;
rollback;
