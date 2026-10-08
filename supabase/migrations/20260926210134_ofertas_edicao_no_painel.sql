-- PAINEL: AS OFERTAS DO CATÁLOGO SE EDITAM PELO PAINEL (PASSO 4).
--
-- Pedido da Adriana (26/09/2026): "todas as infos importantes deste schema devem ser espelhadas e editáveis
-- via painel" — o painel é o controle do schema `catalogo`. Passo 4 de docs/PLANO_OFERTAS_PASSO_A_PASSO.md.
-- Sem D2: função nova e fechada, numa casa que já existe (catalogo.ofertas e as três filhas, Passo 3).
--
-- Uma porta de escrita, no molde de mind_admin_mutate_catalogo — só o service_role executa (a
-- mindagent-catalogo chama), o papel é conferido de novo, trava de versão, antes e depois em
-- mind_admin_audit (resource = 'offers'):
--   · mind_admin_mutate_ofertas(p_action, ...), quatro ações:
--       criar        a oferta nasce desligada (rascunho), já com preços, bônus e exigências;
--       atualizar    muda só o que veio; lista que vem (precos, bonus, requer) é a lista inteira;
--       publicar     põe no ar (liga), se nada bloqueia (abaixo);
--       arquivar     tira do ar (desliga). Nenhuma oferta se apaga.
--     Os nomes das ações são os que mind_admin_audit já aceita (mind_admin_audit_action_check).
--     Mexer num preço, bônus ou exigência também muda a versão da oferta (atualizado_em).
--
-- Regras. Cada recusa volta como admin_validation:<motivo>, que a função do painel traduz:
--   · histórico importado é só leitura, pela marca explícita (historico) — não por estar encerrado;
--   · código: letras minúsculas, números e hífen; não repete código de outra oferta, de outro preço, de
--     programa ou de produto, nem os 16 de institute.ofertas, que a virada (Passo 5) carrega; e não muda
--     depois que a oferta esteve no ar (links, pedidos e acessos usam o código);
--   · oferta que já esteve no ar não perde linha de preço, bônus ou exigência — só muda;
--   · preço não negativo e em centavos; parcelas e valor da parcela vão juntos e fecham com o à vista:
--     parcelas × parcela fica entre o à vista e o à vista + R$ 1 por parcela (o arredondamento de hoje:
--     R$ 5.997 em 12 × R$ 500);
--   · preço sem prazo (base) não tem janela; janela coerente;
--   · exigência (order bump / upgrade) só em oferta condicional, e condicional só vai ao ar com exigência;
--   · por produto, no máximo um preço sem prazo no ar (com dois, a página mostra um e o agente cita outro);
--   · só vai ao ar oferta com preço em todas as linhas, com prazo aberto e de produto que alguém lê: os do
--     Institute depois da virada (quando api.ofertas passar a ler catalogo.ofertas); os outros, quando um
--     site passar a ler. Antes disso, pôr no ar não chegaria a ninguém e quebraria a paridade da virada.
--   Aviso, não recusa: outra oferta com prazo valendo ao mesmo tempo para o mesmo produto (sobrepostas).
--   A regra do plano "nenhuma condicional no ar enquanto nenhuma página usar bump" caiu com a decisão dela
--   de 26/09: "não tira bumps do ar".
--
-- mind_admin_read_ofertas ganha jaFoiAoAr, bloqueioPorNoAr (o motivo, se "pôr no ar" seria recusado agora),
-- sobrepostas e, na leitura de uma oferta só, alteracoes (quem mudou o quê e quando).
--
-- Contrato: tests/ofertas_edicao_contract.sql (termina em OFERTAS_EDICAO_OK).

-- O histórico de alterações de cada oferta sai da auditoria, por oferta.
create index if not exists mind_admin_audit_ofertas_idx
  on public.mind_admin_audit (record_id, occurred_at desc) where resource = 'offers';

-- Alguém lê as ofertas deste produto? Os sites do Institute leem api.ofertas, que só alcança produto com
-- programa em institute.programas; e só leem o catálogo depois da virada, quando api.ofertas depender de
-- catalogo.ofertas. Conferido na própria definição da view: a virada destrava sozinha, sem marca à mão.
create or replace function catalogo.produto_tem_leitor(p_produto_id uuid)
returns boolean
language sql
stable
set search_path to 'pg_catalog', 'public'
as $fn$
  select exists (
           select 1
             from catalogo.produtos p
             join institute.programas pr on pr.produto_codigo = p.codigo
            where p.id = p_produto_id
         )
     and exists (
           select 1
             from pg_catalog.pg_depend d
             join pg_catalog.pg_rewrite rw on rw.oid = d.objid
            where d.classid = 'pg_catalog.pg_rewrite'::regclass
              and d.refclassid = 'pg_catalog.pg_class'::regclass
              and d.refobjid = 'catalogo.ofertas'::regclass
              and rw.ev_class = 'api.ofertas'::regclass
         );
$fn$;

