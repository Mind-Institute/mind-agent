-- Base do relatório de valor para o patrocinador (Mind Summit 2026), pedido da Adriana em 24/09/2026:
-- "você tem que pegar os dados do Supabase para fazer o relatório para os patrocinadores".
-- Uma linha por PESSOA da audiência (palestrantes e staff fora), com presença por dia, ingresso,
-- patrocinador de origem do ingresso, senioridade/área (ICP da regra de 23/09 + cargo), empresa
-- (regra de 24/09) com setor/porte do espelho do HubSpot e o engajamento no app (Yazo).
-- Só leitura; não cria tabela.

create or replace function intelligence.senioridade_por_cargo(p_cargo text, p_icp text)
 returns text language sql immutable as $$
  select case
    when c ~ '\m(ceo|cfo|coo|cto|cmo|chro|cpo|cio|cso|chief|presidente|fundador|fundadora|founder|cofounder|co founder|socio|socia|owner|proprietari[oa]|empresari[oa])\M'
      or p_icp in ('ceo_csuite', 'fundador_socio') then 'C-level / Fundador(a) / Sócio(a)'
    when c ~ '\m(vp|vice presidente|vice president|diretor|diretora|director|superintendente)\M'
      or p_icp in ('chro_vp_diretor_rh', 'diretor_vp_nao_rh') then 'VP / Diretor(a)'
    when c ~ '\mhead\M' then 'Head'
    when c ~ '\m(gerente|manager|gestor|gestora|gerencia)\M' then 'Gerente'
    when c ~ '\m(coordenador|coordenadora|coordenacao|supervisor|supervisora|lider|leader|lead)\M'
      or p_icp in ('gestor_rh', 'gestor_nao_rh') then 'Coordenação / Liderança'
    when c ~ '\m(analista|especialista|specialist|assistente|auxiliar|business partner|bp|hrbp|tecnico|tecnica|estagiari[oa]|consultor interno)\M'
      or p_icp in ('analista_bp_rh', 'analista_nao_rh') then 'Analista / Especialista'
    when p_icp in ('consultor_coach', 'consultor_rh', 'psicologo_saude')
      or c ~ '\m(consultor|consultora|coach|mentor|mentora|psicolog[oa]|terapeuta|psicanalista|medic[oa])\M' then 'Profissional independente (consultor, coach, psicólogo)'
    when p_icp = 'professor_pesquisador_estudante' or c ~ '\m(professor|professora|pesquisador|pesquisadora|estudante|aluno|aluna)\M' then 'Academia / Estudante'
    when c is null then 'Não informado'
    else 'Outros'
  end
  from (select intelligence.texto_chave(p_cargo) c) x
$$;

create or replace function intelligence.area_por_cargo(p_cargo text, p_icp text)
 returns text language sql immutable as $$
  select case
    when p_icp in ('chro_vp_diretor_rh', 'gestor_rh', 'analista_bp_rh', 'consultor_rh')
      or c ~ '\m(rh|recursos humanos|pessoas|people|talent|talentos|gente|cultura|dho|treinamento|t d|business partner|hrbp|hr|remuneracao|beneficios|departamento pessoal|dp|endomarketing|clima|employee)\M' then 'RH / Pessoas'
    when c ~ '\m(saude|medic[oa]|psicolog[oa]|enfermeir[oa]|enfermagem|bem estar|wellness|wellbeing|ergonomia|nutricionista|fisioterapeuta|terapeuta|psicanalista|psiquiatra|seguranca do trabalho|sst)\M'
      or p_icp = 'psicologo_saude' then 'Saúde e bem-estar'
    when p_icp in ('ceo_csuite', 'fundador_socio') then 'Gestão geral / C-level'
    when c ~ '\m(marketing|mkt|comunicacao|brand|marca|conteudo|eventos|relacoes publicas|pr|social media)\M' then 'Marketing / Comunicação'
    when c ~ '\m(comercial|vendas|sales|negocios|key account|account|customer success|cs|atendimento|relacionamento|parcerias|expansao)\M' then 'Comercial / Vendas'
    when c ~ '\m(estrategia|strategy|planejamento|inovacao|transformacao|projetos|pmo|processos)\M' then 'Estratégia / Projetos'
    when p_icp = 'consultor_coach' or c ~ '\m(consultor|consultora|coach|mentor|mentora|facilitador|facilitadora)\M' then 'Consultoria / Coaching'
    when p_icp = 'professor_pesquisador_estudante' or c ~ '\m(professor|professora|pesquisador|pesquisadora|estudante|educador|educadora|pedagog[oa])\M' then 'Educação / Academia'
    when c ~ '\m(financeiro|financas|finance|contabil|controladoria|fiscal|tesouraria|juridico|advogad[oa]|compliance)\M' then 'Finanças / Jurídico'
    when c ~ '\m(tecnologia|ti|dados|data|software|desenvolvedor|engenheiro de software|produto|product|ux)\M' then 'Tecnologia / Produto'
    when c ~ '\m(operacoes|operacao|logistica|producao|industrial|manutencao|qualidade|engenharia|engenheir[oa]|supply|compras)\M' then 'Operações / Engenharia'
    when p_icp in ('gestor_nao_rh', 'diretor_vp_nao_rh', 'analista_nao_rh') then 'Outras áreas de negócio'
    when c is null then 'Não informado'
    else 'Outras áreas de negócio'
  end
  from (select intelligence.texto_chave(p_cargo) c) x
$$;

