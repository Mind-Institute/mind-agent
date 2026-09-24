-- O App ainda nao foi lancado: toda memoria produzida por `mindagent-chat` e teste.
-- Preserva conversas/analises normais como auditoria e nao toca em memoria WhatsApp.

create temp table app_test_memory_target on commit drop as
select pm.id
from intelligence.participante_memoria pm
join intelligence.analise_conversa ac on ac.id=pm.analise_conversa_id
join engagement.conversas c on c.id=ac.conversa_id
where c.agente='mindagent-chat';

-- Uma memoria antiga sem analise estava substituida por uma memoria do App.
-- Soltamos a referencia antes do delete e a reativamos depois, em vez de apagar
-- algo cuja origem App nao esta comprovada.
create temp table app_test_memory_restore on commit drop as
select pm.id, pm.participante_id, pm.chave
from intelligence.participante_memoria pm
where pm.substituida_por in (select id from app_test_memory_target)
  and pm.id not in (select id from app_test_memory_target);

update intelligence.participante_memoria pm
set substituida_por=null, atualizado_em=now()
where pm.id in (select id from app_test_memory_restore);

delete from intelligence.participante_memoria pm
where pm.id in (select id from app_test_memory_target);

update intelligence.participante_memoria pm
set status='ativa', atualizado_em=now()
where pm.id in (select id from app_test_memory_restore)
  and not exists (
    select 1 from intelligence.participante_memoria atual
    where atual.participante_id=pm.participante_id
      and atual.chave=pm.chave
      and atual.status='ativa'
      and atual.id<>pm.id
  );

-- Perfil rapido tambem e exclusivo do App. O predicado exige participante com
-- conversa mindagent-chat e nenhuma conversa de outro agente.
delete from engagement.session_interests si
using engagement.agent_sessions s
where si.agent_session_id=s.id
  and exists (
    select 1 from engagement.conversas c
    where c.participante_id=s.participante_id and c.agente='mindagent-chat'
  )
  and not exists (
    select 1 from engagement.conversas c
    where c.participante_id=s.participante_id
      and coalesce(c.agente,'')<>'mindagent-chat'
  );

-- Esta projecao tinha tres linhas, todas de participantes exclusivos do App.
delete from intelligence.participante_contexto pc
where exists (
    select 1 from engagement.conversas c
    where c.participante_id=pc.participante_id and c.agente='mindagent-chat'
  )
  and not exists (
    select 1 from engagement.conversas c
    where c.participante_id=pc.participante_id
      and coalesce(c.agente,'')<>'mindagent-chat'
  );

-- Remove somente o fixture sintetico do E2E desta correcao.
delete from intelligence.analise_conversa
where conversa_id in (
  'c1000000-0000-4000-8000-000000000001',
  'c1000000-0000-4000-8000-000000000002',
  'c1000000-0000-4000-8000-000000000003'
);

delete from engagement.mensagens
where conversa_id in (
  'c1000000-0000-4000-8000-000000000001',
  'c1000000-0000-4000-8000-000000000002',
  'c1000000-0000-4000-8000-000000000003'
);

delete from engagement.conversas
where id in (
  'c1000000-0000-4000-8000-000000000001',
  'c1000000-0000-4000-8000-000000000002',
  'c1000000-0000-4000-8000-000000000003'
);

delete from pessoas.pessoas
where id in (
  'f1000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000002',
  'f1000000-0000-4000-8000-000000000003'
);

do $contract$
begin
  if exists (
    select 1
    from intelligence.participante_memoria pm
    join intelligence.analise_conversa ac on ac.id=pm.analise_conversa_id
    join engagement.conversas c on c.id=ac.conversa_id
    where c.agente='mindagent-chat'
  ) then raise exception 'restou memoria duravel produzida pelo App'; end if;

  if exists (select 1 from engagement.conversas where session_external_id like 'codex-memory-v5-%') then
    raise exception 'fixture sintetico nao foi removido';
  end if;
end
$contract$;