-- Código já usado por outra oferta, outro preço, programa ou produto — ou reservado para a virada.
create or replace function catalogo.codigo_reservado(p_codigo text, p_oferta_id uuid)
returns boolean
language sql
stable
set search_path to 'pg_catalog', 'public'
as $fn$
  select exists (select 1 from catalogo.ofertas o where o.codigo = p_codigo and o.id is distinct from p_oferta_id)
      or exists (select 1 from catalogo.oferta_precos op
                  where op.codigo = p_codigo and op.oferta_id is distinct from p_oferta_id)
      or exists (select 1 from institute.ofertas io where io.codigo = p_codigo)
      or exists (select 1 from institute.programas pr where pr.codigo = p_codigo)
      or exists (select 1 from catalogo.produtos p where p.codigo = p_codigo);
$fn$;

-- Já esteve no ar: ligada agora, histórico, carregada de outra casa, ou posta no ar pelo painel alguma vez.
create or replace function catalogo.oferta_ja_foi_ao_ar(p_oferta_id uuid)
returns boolean
language sql
stable
set search_path to 'pg_catalog', 'public'
as $fn$
  select o.ativo or o.historico or o.origem is not null
         or exists (select 1 from public.mind_admin_audit a
                     where a.resource = 'offers' and a.record_id = o.id::text and a.action = 'publicar')
    from catalogo.ofertas o
   where o.id = p_oferta_id;
$fn$;

-- O primeiro motivo que impede a oferta de estar no ar; nulo quando nada impede. Com p_ao_ligar, também
-- o que só vale na hora de ligar: prazo já terminado e produto que ninguém lê.
create or replace function catalogo.oferta_bloqueio(p_oferta_id uuid, p_agora timestamptz, p_ao_ligar boolean)
returns text
language sql
stable
set search_path to 'pg_catalog', 'public'
as $fn$
  select case
           when o.historico then 'historico_so_leitura'
           when not exists (select 1 from catalogo.oferta_precos op where op.oferta_id = o.id)
             or exists (select 1 from catalogo.oferta_precos op where op.oferta_id = o.id and op.valor is null)
             then 'sem_preco'
           when o.tipo = 'condicional'
            and not exists (select 1 from catalogo.oferta_requer rq where rq.oferta_id = o.id and rq.ativo)
             then 'condicional_sem_exigencia'
           when p_ao_ligar and o.encerra_em is not null and o.encerra_em <= p_agora then 'prazo_vencido'
           when p_ao_ligar
            and exists (select 1 from catalogo.oferta_precos op
                         where op.oferta_id = o.id and not catalogo.produto_tem_leitor(op.produto_id))
             then 'sem_leitor'
           when o.tipo = 'base'
            and exists (select 1
                          from catalogo.oferta_precos op
                          join catalogo.oferta_precos op2 on op2.produto_id = op.produto_id and op2.oferta_id <> o.id
                          join catalogo.ofertas o2 on o2.id = op2.oferta_id
                         where op.oferta_id = o.id and o2.ativo and not o2.historico and o2.tipo = 'base')
             then 'base_duplicada'
         end
    from catalogo.ofertas o
   where o.id = p_oferta_id;
$fn$;

-- Outras ofertas ligadas, com prazo, que valem ao mesmo tempo que esta para um mesmo produto.
create or replace function catalogo.oferta_sobrepostas(p_oferta_id uuid)
returns jsonb
language sql
stable
set search_path to 'pg_catalog', 'public'
as $fn$
  select coalesce(jsonb_agg(distinct o2.codigo order by o2.codigo), '[]'::jsonb)
    from catalogo.ofertas o
    join catalogo.oferta_precos op on op.oferta_id = o.id
    join catalogo.oferta_precos op2 on op2.produto_id = op.produto_id and op2.oferta_id <> o.id
    join catalogo.ofertas o2 on o2.id = op2.oferta_id
   where o.id = p_oferta_id
     and not o.historico and o.tipo <> 'condicional'
     and (o.inicia_em is not null or o.encerra_em is not null)
     and o2.ativo and not o2.historico and o2.tipo <> 'condicional'
     and (o2.inicia_em is not null or o2.encerra_em is not null)
     and coalesce(o.inicia_em, '-infinity'::timestamptz) <= coalesce(o2.encerra_em, 'infinity'::timestamptz)
     and coalesce(o2.inicia_em, '-infinity'::timestamptz) <= coalesce(o.encerra_em, 'infinity'::timestamptz);
$fn$;

