-- Estrutura e fonte oficial aprovadas por Adriana nesta conversa (07/10/2026).
-- Sem função nova. Tela somente leitura, via mindagent-home autenticada.
create schema if not exists arquitetura;
comment on schema arquitetura is 'Decisões oficiais do projeto Mind. Documentos e painel são espelhos.';
create table if not exists arquitetura.decisoes (
 codigo text primary key check (codigo ~ '^D[1-9][0-9]*$'),
 numero integer not null unique check (numero > 0),
 titulo text not null check (length(trim(titulo)) > 0),
 texto text not null check (length(trim(texto)) > 0),
 significado text not null,
 decidida_em date not null,
 aprovada_por text not null,
 vigencia text not null default 'vigente' check (vigencia in ('vigente','substituida')),
 substituida_por text references arquitetura.decisoes(codigo),
 check (codigo = 'D' || numero::text),
 check ((vigencia = 'vigente' and substituida_por is null) or
        (vigencia = 'substituida' and substituida_por is not null and substituida_por <> codigo))
);
comment on table arquitetura.decisoes is 'Fonte oficial do texto e significado das decisões aprovadas. Alterações somente por decisão da Adriana; painel não escreve.';
create table if not exists arquitetura.implementacao_decisoes (
 codigo text primary key references arquitetura.decisoes(codigo),
 situacao text not null check (situacao in ('aplicada','parcial','so-documento')),
 leitura text not null,
 lugares jsonb not null default '[]' check (jsonb_typeof(lugares) = 'array'),
 medido_em date not null
);
comment on table arquitetura.implementacao_decisoes is 'Fotografia da aplicação, separada do texto aprovado. medido_em informa quando foi aferida; não é telemetria.';
alter table arquitetura.decisoes enable row level security;
alter table arquitetura.implementacao_decisoes enable row level security;
revoke all on schema arquitetura from public, anon, authenticated;
revoke all on all tables in schema arquitetura from public, anon, authenticated;
grant usage on schema arquitetura to service_role;
grant select on arquitetura.decisoes, arquitetura.implementacao_decisoes to service_role;

notify pgrst, 'reload schema';

-- O override já existente de PostgREST no authenticator prevalece sobre a
-- configuração da plataforma. Acrescenta arquitetura preservando os schemas atuais.
do $$
declare v_schemas text;
begin
 select substring(setting from length('pgrst.db_schemas=') + 1) into v_schemas
 from pg_db_role_setting s join pg_roles r on r.oid = s.setrole
 cross join lateral unnest(s.setconfig) x(setting)
 where r.rolname = 'authenticator' and s.setdatabase = 0
   and setting like 'pgrst.db_schemas=%';
 if v_schemas is not null and not ('arquitetura' = any(regexp_split_to_array(v_schemas, '\s*,\s*'))) then
   execute format('alter role authenticator set pgrst.db_schemas to %L', v_schemas || ', arquitetura');
 end if;
end $$;
notify pgrst, 'reload config';
notify pgrst, 'reload schema';
