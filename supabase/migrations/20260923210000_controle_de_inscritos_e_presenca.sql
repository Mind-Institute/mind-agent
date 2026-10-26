-- Controle de inscritos e presença do Summit 2026: uma linha por ingresso (2.577).
--
-- Papéis, para não haver duas tabelas com a mesma função:
--   participantes = o cadastro que a Mind mandou para o credenciamento (quem é, que
--     ingresso é, estado de envio para Worknet e Yazo, pessoa_id). É espelho do
--     projeto vendas, reescrito pelo cron eduzz_espelho_sync: toda coluna nova lá
--     morre - foi o que aconteceu com as colunas de validade/presença em 23/09.
--   controle_de_inscritos_e_presenca = o que aconteceu com cada ingresso: válido ou
--     não em cada sistema (foto do funil do projeto vendas em 23/09/2026) e presença
--     em 16/09 e 17/09 com a fonte da evidência. Repete nome/e-mail/ingresso só
--     para leitura direta.
-- Regra de presença (decisão da Adriana, 23/09): presente no dia = a Worknet bipou o
-- ingresso nesse dia (credenciamento_worknet) OU a Yazo registrou check-in de sala
-- nesse dia (Check Ins Summit). Quando só a Yazo viu a pessoa, a Yazo vence, e a
-- fonte registra isso ("yazo"). Ingresso não válido no Mind = cancelado.
-- Idempotente: pode rodar de novo com relatórios mais novos.
create table if not exists credenciamento_summit_2026.controle_de_inscritos_e_presenca (
  uuid              text primary key,     -- participantes.uuid (id do ingresso no projeto vendas)
  participante_id   uuid,                 -- participantes.id
  nome              text,
  email             text,
  ticket_number     text,
  categoria         text,
  origem_ingresso   text,
  lote              text,
  status_mind       text,
  ativo_na_blinket  text,                 -- sim / nao
  valido_no_mind    text,                 -- sim / nao (= ingresso válido)
  valido_na_worknet text,                 -- sim / nao
  valido_no_yazo    text,                 -- sim / nao
  presenca_16_09    text,                 -- sim / ausente / cancelado
  presenca_17_09    text,                 -- sim / ausente / cancelado
  presenca_2_dias   text,                 -- sim / nao / cancelado
  fonte_16_09       text,                 -- bip / yazo / bip+yazo
  fonte_17_09       text,                 -- bip / yazo / bip+yazo
  atualizado_em     timestamptz not null default now()
);
comment on table credenciamento_summit_2026.controle_de_inscritos_e_presenca is
  'O que aconteceu com cada ingresso do Summit 2026 (2.577, um por linha): válido ou não na Blinket / no Mind / na Worknet / no Yazo (foto do funil do projeto vendas em 23/09/2026) e presença em 16/09 e 17/09 com a fonte da evidência. Nome/e-mail/ingresso são cópia de participantes, só para leitura. Cadastro e estado de envio ficam em participantes.';
comment on table credenciamento_summit_2026.participantes is
  'Cadastro dos ingressos que a Mind mandou para o credenciamento do Summit 2026: quem é, que ingresso é, estado de envio para a Worknet (credenciamento_sync_*) e para a Yazo (yazo_sync_*, yazo_user_id) e o pessoa_id da identidade. Espelho do projeto vendas (cron eduzz_espelho_sync): não se escreve aqui. Validade e presença ficam em controle_de_inscritos_e_presenca.';
comment on column credenciamento_summit_2026.controle_de_inscritos_e_presenca.valido_no_mind is
  'sim/nao. Ingresso válido = ativo no Mind. Fonte: v_credenciamento_funil.ativo_no_mind (projeto vendas), copiado em 23/09/2026.';
comment on column credenciamento_summit_2026.controle_de_inscritos_e_presenca.presenca_16_09 is
  'sim / ausente / cancelado. sim = a Worknet bipou o ingresso na entrada em 16/09 (credenciamento_worknet) OU check-in Yazo em alguma sala em 16/09 (Check Ins Summit, por e-mail, só quando o e-mail tem um único ingresso válido). cancelado = ingresso não válido no Mind.';
