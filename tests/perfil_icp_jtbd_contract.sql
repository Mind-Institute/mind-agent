-- Contrato dos catálogos de ICP/JTBD (intelligence.icp, intelligence.jtbd) e do perfil por regra
-- (intelligence.perfil_projetar, escritor analise_projetar_memoria, leitor mind_customer_intelligence,
-- plano mind_hubspot_perfil_plano). Sempre termina em rollback: a exceção PERFIL_OK é o resultado.
-- Rodar depois das migrations 20260923081119 … 20260923082744.
begin;
set local mind.d5_pular_trigger = '1';
do $$
declare v_p uuid := gen_random_uuid(); v_sessao uuid; r jsonb; n int; v_ci jsonb;
begin
  -- catálogos
  select count(*) into n from intelligence.icp where ativo; if n <> 14 then raise exception 'icp: esperava 14 perfis, achou %', n; end if;
  select count(*) into n from intelligence.jtbd where ativo and nivel = 'mind'; if n <> 13 then raise exception 'jtbd mind: esperava 13, achou %', n; end if;
  select count(*) into n from intelligence.jtbd where ativo and nivel = 'raiz'; if n <> 15 then raise exception 'jtbd raiz: esperava 15, achou %', n; end if;
  select count(*) into n from (select unnest(produtos) p from intelligence.jtbd) s where not exists (select 1 from catalogo.produtos c where c.codigo = s.p);
  if n > 0 then raise exception 'jtbd.produtos fora de catalogo.produtos: %', n; end if;
  select count(*) into n from (select unnest(icps_tipicos) p from intelligence.jtbd) s where not exists (select 1 from intelligence.icp i where i.codigo = s.p);
  if n > 0 then raise exception 'jtbd.icps_tipicos fora de intelligence.icp: %', n; end if;
  select count(*) into n from (select unnest(jt_raiz) p from intelligence.jtbd where nivel = 'mind') s where not exists (select 1 from intelligence.jtbd j where j.codigo = s.p and j.nivel = 'raiz');
  if n > 0 then raise exception 'jt_raiz desconhecido: %', n; end if;
  select count(*) into n from intelligence.icp where hubspot_opcao and hubspot_valor is null; if n > 0 then raise exception 'icp com hubspot_opcao sem hubspot_valor: %', n; end if;
  select count(*) into n from intelligence.jtbd where nivel = 'mind' and (not hubspot_opcao or hubspot_valor is null); if n > 0 then raise exception 'jtbd mind sem opção no HubSpot: %', n; end if;
  select count(*) into n from summit_2026.sessions where cardinality(jtbd) > 0; if n < 55 then raise exception 'sessões marcadas: % (esperava >= 55)', n; end if;

  -- regra de cargo
  if intelligence.icp_por_cargo('Gerente de RH') <> 'gestor_rh' then raise exception 'cargo 1'; end if;
  if intelligence.icp_por_cargo('CEO') <> 'ceo_csuite' then raise exception 'cargo 2'; end if;
  if intelligence.icp_por_cargo('CEO e Fundadora') <> 'fundador_socio' then raise exception 'cargo 3'; end if;
  if intelligence.icp_por_cargo('Psicóloga Organizacional') <> 'psicologo_saude' then raise exception 'cargo 4'; end if;
  if intelligence.icp_por_cargo('Senior People Business Partner') <> 'analista_bp_rh' then raise exception 'cargo 5'; end if;
  if intelligence.icp_por_cargo('Diretora de RH') <> 'chro_vp_diretor_rh' then raise exception 'cargo 6'; end if;
  if intelligence.icp_por_cargo('Consultora de RH') <> 'consultor_rh' then raise exception 'cargo 7'; end if;
  if intelligence.icp_por_cargo('Diretora de Marketing') <> 'diretor_vp_nao_rh' then raise exception 'cargo 8'; end if;
  if intelligence.icp_por_cargo('estudante') <> 'professor_pesquisador_estudante' then raise exception 'cargo 9'; end if;
  if intelligence.icp_por_cargo('Advogada') <> 'outros' then raise exception 'cargo 10'; end if;
  if intelligence.icp_por_cargo('Gerente de RH', 'Vittude') <> 'concorrente' then raise exception 'cargo 11 (concorrente pela empresa)'; end if;
  if intelligence.icp_por_cargo('Chief Happiness Officer') <> 'chro_vp_diretor_rh' then raise exception 'cargo 12'; end if;
  if intelligence.icp_por_cargo('coordenador de rh') <> 'gestor_rh' then raise exception 'cargo 13'; end if;
  if intelligence.icp_por_cargo('-') is not null then raise exception 'cargo 14 (vazio)'; end if;
  if intelligence.icp_por_cargo('Partner') <> 'fundador_socio' then raise exception 'cargo 15 (partner solto é sócio)'; end if;

  -- normalização de texto livre
  if intelligence.texto_chave('Vale S.A.', true) <> intelligence.texto_chave('VALE SA', true) then raise exception 'chave de empresa'; end if;
  if intelligence.texto_chave('Grupo Boticário', true) <> intelligence.texto_chave('O Boticario', true) then raise exception 'chave de empresa 2'; end if;
  if intelligence.texto_exibir('gerente de rh') <> 'Gerente de RH' then raise exception 'exibir 1: %', intelligence.texto_exibir('gerente de rh'); end if;
  if intelligence.texto_exibir('Sócia-fundadora') <> 'Sócia-fundadora' then raise exception 'exibir 2 (caixa mista intacta)'; end if;

  -- cenário: pessoa com check-in numa workshop de NR-1, cargo e JT08 vindos de conversa
  insert into pessoas.pessoas (id, primeiro_nome, sobrenome, origem) values (v_p, 'Contrato', 'Perfil', 'bot');
  select id into v_sessao from summit_2026.sessions where 'nr1_mensuracao' = any(jtbd) order by inicio limit 1;
  insert into credenciamento_summit_2026."Check Ins Summit" ("Nome", "Email", mind_id, sessao_id, checkin_em)
  values ('Contrato Perfil', 'contrato.perfil@example.invalid', v_p, v_sessao, now());
  insert into intelligence.participante_memoria (mind_id, tipo, chave, valor, confianca, origem, status)
  values (v_p, 'jtbd', 'jtbd:JT08', '{"code":"JT08","text":"Traduzir pessoas e bem-estar em business case, dados e influência"}', 0.90, 'analise_concierge', 'ativa'),
         (v_p, 'cargo', 'cargo_atual', '{"text":"Gerente de RH"}', 0.90, 'analise_concierge', 'ativa');

  r := intelligence.perfil_projetar(v_p, true);
  if r->>'icp' <> 'gestor_rh' then raise exception 'icp esperado gestor_rh, veio %', r->>'icp'; end if;
  if r->>'icp_acao' <> 'criada' then raise exception 'icp_acao esperada criada, veio %', r->>'icp_acao'; end if;
  if not exists (select 1 from intelligence.participante_memoria where mind_id = v_p and chave = 'jtbd:nr1_mensuracao' and status = 'ativa' and origem = 'regra_perfil') then
    raise exception 'faltou jtbd:nr1_mensuracao pelo check-in'; end if;
  if not exists (select 1 from intelligence.participante_memoria where mind_id = v_p and chave = 'jtbd:provar_retorno' and status = 'ativa' and origem = 'regra_perfil' and confianca = 0.90) then
    raise exception 'faltou jtbd:provar_retorno traduzido de JT08 com a confiança da conversa'; end if;
  if exists (select 1 from intelligence.participante_memoria where mind_id = v_p and chave = 'jtbd:treinar_liderancas') then
    raise exception 'treinar_liderancas sem evidência de liderança'; end if;

  -- idempotência: rodar de novo não duplica linha
  select count(*) into n from intelligence.participante_memoria where mind_id = v_p;
  r := intelligence.perfil_projetar(v_p, true);
  if (select count(*) from intelligence.participante_memoria where mind_id = v_p) <> n then raise exception 'perfil_projetar não é idempotente'; end if;

  -- memória de conversa vence: ICP ativo de conversa (rótulo legado) faz a regra virar proposta
  update intelligence.participante_memoria set status = 'substituida' where mind_id = v_p and chave = 'icp_atual';
  insert into intelligence.participante_memoria (mind_id, tipo, chave, valor, confianca, origem, status)
  values (v_p, 'icp', 'icp_atual', '{"text":"CEO / C-Suite"}', 0.90, 'analise_concierge', 'ativa');
  r := intelligence.perfil_projetar(v_p, true);
  if r->>'icp_acao' <> 'divergente_da_conversa' then raise exception 'esperava divergente_da_conversa, veio %', r->>'icp_acao'; end if;
  if (select count(*) from intelligence.participante_memoria where mind_id = v_p and chave = 'icp_atual' and status = 'ativa') <> 1 then raise exception 'mais de um icp ativo'; end if;

  -- leitor: rótulo canônico + code do catálogo; jobs mind aparecem
  v_ci := public.mind_customer_intelligence(v_p);
  if v_ci->'professional_context'->'icp'->>'code' <> 'ceo_csuite' then raise exception 'leitor icp: %', v_ci->'professional_context'->'icp'; end if;
  if not exists (select 1 from jsonb_array_elements(v_ci->'jobs_observed') j where j->>'code' = 'nr1_mensuracao') then raise exception 'leitor: jobs_observed sem nr1_mensuracao'; end if;

  -- escritor: traduz rótulo legado e aceita job mind
  n := public.analise_projetar_memoria(v_p, 'analise_vendas_summit',
        '[{"category":"icp","value":"CHRO / VP de Pessoas","confidence":"high","scope":"stable"},
          {"category":"jtbd","code":"encontrar_pares","value":"x","confidence":"high","scope":"stable"}]'::jsonb);
  if not exists (select 1 from intelligence.participante_memoria where mind_id = v_p and chave = 'jtbd:encontrar_pares' and origem = 'analise_vendas_summit') then raise exception 'escritor não aceitou job mind'; end if;
  if not exists (select 1 from intelligence.participante_memoria where mind_id = v_p and chave = 'icp_atual' and status = 'ativa' and valor->>'text' = 'CHRO / VP / Diretor(a) de RH ou Pessoas') then raise exception 'escritor não traduziu o rótulo legado'; end if;

  -- plano do HubSpot lista a pessoa com icp e o job
  if not exists (select 1 from public.mind_hubspot_perfil_plano() p where p.mind_id = v_p and p.icp = 'CHRO / VP de Pessoas' and 'Cumprir a NR-1 e gerir riscos psicossociais com dados' = any(p.jtbd)) then
    raise exception 'plano do HubSpot sem a pessoa ou com valores errados'; end if;

  raise exception 'PERFIL_OK: catálogos, regra de cargo, projeção, escritor, leitor e plano conferem';
end $$;
rollback;
