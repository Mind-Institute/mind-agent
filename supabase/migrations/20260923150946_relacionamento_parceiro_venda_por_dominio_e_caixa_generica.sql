-- =====================================================================================
-- Parceiro de venda por domínio de e-mail e a caixa genérica do Mind fora da regra de staff
-- (Adriana, 23/09/2026: "parceiros de venda: por enquanto qualquer pessoa da Mais Diversidade pode marcar
-- como parceiro").
--
-- 1. intelligence.config.parceiro_venda_dominios (lista JSON de domínios): quem tem e-mail num desses domínios
--    — como identificador da pessoa (engagement.identidades) ou no contato do HubSpot ligado a ela
--    (crm.contato_espelho) — é parceiro de venda. Começa com maisdiversidade.com.br; acrescentar ou tirar um
--    parceiro é editar a lista, sem migration. Como relacionamento_atualizar só acrescenta, tirar um domínio
--    da lista não desfaz a marca de quem já foi marcado: corrige-se à mão na coluna.
-- 2. staff por e-mail @joinmind.com.br deixa de contar a caixa genérica contato@joinmind.com.br: a equipe
--    usa esse endereço para registrar convidados (ex.: ingresso do camarote de patrocinador), que não são
--    equipe.
-- =====================================================================================

insert into intelligence.config (chave, valor)
select 'parceiro_venda_dominios', '["maisdiversidade.com.br"]'
 where not exists (select 1 from intelligence.config where chave = 'parceiro_venda_dominios');

create or replace function pessoas.relacionamento_derivado()
returns table (mind_id uuid, tipo text, fonte text)
language sql stable security definer
set search_path to 'pg_catalog', 'public'
as $fn$
  with dominios_parceiro as (
    select lower(btrim(d)) as dominio
      from intelligence.config c, jsonb_array_elements_text(c.valor::jsonb) d
     where c.chave = 'parceiro_venda_dominios')
  select c.mind_id, 'staff'::text, 'credenciamento_summit_2026.controle_de_inscritos_e_presenca.staff_mind'::text
    from credenciamento_summit_2026.controle_de_inscritos_e_presenca c where c.staff_mind and c.mind_id is not null
  union
  select i.mind_id, 'staff', 'engagement.identidades: e-mail @joinmind.com.br'
    from engagement.identidades i
   where i.canal = 'email' and lower(i.identificador) like '%@joinmind.com.br'
     -- caixa genérica: a equipe registra convidados com ela; quem a tem não é equipe por isso
     and lower(i.identificador) <> all (array['contato@joinmind.com.br'])
  union
  select i.mind_id, 'staff', 'seguranca.equipe'
    from seguranca.equipe e join engagement.identidades i on i.canal = 'auth_user' and i.identificador = e.user_id::text
  union
  select i.mind_id, 'staff', 'public.mind_admin_users'
    from public.mind_admin_users u join engagement.identidades i on i.canal = 'auth_user' and i.identificador = u.user_id::text
   where u.active
  union
  select c.mind_id, 'palestrante', 'credenciamento_summit_2026.controle_de_inscritos_e_presenca.palestrante'
    from credenciamento_summit_2026.controle_de_inscritos_e_presenca c where c.palestrante and c.mind_id is not null
  union
  select pf.mind_id, 'palestrante', 'ecossistema.perfis_publicos → palestrantes_especialistas'
    from ecossistema.perfis_publicos pf where pf.mind_id is not null and pf.palestrante_especialista_id is not null
  union
  select pp.mind_id, 'professor', 'institute.programa_pessoas (' || coalesce(pp.papel, '?') || ')'
    from institute.programa_pessoas pp where pp.mind_id is not null
  union
  select i.mind_id, 'parceiro_venda', 'engagement.identidades: e-mail de parceiro (' || split_part(lower(i.identificador), '@', 2) || ')'
    from engagement.identidades i
   where i.canal = 'email' and split_part(lower(i.identificador), '@', 2) in (select dominio from dominios_parceiro)
  union
  select e.mind_id, 'parceiro_venda', 'crm.contato_espelho: e-mail de parceiro (' || split_part(lower(e.email), '@', 2) || ')'
    from crm.contato_espelho e
   where e.mind_id is not null and split_part(lower(e.email), '@', 2) in (select dominio from dominios_parceiro)
$fn$;
revoke execute on function pessoas.relacionamento_derivado() from public, anon, authenticated;
comment on function pessoas.relacionamento_derivado() is 'De onde vem cada tipo de relacionamento com o Mind (só vínculos por mind_id, nunca por nome): staff (credenciamento staff_mind, e-mail @joinmind.com.br exceto a caixa genérica contato@, seguranca.equipe, mind_admin_users), palestrante (credenciamento palestrante, ecossistema.perfis_publicos de palestrantes_especialistas), professor (institute.programa_pessoas), parceiro_venda (e-mail — identificador ou contato do HubSpot — num domínio de intelligence.config.parceiro_venda_dominios). Outros parceiros de venda se marcam à mão em pessoas.pessoas.relacionamento_mind.';
