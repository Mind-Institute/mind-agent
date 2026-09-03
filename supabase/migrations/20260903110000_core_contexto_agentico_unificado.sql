-- Core agêntico unificado: contexto compacto, lupa contextual, paridade B2B/B2C
-- e defesa em profundidade nas tabelas internas de identidade/eventos.
--
-- Fatos comerciais continuam em structured. A lupa só recupera long-tail e nunca
-- substitui preço, desconto, checkout, disponibilidade ou regra comercial.

begin;

-- ---------------------------------------------------------------------------
-- 1. Decisioning comercial compacto e comum às duas rotas de venda.

insert into agentes.prompts
  (chave, titulo, conteudo, ativo, versao, produto_codigo, atualizado_em)
values (
  'decisioning_vendas_universal',
  'Decisioning comercial universal e compacto',
  $prompt$
DECISIONING COMERCIAL UNIVERSAL

FUNÇÃO
Escolher o melhor movimento comercial deste turno. O playbook da rota define como vender aquela solução; o Kit informa os fatos atuais; este bloco organiza a decisão sem obrigar o comprador a percorrer um funil que ele já atravessou.

ORDEM DE PRIORIDADE
1. Preserve uma compra que já está acontecendo.
2. Resolva a barreira concreta que impede a compra.
3. Proteja o momentum: quanto maior a intenção, menor o atrito.
4. Ajude a decidir quando a escolha ainda estiver aberta.
5. Construa valor somente quando ele ainda não estiver claro.
6. Pergunte apenas o que puder mudar a próxima ação.

ANTES DE RESPONDER
Determine silenciosamente:
- estado: orientando, escolhendo, validando, decidido, transacional, bloqueado, aguardando terceiro, adiado ou encerrado
- intenção: baixa, média, alta ou muito alta
- barreira dominante: nenhuma, dúvida, valor, preço/orçamento, aprovação, agenda/logística, fit, disponibilidade, pagamento/técnica, procurement/legal ou incerta
- objetivo do turno: orientar, recomendar, confirmar escolha, remover incerteza, construir valor, resolver barreira, armar champion, enviar checkout, concluir, preservar compromisso ou preparar handoff

Não exponha essas classificações. Não invente objeção. Silêncio não é objeção.

CAMINHO CURTO
Responda primeiro ao que foi perguntado. Se a pessoa já escolheu, não reabra opções. Se quer pagar, pare de vender e facilite a transação. Se preço, parcelamento, argumento e checkout oficiais já resolvem o mesmo objetivo, entregue tudo no mesmo turno. Não serialize artificialmente.

CONTATO COMERCIAL NO INÍCIO
Nas rotas de venda B2B e B2C, use primeiro perfil, CRM, histórico e credenciamento. Complete no início da conversa apenas o que estiver ausente entre nome completo, e-mail, WhatsApp, empresa e cargo. Faça no máximo uma pergunta curta por turno, grave cada resposta imediatamente e nunca repita um dado conhecido.

Você pode responder uma pergunta objetiva enquanto coleta o contato, mas não entregue calculadora, proposta ou checkout antes de o cadastro mínimo estar completo. Handoff de segurança ou pedido explícito por humano nunca fica bloqueado por cadastro.

LUPA DE INTELLIGENCE
O contexto inicial é deliberadamente enxuto. Use buscar_intelligence quando uma explicação, evidência, pessoa, sessão, material, objeção long-tail ou relação com o problema da empresa exigir profundidade que não está no structured. Use ler_intelligence para abrir o candidato relevante.

Não use a lupa para preço, desconto, checkout, disponibilidade, categoria de ingresso ou regra comercial: esses fatos precisam vir do structured. Resultado vazio significa que não foi encontrado; não autoriza completar de memória.

OBJEÇÕES
Primeiro diferencie dúvida, fricção transacional, dependência externa, pausa, objeção e recusa real. Resolva a barreira real, não a frase aparente. Se a causa estiver ambígua e mudar a estratégia, faça uma pergunta curta.

Preço pode significar falta de valor percebido ou limite financeiro real. No primeiro caso, conecte a solução ao objetivo declarado. No segundo, use somente condição disponível no Kit. Nunca revele escada interna, nunca aumente concessão só porque houve hesitação e nunca use desconto para resolver agenda, logística, aprovação ou erro técnico.

Depois que a barreira desaparecer, avance. Depois que a pessoa recusar claramente, respeite e encerre sem insistência.

HUMANO
Handoff é capacidade, não fuga por falta de informação. Acione conforme o playbook quando houver pedido humano, exceção comercial, contrato/procurement, erro que o fluxo não resolve, risco sério ou negociação personalizada. Antes, responda o que puder e organize silenciosamente o contexto já disponível. Campo ausente nunca impede transferência.

REGRA FINAL
Uma resposta, um objetivo dominante, um próximo movimento claro. Use toda a inteligência necessária; diga apenas o que agrega valor agora.
$prompt$,
  true,
  1,
  null,
  now()
)
on conflict (chave) do update
set titulo = excluded.titulo,
    conteudo = excluded.conteudo,
    ativo = excluded.ativo,
    versao = greatest(agentes.prompts.versao, excluded.versao),
    produto_codigo = excluded.produto_codigo,
    atualizado_em = case
      when agentes.prompts.conteudo is distinct from excluded.conteudo then now()
      else agentes.prompts.atualizado_em
    end;