comment on column credenciamento_summit_2026.controle_de_inscritos_e_presenca.presenca_17_09 is
  'sim / ausente / cancelado. Mesma regra de presenca_16_09, para 17/09.';
comment on column credenciamento_summit_2026.controle_de_inscritos_e_presenca.presenca_2_dias is
  'sim quando 16/09 = sim e 17/09 = sim; nao caso contrário; cancelado quando o ingresso não é válido.';
comment on column credenciamento_summit_2026.controle_de_inscritos_e_presenca.fonte_16_09 is
  'bip | yazo | bip+yazo. bip = a Worknet bipou o ingresso nesse dia (credenciamento_worknet); yazo = check-in de sala no app. "yazo" sozinho = a pessoa estava nas salas mas a Worknet não a bipou nesse dia.';
comment on column credenciamento_summit_2026.controle_de_inscritos_e_presenca.fonte_17_09 is
  'Mesma regra de fonte_16_09, para 17/09.';

-- As colunas de validade/presença que nasceram em participantes e foram zeradas
-- pelo espelho saem de lá. Nenhuma função ou view as referencia.
alter table credenciamento_summit_2026.participantes
  drop column if exists ativo_na_blinket,
  drop column if exists valido_no_mind,
  drop column if exists valido_na_worknet,
  drop column if exists valido_no_yazo,
  drop column if exists presenca_16_09,
  drop column if exists presenca_17_09,
  drop column if exists presenca_2_dias;

-- 1) identificação, copiada de participantes (refresca se o ingresso já existir)
insert into credenciamento_summit_2026.controle_de_inscritos_e_presenca
  (uuid, participante_id, nome, email, ticket_number, categoria, origem_ingresso, lote, status_mind)
select p.uuid, p.id, p.name, p.email, p.ticket_number, p.ticket_type, p.ticket_origin, p.batch, p.status
  from credenciamento_summit_2026.participantes p
 where p.uuid is not null
on conflict (uuid) do update
   set participante_id = excluded.participante_id, nome = excluded.nome, email = excluded.email,
       ticket_number = excluded.ticket_number, categoria = excluded.categoria,
       origem_ingresso = excluded.origem_ingresso, lote = excluded.lote, status_mind = excluded.status_mind,
       atualizado_em = now();

-- 2) validade, copiada do funil do projeto vendas (public.v_credenciamento_funil) em
--    23/09/2026: 2.385 passam em tudo; 192 caem em quatro padrões.
update credenciamento_summit_2026.controle_de_inscritos_e_presenca
   set ativo_na_blinket='sim', valido_no_mind='sim', valido_na_worknet='sim', valido_no_yazo='sim';

