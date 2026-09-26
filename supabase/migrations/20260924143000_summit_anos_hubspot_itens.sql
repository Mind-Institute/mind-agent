-- Passo 16 (Adriana, 24/09/2026): o que marcar em cada contato do HubSpot sobre o Summit — anos (2023–2025 pelos
-- ingressos; 2026 por quem esteve no credenciamento), categoria por ano (Mind/VIP/Prime/Camarote) e tipo de
-- entrada (Pago, Cortesia, Patrocínio, Bonus). Cortesia/Patrocínio só quando o lote diz. A edge function
-- hubspot-limpeza (op 'acrescentar') SOMA esses valores ao que já existe no HubSpot; nunca apaga.
create or replace function public.mind_summit_anos_hubspot_itens()
returns jsonb language sql stable security definer set search_path to 'public','pessoas','eduzz','engagement','crm','credenciamento_summit_2026'
set statement_timeout to '40s'
as $$
with presentes as (
  select distinct r.mind_id pid from credenciamento_summit_2026."Relatorio Yazzo Consolidado" r where r.mind_id is not null
  union select p.mind_id from credenciamento_summit_2026.participantes p where p.mind_id is not null and p.revogado_em is null),
t as (
  select i.mind_id pid, right(i.evento_titulo,4) ano, i.descricao d
    from eduzz.ingressos i
   where i.mind_id is not null and i.status not in ('Cancelado','Reembolsado','Reembolso Solicitado')
     and coalesce(i.descricao,'') !~* 'staff' and right(i.evento_titulo,4) in ('2023','2024','2025','2026')),
c as (
  select pid, ano,
    case when d ~* 'para\s+prime' then 'Prime' when d ~* 'para\s+vip' then 'VIP' when d ~* 'camarote' then 'Camarote'
         when d ~* 'prime' then 'Prime' when d ~* 'vip' then 'VIP' when d ~* '(mind|[úu]nico|business)' then 'Mind' end cat,
    case when d ~* '(cortesia|convidado|imprensa|palestrante|bandnews)' then 'Cortesia'
         when d ~* '(institute|combo|journey|clube canguru)' then 'Bonus | Ingresso incluido em oferta'
         when d ~* '(heineken|hnk|bwg|eduzz|vibra|chilli|literare|wellz|natura|vale|altis|beiersdorf|haleon|sextante|vip bp|fleury|maisdiversidade)' then 'Patrocínio'
         when d ~* '(ivana|thiago|marlucia|adriana vip|carla|andrew|juliana|leandro|souza|issao|bluma|profera|vidasimples|protagonistas|para[ií]so|universidade de pais|maternidade|mindself|sme|prime especial)' then 'Cortesia'
         when d ~* '(venda|compre 1|upgrade|business|experi|exp\.|[úu]nico|pr[ée]-venda|lote)' then 'Pago' end tipo
  from t where ano <> '2026' or pid in (select pid from presentes)
  union all select pid, '2026', null, null from presentes),
agg as (
  select pid,
    string_agg(distinct ano, ';') anos, string_agg(distinct cat, ';') cats,
    string_agg(distinct cat, ';') filter (where ano='2024') c24, string_agg(distinct cat, ';') filter (where ano='2025') c25, string_agg(distinct cat, ';') filter (where ano='2026') c26,
    string_agg(distinct tipo, ';') tipos,
    string_agg(distinct tipo, ';') filter (where ano='2023') t23, string_agg(distinct tipo, ';') filter (where ano='2024') t24,
    string_agg(distinct tipo, ';') filter (where ano='2025') t25, string_agg(distinct tipo, ';') filter (where ano='2026') t26,
    string_agg(distinct ano, ';') filter (where tipo='Cortesia') cort, string_agg(distinct ano, ';') filter (where tipo='Patrocínio') patr
  from c group by pid),
hs as (
  select pid, jsonb_agg(distinct id) ids from (
    select i.mind_id pid, i.identificador id from engagement.identidades i join agg on agg.pid=i.mind_id where i.canal='hubspot'
    union select e.mind_id, e.hubspot_id from crm.contato_espelho e join agg on agg.pid=e.mind_id
    union select p.id, p.hubspot_id from pessoas.pessoas p join agg on agg.pid=p.id where p.hubspot_id is not null) x
  group by pid)
select coalesce(jsonb_agg(jsonb_build_object('mind_id', a.pid, 'ids', hs.ids,
  'props', jsonb_strip_nulls(jsonb_build_object('summit__participacao_anual', anos, 'summit__categoria_do_ingresso', cats,
      'summit__categoria_2024', c24, 'summit__categoria_2025', c25, 'summit__categoria_2026', c26, 'tipo_de_entrada', tipos,
      'summit__tipo_entrada_2023', t23, 'summit__tipo_entrada_2024', t24, 'summit__tipo_entrada_2025', t25, 'summit__tipo_entrada_2026', t26,
      'summit__cortesia_anos', cort, 'summit__patrocinio_anos', patr)))), '[]')
from agg a join hs on hs.pid=a.pid
$$;
revoke all on function public.mind_summit_anos_hubspot_itens() from public, anon, authenticated;