insert into agentes.kit_blocos
  (rota, bloco, provider, secao, obrigatorio, ativo)
values
  ('summit_b2c','decisioning_vendas_universal','agentes.prompts','decisioning',false,true),
  ('summit_b2b','decisioning_vendas_universal','agentes.prompts','decisioning',false,true),
  ('summit_b2c','buscar_intelligence','concierge.ferramentas','tools',false,true),
  ('summit_b2c','ler_intelligence','concierge.ferramentas','tools',false,true),
  ('summit_b2b','buscar_intelligence','concierge.ferramentas','tools',false,true),
  ('summit_b2b','ler_intelligence','concierge.ferramentas','tools',false,true)
on conflict (rota, bloco) do update
set provider = excluded.provider,
    secao = excluded.secao,
    obrigatorio = excluded.obrigatorio,
    ativo = excluded.ativo;

-- Uma rota de venda não carrega dois cérebros comerciais concorrentes. Os blocos
-- antigos permanecem versionados, mas saem da composição ativa dessas duas rotas.
update agentes.kit_blocos
set ativo=false
where rota in ('summit_b2c','summit_b2b')
  and secao='decisioning'
  and bloco<>'decisioning_vendas_universal'
  and ativo;

-- O B2C deixa de depender nominalmente dos módulos antigos. O conteúdo essencial
-- agora está no decisioning comum carregado pelo Kit.
update agentes.prompts
set conteudo = replace(
      replace(conteudo,
        'O Sales Decision Engine já determina:',
        'O Decisioning Comercial Universal já determina:'),
      'Quando o Sales Decision Engine identificar uma objeção ou barreira:',
      'Quando o Decisioning Comercial Universal identificar uma objeção ou barreira:'),
    versao = greatest(versao, 6),
    atualizado_em = now()
where chave = 'playbook_summit_b2c'
  and ativo
  and (
    conteudo like '%O Sales Decision Engine já determina:%'
    or conteudo like '%Quando o Sales Decision Engine identificar uma objeção ou barreira:%'
  );

-- Captura de contato é comum às rotas de venda. No B2B, substitui-se a regra
-- anterior que liberava a transação antes da identificação completa do lead.
update agentes.prompts
set conteudo = regexp_replace(
      conteudo,
      'CADASTRO B2B OBRIGATÓRIO E PROGRESSIVO.*?SINAIS DE ALTA INTENÇÃO',
      $novo$CADASTRO B2B OBRIGATÓRIO NO INÍCIO
O contato mínimo é: nome completo, e-mail, WhatsApp, empresa e cargo.

Antes de perguntar, verifique perfil, CRM, histórico e credenciamento. Um campo só está ausente quando não aparece em nenhuma dessas fontes. Dados do comprador nunca devem ser usados como se fossem da pessoa que conversa.

Comece pelos campos ausentes. Faça uma pergunta curta por mensagem e grave cada resposta imediatamente; nunca despeje uma ficha. Ordem preferencial: nome completo, empresa, cargo, e-mail e WhatsApp. Nunca repita um dado conhecido.

Antes de considerar e-mail ou WhatsApp completos, confira a validação recebida no contexto. Se o formato estiver inválido ou ambíguo, peça confirmação ou correção e não marque o campo como preenchido.

Enquanto coleta, responda perguntas objetivas que ajudem a pessoa a avançar. Não entregue calculadora, proposta ou checkout até completar o contato mínimo. Pedido explícito por humano, risco ou suporte urgente não fica bloqueado pelo cadastro.

SINAIS DE ALTA INTENÇÃO$novo$,
      'ns'),
    versao = greatest(versao, 9),
    atualizado_em = now()
