-- Credenciamento person-bound e cadastro B2B progressivo e validado.
-- Dados do comprador permanecem armazenados no espelho, mas não entram no contexto
-- do modelo nem ganham endpoint novo de consulta.

DO $migration$
DECLARE
  v_atualizados integer;
BEGIN
  UPDATE agentes.prompts
     SET conteudo = $playbook$


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

CADASTRO B2B OBRIGATÓRIO E PROGRESSIVO
O cadastro mínimo é: primeiro nome, sobrenome, e-mail, WhatsApp, empresa e cargo.

Antes de perguntar, verifique perfil, CRM, histórico e credenciamento. Um campo só está ausente quando não aparece em nenhuma dessas fontes. O WhatsApp conta como conhecido quando estiver no perfil ou no credenciamento; o dado do participante no credenciamento conta como conhecido, mas dado do comprador nunca deve ser usado como se fosse da pessoa.

Se qualquer campo mínimo estiver ausente, sempre colete o próximo. Faça uma pergunta curta por mensagem e integre-a à conversa; nunca despeje uma ficha. Nome e sobrenome podem ser pedidos juntos como nome completo. Continue nos turnos seguintes até os seis campos estarem completos.

Antes de considerar e-mail ou WhatsApp completos, confira a validação recebida no contexto. Validação de formato não comprova propriedade nem entregabilidade. Se o formato estiver inválido ou ambíguo, diga com naturalidade que o dado parece incorreto e peça confirmação ou correção; não marque o campo como preenchido.

Responda primeiro ao que a pessoa pediu e execute a ação disponível. Depois, na mesma mensagem, peça o próximo campo ausente. Preço, calculadora, checkout e handoff não ficam bloqueados, mas também não encerram a coleta enquanto houver conversa.

Ordem preferencial quando vários campos faltarem: nome completo, empresa, cargo, e-mail e WhatsApp. Adapte a ordem ao contexto sem deixar nenhum campo para trás. Nunca repita um dado já conhecido.

SINAIS DE ALTA INTENÇÃO
Considere alta intenção quando a pessoa:
- informa quantidade
- pergunta preço, desconto, pagamento ou disponibilidade
- pede proposta, nota fiscal ou contato comercial
- menciona prazo de aprovação
- quer comprar, reservar ou fechar
- identifica decisor ou barreira interna
- volta depois de receber material ou simulação

Com qualquer desses sinais, avance na venda e mantenha a coleta cadastral progressiva: entregue valor primeiro e peça o próximo campo ausente na mesma mensagem.

QUALIFICAÇÃO CORPORATIVA PROGRESSIVA
Descubra apenas o que muda recomendação ou fechamento, nesta prioridade:
1. quantidade aproximada ou faixa
2. objetivo principal da empresa
3. perfis ou níveis que precisam participar
4. barreira atual para avançar
5. quem defende, quem aprova e quem participa da decisão
6. situação de verba, compras ou procurement
7. prazo e próximo compromisso

Pare de fazer perguntas de qualificação comercial assim que já puder recomendar ou avançar. Isso não interrompe o cadastro obrigatório: continue pedindo o próximo campo mínimo ausente. Se a pessoa já informou uma resposta, use-a.

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
Se a pessoa pedir o link ou disser que quer comprar, envie o checkout antes da pergunta cadastral e, na mesma mensagem, peça o próximo campo ausente. Continue nos turnos seguintes até completar o cadastro.

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

Não obrigue a pessoa a repetir dados. Não prenda a transferência em campo ausente, mas peça o próximo campo cadastral ausente enquanto a conversa estiver ativa. Explique por que o humano agrega valor e confirme que o contexto foi encaminhado.
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
         versao = 9,
         atualizado_em = now()
   WHERE chave = 'playbook_summit_b2b'
     AND ativo
     AND versao = 8;

  GET DIAGNOSTICS v_atualizados = ROW_COUNT;
  IF v_atualizados <> 1 THEN
    RAISE EXCEPTION 'playbook_summit_b2b: esperado atualizar uma versão 8, atualizadas %', v_atualizados;
  END IF;
END
$migration$;

