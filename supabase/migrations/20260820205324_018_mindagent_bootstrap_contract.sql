
insert into mind.taxonomy(tipo,codigo,rotulo,sinonimos,ativo)
values
('tema','seguranca_psicologica','Segurança psicológica','{}'::text[],true),
('tema','dados_bem_estar','Dados e ROI do bem-estar','{}'::text[],true),
('tema','regulacao','NR-1 e riscos psicossociais','{}'::text[],true),
('tema','lideranca_humana','Liderança','{}'::text[],true),
('tema','cultura','Cultura organizacional','{}'::text[],true),
('tema','saude_mental','Saúde mental','{}'::text[],true),
('tema','performance','Performance sustentável','{}'::text[],true),
('tema','diversidade','Diversidade e inclusão','{}'::text[],true),
('tema','felicidade','Felicidade e propósito','{}'::text[],true),
('tema','futuro_trabalho','Futuro do trabalho','{}'::text[],true)
on conflict (codigo) do update set
  tipo=excluded.tipo, rotulo=excluded.rotulo, ativo=true;

alter table mind.speakers
  add column if not exists asset_path text,
  add column if not exists destaque boolean not null default false,
  add column if not exists temas text[] not null default '{}'::text[];

update mind.sessions set topicos_aprendizado='["futuro_trabalho"]'::jsonb, atualizado_em=now() where id='b37a79ac-1c4c-5cd9-afe8-25b2d4f32bc6'::uuid;
update mind.sessions set topicos_aprendizado='["dados_bem_estar","cultura"]'::jsonb, atualizado_em=now() where id='7c5b0e9d-b358-5d78-96c7-eedf8b020d15'::uuid;
update mind.sessions set topicos_aprendizado='["dados_bem_estar"]'::jsonb, atualizado_em=now() where id='4b9f03be-81d3-5f54-93f1-6501d7914d84'::uuid;
update mind.sessions set topicos_aprendizado='["dados_bem_estar","performance"]'::jsonb, atualizado_em=now() where id='d6787e2e-867d-5cd7-b2ba-92deba8feec8'::uuid;
update mind.sessions set topicos_aprendizado='["dados_bem_estar","regulacao","performance"]'::jsonb, atualizado_em=now() where id='3c18c504-a6dc-58dd-ba4f-23f22667c664'::uuid;
update mind.sessions set topicos_aprendizado='["lideranca_humana","performance"]'::jsonb, atualizado_em=now() where id='10c73962-cee3-53a1-80bc-e57075f8daeb'::uuid;
update mind.sessions set topicos_aprendizado='["dados_bem_estar","cultura"]'::jsonb, atualizado_em=now() where id='6d4eba89-5e4a-5703-b4f4-3c3d856d96a2'::uuid;
update mind.sessions set topicos_aprendizado='["dados_bem_estar","performance"]'::jsonb, atualizado_em=now() where id='7c96ea1f-c222-5778-bebc-75948eb6be4b'::uuid;
update mind.sessions set topicos_aprendizado='["cultura","performance","diversidade"]'::jsonb, atualizado_em=now() where id='f2d5d382-891f-5242-84f0-7950ab1cea41'::uuid;
update mind.sessions set topicos_aprendizado='["performance"]'::jsonb, atualizado_em=now() where id='35fde208-ab37-5b7f-a329-a99cb4997b01'::uuid;
update mind.sessions set topicos_aprendizado='["diversidade"]'::jsonb, atualizado_em=now() where id='4cdf1e4d-6541-54ac-bf3a-bd0acc37d346'::uuid;
update mind.sessions set topicos_aprendizado='["dados_bem_estar"]'::jsonb, atualizado_em=now() where id='75a51468-1844-59a9-b042-fd403c713b6c'::uuid;
update mind.sessions set topicos_aprendizado='["seguranca_psicologica","lideranca_humana"]'::jsonb, atualizado_em=now() where id='5de63173-a984-5b2b-8fbf-6e17d85bebb2'::uuid;
update mind.sessions set topicos_aprendizado='["performance","futuro_trabalho"]'::jsonb, atualizado_em=now() where id='68a39f7e-60e5-52eb-adb2-fa911acf040b'::uuid;
update mind.sessions set topicos_aprendizado='["lideranca_humana"]'::jsonb, atualizado_em=now() where id='ee81defd-7aa0-55a8-9e82-9d8b780dc914'::uuid;
update mind.sessions set topicos_aprendizado='["lideranca_humana"]'::jsonb, atualizado_em=now() where id='5d90e3cf-71eb-5ce7-8f86-a07f4b390759'::uuid;
update mind.sessions set topicos_aprendizado='["performance"]'::jsonb, atualizado_em=now() where id='3df81b17-957b-5f65-aae1-14a428dade1f'::uuid;
update mind.sessions set topicos_aprendizado='["cultura"]'::jsonb, atualizado_em=now() where id='946dcdbb-55f4-535d-8392-6aacab9dddfa'::uuid;
update mind.sessions set topicos_aprendizado='["lideranca_humana","cultura"]'::jsonb, atualizado_em=now() where id='0222fc31-8a81-5010-a7c3-e3a86fe5c916'::uuid;
update mind.sessions set topicos_aprendizado='["saude_mental"]'::jsonb, atualizado_em=now() where id='6d4d6dbe-5b52-5035-8bd8-ec82eb36e79a'::uuid;
update mind.sessions set topicos_aprendizado='["lideranca_humana","performance"]'::jsonb, atualizado_em=now() where id='a1e85d2a-fcf5-5cab-b677-f8f42fefe38f'::uuid;
update mind.sessions set topicos_aprendizado='["saude_mental"]'::jsonb, atualizado_em=now() where id='91bd717a-fa98-5f18-a01c-a40c57f3c58c'::uuid;
update mind.sessions set topicos_aprendizado='["saude_mental"]'::jsonb, atualizado_em=now() where id='a3bacc8c-2654-59fe-ba7c-54a00cd172e5'::uuid;
update mind.sessions set topicos_aprendizado='["lideranca_humana"]'::jsonb, atualizado_em=now() where id='de5dab51-ba11-5da1-ba2f-27b6cdb8cd0d'::uuid;
update mind.sessions set topicos_aprendizado='["seguranca_psicologica","dados_bem_estar","felicidade"]'::jsonb, atualizado_em=now() where id='122b5a47-da41-5fd3-9b47-ced719165772'::uuid;
update mind.sessions set topicos_aprendizado='["regulacao","lideranca_humana"]'::jsonb, atualizado_em=now() where id='868308ce-2f1c-564a-9b2b-c91a30d616ad'::uuid;
update mind.sessions set topicos_aprendizado='["dados_bem_estar","felicidade"]'::jsonb, atualizado_em=now() where id='2f17a564-b446-5699-91d8-327d1f336e51'::uuid;
update mind.sessions set topicos_aprendizado='["seguranca_psicologica","futuro_trabalho"]'::jsonb, atualizado_em=now() where id='f237d451-4fae-5906-90aa-d5fc388ee6d2'::uuid;
update mind.sessions set topicos_aprendizado='["regulacao"]'::jsonb, atualizado_em=now() where id='f6bb40b6-ad85-5db7-ae1c-043218f56a4c'::uuid;
update mind.sessions set topicos_aprendizado='["seguranca_psicologica"]'::jsonb, atualizado_em=now() where id='8d921914-ba99-5607-a952-1511a296fd5a'::uuid;
update mind.sessions set topicos_aprendizado='["saude_mental","performance"]'::jsonb, atualizado_em=now() where id='6694a489-b494-5cf2-b914-304319d53f9b'::uuid;
update mind.sessions set topicos_aprendizado='["lideranca_humana","saude_mental","performance"]'::jsonb, atualizado_em=now() where id='a0091247-4943-5f91-a1f1-fdd0a0a310b8'::uuid;
update mind.sessions set topicos_aprendizado='["diversidade","futuro_trabalho"]'::jsonb, atualizado_em=now() where id='617f8e6a-3dd9-5910-b408-26b4db2499d1'::uuid;
update mind.sessions set topicos_aprendizado='["lideranca_humana","saude_mental","performance"]'::jsonb, atualizado_em=now() where id='0b82c475-fc9e-5e25-bbb1-45eba9dc64f1'::uuid;
update mind.sessions set topicos_aprendizado='["cultura","diversidade"]'::jsonb, atualizado_em=now() where id='40c0274c-4512-5e95-a809-13599b010217'::uuid;
update mind.sessions set topicos_aprendizado='["felicidade"]'::jsonb, atualizado_em=now() where id='b883b99a-834b-5b3c-aa6d-8d195a643ec6'::uuid;
update mind.sessions set topicos_aprendizado='["lideranca_humana","saude_mental"]'::jsonb, atualizado_em=now() where id='55f69ee1-cf8d-5b3d-bc0f-69f7dd044268'::uuid;
update mind.sessions set topicos_aprendizado='["performance"]'::jsonb, atualizado_em=now() where id='e9c10661-398f-5de8-80ac-fa5783b22304'::uuid;
update mind.sessions set topicos_aprendizado='["lideranca_humana","futuro_trabalho"]'::jsonb, atualizado_em=now() where id='9ebdc8c9-902f-5638-8a98-03cb806f931e'::uuid;
update mind.sessions set topicos_aprendizado='["lideranca_humana","performance"]'::jsonb, atualizado_em=now() where id='cc86e6f1-7152-51d4-9227-9e84e88aec58'::uuid;
update mind.sessions set topicos_aprendizado='["lideranca_humana","performance"]'::jsonb, atualizado_em=now() where id='36b7f988-4877-5d17-bdf9-62f11eca7ded'::uuid;
update mind.sessions set topicos_aprendizado='["saude_mental"]'::jsonb, atualizado_em=now() where id='4b2ecfa4-0ac6-5ed2-be7a-9ad61be1181a'::uuid;
update mind.sessions set topicos_aprendizado='["lideranca_humana","cultura"]'::jsonb, atualizado_em=now() where id='568302ff-3f7d-5fce-b47f-61d002137747'::uuid;
update mind.sessions set topicos_aprendizado='["seguranca_psicologica","lideranca_humana"]'::jsonb, atualizado_em=now() where id='62c883dd-0e86-530d-8f4f-7fc39a41ce24'::uuid;
update mind.sessions set topicos_aprendizado='["seguranca_psicologica"]'::jsonb, atualizado_em=now() where id='9852f37e-c994-577a-938b-9cff8e3c5b60'::uuid;