where chave = 'playbook_summit_b2b'
  and ativo
  and conteudo like '%CADASTRO B2B OBRIGATÓRIO E PROGRESSIVO%';

do $b2b$
declare v_prompt text;
begin
  select conteudo into v_prompt
  from agentes.prompts
  where chave='playbook_summit_b2b' and ativo;

  if v_prompt is null
     or v_prompt not like '%CADASTRO B2B OBRIGATÓRIO NO INÍCIO%'
     or v_prompt not like '%Não entregue calculadora, proposta ou checkout até completar o contato mínimo%'
     or v_prompt like '%NÃO COLETE CADASTRO%' then
    raise exception 'playbook B2B não incorporou a decisão cadastral vigente';
  end if;
end
$b2b$;

-- Compatibilidade para consumidores antigos: a composição passa a obedecer ao mesmo
-- registry do Kit. tom_de_voz e os módulos genéricos enormes deixam de ser um caminho
-- paralelo exclusivo do Treble.
create or replace function public.treble_agent_prompt(
  p_audience text default 'desconhecido'::text,
  p_camada text default 'completo'::text
)
returns text
language sql
stable
security definer
set search_path to 'public', 'agentes'
as $function$
  with rota as (
    select case coalesce(nullif(btrim(p_audience),''),'desconhecido')
      when 'b2c' then 'summit_b2c'
      when 'b2b' then 'summit_b2b'
      else coalesce(nullif(btrim(p_audience),''),'desconhecido')
    end r
  ), partes as (
    select 1 ordem, p.chave, p.conteudo
    from agentes.prompts p
    where p.chave='base' and p.ativo
      and coalesce(p_camada,'completo') in ('completo','agent')
    union all
    select 2, p.chave, p.conteudo
    from rota r
    join agentes.prompts p on p.chave='playbook_' || r.r and p.ativo
    where coalesce(p_camada,'completo') in ('completo','agent')
    union all
    select 3, p.chave, p.conteudo
    from rota r
    join agentes.kit_blocos k
      on k.rota=r.r and k.ativo and k.secao='decisioning'
    join agentes.prompts p on p.chave=k.bloco and p.ativo
    where coalesce(p_camada,'completo') in ('completo','decisioning')
  )
  select string_agg(conteudo,E'\n\n' order by ordem,chave) from partes;
$function$;

revoke all on function public.treble_agent_prompt(text,text)
  from public, anon, authenticated;
grant execute on function public.treble_agent_prompt(text,text)
  to service_role;

-- ---------------------------------------------------------------------------
-- 2. Product Intelligence B2C escopada ao produto do playbook.

create or replace function public.mind_produto_da_rota_status(p_rota text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_strip_nulls(jsonb_build_object(
    'rota', p_rota,
    'playbook', pr.chave,
    'produto_codigo', pr.produto_codigo,
    'catalogado', p.codigo is not null,
    'ativo', coalesce(p.ativo,false),
    'vende', coalesce(p.vende,false),
    'vendavel_agora', coalesce(p.ativo and p.vende,false),
    'nome', p.nome,
    'tipo', p.tipo,
    'vertical', p.vertical
  ))
  from agentes.prompts pr
  left join catalogo.produtos p on p.codigo=pr.produto_codigo
  where pr.chave='playbook_' || p_rota and pr.ativo
  limit 1;
$function$;

revoke all on function public.mind_produto_da_rota_status(text)
  from public, anon, authenticated;
grant execute on function public.mind_produto_da_rota_status(text)
  to service_role;

create or replace function public.mind_kit_product_intelligence_b2c(
  p_conversa_id uuid default null::uuid,
  p_necessidade jsonb default null::jsonb
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  with status as (
    select public.mind_produto_da_rota_status('summit_b2c') j
  ), produto as (
    select p.*, d.metadata
    from status s
    join catalogo.produtos p on p.codigo=s.j->>'produto_codigo'
    left join summit_2026.knowledge_documents d
      on d.produto_codigo=p.codigo and d.ativo
     and (d.valido_de is null or d.valido_de<=now())
     and (d.valido_ate is null or d.valido_ate>now())
    where p.ativo
    order by d.atualizado_em desc nulls last
    limit 1
  )
  select jsonb_build_object(
    'bloco','product_intelligence',
    'produto_da_rota',coalesce((select j from status),'{}'::jsonb),
    'regra','O playbook define a solução; o catálogo confirma se ela está ativa e vendável.',
    'produtos',coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'codigo',p.codigo,'nome',p.nome,
        'natureza',p.metadata->>'natureza_solucao',
        'definicao',coalesce(p.descricao,p.descricao_curta),
        'resultado_principal',p.metadata->>'resultado_principal',
        'profundidade',p.metadata->>'profundidade',
        'formato',p.metadata->>'formato','escopo',p.metadata->>'escopo',
        'resolve',p.metadata->'resolve','capacidades',p.metadata->'capacidades',
        'adequado_quando',p.metadata->'adequado_quando','limites',p.metadata->'limites',
        'vendavel_agora',p.vende
      ))) from produto p where p.vende
    ),'[]'::jsonb),
    'nao_contem',jsonb_build_array(
      'preço','lote','parcelamento','checkout','desconto','disponibilidade por categoria')
  );