create or replace function public.mind_admin_read_ofertas(p_id uuid default null, p_agora timestamptz default now())
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $fn$
  select coalesce(jsonb_agg(x.obj order by x.ordem, x.inicio desc nulls last, x.codigo), '[]'::jsonb)
  from (
    select o.codigo, o.inicia_em as inicio, s.ordem,
      jsonb_build_object(
        'id', o.id::text,
        'codigo', o.codigo,
        'nome', o.nome,
        'descricao', o.descricao,
        'tipo', o.tipo,
        'ativo', o.ativo,
        'publico', o.publico,
        'historico', o.historico,
        'iniciaEm', o.inicia_em,
        'encerraEm', o.encerra_em,
        'meiosPagamento', to_jsonb(o.meios_pagamento),
        'situacao', s.situacao,
        'situacaoOrdem', s.ordem,
        'noSite', coalesce(p.no_site, false),
        'verticais', coalesce(p.verticais, '[]'::jsonb),
        'produtos', coalesce(p.produtos, '[]'::jsonb),
        'precos', coalesce(p.precos, '[]'::jsonb),
        'bonus', coalesce(b.bonus, '[]'::jsonb),
        'requer', coalesce(r.requer, '[]'::jsonb),
        'origem', o.origem,
        'jaFoiAoAr', catalogo.oferta_ja_foi_ao_ar(o.id),
        'bloqueioPorNoAr', case when o.ativo then null else catalogo.oferta_bloqueio(o.id, p_agora, true) end,
        'sobrepostas', catalogo.oferta_sobrepostas(o.id),
        -- Quem mudou o quê e quando: só na leitura de uma oferta, que é o que o detalhe abre.
        'alteracoes', case when p_id is null then null else coalesce((
          select jsonb_agg(jsonb_build_object(
                   'acao', a.action,
                   'em', a.occurred_at,
                   'por', u.display_name,
                   'campos', coalesce((
                     select jsonb_agg(k.chave order by k.chave)
                       from jsonb_object_keys(coalesce(a.after_data, '{}'::jsonb)) as k(chave)
                      where a.before_data is not null
                        and k.chave not in ('atualizadoEm', 'situacao', 'situacaoOrdem', 'noSite', 'jaFoiAoAr',
                                            'bloqueioPorNoAr', 'sobrepostas', 'alteracoes')
                        and (a.before_data -> k.chave) is distinct from (a.after_data -> k.chave)
                   ), '[]'::jsonb)
                 ) order by a.occurred_at desc)
            from (select a0.* from public.mind_admin_audit a0
                   where a0.resource = 'offers' and a0.record_id = o.id::text
                   order by a0.occurred_at desc limit 50) a
            left join public.mind_admin_users u on u.user_id = a.actor_user_id
        ), '[]'::jsonb) end,
        'criadoEm', o.criado_em,
        'atualizadoEm', o.atualizado_em
      ) as obj
    from catalogo.ofertas o
    cross join lateral (
      select case
               when o.historico then 'historico'
               when not o.ativo then 'desligada'
               when o.inicia_em is not null and p_agora < o.inicia_em then 'agendada'
               when o.encerra_em is not null and p_agora > o.encerra_em then 'encerrada'
               when not o.publico then 'so_link'
               else 'no_ar'
             end as situacao
    ) s0
    cross join lateral (
      select s0.situacao,
             case s0.situacao
               when 'no_ar' then 1 when 'so_link' then 2 when 'agendada' then 3
               when 'encerrada' then 4 when 'desligada' then 5 else 6
             end as ordem
    ) s
    left join lateral (
      select
        jsonb_agg(jsonb_build_object(
          'codigo', op.codigo,
          'produtoId', pr.id::text,
          'produtoCodigo', pr.codigo,
          'produtoNome', pr.nome,
          'produtoVertical', pr.vertical,
          'produtoCategoria', pr.categoria,
          'nome', op.nome,
          'descricao', op.descricao,
          'valor', op.valor,
          'parcelas', op.parcelas,
          'valorParcela', op.valor_parcela,
          'valorRiscado', op.valor_riscado,
          'moeda', op.moeda,
          'ordem', op.ordem,
          'checkoutUrl', op.checkout_url,
          'sistemaExterno', op.sistema_externo,
          'skuExterno', op.sku_externo,
          'noSite', site.codigo is not null,
          'vigenteNoSite', coalesce(site.vigente, false),
          'eduzz', case when ez.eduzz_product_id is null then null
                        else jsonb_build_object('preco', ez.price_value, 'lidoEm', ez.last_synced_at,
                                                'arquivado', ez.arquivado) end
        ) order by op.ordem, pr.nome, op.codigo) as precos,
        jsonb_agg(distinct to_jsonb(pr.vertical)) filter (where pr.vertical is not null) as verticais,
        jsonb_agg(distinct to_jsonb(pr.codigo)) as produtos,
        bool_or(site.codigo is not null) as no_site
      from catalogo.oferta_precos op
      join catalogo.produtos pr on pr.id = op.produto_id
      left join api.ofertas site on site.codigo = op.codigo
      left join eduzz.produtos ez on ez.eduzz_product_id = op.sku_externo
      where op.oferta_id = o.id
    ) p on true
    left join lateral (
      select jsonb_agg(jsonb_build_object(
               'produtoCodigo', pp.codigo,
               'inclusoCodigo', pi.codigo,
               'inclusoNome', pi.nome,
               'nome', oi.nome,
               'descricao', oi.descricao,
               'detalhe', oi.detalhe,
               'nota', oi.nota,
               'valor', oi.valor,
               'valorReferencia', oi.valor_referencia,
               'iniciaEm', oi.inicia_em,
               'encerraEm', oi.encerra_em,
               'ordem', oi.ordem
             ) order by oi.ordem, pi.nome) as bonus
        from catalogo.oferta_inclui oi
        join catalogo.produtos pp on pp.id = oi.produto_id
        join catalogo.produtos pi on pi.id = oi.incluso_id
       where oi.oferta_id = o.id
    ) b on true
    left join lateral (
      select jsonb_agg(jsonb_build_object(
               'produtoCodigo', pq.codigo,
               'produtoNome', pq.nome,
               'modo', rq.modo,
               'prioridade', rq.prioridade,
               'grupoExclusivo', rq.grupo_exclusivo,
               'ativo', rq.ativo,
               'iniciaEm', rq.inicia_em,
               'encerraEm', rq.encerra_em,
               'observacao', rq.observacao,
               'ordem', rq.ordem
             ) order by rq.ordem, pq.nome) as requer
        from catalogo.oferta_requer rq
        join catalogo.produtos pq on pq.id = rq.produto_id
       where rq.oferta_id = o.id
    ) r on true
    where p_id is null or o.id = p_id
  ) x;
