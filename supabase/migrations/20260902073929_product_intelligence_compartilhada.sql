-- Reconstructed from production migration ledger 20260902073929.
-- PRODUCT INTELLIGENCE compartilhada do Mind.
-- Fontes aprovadas em 2026-09-02: joinmind.com.br e mindinstitute.com.br.
-- Somente posicionamento/capacidades estáveis. Comercial mutável permanece fora.
-- Sem tabela, schema, Router, Edge ou pipeline novo.

update catalogo.produtos
set descricao_curta = 'Ecossistema que traduz ciência sobre bem-estar no trabalho, liderança e cultura em experiências, formação profissional e transformação organizacional.',
    descricao = 'O Mind conecta ciência e prática para profissionais, líderes e organizações. Summit amplia repertório e conexões; Institute desenvolve competências; Dash apoia diagnóstico, desenho, implementação e acompanhamento de transformações organizacionais.',
    ativo = true,
    vende = false,
    atualizado_em = now()
where codigo = 'mind';

update catalogo.produtos
set descricao_curta = 'Frente de educação executiva do Mind para desenvolver competências e transformar ciência em decisões, práticas e projetos aplicáveis ao trabalho.',
    descricao = 'Formações executivas modulares, certificação integrada, cohorts e metodologia Learn–Apply–Reflect nos eixos Gestão Estratégica de Bem-Estar no Trabalho, Segurança Psicológica e Voz Ativa, Engajamento e Significado no Trabalho e integração sistêmica dos três.',
    ativo = true,
    vende = false,
    atualizado_em = now()
where codigo = 'mind-institute';

update catalogo.produtos
set descricao_curta = 'Frente de consultoria e assessoria estratégica do Mind para organizações que precisam diagnosticar, desenhar, implementar e acompanhar transformações.',
    descricao = 'Atua em bem-estar no trabalho, riscos psicossociais, cultura e liderança por meio de diagnóstico, definição de prioridades, plano de ação, implementação ou apoio, indicadores e acompanhamento.',
    ativo = true,
    vende = false,
    atualizado_em = now()
where codigo = 'mind-dash';

update catalogo.produtos
set descricao_curta = 'Encontro do ecossistema Mind dedicado à ciência e à prática do bem-estar no trabalho, liderança e performance sustentável.',
    descricao = 'Amplia repertório, conecta participantes a referências e pares e permite descobrir temas, especialistas e caminhos possíveis. Não substitui formação executiva, diagnóstico ou implementação organizacional.',
    atualizado_em = now()
where codigo = 'mind-summit-2026';

