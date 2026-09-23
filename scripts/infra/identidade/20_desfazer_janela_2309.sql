-- ============================================================================
-- 20 — desfazer o que os triggers da primeira migration D5 colaram em 23/09, 02:50 UTC
-- ============================================================================
-- Executado em produção às 03:55:54 UTC de 23/09/2026 (Claude, a pedido da Adriana:
-- "nada deve ficar comigo, execute"). Fica aqui como registro do que foi feito e
-- como modelo, caso um intervalo parecido precise ser desfeito um dia.
--
-- O que aconteceu: a migration 20260923024555 entrou às 02:47; às 02:50 o sync da
-- Eduzz/credenciamento (que apaga e regrava as quatro tabelas espelhadas a cada
-- 30 min) disparou os triggers novos. Com telefone (força 3) ganhando de e-mail
-- (força 2), cada linha casou pelo telefone do COMPRADOR e colou à pessoa dele o
-- e-mail, o CPF e os ids de quem estivesse na linha — os colegas inscritos por
-- terceiro. 13.205 identificadores nasceram naquele minuto; 1.045 pendências;
-- 2.159 pessoas ganharam colunas (864 e-mails, 477 WhatsApps, 2.083 nomes).
--
-- Como foi desfeito (uma transação):
--   1. tudo o que nasceu no minuto 02:50 em engagement.identidades foi apagado —
--      todos os 13.205 tinham fonte nas quatro tabelas espelhadas; nenhum era
--      tráfego vivo (conferido antes);
--   2. as 1.045 pendências do mesmo minuto foram apagadas (ainda pendentes; as
--      válidas renascem quando a regra nova rodar);
--   3. e-mail/WhatsApp copiados para pessoas.pessoas a partir desses
--      identificadores voltaram a nulo;
--   4. nomes voltaram a nulo SÓ quando (a) o nome atual é literalmente o de uma
--      linha cujos identificadores foram colados àquela pessoa e (b) não há apoio
--      anterior: login no app, contato do HubSpot com nome compatível ou nome de
--      perfil do WhatsApp compatível. Resultado: 337 zerados, 1.746 mantidos com
--      apoio, 76 pré-existentes mantidos.
--   As linhas das quatro tabelas não precisaram de nada: o sync das 03:20 já as
--   tinha regravado sem pessoa_id (triggers desligados entre 03:12 e 03:39).
--
-- Resultado conferido depois: identidades voltaram a 3.258 e-mails, 5.616
-- WhatsApps, 5.589 HubSpot (5.533 + 56 recuperados das colunas da pessoa), 4.017
-- logins; pendências voltaram a 1.605 (as anteriores a D5).
-- ============================================================================

begin;
select set_config('mind.d5_pular_trigger', '1', true);

create temp table d5_undo_ids as
  select id, pessoa_id, canal, identificador from engagement.identidades
   where criado_em >= '2026-09-23 02:50:00+00' and criado_em < '2026-09-23 02:51:00+00';

create temp table d5_undo_pessoas as
  select p.id, p.primeiro_nome, p.sobrenome, p.email, p.whatsapp,
    exists (select 1 from engagement.identidades i where i.pessoa_id = p.id and i.canal = 'auth_user') as tem_login,
    exists (select 1 from crm.contato_espelho c where c.pessoa_id = p.id and coalesce(c.firstname,'') <> ''
              and public.mind_nomes_compativeis(concat_ws(' ', c.firstname, c.lastname), concat_ws(' ', p.primeiro_nome, p.sobrenome))) as hubspot_apoia,
    exists (select 1 from engagement.conversas v where v.participante_id = p.id and coalesce(v.nome_contato,'') <> ''
              and public.mind_nomes_compativeis(v.nome_contato, concat_ws(' ', p.primeiro_nome, p.sobrenome))) as whatsapp_apoia,
    exists (select 1 from d5_undo_ids u
             where u.pessoa_id = p.id and (
               exists (select 1 from eduzz.ingressos r where lower(btrim(r.participante)) = lower(btrim(concat_ws(' ', p.primeiro_nome, p.sobrenome)))
                         and (lower(btrim(r.email)) = u.identificador or r.telefone_norm = u.identificador or r.cod_participante = u.identificador or regexp_replace(coalesce(r.cpf_cnpj,''), '\D', '', 'g') = u.identificador))
            or exists (select 1 from eduzz.vendas r where lower(btrim(r.cliente_nome)) = lower(btrim(concat_ws(' ', p.primeiro_nome, p.sobrenome)))
                         and (lower(btrim(r.cliente_email)) = u.identificador or r.cliente_telefone_norm = u.identificador or regexp_replace(coalesce(r.cliente_documento,''), '\D', '', 'g') = u.identificador))
            or exists (select 1 from credenciamento_summit_2026.participantes r where lower(btrim(r.name)) = lower(btrim(concat_ws(' ', p.primeiro_nome, p.sobrenome)))
                         and (lower(btrim(r.email)) = u.identificador or r.telefone_norm = u.identificador or r.id::text = u.identificador or r.yazo_user_id::text = u.identificador))
            or exists (select 1 from credenciamento_summit_2026.yazo_espelho r where lower(btrim(r.name)) = lower(btrim(concat_ws(' ', p.primeiro_nome, p.sobrenome)))
                         and (lower(btrim(r.email)) = u.identificador or r.yazo_id::text = u.identificador)))) as nome_veio_do_burst
  from pessoas.pessoas p
 where p.atualizado_em >= '2026-09-23 02:50:00+00' and p.atualizado_em < '2026-09-23 02:51:00+00';

update pessoas.pessoas p set email = null, atualizado_em = now()
 where p.email is not null and exists (select 1 from d5_undo_ids u where u.canal = 'email' and u.pessoa_id = p.id and u.identificador = lower(p.email));
update pessoas.pessoas p set whatsapp = null, atualizado_em = now()
 where p.whatsapp is not null and exists (select 1 from d5_undo_ids u where u.canal = 'whatsapp' and u.pessoa_id = p.id and u.identificador = p.whatsapp);

update pessoas.pessoas p set primeiro_nome = null, sobrenome = null, atualizado_em = now()
  from d5_undo_pessoas u
 where u.id = p.id and p.primeiro_nome is not null
   and u.nome_veio_do_burst and not u.tem_login and not u.hubspot_apoia and not u.whatsapp_apoia;

delete from engagement.identidade_fusoes f
 where f.criado_em >= '2026-09-23 02:50:00+00' and f.criado_em < '2026-09-23 02:51:00+00' and f.status = 'pendente';
delete from engagement.identidades i where i.id in (select id from d5_undo_ids);

commit;

-- Complemento executado às 03:59 UTC: o sync das 03:50 (já com a regra nova) tinha
-- carimbado as quatro tabelas contra os identificadores colados, ainda não apagados.
-- Os carimbos foram zerados sem disparar o trigger; o sync seguinte os refaz limpos.
begin;
select set_config('mind.d5_pular_trigger', '1', true);
update eduzz.ingressos set pessoa_id = null, pessoa_criterio = null, pessoa_resolvido_em = null where pessoa_resolvido_em is not null;
update eduzz.vendas set pessoa_id = null, pessoa_criterio = null, pessoa_resolvido_em = null where pessoa_resolvido_em is not null;
update credenciamento_summit_2026.participantes set pessoa_id = null, pessoa_criterio = null, pessoa_resolvido_em = null where pessoa_resolvido_em is not null;
update credenciamento_summit_2026.yazo_espelho set pessoa_id = null, pessoa_criterio = null, pessoa_resolvido_em = null where pessoa_resolvido_em is not null;
commit;
