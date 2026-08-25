-- Config de integracao sai de treble.config. Token de HubSpot e Eduzz nao e do bot
-- do WhatsApp -- e de como o Mind Intelligence fala com o mundo la fora.
--
-- Mesmo idioma que platform.llm_providers ja usava: guarda o NOME do secret
-- (secret_ref), nunca o valor. O valor vive so nos secrets do Supabase.
create table if not exists platform.integracoes (
  codigo text primary key,
  rotulo text not null,
  base_url text,
  secret_ref text,
  config jsonb not null default '{}'::jsonb,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

comment on table platform.integracoes is
  'Como o Mind Intelligence fala com sistemas de fora. secret_ref e o NOME da variavel nos secrets do Supabase -- o valor nunca entra no banco. config guarda o que nao e segredo (id de portal, chave publica, guid de formulario).';
comment on column platform.integracoes.secret_ref is
  'Nome da variavel de ambiente que a Edge Function le. Nunca o valor.';
comment on column platform.integracoes.config is
  'Config nao secreta. Public Key da Eduzz e id de portal do HubSpot moram aqui: sao identificadores, nao credenciais.';

insert into platform.integracoes (codigo, rotulo, base_url, secret_ref, config) values
  ('hubspot', 'HubSpot', 'https://api.hubapi.com', 'HUBSPOT_TOKEN',
   jsonb_build_object(
     'portal_id', '50780019',
     'form_guid', '9995b760-dd1d-4ed2-ab79-8e8b97188d8e',
     'pipeline_leads', '917379159',
     'pipeline_historico', 'default')),
  ('eduzz', 'Eduzz', 'https://api.eduzz.com', 'EDUZZ_API_KEY',
   jsonb_build_object('public_key', '14449348'))
on conflict (codigo) do nothing;

revoke all on table platform.integracoes from public, anon, authenticated;