update mind.speakers set asset_path='palestrantes/amy.webp', destaque=true, temas='{seguranca_psicologica,dados_bem_estar,lideranca_humana,performance}'::text[], atualizado_em=now() where id='8ce2e6fb-3b07-594c-aa6f-cfcbd3fcda16'::uuid;
update mind.speakers set asset_path='palestrantes/christina.webp', destaque=true, temas='{dados_bem_estar,saude_mental}'::text[], atualizado_em=now() where id='c431edf7-455c-51ef-bf57-93bc34bbebe3'::uuid;
update mind.speakers set asset_path='palestrantes/deneve.webp', destaque=true, temas='{dados_bem_estar,lideranca_humana}'::text[], atualizado_em=now() where id='c85978d8-6fad-5844-9e13-fecf85c76423'::uuid;
update mind.speakers set asset_path='palestrantes/sonja.webp', destaque=true, temas='{dados_bem_estar,performance,felicidade,futuro_trabalho}'::text[], atualizado_em=now() where id='6eaf9d6a-f589-525e-9c0c-2e6eee6fc6ea'::uuid;
update mind.speakers set asset_path='palestrantes/adriana.webp', destaque=false, temas='{dados_bem_estar}'::text[], atualizado_em=now() where id='819c0597-c8fb-5b13-b0d1-4e9e0c2f2b69'::uuid;
update mind.speakers set asset_path='palestrantes/carla.webp', destaque=false, temas='{dados_bem_estar,saude_mental,performance}'::text[], atualizado_em=now() where id='77c744c4-5557-5635-bda8-57f28b3af144'::uuid;
update mind.speakers set asset_path='palestrantes/ana-claudia.webp', destaque=false, temas='{saude_mental,felicidade}'::text[], atualizado_em=now() where id='0c8ed8db-319c-59fc-8ac6-1f0061b6ba19'::uuid;
update mind.speakers set asset_path='palestrantes/marcio.webp', destaque=false, temas='{performance,futuro_trabalho}'::text[], atualizado_em=now() where id='0fa278a4-57b1-5088-a7c3-16add340f72c'::uuid;
update mind.speakers set asset_path='palestrantes/arthur.webp', destaque=false, temas='{lideranca_humana,saude_mental,performance}'::text[], atualizado_em=now() where id='bf6188d9-ee3d-5b36-ae08-4f1e20884578'::uuid;
update mind.speakers set asset_path='palestrantes/daniel.webp', destaque=false, temas='{saude_mental}'::text[], atualizado_em=now() where id='e869e5de-6383-5b3f-bc4f-8100a3722c4d'::uuid;
update mind.speakers set asset_path='palestrantes/izabella.webp', destaque=false, temas='{dados_bem_estar,saude_mental,performance}'::text[], atualizado_em=now() where id='b24d3e26-74f0-5fa2-8c2f-1e134304e17e'::uuid;
update mind.speakers set asset_path='palestrantes/renata.webp', destaque=false, temas='{dados_bem_estar,felicidade,futuro_trabalho}'::text[], atualizado_em=now() where id='273585de-88a0-5cc1-b946-f841e28f943c'::uuid;
update mind.speakers set asset_path='palestrantes/tamara.webp', destaque=false, temas='{dados_bem_estar}'::text[], atualizado_em=now() where id='69e92856-8d05-5052-8b89-5ab06b744afb'::uuid;
update mind.speakers set asset_path='palestrantes/deepika.webp', destaque=false, temas='{performance}'::text[], atualizado_em=now() where id='e63df174-ed5e-5eda-8e54-a1ab6613682c'::uuid;
update mind.speakers set asset_path='palestrantes/paul.webp', destaque=false, temas='{saude_mental}'::text[], atualizado_em=now() where id='64b61e92-e822-5e15-bfc0-51ad5c6222c1'::uuid;
update mind.speakers set asset_path='palestrantes/michael.webp', destaque=false, temas='{dados_bem_estar,performance}'::text[], atualizado_em=now() where id='259a137f-eb8d-5c7f-9aad-45c897c97c4d'::uuid;
update mind.speakers set asset_path='palestrantes/oscar.webp', destaque=false, temas='{dados_bem_estar}'::text[], atualizado_em=now() where id='1acd845f-c95d-5892-9d69-0b3fb8ef9be5'::uuid;
update mind.speakers set asset_path='palestrantes/gustavo.webp', destaque=false, temas='{lideranca_humana}'::text[], atualizado_em=now() where id='dd3254dd-28b1-5ffb-9ab0-f5e551ea2fac'::uuid;
update mind.speakers set asset_path='palestrantes/ana-bogus.webp', destaque=false, temas='{lideranca_humana,cultura}'::text[], atualizado_em=now() where id='0cdd10b4-8f89-5443-b381-d8031ef3296b'::uuid;
update mind.speakers set asset_path='palestrantes/mauro.webp', destaque=false, temas='{regulacao,lideranca_humana}'::text[], atualizado_em=now() where id='361d2d79-4c7a-5b1f-8bf9-7af2f5448526'::uuid;
update mind.speakers set asset_path='palestrantes/cirlene.webp', destaque=false, temas='{lideranca_humana,saude_mental}'::text[], atualizado_em=now() where id='5ea89a7a-a4d0-5384-b6b7-a2e59878baa9'::uuid;
update mind.speakers set asset_path='palestrantes/igor.webp', destaque=false, temas='{dados_bem_estar,regulacao}'::text[], atualizado_em=now() where id='309582c2-59c0-5e38-9eb2-4442d202f43c'::uuid;
update mind.speakers set asset_path='palestrantes/veruska.webp', destaque=false, temas='{seguranca_psicologica,cultura}'::text[], atualizado_em=now() where id='5202df6c-254a-5737-95b5-86280c5d3ff9'::uuid;
update mind.speakers set asset_path='palestrantes/edna.webp', destaque=false, temas='{performance}'::text[], atualizado_em=now() where id='5cb3383f-7bc5-58aa-8c61-0126e3e95637'::uuid;
update mind.speakers set asset_path='palestrantes/joao.webp', destaque=false, temas='{cultura,diversidade,felicidade}'::text[], atualizado_em=now() where id='9a99d5f1-7c04-5d85-abfc-378427622ffd'::uuid;
update mind.speakers set asset_path='palestrantes/alana.webp', destaque=false, temas='{saude_mental}'::text[], atualizado_em=now() where id='28299daa-1ea3-5b71-9410-85f2916bd052'::uuid;
update mind.speakers set asset_path='palestrantes/yuri.webp', destaque=false, temas='{dados_bem_estar,cultura}'::text[], atualizado_em=now() where id='6bdc197f-8394-5374-96a5-2d4f8ac3a75d'::uuid;
update mind.speakers set asset_path='palestrantes/fernanda.webp', destaque=false, temas='{performance}'::text[], atualizado_em=now() where id='53cf2845-a189-5681-8f25-ecc2e455ab39'::uuid;
update mind.speakers set asset_path='palestrantes/maryanna.webp', destaque=false, temas='{saude_mental,felicidade}'::text[], atualizado_em=now() where id='bdb1d875-a8ac-50bc-9148-b14cf539de13'::uuid;
update mind.speakers set asset_path='palestrantes/irene.webp', destaque=false, temas='{dados_bem_estar,saude_mental}'::text[], atualizado_em=now() where id='d4b57ffa-c08b-50ee-a715-0f0c19ac747b'::uuid;
update mind.speakers set asset_path='palestrantes/lailson.webp', destaque=false, temas='{regulacao,lideranca_humana,saude_mental}'::text[], atualizado_em=now() where id='ac2a874a-bc83-51f7-b056-c85c137412db'::uuid;
update mind.speakers set asset_path='palestrantes/michelle.webp', destaque=false, temas='{lideranca_humana,futuro_trabalho}'::text[], atualizado_em=now() where id='1b9ada35-f8fd-53a3-8331-33dd424f8a37'::uuid;
update mind.speakers set asset_path='palestrantes/daiana.webp', destaque=false, temas='{saude_mental}'::text[], atualizado_em=now() where id='29084e5d-0e27-5da1-af5d-c793d48cafa0'::uuid;
update mind.speakers set asset_path='palestrantes/ana-mocny.webp', destaque=false, temas='{lideranca_humana,cultura,performance,diversidade,futuro_trabalho}'::text[], atualizado_em=now() where id='a6e84d6f-5880-5814-b373-0470453b412d'::uuid;
update mind.speakers set asset_path='palestrantes/esabela.webp', destaque=false, temas='{regulacao,lideranca_humana,cultura,saude_mental,performance,futuro_trabalho}'::text[], atualizado_em=now() where id='5b626b9c-6a63-5d2d-9640-d2a92ed6c709'::uuid;
update mind.speakers set asset_path='palestrantes/ivana.webp', destaque=false, temas='{futuro_trabalho}'::text[], atualizado_em=now() where id='6cbdab4a-ede8-5112-827f-a3e46606cc03'::uuid;
update mind.speakers set asset_path='palestrantes/mauricio.webp', destaque=false, temas='{lideranca_humana,cultura,performance,futuro_trabalho}'::text[], atualizado_em=now() where id='4990b7e4-587f-5fc6-b982-70cdf45f40c1'::uuid;
update mind.speakers set asset_path='palestrantes/paula.webp', destaque=false, temas='{cultura}'::text[], atualizado_em=now() where id='f60ed49b-0170-5f34-a569-6a1902649edd'::uuid;
update mind.speakers set asset_path='palestrantes/caito.webp', destaque=false, temas='{cultura,futuro_trabalho}'::text[], atualizado_em=now() where id='12cbca34-8da6-5329-8bbf-7f8cd9821c7c'::uuid;

