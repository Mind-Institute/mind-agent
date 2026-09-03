-- Contrato do vendedor B2B Summit v7.
-- Leitura apenas; não cria fixture nem altera dados.

do $test$
declare
  v_b2b text;
  v_b2c text;
  v_bloco jsonb;
  v_kit jsonb;
  v_conversa uuid;
begin
  select public.treble_agent_prompt('summit_b2b','completo') into v_b2b;
  select public.treble_agent_prompt('summit_b2c','completo') into v_b2c;
  select public.mind_kit_delegacao_corporativa(null::uuid,'{}'::jsonb) into v_bloco;

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
  if position('Classifique quem chegou:' in coalesce(v_b2c,'')) > 0 then
    raise exception 'playbook_router ainda montado no B2C';
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

  select id into v_conversa
  from engagement.conversas
  order by iniciada_em desc
  limit 1;

  if v_conversa is null then
    raise exception 'sem conversa disponível para testar o Kit';
  end if;

  v_kit := public.mind_agent_kit('summit_b2b', v_conversa, '{}'::jsonb);
  if coalesce((v_kit->'meta'->>'kit_disponivel')::boolean, false) is not true then
    raise exception 'Kit B2B indisponível';
  end if;
  if not ((v_kit->'structured') ? 'delegacao_corporativa') then
    raise exception 'bloco delegacao_corporativa ausente do Kit';
  end if;
end
$test$;
