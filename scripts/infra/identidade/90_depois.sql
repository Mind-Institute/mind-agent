-- 90 — fotografia depois da passada e verificações. Só leitura. Compare com o 00.
select jsonb_pretty(jsonb_build_object(
  'quando', now(),
  'pessoas', (select count(*) from pessoas.pessoas),
  'pessoas_ativas', (select count(*) from pessoas.pessoas where fundida_em is null),
  'pessoas_fundidas', (select count(*) from pessoas.pessoas where fundida_em is not null),
  'pessoas_por_enriquecer', (select count(*) from pessoas.pessoas where enriquecida_em is null and fundida_em is null),
  'identidades_por_canal', (select jsonb_object_agg(canal, n) from (select canal, count(*) n from engagement.identidades group by 1) s),
  'propostas_pendentes_por_padrao', (select coalesce(jsonb_object_agg(coalesce(padrao, '(sem padrao)'), n), '{}'::jsonb) from (select padrao, count(*) n from engagement.identidade_fusoes where status = 'pendente' group by 1) s),
  'sem_pessoa_por_fonte', jsonb_build_object(
    'hubspot_contato_espelho',      (select count(*) from crm.contato_espelho where mind_id is null),
    'eduzz_vendas',                 (select count(*) from eduzz.vendas where mind_id is null),
    'blinket_ingressos',            (select count(*) from eduzz.ingressos where mind_id is null),
    'treble_conversas',             (select count(*) from engagement.conversas where mind_id is null),
    'credenciamento_participantes', (select count(*) from credenciamento_summit_2026.participantes where mind_id is null),
    'yazo_espelho',                 (select count(*) from credenciamento_summit_2026.yazo_espelho where mind_id is null),
    'leads_capturados',             (select count(*) from crm.leads_capturados where mind_id is null),
    'checkout_pedidos',             (select count(*) from checkout.pedidos where mind_id is null)),
  'motivos_sem_pessoa_hubspot', (select coalesce(jsonb_object_agg(mind_id_criterio, n), '{}'::jsonb) from (select mind_id_criterio, count(*) n from crm.contato_espelho where mind_id is null group by 1) s),
  -- verificações: têm de ser zero
  'identidade_apontando_para_pessoa_fundida', (select count(*) from engagement.identidades i join pessoas.pessoas p on p.id = i.mind_id where p.fundida_em is not null),
  'emails_em_duas_pessoas_ativas', (select count(*) from (select lower(email) e from pessoas.pessoas where email is not null and fundida_em is null group by 1 having count(*) > 1) d),
  'linhas_de_fonte_apontando_para_pessoa_fundida', (select count(*) from crm.contato_espelho c join pessoas.pessoas p on p.id = c.mind_id where p.fundida_em is not null)
    + (select count(*) from credenciamento_summit_2026.participantes c join pessoas.pessoas p on p.id = c.mind_id where p.fundida_em is not null),
  -- o credenciado típico, com os quatro ids na mesma linha
  'credenciados_com_hubspot_e_credenciamento_na_mesma_pessoa', (select count(*) from pessoas.v_pessoa_360 v where v.credenciamento_ids is not null and v.hubspot_ids is not null and v.fundida_em is null)
)) as depois;
