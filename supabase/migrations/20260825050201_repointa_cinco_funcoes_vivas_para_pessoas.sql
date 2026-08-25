-- Repointa crm.pessoas -> pessoas.pessoas nas 5 funções que ainda funcionam.
-- (mind_identificar_pessoa e treble_agent_start ficam de fora: referenciam
--  treble.conversations, que foi dropada na redução do treble a config, e serão
--  reconstruídas junto com o runtime do treble.)
-- Troca só o token inteiro (\m...\M): não toca crm.pessoas_interno/pessoa_produtos.
do $repoint$
declare
  r record;
begin
  for r in
    select p.oid
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where p.prokind = 'f'
      and (n.nspname||'.'||p.proname) in (
        'crm.buscar_pessoa','public.mind_candidatos_identidade','public.mind_espelho_ligar',
        'public.mind_pessoa_completar','public.treble_resolver_por_whatsapp')
  loop
    execute regexp_replace(pg_get_functiondef(r.oid), '\mcrm\.pessoas\M', 'pessoas.pessoas', 'g');
  end loop;
end
$repoint$;