with v as (
  select
    md5('mind-product-intelligence:mind-institute')::uuid as id,
    md5('https://mindinstitute.com.br/')::uuid as fonte_id,
    'Mind Institute — Product Intelligence'::text as titulo,
    $doc$Definição: o Mind Institute é a frente de educação executiva do Mind. Desenvolve competências para que líderes, profissionais de RH, consultores e especialistas transformem ciência em decisões, práticas e projetos aplicáveis ao trabalho.

Natureza da solução: desenvolvimento de competência.

Eixos: Gestão Estratégica de Bem-Estar no Trabalho; Segurança Psicológica e Voz Ativa; Engajamento e Significado no Trabalho; integração sistêmica dos três.

Modelo educacional: formações executivas modulares, certificação integrada, cohorts abertos ou corporativos, aprendizagem síncrona e assíncrona e metodologia Learn–Apply–Reflect.

Limites: não executa pela organização uma transformação completa, não é diagnóstico organizacional completo, intervenção clínica, pós-graduação regulamentada ou garantia de resultado independente da aplicação.$doc$::text as corpo,
    jsonb_build_object(
      'natureza_solucao','desenvolvimento_de_competencia',
      'resolve',jsonb_build_array(
        'falta de repertório estruturado',
        'dificuldade de traduzir ciência em prática',
        'necessidade de desenvolver líderes e profissionais',
        'necessidade de diagnosticar e intervir com método',
        'necessidade de construir credibilidade e especialização'
      ),
      'capacidades',jsonb_build_array(
        'compreender bem-estar como sistema de gestão',
        'identificar riscos e ativos psicossociais',
        'transformar diagnóstico em plano de ação',
        'construir business case e indicadores',
        'desenvolver segurança psicológica, voz ativa e conversas difíceis',
        'fortalecer pertencimento, contribuição, autonomia e significado',
        'aplicar aprendizagem a problemas reais do trabalho'
      ),
      'eixos',jsonb_build_array(
        'Gestão Estratégica de Bem-Estar no Trabalho',
        'Segurança Psicológica e Voz Ativa',
        'Engajamento e Significado no Trabalho',
        'Integração sistêmica dos três'
      ),
      'adequado_quando',jsonb_build_array(
        'a pessoa ou a organização precisa desenvolver competência',
        'é necessário aprender a medir, decidir ou agir com método',
        'o objetivo é formar líderes, RH, consultores ou especialistas'
      ),
      'limites',jsonb_build_array(
        'não executa pela organização uma transformação completa',
        'não é diagnóstico organizacional completo',
        'não é intervenção clínica',
        'não é pós-graduação regulamentada',
        'não garante resultado independente da aplicação'
      ),
      'fontes',jsonb_build_array(
        'https://mindinstitute.com.br/',
        'https://mindinstitute.com.br/formacoes/',
        'https://mindinstitute.com.br/para-empresas/'
      ),
      'canon_date','2026-09-02'
    ) as metadata
)
insert into institute.knowledge_documents
  (id,fonte_id,titulo,corpo,metadata,hash,atualizado_em,tipo_conteudo,
   problema,resultado_desejado,autor,url,ativo,agents,atualizado_em_fonte,
   aprovado_treble,produto_codigo,event_id,valido_de,valido_ate,cluster,audiencia)
select
  id,fonte_id,titulo,corpo,metadata,md5(corpo || metadata::text),now(),
  'product_intelligence',
  'A pessoa ou organização precisa desenvolver competência para transformar ciência em prática.',
  'Capacidade aplicada para decidir e agir com método no trabalho.',
  'Mind','https://mindinstitute.com.br/',true,'{}'::text[],
  '2026-09-02 00:00:00+00'::timestamptz,true,'mind-institute',
  null,null,null,'empresa','publico'
from v
on conflict (id) do update set
  fonte_id=excluded.fonte_id,
  titulo=excluded.titulo,
  corpo=excluded.corpo,
  metadata=excluded.metadata,
  hash=excluded.hash,
  atualizado_em=now(),
  tipo_conteudo=excluded.tipo_conteudo,
  problema=excluded.problema,
  resultado_desejado=excluded.resultado_desejado,
  autor=excluded.autor,
  url=excluded.url,
  ativo=true,
  agents=excluded.agents,
  atualizado_em_fonte=excluded.atualizado_em_fonte,
  aprovado_treble=true,
  produto_codigo=excluded.produto_codigo,
  event_id=null,
  valido_de=null,
  valido_ate=null,
  cluster=excluded.cluster,
  audiencia=excluded.audiencia;

