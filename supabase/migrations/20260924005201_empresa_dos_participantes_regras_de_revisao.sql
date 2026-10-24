-- Empresa de cada participante do Summit 2026 (pedido da Adriana, 24/09/2026):
--   1. empresa declarada no credenciamento ("Relatorio Yazzo Consolidado") — vence as demais;
--   2. sem ela, o domínio do e-mail corporativo (company do HubSpot pelo domínio, ou a empresa em que
--      mais colegas do mesmo domínio caem pelo nome declarado);
--   3. sem ela, a company à qual o contato está associado no HubSpot (ou o campo company do contato);
--   4. o nome final é o da company no espelho do HubSpot (crm.empresa_espelho) quando ela existe —
--      mesma chave de nome, nome compatível com a company associada/do domínio, ou grafia quase igual;
--      nunca cria empresa (quem não está no HubSpot fica com o nome declarado, uma grafia por chave);
--   5. crm.empresa_participantes_summit_2026_gravar(true) grava em pessoas.pessoas.empresa e deixa
--      antes/depois em mind_admin_audit (resource 'pessoas_empresa_summit_2026').
create or replace function crm.empresa_participantes_summit_2026()
 returns table (
   mind_id uuid, email text, empresa_atual text,
   fonte text, candidato text,
   hubspot_company_id text, casamento text, empresa_final text)
 language sql
 stable
 security definer
 set search_path to 'pg_catalog', 'public', 'crm', 'intelligence', 'pessoas', 'credenciamento_summit_2026'