-- fora da Blinket e do Mind, mas na Worknet (84)
update credenciamento_summit_2026.controle_de_inscritos_e_presenca
   set ativo_na_blinket='nao', valido_no_mind='nao', valido_no_yazo='nao'
 where uuid in ('a226be98-5dd7-430a-97ea-fefa676ceec2','a2b8da99-0c55-4cf2-ae47-f0787b1b0cec','a2bf3ed4-c717-4fc4-aca4-5877e2dfdad6','a2967b71-3215-4b25-81cc-da8d7a78a1d6','a2b88559-7f6a-4237-98f9-4b283f48feb6','a2beec8a-bb34-4d8b-b43a-13dddfa4397d','a2b710ea-69cf-462f-9300-eb67987d0f13','a2bedc77-aca6-44f5-b0c0-3ad5105fb084','a2aa8241-0fc9-4b53-9d19-e6316eae3ab4','a2beeca2-6509-4724-8384-8e8dca0363d4','a2aceaeb-3d0c-43d2-a4c4-133c9026a41d','a2bf2920-9154-4450-97d5-eefc800bc734','a2b4f45e-ce48-4722-8a37-e8cbc9cc3cba','a2beec9c-486b-4a49-84c8-1aa64a55ba76','a2beeca1-80f2-4136-93c2-f1c17bab6a2b','a2beec9e-3db7-4daf-967f-f877bdc1d457','a2bedc81-16df-4eed-a547-3798808a4176','a2a7ab56-2b69-4ac2-8a1c-8b0b8d00cda3','a1caf760-c5c1-40e0-a73a-033aed8b51cb','a21740a8-e47a-4252-a76f-6bbfd42924ea','a256172d-9108-43c6-9591-759225edce8d','a2beec93-9f55-4437-bf5b-c5aa094d767f','a29819c7-cbea-4467-b295-55e4b6900dc2','a2beec8f-8f32-458c-aa3d-1b685d1432c8','a2a7a6e2-6b80-414c-b8ac-4f8415c75efb','a2bf51c2-b83b-47e5-8bf6-05eceda1c969','a17b09c2-88a3-4fa9-bebb-631620206128','a2beec86-e5e6-478e-bfb1-2283b386c974','a286c9ad-0d0b-4de5-bab8-f0b81d14168a','a2bedc85-3e62-48f4-854a-103aa0b14c97','a2acb295-94e9-476e-b8b3-9266e07e6aa4','a2ad4c19-df2b-4abf-86d0-83330af770d8','a27ea5c3-5a70-4d61-b6ba-2eba7ea95770','a2aa83ce-a5b9-46ec-9fc2-6516f6b2df4b','a22ac030-c188-4b4d-83c6-bac7bbfcb27c','a2b36d2e-497a-4d67-ad90-3d41c432ff89','a2a53eda-1b43-4a89-b482-262bc322d40e','a2c044f7-efe7-47ab-a9b3-cdbd77fbd25c','a2bedc83-387b-41e0-b96e-8d4b22bd47fa','a29b316a-053e-4d7e-b833-a6942c7de622','a2ab3903-73e0-41bf-91f4-cbd92cbd15c7','a22680e2-894c-40cc-bed3-0df389c85e20','a29ae3a3-1baf-4ad8-8297-ed458e3507f9','a296f701-d431-4db8-bbd7-50dbd53ca0c1','a2b6ce43-b791-44e9-a631-3a5055eeec62','a29d1a83-71ed-4de4-932c-3e1faf351b11','a2a7a50a-e648-4f28-b3f5-aff9ed297f3c','a286109f-9080-45bc-b5c2-cf22b0d16175','a2aa8751-679e-45ff-8f24-2b44d5b95064','a2ab3b9f-45e1-4f34-9b52-cbe7d59c8ca8','a2b736d7-95ff-4ffd-856d-2c5252d4556b','a2b9023a-37c3-474b-8c0e-e155663f2bfa','a2c32f7a-e54e-44b8-b3c7-e9622ee8acf2','a29ad9c8-fb0c-430f-833d-9929c3f5b661','a2a66a05-a95d-4d6c-a7a3-af88b5f0131f','a2b4ad8a-2ab5-4fd8-9212-291f8bb4d3f1','a2bf2923-5d15-4259-b0a4-cb49704f0688','a2275850-d4ce-4526-8c07-5040b6160198','a2acb296-18a1-4aca-8081-4d768cd9b914','a2bedc7a-1ff5-4a19-8da5-3090555d56e3','a2beec8c-aeec-43e4-85d4-af8e6a508ff9','a2b2d70a-aadb-44cb-b1ec-1f5c78a1d4f6','a2b4cd43-caa9-4829-88e2-88b09f03ec41','a2bedc7e-884b-44cc-81b6-de9b0fd89a32','a2a7924d-63a3-420c-b6ad-5133116355c4','a1a3034b-9965-4bd2-b82f-7fef26d49b13','a2a78eb7-557e-49b1-85cb-d96f2f42ae61','a2bf51bb-e6fb-438a-9450-a46d7d64525d','a2bedc75-a03c-4e75-9f4b-59b308e17c80','a2a7ab57-683a-4abe-92b9-982bf4ffef3a','a22a7189-557e-4494-af17-a1ba7e6c69b2','a2bf292d-d113-4d7e-bba2-c200052e1460','a2b71d9f-7437-4fbd-89e5-937f987d4b32','a2aab6bf-9955-4827-bb19-40cfcbb19a9d','a2b8aef4-e0f3-4931-bbb7-6ac666a9734a','a2b4cd41-ba51-49bd-aa02-626b47f7ea9a','a2bedc7c-7e94-4b7a-af35-849e361134f8','a2b10f32-4aed-417e-9686-d3197a9f2068','a2bedc80-63e0-4e84-9e69-cf9db4dc2936','a2b10c79-92d9-4e89-a51a-5b4e3f3fac17','a2b8c4cd-e340-49e1-addd-6d6aee7a8b7f','a2beec91-d30a-43cd-ad15-c1f77167ec4a','a2b466fd-9797-40f9-9ffa-8d17eab07ca6','a2bedc78-57f6-423b-afec-1af7bec98c64');