with v as (
  select
    md5('mind-product-intelligence:mind-dash')::uuid as id,
    md5('https://mindinstitute.com.br/para-empresas/#dash')::uuid as fonte_id,
    'Mind Dash — Product Intelligence'::text as titulo,
    $doc$Definição: o Mind Dash é a frente de consultoria e assessoria estratégica do Mind para organizações que precisam transformar bem-estar no trabalho, riscos psicossociais, cultura e liderança em um sistema de gestão.

Natureza da solução: intervenção organizacional.

Cadeia de entrega: diagnóstico de riscos e ativos; interpretação e definição de prioridades; plano de ação; implementação ou apoio à implementação; indicadores; acompanhamento e ajustes.

Sinal de fit: o problema deixou de ser apenas aprender e passou a exigir que a organização diagnostique, desenhe, implemente ou acompanhe uma transformação.

Limites: não é curso individual, benefício isolado, avaliação clínica de funcionários, pacote idêntico para qualquer empresa ou promessa de eliminar burnout.$doc$::text as corpo,
    jsonb_build_object(
      'natureza_solucao','intervencao_organizacional',
      'resolve',jsonb_build_array(
        'ausência de diagnóstico confiável',
        'ações fragmentadas de bem-estar',
        'riscos psicossociais tratados apenas como compliance',
        'dificuldade de priorizar intervenções',
        'falta de conexão entre dados e decisões',
        'dificuldade de envolver a liderança',
        'ausência de acompanhamento e aprendizagem contínua'
      ),
      'capacidades',jsonb_build_array(
        'diagnosticar riscos psicossociais e ativos de bem-estar',
        'interpretar dados no contexto organizacional',
        'definir prioridades',
        'desenhar plano de ação',
        'implementar ou apoiar a implementação',
        'construir indicadores',
        'acompanhar resultados e ajustar intervenções'
      ),
      'adequado_quando',jsonb_build_array(
        'a organização precisa diagnosticar um problema',
        'a organização precisa desenhar ou implementar uma transformação',
        'é necessário acompanhar indicadores e ajustar a estratégia'
      ),
      'limites',jsonb_build_array(
        'não é curso individual',
        'não é benefício isolado',
        'não é avaliação clínica de funcionários',
        'não é pacote padronizado para qualquer organização',
        'não promete eliminar burnout',
        'não é simples adequação documental à NR-1'
      ),
      'fontes',jsonb_build_array(
        'https://joinmind.com.br/',
        'https://mindinstitute.com.br/para-empresas/'
      ),
      'canon_date','2026-09-02'
    ) as metadata
)
insert into dash.knowledge_documents
  (id,fonte_id,titulo,corpo,metadata,hash,atualizado_em,tipo_conteudo,
   problema,resultado_desejado,autor,url,ativo,agents,atualizado_em_fonte,
   aprovado_treble,produto_codigo,event_id,valido_de,valido_ate,cluster,audiencia)
select
  id,fonte_id,titulo,corpo,metadata,md5(corpo || metadata::text),now(),
  'product_intelligence',
  'A organização precisa diagnosticar, desenhar, implementar ou acompanhar uma transformação.',
  'Sistema de gestão com prioridades, plano, implementação, indicadores e aprendizagem.',
  'Mind','https://mindinstitute.com.br/para-empresas/',true,'{}'::text[],
  '2026-09-02 00:00:00+00'::timestamptz,true,'mind-dash',
  null,null,null,'empresa','publico'
from v
on conflict (id) do update set
  fonte_id=excluded.fonte_id,
  titulo=excluded.titulo,
  corpo=excluded.corpo,
  metadata=excluded.metadata,
  hash=excluded.hash,
  atualizado_em=now(),
  tipo_conteudo=excluded.tipo_conteudo,
  problema=excluded.problema,
  resultado_desejado=excluded.resultado_desejado,
  autor=excluded.autor,
  url=excluded.url,
  ativo=true,
  agents=excluded.agents,
  atualizado_em_fonte=excluded.atualizado_em_fonte,
  aprovado_treble=true,
  produto_codigo=excluded.produto_codigo,
  event_id=null,
  valido_de=null,
  valido_ate=null,
  cluster=excluded.cluster,
  audiencia=excluded.audiencia;

