-- Aceite da Lusha mais estrito na busca por nome (a similaridade sozinha aceitava "Consultoria" → empresa de
-- saúde com 845 funcionários, "Café & Pão de Queijo" → fábrica de pão de queijo).
create or replace view crm.v_empresa_lusha_aceita as
with l as (
  select l.*,
         regexp_replace(lower(l.lusha_dominio), '^(https?://)?(www\.)?', '') ld,
         intelligence.texto_chave(l.lusha_nome, true) lk,
         intelligence.texto_chave(l.nome_busca, true) bk
    from crm.empresa_lusha l where l.lusha_id is not null)
select l.emp_id, l.nome_busca, l.dominio_busca, l.pessoas, l.lusha_id, l.lusha_nome, l.lusha_dominio,
       l.funcionarios, l.faixa_min, l.faixa_max, l.setor, l.cidade, l.uf, l.pais, l.aceito, l.motivo,
       l.consultado_em, l.criado_em,
       coalesce(l.funcionarios, l.faixa_max) funcionarios_usado
  from l
 where (l.dominio_busca is not null and nullif(l.ld, '') is not null
        and (l.ld = l.dominio_busca or l.dominio_busca like '%.' || l.ld or l.ld like '%.' || l.dominio_busca))
    or (l.pais = 'Brazil' and l.lk is not null and l.bk is not null
        and split_part(l.lk, ' ', 1) = split_part(l.bk, ' ', 1)
        and (l.lk = l.bk or (' ' || l.lk || ' ') like ('% ' || l.bk || ' %') or (' ' || l.bk || ' ') like ('% ' || l.lk || ' %'))
        and l.bk !~ '^(consultoria|psicologia|estrategia|people|rh|saude|coaching|treinamentos?|educacao|terapia|mentoria|instituto|grupo|empresa|clinica|escola|servicos)$');
comment on view crm.v_empresa_lusha_aceita is
  'Resultados da Lusha aceitos: domínio bateu; ou (busca por nome) sede no Brasil, mesma primeira palavra, um nome contém o outro, e o nome buscado não é genérico.';
revoke all on crm.v_empresa_lusha_aceita from public, anon, authenticated;