-- válidos que não chegaram ao Yazo (75)
update credenciamento_summit_2026.controle_de_inscritos_e_presenca
   set valido_no_yazo='nao'
 where uuid in ('a2bf51c6-e386-40a1-89d9-594d74127023','a2bb1efd-9c4c-4b43-ad84-b0d48b86252d','a2c18047-17ab-4270-a4be-8aa3972024d0','a2bf291f-2942-4554-aab0-60cd1588cceb','a2bf292d-2388-47ac-ab70-b7753f063351','a2c158e6-169c-4edc-8aa4-23b5e7a563d2','a2bf47fb-6532-46d4-aa9b-42d6b08a91c8','a2c0f6fb-8c42-4a4d-84a5-8213b18f61df','a2c2a9ea-efc3-43fb-90c0-54980df0304d','a2be826f-6450-4a3b-bf7c-6f12191fc122','a2c118d7-d485-4a7f-a398-c883381893c0','a2b672a7-ccea-403e-a27a-d8bc81bd49a6','a2c11219-ae3b-4f01-b2fd-efcd2b9c77aa','a2c0ab8f-01c3-4e5f-a9ea-0b92b862b771','a2c19490-52f1-45c1-9294-bd53a06b542c','a2bf291b-8bad-4222-99c7-15382aace42f','a2c23da8-e05b-4083-b42d-4ede18cf7c0c','a2c09163-af01-4015-b592-33d2cc8002fd','a2bb2526-1012-4938-acdd-db7876500a27','a2b6d33b-4238-4c8b-bb2b-3f07ef09fbb7','a2bf8116-a11d-4ca5-a849-a5f370d5384d','a2c11df9-b4a1-43f9-bb8d-2cddada89bd1','a2c12244-7978-43b6-af8c-5f731b68f886','a2bb2137-77e0-4e05-bb94-ced55a69d71d','a2c13280-16e8-4674-8628-1ba48c6250b9','a2c1576c-e587-49c4-b4e7-7573aea29f6a','a2bf51c4-d1f8-471b-8afb-aeb0b5ee7a4f','a2c08906-0f63-47f5-bfd4-7a6fbf2be5c1','a2bb2620-28d6-40a2-bf4c-13e743c4fa1a','a2c0903e-a203-4485-8e65-a1f19c4d4613','a2c09b5b-9b4e-4ba7-81d5-8df7162323ca','a2bf5903-bc98-4dfc-a61e-03c7add8e10e','a2bb17ea-0269-4dec-862b-214fbe311576','a2c2ee30-7261-43c6-adeb-1fae2bc64dbf','a2c105a6-983b-4a1c-80ef-831d8fd8b088','a2bf2927-8220-446f-8910-f1256b704cb4','a2be74ac-6a15-47c1-a469-904141088ce7','a2c301a9-66dc-4325-8a67-198cc5be310d','a2bb17cc-d0be-445d-aa46-b90fbf68d15d','a2bb2680-a7bb-485d-94ac-d58fcae7b163','a2bb1a8c-d084-400f-a337-3e2bb99cb739','a2c2ffd1-a502-4601-a205-32048063dd8e','a2c08d39-ff37-4c72-bcf7-aab0068bf5f0','a2c1da8e-46ca-440d-ad46-876e540e5087','a2bb26e6-de4e-44da-b933-5a32670a18f5','a2bf51c6-2311-4d65-a8e3-cd01fbeb3a17','a2bb1c56-f19d-40b3-897d-a825223e8ad5','a2bb220f-9f3d-425d-98a6-6bcbe62d665e','a2bb22c5-adbc-401b-84f0-3e58ea2d453d','a2be9e3e-c6b5-4ff5-a28d-71fbe2dc79e8','a2bb1a8d-3259-4539-8f4b-70ebd15cbf65','a2bb18a7-784a-4fec-9546-145cfe8bc8af','a2bb226b-2876-47e1-9600-84006388c12a','a2bf4276-518e-48b1-a1c7-e54084482f3a','a2c0fd85-bbc6-4102-bf74-397263e79f59','a2b4b657-0367-466a-b362-1fbc9e0f0b8e','a2bb1aa2-2687-4cd3-8a18-e6f07c8082ed','a2c15157-818d-43fe-b603-bca0da0bc5f4','a2c104e3-c5ed-4150-9c66-6b4ea5436c8d','a2bb2137-60a1-4e1c-9867-6b8ae653fb21','a2c0eded-2e11-4b13-8f71-7444266843d5','a2c0fd1f-0d2c-47d8-af71-0316bad2d701','a2bb1f6e-b442-4282-9bc3-7adb91583662','a2c0efb8-8e91-4bf1-8bc5-606ae04a9b6b','a2bb1958-a2b9-490f-a88f-da54a7cf378a','a2c09093-5396-47ea-b251-c75edba8d65e','a2bf51bb-3a02-4352-8819-e6f2316703f6','a2b6712e-6c71-4818-842e-d29d64bb7939','a2c0fd86-80e2-4033-859b-b006d49357d0','a2bf291f-d669-4ce1-aecd-cc2d2282b2c8','a2c0fd87-5254-46a0-b70f-84a2a026198e','a2c0a087-6f05-4638-977c-8031cfe211d1','a2bb2139-9c34-46ba-90f7-5786c616185e','a2bf51bc-a61d-4af4-9d6b-c7eef371fa88','a2bf51c5-80e5-4086-804c-7bdf534740b8');

