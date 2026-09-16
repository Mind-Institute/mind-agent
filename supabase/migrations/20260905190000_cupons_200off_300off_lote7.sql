-- Cupons individuais do lote 7: 200OFF (Mind) e 300OFF (VIP; no Mind só como resgate).
--
-- Decisão da Adriana em 05/09/2026:
--   - AGORA10, AGORA20, AGORA30 e AGORA40 não valem mais e saem da regra;
--   - a condição individual passa a ser cupom de valor fixo DIGITADO no checkout
--     (não há link com cupom aplicado);
--   - "comprando até 23:59 de hoje" é copy de urgência, não validade cadastrada;
--   - Prime segue sem desconto individual.
--
-- Casa existente: `summit_2026.commercial_rules` (o Kit do vendedor lê `regras_comerciais`
-- inteiro) e `summit_2026.coupons` (registro). O guardrail de preço lê `desconto.valor`
-- como economia e `valor` + `condicoes_pagamento` como preço final e parcela do cupom.
-- Valor final = preço do lote 7 menos o cupom; parcela = valor final / 12, arredondado
-- como nas ofertas de lote ("12x de R$ 225" para R$ 2.697).
--
-- Idempotente: os UPDATEs fixam o estado final; os INSERTs só entram se o código não existir.

begin;

update summit_2026.commercial_rules
   set descricao = 'Condições individuais vigentes do Mind Summit 2026 (lote 7): cupons de valor fixo digitados no checkout. O playbook decide quando usar cada um; esta regra só informa o que existe, o valor final e a parcela.',
       config = $cfg$
{
  "lote": 7,
  "modo": "cupom_digitado_no_checkout",
  "prazo_copy": "comprando até 23:59 de hoje",
  "cupons": [
    {
      "cupom": "200OFF",
      "categoria": "mind",
      "oferta_codigo": "mind-lote-7",
      "desconto": {"tipo": "valor_fixo", "valor": 200, "categoria": "mind"},
      "valor": 1497,
      "condicoes_pagamento": "12x de R$ 125",
      "quando": "condição do Mind; pode entrar na abertura pela oferta e ao tratar barreira de preço"
    },
    {
      "cupom": "300OFF",
      "categoria": "vip",
      "oferta_codigo": "vip-lote-7",
      "desconto": {"tipo": "valor_fixo", "valor": 300, "categoria": "vip"},
      "valor": 2397,
      "condicoes_pagamento": "12x de R$ 200",
      "quando": "condição do VIP; pode entrar na abertura pela oferta e ao tratar barreira de preço"
    },
    {
      "cupom": "300OFF",
      "categoria": "mind",
      "oferta_codigo": "mind-lote-7",
      "desconto": {"tipo": "valor_fixo", "valor": 300, "categoria": "mind"},
      "valor": 1397,
      "condicoes_pagamento": "12x de R$ 116",
      "quando": "resgate: só depois de a pessoa insistir no preço após receber o 200OFF, e só depois de dizer que vai verificar se consegue aprovar uma condição melhor"
    }
  ],
  "prime": {"cupom": null, "disponivel": false, "nota": "Prime não tem desconto individual. Use disponibilidade e procura da Intelligence."},
  "uso": {
    "como_aplicar": "Envie o checkout_url oficial da oferta do lote 7 e peça para a pessoa digitar o cupom no campo de cupom do checkout. O link não aplica o cupom sozinho.",
    "como_falar": "Diga o cupom, o valor final e a parcela exatamente como estão aqui. Forma de referência: 'R$ 200 de desconto: fica R$ 1.497, 12x de R$ 125, digitando 200OFF no checkout'.",
    "nao_revelar_escada": "Nunca revele que existe condição maior que a oferecida nem que o 300OFF pode valer para o Mind. Uma recusa não autoriza o 300OFF no Mind: precisa de objeção de preço persistente com valor reconhecido.",
    "indisponivel": "Cupom que não está nesta lista não existe: nunca invente cupom, link, percentual ou exceção.",
    "prazo": "'Até 23:59 de hoje' é copy de urgência, não validade cadastrada: não afirme hora exata de expiração nem que o preço sobe amanhã."
  }
}
$cfg$::jsonb,
       atualizado_em = now()
 where chave = 'desconto_individual'
   and produto_codigo = 'mind-summit-2026';