$fn$;

create or replace function public.mind_admin_mutate_ofertas(
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
set search_path to 'pg_catalog', 'public'
as $fn$
declare
  v_role text;
  v_atual catalogo.ofertas%rowtype;
  v_novo catalogo.ofertas%rowtype;
  v_id uuid;
  v_ja_foi boolean := false;
  v_before jsonb;
  v_after jsonb;
  v_motivo text;
  v_item jsonb;
  v_pos int;
  v_produto uuid;
  v_incluso uuid;
  v_codigo text;
  v_codigos text[] := '{}';
  v_precos uuid[] := '{}';
  v_pares text[] := '{}';
  v_exigidos uuid[] := '{}';
  v_valor numeric;
  v_parcelas smallint;
  v_valor_parcela numeric;
  v_riscado numeric;
  v_referencia numeric;
  v_ini timestamptz;
  v_fim timestamptz;
  v_link text;
  v_sistema text;
  v_modo text;
  v_existente catalogo.oferta_precos%rowtype;
begin
  -- Mesmas regras de papel das outras escritas do painel.
  select role into v_role
  from public.mind_admin_users
  where user_id = p_actor_id and active;

  if v_role is null or v_role not in ('administrador', 'editor', 'aprovador') then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  end if;
  if p_action is null or p_action not in ('criar', 'atualizar', 'publicar', 'arquivar') then
    raise exception using errcode = '22023', message = 'admin_validation:acao_invalida';
  end if;
  if p_action in ('criar', 'atualizar') and (p_payload is null or jsonb_typeof(p_payload) <> 'object') then
    raise exception using errcode = '22023', message = 'admin_validation:corpo_invalido';
  end if;
  p_payload := coalesce(p_payload, '{}'::jsonb);
  -- Ligar e desligar são ações próprias, com as regras delas; a marca de histórico não se edita.
  if p_payload ? 'ativo' then
    raise exception using errcode = '22023', message = 'admin_validation:ativo_pelos_botoes';
  end if;
  if p_payload ? 'historico' then
    raise exception using errcode = '22023', message = 'admin_validation:historico_so_leitura';
  end if;

  if p_action = 'criar' then
    v_id := gen_random_uuid();
    v_novo.id := v_id;
    v_novo.ativo := false;
    v_novo.historico := false;
    v_novo.publico := true;
    v_novo.meios_pagamento := '{}';
  else
    if p_id is null then
      raise exception using errcode = '22023', message = 'admin_validation:id_obrigatorio';
    end if;
    -- Trava a linha: entre conferir a versão e gravar, ninguém mais escreve nesta oferta.
    select * into v_atual from catalogo.ofertas where id = p_id for update;
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
    if v_atual.historico then
      raise exception using errcode = '22023', message = 'admin_validation:historico_so_leitura';
    end if;
    v_id := v_atual.id;
    v_novo := v_atual;
    v_ja_foi := catalogo.oferta_ja_foi_ao_ar(v_id);
    v_before := (public.mind_admin_read_ofertas(v_id)->0) - 'alteracoes';
  end if;

  if p_action = 'publicar' then
    if v_atual.ativo then
      return public.mind_admin_read_ofertas(v_id)->0;
    end if;
    -- Trava os produtos da oferta: duas pessoas não põem no ar, ao mesmo tempo, dois preços sem prazo
    -- do mesmo produto.
    perform 1 from catalogo.produtos pr
     where pr.id in (select op.produto_id from catalogo.oferta_precos op where op.oferta_id = v_id)
     order by pr.id
       for update;
    v_motivo := catalogo.oferta_bloqueio(v_id, now(), true);
    if v_motivo is not null then
      raise exception using errcode = '22023', message = 'admin_validation:' || v_motivo;
    end if;
    update catalogo.ofertas set ativo = true, atualizado_em = clock_timestamp() where id = v_id;

  elsif p_action = 'arquivar' then
    if not v_atual.ativo then
      return public.mind_admin_read_ofertas(v_id)->0;
    end if;
    update catalogo.ofertas set ativo = false, atualizado_em = clock_timestamp() where id = v_id;

  else
    -- ---------- criar / atualizar: a oferta ----------
    if p_payload ? 'codigo' then
      v_codigo := nullif(btrim(p_payload->>'codigo'), '');
      if v_codigo is distinct from v_novo.codigo then
        if v_ja_foi then
          raise exception using errcode = '22023', message = 'admin_validation:codigo_nao_editavel';
        end if;
        if v_codigo !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
          raise exception using errcode = '22023', message = 'admin_validation:codigo_invalido';
        end if;
        if catalogo.codigo_reservado(v_codigo, v_id) then
          raise exception using errcode = '22023', message = 'admin_validation:codigo_repetido';
        end if;
        v_novo.codigo := v_codigo;
      end if;
    end if;
    if v_novo.codigo is null then
      raise exception using errcode = '22023', message = 'admin_validation:codigo_obrigatorio';
    end if;
    if p_payload ? 'nome' then v_novo.nome := nullif(btrim(p_payload->>'nome'), ''); end if;
    if v_novo.nome is null then
      raise exception using errcode = '22023', message = 'admin_validation:nome_obrigatorio';
    end if;
    if p_payload ? 'descricao' then v_novo.descricao := nullif(btrim(p_payload->>'descricao'), ''); end if;
    if p_payload ? 'tipo' then v_novo.tipo := nullif(btrim(p_payload->>'tipo'), ''); end if;
    if v_novo.tipo is null or v_novo.tipo not in ('base', 'periodo', 'combo', 'condicional') then
      raise exception using errcode = '22023', message = 'admin_validation:tipo_invalido';
    end if;
    if p_payload ? 'publico' then v_novo.publico := coalesce((p_payload->>'publico')::boolean, true); end if;
    if p_payload ? 'iniciaEm' then v_novo.inicia_em := nullif(btrim(p_payload->>'iniciaEm'), '')::timestamptz; end if;
    if p_payload ? 'encerraEm' then v_novo.encerra_em := nullif(btrim(p_payload->>'encerraEm'), '')::timestamptz; end if;
    if v_novo.tipo = 'base' and (v_novo.inicia_em is not null or v_novo.encerra_em is not null) then
      raise exception using errcode = '22023', message = 'admin_validation:base_sem_prazo';
    end if;
    if v_novo.inicia_em >= v_novo.encerra_em then
      raise exception using errcode = '22023', message = 'admin_validation:janela_invertida';
    end if;
    if p_payload ? 'meiosPagamento' then
      if jsonb_typeof(p_payload->'meiosPagamento') not in ('array', 'null') then
        raise exception using errcode = '22023', message = 'admin_validation:meios_pagamento';
      end if;
      select coalesce(array_agg(btrim(e.v) order by e.o) filter (where btrim(e.v) <> ''), '{}')
        into v_novo.meios_pagamento
        from jsonb_array_elements_text(coalesce(nullif(p_payload->'meiosPagamento', 'null'::jsonb), '[]'::jsonb))
             with ordinality as e(v, o);
      if not (v_novo.meios_pagamento <@ array['cartao', 'pix', 'boleto'])
         or cardinality(v_novo.meios_pagamento)
            <> (select count(distinct m) from unnest(v_novo.meios_pagamento) m) then
        raise exception using errcode = '22023', message = 'admin_validation:meios_pagamento';
      end if;
    end if;

    if p_action = 'criar' then
      insert into catalogo.ofertas(id, codigo, nome, descricao, tipo, ativo, inicia_em, encerra_em, publico,
                                   meios_pagamento, historico, origem)
      values (v_id, v_novo.codigo, v_novo.nome, v_novo.descricao, v_novo.tipo, false, v_novo.inicia_em,
              v_novo.encerra_em, v_novo.publico, v_novo.meios_pagamento, false, null);
    else
      update catalogo.ofertas set
        codigo = v_novo.codigo,
        nome = v_novo.nome,
        descricao = v_novo.descricao,
        tipo = v_novo.tipo,
        publico = v_novo.publico,
        inicia_em = v_novo.inicia_em,
        encerra_em = v_novo.encerra_em,
        meios_pagamento = v_novo.meios_pagamento
      where id = v_id;
    end if;

    -- ---------- preços: um por produto; a lista que vem é a lista inteira ----------
    if p_payload ? 'precos' then
      if jsonb_typeof(p_payload->'precos') <> 'array' then
        raise exception using errcode = '22023', message = 'admin_validation:dados_invalidos';
      end if;
      v_pos := 0;
      for v_item in select e.value from jsonb_array_elements(p_payload->'precos') e loop
        v_pos := v_pos + 1;
        if jsonb_typeof(v_item) <> 'object' then
          raise exception using errcode = '22023', message = 'admin_validation:dados_invalidos';
        end if;
        select pr.id into v_produto from catalogo.produtos pr where pr.codigo = btrim(v_item->>'produtoCodigo');
        if v_produto is null then
          raise exception using errcode = '22023', message = 'admin_validation:produto_desconhecido';
        end if;
        if v_produto = any(v_precos) then
          raise exception using errcode = '22023', message = 'admin_validation:preco_repetido';
        end if;
        v_precos := v_precos || v_produto;

        v_codigo := nullif(btrim(v_item->>'codigo'), '');
        if v_codigo is null then
          raise exception using errcode = '22023', message = 'admin_validation:codigo_do_preco_obrigatorio';
        end if;
        if v_codigo !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
          raise exception using errcode = '22023', message = 'admin_validation:codigo_invalido';
        end if;
        if v_codigo = any(v_codigos) then
          raise exception using errcode = '22023', message = 'admin_validation:codigo_repetido';
        end if;
        v_codigos := v_codigos || v_codigo;
        select * into v_existente from catalogo.oferta_precos op where op.oferta_id = v_id and op.produto_id = v_produto;
        if found then
          if v_existente.codigo <> v_codigo then
            if v_ja_foi then
              raise exception using errcode = '22023', message = 'admin_validation:codigo_nao_editavel';
            end if;
            if catalogo.codigo_reservado(v_codigo, v_id) then
              raise exception using errcode = '22023', message = 'admin_validation:codigo_repetido';
            end if;
          end if;
        elsif catalogo.codigo_reservado(v_codigo, v_id) then
          raise exception using errcode = '22023', message = 'admin_validation:codigo_repetido';
        end if;

        v_valor := nullif(btrim(v_item->>'valor'), '')::numeric;
        v_parcelas := nullif(btrim(v_item->>'parcelas'), '')::smallint;
        v_valor_parcela := nullif(btrim(v_item->>'valorParcela'), '')::numeric;
        v_riscado := nullif(btrim(v_item->>'valorRiscado'), '')::numeric;
        if v_valor < 0 or v_valor_parcela < 0 or v_riscado < 0 then
          raise exception using errcode = '22023', message = 'admin_validation:preco_negativo';
        end if;
        if v_valor <> round(v_valor, 2) or v_valor_parcela <> round(v_valor_parcela, 2)
           or v_riscado <> round(v_riscado, 2) then
          raise exception using errcode = '22023', message = 'admin_validation:centavos';
        end if;
        if (v_parcelas is null) <> (v_valor_parcela is null) or v_parcelas < 1 then
          raise exception using errcode = '22023', message = 'admin_validation:parcelas_incompletas';
        end if;
        if v_valor is not null and v_parcelas is not null
           and (v_parcelas * v_valor_parcela < v_valor or v_parcelas * v_valor_parcela > v_valor + v_parcelas) then
          raise exception using errcode = '22023', message = 'admin_validation:parcela_nao_fecha';
        end if;
        v_link := nullif(btrim(v_item->>'checkoutUrl'), '');
        if v_link !~ '^https://[^[:space:]]+$' then
          raise exception using errcode = '22023', message = 'admin_validation:link_invalido';
        end if;
        v_sistema := nullif(btrim(v_item->>'sistemaExterno'), '');
        if v_sistema not in ('eduzz', 'infinitepay') then
          raise exception using errcode = '22023', message = 'admin_validation:sistema_externo';
        end if;

        insert into catalogo.oferta_precos(oferta_id, produto_id, codigo, nome, descricao, valor, parcelas,
                                           valor_parcela, valor_riscado, moeda, ordem, checkout_url,
                                           sistema_externo, sku_externo)
        values (v_id, v_produto, v_codigo, nullif(btrim(v_item->>'nome'), ''), nullif(btrim(v_item->>'descricao'), ''),
                v_valor, v_parcelas, v_valor_parcela, v_riscado,
                coalesce(nullif(upper(btrim(v_item->>'moeda')), ''), 'BRL'),
                coalesce(nullif(btrim(v_item->>'ordem'), '')::smallint, v_pos::smallint),
                v_link, v_sistema, nullif(btrim(v_item->>'skuExterno'), ''))
        on conflict (oferta_id, produto_id) do update set
          codigo = excluded.codigo,
          nome = excluded.nome,
          descricao = excluded.descricao,
          valor = excluded.valor,
          parcelas = excluded.parcelas,
          valor_parcela = excluded.valor_parcela,
          valor_riscado = excluded.valor_riscado,
          moeda = excluded.moeda,
          ordem = excluded.ordem,
          checkout_url = excluded.checkout_url,
          sistema_externo = excluded.sistema_externo,
          sku_externo = excluded.sku_externo;
      end loop;
      if exists (select 1 from catalogo.oferta_precos op where op.oferta_id = v_id and op.produto_id <> all(v_precos)) then
        if v_ja_foi then
          raise exception using errcode = '22023', message = 'admin_validation:linha_nao_se_remove';
        end if;
        delete from catalogo.oferta_precos op where op.oferta_id = v_id and op.produto_id <> all(v_precos);
      end if;
    end if;

    -- ---------- bônus: o que entra junto com o preço de um produto ----------
    if p_payload ? 'bonus' then
      if jsonb_typeof(p_payload->'bonus') <> 'array' then
        raise exception using errcode = '22023', message = 'admin_validation:dados_invalidos';
      end if;
      v_pos := 0;
      for v_item in select e.value from jsonb_array_elements(p_payload->'bonus') e loop
        v_pos := v_pos + 1;
        if jsonb_typeof(v_item) <> 'object' then
          raise exception using errcode = '22023', message = 'admin_validation:dados_invalidos';
        end if;
        select pr.id into v_produto from catalogo.produtos pr where pr.codigo = btrim(v_item->>'produtoCodigo');
        if v_produto is null
           or not exists (select 1 from catalogo.oferta_precos op where op.oferta_id = v_id and op.produto_id = v_produto) then
          raise exception using errcode = '22023', message = 'admin_validation:bonus_sem_preco';
        end if;
        select pr.id into v_incluso from catalogo.produtos pr where pr.codigo = btrim(v_item->>'inclusoCodigo');
        if v_incluso is null then
          raise exception using errcode = '22023', message = 'admin_validation:produto_desconhecido';
        end if;
        if v_incluso = v_produto then
          raise exception using errcode = '22023', message = 'admin_validation:bonus_de_si_mesmo';
        end if;
        if (v_produto::text || '/' || v_incluso::text) = any(v_pares) then
          raise exception using errcode = '22023', message = 'admin_validation:bonus_repetido';
        end if;
        v_pares := v_pares || (v_produto::text || '/' || v_incluso::text);
        v_valor := coalesce(nullif(btrim(v_item->>'valor'), '')::numeric, 0);
        v_referencia := nullif(btrim(v_item->>'valorReferencia'), '')::numeric;
        if v_valor < 0 or v_referencia < 0 then
          raise exception using errcode = '22023', message = 'admin_validation:preco_negativo';
        end if;
        if v_valor <> round(v_valor, 2) or v_referencia <> round(v_referencia, 2) then
          raise exception using errcode = '22023', message = 'admin_validation:centavos';
        end if;
        v_ini := nullif(btrim(v_item->>'iniciaEm'), '')::timestamptz;
        v_fim := nullif(btrim(v_item->>'encerraEm'), '')::timestamptz;
        if v_ini >= v_fim then
          raise exception using errcode = '22023', message = 'admin_validation:janela_invertida';
        end if;

        insert into catalogo.oferta_inclui(oferta_id, produto_id, incluso_id, valor, ordem, nome, descricao, detalhe,
                                           nota, valor_referencia, inicia_em, encerra_em)
        values (v_id, v_produto, v_incluso, v_valor,
                coalesce(nullif(btrim(v_item->>'ordem'), '')::smallint, v_pos::smallint),
                nullif(btrim(v_item->>'nome'), ''), nullif(btrim(v_item->>'descricao'), ''),
                nullif(btrim(v_item->>'detalhe'), ''), nullif(btrim(v_item->>'nota'), ''),
                v_referencia, v_ini, v_fim)
        on conflict (oferta_id, produto_id, incluso_id) do update set
          valor = excluded.valor,
          ordem = excluded.ordem,
          nome = excluded.nome,
          descricao = excluded.descricao,
          detalhe = excluded.detalhe,
          nota = excluded.nota,
          valor_referencia = excluded.valor_referencia,
          inicia_em = excluded.inicia_em,
          encerra_em = excluded.encerra_em;
      end loop;
      if exists (select 1 from catalogo.oferta_inclui oi
                  where oi.oferta_id = v_id and (oi.produto_id::text || '/' || oi.incluso_id::text) <> all(v_pares)) then
        if v_ja_foi then
          raise exception using errcode = '22023', message = 'admin_validation:linha_nao_se_remove';
        end if;
        delete from catalogo.oferta_inclui oi
         where oi.oferta_id = v_id and (oi.produto_id::text || '/' || oi.incluso_id::text) <> all(v_pares);
      end if;
    end if;

    -- ---------- exigências: o que o order bump ou o upgrade pede ----------
    if p_payload ? 'requer' then
      if jsonb_typeof(p_payload->'requer') <> 'array' then
        raise exception using errcode = '22023', message = 'admin_validation:dados_invalidos';
      end if;
      v_pos := 0;
      for v_item in select e.value from jsonb_array_elements(p_payload->'requer') e loop
        v_pos := v_pos + 1;
        if jsonb_typeof(v_item) <> 'object' then
          raise exception using errcode = '22023', message = 'admin_validation:dados_invalidos';
        end if;
        select pr.id into v_produto from catalogo.produtos pr where pr.codigo = btrim(v_item->>'produtoCodigo');
        if v_produto is null then
          raise exception using errcode = '22023', message = 'admin_validation:produto_desconhecido';
        end if;
        if v_produto = any(v_exigidos) then
          raise exception using errcode = '22023', message = 'admin_validation:requer_repetido';
        end if;
        v_exigidos := v_exigidos || v_produto;
        v_modo := coalesce(nullif(btrim(v_item->>'modo'), ''), 'carrinho');
        if v_modo not in ('carrinho', 'posse') then
          raise exception using errcode = '22023', message = 'admin_validation:requer_modo';
        end if;
        v_ini := nullif(btrim(v_item->>'iniciaEm'), '')::timestamptz;
        v_fim := nullif(btrim(v_item->>'encerraEm'), '')::timestamptz;
        if v_ini >= v_fim then
          raise exception using errcode = '22023', message = 'admin_validation:janela_invertida';
        end if;

        insert into catalogo.oferta_requer(oferta_id, produto_id, modo, prioridade, grupo_exclusivo, ativo,
                                           inicia_em, encerra_em, observacao, ordem)
        values (v_id, v_produto, v_modo,
                coalesce(nullif(btrim(v_item->>'prioridade'), '')::smallint, 100::smallint),
                nullif(btrim(v_item->>'grupoExclusivo'), ''),
                coalesce((v_item->>'ativo')::boolean, true),
                v_ini, v_fim, nullif(btrim(v_item->>'observacao'), ''),
                coalesce(nullif(btrim(v_item->>'ordem'), '')::smallint, v_pos::smallint))
        on conflict (oferta_id, produto_id) do update set
          modo = excluded.modo,
          prioridade = excluded.prioridade,
          grupo_exclusivo = excluded.grupo_exclusivo,
          ativo = excluded.ativo,
          inicia_em = excluded.inicia_em,
          encerra_em = excluded.encerra_em,
          observacao = excluded.observacao,
          ordem = excluded.ordem;
      end loop;
      if exists (select 1 from catalogo.oferta_requer rq where rq.oferta_id = v_id and rq.produto_id <> all(v_exigidos)) then
        if v_ja_foi then
          raise exception using errcode = '22023', message = 'admin_validation:linha_nao_se_remove';
        end if;
        delete from catalogo.oferta_requer rq where rq.oferta_id = v_id and rq.produto_id <> all(v_exigidos);
      end if;
    end if;

    -- Exigência só faz sentido em oferta condicional (order bump ou upgrade).
    if v_novo.tipo <> 'condicional' and exists (select 1 from catalogo.oferta_requer rq where rq.oferta_id = v_id) then
      raise exception using errcode = '22023', message = 'admin_validation:requer_so_condicional';
    end if;

    -- Oferta no ar continua tendo de valer como oferta no ar.
    if v_novo.ativo then
      perform 1 from catalogo.produtos pr
       where pr.id in (select op.produto_id from catalogo.oferta_precos op where op.oferta_id = v_id)
       order by pr.id
         for update;
      v_motivo := catalogo.oferta_bloqueio(v_id, now(), false);
      if v_motivo is not null then
        raise exception using errcode = '22023', message = 'admin_validation:' || v_motivo;
      end if;
    end if;

    -- Qualquer mudança — na oferta, num preço, num bônus, numa exigência — é uma versão nova da oferta.
    update catalogo.ofertas set atualizado_em = clock_timestamp() where id = v_id;
  end if;

  v_after := (public.mind_admin_read_ofertas(v_id)->0) - 'alteracoes';

  -- A hora de cada alteração é a do relógio, não a do começo da transação: o histórico sai na ordem certa.
  insert into public.mind_admin_audit(
    actor_user_id, action, resource, record_id, record_label, before_data, after_data, request_id, occurred_at
  ) values (
    p_actor_id, p_action, 'offers', v_id::text, v_after->>'nome', v_before, v_after, p_request_id, clock_timestamp()
  );

  return public.mind_admin_read_ofertas(v_id)->0;
exception
  when unique_violation then
    raise exception using errcode = '22023', message = 'admin_validation:codigo_repetido';
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow
    or numeric_value_out_of_range or check_violation or not_null_violation or foreign_key_violation then
    raise exception using errcode = '22023', message = 'admin_validation:dados_invalidos';
end;
$fn$;

revoke all on function catalogo.produto_tem_leitor(uuid) from public, anon, authenticated, service_role;
revoke all on function catalogo.codigo_reservado(text, uuid) from public, anon, authenticated, service_role;
revoke all on function catalogo.oferta_ja_foi_ao_ar(uuid) from public, anon, authenticated, service_role;
revoke all on function catalogo.oferta_bloqueio(uuid, timestamptz, boolean) from public, anon, authenticated, service_role;
revoke all on function catalogo.oferta_sobrepostas(uuid) from public, anon, authenticated, service_role;
revoke all on function public.mind_admin_read_ofertas(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.mind_admin_mutate_ofertas(text, uuid, jsonb, text, uuid, uuid) from public, anon, authenticated;
grant execute on function public.mind_admin_read_ofertas(uuid, timestamptz) to service_role;
grant execute on function public.mind_admin_mutate_ofertas(text, uuid, jsonb, text, uuid, uuid) to service_role;
