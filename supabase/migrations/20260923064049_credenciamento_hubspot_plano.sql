-- Plano de escrita do credenciamento no HubSpot: uma linha por e-mail, com tudo que a
-- Edge `hubspot-credenciamento-writeback` precisa para decidir o que escrever em cada
-- contato. Pedido da Adriana em 23/09/2026 (D1: o banco alimenta o HubSpot).
--
-- Só leitura: esta função não escreve nada. Quem escreve é a Edge, e só com `executar`.
--
-- Regras que já moram aqui, para a Edge não as reinventar:
-- - uma pessoa = um e-mail (minúsculo, aparado). Várias linhas do mesmo e-mail viram
--   uma: categorias, origens, lotes e instituições acumulam; nome vem da linha ativa
--   mais recente.
-- - ingresso revogado não conta como participação. Quem só tem linha revogada entra
--   com `participante = false`.
-- - reembolso (Adriana, 23/09): revogado com motivo 'reembolsado', sem outro válido, e
--   a Eduzz — autoridade da transação — dizendo `status = 'Reembolsado'` na fatura.
--   Sem a Eduzz confirmar, `reembolso_nao_confirmado` acende e nada é marcado.
-- - inscrição por terceiro (D5): quando o comprador é outro e-mail, telefone e CPF da
--   linha são do comprador. Só saem telefone e CPF de linha própria (comprador =
--   participante), ativa, a mais recente.
-- - pagante: só quem tem linha ativa própria de origem 'Pago'. Cortesia e patrocínio
--   também têm "comprador" igual ao participante no credenciamento, e não pagaram.
-- - 'SEM MAPA' não é categoria; fica de fora de `categorias`.

create or replace function public.mind_credenciamento_hubspot_plano()
returns table (
  email                    text,
  primeiro_nome            text,
  sobrenome                text,
  telefone                 text,
  cpf                      text,
  categorias               text[],
  origens                  text[],
  lotes                    text[],
  instituicoes             text[],
  pagante                  boolean,
  participante             boolean,
  cortesia                 boolean,
  patrocinio               boolean,
  reembolsado              boolean,
  reembolso_nao_confirmado boolean,
  so_por_terceiro          boolean,
  linhas_ativas            integer,
  linhas_revogadas         integer
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with p as (
    select
      lower(btrim(x.email))       as em,
      x.primeiro_nome             as p_primeiro_nome,
      x.sobrenome                 as p_sobrenome,
      x.telefone_norm             as p_telefone_norm,
      x.cpf                       as p_cpf,
      x.ticket_type               as p_ticket_type,
      x.ticket_origin             as p_ticket_origin,
      x.batch                     as p_batch,
      x.sponsor_company           as p_sponsor_company,
      x.motivo_revogacao          as p_motivo,
      x.invoice_or_sale_number    as p_fatura,
      x.criado_em                 as p_criado_em,
      (x.status = 'ativo')        as p_ativo,
      (x.buyer_email is not null and btrim(x.buyer_email) <> ''
        and lower(btrim(x.buyer_email)) = lower(btrim(x.email))) as p_proprio
    from credenciamento_summit_2026.participantes x
    where x.email is not null and btrim(x.email) <> ''
  ),
  nome as (
    select distinct on (p.em) p.em, p.p_primeiro_nome, p.p_sobrenome
      from p
     order by p.em, p.p_ativo desc, p.p_criado_em desc nulls last
  ),
  contato as (
    select distinct on (p.em) p.em,
           case when p.p_telefone_norm ~ '^[0-9]{10,15}$' then '+' || p.p_telefone_norm end as c_telefone,
           case when regexp_replace(coalesce(p.p_cpf, ''), '[^0-9]', '', 'g') ~ '^[0-9]{11}$'
                then regexp_replace(p.p_cpf, '[^0-9]', '', 'g') end as c_cpf
      from p
     where p.p_ativo and p.p_proprio
     order by p.em, p.p_criado_em desc nulls last
  ),
  lotes_por_email as (
    select l.em, array_agg(l.p_batch order by l.p_criado_em desc nulls last) as l_lotes
      from (
        select distinct on (p.em, p.p_batch) p.em, p.p_batch, p.p_criado_em
          from p
         where p.p_ativo and p.p_batch is not null
         order by p.em, p.p_batch, p.p_criado_em desc nulls last
      ) l
     group by l.em
  ),
  reembolso as (
    select p.em,
           coalesce(bool_or(v.status = 'Reembolsado'), false)               as r_confirmado,
           coalesce(bool_or(v.status is distinct from 'Reembolsado'), false) as r_nao_confirmado
      from p
      left join eduzz.vendas v on v.fatura::text = p.p_fatura::text
     where not p.p_ativo and p.p_motivo = 'reembolsado'
     group by p.em
  ),
  agg as (
    select p.em,
      array_remove(array_agg(distinct p.p_ticket_type)
        filter (where p.p_ativo and p.p_ticket_type <> 'SEM MAPA'), null)            as a_categorias,
      array_remove(array_agg(distinct p.p_ticket_origin) filter (where p.p_ativo), null) as a_origens,
      array_remove(array_agg(distinct nullif(btrim(p.p_sponsor_company), ''))
        filter (where p.p_ativo), null)                                              as a_instituicoes,
      coalesce(bool_or(p.p_ativo and p.p_proprio and p.p_ticket_origin = 'Pago'), false) as a_pagante,
      coalesce(bool_or(p.p_ativo), false)                                            as a_participante,
      coalesce(bool_or(p.p_ativo and p.p_ticket_origin = 'Cortesia'), false)         as a_cortesia,
      coalesce(bool_or(p.p_ativo and p.p_ticket_origin = 'Patrocínio'), false)       as a_patrocinio,
      coalesce(bool_or(p.p_ativo and p.p_proprio), false)                            as a_alguma_propria,
      count(*) filter (where p.p_ativo)::int                                         as a_ativas,
      count(*) filter (where not p.p_ativo)::int                                     as a_revogadas
    from p
    group by p.em
  )
  select
    a.em,
    n.p_primeiro_nome,
    n.p_sobrenome,
    case when a.a_participante then c.c_telefone end,
    case when a.a_participante then c.c_cpf end,
    coalesce(a.a_categorias, '{}'::text[]),
    coalesce(a.a_origens, '{}'::text[]),
    coalesce(l.l_lotes, '{}'::text[]),
    coalesce(a.a_instituicoes, '{}'::text[]),
    a.a_pagante,
    a.a_participante,
    a.a_cortesia,
    a.a_patrocinio,
    (not a.a_participante and coalesce(r.r_confirmado, false)),
    (not a.a_participante and coalesce(r.r_nao_confirmado, false) and not coalesce(r.r_confirmado, false)),
    (a.a_participante and not a.a_alguma_propria),
    a.a_ativas,
    a.a_revogadas
  from agg a
  join nome n on n.em = a.em
  left join contato c on c.em = a.em
  left join lotes_por_email l on l.em = a.em
  left join reembolso r on r.em = a.em
  order by a.em;
$$;

revoke all on function public.mind_credenciamento_hubspot_plano() from public, anon, authenticated;
grant execute on function public.mind_credenciamento_hubspot_plano() to service_role;

comment on function public.mind_credenciamento_hubspot_plano() is
  'Plano de escrita do credenciamento Summit 2026 no HubSpot: uma linha por e-mail, com telefone/CPF só de linha própria (D5), pagante só com Pago próprio, e reembolso só confirmado pela Eduzz. Só leitura; quem escreve é a Edge hubspot-credenciamento-writeback. Só service_role.';
