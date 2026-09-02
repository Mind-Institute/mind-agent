-- Product Intelligence / Decisioning v2.
-- Fecha o contrato estável de Summit × Institute × Dash sem misturar sellability.

update institute.knowledge_documents
set metadata = metadata || jsonb_build_object(
  'resultado_principal','desenvolver capacidade aplicada para decidir e agir com método no trabalho',
  'profundidade','aprendizagem estruturada, aplicação e reflexão',
  'formato','formações executivas online com conteúdo assíncrono e encontros ao vivo; cohorts abertos ou corporativos',
  'escopo','profissional, liderança, RH, consultoria ou cohort em desenvolvimento',
  'programas', jsonb_build_array(
    jsonb_build_object('codigo','gestao_estrategica_bem_estar','nome_oficial','Formação em Gestão Estratégica de Saúde Mental e Bem-Estar no Trabalho','eixo_canonico','Gestão Estratégica de Bem-Estar no Trabalho','tipo','formacao_executiva','adequado_quando',jsonb_build_array('é preciso estruturar bem-estar como agenda de gestão','é preciso identificar riscos e ativos psicossociais','é preciso conectar diagnóstico a intervenção, plano, business case ou indicadores'),'capacidades',jsonb_build_array('mapear riscos e ativos psicossociais','diferenciar sintomas de causas do trabalho','interpretar diagnósticos','selecionar intervenções coerentes','estruturar plano de ação','construir business case e indicadores')),
    jsonb_build_object('codigo','seguranca_psicologica','nome_oficial','Formação em Segurança Psicológica Aplicada à Inovação','eixo_canonico','Segurança Psicológica e Voz Ativa','tipo','formacao_executiva','adequado_quando',jsonb_build_array('pessoas evitam perguntar, discordar ou comunicar problemas','é preciso fortalecer confiança, aprendizagem e voz ativa','é preciso combinar segurança psicológica com accountability e conversas difíceis'),'capacidades',jsonb_build_array('diagnosticar barreiras à voz ativa','fortalecer confiança e aprendizagem','conduzir conversas difíceis','equilibrar segurança psicológica e responsabilização','transformar diagnóstico em plano de ação')),
    jsonb_build_object('codigo','engajamento_significado','nome_oficial','Formação em Engajamento e Significado no Trabalho','eixo_canonico','Engajamento e Significado no Trabalho','tipo','formacao_executiva','adequado_quando',jsonb_build_array('propósito existe no discurso mas não aparece na rotina','é preciso fortalecer pertencimento, contribuição ou reconhecimento','líderes precisam desenvolver autonomia, apoio e crescimento'),'capacidades',jsonb_build_array('conectar propósito ao cotidiano','fortalecer comunidade e pertencimento','tornar contribuição e impacto visíveis','praticar reconhecimento específico','equilibrar autonomia, apoio e desafio','estruturar práticas e plano de ação')),
    jsonb_build_object('codigo','certificacao_avancada','nome_oficial','Certificação Avançada em Liderança e Saúde Mental Positiva','eixo_canonico','Integração sistêmica dos três','tipo','certificacao_integrada','adequado_quando',jsonb_build_array('os três desafios aparecem de forma conectada','a pessoa busca uma visão sistêmica e formação abrangente','há intenção real de integrar as três formações em um projeto aplicado'),'capacidades',jsonb_build_array('integrar bem-estar, segurança psicológica e significado','conectar diagnósticos e práticas','estruturar projeto aplicado','consolidar uma visão sistêmica de liderança, cultura e trabalho'))
  )
), atualizado_em=now()
where id=md5('mind-product-intelligence:mind-institute')::uuid and ativo;

update dash.knowledge_documents
set metadata = metadata || jsonb_build_object(
  'resultado_principal','transformar diagnóstico e prioridades em um sistema de gestão com implementação e acompanhamento',
  'profundidade','diagnóstico, desenho, implementação ou apoio à implementação e acompanhamento',
  'formato','consultoria e assessoria estratégica sob medida',
  'escopo','organização, cultura, liderança, desenho do trabalho e práticas de gestão'
), atualizado_em=now()
where id=md5('mind-product-intelligence:mind-dash')::uuid and ativo;