update summit_2026.commercial_rules
   set config = $cfg$
{
  "permitido": "condicional",
  "regra": "Desconto NÃO pode ser oferecido indiscriminadamente. PODE ser oferecido por iniciativa do agente quando o playbook identificar necessidade comercial legítima (barreira real de preço ou orçamento) ou quando a pessoa chegou pedindo a oferta ou a condição especial, conforme o playbook.",
  "quem_escolhe_o_nivel": "O playbook. A Intelligence só informa as condições disponíveis (ver regra desconto_individual).",
  "nunca": "Revelar ao cliente que existe condição maior que a oferecida."
}
$cfg$::jsonb,
       atualizado_em = now()
 where chave = 'desconto_espontaneo'
   and produto_codigo = 'mind-summit-2026';

update summit_2026.commercial_rules
   set config = $cfg$
{
  "permitido": "condicional",
  "regra": "Não mencionar cupom de forma indiscriminada. Quando o playbook determinar uma condição de desconto, o agente informa o cupom, o valor final e a parcela da regra desconto_individual, envia o checkout_url oficial da oferta e pede para a pessoa digitar o cupom no campo de cupom do checkout.",
  "nunca": "Revelar ao cliente que existe condição maior que a oferecida."
}
$cfg$::jsonb,
       atualizado_em = now()
 where chave = 'mencionar_cupom_nao_solicitado'
   and produto_codigo = 'mind-summit-2026';

insert into summit_2026.coupons (event_id, codigo, descricao, tipo, valor, offer_codigo, ativo, condicoes)
select e.id, '200OFF', 'R$ 200 de desconto na Experiência Mind (lote 7). Digitado no campo de cupom do checkout.',
       'valor_fixo', 200, 'mind-lote-7', true,
       '{"aplicacao": "digitado_no_checkout", "categorias": ["mind"], "valor_final": 1497, "condicoes_pagamento": "12x de R$ 125"}'::jsonb
  from summit_2026.events e
 where e.ativo
   and not exists (select 1 from summit_2026.coupons c where c.codigo = '200OFF');

insert into summit_2026.coupons (event_id, codigo, descricao, tipo, valor, offer_codigo, ativo, condicoes)
select e.id, '300OFF', 'R$ 300 de desconto na Experiência VIP (lote 7); no Mind só como resgate após objeção de preço persistente. Digitado no campo de cupom do checkout.',
       'valor_fixo', 300, 'vip-lote-7', true,
       '{"aplicacao": "digitado_no_checkout", "categorias": ["vip", "mind"], "vip": {"valor_final": 2397, "condicoes_pagamento": "12x de R$ 200"}, "mind": {"valor_final": 1397, "condicoes_pagamento": "12x de R$ 116", "quando": "resgate"}}'::jsonb
  from summit_2026.events e
 where e.ativo
   and not exists (select 1 from summit_2026.coupons c where c.codigo = '300OFF');

do $$
declare v jsonb;
begin
  select config into v from summit_2026.commercial_rules
   where chave = 'desconto_individual' and produto_codigo = 'mind-summit-2026' and ativo;
  if v is null then raise exception 'desconto_individual ausente'; end if;
  if v ? 'niveis' or v::text ilike '%AGORA%' then raise exception 'escada AGORA ainda presente'; end if;
  if jsonb_array_length(v->'cupons') <> 3 then raise exception 'esperados 3 cupons, achados %', jsonb_array_length(v->'cupons'); end if;
  if (select count(*) from summit_2026.coupons where codigo in ('200OFF','300OFF') and ativo) <> 2 then
    raise exception 'cupons 200OFF/300OFF não registrados';
  end if;
end $$;

commit;
