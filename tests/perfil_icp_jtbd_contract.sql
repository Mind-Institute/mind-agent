-- Contrato dos catálogos de ICP/JTBD (intelligence.icp, intelligence.jtbd) e do perfil por regra
-- (intelligence.perfil_projetar, escritor analise_projetar_memoria, leitor mind_customer_intelligence,
-- plano mind_hubspot_perfil_plano). Sempre termina em rollback: a exceção PERFIL_OK é o resultado.
-- Rodar depois das migrations 20260923081119 … 20260923150946 (revisão de 23/09: pesos por sala, reserva fraca,
-- veto por ICP típico, regra de cargo ampliada, ICP manual do HubSpot só quando não é do Mind; escritor não pisa na
-- regra; relacionamento com o Mind — quem não é lead não tem ICP nem JTBD).
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
  -- revisão 23/09: RH com nível antes de saúde, siglas/abreviações, executivos públicos, "executive" que não é executivo
  if intelligence.icp_por_cargo('Gerente Médica Saúde Corporativa') <> 'gestor_rh' then raise exception 'cargo 16 (gerente de saúde corporativa compra para a empresa)'; end if;
  if intelligence.icp_por_cargo('Coord de RH') <> 'gestor_rh' then raise exception 'cargo 17 (coord abreviado)'; end if;
  if intelligence.icp_por_cargo('Human Resource Analyst') <> 'analista_bp_rh' then raise exception 'cargo 18'; end if;
  if intelligence.icp_por_cargo('Especialista de C&B') <> 'analista_bp_rh' then raise exception 'cargo 19 (C&B é RH)'; end if;
  if intelligence.icp_por_cargo('Executive Assistant') <> 'analista_nao_rh' then raise exception 'cargo 20 (executive assistant não é executivo)'; end if;
  if intelligence.icp_por_cargo('Secretária de Estado') <> 'ceo_csuite' then raise exception 'cargo 21 (executivo público)'; end if;
  if intelligence.icp_por_cargo('Chairmam') <> 'ceo_csuite' then raise exception 'cargo 22 (typo de chairman)'; end if;
  if intelligence.icp_por_cargo('Product Owner') <> 'analista_nao_rh' then raise exception 'cargo 23 (owner de produto não é dono)'; end if;
  if intelligence.icp_por_cargo('Educadora respiratória') <> 'psicologo_saude' then raise exception 'cargo 24'; end if;
  if intelligence.icp_por_cargo('Dona de casa') <> 'outros' then raise exception 'cargo 25'; end if;
  if intelligence.icp_por_cargo('Supte RH') <> 'chro_vp_diretor_rh' then raise exception 'cargo 26 (superintendente abreviado)'; end if;

  -- normalização de texto livre
  if intelligence.texto_chave('Vale S.A.', true) <> intelligence.texto_chave('VALE SA', true) then raise exception 'chave de empresa'; end if;
  if intelligence.texto_chave('Grupo Boticário', true) <> intelligence.texto_chave('O Boticario', true) then raise exception 'chave de empresa 2'; end if;
  if intelligence.texto_exibir('gerente de rh') <> 'Gerente de RH' then raise exception 'exibir 1: %', intelligence.texto_exibir('gerente de rh'); end if;
  if intelligence.texto_exibir('Sócia-fundadora') <> 'Sócia-fundadora' then raise exception 'exibir 2 (caixa mista intacta)'; end if;
  if intelligence.texto_exibir('gerente Rh') <> 'Gerente RH' then raise exception 'exibir 3 (sigla e inicial em caixa mista): %', intelligence.texto_exibir('gerente Rh'); end if;
  if intelligence.texto_exibir('Ceo') <> 'CEO' then raise exception 'exibir 4: %', intelligence.texto_exibir('Ceo'); end if;

  -- cenário: pessoa com check-in numa workshop de NR-1, cargo e JT08 vindos de conversa
  insert into pessoas.pessoas (id, primeiro_nome, sobrenome, origem) values (v_p, 'Contrato', 'Perfil', 'bot');
  -- a sessão de NR-1 com menos check-ins (sala pequena: check-in vale 0,70 e faz job ativo)
  select se.id into v_sessao from summit_2026.sessions se where 'nr1_mensuracao' = any(se.jtbd)
   order by (select count(distinct c.mind_id) from credenciamento_summit_2026."Check Ins Summit" c where c.sessao_id = se.id), se.inicio limit 1;
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

  -- reserva sozinha (mesmo em sessão pequena) é intenção fraca: vira hipótese, nunca job ativo
  select se.id into v_sessao from summit_2026.sessions se where 'encontrar_pares' = any(se.jtbd) and not ('nr1_mensuracao' = any(se.jtbd))
   order by (select count(distinct c.mind_id) from credenciamento_summit_2026."Check Ins Summit" c where c.sessao_id = se.id), se.inicio limit 1;
  insert into credenciamento_summit_2026."Reservas_Agenda_APP" ("Nome", "Email", mind_id, sessao_id, criada_em)
  values ('Contrato Perfil', 'contrato.perfil@example.invalid', v_p, v_sessao, now());
  r := intelligence.perfil_projetar(v_p, true);
  if not exists (select 1 from intelligence.participante_memoria where mind_id = v_p and chave = 'jtbd:encontrar_pares' and status = 'proposta' and origem = 'regra_perfil') then
    raise exception 'reserva sozinha devia virar hipótese (proposta) de encontrar_pares'; end if;
  -- e quando a evidência some, a regra rebaixa o que ela mesma promoveu
  delete from credenciamento_summit_2026."Check Ins Summit" where mind_id = v_p;
  r := intelligence.perfil_projetar(v_p, true);
  if exists (select 1 from intelligence.participante_memoria where mind_id = v_p and chave = 'jtbd:nr1_mensuracao' and status = 'ativa' and origem = 'regra_perfil') then
    raise exception 'nr1_mensuracao devia ter sido rebaixada sem o check-in'; end if;
  if (r->>'memorias_rebaixadas')::int < 1 then raise exception 'esperava memorias_rebaixadas >= 1, veio %', r->>'memorias_rebaixadas'; end if;
  -- só toca o que muda: rodar de novo não carimba atualizado_em
  r := intelligence.perfil_projetar(v_p, true);
  if (r->>'memorias_alteradas')::int <> 0 or (r->>'memorias_novas')::int <> 0 or (r->>'memorias_rebaixadas')::int <> 0 then
    raise exception 'segunda rodada devia ser sem mudanças: %', r; end if;
  -- de volta ao cenário com check-in para o resto do contrato
  insert into credenciamento_summit_2026."Check Ins Summit" ("Nome", "Email", mind_id, sessao_id, checkin_em)
  select 'Contrato Perfil', 'contrato.perfil@example.invalid', v_p, se.id, now() from summit_2026.sessions se where 'nr1_mensuracao' = any(se.jtbd)
   order by (select count(distinct c.mind_id) from credenciamento_summit_2026."Check Ins Summit" c where c.sessao_id = se.id), se.inicio limit 1;
  r := intelligence.perfil_projetar(v_p, true);
  if not exists (select 1 from intelligence.participante_memoria where mind_id = v_p and chave = 'jtbd:nr1_mensuracao' and status = 'ativa' and origem = 'regra_perfil') then
    raise exception 'nr1_mensuracao devia voltar a ativa com o check-in'; end if;

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
  if not exists (select 1 from jsonb_array_elements(v_ci->'jobs_observed') j where j->>'code' = 'nr1_mensuracao' and j->>'source' = 'rule' and j->>'evidence' like '%checkin%') then
    raise exception 'leitor: jobs_observed sem source/evidence: %', v_ci->'jobs_observed'; end if;
  if jsonb_array_length(v_ci->'jobs_observed') > 5 then raise exception 'leitor: mais de 5 jobs'; end if;

  -- escritor: traduz rótulo legado e aceita job mind; a conversa não pisa na linha da regra (encontrar_pares já era hipótese da regra)
  n := public.analise_projetar_memoria(v_p, 'analise_vendas_summit',
        '[{"category":"icp","value":"CHRO / VP de Pessoas","confidence":"high","scope":"stable"},
          {"category":"jtbd","code":"encontrar_pares","value":"x","confidence":"high","scope":"stable"}]'::jsonb);
  if not exists (select 1 from intelligence.participante_memoria where mind_id = v_p and chave = 'jtbd:encontrar_pares' and origem = 'analise_vendas_summit' and status = 'ativa') then raise exception 'escritor não aceitou job mind'; end if;
  if not exists (select 1 from intelligence.participante_memoria where mind_id = v_p and chave = 'jtbd:encontrar_pares' and origem = 'regra_perfil' and status = 'proposta') then raise exception 'linha da regra devia continuar como hipótese ao lado da conversa'; end if;
  if not exists (select 1 from intelligence.participante_memoria where mind_id = v_p and chave = 'icp_atual' and status = 'ativa' and valor->>'text' = 'CHRO / VP / Diretor(a) de RH ou Pessoas') then raise exception 'escritor não traduziu o rótulo legado'; end if;
  -- e a regra, rodando de novo, não promove a própria linha por cima da conversa ativa
  r := intelligence.perfil_projetar(v_p, true);
  if (select count(*) from intelligence.participante_memoria where mind_id = v_p and chave = 'jtbd:encontrar_pares' and status = 'ativa') <> 1 then raise exception 'encontrar_pares com mais de uma ativa'; end if;

  -- caso A (FOUND sobrescrito em 095020, corrigido em 20260923143941): a regra tem o job ATIVO e a conversa confirma o
  -- mesmo job com alta confiança → a conversa grava a própria linha ativa e a da regra cede (proposta)
  n := public.analise_projetar_memoria(v_p, 'analise_vendas_summit',
        '[{"category":"jtbd","code":"nr1_mensuracao","value":"x","confidence":"high","scope":"stable"}]'::jsonb);
  if not exists (select 1 from intelligence.participante_memoria where mind_id = v_p and chave = 'jtbd:nr1_mensuracao' and origem = 'analise_vendas_summit' and status = 'ativa') then
    raise exception 'caso A: a conversa devia gravar nr1_mensuracao ativa mesmo com a regra ativa'; end if;
  if not exists (select 1 from intelligence.participante_memoria where mind_id = v_p and chave = 'jtbd:nr1_mensuracao' and origem = 'regra_perfil' and status = 'proposta') then
    raise exception 'caso A: a linha da regra devia ceder (proposta)'; end if;
  r := intelligence.perfil_projetar(v_p, true);
  if (select count(*) from intelligence.participante_memoria where mind_id = v_p and chave = 'jtbd:nr1_mensuracao' and status = 'ativa') <> 1 then
    raise exception 'caso A: nr1_mensuracao devia ter exatamente uma ativa'; end if;

  -- plano do HubSpot lista a pessoa com icp e o job
  if not exists (select 1 from public.mind_hubspot_perfil_plano() p where p.mind_id = v_p and p.icp = 'CHRO / VP de Pessoas' and 'Cumprir a NR-1 e gerir riscos psicossociais com dados' = any(p.jtbd)) then
    raise exception 'plano do HubSpot sem a pessoa ou com valores errados'; end if;

  -- relacionamento com o Mind (Adriana, 23/09): quem não é lead não tem ICP nem JTBD
  if not pessoas.e_lead(v_p) then raise exception 'pessoa nova devia nascer lead'; end if;
  begin
    update pessoas.pessoas set relacionamento_mind = '{lead,staff}' where id = v_p;
    raise exception 'lead junto com outro tipo devia ser recusado';
  exception when check_violation then null; end;
  begin
    update pessoas.pessoas set relacionamento_mind = '{cliente}' where id = v_p;
    raise exception 'tipo fora da lista devia ser recusado';
  exception when check_violation then null; end;
  update pessoas.pessoas set relacionamento_mind = '{palestrante}' where id = v_p;
  if pessoas.e_lead(v_p) then raise exception 'palestrante não é lead'; end if;
  -- o atualizador só acrescenta: não tira a marca feita à mão
  r := pessoas.relacionamento_atualizar(true);
  if (select relacionamento_mind from pessoas.pessoas where id = v_p) <> '{palestrante}' then raise exception 'relacionamento_atualizar tirou uma marca'; end if;
  -- a regra apaga a própria classificação e rejeita a da conversa; cargo e empresa ficam
  r := intelligence.perfil_projetar(v_p, true);
  if coalesce((r->>'nao_e_lead')::boolean, false) is not true then raise exception 'perfil_projetar devia dizer nao_e_lead: %', r; end if;
  if (r->>'memorias_apagadas')::int < 1 or (r->>'memorias_rejeitadas')::int < 1 then raise exception 'esperava apagar a regra e rejeitar a conversa: %', r; end if;
  if exists (select 1 from intelligence.participante_memoria where mind_id = v_p and tipo in ('icp', 'jtbd') and status in ('ativa', 'proposta')) then
    raise exception 'não-lead ficou com ICP/JTBD ativo ou proposto'; end if;
  if exists (select 1 from intelligence.participante_memoria where mind_id = v_p and tipo in ('icp', 'jtbd') and origem = 'regra_perfil') then
    raise exception 'a regra devia apagar a própria classificação'; end if;
  if not exists (select 1 from intelligence.participante_memoria where mind_id = v_p and chave = 'cargo_atual' and status = 'ativa') then
    raise exception 'cargo é fato: não-lead mantém'; end if;
  r := intelligence.perfil_projetar(v_p, true);
  if (r->>'memorias_apagadas')::int <> 0 or (r->>'memorias_rejeitadas')::int <> 0 then raise exception 'limpeza devia ser idempotente: %', r; end if;
  -- o escritor da conversa ignora icp/jtbd de não-lead, mas grava o resto
  n := public.analise_projetar_memoria(v_p, 'analise_vendas_summit',
        '[{"category":"icp","value":"CHRO / VP de Pessoas","confidence":"high","scope":"stable"},
          {"category":"jtbd","code":"nr1_mensuracao","value":"x","confidence":"high","scope":"stable"},
          {"category":"interest","value":"Liderança humanizada","confidence":"high","scope":"stable"}]'::jsonb);
  if n <> 1 then raise exception 'escritor devia gravar só o interesse (1), gravou %', n; end if;
  if exists (select 1 from intelligence.participante_memoria where mind_id = v_p and tipo in ('icp', 'jtbd') and status in ('ativa', 'proposta')) then
    raise exception 'escritor gravou ICP/JTBD de não-lead'; end if;
  -- o leitor do Agent não devolve ICP nem jobs
  v_ci := public.mind_customer_intelligence(v_p);
  if v_ci->'professional_context' ? 'icp' or jsonb_array_length(v_ci->'jobs_observed') <> 0 then raise exception 'leitor devolveu perfil de não-lead: %', v_ci; end if;
  if v_ci->'professional_context'->>'role' is null then raise exception 'leitor devia manter o cargo do não-lead'; end if;
  -- o plano do HubSpot manda limpar (nao_lead) e entra no recorte horário porque a pessoa mudou
  if not exists (select 1 from public.mind_hubspot_perfil_plano() p where p.mind_id = v_p and p.nao_lead and p.icp is null and p.icp_confianca is null
                   and cardinality(p.jtbd) = 0 and p.resumo is null and p.fontes->'relacionamento' = '["palestrante"]'::jsonb) then
    raise exception 'plano do HubSpot devia trazer o não-lead limpo'; end if;
  if not exists (select 1 from public.mind_hubspot_perfil_plano(now() - interval '1 minute') p where p.mind_id = v_p and p.nao_lead) then
    raise exception 'não-lead recém-marcado devia entrar no recorte por data'; end if;
  -- e volta: marcado de novo como lead, a regra reclassifica pelo cargo
  update pessoas.pessoas set relacionamento_mind = '{lead}' where id = v_p;
  r := intelligence.perfil_projetar(v_p, true);
  if r->>'icp_acao' <> 'criada' then raise exception 'de volta a lead, a regra devia recriar o ICP: %', r; end if;

  -- parceiro de venda pelo domínio de e-mail (intelligence.config.parceiro_venda_dominios; 20260923150946) e a
  -- caixa genérica contato@joinmind.com.br fora da regra de staff
  insert into engagement.identidades (mind_id, canal, identificador, verificado, confianca)
  values (v_p, 'email', 'contrato.perfil@maisdiversidade.com.br', true, 1);
  if not exists (select 1 from pessoas.relacionamento_derivado() d where d.mind_id = v_p and d.tipo = 'parceiro_venda') then
    raise exception 'e-mail de domínio parceiro devia derivar parceiro_venda'; end if;
  r := pessoas.relacionamento_atualizar(true);
  if (select relacionamento_mind from pessoas.pessoas where id = v_p) <> '{parceiro_venda}' then
    raise exception 'relacionamento_atualizar devia marcar parceiro_venda e tirar lead: %', (select relacionamento_mind from pessoas.pessoas where id = v_p); end if;
  if exists (select 1 from pessoas.relacionamento_derivado() d
               join engagement.identidades i on i.mind_id = d.mind_id and i.canal = 'email' and i.identificador = 'contato@joinmind.com.br'
              where d.tipo = 'staff' and d.fonte like '%@joinmind.com.br%'
                and not exists (select 1 from engagement.identidades j where j.mind_id = d.mind_id and j.canal = 'email'
                                   and j.identificador like '%@joinmind.com.br' and j.identificador <> 'contato@joinmind.com.br')) then
    raise exception 'contato@joinmind.com.br (caixa genérica) não devia fazer de ninguém staff'; end if;

  raise exception 'PERFIL_OK: catálogos, regra de cargo (26 casos), projeção (pesos, reserva fraca, rebaixamento, idempotência), escritor (e caso A), leitor, plano, não-lead e parceiro por domínio conferem';
end $$;
rollback;
