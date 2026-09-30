-- Correção de typos de e-mail em pessoas.pessoas (Adriana, 24/09/2026 — passo 2 do enriquecimento).
-- Só pessoas cujo e-mail corrigido ainda não pertence a ninguém. O corrigido entra pela porta
-- mind_identificador_declarado_registrar; o e-mail com typo continua como identificador da mesma
-- pessoa (quem digitar errado de novo cai no mesmo mind_id). Depois o corrigido vira o principal.
-- Quando o corrigido já é de outra pessoa, nada muda aqui: é duplicata e vai para o passo 11.
-- jose@msn.com.br fica de fora (jose@msn.com seria a caixa de outra pessoa).
with alvo(id, errado, certo) as (values
 ('7ae7e484-8df1-4ede-8f0f-577e4eccbd4d'::uuid,'aambulanciasmban.com.br','ambulanciasmban.com.br'),
 ('1cf98dbc-b562-4c4c-97fb-50100a47f317','beyondcorporate.com.be','beyondcorporate.com.br'),
 ('9fb132d3-0280-4492-90cf-e749628c0e50','boehringr-ingelheim.com','boehringer-ingelheim.com'),
 ('8d642f20-7a5f-4a34-9bc3-4661a16b656b','dbacomp.br','dbacomp.com.br'),
 ('f0766646-ea85-4909-ac39-a10b5e263c02','gamil.com','gmail.com'),
 ('cc9fbd8d-f75c-44bb-88e5-cb455b5193f4','gnail.com','gmail.com'),
 ('6df1bf7f-bd66-404f-afd8-844486ebd315','gmal.com','gmail.com'),
 ('b7334028-ea78-4403-8667-f5ce6c5fa27a','gmail.com.br','gmail.com'),
 ('963b516d-9983-44ab-b6b8-9ec430e208f1','gmail.com.br','gmail.com'),
 ('5d3d9457-08a2-4317-8185-5c39cfa8869b','hotmail.con','hotmail.com'),
 ('9da81396-f383-487b-a2d7-571e1065187e','icour.com','icloud.com'),
 ('6823361d-54e2-4c81-a817-30469ff7d68d','iclaud.com','icloud.com'),
 ('245e419f-df57-48d4-9aa3-6a29ceed6b2d','icourd.com','icloud.com'),
 ('6a92bb9f-a195-440b-a9b5-4c97ac0be07a','icoud.com','icloud.com'),
 ('5678ce23-bf4d-4fe4-8aa2-848df57f1201','maisidiversidade.com.br','maisdiversidade.com.br'),
 ('f3225f79-a398-427f-aa61-d8295a15c591','medic360.com.bt','medic360.com.br'),
 ('e86308bc-ff79-4289-9dee-13ee9bfb861f','proconnecengenharia.com.br','proconnectengenharia.com.br'),
 ('19403d6d-0f0f-4dff-ab11-5986227a8f0b','rochsmiranda.adv.br','rochamiranda.adv.br'),
 ('01f9d4a9-6b88-4374-a863-b456be56edf0','uol.com','uol.com.br')),
req as (select gen_random_uuid() r),
feito as (
 select a.id, p.email antes, split_part(p.email,'@',1)||'@'||a.certo depois,
        public.mind_identificador_declarado_registrar(a.id,'email',split_part(p.email,'@',1)||'@'||a.certo) r
   from alvo a join pessoas.pessoas p on p.id=a.id and lower(split_part(p.email,'@',2))=a.errado
  order by a.id::text),
troca as (
 update pessoas.pessoas p set email = f.depois, atualizado_em = now()
   from feito f
  where p.id = f.id and (f.r->>'ok')::boolean
    and not exists (select 1 from pessoas.pessoas q where q.id<>p.id and lower(q.email)=f.depois)
 returning p.id),
aud as (
 insert into public.mind_admin_audit (action, resource, record_id, record_label, before_data, after_data, request_id)
 select 'atualizar','pessoas_email_typo', f.id::text, 'typo de e-mail corrigido',
        jsonb_build_object('email', f.antes), jsonb_build_object('email', f.depois, 'porta', f.r), (select r from req)
   from feito f where f.id in (select id from troca)
 returning 1)
select f.id, f.antes, f.depois, f.r, f.id in (select id from troca) trocado, (select count(*) from aud) auditados from feito f;
