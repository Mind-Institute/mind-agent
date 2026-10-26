-- Executar no mind-agent após a transferência inicial. Não contém textos de decisões.
begin;
do $$ begin
 if (select count(*) from arquitetura.decisoes) < 11 then raise exception 'Transferência inicial incompleta'; end if;
 if has_table_privilege('anon','arquitetura.decisoes','SELECT') or
    has_table_privilege('authenticated','arquitetura.decisoes','SELECT') then
   raise exception 'Decisões abertas fora da porta administrativa';
 end if;
 if has_table_privilege('service_role','arquitetura.decisoes','UPDATE') or
    has_table_privilege('service_role','arquitetura.decisoes','INSERT') then
   raise exception 'A porta de leitura tem permissão de escrita';
 end if;
 if not has_table_privilege('service_role','arquitetura.implementacao_decisoes','SELECT') then
   raise exception 'Mapa de implementação inacessível à porta';
 end if;
 if to_regclass('public.arquitetura_decisoes_painel') is not null then
   raise exception 'Estrutura de arquitetura fora do schema indicado';
 end if;
 if not (select relrowsecurity from pg_class where oid='arquitetura.decisoes'::regclass) then
   raise exception 'RLS desligada';
 end if;
end $$;
rollback;