as $function$
with
co as (   -- companies do espelho, nome sem entidade HTML
  select e.hubspot_company_id id,
         btrim(regexp_replace(replace(replace(e.name, '&amp;', '&'), '&#39;', ''''), '\s*\[[^]]*\]\([^)]*\)', '', 'g')) nome,
         case when regexp_replace(lower(btrim(e.domain)), '^www\.', '') ~ '^[a-z0-9-]+(\.[a-z0-9-]+)+$'
               and regexp_replace(lower(btrim(e.domain)), '^www\.', '') !~ '^(com|net|org|edu|gov|co|ac|adv|ind|art|med|psi)(\.[a-z]{2})?$'
              then regexp_replace(lower(btrim(e.domain)), '^www\.', '') end dominio,
         coalesce(e.num_associated_contacts, 0) n
    from crm.empresa_espelho e where nullif(btrim(e.name), '') is not null),
co_k as materialized (select co.*, intelligence.texto_chave(co.nome, true) k from co),
por_chave as materialized (  -- uma company por grafia: a de mais contatos (evita escolher duplicata vazia)
  select distinct on (k) k, id, nome from co_k where k is not null order by k, n desc, id),
por_dom as (
  select distinct on (dominio) dominio, id, nome from co where dominio is not null order by dominio, n desc, id),
u as (
  select distinct public.mind_pessoa_canonica(x.mind_id) id from (
    select r.mind_id from credenciamento_summit_2026."Relatorio Yazzo Consolidado" r where r.mind_id is not null
    union select p.mind_id from credenciamento_summit_2026.participantes p where p.mind_id is not null and p.revogado_em is null) x),
y as (   -- 1. o que a pessoa declarou na Yazo (sem "n/a", "-", "nenhuma")
  select public.mind_pessoa_canonica(r.mind_id) id, mode() within group (order by btrim(r."Empresa")) emp
    from credenciamento_summit_2026."Relatorio Yazzo Consolidado" r
   where r.mind_id is not null and nullif(btrim(r."Empresa"), '') is not null
     and coalesce(intelligence.texto_chave(r."Empresa"), '') !~ '^(|n a|na|nao|n|nenhum|nenhuma|x+|0|sem empresa|nao tenho|nao se aplica|nd|nao possuo|nao informado)$'
   group by 1),
base as materialized (
  select u.id, p.email, p.empresa atual,
         lower(split_part(p.email, '@', 2)) dom, y.emp yazo,
         nullif(c.propriedades->>'associatedcompanyid', '') acid,
         nullif(btrim(c.company), '') hs_campo
    from u join pessoas.pessoas p on p.id = u.id
    left join y on y.id = u.id
    left join lateral (select * from crm.contato_espelho c
                        where c.hubspot_id::text = p.hubspot_id::text limit 1) c on true),
corp as (   -- 2. domínio corporativo (fora de webmail)
  select distinct dom from base
   where dom <> '' and dom !~ '^(gmail|googlemail|hotmail|outlook|live|msn|yahoo|ymail|icloud|me|mac|uol|bol|terra|ig|globo|globomail|aol|protonmail|proton|gmx|zipmail|r7|oi|email|mail)\.'),
dom_hs as (
  select distinct on (c.dom) c.dom, d.id, d.nome
    from corp c join por_dom d on c.dom = d.dominio or c.dom like '%.' || d.dominio
   order by c.dom, length(d.dominio) desc),
dom_consenso as (  -- a company do HubSpot em que mais colegas do mesmo domínio já caem pelo nome declarado
  select distinct on (b.dom) b.dom, k.id, k.nome
    from base b join corp using (dom)
    join por_chave k on k.k = intelligence.texto_chave(b.yazo, true)
   group by b.dom, k.id, k.nome
   order by b.dom, count(*) desc, k.id),
dom_yz as (  -- domínio sem company no HubSpot: a empresa que colegas do mesmo domínio declararam
  select b.dom, mode() within group (order by b.yazo) nome
    from base b join corp using (dom) where b.yazo is not null group by 1),
cand as materialized (
  select b.*,
         case when b.yazo is not null then '1_yazo'
              when dc.nome is not null or dh.nome is not null or dy.nome is not null then '2_email'
              when hc.nome is not null then '3_hubspot_associada'
              when b.hs_campo is not null then '3_hubspot_campo_company' end fonte,
         coalesce(b.yazo, dc.nome, dh.nome, dy.nome, hc.nome, b.hs_campo) candidato,
         intelligence.texto_chave(coalesce(b.yazo, dc.nome, dh.nome, dy.nome, hc.nome, b.hs_campo), true) ck,
         hc.id hc_id, hc.nome hc_nome, coalesce(dc.id, dh.id) dh_id, coalesce(dc.nome, dh.nome) dh_nome
    from base b
    left join dom_consenso dc on dc.dom = b.dom
    left join dom_hs dh on dh.dom = b.dom
    left join dom_yz dy on dy.dom = b.dom
    left join co hc on hc.id = b.acid),
casado as (
  select c.*, m.id m_id, m.nome m_nome, m.via
    from cand c
    left join lateral (
      select z.id, z.nome, z.via from (
        -- fonte já é a company do HubSpot (domínio ou associação)
        select c.dh_id id, c.dh_nome nome, 'dominio_hubspot' via, 0 o where c.fonte = '2_email' and c.candidato = c.dh_nome
        union all
        select c.hc_id, c.hc_nome, 'associada_hubspot', 0 where c.fonte = '3_hubspot_associada'
        union all  -- mesma grafia (sem acento, sufixo jurídico, artigo)
        select k.id, k.nome, 'mesmo_nome', 1 from por_chave k where k.k = c.ck
        union all  -- company associada ao contato ou do domínio, com nome compatível
        select v.id, v.nome, v.via, 2
          from (values (c.hc_id, c.hc_nome, 'associada_compativel'), (c.dh_id, c.dh_nome, 'dominio_compativel')) v(id, nome, via)
         where v.id is not null
           and (similarity(intelligence.texto_chave(v.nome, true), c.ck) >= 0.5
                or (' ' || intelligence.texto_chave(v.nome, true) || ' ') like ('% ' || c.ck || ' %')
                or (' ' || c.ck || ' ') like ('% ' || intelligence.texto_chave(v.nome, true) || ' %'))
        union all  -- typo: grafia quase igual
        (select k.id, k.nome, 'grafia_parecida', 3 from por_chave k
          where length(c.ck) >= 5 and k.k % c.ck and similarity(k.k, c.ck) >= 0.8
            and split_part(k.k, ' ', 1) = split_part(c.ck, ' ', 1)
          order by similarity(k.k, c.ck) desc limit 1)
      ) z where z.nome is not null order by z.o limit 1) m on true
   where c.candidato is not null),
exibir as (  -- empresa fora do HubSpot: uma grafia só por chave (a mais frequente), como no perfil de 23/09
  select c.ck, mode() within group (order by intelligence.texto_exibir(c.candidato)) nome
    from casado c where c.m_id is null group by c.ck)
select b.id, b.email, b.atual,
       c.fonte, c.candidato, c.m_id, coalesce(c.via, case when c.candidato is not null then 'fora_do_hubspot' end),
       coalesce(c.m_nome, e.nome, intelligence.texto_exibir(c.candidato))
  from base b
  left join casado c on c.id = b.id
  left join exibir e on e.ck = c.ck and c.m_id is null;
$function$;

comment on function crm.empresa_participantes_summit_2026() is
  'Empresa de cada participante do Summit 2026 (24/09, regra da Adriana): 1 Yazo declarada > 2 domínio de e-mail corporativo > 3 contato do HubSpot associado a uma company; o nome final é o da company no espelho do HubSpot quando ela existe (nunca cria empresa). Leitura; quem grava é crm.empresa_participantes_summit_2026_gravar.';

create or replace function crm.empresa_participantes_summit_2026_gravar(p_gravar boolean default false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public', 'crm', 'pessoas', 'intelligence'
as $function$
declare v_mudancas jsonb; v_n int; v_resumo jsonb; v_preservados jsonb;
begin
  create temp table emp_tmp on commit drop as select * from crm.empresa_participantes_summit_2026();

  -- O declarado (Yazo) vence o que houver. Fonte inferida (e-mail, HubSpot) preenche vazio e
  -- corrige grafia/nome compatível ou valor que era só o domínio do e-mail ("Grupodaycoval");
  -- empresa diferente que já existia fica e vai para `preservados` (revisão humana).
  alter table emp_tmp add column acao text;
  update emp_tmp t set acao = case
      when t.empresa_final is null then 'sem_empresa'
      when p.empresa is not distinct from t.empresa_final then 'igual'
      when t.fonte = '1_yazo' or nullif(btrim(p.empresa), '') is null then 'grava'
      when similarity(intelligence.texto_chave(p.empresa, true), intelligence.texto_chave(t.empresa_final, true)) >= 0.5
        or (' ' || intelligence.texto_chave(t.empresa_final, true) || ' ') like ('% ' || intelligence.texto_chave(p.empresa, true) || ' %')
        or (' ' || intelligence.texto_chave(p.empresa, true) || ' ') like ('% ' || intelligence.texto_chave(t.empresa_final, true) || ' %')
        or replace(intelligence.texto_chave(p.empresa), ' ', '') = split_part(split_part(lower(t.email), '@', 2), '.', 1)
        then 'grava'
      else 'preserva' end
    from pessoas.pessoas p where p.id = t.mind_id;

  select coalesce(jsonb_agg(jsonb_build_object('mind_id', t.mind_id, 'antes', p.empresa, 'depois', t.empresa_final,
                                               'fonte', t.fonte, 'casamento', t.casamento,
                                               'hubspot_company_id', t.hubspot_company_id) order by t.empresa_final)
                    filter (where t.acao = 'grava'), '[]'::jsonb),
         count(*) filter (where t.acao = 'grava'),
         coalesce(jsonb_agg(jsonb_build_object('mind_id', t.mind_id, 'email', t.email, 'atual', p.empresa, 'sugerida', t.empresa_final,
                                               'fonte', t.fonte, 'casamento', t.casamento))
                    filter (where t.acao = 'preserva'), '[]'::jsonb)
    into v_mudancas, v_n, v_preservados
    from emp_tmp t join pessoas.pessoas p on p.id = t.mind_id;

  select jsonb_build_object(
           'participantes', count(*),
           'com_empresa', count(*) filter (where empresa_final is not null),
           'sem_empresa', count(*) filter (where empresa_final is null),
           'por_fonte', (select jsonb_object_agg(coalesce(f, 'nenhuma'), n) from (select fonte f, count(*) n from emp_tmp group by 1) x),
           'por_casamento', (select jsonb_object_agg(coalesce(c, 'nenhum'), n) from (select casamento c, count(*) n from emp_tmp group by 1) x),
           'no_hubspot', count(*) filter (where hubspot_company_id is not null),
           'empresas_distintas', count(distinct empresa_final),
           'a_mudar', v_n, 'preservados', jsonb_array_length(v_preservados), 'gravou', p_gravar)
    into v_resumo from emp_tmp;

  if p_gravar and v_n > 0 then
    update pessoas.pessoas p set empresa = t.empresa_final, atualizado_em = now()
      from emp_tmp t
     where t.mind_id = p.id and t.acao = 'grava';

    insert into public.mind_admin_audit (action, resource, record_id, record_label, after_data, request_id)
    values ('atualizar', 'pessoas_empresa_summit_2026', to_char(now(), 'YYYYMMDDHH24MISS'),
            'Empresa dos participantes do Summit 2026 (Yazo > e-mail > HubSpot; nome da company do HubSpot)',
            jsonb_build_object('resumo', v_resumo, 'mudancas', v_mudancas, 'preservados', v_preservados), gen_random_uuid());
  end if;

  return v_resumo || jsonb_build_object('preservados_lista', v_preservados,
                                        'amostra', (select jsonb_agg(m) from (select m from jsonb_array_elements(v_mudancas) m limit 40) x));
end $function$;

comment on function crm.empresa_participantes_summit_2026_gravar(boolean) is
  'Grava em pessoas.pessoas.empresa o resultado de crm.empresa_participantes_summit_2026() (p_gravar = false é ensaio). Cada execução gravada deixa antes/depois em mind_admin_audit (resource pessoas_empresa_summit_2026) para desfazer.';

revoke all on function crm.empresa_participantes_summit_2026() from public, anon, authenticated;
revoke all on function crm.empresa_participantes_summit_2026_gravar(boolean) from public, anon, authenticated;