-- na Blinket e na Worknet, mas não no Mind nem no Yazo (21)
update credenciamento_summit_2026.controle_de_inscritos_e_presenca
   set valido_no_mind='nao', valido_no_yazo='nao'
 where uuid in ('a29c2af0-68bf-474f-b90a-d9eb3c593a6f','a2965f9f-961f-4409-a528-49cf7b716d9a','a286a28e-89d0-476d-b03c-eb21330f1ee7','a2a728d9-b699-44a5-9504-c6a31a8f95e8','a2b281de-0f47-496f-9d91-7e6ef032e397','a2a741b3-d3d7-4fb3-a1b5-be733e243cb9','a2a72882-9c98-4da6-9cf4-e862f137a4fa','a29aa50d-722b-420b-a3ae-76b0bf9fcbb4','a2a94f1c-319b-4189-bee9-95e2812128f3','a2a75e3e-2b69-405c-8e3d-c5ef99f6583c','a2af9ecd-ec8b-4a62-bca9-d7b748e63507','a2968f50-5932-4af4-a4ba-227be70251db','a2a4aeab-47fc-4fc7-aa95-7b4ed733c1eb','a2a32497-ccaa-4659-b781-2364c6d900c1','a2aa7bee-b512-4a06-b8fd-681a32d10da3','a2aa5c72-ea2e-411e-a378-9eee4861acf8','a2a8631c-4c27-4d01-b0b0-0e0cca0de95d','a2a78eb7-47bf-46cb-9f42-b1f427ae029e','a29ac0da-ead8-411d-afa1-eacf90b8b08f','a2af0b8e-7aef-458c-b65b-197e62138038','a2aaf95d-e099-4615-ad9c-5e14941a178e');