update summit_2026.knowledge_documents
set metadata = metadata || jsonb_build_object(
  'resultado_principal','ampliar repertório, perspectivas e conexões para melhorar decisões e mobilizar agendas',
  'profundidade','exposição qualificada, comparação de perspectivas e aprendizagem em múltiplos formatos',
  'formato','evento presencial com palestras, painéis, workshops, masterclasses e networking, conforme acesso do ingresso',
  'escopo','pessoa, grupo ou delegação vivendo a experiência do evento'
), atualizado_em=now()
where id=md5('mind-product-intelligence:mind-summit-2026')::uuid and ativo;

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
  ), documentos as (
    select d.produto_codigo,d.metadata from summit_2026.knowledge_documents d where d.id=md5('mind-product-intelligence:mind-summit-2026')::uuid and d.ativo
    union all select d.produto_codigo,d.metadata from institute.knowledge_documents d where d.id=md5('mind-product-intelligence:mind-institute')::uuid and d.ativo
    union all select d.produto_codigo,d.metadata from dash.knowledge_documents d where d.id=md5('mind-product-intelligence:mind-dash')::uuid and d.ativo
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
        'nenhuma recomendação é um resultado válido',
        'não apresentar uma solução como versão superior da outra'
      )
    ),
    'produtos',coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'codigo',p.codigo,
      'nome',p.nome,
      'natureza',case when p.codigo='mind' then 'ecossistema' else d.metadata->>'natureza_solucao' end,
      'definicao',coalesce(p.descricao,p.descricao_curta),
      'resultado_principal',d.metadata->>'resultado_principal',
      'profundidade',d.metadata->>'profundidade',
      'formato',d.metadata->>'formato',
      'escopo',d.metadata->>'escopo',
      'resolve',d.metadata->'resolve',
      'capacidades',d.metadata->'capacidades',
      'eixos',d.metadata->'eixos',
      'programas',d.metadata->'programas',
      'adequado_quando',d.metadata->'adequado_quando',
      'limites',d.metadata->'limites'
    )) order by case p.codigo when 'mind' then 0 when 'mind-summit-2026' then 1 when 'mind-institute' then 2 when 'mind-dash' then 3 else 9 end),'[]'::jsonb),
    'nao_contem',jsonb_build_array('preço','lote','parcelamento','checkout','turma','disponibilidade')
  )
  from produtos p left join documentos d on d.produto_codigo=p.codigo;
$function$;