$function$;

revoke all on function public.mind_kit_product_intelligence_b2c(uuid,jsonb)
  from public, anon, authenticated;
grant execute on function public.mind_kit_product_intelligence_b2c(uuid,jsonb)
  to service_role;

create or replace function public.mind_kit_inclusoes_b2c(
  p_conversa_id uuid default null::uuid,
  p_necessidade jsonb default null::jsonb
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  with original as (
    select public.mind_kit_inclusoes(p_conversa_id,p_necessidade) j
  ), experiencias as (
    select coalesce(jsonb_agg(e.value-'ofertas_vigentes' order by e.ordinality),'[]'::jsonb) j
    from original o,
         lateral jsonb_array_elements(coalesce(o.j->'experiencias','[]'::jsonb))
           with ordinality e(value,ordinality)
  )
  select case when o.j is null then null::jsonb
    else jsonb_set(o.j,'{experiencias}',e.j,true) end
  from original o cross join experiencias e;
$function$;

revoke all on function public.mind_kit_inclusoes_b2c(uuid,jsonb)
  from public, anon, authenticated;
grant execute on function public.mind_kit_inclusoes_b2c(uuid,jsonb)
  to service_role;

update agentes.kit_blocos
set provider=case bloco
  when 'product_intelligence' then 'public.mind_kit_product_intelligence_b2c'
  when 'inclusoes' then 'public.mind_kit_inclusoes_b2c'
  else provider end,
    obrigatorio=case when bloco='product_intelligence' then true else obrigatorio end
where rota='summit_b2c'
  and secao='structured'
  and bloco in ('product_intelligence','inclusoes');

-- ---------------------------------------------------------------------------
-- 3. Índice recuperável: chunks lexicais imediatos, embeddings preenchíveis sem
-- alterar o contrato do Agent. O recorte de 4.000 com passo 3.500 preserva sobreposição.

create or replace function public.mind_knowledge_preparar_chunks(p_schema text)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count integer;
begin
  if p_schema not in ('summit_2026','institute','dash','eventos') then
    raise exception 'schema de knowledge não permitido';
  end if;

  execute format(
    'create unique index if not exists %I on %I.knowledge_chunks(doc_id,ordem,indice)',
    'knowledge_chunks_doc_ordem_indice_uidx', p_schema);
  execute format(
    'create index if not exists %I on %I.knowledge_chunks(stale desc,ordem,id) where embedding is null or stale or modelo_embedding is distinct from %L',
    'knowledge_chunks_embedding_pendente_idx',p_schema,'text-embedding-3-small');

  execute format($sql$
    insert into %I.knowledge_chunks
      (doc_id,ordem,texto,metadata,embedding,stale,embedado_em,modelo_embedding,indice)
    select d.id, g.ordem,
           substring(d.corpo from 1 + ((g.ordem-1)*3500) for 4000),
           jsonb_build_object('document_hash',d.hash,'titulo',d.titulo),
           null, true, null, null, 'principal'
    from %I.knowledge_documents d
    cross join lateral generate_series(
      1, greatest(1,ceil(length(coalesce(d.corpo,'')) / 3500.0)::int)
    ) g(ordem)
    where d.ativo and btrim(coalesce(d.corpo,''))<>''
    on conflict (doc_id,ordem,indice) do update
    set texto=excluded.texto,
        metadata=excluded.metadata,
        embedding=case
          when %I.knowledge_chunks.metadata->>'document_hash'
               is distinct from excluded.metadata->>'document_hash' then null
          else %I.knowledge_chunks.embedding end,
        stale=case
          when %I.knowledge_chunks.metadata->>'document_hash'
               is distinct from excluded.metadata->>'document_hash' then true
          else %I.knowledge_chunks.stale end,
        embedado_em=case
          when %I.knowledge_chunks.metadata->>'document_hash'
               is distinct from excluded.metadata->>'document_hash' then null
          else %I.knowledge_chunks.embedado_em end,
        modelo_embedding=case
          when %I.knowledge_chunks.metadata->>'document_hash'
               is distinct from excluded.metadata->>'document_hash' then null
          else %I.knowledge_chunks.modelo_embedding end
  $sql$,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema);

  get diagnostics v_count=row_count;
  return v_count;
end;
$function$;

revoke all on function public.mind_knowledge_preparar_chunks(text)
  from public, anon, authenticated;
grant execute on function public.mind_knowledge_preparar_chunks(text)
  to service_role;

select public.mind_knowledge_preparar_chunks('summit_2026');
select public.mind_knowledge_preparar_chunks('institute');
select public.mind_knowledge_preparar_chunks('dash');
select public.mind_knowledge_preparar_chunks('eventos');

-- Porta de indexação. A Edge interna lê somente chunks pendentes e grava somente o
-- embedding do chunk pedido; nome de schema nunca vira SQL sem allowlist.
create or replace function public.mind_intelligence_chunks_pendentes(
  p_schema text,
  p_limite integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_saida jsonb;
begin
  if p_schema not in ('summit_2026','institute','dash','eventos') then
    raise exception 'schema de knowledge não permitido';
  end if;

  execute format($sql$
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',id,'texto',texto,'metadata',metadata
    ) order by ordem,id),'[]'::jsonb)
    from (
      select id,texto,metadata,ordem
      from %I.knowledge_chunks
      where embedding is null or stale or modelo_embedding is distinct from 'text-embedding-3-small'
      order by stale desc,ordem,id
      limit $1
    ) pendentes
  $sql$,p_schema)
  into v_saida
  using least(100,greatest(1,coalesce(p_limite,50)));

  return v_saida;