update mind.event_rules
set texto=replace(texto,'Arena LinkedIn','Arena Top Voice'),
    atualizado_em=now()
where chave='vagas_limitadas' and texto like '%Arena LinkedIn%';

create or replace function api.mindagent_bootstrap(p_event_slug text default 'mind-summit-2026')
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog','mind'
as $fn$
with ev as (
  select e.* from mind.events e where e.slug=p_event_slug and e.ativo limit 1
)
select jsonb_build_object(
  '_meta',jsonb_build_object(
    'schema_version','1.0',
    'event_slug',p_event_slug,
    'generated_at',now()
  ),
  '_nota','Dados oficiais do Supabase. Informações ausentes não devem ser inventadas.',
  'evento',(select jsonb_build_object(
    'nome',e.nome,
    'dias',e.dias,
    'local',e.local,
    'regra_reserva',(select r.texto from mind.event_rules r where r.ativo and r.chave='reserva_expira' and (r.event_id is null or r.event_id=e.id) order by r.event_id nulls last limit 1),
    'regra_vagas',(select r.texto from mind.event_rules r where r.ativo and r.chave='vagas_limitadas' and (r.event_id is null or r.event_id=e.id) order by r.event_id nulls last limit 1)
  ) from ev e),
  'temas',coalesce((
    select jsonb_agg(jsonb_build_object('codigo',t.codigo,'rotulo',t.rotulo) order by t.rotulo)
    from mind.taxonomy t where t.tipo='tema' and t.ativo
  ),'[]'::jsonb),
  'sessoes',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',coalesce(s.yazo_id,s.id::text),
      'dia',s.dia,
      'inicio',to_char(s.inicio at time zone e.fuso,'HH24:MI'),
      'fim',to_char(s.fim at time zone e.fuso,'HH24:MI'),
      'titulo',s.titulo,
      'descricao',coalesce(s.descricao,''),
      'quem',coalesce((
        select string_agg(sp.nome,'; ' order by sp.nome)
        from mind.session_speakers ss join mind.speakers sp on sp.id=ss.palestrante_id
        where ss.sessao_id=s.id
      ),'Em breve'),
      'espaco',l.nome,
      'formato',coalesce(s.tipo,s.formato,'sessao'),
      'etiqueta',coalesce(tt.rotulo,initcap(coalesce(s.tipo,s.formato,'Sessão'))),
      'trilhas',coalesce(s.trilhas,'{}'::text[]),
      'vaga_limitada',coalesce(s.precisa_reserva,false),
      'online',lower(coalesce(s.formato,'')) in ('remoto','online','virtual'),
      'temas',coalesce(s.topicos_aprendizado,'[]'::jsonb)
    ) order by s.inicio,s.titulo)
    from mind.sessions s
    join ev e on e.id=s.event_id
    left join mind.locations l on l.id=s.espaco_id
    left join mind.taxonomy tt on tt.tipo='tipo_sessao' and tt.codigo=s.tipo and tt.ativo
  ),'[]'::jsonb),
  'pessoas',coalesce((
    select jsonb_agg(jsonb_build_object(
      'nome',sp.nome,
      'credencial',concat_ws(' · ',nullif(sp.cargo,''),nullif(sp.organizacao,'')),
      'resumo',coalesce(sp.bio,''),
      'foto',sp.asset_path,
      'destaque',sp.destaque,
      'na_grade',exists(
        select 1 from mind.session_speakers ss
        join mind.sessions sx on sx.id=ss.sessao_id
        join ev e on e.id=sx.event_id
        where ss.palestrante_id=sp.id
      ),
      'temas',sp.temas
    ) order by sp.destaque desc,sp.nome)
    from mind.speakers sp
    where exists(
      select 1 from mind.session_speakers ss
      join mind.sessions sx on sx.id=ss.sessao_id
      join ev e on e.id=sx.event_id
      where ss.palestrante_id=sp.id
    )
  ),'[]'::jsonb)
);
$fn$;

revoke all on function api.mindagent_bootstrap(text) from public;
grant execute on function api.mindagent_bootstrap(text) to anon,authenticated,service_role;

create or replace function public.mindagent_bootstrap(p_event_slug text default 'mind-summit-2026')
returns jsonb
language sql
stable
security invoker
set search_path='pg_catalog','api'
as $fn$
  select api.mindagent_bootstrap(p_event_slug);
$fn$;

revoke all on function public.mindagent_bootstrap(text) from public;
grant execute on function public.mindagent_bootstrap(text) to anon,authenticated,service_role;

