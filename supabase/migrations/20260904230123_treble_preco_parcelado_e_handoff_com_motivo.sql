-- Ajuste cirúrgico no decisioning compartilhado do vendedor.
--
-- Não reescreve os playbooks B2C ou B2B. O hash impede aplicar sobre uma versão
-- desconhecida; a âncora única limita a troca ao parágrafo HUMANO; a prova reversível
-- garante que todo o restante do prompt permaneça byte a byte igual.

do $migration$
declare
  v_antes text;
  v_depois text;
  v_versao integer;
  v_sha text;
  v_ancora constant text := E'HUMANO\nHandoff é capacidade, não fuga por falta de informação. Acione conforme o playbook quando houver pedido humano, exceção comercial, contrato/procurement, erro que o fluxo não resolve, risco sério ou negociação personalizada. Antes, responda o que puder e organize silenciosamente o contexto já disponível. Campo ausente nunca impede transferência.';
  v_bloco constant text := E'APRESENTAÇÃO DE PREÇO E PARCELAMENTO\nQuando uma oferta vigente tiver parcelamento, apresente primeiro o valor das parcelas e depois o valor total entre parênteses.\nFormato obrigatório: “O [categoria] está 12x R$[parcela] no lote vigente (R$[valor total]).”\nUse exclusivamente os valores recebidos do Kit. Preserve a precisão comercial do campo oficial e não recalcule parcelas. Não comece pelo valor total, não use “com parcelamento em” e não inverta a ordem.\n\nCONTINUIDADE ENTRE CATEGORIAS\nPedir para conhecer, comparar ou mudar o interesse entre Mind, VIP e Prime é continuação normal da venda B2C. Responda sobre a categoria pedida com os dados oficiais e mantenha needs_human=false. Perguntar preço, benefícios, disponibilidade, diferenças ou checkout também não é motivo de handoff.\n\nHUMANO\nHandoff é capacidade, não fuga por falta de informação. No vendedor, needs_human=true somente quando houver uma necessidade humana prevista pelo playbook e um handoff_reason válido. Antes, responda o que puder e organize silenciosamente o contexto já disponível. Campo ausente nunca impede transferência.\n\nUse exatamente um destes motivos quando o caso se aplicar:\n- pedido_humano: a pessoa pediu explicitamente atendimento humano\n- erro_pagamento: existe erro ou divergência de pagamento\n- reclamacao_seria: existe reclamação séria\n- condicao_fora_regra: pediram exceção ou condição não autorizada\n- contrato_faturamento_procurement: o caso exige proposta, contrato, nota fiscal, faturamento ou procurement\n- negociacao_personalizada: a negociação exige desenho comercial personalizado\n- duvida_factual_bloqueante: falta um fato que realmente impede a decisão e não pode ser resolvido com o Kit ou as ferramentas\n- b2b_5_9_alta_intencao: delegação de 5 a 9 pessoas dentro do critério do playbook B2B\n- volume_10_mais: delegação de 10 ou mais pessoas\n\nSe nenhum desses motivos existir, use needs_human=false e handoff_reason=null. Nunca acione handoff porque a pessoa mudou de VIP para Prime, pediu informações sobre outra categoria, quis comparar ingressos, perguntou preço, benefícios, disponibilidade ou checkout.';
begin
  select conteudo, versao, encode(digest(conteudo, 'sha256'), 'hex')
    into v_antes, v_versao, v_sha
  from agentes.prompts
  where chave = 'decisioning_vendas_universal'
  for update;

  if v_antes is null then
    raise exception 'decisioning_vendas_universal ausente';
  end if;
  if v_versao <> 2
     or v_sha <> '7668a62d9f01bb98fff3ce06af7d738a5bbfec6b055d13958de8fbebd84a7860' then
    raise exception 'prompt mudou: versao %, sha %', v_versao, v_sha;
  end if;
  if (length(v_antes) - length(replace(v_antes, v_ancora, ''))) / length(v_ancora) <> 1 then
    raise exception 'ancora HUMANO nao e unica';
  end if;

  v_depois := replace(v_antes, v_ancora, v_bloco);
  if replace(v_depois, v_bloco, v_ancora) is distinct from v_antes then
    raise exception 'alteracao nao e reversivel ao texto original';
  end if;

  update agentes.prompts
  set conteudo = v_depois,
      versao = 3,
      atualizado_em = now()
  where chave = 'decisioning_vendas_universal';

  if (select encode(digest(conteudo, 'sha256'), 'hex')
      from agentes.prompts where chave = 'playbook_summit_b2c')
      <> '36e1af97da88f76f5752d24483f6914e4a7a8da96349ab2a543b11030c26269e' then
    raise exception 'playbook B2C foi alterado';
  end if;
  if (select encode(digest(conteudo, 'sha256'), 'hex')
      from agentes.prompts where chave = 'playbook_summit_b2b')
      <> 'ebee9425c9b87fd46334ca57212a189a94451965affbff87fd4bf379abf4c6a1' then
    raise exception 'playbook B2B foi alterado';
  end if;
  if position('Formato obrigatório: “O [categoria] está 12x R$[parcela] no lote vigente (R$[valor total]).”'
      in public.treble_agent_prompt('summit_b2c')) = 0 then
    raise exception 'regra de preco nao entrou no prompt B2C composto';
  end if;
  if position('Nunca acione handoff porque a pessoa mudou de VIP para Prime'
      in public.treble_agent_prompt('summit_b2c')) = 0 then
    raise exception 'regra de continuidade nao entrou no prompt B2C composto';
  end if;
end
$migration$;