end;
$function$;

create or replace function public.mind_intelligence_embedding_registrar(
  p_schema text,
  p_chunk_id uuid,
  p_embedding public.vector(1536),
  p_modelo text default 'text-embedding-3-small'
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count integer;
begin
  if p_schema not in ('summit_2026','institute','dash','eventos') then
    raise exception 'schema de knowledge não permitido';
  end if;
  if p_modelo<>'text-embedding-3-small' then
    raise exception 'modelo de embedding não permitido';
  end if;

  execute format(
    'update %I.knowledge_chunks set embedding=$1,stale=false,embedado_em=now(),modelo_embedding=$2 where id=$3',
    p_schema
  ) using p_embedding,p_modelo,p_chunk_id;
  get diagnostics v_count=row_count;
  return v_count=1;
end;
$function$;

revoke all on function public.mind_intelligence_chunks_pendentes(text,integer)
  from public, anon, authenticated;
revoke all on function public.mind_intelligence_embedding_registrar(text,uuid,public.vector,text)
  from public, anon, authenticated;
grant execute on function public.mind_intelligence_chunks_pendentes(text,integer)
  to service_role;
grant execute on function public.mind_intelligence_embedding_registrar(text,uuid,public.vector,text)
  to service_role;

create or replace function public.mind_intelligence_buscar_contextual(
  p_necessidade text,
  p_limite integer default 6,
  p_rota text default null,
  p_canal text default null,
  p_produto_codigo text default null,
  p_embedding public.vector(1536) default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  with cfg as (
    select least(10,greatest(1,coalesce(p_limite,6))) n,
           plainto_tsquery('portuguese',coalesce(btrim(p_necessidade),'')) q
  ), docs as (
    select 'summit_2026' origem,d.* from summit_2026.knowledge_documents d
    where coalesce(p_rota,'') in ('summit_b2c','summit_b2b','concierge_summit','cliente_suporte')
    union all
    select 'institute',d.* from institute.knowledge_documents d where p_rota='institute'
    union all
    select 'dash',d.* from dash.knowledge_documents d where p_rota='dash'
    union all
    select 'eventos',d.* from eventos.knowledge_documents d
    where p_rota not in ('summit_b2c','summit_b2b','concierge_summit','cliente_suporte','institute','dash')
  ), permitidos as (
    select d.* from docs d
    where d.ativo
      and (d.valido_de is null or d.valido_de<=now())
      and (d.valido_ate is null or d.valido_ate>now())
      and (d.produto_codigo is null or p_produto_codigo is null or d.produto_codigo=p_produto_codigo)
      and (coalesce(p_canal,'')<>'whatsapp' or d.aprovado_treble)
      and (coalesce(p_canal,'')='whatsapp' or cardinality(d.agents)=0 or 'concierge'=any(d.agents))
  ), chunks as (
    select 'summit_2026' origem,c.* from summit_2026.knowledge_chunks c
    union all select 'institute',c.* from institute.knowledge_chunks c
    union all select 'dash',c.* from dash.knowledge_chunks c
    union all select 'eventos',c.* from eventos.knowledge_chunks c
  ), texto as (
    select c.origem,c.id,c.doc_id,
           row_number() over(order by ts_rank_cd(c.tsv,cfg.q) desc) pos
    from chunks c join permitidos d on d.origem=c.origem and d.id=c.doc_id cross join cfg
    where c.tsv@@cfg.q
    order by pos limit (select n*4 from cfg)
  ), vetor as (
    select c.origem,c.id,c.doc_id,
           row_number() over(order by c.embedding OPERATOR(public.<=>) p_embedding) pos
    from chunks c join permitidos d on d.origem=c.origem and d.id=c.doc_id cross join cfg
    where p_embedding is not null and c.embedding is not null and not c.stale
      and c.modelo_embedding='text-embedding-3-small'
    order by pos limit (select n*4 from cfg)
  ), fundido as (
    select origem,id,doc_id,sum(score) score
    from (
      select origem,id,doc_id,1.0/(60+pos) score from texto
      union all
      select origem,id,doc_id,1.0/(60+pos) score from vetor
    ) x group by origem,id,doc_id
  ), conhecimento as (
    select distinct on (d.origem,d.id)
      jsonb_build_object(
        'tipo','conhecimento','id',d.origem || ':' || d.id::text,
        'titulo',d.titulo,
        'resumo',left(c.texto,220),
        'fonte',d.origem,
        'score',round(f.score::numeric,6)) candidato,
      f.score
    from fundido f
    join chunks c on c.origem=f.origem and c.id=f.id
    join permitidos d on d.origem=f.origem and d.id=f.doc_id
    order by d.origem,d.id,f.score desc
  ), busca_evento as (
    select case when coalesce(p_rota,'') in ('summit_b2c','summit_b2b','concierge_summit','cliente_suporte')
      then public.mindagent_chat_search('mind-summit-2026',p_necessidade,(select n from cfg))
      else '{}'::jsonb end j
  ), outros as (
    select jsonb_build_object('tipo','palestrante','id',e->>'id','titulo',e->>'name',
      'resumo',nullif(concat_ws(' · ',nullif(e->>'role',''),nullif(e->>'organization','')),'')) candidato,
      0.01::double precision score
    from busca_evento,lateral jsonb_array_elements(coalesce(j->'speakers','[]'::jsonb)) e
    union all
    select jsonb_build_object('tipo','sessao','id',e->>'id','titulo',e->>'title',
      'resumo',nullif(concat_ws(' · ',nullif(e->>'type',''),nullif(e->>'starts_at_local',''),nullif(e->>'location','')),'')),
      0.01::double precision
    from busca_evento,lateral jsonb_array_elements(coalesce(j->'sessions','[]'::jsonb)) e
  ), todos as (
    select candidato,score from conhecimento
    union all select candidato,score from outros
  )
  select jsonb_build_object(
    'necessidade',p_necessidade,
    'escopo',jsonb_build_object('rota',p_rota,'canal',p_canal,'produto_codigo',p_produto_codigo),
    'motor',case when p_embedding is null then 'lexical' else 'hibrido' end,
    'candidatos',coalesce((select jsonb_agg(candidato order by score desc,candidato->>'titulo')
      from (select * from todos order by score desc limit (select n from cfg)) z),'[]'::jsonb),
    'total',coalesce((select count(*) from (select * from todos limit (select n from cfg)) z),0),
    'como_usar','Leia o candidato relevante com ler_intelligence. Resultado vazio não autoriza completar de memória.'
  );
$function$;

create or replace function public.mind_intelligence_ler_contextual(
  p_tipo text,
  p_id text,
  p_rota text default null,
  p_canal text default null,
  p_produto_codigo text default null,
  p_corte integer default 1200
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select case lower(coalesce(p_tipo,''))
    when 'palestrante' then public.mind_intelligence_ler('palestrante',p_id,p_corte)
    when 'sessao' then public.mind_intelligence_ler('sessao',p_id,p_corte)
    when 'conhecimento' then (
      with alvo as (
        select case when p_id like '%:%' then split_part(p_id,':',1) else 'summit_2026' end origem,
               case when p_id like '%:%' then split_part(p_id,':',2) else p_id end id
      ), docs as (
        select 'summit_2026' origem,d.* from summit_2026.knowledge_documents d
        union all select 'institute',d.* from institute.knowledge_documents d
        union all select 'dash',d.* from dash.knowledge_documents d
        union all select 'eventos',d.* from eventos.knowledge_documents d
      )
      select jsonb_strip_nulls(jsonb_build_object(
        'tipo','conhecimento','id',d.origem || ':' || d.id::text,
        'titulo',d.titulo,'categoria',d.tipo_conteudo,'problema',d.problema,
        'resultado_desejado',d.resultado_desejado,'audiencia',d.audiencia,
        'cluster',d.cluster,'corpo',public.mind_txt_corta(d.corpo,greatest(200,least(4000,coalesce(p_corte,1200)))*3),
        'autor',d.autor,'url',d.url,'produto_codigo',d.produto_codigo))
      from docs d join alvo a on a.origem=d.origem and d.id::text=a.id
      where d.ativo
        and (d.valido_de is null or d.valido_de<=now())
        and (d.valido_ate is null or d.valido_ate>now())
        and (d.produto_codigo is null or p_produto_codigo is null or d.produto_codigo=p_produto_codigo)
        and (coalesce(p_canal,'')<>'whatsapp' or d.aprovado_treble)
        and (coalesce(p_canal,'')='whatsapp' or cardinality(d.agents)=0 or 'concierge'=any(d.agents))
        and (
          (p_rota in ('summit_b2c','summit_b2b','concierge_summit','cliente_suporte') and d.origem='summit_2026')
          or (p_rota='institute' and d.origem='institute')
          or (p_rota='dash' and d.origem='dash')
          or (p_rota not in ('summit_b2c','summit_b2b','concierge_summit','cliente_suporte','institute','dash') and d.origem='eventos')
        )
      limit 1
    )
    else null end;
$function$;

revoke all on function public.mind_intelligence_buscar_contextual(text,integer,text,text,text,public.vector)
  from public, anon, authenticated;
revoke all on function public.mind_intelligence_ler_contextual(text,text,text,text,text,integer)
  from public, anon, authenticated;
grant execute on function public.mind_intelligence_buscar_contextual(text,integer,text,text,text,public.vector)
  to service_role;
grant execute on function public.mind_intelligence_ler_contextual(text,text,text,text,text,integer)
  to service_role;

-- ---------------------------------------------------------------------------
-- 4. Casos de avaliação que transformam "agente surpreendente" em contrato
-- verificável no E2E, sem PII e sem duplicar uma nova casa de eval.

insert into engagement.avaliacoes(caso,categoria,pergunta,contexto,espera,ativo)
select v.caso,v.categoria,v.pergunta,v.contexto,v.espera,true
from (values
  (
    'core_v9_b2c_compra_direta',
    'conversao',
    'Já decidi. Quero comprar o Mind agora; me manda somente o link.',
    '{"rota":"summit_b2c","canal":"whatsapp"}'::jsonb,
    '{"checkout_sent":false,"coletar_contato_primeiro":true,"uma_pergunta":true}'::jsonb
  ),
  (
    'core_v9_b2b_cinco_ingressos_cadastro_progressivo',
    'conversao_b2b',
    'Quero 5 ingressos Mind para meu time. Quanto fica e como compro?',
    '{"rota":"summit_b2b","canal":"whatsapp"}'::jsonb,
    '{"needs_human":false,"faixa":"5+","checkout_sent":false,"coletar_contato_primeiro":true}'::jsonb
  ),
  (
    'core_v9_b2b_aprovacao_com_lupa',
    'rag_comercial',
    'Preciso justificar para a diretoria como o Summit ajuda líderes com segurança psicológica.',
    '{"rota":"summit_b2b","canal":"whatsapp"}'::jsonb,
    '{"usar_intelligence_quando_necessario":true,"nao_inventar_evidencia":true}'::jsonb
  ),
  (
    'core_v9_app_concierge_durante_summit',
    'roteamento_app',
    'Já estou no Summit. O que faz mais sentido para mim agora?',
    '{"rota":"concierge_summit","canal":"mindagent-web","origem":"mind_summit_app"}'::jsonb,
    '{"priorizar_concierge":true,"nao_vender_ingresso_sem_sinal":true}'::jsonb
  ),
  (
    'core_v9_oferta_futura_sem_fonte',
    'anti_alucinacao',
    'Qual o preço do Instituto e da pré-venda do Summit do ano que vem?',
    '{"canal":"mindagent-web"}'::jsonb,
    '{"nao_inventar_preco":true,"usar_apenas_oferta_oficial":true}'::jsonb
  )
) v(caso,categoria,pergunta,contexto,espera)
where not exists (
  select 1 from engagement.avaliacoes a where a.caso=v.caso
);

-- ---------------------------------------------------------------------------
-- 5. RLS defensivo. Essas tabelas são internas. service_role/postgres continuam
-- funcionando por BYPASSRLS; mind_agent só enxerga a pessoa declarada na
-- transação por SET LOCAL mind.person_id. Sem esse vínculo, a leitura é vazia.

alter table engagement.identidades enable row level security;
alter table engagement.pessoa_perfil enable row level security;
alter table engagement.treble_eventos enable row level security;

revoke all on table engagement.identidades from public, anon, authenticated;
revoke all on table engagement.pessoa_perfil from public, anon, authenticated;
revoke all on table engagement.treble_eventos from public, anon, authenticated;

do $policies$
begin
  if not exists (
    select 1 from pg_policies where schemaname='engagement'
      and tablename='identidades' and policyname='mind_agent_le_identidades'
  ) then
    create policy mind_agent_le_identidades on engagement.identidades
      for select to mind_agent using (pessoa_id = mind.pessoa_atual());
  end if;

  if not exists (
    select 1 from pg_policies where schemaname='engagement'
      and tablename='pessoa_perfil' and policyname='mind_agent_le_pessoa_perfil'
  ) then
    create policy mind_agent_le_pessoa_perfil on engagement.pessoa_perfil
      for select to mind_agent using (pessoa_id = mind.pessoa_atual());
  end if;
end
$policies$;

-- Guardas transacionais.
do $guard$
declare
  v_prompt_b2b text;
  v_prompt_b2c text;
begin
  select public.treble_agent_prompt('summit_b2b','completo') into v_prompt_b2b;
  select public.treble_agent_prompt('summit_b2c','completo') into v_prompt_b2c;

  if length(v_prompt_b2b)>=25000 or length(v_prompt_b2c)>=28000 then
    raise exception 'contexto de instruções ainda excessivo: b2b %, b2c %',
      length(v_prompt_b2b),length(v_prompt_b2c);
  end if;

  if position('decisioning comercial universal' in lower(v_prompt_b2b))=0
     or position('decisioning comercial universal' in lower(v_prompt_b2c))=0 then
    raise exception 'decisioning comum ausente';
  end if;

  if (select count(*) from agentes.kit_blocos
      where rota in ('summit_b2b','summit_b2c') and secao='tools' and ativo)<>4 then
    raise exception 'B2B e B2C não receberam as duas ferramentas';
  end if;

  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='engagement'
      and c.relname in ('identidades','pessoa_perfil','treble_eventos')
      and not c.relrowsecurity
  ) then
    raise exception 'RLS interno não foi habilitado';
  end if;

  if exists (
    select 1
    from pg_policies p
    where p.schemaname='engagement'
      and p.policyname in ('mind_agent_le_identidades','mind_agent_le_pessoa_perfil')
      and p.qual not like '%pessoa_atual()%'
  ) or (select count(*) from pg_policies p
        where p.schemaname='engagement'
          and p.policyname in ('mind_agent_le_identidades','mind_agent_le_pessoa_perfil'))<>2 then
    raise exception 'RLS de identidade/perfil não está restrito à pessoa da transação';
  end if;

  if (select count(*) from engagement.avaliacoes where caso like 'core_v9_%')<>5 then
    raise exception 'suíte mínima de avaliação não foi registrada';
  end if;
end
$guard$;

commit;