revoke execute on function public.mind_kit_product_intelligence(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.mind_kit_product_intelligence(uuid,jsonb) to service_role;

do $check$
declare v text;
begin
  select conteudo into v from agentes.prompts where chave='product_decisioning' and ativo;
  if v is null then raise exception 'product_decisioning ausente'; end if;
  if position('4. COMO DECIDIR' in v)=0 or position('DASH' in v)=0 then raise exception 'estrutura inesperada do prompt'; end if;
end $check$;

update agentes.prompts
set conteudo = replace(
  replace(
    conteudo,
    E'Limite: não executa pela organização uma transformação completa e não substitui diagnóstico organizacional amplo.\n\nDASH',
    E'Limite: não executa pela organização uma transformação completa e não substitui diagnóstico organizacional amplo.\n\nSE INSTITUTE FOR O FIT PRINCIPAL\n\nSó escolha uma formação específica quando a transformação buscada apontar claramente para uma capacidade atual do programa. Não escolha por ICP nem por código JTBD isolado.\n\n- Gestão Estratégica de Bem-Estar no Trabalho: estruturar bem-estar como gestão; riscos e ativos psicossociais; diagnóstico → intervenção; business case e indicadores.\n- Segurança Psicológica e Voz Ativa: confiança, voz, aprendizagem, accountability e conversas difíceis.\n- Engajamento e Significado no Trabalho: propósito no cotidiano, pertencimento, contribuição, reconhecimento, autonomia e crescimento.\n- Certificação Avançada: somente quando múltiplos eixos aparecem de forma realmente conectada ou a pessoa busca deliberadamente uma formação integrada e abrangente.\n\nSe Institute for o melhor fit mas ainda não houver evidência para escolher uma formação, recomende Institute como caminho e faça no máximo uma pergunta discriminante.\n\nDASH'
  ),
  E'==================================================\n4. COMO DECIDIR\n==================================================\n\nSe os quatro eixos apontarem para uma solução, recomende-a com uma razão concreta.',
  E'==================================================\n4. COMO DECIDIR\n==================================================\n\nNENHUMA RECOMENDAÇÃO É UM RESULTADO VÁLIDO.\nSe nenhuma solução do Mind resolver de forma coerente a transformação buscada agora, não force fit e não invente necessidade. Continue ajudando dentro da competência atual ou diga com honestidade que não há uma solução clara para recomendar.\n\nSe os quatro eixos apontarem para uma solução, recomende-a com uma razão concreta.'
), versao=2
where chave='product_decisioning' and ativo;

update agentes.prompts
set conteudo=replace(
  conteudo,
  E'SOLUCAO_PRINCIPAL\nCONFIANCA',
  E'SOLUCAO_PRINCIPAL  [Summit | Institute | Dash | nenhuma]\nPROGRAMA_INSTITUTE  [somente quando Institute for principal e houver evidência suficiente]\nCONFIANCA'
)
where chave='product_decisioning' and ativo;

do $verify$
declare v_pi jsonb; v_pd text; v_b2c text; v_c uuid; v_kit jsonb; v_inst jsonb;
begin
  v_pi:=public.mind_kit_product_intelligence(null,null);
  if jsonb_array_length(coalesce(v_pi->'produtos','[]'::jsonb))<>4 then raise exception 'PI: produtos != 4'; end if;
  select e into v_inst from jsonb_array_elements(v_pi->'produtos') e where e->>'codigo'='mind-institute';
  if jsonb_array_length(coalesce(v_inst->'programas','[]'::jsonb))<>4 then raise exception 'PI: programas Institute != 4'; end if;
  if coalesce(v_inst->>'profundidade','')='' or coalesce(v_inst->>'formato','')='' or coalesce(v_inst->>'escopo','')='' then raise exception 'PI: contrato incompleto'; end if;
  if v_pi::text ilike '%R$%' then raise exception 'PI: valor comercial vazou'; end if;
  select conteudo into v_pd from agentes.prompts where chave='product_decisioning' and ativo;
  if position('NENHUMA RECOMENDAÇÃO É UM RESULTADO VÁLIDO' in v_pd)=0 or position('SE INSTITUTE FOR O FIT PRINCIPAL' in v_pd)=0 or position('PROGRAMA_INSTITUTE' in v_pd)=0 then raise exception 'PD: contrato v2 incompleto'; end if;
  if (select versao from agentes.prompts where chave='product_decisioning')<>2 then raise exception 'PD: versao != 2'; end if;
  select public.treble_agent_prompt('summit_b2c','decisioning') into v_b2c;
  if position('NENHUMA RECOMENDAÇÃO É UM RESULTADO VÁLIDO' in coalesce(v_b2c,''))=0 then raise exception 'PD: composição Treble sem v2'; end if;
  select id into v_c from engagement.conversas order by iniciada_em desc limit 1;
  if v_c is not null then
    v_kit:=public.mind_agent_kit('concierge_summit',v_c,jsonb_build_object('pergunta','oi','interesses','[]'::jsonb));
    if not ((v_kit->'structured') ? 'product_intelligence') then raise exception 'Kit Concierge sem Product Intelligence'; end if;
  end if;
end $verify$;
