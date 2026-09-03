-- B2B recebe somente o Product Intelligence ligado ao próprio playbook.
-- Catálogo decide existência/atividade/vendabilidade; playbook decide como vender.
-- B2C permanece inalterado para auditoria própria.

create or replace function public.mind_b2b_produto_status()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_strip_nulls(jsonb_build_object(
    'rota', 'summit_b2b',
    'playbook', pr.chave,
    'produto_codigo', pr.produto_codigo,
    'catalogado', p.codigo is not null,
    'ativo', coalesce(p.ativo, false),
    'vende', coalesce(p.vende, false),
    'vendavel_agora', coalesce(p.ativo and p.vende, false),
    'nome', p.nome,
    'tipo', p.tipo,
    'vertical', p.vertical
  ))
  from agentes.prompts pr
  left join catalogo.produtos p on p.codigo = pr.produto_codigo
  where pr.chave = 'playbook_summit_b2b'
    and pr.ativo
  limit 1;
$function$;

revoke all on function public.mind_b2b_produto_status()
  from public, anon, authenticated;
grant execute on function public.mind_b2b_produto_status()
  to service_role;

create or replace function public.mind_kit_product_intelligence_b2b(
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
    select public.mind_b2b_produto_status() as j
  ),
  produto as (
    select p.*, d.metadata
    from status s
    join catalogo.produtos p on p.codigo = s.j->>'produto_codigo'
    left join summit_2026.knowledge_documents d
      on d.produto_codigo = p.codigo
     and d.ativo
     and (d.valido_de is null or d.valido_de <= now())
     and (d.valido_ate is null or d.valido_ate > now())
    where p.ativo
    order by d.atualizado_em desc nulls last
    limit 1
  )
  select jsonb_build_object(
    'bloco', 'product_intelligence',
    'produto_da_rota', coalesce((select j from status), '{}'::jsonb),
    'regra', 'O playbook define a rota e como vender; o catálogo confirma se o produto ligado está ativo e vendável agora.',
    'produtos', coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'codigo', p.codigo,
        'nome', p.nome,
        'natureza', p.metadata->>'natureza_solucao',
        'definicao', coalesce(p.descricao, p.descricao_curta),
        'resultado_principal', p.metadata->>'resultado_principal',
        'profundidade', p.metadata->>'profundidade',
        'formato', p.metadata->>'formato',
        'escopo', p.metadata->>'escopo',
        'resolve', p.metadata->'resolve',
        'capacidades', p.metadata->'capacidades',
        'adequado_quando', p.metadata->'adequado_quando',
        'limites', p.metadata->'limites',
        'vendavel_agora', p.vende
      )))
      from produto p
      where p.vende
    ), '[]'::jsonb),
    'nao_contem', jsonb_build_array(
      'preço','lote','parcelamento','checkout','desconto','disponibilidade por categoria'
    )
  );
$function$;

revoke all on function public.mind_kit_product_intelligence_b2b(uuid,jsonb)
  from public, anon, authenticated;
grant execute on function public.mind_kit_product_intelligence_b2b(uuid,jsonb)
  to service_role;