create or replace view intelligence.v_relatorio_patrocinador_audiencia as
with ctrl as (
  select public.mind_pessoa_canonica(c.mind_id) mind_id,
         bool_or(c.presenca_16_09 = 'sim') dia_16,
         bool_or(c.presenca_17_09 = 'sim') dia_17,
         (array_agg(c.categoria order by case c.categoria when 'Camarote' then 1 when 'Prime' then 2 when 'VIP' then 3 else 4 end))[1] ingresso,
         bool_or(c.palestrante) palestrante, bool_or(c.staff_mind) staff
    from credenciamento_summit_2026.controle_de_inscritos_e_presenca c
   where c.valido_no_mind = 'sim' and c.mind_id is not null
   group by 1),
yz as (
  select public.mind_pessoa_canonica(r.mind_id) mind_id,
         mode() within group (order by nullif(btrim(r."Empresa Patrocinadora, quando aplicável"), '')) patrocinador_ingresso,
         bool_or(nullif(btrim(r."Data/horário do primeiro acesso"), '') is not null) app_ativou,
         max(nullif(btrim(r."Data/horário do primeiro acesso"), '')) app_primeiro_acesso,
         max(nullif(btrim(r."Data/horário do último acesso"), '')) app_ultimo_acesso,
         sum(r."Postagens") postagens, sum(r."Curtidas") curtidas, sum(r."Comentários") comentarios,
         sum(r."Favoritos em agendas") favoritos_agenda, sum(r."Favoritos em palestrantes") favoritos_palestrantes,
         sum(r."Mensagens trocadas") mensagens, sum(r."Trocas de contato") trocas_contato
    from credenciamento_summit_2026."Relatorio Yazzo Consolidado" r
   where r.mind_id is not null group by 1),
icp as (
  select distinct on (public.mind_pessoa_canonica(m.mind_id)) public.mind_pessoa_canonica(m.mind_id) mind_id,
         coalesce(m.valor->>'code', i.codigo) icp
    from intelligence.participante_memoria m
    left join intelligence.icp i on (m.valor->>'code') is null
         and (m.valor->>'text') in (i.rotulo, i.hubspot_valor, i.rotulo_legado)
   where m.tipo = 'icp' and m.chave = 'icp_atual' and m.status = 'ativa'
   order by public.mind_pessoa_canonica(m.mind_id), m.atualizado_em desc),
emp as (select * from crm.empresa_participantes_summit_2026()),
res as (
  select public.mind_pessoa_canonica(r.mind_id) mind_id, count(*) reservas,
         count(*) filter (where r."Fila de espera"::text = 'Sim') fila_espera
    from credenciamento_summit_2026."Reservas_Agenda_APP" r where r.mind_id is not null group by 1),
chk as (
  select public.mind_pessoa_canonica(k.mind_id) mind_id, count(distinct k.sessao_id) sessoes_checkin
    from credenciamento_summit_2026."Check Ins Summit" k where k.mind_id is not null group by 1)
select c.mind_id,
       c.dia_16, c.dia_17, (c.dia_16 or c.dia_17) presente, (c.dia_16 and c.dia_17) dois_dias,
       c.ingresso,
       yz.patrocinador_ingresso,
       p.cargo,
       icp.icp,
       intelligence.senioridade_por_cargo(p.cargo, icp.icp) senioridade,
       intelligence.area_por_cargo(p.cargo, icp.icp) area,
       p.empresa,
       emp.hubspot_company_id,
       emp.fonte empresa_fonte,
       e.industry setor_hubspot,
       e.numberofemployees funcionarios,
       case when e.numberofemployees is null then null
            when e.numberofemployees <= 100 then '1. até 100'
            when e.numberofemployees <= 500 then '2. 101–500'
            when e.numberofemployees <= 1000 then '3. 501–1.000'
            when e.numberofemployees <= 5000 then '4. 1.001–5.000'
            when e.numberofemployees <= 10000 then '5. 5.001–10.000'
            else '6. +10.000' end porte,
       e.country pais_empresa, e.city cidade_empresa, e.state uf_empresa,
       coalesce(yz.app_ativou, false) app_ativou, yz.app_primeiro_acesso, yz.app_ultimo_acesso,
       yz.postagens, yz.curtidas, yz.comentarios, yz.favoritos_agenda, yz.favoritos_palestrantes,
       yz.mensagens, yz.trocas_contato,
       coalesce(res.reservas, 0) reservas, coalesce(res.fila_espera, 0) fila_espera,
       coalesce(chk.sessoes_checkin, 0) sessoes_checkin
  from ctrl c
  join pessoas.pessoas p on p.id = c.mind_id
  left join yz on yz.mind_id = c.mind_id
  left join icp on icp.mind_id = c.mind_id
  left join emp on emp.mind_id = c.mind_id
  left join crm.empresa_espelho e on e.hubspot_company_id = emp.hubspot_company_id
  left join res on res.mind_id = c.mind_id
  left join chk on chk.mind_id = c.mind_id
 where not coalesce(c.palestrante, false) and not coalesce(c.staff, false);

comment on view intelligence.v_relatorio_patrocinador_audiencia is
  'Audiência do Mind Summit 2026 para o relatório de patrocinadores: 1 linha por pessoa (sem palestrantes e staff), presença por dia, ingresso, patrocinador de origem, senioridade/área, empresa (HubSpot: setor, porte) e engajamento no app. Filtrar presente = true para números de audiência.';

revoke all on intelligence.v_relatorio_patrocinador_audiencia from public, anon, authenticated;
