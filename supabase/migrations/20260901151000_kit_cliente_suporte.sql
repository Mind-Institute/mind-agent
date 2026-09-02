-- `cliente_suporte` passa a EXECUTAR. Antes o Gate abria e fechava na mesma frase.
--
-- O QUE ESTAVA QUEBRADO, medido: `mind_rota_capacidade('cliente_suporte','mindagent-web')`
-- devolvia `pode_executar: false, reason: 'missing_kit'`, e `mind_kit_meta('cliente_suporte')`
-- explicava por quê: `kit_configurado: false` — ZERO linhas em `agentes.kit_blocos` para
-- essa rota. Não faltava playbook: `playbook_cliente_suporte` está ativo desde sempre.
-- Faltava o Kit. Sem ele o Router podia escolher a rota e o turno morria no Gate.
--
-- POR QUE ISTO É A MENOR MUDANÇA. Não há runtime de suporte, não há tabela nova, não há
-- provider novo e não há fato duplicado. As três casas já existem, já estão em produção
-- servindo `concierge_summit` e `summit_b2c`, e são exatamente o que o playbook de suporte
-- manda usar — ele diz, com estas palavras, "responda com os dados oficiais (políticas,
-- local, acesso, programação)":
--
--   evento       onde é, que dias, que fuso            (mind_kit_evento)
--   programacao  que horas, em qual espaço, com quem   (mind_kit_programacao)
--   inclusoes    o que o ingresso dá direito           (mind_kit_inclusoes)
--
-- OS TRÊS SÃO OBRIGATÓRIOS de propósito. Atendimento sem dado oficial não é atendimento
-- degradado, é invenção: é a hora exata em que alguém responde "acho que abre às 8h" para
-- quem vai pegar um avião. Se um bloco cair, o Gate fecha e o handoff acende — que é o
-- comportamento certo. Os três providers foram verificados devolvendo payload não-nulo
-- com `(null, null)`, que é a checagem de disponibilidade que `mind_kit_meta` faz.
--
-- O QUE O SUPORTE CONTINUA NÃO FAZENDO. Ingresso que não aparece, erro de pagamento,
-- troca de titularidade e reembolso não estão aqui e não vão estar: nenhum dado desses
-- existe neste canal. Para isso vale a regra que já está escrita e injetada em toda
-- conversa — o playbook `base`: admitir que não sabe e oferecer a saída real do canal.
-- Nenhuma capacidade nova foi inventada para o App.

insert into agentes.kit_blocos (rota, secao, bloco, provider, obrigatorio, ativo) values
  ('cliente_suporte', 'structured', 'evento',      'public.mind_kit_evento',      true, true),
  ('cliente_suporte', 'structured', 'programacao', 'public.mind_kit_programacao', true, true),
  ('cliente_suporte', 'structured', 'inclusoes',   'public.mind_kit_inclusoes',   true, true)
on conflict (rota, bloco) do update
  set secao       = excluded.secao,
      provider    = excluded.provider,
      obrigatorio = excluded.obrigatorio,
      ativo       = excluded.ativo;

-- GUARDA. A migration só está correta se a rota REALMENTE virou executável nos dois
-- canais que a política habilita para ela. Falhar aqui é melhor que descobrir no turno.
do $$
declare v_web jsonb; v_wa jsonb;
begin
  v_web := public.mind_rota_capacidade('cliente_suporte', 'mindagent-web');
  v_wa  := public.mind_rota_capacidade('cliente_suporte', 'whatsapp');
  if (v_web->>'pode_executar')::boolean is not true then
    raise exception 'cliente_suporte continua sem executar no app: %', v_web;
  end if;
  if (v_wa->>'pode_executar')::boolean is not true then
    raise exception 'cliente_suporte continua sem executar no whatsapp: %', v_wa;
  end if;
end $$;