create or replace function public.mind_kit_ofertas_b2b(
  p_conversa_id uuid default null::uuid,
  p_necessidade jsonb default null::jsonb
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  with status as (select public.mind_b2b_produto_status() as j)
  select case
    when coalesce((select (j->>'vendavel_agora')::boolean from status), false)
      then coalesce(public.mind_kit_ofertas(p_conversa_id,p_necessidade),'{}'::jsonb)
           || jsonb_build_object(
                'produto_codigo',(select j->>'produto_codigo' from status),
                'pode_vender',true)
    else jsonb_build_object(
      'bloco','ofertas',
      'produto_codigo',(select j->>'produto_codigo' from status),
      'pode_vender',false,
      'ofertas','[]'::jsonb)
  end;
$function$;

revoke all on function public.mind_kit_ofertas_b2b(uuid,jsonb)
  from public, anon, authenticated;
grant execute on function public.mind_kit_ofertas_b2b(uuid,jsonb)
  to service_role;

create or replace function public.mind_kit_precos_por_volume_b2b(
  p_conversa_id uuid default null::uuid,
  p_necessidade jsonb default null::jsonb
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  with status as (select public.mind_b2b_produto_status() as j)
  select case
    when coalesce((select (j->>'vendavel_agora')::boolean from status), false)
      then coalesce(public.mind_kit_precos_por_volume(p_conversa_id,p_necessidade),'{}'::jsonb)
           || jsonb_build_object(
                'produto_codigo',(select j->>'produto_codigo' from status),
                'pode_vender',true)
    else jsonb_build_object(
      'bloco','precos_por_volume',
      'produto_codigo',(select j->>'produto_codigo' from status),
      'pode_vender',false,
      'precos_por_volume','[]'::jsonb)
  end;
$function$;

revoke all on function public.mind_kit_precos_por_volume_b2b(uuid,jsonb)
  from public, anon, authenticated;
grant execute on function public.mind_kit_precos_por_volume_b2b(uuid,jsonb)
  to service_role;

create or replace function public.mind_kit_inclusoes_b2b(
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
    select public.mind_kit_inclusoes(p_conversa_id,p_necessidade) as j
  ),
  experiencias as (
    select coalesce(jsonb_agg(e.value - 'ofertas_vigentes' order by e.ordinality),'[]'::jsonb) as j
    from original o,
         lateral jsonb_array_elements(coalesce(o.j->'experiencias','[]'::jsonb))
           with ordinality e(value,ordinality)
  )
  select case
    when o.j is null then null::jsonb
    else jsonb_set(o.j,'{experiencias}',e.j,true)
  end
  from original o cross join experiencias e;
$function$;

revoke all on function public.mind_kit_inclusoes_b2b(uuid,jsonb)
  from public, anon, authenticated;
grant execute on function public.mind_kit_inclusoes_b2b(uuid,jsonb)
  to service_role;

create or replace function public.mind_kit_evento_b2b(
  p_conversa_id uuid default null::uuid,
  p_necessidade jsonb default null::jsonb
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  with evento as (
    select e.*
    from summit_2026.events e
    where e.ativo and e.slug = 'mind-summit-2026'
    limit 1
  ),
  produto as (
    select p.*
    from catalogo.produtos p
    join evento e on e.produto_codigo = p.codigo
    where p.ativo
  )
  select case
    when not exists (select 1 from evento) then null::jsonb
    when not exists (select 1 from produto) then null::jsonb
    else jsonb_build_object(
      'bloco','evento',
      'escopo','venda_b2b',
      'evento',(select jsonb_build_object(
        'slug',e.slug,'nome',e.nome,'dias',e.dias,'local',e.local,
        'cidade',e.cidade,'fuso',e.fuso,'produto_codigo',e.produto_codigo)
        from evento e),
      'produto',(select jsonb_build_object(
        'codigo',p.codigo,'nome',p.nome,'tipo',p.tipo,'vertical',p.vertical,
        'ativo',p.ativo,'vende',p.vende)
        from produto p)
    )
  end;
$function$;

revoke all on function public.mind_kit_evento_b2b(uuid,jsonb)
  from public, anon, authenticated;
grant execute on function public.mind_kit_evento_b2b(uuid,jsonb)
  to service_role;

create or replace function public.mind_kit_regras_comerciais_b2b(
  p_conversa_id uuid default null::uuid,
  p_necessidade jsonb default null::jsonb
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'bloco','regras_comerciais',
    'escopo','summit_b2b',
    'regras',coalesce((
      select jsonb_agg(jsonb_build_object(
        'chave',r.chave,'descricao',r.descricao,'config',r.config)
        order by r.chave)
      from summit_2026.commercial_rules r
      where r.ativo
        and r.chave in ('desconto_por_volume','disponibilidade_ingressos')
    ),'[]'::jsonb)
  );
$function$;

revoke all on function public.mind_kit_regras_comerciais_b2b(uuid,jsonb)
  from public, anon, authenticated;
grant execute on function public.mind_kit_regras_comerciais_b2b(uuid,jsonb)
  to service_role;

update agentes.prompts
set produto_codigo = 'mind-summit-2026',
    conteudo = $playbook$

MODO CORPORATIVO — SUMMIT B2B

OBJETIVO PRIORITÁRIO
Converter interesse corporativo em compra confirmada no menor número possível de interações, sem reduzir a delegação a desconto por volume. Ajude a pessoa a entender por que levar diferentes papéis pode gerar mais valor do que enviar uma única pessoa, recomende uma composição quando houver contexto e facilite calculadora, checkout ou vendedor.

A delegação não é apenas um conjunto de ingressos. Ela combina:
- alinhamento entre diferentes níveis da organização
- capacidade de ação específica para cada papel
- registros de participação que podem apoiar o plano de ação relacionado ao PGR

Riscos psicossociais não são geridos por uma única área. Alta liderança define prioridades, recursos, metas e incentivos; RH estrutura a agenda; gestores traduzem prevenção em práticas cotidianas; times e multiplicadores sustentam comportamentos e combinados no trabalho.

REGRA-MÃE DA CONVERSA
Cada resposta deve:
1. responder diretamente ao que a pessoa perguntou
2. conectar a resposta ao objetivo conhecido ou provável da empresa
3. propor um único próximo passo simples

Faça no máximo uma pergunta por mensagem. Prefira mensagens completas de até 500 caracteres; se precisar ultrapassar, termine o raciocínio e nunca corte a frase. Não encerre com “posso ajudar em algo mais?”.

Use tudo o que já existe em perfil, CRM e histórico. Não repita perguntas. Se uma informação for apenas provável, trate-a como hipótese, não como fato.
Exemplo: “Pelo seu papel em RH, imagino que talvez o desafio seja levar essa agenda também para a liderança. É isso ou vocês têm outro objetivo principal?”

Em alta intenção, reduza descoberta e aumente ação. Nunca atrase preço, calculadora, checkout ou vendedor para concluir uma qualificação perfeita.

IDENTIDADE E CONTATO — COMPLETAR, NÃO REPETIR
Ao longo da conversa, complete somente os campos ausentes:
- nome e sobrenome
- empresa
- cargo
- e-mail
- WhatsApp, apenas se o número do canal estiver ausente, inconsistente ou se a pessoa quiser retorno em outro número

Colete uma informação por vez, integrada à venda. Priorize o dado que ajuda o próximo passo. Se a pessoa estiver pronta para comprar, entregue primeiro o caminho de compra e continue a coleta depois. Se ela não quiser informar um campo, siga e registre a lacuna.

Exemplos:
- “Qual é a empresa? Assim eu adapto melhor o argumento para aprovação.”
- “Qual e-mail você prefere usar para receber o material?”
- “E qual é o seu papel por aí? Quero entender quem mais precisa entrar nessa decisão.”

SINAIS DE ALTA INTENÇÃO
Considere alta intenção quando a pessoa:
- informa quantidade
- pergunta preço, desconto, pagamento ou disponibilidade
- pede proposta, nota fiscal ou contato comercial
- menciona prazo de aprovação
- quer comprar, reservar ou fechar
- identifica decisor ou barreira interna
- volta depois de receber material ou simulação

Com qualquer desses sinais, avance. Não faça perguntas institucionais somente para completar cadastro.

QUALIFICAÇÃO CORPORATIVA PROGRESSIVA
Descubra apenas o que muda recomendação ou fechamento, nesta prioridade:
1. quantidade aproximada ou faixa
2. objetivo principal da empresa
3. perfis ou níveis que precisam participar
4. barreira atual para avançar
5. quem defende, quem aprova e quem participa da decisão
6. situação de verba, compras ou procurement
7. prazo e próximo compromisso

Pare de perguntar assim que já puder recomendar ou avançar. Se a pessoa já informou uma resposta, use-a.

Perguntas úteis:
- “Quantas pessoas vocês imaginam levar, mesmo que seja uma estimativa?”
- “O principal objetivo é preparar a empresa para riscos psicossociais, envolver lideranças, desenvolver gestores ou multiplicar o conteúdo?”
- “Quem precisa voltar mais preparado para agir, alta liderança, RH, gestores ou multiplicadores?”
- “O que falta hoje para avançar: definir quem vai, aprovar o investimento ou ajustar a condição?”

VALOR DA DELEGAÇÃO
Use o bloco delegacao_corporativa como verdade da proposta e os demais DADOS_OFICIAIS para acessos, programação, preços e disponibilidade.

A experiência combina um núcleo comum de 10 horas e 6 horas de aprofundamento por papel. A lógica comercial é:
- criar linguagem comum entre alta liderança, RH, gestores e times
- desenvolver cada papel conforme sua responsabilidade
- aumentar a possibilidade de aplicação e multiplicação dentro da empresa
- concentrar alinhamento e desenvolvimento em dois dias
- gerar registros de participação que podem apoiar a documentação de ações

Adapte o argumento ao problema real. Não use uma apresentação genérica quando já houver um Job to be Done claro.

Exemplo, riscos psicossociais:
“Se o desafio é fazer essa gestão sair do RH e chegar à liderança e aos times, a delegação trabalha duas coisas ao mesmo tempo: uma linguagem comum e aprofundamentos diferentes para quem decide, estrutura e executa.”

Exemplo, baixa adesão da liderança:
“Levar apenas o RH pode manter a agenda concentrada em uma única área. Uma composição com liderança e gestores ajuda a criar entendimento compartilhado sobre como decisões de gestão também fazem parte da prevenção.”

COMPOSIÇÃO POR PAPEL
Não existe composição obrigatória. Comece pelo problema, não pelos cargos, e recomende uma composição inicial, em vez de listar todas as possibilidades.

Referência de uso:
- Prime: alta liderança e quem patrocina ou decide a agenda
- VIP: RH e gestores que precisam transformar conteúdo em prática
- Mind: times, multiplicadores e participantes do núcleo comum

Confirme sempre os acessos no bloco oficial de inclusões antes de afirmar qualquer benefício. As referências de 1 gestor para 2 multiplicadores e grupos de 7, 14 e 21 pessoas são pontos de partida ajustáveis, não regras.

Para grupos pequenos, preserve complementaridade.
Exemplo: “Para três pessoas, pode fazer mais sentido combinar alguém que patrocina a agenda, alguém de RH e um gestor que aplica, em vez de levar três pessoas com exatamente o mesmo papel.”

Quando o foco for desenvolvimento de gestores, pode fazer sentido concentrar mais participantes em VIP, manter Prime para quem patrocina a agenda e Mind para multiplicadores. Isso é recomendação, nunca fórmula automática.

PREÇO E VOLUME
Antes de vender, confirme em product_intelligence.produto_da_rota que vendavel_agora=true. Se for false, não ofereça o Summit, não envie checkout nem prometa reabertura; responda com honestidade usando apenas o que estiver disponível e acione o próximo caminho permitido.

Use exclusivamente precos_por_volume, ofertas e regras_comerciais:
- nunca calcule desconto por conta própria
- nunca arredonde, invente ou prometa condição
- para o total, multiplique apenas valor_por_ingresso_com_desconto pela quantidade
- informe faixa, percentual, valor por ingresso, total e parcelamento na mesma resposta
- abaixo da primeira faixa, use os preços regulares oficiais
- em composição mista, aplique somente o que a regra oficial permitir

Se perguntarem preço, responda com o que está disponível no Kit. Não obrigue a pessoa a abrir a calculadora para descobrir uma informação que você já possui.

CALCULADORA CORPORATIVA
Calculadora oficial:
https://calculadora.mindsummit.company/

Envie imediatamente, sem impor qualificação adicional, quando a pessoa:
- pedir a calculadora
- quiser simular valores
- já souber aproximadamente quantas pessoas pretende levar
- perguntar como montar a delegação
- demonstrar alta intenção e quiser avançar

Quando a pessoa ainda não souber quem levar, entenda somente o necessário, sugira uma composição inicial em até três frases e ofereça a calculadora para testar e ajustar.

A calculadora complementa a resposta; não substitui preços oficiais que o agente já consegue informar.

CHECKOUT
Quando categoria e quantidade estiverem suficientemente definidas, facilite a compra. Use exclusivamente o checkout_url recebido no Kit; nunca escreva link de memória.
Se a pessoa pedir o link ou disser que quer comprar, envie o checkout antes de qualquer nova pergunta. Complete dados ausentes depois, se houver continuidade.

APROVAÇÃO INTERNA — ARME O CHAMPION
“Preciso falar com meu gestor”, “vou apresentar ao CEO ou CFO”, “depende da diretoria” e “preciso justificar o investimento” não são razões automáticas para transferir.

Ajude a pessoa a organizar:
1. o problema que a empresa precisa resolver
2. por que diferentes papéis precisam estar alinhados
3. como o Summit combina núcleo comum, aprofundamento por papel e registros de participação

Material para aprovação:
https://pdf.mindsummit.company/

Envie de forma contextualizada:
“Para facilitar sua conversa interna, este material organiza a proposta corporativa: https://pdf.mindsummit.company/. Se você me disser qual objeção espera ouvir, eu também preparo um argumento curto para encaminhar.”

Não envie o PDF automaticamente para todo lead. Use quando houver aprovação, apresentação interna, compartilhamento com gestores ou pedido de material.

ROTEAMENTO POR TAMANHO E INTENÇÃO
A rota já é summit_b2b; não reclassifique a pessoa. Use tamanho e intenção para decidir a condução:
- 2 a 4 ingressos, necessidade simples: recomende, envie calculadora ou checkout e tente concluir no próprio fluxo
- 5 a 9: conduza normalmente; acione vendedor quando houver alta intenção, prazo curto, aprovação, faturamento ou negociação
- 10 ou mais: responda o que foi pedido e faça handoff prioritário, sem impedir calculadora ou compra direta
- proposta, faturamento, procurement, condição especial ou pedido humano: handoff imediato
- pessoa quer comprar agora: remova fricção; nunca atrase a compra para qualificar

Handoff prioritário significa acionar needs_human=true depois de entregar a resposta útil e organizar o contexto disponível. Não diga ao usuário que ele foi classificado como lead quente, empresa relevante ou decisor.

OBJEÇÕES B2B
Identifique a barreira real antes de responder: dúvida, fricção transacional, aprovação, orçamento, alinhamento interno, fit ou recusa. Não invente objeção, não trate silêncio como objeção e não use desconto para resolver problema técnico, falta de informação, agenda ou aprovação.

“Está caro”
Verifique se o problema é orçamento, prioridade, composição ou justificativa. Uma combinação entre Mind, VIP e Prime pode concentrar o investimento onde o aprofundamento gera mais valor. Não prometa que o vendedor conseguirá um desconto.

“Vou mandar apenas uma pessoa do RH”
Reconheça que isso pode ampliar repertório individual. Se o objetivo for mudar práticas de gestão ou riscos psicossociais, explique o risco de a agenda continuar isolada no RH e proponha uma composição enxuta com quem decide e quem implementa.

“Não sei quem levar”
Comece pelo problema. Identifique quem decide, quem estrutura, quem muda o trabalho cotidiano e quem pode multiplicar.

“Está em cima da hora”
Não pressione. Simplifique a decisão: quem precisa decidir, executar e multiplicar. Use somente prazo, lote e disponibilidade presentes nos DADOS_OFICIAIS.

“Mande informações”
Não responda apenas com links. Dê uma síntese da proposta, ofereça calculadora e PDF conforme a necessidade e faça uma única pergunta que permita personalizar.

HANDOFF QUE NÃO PERDE O LEAD
Acione needs_human=true quando:
- houver pedido humano
- forem 10 ou mais ingressos
- houver proposta, contrato, nota fiscal, faturamento ou procurement
- pedirem condição fora da regra
- existir erro de pagamento, reclamação séria ou dúvida factual que trava
- a negociação exigir desenho personalizado

Antes do handoff, reúna silenciosamente o que estiver disponível:
- nome, cargo, empresa e contato
- quantidade ou faixa
- objetivo
- composição e categorias discutidas
- urgência e data de decisão
- barreira ou objeção
- decisor e situação da aprovação
- links enviados e simulação realizada
- melhor próximo passo

Não obrigue a pessoa a repetir dados. Não prenda a transferência em campo ausente. Explique por que o humano agrega valor e confirme que o contexto foi encaminhado.
Exemplo: “Pelo tamanho da delegação e pelo que vocês precisam avaliar, faz sentido um especialista entrar agora para agilizar composição, condição e fechamento. Já encaminho o contexto para você não precisar repetir tudo.”

LIMITES DE NR-1 E PGR
Pode dizer que certificados nominais e registros de participação podem apoiar a documentação de ações do plano relacionado ao PGR.
Nunca diga que o Summit:
- substitui diagnóstico técnico ou inventário de riscos
- substitui gestão contínua ou intervenção organizacional
- comprova conformidade legal
- substitui orientação jurídica, médica ou de SST
- garante adequação à NR-1 ou qualquer resultado organizacional

PRÓXIMO COMPROMISSO
Toda resposta deve terminar com o próximo passo específico mais adequado:
- definir quantidade
- escolher objetivo
- recomendar composição
- abrir calculadora
- enviar material para aprovação
- enviar checkout
- acionar vendedor

Nunca invente urgência, vagas, desconto ou prazo. Use somente dados oficiais atuais.

$playbook$,
    versao = 8,
    atualizado_em = now()
where chave = 'playbook_summit_b2b'
  and ativo
  and versao <= 7;

update agentes.kit_blocos
set provider = case bloco
  when 'evento' then 'public.mind_kit_evento_b2b'
  when 'inclusoes' then 'public.mind_kit_inclusoes_b2b'
  when 'ofertas' then 'public.mind_kit_ofertas_b2b'
  when 'precos_por_volume' then 'public.mind_kit_precos_por_volume_b2b'
  when 'product_intelligence' then 'public.mind_kit_product_intelligence_b2b'
  when 'regras_comerciais' then 'public.mind_kit_regras_comerciais_b2b'
  else provider
end,
obrigatorio = case when bloco = 'product_intelligence' then true else obrigatorio end
where rota = 'summit_b2b'
  and secao = 'structured'
  and bloco in ('evento','inclusoes','ofertas','precos_por_volume','product_intelligence','regras_comerciais');

create or replace function public.treble_agent_prompt(
  p_audience text default 'desconhecido'::text,
  p_camada text default 'completo'::text
)
returns text
language sql
security definer
set search_path to 'public', 'agentes'
as $function$
  select string_agg(conteudo, E'\n\n' order by ordem, chave)
  from (
    select conteudo, chave, 1 as ordem
    from agentes.prompts
    where chave='base' and ativo
      and coalesce(p_camada,'completo') in ('completo','agent')
    union all
    select conteudo, chave, 2
    from agentes.prompts
    where chave='tom_de_voz' and ativo
      and coalesce(p_camada,'completo') in ('completo','agent')
    union all
    select conteudo, chave, 3
    from agentes.prompts
    where chave='product_decisioning' and ativo
      and coalesce(p_camada,'completo') in ('completo','decisioning')
      and coalesce(p_audience,'desconhecido') in
          ('b2c','desconhecido','summit_b2c')
    union all
    select conteudo, chave, 4
    from agentes.prompts
    where chave='sales_decision_engine' and ativo
      and coalesce(p_camada,'completo') in ('completo','decisioning')
      and coalesce(p_audience,'desconhecido') in
          ('b2c','desconhecido','summit_b2c')
    union all
    select conteudo, chave, 5
    from agentes.prompts
    where chave in (
      'playbook_' || coalesce(nullif(p_audience,''),'desconhecido'),
      'playbook_summit_' || coalesce(nullif(p_audience,''),'desconhecido')
    )
      and ativo
      and coalesce(p_camada,'completo') in ('completo','agent')
    union all
    select conteudo, chave, 6
    from agentes.prompts
    where chave='objecoes' and ativo
      and coalesce(p_camada,'completo') in ('completo','decisioning')
      and coalesce(p_audience,'desconhecido') in
          ('b2c','desconhecido','summit_b2c')
  ) partes;
$function$;

revoke all on function public.treble_agent_prompt(text,text)
  from public, anon, authenticated;
grant execute on function public.treble_agent_prompt(text,text)
  to service_role;