-- válidos no Mind, mas nem na Worknet nem no Yazo (12)
update credenciamento_summit_2026.controle_de_inscritos_e_presenca
   set valido_na_worknet='nao', valido_no_yazo='nao'
 where uuid in ('a2c0efb9-24bd-4b93-a07b-aad27dd417a7','a2c24177-bc5e-400d-9696-8248993663c6','a2c2ad00-6548-410c-b4e8-d3aa2ca3da40','a2c2ff35-215e-4c3c-a74f-f0c8eccdbad9','a2c28f3f-558b-468f-b35b-c1233c0aea7c','a2c15327-2351-4d55-a86e-196d494fa1de','a2c136be-91f2-4b53-8ca7-41caca263964','a2c1385e-2b58-44c6-8505-8eaac9ff76aa','a2c13582-44ec-4cd3-9c5b-80f539fa6592','a2c07248-17cf-460f-a33b-905e9545fbf7','a2c2571d-5c58-4675-98e4-f39015287fa0','a2c23fab-ac51-42af-a288-66eab4e36ee9');

-- 3) presença: a Worknet bipou o ingresso no dia (por ingresso, ou por e-mail nos
--    check-ins manuais) OU check-in Yazo em sala no dia (por e-mail, só quando o
--    e-mail identifica um único ingresso válido - com e-mail compartilhado o check-in
--    de sala não diz qual ingresso foi usado). A fonte fica registrada.
with unico as (
  select lower(trim(email)) as email from credenciamento_summit_2026.controle_de_inscritos_e_presenca
   where valido_no_mind = 'sim' group by 1 having count(*) = 1
),
yazo as (
  select distinct lower(trim("Email")) as email, extract(day from checkin_em at time zone 'America/Sao_Paulo')::int as dia
    from credenciamento_summit_2026."Check Ins Summit" where checkin_em is not null
),
ev as (
  select c.uuid,
         exists (select 1 from credenciamento_summit_2026.credenciamento_worknet b where b.dia=16 and ((not b.por_email and b.chave = upper(trim(c.ticket_number))) or (b.por_email and b.chave = lower(trim(c.email))))) as bip16,
         exists (select 1 from credenciamento_summit_2026.credenciamento_worknet b where b.dia=17 and ((not b.por_email and b.chave = upper(trim(c.ticket_number))) or (b.por_email and b.chave = lower(trim(c.email))))) as bip17,
         (lower(trim(c.email)) in (select email from unico) and exists (select 1 from yazo y where y.email = lower(trim(c.email)) and y.dia = 16)) as yazo16,
         (lower(trim(c.email)) in (select email from unico) and exists (select 1 from yazo y where y.email = lower(trim(c.email)) and y.dia = 17)) as yazo17
    from credenciamento_summit_2026.controle_de_inscritos_e_presenca c
)
update credenciamento_summit_2026.controle_de_inscritos_e_presenca c
   set presenca_16_09 = case when c.valido_no_mind='nao' then 'cancelado' when ev.bip16 or ev.yazo16 then 'sim' else 'ausente' end,
       presenca_17_09 = case when c.valido_no_mind='nao' then 'cancelado' when ev.bip17 or ev.yazo17 then 'sim' else 'ausente' end,
       fonte_16_09 = case when c.valido_no_mind='nao' then null when ev.bip16 and ev.yazo16 then 'bip+yazo' when ev.bip16 then 'bip' when ev.yazo16 then 'yazo' end,
       fonte_17_09 = case when c.valido_no_mind='nao' then null when ev.bip17 and ev.yazo17 then 'bip+yazo' when ev.bip17 then 'bip' when ev.yazo17 then 'yazo' end,
       atualizado_em = now()
  from ev where ev.uuid = c.uuid;

update credenciamento_summit_2026.controle_de_inscritos_e_presenca
   set presenca_2_dias = case when valido_no_mind='nao' then 'cancelado' when presenca_16_09='sim' and presenca_17_09='sim' then 'sim' else 'nao' end;