with v as (
  select
    md5('mind-product-intelligence:mind-summit-2026')::uuid as id,
    md5('https://joinmind.com.br/#summit')::uuid as fonte_id,
    'Mind Summit — Product Intelligence'::text as titulo,
    $doc$Definição: o Mind Summit é o encontro do ecossistema Mind dedicado à ciência e à prática do bem-estar no trabalho, liderança e performance sustentável.

Natureza da solução: descoberta, ampliação de repertório e conexão.

Entregas: acesso a pesquisadores e profissionais de referência; conteúdos científicos e aplicações práticas; palestras, painéis, workshops e Masterclasses; comparação de perspectivas; networking e contato com pares.

Limites: não diagnostica a organização, não implementa uma transformação, não substitui formação executiva ou consultoria e não garante que assistir a conteúdos resolva o problema.$doc$::text as corpo,
    jsonb_build_object(
      'natureza_solucao','descoberta_repertorio_conexao',
      'resolve',jsonb_build_array(
        'repertório desatualizado ou fragmentado',
        'dificuldade de compreender novas agendas de pessoas e trabalho',
        'isolamento decisório',
        'necessidade de referências confiáveis',
        'busca por pares e perspectivas'
      ),
      'capacidades',jsonb_build_array(
        'ampliar repertório',
        'acessar referências',
        'comparar perspectivas',
        'descobrir temas, especialistas e caminhos possíveis',
        'conectar-se a pares'
      ),
      'adequado_quando',jsonb_build_array(
        'a pessoa busca repertório, referências ou pares',
        'é necessário mobilizar lideranças em torno de uma agenda',
        'o objetivo é descobrir possibilidades antes de escolher uma intervenção'
      ),
      'limites',jsonb_build_array(
        'não diagnostica a organização',
        'não implementa uma transformação',
        'não substitui formação executiva',
        'não substitui consultoria',
        'não garante resolução apenas pela participação'
      ),
      'fontes',jsonb_build_array('https://joinmind.com.br/'),
      'canon_date','2026-09-02'
    ) as metadata
)
insert into summit_2026.knowledge_documents
  (id,fonte_id,titulo,corpo,metadata,hash,atualizado_em,tipo_conteudo,
   problema,resultado_desejado,autor,url,ativo,agents,atualizado_em_fonte,
   aprovado_treble,produto_codigo,event_id,valido_de,valido_ate,cluster,audiencia)
select
  id,fonte_id,titulo,corpo,metadata,md5(corpo || metadata::text),now(),
  'product_intelligence',
  'A pessoa busca repertório, referências, perspectivas ou pares.',
  'Ampliação de repertório e descoberta de caminhos possíveis.',
  'Mind','https://joinmind.com.br/',true,'{}'::text[],
  '2026-09-02 00:00:00+00'::timestamptz,true,'mind-summit-2026',
  null,null,null,'empresa','publico'
from v
on conflict (id) do update set
  fonte_id=excluded.fonte_id,
  titulo=excluded.titulo,
  corpo=excluded.corpo,
  metadata=excluded.metadata,
  hash=excluded.hash,
  atualizado_em=now(),
  tipo_conteudo=excluded.tipo_conteudo,
  problema=excluded.problema,
  resultado_desejado=excluded.resultado_desejado,
  autor=excluded.autor,
  url=excluded.url,
  ativo=true,
  agents=excluded.agents,
  atualizado_em_fonte=excluded.atualizado_em_fonte,
  aprovado_treble=true,
  produto_codigo=excluded.produto_codigo,
  event_id=null,
  valido_de=null,
  valido_ate=null,
  cluster=excluded.cluster,
  audiencia=excluded.audiencia;

