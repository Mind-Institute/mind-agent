-- 00 — fotografia antes da passada D5. Só leitura. Guarde o resultado: o 90 compara com ele.
-- Exige a migration D5 aplicada (as colunas pessoa_id das fontes nascem nela).
select jsonb_pretty(jsonb_build_object(
  'quando', now(),
  'pessoas', (select count(*) from pessoas.pessoas),
  'pessoas_fundidas', (select count(*) from pessoas.pessoas where fundida_em is not null),
  'pessoas_por_enriquecer', (select count(*) from pessoas.pessoas where enriquecida_em is null and fundida_em is null),
  'identidades_por_canal', (select jsonb_object_agg(canal, n) from (select canal, count(*) n from engagement.identidades group by 1) s),
  'pendencias_por_tipo_status', (select jsonb_object_agg(tipo || ' / ' || status, n) from (select tipo, status, count(*) n from engagement.identidade_fusoes group by 1, 2) s),
  'propostas_pendentes_por_padrao', (select coalesce(jsonb_object_agg(coalesce(padrao, '(sem padrao)'), n), '{}'::jsonb) from (select padrao, count(*) n from engagement.identidade_fusoes where status = 'pendente' group by 1) s),
  'sem_pessoa_por_fonte', jsonb_build_object(
    'hubspot_contato_espelho',      (select count(*) from crm.contato_espelho where pessoa_id is null),
    'eduzz_vendas',                 (select count(*) from eduzz.vendas where pessoa_id is null),
    'blinket_ingressos',            (select count(*) from eduzz.ingressos where pessoa_id is null),
    'treble_conversas',             (select count(*) from engagement.conversas where participante_id is null),
    'credenciamento_participantes', (select count(*) from credenciamento_summit_2026.participantes where pessoa_id is null),
    'yazo_espelho',                 (select count(*) from credenciamento_summit_2026.yazo_espelho where pessoa_id is null),
    'leads_capturados',             (select count(*) from crm.leads_capturados where pessoa_id is null),
    'checkout_pedidos',             (select count(*) from checkout.pedidos where pessoa_id is null))
)) as antes;
