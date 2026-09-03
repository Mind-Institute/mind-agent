-- Contrato do vendedor B2B Summit v8.
-- Leitura apenas; não cria fixture nem altera dados.

do $test$
declare
  v_b2b text;
  v_b2c text;
  v_bloco jsonb;
  v_kit jsonb;
  v_status jsonb;
  v_conversa uuid;
  v_regras text[];
  v_vendavel boolean;
begin
  select public.treble_agent_prompt('summit_b2b','completo') into v_b2b;
  select public.treble_agent_prompt('summit_b2c','completo') into v_b2c;
  select public.mind_kit_delegacao_corporativa(null::uuid,'{}'::jsonb) into v_bloco;
  select public.mind_b2b_produto_status() into v_status;

  if position('MODO CORPORATIVO — SUMMIT B2B' in coalesce(v_b2b,'')) = 0 then
    raise exception 'playbook B2B ausente';
  end if;
  if position('https://calculadora.mindsummit.company/' in coalesce(v_b2b,'')) = 0 then
    raise exception 'calculadora ausente do playbook';
  end if;
  if position('https://pdf.mindsummit.company/' in coalesce(v_b2b,'')) = 0 then
    raise exception 'material de aprovação ausente';
  end if;
  if position('10 ou mais' in coalesce(v_b2b,'')) = 0 then
    raise exception 'regra de handoff por volume ausente';
  end if;
  if position('nome e sobrenome' in coalesce(v_b2b,'')) = 0
     or position('empresa' in coalesce(v_b2b,'')) = 0
     or position('cargo' in coalesce(v_b2b,'')) = 0
     or position('e-mail' in coalesce(v_b2b,'')) = 0 then
    raise exception 'campos progressivos ausentes';
  end if;
  if position('Classifique quem chegou:' in coalesce(v_b2b,'')) > 0 then
    raise exception 'playbook_router ainda montado no B2B';
  end if;
  if position('SALES DECISION ENGINE' in coalesce(v_b2b,'')) > 0
     or position('PLAYBOOK DE OBJEÇÕES — MIND SUMMIT' in coalesce(v_b2b,'')) > 0
     or position('PRODUCT DECISIONING ENTRE SOLUÇÕES MIND' in coalesce(v_b2b,'')) > 0 then
    raise exception 'módulo genérico ainda montado no B2B';
  end if;
  if length(v_b2b) >= 35000 then
    raise exception 'prompt B2B continua excessivo: % caracteres', length(v_b2b);
  end if;

  if position('SALES DECISION ENGINE' in coalesce(v_b2c,'')) = 0
     or position('PRODUCT DECISIONING ENTRE SOLUÇÕES MIND' in coalesce(v_b2c,'')) = 0 then
    raise exception 'B2C alterado antes da auditoria própria';
  end if;
  if position('CALCULADORA CORPORATIVA' in coalesce(v_b2c,'')) > 0 then
    raise exception 'playbook B2B vazou para B2C';
  end if;

  if v_bloco->'estrutura'->>'nucleo_comum_horas' <> '10' then
    raise exception 'núcleo comum diferente de 10 horas';
  end if;
  if v_bloco->'estrutura'->>'aprofundamento_por_papel_horas' <> '6' then
    raise exception 'aprofundamento diferente de 6 horas';
  end if;
  if v_bloco->'recursos'->'calculadora'->>'url' <> 'https://calculadora.mindsummit.company/' then
    raise exception 'URL da calculadora incorreta';
  end if;
  if v_bloco->'recursos'->'material_aprovacao'->>'url' <> 'https://pdf.mindsummit.company/' then
    raise exception 'URL do PDF incorreta';
  end if;
  if v_bloco->'composicao'->>'proporcao_referencia' <> '1 gestor para 2 multiplicadores' then
    raise exception 'proporção de referência incorreta';
  end if;

  if v_status->>'produto_codigo' <> 'mind-summit-2026' then
    raise exception 'playbook B2B não aponta para o produto Summit 2026';
  end if;

  select id into v_conversa
  from engagement.conversas
  order by iniciada_em desc
  limit 1;
  if v_conversa is null then
    raise exception 'sem conversa disponível para testar o Kit';
  end if;

  v_kit := public.mind_agent_kit(
    'summit_b2b',
    v_conversa,
    jsonb_build_object('texto','Quero levar dez gestores')
  );

  if coalesce((v_kit->'meta'->>'kit_disponivel')::boolean,false) is not true then
    raise exception 'Kit B2B indisponível';
  end if;
  if not ((v_kit->'structured') ? 'delegacao_corporativa') then
    raise exception 'bloco delegacao_corporativa ausente do Kit';
  end if;
  if v_kit->'structured'->'product_intelligence'->'produto_da_rota'->>'produto_codigo'
       <> 'mind-summit-2026' then
    raise exception 'Product Intelligence não seguiu o produto do playbook';
  end if;

  v_vendavel := coalesce(
    (v_kit->'structured'->'product_intelligence'->'produto_da_rota'->>'vendavel_agora')::boolean,
    false
  );

  if jsonb_array_length(v_kit->'structured'->'product_intelligence'->'produtos')
       <> (case when v_vendavel then 1 else 0 end) then
    raise exception 'Product Intelligence entregou catálogo inteiro ou produto não vendável';
  end if;
  if v_vendavel
     and v_kit->'structured'->'product_intelligence'->'produtos'->0->>'codigo'
         <> 'mind-summit-2026' then
    raise exception 'B2B recebeu produto diferente do produto do playbook';
  end if;
  if not v_vendavel
     and (
       jsonb_array_length(v_kit->'structured'->'ofertas'->'ofertas') <> 0
       or jsonb_array_length(v_kit->'structured'->'precos_por_volume'->'precos_por_volume') <> 0
     ) then
    raise exception 'produto não vendável ainda aparece como oferta';
  end if;

  if (v_kit->'structured'->'evento') ? 'avisos_importantes' then
    raise exception 'avisos do Concierge vazaram para o Kit B2B';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(v_kit->'structured'->'inclusoes'->'experiencias') x
    where x ? 'ofertas_vigentes'
  ) then
    raise exception 'ofertas duplicadas dentro de inclusões';
  end if;

  select array_agg(x->>'chave' order by x->>'chave')
  into v_regras
  from jsonb_array_elements(v_kit->'structured'->'regras_comerciais'->'regras') x;
  if v_regras is distinct from
       array['desconto_por_volume','disponibilidade_ingressos']::text[] then
    raise exception 'regras B2B fora do escopo: %', v_regras;
  end if;

  if not exists (
    select 1
    from agentes.kit_blocos
    where rota='summit_b2b'
      and bloco='product_intelligence'
      and provider='public.mind_kit_product_intelligence_b2b'
      and ativo
      and obrigatorio
  ) then
    raise exception 'Product Intelligence específico não é obrigatório no B2B';
  end if;
end
$test$;