CREATE OR REPLACE FUNCTION public.mind_identificador_validar(p_canal text, p_valor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_canal text := lower(btrim(coalesce(p_canal, '')));
  v_valor text := btrim(coalesce(p_valor, ''));
  v_normalizado text;
begin
  if v_canal = 'whatsapp' then
    v_normalizado := public.telefone_normalizar(v_valor);
  elsif v_canal = 'email' then
    v_normalizado := lower(v_valor);
    if v_normalizado = ''
       or length(v_normalizado) > 320
       or v_normalizado !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$' then
      v_normalizado := null;
    end if;
  else
    return jsonb_build_object('valido', false, 'canal', v_canal, 'motivo', 'canal_invalido');
  end if;

  return jsonb_build_object(
    'valido', v_normalizado is not null,
    'canal', v_canal,
    'motivo', case when v_normalizado is null then 'formato_invalido' else null end
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.mind_identificador_declarado_registrar(
  p_pessoa_id uuid,
  p_canal text,
  p_valor text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_canal text := lower(btrim(coalesce(p_canal, '')));
  v_normalizado text;
  v_dono uuid;
  v_inseridos integer := 0;
begin
  if p_pessoa_id is null
     or not exists (select 1 from pessoas.pessoas p where p.id = p_pessoa_id) then
    return jsonb_build_object('ok', false, 'motivo', 'pessoa_invalida');
  end if;

  if coalesce((public.mind_identificador_validar(v_canal, p_valor)->>'valido')::boolean, false)
     is not true then
    return jsonb_build_object('ok', false, 'canal', v_canal, 'motivo', 'formato_invalido');
  end if;

  if v_canal = 'whatsapp' then
    v_normalizado := public.telefone_normalizar(p_valor);
  elsif v_canal = 'email' then
    v_normalizado := lower(btrim(p_valor));
  else
    return jsonb_build_object('ok', false, 'canal', v_canal, 'motivo', 'canal_invalido');
  end if;

  select i.pessoa_id into v_dono
  from engagement.identidades i
  where i.canal = v_canal and i.identificador = v_normalizado
  limit 1;

  if v_dono is not null and v_dono <> p_pessoa_id then
    perform public.mind_conflito_registrar(
      p_pessoa_id,
      'conflito_identidade',
      'identificador declarado aponta para outra pessoa; conversa ancorada permanece',
      v_dono,
      jsonb_build_object('canal', v_canal)
    );
    return jsonb_build_object('ok', false, 'canal', v_canal, 'motivo', 'conflito_identidade');
  end if;

  if v_dono is null then
    insert into engagement.identidades
      (pessoa_id, canal, identificador, verificado, confianca)
    values
      (p_pessoa_id, v_canal, v_normalizado, false, 'media')
    on conflict (canal, identificador) do nothing;
    get diagnostics v_inseridos = row_count;

    select i.pessoa_id into v_dono
    from engagement.identidades i
    where i.canal = v_canal and i.identificador = v_normalizado
    limit 1;

    if v_dono is distinct from p_pessoa_id then
      perform public.mind_conflito_registrar(
        p_pessoa_id,
        'conflito_identidade',
        'concorrencia ao registrar identificador declarado; conversa ancorada permanece',
        v_dono,
        jsonb_build_object('canal', v_canal)
      );
      return jsonb_build_object('ok', false, 'canal', v_canal, 'motivo', 'conflito_identidade');
    end if;
  end if;

  if v_canal = 'whatsapp' then
    update pessoas.pessoas p
       set whatsapp = v_normalizado, atualizado_em = now()
     where p.id = p_pessoa_id and p.whatsapp is null
       and not exists (
         select 1 from pessoas.pessoas q
         where q.id <> p.id and q.whatsapp = v_normalizado
       );
  elsif v_canal = 'email' then
    update pessoas.pessoas p
       set email = v_normalizado, atualizado_em = now()
     where p.id = p_pessoa_id and p.email is null
       and not exists (
         select 1 from pessoas.pessoas q
         where q.id <> p.id and lower(q.email) = v_normalizado
       );
  end if;

  return jsonb_build_object(
    'ok', true,
    'canal', v_canal,
    'status', case when v_inseridos = 1 then 'registrado' else 'conhecido' end,
    'verificado', false,
    'confianca', 'media'
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.mind_credenciamento_fatos(p_pessoa_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
with registros_ativos as (
  select
    nullif(btrim(v.name), '') as nome,
    nullif(lower(btrim(v.email)), '') as email,
    public.telefone_normalizar(coalesce(v.telefone_norm, v.cellphone)) as whatsapp,
    coalesce(nullif(btrim(v.ticket_name), ''), nullif(btrim(v.ticket_type), '')) as categoria,
    v.sincronizado_em
  from credenciamento_summit_2026.v_participantes v
  where v.pessoa_id = p_pessoa_id
    and lower(coalesce(v.status, '')) = 'ativo'
    and v.revogado_em is null
),
ingressos_ativos as (
  select r.*
  from registros_ativos r
  where r.categoria is not null
    and upper(r.categoria) <> 'SEM MAPA'
),
categorias as (
  select i.categoria, count(*)::integer as quantidade
  from ingressos_ativos i
  group by i.categoria
),
cadastro as (
  select jsonb_strip_nulls(jsonb_build_object(
    'nome', case
      when count(distinct lower(r.nome)) filter (where r.nome is not null) = 1
      then min(r.nome) filter (where r.nome is not null)
      else null
    end,
    'email', case
      when count(distinct r.email) filter (where r.email is not null) = 1
      then min(r.email) filter (where r.email is not null)
      else null
    end,
    'whatsapp', case
      when count(distinct r.whatsapp) filter (where r.whatsapp is not null) = 1
      then min(r.whatsapp) filter (where r.whatsapp is not null)
      else null
    end
  )) as j,
  max(r.sincronizado_em) as sincronizado_em
  from registros_ativos r
),
stats as (
  select
    count(*)::integer as ingressos_total,
    count(distinct i.categoria)::integer as categorias_total,
    min(i.categoria) as categoria_unica
  from ingressos_ativos i
)
select case
  when p_pessoa_id is null then
    jsonb_build_object('ok', false, 'motivo', 'sem_pessoa')
  else
    jsonb_build_object(
      'ok', true,
      'pessoa_id', p_pessoa_id,
      'evento_codigo', 'mind-summit-2026',
      'participante', (select j from cadastro),
      'tem_ingresso_ativo', (select ingressos_total > 0 from stats),
      'categoria_unica', (
        select case when categorias_total = 1 then categoria_unica else null end from stats
      ),
      'categorias', coalesce((
        select jsonb_agg(c.categoria order by c.categoria) from categorias c
      ), '[]'::jsonb),
      'ingressos', coalesce((
        select jsonb_agg(
          jsonb_build_object('categoria', c.categoria, 'quantidade', c.quantidade)
          order by c.categoria
        )
        from categorias c
      ), '[]'::jsonb),
      'meta', jsonb_build_object(
        'fonte', 'credenciamento_oficial',
        'sincronizado_em', (select sincronizado_em from cadastro),
        'dados_comprador_omitidos', true
      )
    )
end
$function$;

REVOKE ALL ON FUNCTION public.mind_identificador_validar(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mind_identificador_validar(text, text) TO postgres, service_role;
REVOKE ALL ON FUNCTION public.mind_identificador_declarado_registrar(uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mind_identificador_declarado_registrar(uuid, text, text) TO postgres, service_role;
REVOKE ALL ON FUNCTION public.mind_credenciamento_fatos(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mind_credenciamento_fatos(uuid) TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.mind_agent_context(p_conversa_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
with
conversa as (
  select c.id, c.participante_id, c.canal, c.origem_codigo, c.produto_codigo, c.variables
    from engagement.conversas c
   where c.id = p_conversa_id
),
pessoa as (
  select cv.participante_id as pessoa_id from conversa cv where cv.participante_id is not null
),

-- Cada coletor uma vez.
coletores as (
  select p.pessoa_id,
         public.mind_pessoa_fatos(p.pessoa_id)     as person,
         public.mind_crm_fatos(p.pessoa_id)        as crm,
         public.mind_crm_comercial(p.pessoa_id)       as commercial,
         public.mind_credenciamento_fatos(p.pessoa_id) as credenciamento,
         public.mind_engagement_fatos(p.pessoa_id)     as engajamento
    from pessoa p
),

-- ENTRY. So fato da entrada atual. `variables` nunca sai cru: dele se extrai apenas a CTA.
-- A normalizacao das duas formas possiveis (array de {key,value} vindo do session.close,
-- objeto quando o agente escreve) e a mesma ja provada em analise_montar_contexto.
vars as (
  select case
           when jsonb_typeof(cv.variables) = 'array' then (
             select coalesce(jsonb_object_agg(v->>'key', v->>'value')
                      filter (where nullif(v->>'key','') is not null
                                and nullif(v->>'value','') is not null),
                    '{}'::jsonb)
               from jsonb_array_elements(cv.variables) v)
           when jsonb_typeof(cv.variables) = 'object' then cv.variables
           else '{}'::jsonb
         end as j
    from conversa cv
),
entrada as (
  select jsonb_build_object(
           'canal',          cv.canal,
           'origem_codigo',  cv.origem_codigo,
           'origem',         (select jsonb_build_object(
                                       'site',         o.site,
                                       'botao_rotulo', o.botao_rotulo,
                                       'descricao',    o.descricao)
                                from engagement.origens o
                               where o.codigo = cv.origem_codigo),
           'produto_codigo', cv.produto_codigo,
           'entry_action',   nullif(btrim(coalesce(
                               (select j->>'hubspot_opcao_selecionada_treble' from vars),
                               (select j->>'opcao_selecionada'                from vars),
                               '')), '')
         ) as j
    from conversa cv
),

-- A conversa atual sai de dentro do proprio coletor, na linguagem dele. As demais mantem
-- a ordem deterministica do coletor (iniciada_em, id) — WITH ORDINALITY preserva o array.
conversas_do_coletor as (
  select c.valor, c.ord
    from coletores k,
         lateral jsonb_array_elements(k.engajamento->'conversas') with ordinality c(valor, ord)
),
atual as (
  select c.valor as j from conversas_do_coletor c
   where (c.valor->>'conversa_id')::uuid = p_conversa_id
   limit 1
),
anteriores as (
  select coalesce(jsonb_agg(c.valor order by c.ord), '[]'::jsonb) as j
    from conversas_do_coletor c
   where (c.valor->>'conversa_id')::uuid is distinct from p_conversa_id
)

select case
  when p_conversa_id is null then
    jsonb_build_object('ok', false, 'motivo', 'sem_conversa')
  when not exists (select 1 from conversa) then
    jsonb_build_object('ok', false, 'motivo', 'conversa_nao_encontrada', 'conversa_id', p_conversa_id)
  when not exists (select 1 from pessoa) then
    jsonb_build_object('ok', false, 'motivo', 'conversa_sem_pessoa', 'conversa_id', p_conversa_id)
  else
    jsonb_build_object(
      'ok',           true,
      'pessoa_id',    (select pessoa_id from coletores),
      'conversa_id',  p_conversa_id,
      'person',       (select person     from coletores),
      'crm',          (select crm        from coletores),
      'commercial',      (select commercial      from coletores),
      'credenciamento',   (select credenciamento  from coletores),
      'entry',        (select j from entrada),
      'conversation', (select j from atual),
      -- historico factual pessoa-wide inteiro, nao contador: as outras conversas vem
      -- completas, com suas mensagens. Engagement factual nao e Memory.
      'engagement',   jsonb_build_object(
                        'resumo',               (select engajamento->'resumo' from coletores),
                        'conversas_anteriores', (select j from anteriores),
                        'meta',                 (select engajamento->'meta'   from coletores)))
end
$function$
;

CREATE OR REPLACE FUNCTION public.mind_conversa_estado(p_conversa_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
  select jsonb_build_object(
    'historico', coalesce((
      select jsonb_agg(jsonb_build_object('papel', m.papel, 'conteudo', m.conteudo)
                       order by m.criado_em)
      from (select papel, conteudo, criado_em from engagement.mensagens
             where conversa_id = p_conversa_id order by criado_em desc limit 12) m), '[]'::jsonb),
    'turnos_do_agente', (select count(*) from engagement.mensagens
                          where conversa_id = p_conversa_id and papel = 'agente'),
    'credenciamento', (select public.mind_credenciamento_fatos(c.participante_id)
                         from engagement.conversas c where c.id = p_conversa_id),
    'perfil', (select jsonb_strip_nulls(jsonb_build_object(
                 'pessoa_id', p.id, 'primeiro_nome', p.primeiro_nome, 'sobrenome', p.sobrenome,
                 'email', p.email, 'whatsapp', p.whatsapp, 'empresa', p.empresa, 'cargo', p.cargo))
               from engagement.conversas c join pessoas.pessoas p on p.id = c.participante_id
              where c.id = p_conversa_id));
$function$
;

CREATE OR REPLACE FUNCTION public.mindagent_chat_get_context(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'summit', 'comum', 'mind', 'engagement', 'intelligence', 'concierge'
AS $function$
declare
  v_session engagement.agent_sessions%rowtype;
  v_conversation engagement.conversas%rowtype;
  v_history jsonb := '[]'::jsonb;
  v_interests jsonb := '[]'::jsonb;
  v_memories jsonb := '[]'::jsonb;
  v_profile jsonb := null;
  v_credenciamento jsonb := null;
  v_rota_ativa text := null;
begin
  select * into v_session from engagement.agent_sessions
  where id=p_session_id and auth_user_id=p_auth_user_id and token_hash=p_token_hash and expira_em>now();
  if not found then raise exception using errcode='28000', message='invalid_chat_session'; end if;

  select * into v_conversation from engagement.conversas
  where id=p_conversation_id and dispositivo_id=v_session.dispositivo_id and encerrada_em is null;
  if not found then raise exception using errcode='28000', message='invalid_chat_conversation'; end if;

  update engagement.agent_sessions set ultima_atividade=now() where id=v_session.id;
  update engagement.dispositivos set ultimo_acesso=now() where id=v_session.dispositivo_id;
  update engagement.conversas set ultima_atividade=now() where id=v_conversation.id;

  select coalesce(jsonb_agg(jsonb_build_object('role',case h.papel when 'lead' then 'user' else 'assistant' end,
                                               'content',h.conteudo) order by h.criado_em),'[]'::jsonb)
    into v_history
  from (select papel,conteudo,criado_em from engagement.mensagens
        where conversa_id=v_conversation.id and papel in ('lead','agente') and conteudo is not null
        order by criado_em desc limit 12) h;

  select coalesce(jsonb_agg(jsonb_build_object('key',i.chave,'label',i.rotulo,'confidence',i.confianca,
                                               'occurrences',i.ocorrencias) order by i.ultima_em desc),'[]'::jsonb)
    into v_interests
  from engagement.session_interests i where i.agent_session_id=v_session.id;

  if v_session.participante_id is not null then
    v_credenciamento := public.mind_credenciamento_fatos(v_session.participante_id);

    select jsonb_build_object('participant_id',p.id,'name',p.nome,'role',p.cargo,'company',p.empresa,
                              'language',p.idioma,'interests',coalesce(pc.temas_relevantes,'[]'::jsonb))
      into v_profile
    from engagement.v_pessoa p
    left join intelligence.participante_contexto pc on pc.participante_id=p.id
    where p.id=v_session.participante_id;

    select coalesce(jsonb_agg(jsonb_build_object('type',pm.tipo,'key',pm.chave,
      'value',coalesce(pm.valor->>'text',pm.valor->>'label'),'scope',pm.valor->>'scope','confidence',pm.confianca)
      order by pm.confianca desc nulls last,pm.atualizado_em desc nulls last),'[]'::jsonb)
      into v_memories
    from intelligence.participante_memoria pm
    where pm.participante_id=v_session.participante_id and pm.tipo='interesse' and pm.status='ativa'
      and (pm.valido_ate is null or pm.valido_ate>now())
      and coalesce(pm.valor->>'text',pm.valor->>'label') is not null;
  end if;

  if jsonb_typeof(v_conversation.variables)='object' then
    v_rota_ativa:=nullif(btrim(coalesce(v_conversation.variables->>'rota_ativa','')),'');
  end if;

  return jsonb_build_object('identity_verified',false,'identity_source',v_session.origem_identidade,
    'identity_confidence',v_session.confianca,'participant_profile',v_profile,
    'credenciamento',v_credenciamento,'history',v_history,
    'interests',v_interests,'memories',v_memories,'origem_codigo',v_conversation.origem_codigo,
    'rota_ativa',v_rota_ativa,'expires_at',v_session.expira_em);
end
$function$
;

REVOKE ALL ON FUNCTION public.mind_agent_context(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mind_agent_context(uuid) TO postgres, service_role;
REVOKE ALL ON FUNCTION public.mind_conversa_estado(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mind_conversa_estado(uuid) TO postgres, service_role;
REVOKE ALL ON FUNCTION public.mindagent_chat_get_context(uuid, uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mindagent_chat_get_context(uuid, uuid, uuid, text) TO postgres, service_role;
