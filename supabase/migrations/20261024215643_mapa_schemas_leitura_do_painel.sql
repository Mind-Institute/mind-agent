-- O painel lê arquitetura.mapa_schemas pela mindagent-home com service_role, como já faz com
-- arquitetura.decisoes e implementacao_decisoes. A tabela nasceu sem o grant: a leitura dava
-- 42501, a função respondia 403 e /admin/arquitetura/schemas ficava vazio (24/10/2026, medido
-- nos logs: decisoes 200 e mapa-schemas 403 na mesma sessão). Mesmo padrão das irmãs: RLS ligado
-- e SELECT só para service_role (anon/authenticated seguem sem acesso).
alter table arquitetura.mapa_schemas enable row level security;
grant select on arquitetura.mapa_schemas to service_role;