create or replace function public.mind_kit_product_intelligence(
  p_conversa_id uuid default null,
  p_necessidade jsonb default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  with produtos as (
    select p.codigo,p.nome,p.tipo,p.vertical,p.descricao_curta,p.descricao
    from catalogo.produtos p
    where p.codigo in ('mind','mind-summit-2026','mind-institute','mind-dash')
      and p.ativo
  ),
  documentos as (
    select d.produto_codigo,d.metadata
    from summit_2026.knowledge_documents d
    where d.id = md5('mind-product-intelligence:mind-summit-2026')::uuid
      and d.ativo
    union all
    select d.produto_codigo,d.metadata
    from institute.knowledge_documents d
    where d.id = md5('mind-product-intelligence:mind-institute')::uuid
      and d.ativo
    union all
    select d.produto_codigo,d.metadata
    from dash.knowledge_documents d
    where d.id = md5('mind-product-intelligence:mind-dash')::uuid
      and d.ativo
  )
  select jsonb_build_object(
    'bloco','product_intelligence',
    'regra_decisioning',jsonb_build_object(
      'principio','Product Intelligence informa capacidades; Decisioning escolhe a estratégia.',
      'regras',jsonb_build_array(
        'ICP não determina produto',
        'JTBD não determina sozinho o produto',
        'interesse em um tema não prova intenção de compra',
        'escolher pela transformação buscada, profundidade, escopo e urgência',
        'não apresentar uma solução como versão superior da outra'
      )
    ),
    'produtos',coalesce(jsonb_agg(
      jsonb_strip_nulls(jsonb_build_object(
        'codigo',p.codigo,
        'nome',p.nome,
        'natureza',case when p.codigo='mind' then 'ecossistema' else d.metadata->>'natureza_solucao' end,
        'definicao',coalesce(p.descricao,p.descricao_curta),
        'resolve',d.metadata->'resolve',
        'capacidades',d.metadata->'capacidades',
        'eixos',d.metadata->'eixos',
        'adequado_quando',d.metadata->'adequado_quando',
        'limites',d.metadata->'limites'
      ))
      order by case p.codigo
        when 'mind' then 0
        when 'mind-summit-2026' then 1
        when 'mind-institute' then 2
        when 'mind-dash' then 3
        else 9 end
    ),'[]'::jsonb),
    'nao_contem',jsonb_build_array(
      'preço','lote','parcelamento','checkout','turma','disponibilidade'
    )
  )
  from produtos p
  left join documentos d on d.produto_codigo=p.codigo;
$function$;

revoke execute on function public.mind_kit_product_intelligence(uuid,jsonb)
  from public, anon, authenticated;
grant execute on function public.mind_kit_product_intelligence(uuid,jsonb)
  to service_role;

insert into agentes.kit_blocos
  (rota,bloco,provider,secao,obrigatorio,ativo)
values
  ('concierge_summit','product_intelligence','public.mind_kit_product_intelligence','structured',false,true),
  ('cliente_suporte','product_intelligence','public.mind_kit_product_intelligence','structured',false,true),
  ('summit_b2c','product_intelligence','public.mind_kit_product_intelligence','structured',false,true),
  ('summit_b2b','product_intelligence','public.mind_kit_product_intelligence','structured',false,true)
on conflict (rota,bloco) do update set
  provider=excluded.provider,
  secao=excluded.secao,
  obrigatorio=excluded.obrigatorio,
  ativo=excluded.ativo;

do $verify$
declare
  v_payload jsonb;
begin
  if (select count(*) from catalogo.produtos
      where codigo in ('mind','mind-summit-2026','mind-institute','mind-dash')
        and ativo) <> 4 then
    raise exception 'product_intelligence: catálogo incompleto';
  end if;

  if not exists (
    select 1 from institute.knowledge_documents
    where id=md5('mind-product-intelligence:mind-institute')::uuid and ativo
  ) or not exists (
    select 1 from dash.knowledge_documents
    where id=md5('mind-product-intelligence:mind-dash')::uuid and ativo
  ) or not exists (
    select 1 from summit_2026.knowledge_documents
    where id=md5('mind-product-intelligence:mind-summit-2026')::uuid and ativo
  ) then
    raise exception 'product_intelligence: documentos canônicos ausentes';
  end if;

  v_payload := public.mind_kit_product_intelligence(null,null);
  if jsonb_array_length(coalesce(v_payload->'produtos','[]'::jsonb)) <> 4 then
    raise exception 'product_intelligence: provider não devolveu quatro produtos';
  end if;

  if (select count(*) from agentes.kit_blocos
      where bloco='product_intelligence' and ativo
        and rota in ('concierge_summit','cliente_suporte','summit_b2c','summit_b2b')) <> 4 then
    raise exception 'product_intelligence: registro de Kits incompleto';
  end if;
end;
$verify$;
