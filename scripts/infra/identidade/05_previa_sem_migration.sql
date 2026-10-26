-- 05 — prévia da fase A, só leitura, roda ANTES da migration D5.
-- Quanto o enriquecimento acrescentaria às pessoas já ligadas ao HubSpot, e quantas
-- duplicatas ele revelaria (identificador do contato que já pertence a outra pessoa).
with p_hs as (
  select i.pessoa_id, c.hubspot_id,
         nullif(lower(btrim(c.email)), '')                       as email,
         public.telefone_normalizar(c.phone)                     as tel1,
         public.telefone_normalizar(c.hs_whatsapp_phone_number)  as tel2,
         nullif(btrim(concat_ws(' ', c.firstname, c.lastname)), '') as nome
    from engagement.identidades i
    join crm.contato_espelho c on c.hubspot_id = i.identificador
   where i.canal = 'hubspot'
),
cand as (
  select pessoa_id, 'email' as canal, email as ident from p_hs where email is not null
  union select pessoa_id, 'whatsapp', tel1 from p_hs where tel1 is not null
  union select pessoa_id, 'whatsapp', tel2 from p_hs where tel2 is not null
),
novo as (
  select c.pessoa_id, c.canal, c.ident, i.pessoa_id as dona_atual
    from cand c
    left join engagement.identidades i on i.canal = c.canal and i.identificador = c.ident
   where i.pessoa_id is null or i.pessoa_id <> c.pessoa_id
),
dup as (
  select n.*,
         exists (select 1 from engagement.identidades a where a.pessoa_id = n.dona_atual and a.canal = 'auth_user') as dona_tem_login,
         exists (select 1 from engagement.identidades a where a.pessoa_id = n.dona_atual and a.canal = 'hubspot')   as dona_tem_hubspot
    from novo n where n.dona_atual is not null
)
select jsonb_pretty(jsonb_build_object(
  'pessoas_ligadas_ao_hubspot', (select count(distinct pessoa_id) from p_hs),
  'acrescentaria_por_canal', (select jsonb_object_agg(canal, n) from (select canal, count(*) n from novo where dona_atual is null group by 1) s),
  'pessoas_que_ganhariam_nome', (select count(distinct h.pessoa_id) from p_hs h join pessoas.pessoas p on p.id = h.pessoa_id where p.primeiro_nome is null and h.nome is not null),
  'duplicatas_reveladas', (select count(distinct (pessoa_id, dona_atual)) from dup),
  'duplicatas_por_padrao', (select jsonb_object_agg(padrao, n) from (
      select case when canal = 'email' and dona_tem_login then 'mesmo_email_hubspot_x_login'
                  when canal = 'email' and dona_tem_hubspot then 'mesmo_email_dois_hubspot'
                  when canal = 'email' then 'mesmo_email'
                  else 'mesmo_telefone_emails_diferentes' end as padrao, count(distinct (pessoa_id, dona_atual)) n
        from dup group by 1) s),
  'credenciamento', jsonb_build_object(
      'participantes_ativos_com_pessoa', (select count(*) from credenciamento_summit_2026.v_participantes where status = 'ativo' and pessoa_id is not null),
      'ids_de_credenciamento_a_acrescentar', (select count(*) from credenciamento_summit_2026.v_participantes v where v.status = 'ativo' and v.pessoa_id is not null
                                                and not exists (select 1 from engagement.identidades i where i.canal = 'credenciamento' and i.identificador = v.id::text)),
      'telefones_a_acrescentar', (select count(distinct v.telefone_norm) from credenciamento_summit_2026.v_participantes v where v.status = 'ativo' and v.pessoa_id is not null and v.telefone_norm is not null
                                                and not exists (select 1 from engagement.identidades i where i.canal = 'whatsapp' and i.identificador = v.telefone_norm)))
)) as previa_fase_a;
