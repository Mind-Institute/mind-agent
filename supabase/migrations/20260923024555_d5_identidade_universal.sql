-- ============================================================================
-- D5 — identidade universal: toda linha sobre uma pessoa nasce com pessoa_id
-- ============================================================================
-- Decisão da Adriana, 22–23/09/2026 (PROJECT_STATE v10, D5):
--
--   1. pessoas.pessoas.id é o id único e persistente de TODA pessoa, de qualquer
--      fonte. Toda tabela que fala de pessoa carrega pessoa_id. Ids de terceiros
--      (HubSpot, Yazo, credenciamento, Eduzz/Blinket, LearnWorlds, login), CPF,
--      CNPJ, e-mails e WhatsApp são IDENTIFICADORES da pessoa, em
--      engagement.identidades — nunca ids alternativos.
--   2. Resolver ou criar ANTES de escrever: toda fonte passa pela porta única
--      mind_identidade_resolver no momento da escrita (trigger before insert/
--      update). Falha de identidade não bloqueia a linha: pessoa_id fica nulo e
--      o motivo fica em pessoa_criterio.
--   3. Sem identificador determinístico forte não se cria pessoa. Nome sozinho
--      não identifica. CNPJ sozinho não identifica pessoa (é empresa).
--   4. Antes de criar qualquer pessoa: enriquecer e unificar quem já existe.
--      Toda pessoa recebe primeiro todos os identificadores que as fontes já
--      ligadas a ela conhecem. Criar antes de enriquecer é como nasceram as 586
--      duplicatas medidas em 23/09 (pessoa nascida do WhatsApp, ligada ao
--      HubSpot só pelo id do contato — sem o e-mail —, e recriada no login).
--   5. Conflito e duplicação NUNCA se resolvem sozinhos. A passada propõe
--      (padrão, quem sobrevive, quem é absorvida) e espera a decisão da Adriana,
--      por padrão inteiro ou linha a linha. A fusão preserva o id sobrevivente
--      e guarda o absorvido como apelido: nenhum id morre.
--   6. CPF é evidência de apoio, não identidade (Adriana, 23/09): muitas vezes é
--      do comprador ou do porta-voz, não da pessoa. CPF igual com e-mail,
--      WhatsApp ou nome diferente = pessoa diferente. Sozinho, nunca escolhe,
--      cria nem propõe fusão; serve para reforçar ou enfraquecer uma proposta
--      que nasceu de e-mail/WhatsApp. No credenciamento e na Yazo o CPF é o do
--      comprador (igual ao "CPF do Comprador" em 100% do export de 21/09) e
--      fica fora do mapa dessas fontes.
--   7. Na dúvida, perguntar e não unificar: aprovação em bloco só para
--      propostas de confiança alta; o resto é linha a linha.
--
-- O que já existia e é reutilizado, sem trocar de assinatura:
--   public.mind_identidade_resolver     — a única porta que escreve identidade
--   public.mind_identificadores_normalizar — ganha os canais novos
--   public.mind_conflito_registrar      — único escritor de identidade_fusoes
--   public.mind_crm_vincular_pessoa     — corrigida na causa-raiz
--   public.telefone_normalizar, institute.cpf_valido — normalização e validação
--   public.mind_admin_users / mind_admin_audit — gate de papel e auditoria
--
-- O que nasce aqui: canais cpf/cnpj/credenciamento/learnworlds; pessoa_id nas
-- tabelas-fonte; o trigger genérico; mind_pessoa_enriquecer; a fusão
-- (mind_pessoa_fundir, só via mind_fusao_decidir); pessoas.v_pessoa_360.
--
-- Idempotente: pode rodar duas vezes. Provada num Postgres 16 descartável com
-- o cenário das 586 (tests/d5_identidade_universal_local.sql).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. Vocabulário: canais novos em identidades, origens novas em pessoas
-- ----------------------------------------------------------------------------
alter table engagement.identidades drop constraint if exists identidades_canal_ck;
alter table engagement.identidades add constraint identidades_canal_ck
  check (canal = any (array['whatsapp','email','telefone','auth_user','hubspot','dispositivo',
                            'sessao_externa','yazo','eduzz','treble_session',
                            'cpf','cnpj','credenciamento','learnworlds']));

alter table pessoas.pessoas drop constraint if exists pessoas_origem_check;
alter table pessoas.pessoas add constraint pessoas_origem_check
  check (origem = any (array['hubspot','bot','manual','checkout','credenciamento','eduzz','site']));

alter table pessoas.pessoas add column if not exists fundida_em     uuid references pessoas.pessoas(id);
alter table pessoas.pessoas add column if not exists fundida_quando timestamptz;
alter table pessoas.pessoas add column if not exists enriquecida_em timestamptz;
-- Pessoa nova, por qualquer caminho, ja nasce enriquecida: o marcador nulo so
-- descreve o estoque anterior a D5, que a fase A precisa percorrer.
alter table pessoas.pessoas alter column enriquecida_em set default now();
create index if not exists pessoas_fundida_em_idx on pessoas.pessoas (fundida_em) where fundida_em is not null;

comment on table pessoas.pessoas is
  'O eixo de identidade do sistema: uma linha por pessoa, com o id que persiste (D5). Toda pessoa de qualquer fonte — HubSpot, credenciamento, Yazo, Eduzz, checkout, WhatsApp, app — existe aqui, e toda tabela que fala de pessoa aponta para este id. Os identificadores (e-mails, WhatsApp, CPF, ids de terceiros) ficam em engagement.identidades; a única porta que escreve aqui é public.mind_identidade_resolver. Não é perfil: o que sabemos SOBRE a pessoa mora em crm.* e intelligence.*. Uma pessoa absorvida por fusão continua existindo com fundida_em apontando para a sobrevivente.';
comment on column pessoas.pessoas.fundida_em is
  'Preenchido quando esta pessoa foi fundida em outra (D5): aponta para a sobrevivente. A linha fica para que o id antigo continue resolvendo — use mind_pessoa_canonica(id).';
comment on column pessoas.pessoas.fundida_quando is 'Momento da fusão.';
comment on column pessoas.pessoas.enriquecida_em is
  'Última vez que a fase A da passada D5 (mind_pessoa_enriquecer) completou esta pessoa com os identificadores das fontes já ligadas a ela. Nulo = ainda não passou nesta rodada.';

alter table engagement.identidade_fusoes add column if not exists padrao        text;
alter table engagement.identidade_fusoes add column if not exists proposta      jsonb;
alter table engagement.identidade_fusoes add column if not exists decisao       jsonb;
alter table engagement.identidade_fusoes add column if not exists resolvido_por text;
create index if not exists identidade_fusoes_padrao_idx on engagement.identidade_fusoes (padrao) where status = 'pendente';

comment on column engagement.identidade_fusoes.padrao is
  'Padrão da duplicata: mesmo_email_hubspot_x_login, mesmo_email_dois_hubspot, mesmo_email (confiança alta: podem ser aprovados em bloco), mesmo_telefone_emails_diferentes (média: linha a linha — e-mails diferentes podem ser a mesma pessoa ou não), telefone_compartilhado e nomes_divergentes (baixa: sempre linha a linha), outro. CPF nunca gera padrão sozinho; só reforça ou enfraquece a confiança.';
comment on column engagement.identidade_fusoes.proposta is
  'O que a passada propõe: {sobrevive, absorvida, padrao, motivo, confianca}. Proposta, não decisão: só mind_fusao_decidir executa.';
comment on column engagement.identidade_fusoes.decisao is 'O que a Adriana decidiu (aprovar/rejeitar), com quem e quando, e o resultado da fusão quando houve.';
comment on column engagement.identidade_fusoes.resolvido_por is 'Quem decidiu (display_name do admin ou nome informado no SQL Editor).';

-- ----------------------------------------------------------------------------
-- 1. Normalizador: os canais que a porta passa a conhecer
-- ----------------------------------------------------------------------------
-- Compatível com as chaves antigas (whatsapp/telefone/phone, email, auth_user_id,
-- hubspot_id). Novas: telefones[], emails[], hubspot_ids[], cpf, cnpj, documento
-- (decide por tamanho), yazo_id(s), credenciamento_id, eduzz_participante,
-- eduzz_comprador, learnworlds_user_id. Saída deduplicada.
create or replace function public.mind_identificadores_normalizar(p_ids jsonb)
returns jsonb
language plpgsql
immutable
as $function$
declare
  v_out  jsonb := '[]'::jsonb;
  v_tel  text;
  v_mail text;
  v_txt  text;
  v_item jsonb;
  v_doc  text;
begin
  p_ids := coalesce(p_ids, '{}'::jsonb);

  -- telefone/whatsapp: uma unica forma canonica no sistema inteiro
  for v_item in
    select x from jsonb_array_elements(
      coalesce(case when jsonb_typeof(p_ids->'telefones') = 'array' then p_ids->'telefones' end, '[]'::jsonb)
      || jsonb_build_array(coalesce(p_ids->>'whatsapp', p_ids->>'telefone', p_ids->>'phone'))) x
  loop
    v_tel := public.telefone_normalizar(nullif(btrim(coalesce(v_item #>> '{}', '')), ''));
    if v_tel is not null then
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'canal','whatsapp','identificador',v_tel,'forca',3,'verificado',true,'confianca','alta'));
    end if;
  end loop;

  -- e-mail e evidencia mais fraca: a pessoa pode digitar o de um terceiro
  for v_item in
    select x from jsonb_array_elements(
      coalesce(case when jsonb_typeof(p_ids->'emails') = 'array' then p_ids->'emails' end, '[]'::jsonb)
      || jsonb_build_array(coalesce(p_ids->>'email',''))) x
  loop
    v_mail := lower(btrim(coalesce(v_item #>> '{}', '')));
    if v_mail <> '' and v_mail ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$'
       and length(v_mail) <= 320 then
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'canal','email','identificador',v_mail,'forca',2,'verificado',false,'confianca','media'));
    end if;
  end loop;

  -- identidade autenticada: a evidencia mais forte que existe
  v_txt := btrim(coalesce(p_ids->>'auth_user_id',''));
  if v_txt ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'canal','auth_user','identificador',v_txt,'forca',4,'verificado',true,'confianca','alta'));
  end if;

  -- ids do HubSpot (um ou varios: uma pessoa pode ter mais de um contato)
  for v_item in
    select x from jsonb_array_elements(
      coalesce(case when jsonb_typeof(p_ids->'hubspot_ids') = 'array' then p_ids->'hubspot_ids' end, '[]'::jsonb)
      || jsonb_build_array(coalesce(p_ids->>'hubspot_id',''))) x
  loop
    v_txt := btrim(coalesce(v_item #>> '{}', ''));
    if v_txt <> '' and v_txt ~ '^[0-9]+$' then
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'canal','hubspot','identificador',v_txt,'forca',3,'verificado',true,'confianca','alta'));
    end if;
  end loop;

  -- CPF: 11 digitos, zeros a esquerda recuperados (planilha que virou numero),
  -- digitos verificadores conferidos. FORCA 1: e evidencia de apoio, nao
  -- identidade — muitas vezes e o CPF do comprador ou do porta-voz (Adriana,
  -- 23/09). Nunca escolhe, cria nem propoe fusao sozinho. CNPJ: 14 digitos,
  -- forca 1 — e empresa. "documento" decide pelo tamanho.
  for v_item in
    select x from jsonb_array_elements(jsonb_build_array(
      coalesce(p_ids->>'cpf',''), coalesce(p_ids->>'cnpj',''), coalesce(p_ids->>'documento',''))) x
  loop
    v_doc := regexp_replace(coalesce(v_item #>> '{}', ''), '\D', '', 'g');
    if v_doc = '' then continue; end if;
    if length(v_doc) <= 11 then
      v_doc := lpad(v_doc, 11, '0');
      if institute.cpf_valido(v_doc) then
        v_out := v_out || jsonb_build_array(jsonb_build_object(
          'canal','cpf','identificador',v_doc,'forca',1,'verificado',false,'confianca','baixa'));
      end if;
    elsif length(v_doc) = 14 and v_doc !~ '^(\d)\1{13}$' then
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'canal','cnpj','identificador',v_doc,'forca',1,'verificado',false,'confianca','baixa'));
    end if;
  end loop;

  -- ids de terceiros: cada um identifica a pessoa naquele sistema
  for v_item in
    select x from jsonb_array_elements(
      coalesce(case when jsonb_typeof(p_ids->'yazo_ids') = 'array' then p_ids->'yazo_ids' end, '[]'::jsonb)
      || jsonb_build_array(coalesce(p_ids->>'yazo_id',''))) x
  loop
    v_txt := btrim(coalesce(v_item #>> '{}', ''));
    if v_txt ~ '^[0-9]+$' then
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'canal','yazo','identificador',v_txt,'forca',3,'verificado',true,'confianca','alta'));
    end if;
  end loop;

  v_txt := btrim(coalesce(p_ids->>'credenciamento_id',''));
  if v_txt ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'canal','credenciamento','identificador',v_txt,'forca',3,'verificado',true,'confianca','alta'));
  end if;

  for v_item in
    select x from jsonb_array_elements(jsonb_build_array(
      coalesce(p_ids->>'eduzz_participante',''), coalesce(p_ids->>'eduzz_comprador',''))) x
  loop
    v_txt := btrim(coalesce(v_item #>> '{}', ''));
    if v_txt <> '' and v_txt ~ '^[0-9A-Za-z_-]{1,64}$' then
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'canal','eduzz','identificador',v_txt,'forca',3,'verificado',true,'confianca','alta'));
    end if;
  end loop;

  v_txt := btrim(coalesce(p_ids->>'learnworlds_user_id',''));
  if v_txt <> '' and length(v_txt) <= 128 then
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'canal','learnworlds','identificador',v_txt,'forca',3,'verificado',true,'confianca','alta'));
  end if;

  -- deduplica (canal, identificador), preservando a primeira ocorrencia
  select coalesce(jsonb_agg(x order by ord), '[]'::jsonb) into v_out
  from (
    select distinct on (x->>'canal', x->>'identificador') x, ord
    from jsonb_array_elements(v_out) with ordinality as e(x, ord)
    order by x->>'canal', x->>'identificador', ord
  ) d;
  return v_out;
end $function$;

comment on function public.mind_identificadores_normalizar(jsonb) is
  'Normaliza os identificadores de uma entrada e atribui força: auth_user 4; whatsapp, hubspot, yazo, credenciamento, eduzz, learnworlds 3; email 2; cpf e cnpj 1 (evidência de apoio: nunca decidem pessoa sozinhos — o CPF é muitas vezes do comprador). Aceita as chaves antigas (whatsapp/telefone/phone, email, auth_user_id, hubspot_id) e as novas (telefones[], emails[], hubspot_ids[], cpf, cnpj, documento, yazo_id(s), credenciamento_id, eduzz_participante, eduzz_comprador, learnworlds_user_id). CPF recebe lpad para 11 dígitos — planilha que virou número perde o zero à esquerda — e só entra se os dígitos verificadores fecharem.';

-- ----------------------------------------------------------------------------
-- 2. Proposta de fusão: padrão + quem sobrevive. Proposta, não decisão.
-- ----------------------------------------------------------------------------
create or replace function public.mind_fusao_propor(p_a uuid, p_b uuid, p_canal_conflito text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, engagement, pessoas
as $function$
declare
  ca text[]; cb text[]; na text; nb text; n_a int; n_b int; c_a timestamptz; c_b timestamptz;
  v_padrao text; v_sob uuid; v_abs uuid; v_conf text; v_motivo text; v_tel_pessoas int := 0;
  v_prop jsonb; cpf_a text; cpf_b text; v_nota text := '';
begin
  if p_a is null or p_b is null or p_a = p_b then return null; end if;
  -- CPF nunca abre proposta sozinho (Adriana, 23/09): CPF igual com e-mail,
  -- WhatsApp ou nome diferente e pessoa diferente. Ele so reforca ou enfraquece.
  if p_canal_conflito in ('cpf','cnpj') then return null; end if;

  select coalesce(array_agg(distinct canal), '{}'), count(*) into ca, n_a from engagement.identidades where pessoa_id = p_a;
  select coalesce(array_agg(distinct canal), '{}'), count(*) into cb, n_b from engagement.identidades where pessoa_id = p_b;
  select lower(coalesce(primeiro_nome,'')), criado_em into na, c_a from pessoas.pessoas where id = p_a;
  select lower(coalesce(primeiro_nome,'')), criado_em into nb, c_b from pessoas.pessoas where id = p_b;
  select identificador into cpf_a from engagement.identidades where pessoa_id = p_a and canal = 'cpf' limit 1;
  select identificador into cpf_b from engagement.identidades where pessoa_id = p_b and canal = 'cpf' limit 1;

  if p_canal_conflito = 'whatsapp' then
    select count(distinct i.pessoa_id) into v_tel_pessoas
      from engagement.identidades i
     where i.canal = 'whatsapp'
       and i.identificador in (select identificador from engagement.identidades where pessoa_id in (p_a, p_b) and canal = 'whatsapp');
  end if;

  v_padrao := case
    when na <> '' and nb <> '' and na <> nb then 'nomes_divergentes'
    when p_canal_conflito = 'email'
         and (('hubspot' = any(ca) and not 'auth_user' = any(ca) and 'auth_user' = any(cb))
           or ('hubspot' = any(cb) and not 'auth_user' = any(cb) and 'auth_user' = any(ca))) then 'mesmo_email_hubspot_x_login'
    when p_canal_conflito = 'email' and 'hubspot' = any(ca) and 'hubspot' = any(cb) then 'mesmo_email_dois_hubspot'
    when p_canal_conflito = 'email' then 'mesmo_email'
    when p_canal_conflito = 'whatsapp' and v_tel_pessoas > 2 then 'telefone_compartilhado'
    when p_canal_conflito = 'whatsapp' then 'mesmo_telefone_emails_diferentes'
    else 'outro' end;

  -- quem sobrevive: quem tem login no app; depois quem tem mais identificadores; depois a mais antiga
  if 'auth_user' = any(ca) and not 'auth_user' = any(cb) then v_sob := p_a;
  elsif 'auth_user' = any(cb) and not 'auth_user' = any(ca) then v_sob := p_b;
  elsif n_a > n_b then v_sob := p_a;
  elsif n_b > n_a then v_sob := p_b;
  elsif c_a <= c_b then v_sob := p_a;
  else v_sob := p_b; end if;
  v_abs := case when v_sob = p_a then p_b else p_a end;

  v_conf := case v_padrao
    when 'mesmo_email_hubspot_x_login' then 'alta'
    when 'mesmo_email_dois_hubspot' then 'alta'
    when 'mesmo_email' then 'alta'
    when 'mesmo_telefone_emails_diferentes' then 'media'
    else 'baixa' end;
  v_motivo := case v_padrao
    when 'mesmo_email_hubspot_x_login' then 'mesmo e-mail: uma pessoa nasceu do WhatsApp/HubSpot sem e-mail registrado, a outra do login no app; sobrevive quem tem login'
    when 'mesmo_email_dois_hubspot' then 'mesmo e-mail em duas pessoas, ambas ligadas ao HubSpot (dois contatos para a mesma pessoa)'
    when 'mesmo_email' then 'mesmo e-mail em duas pessoas'
    when 'mesmo_telefone_emails_diferentes' then 'mesmo telefone com e-mails diferentes: pode ser a mesma pessoa com dois e-mails, ou casal/empresa — caso a caso'
    when 'telefone_compartilhado' then 'telefone em mais de duas pessoas (central/empresa): nunca aprovar em bloco'
    when 'nomes_divergentes' then 'primeiros nomes diferentes: decidir linha a linha'
    else 'identificador em comum sem padrão conhecido' end;

  -- CPF e nome so reforcam ou enfraquecem: nunca decidem
  if cpf_a is not null and cpf_b is not null and cpf_a <> cpf_b then
    v_conf := 'baixa'; v_nota := v_nota || '; CPFs diferentes nas duas pessoas: conferir';
  elsif cpf_a is not null and cpf_a = cpf_b then
    v_nota := v_nota || '; mesmo CPF nas duas';
  end if;
  if na <> '' and na = nb then v_nota := v_nota || '; mesmo primeiro nome'; end if;
  v_motivo := v_motivo || v_nota;

  v_prop := jsonb_build_object('sobrevive', v_sob, 'absorvida', v_abs, 'padrao', v_padrao,
                               'motivo', v_motivo, 'confianca', v_conf, 'canal', p_canal_conflito,
                               'cpf_igual', (cpf_a is not null and cpf_a = cpf_b), 'nome_igual', (na <> '' and na = nb));

  update engagement.identidade_fusoes f
     set padrao = v_padrao, proposta = v_prop
   where f.status = 'pendente'
     and f.participante_origem is not null
     and least(f.participante_id, f.participante_origem) = least(p_a, p_b)
     and greatest(f.participante_id, f.participante_origem) = greatest(p_a, p_b);
  return v_prop;
end $function$;

revoke all on function public.mind_fusao_propor(uuid, uuid, text) from public;
comment on function public.mind_fusao_propor(uuid, uuid, text) is
  'Dado um par de pessoas que compartilham um identificador, classifica o padrão da duplicata e propõe quem sobrevive (login no app > mais identificadores > mais antiga). Só grava a proposta na pendência já registrada em identidade_fusoes. Não funde: isso é mind_fusao_decidir.';

-- ----------------------------------------------------------------------------
-- 3. A porta única, com cinco mudanças cirúrgicas
-- ----------------------------------------------------------------------------
--   a. só cria pessoa se houver identificador com força >= 2 (CPF/CNPJ sozinhos não criam);
--   b. completa sobrenome nulo, não só primeiro nome;
--   c. todo conflito registrado ganha proposta (mind_fusao_propor);
--   d. origem da pessoa nova segue o canal de entrada (tabela-fonte), não sempre 'bot';
--   e. p_criar=false liga sem criar (o trigger usa isso enquanto a fase A não terminou).
-- A assinatura ganha um parametro com default: a antiga sai para nao haver duas
-- funcoes ambiguas. Os chamadores (mind_inbound, treble_*, mindagent_chat_bind_identity,
-- mind_crm_vincular_pessoa, pessoa_vincular_hubspot) resolvem pelo nome em tempo de
-- execucao e continuam valendo. Tudo o mais e o codigo vivo de 23/09, intacto.
drop function if exists public.mind_identidade_resolver(jsonb, text, text, uuid);
create or replace function public.mind_identidade_resolver(
  p_identificadores jsonb, p_nome text default null, p_canal text default null, p_pessoa_ancora uuid default null,
  p_criar boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, engagement, pessoas
as $function$
declare
  v_ids       jsonb := public.mind_identificadores_normalizar(p_identificadores);
  v_item      jsonb;
  v_achados   jsonb := '[]'::jsonb;
  v_pessoa    uuid;
  v_outro     uuid;
  v_criada    boolean := false;
  v_conflito  jsonb := null;
  v_nome      text := nullif(left(btrim(coalesce(p_nome,'')),160),'');
  v_primeiro  text;
  v_sobrenome text;
  v_tel       text;
  v_mail      text;
  v_dono      uuid;
  v_vinculadas jsonb := '[]'::jsonb;
  v_origem    text;
  v_canal_conf text;
begin
  if jsonb_array_length(v_ids) = 0 then
    return jsonb_build_object('pessoa_id', p_pessoa_ancora, 'criada', false,
      'motivo','sem_identificador_deterministico', 'conflito', null,
      'ancorada', p_pessoa_ancora is not null, 'identidades', '[]'::jsonb);
  end if;

  -- Serializa somente entradas que compartilham o mesmo identificador.
  for v_item in
    select x.value from jsonb_array_elements(v_ids) as x(value)
     order by x.value->>'canal', x.value->>'identificador'
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('mind_identidade:' || (v_item->>'canal') || ':' || (v_item->>'identificador'), 0));
  end loop;

  for v_item in select * from jsonb_array_elements(v_ids) loop
    select i.pessoa_id into v_outro
      from engagement.identidades i
     where i.canal = v_item->>'canal' and i.identificador = v_item->>'identificador'
     limit 1;
    if v_outro is not null then
      v_achados := v_achados || jsonb_build_array(jsonb_build_object(
        'pessoa_id', v_outro, 'forca', (v_item->>'forca')::int, 'canal', v_item->>'canal'));
    end if;
  end loop;

  -- D5: so evidencia forte (forca >= 2) escolhe pessoa ou abre conflito. CPF e
  -- CNPJ (forca 1) sao apoio: se ja pertencem a outra pessoa, ficam la, em silencio.
  if p_pessoa_ancora is not null then
    v_pessoa := p_pessoa_ancora;          -- a conversa (ou a pessoa sendo enriquecida) manda
  else
    select a.pessoa_id into v_pessoa
      from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text)
      join pessoas.pessoas p on p.id = a.pessoa_id
     where a.forca >= 2
     order by a.forca desc, (a.canal = p_canal) desc, p.criado_em asc
     limit 1;
  end if;

  if exists (select 1 from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text)
              where v_pessoa is not null and a.pessoa_id <> v_pessoa and a.forca >= 2) then
    v_conflito := jsonb_build_object('pessoa_escolhida', v_pessoa,
                                     'ancorada', p_pessoa_ancora is not null,
                                     'evidencias', v_achados);
    for v_outro in
      select distinct a.pessoa_id
        from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text)
       where a.pessoa_id <> v_pessoa and a.forca >= 2
    loop
      perform public.mind_conflito_registrar(
        v_pessoa, 'conflito_identidade',
        case when p_pessoa_ancora is not null
             then 'evidencia nova aponta para outra pessoa; conversa ancorada permanece'
             else 'identificadores da mesma entrada apontam para pessoas diferentes' end,
        v_outro, v_ids);
      -- D5: todo conflito nasce com padrão e proposta, para a Adriana decidir em bloco
      select a.canal into v_canal_conf
        from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text)
       where a.pessoa_id = v_outro and a.forca >= 2
       order by a.forca desc limit 1;
      perform public.mind_fusao_propor(v_pessoa, v_outro, v_canal_conf);
    end loop;
  end if;

  if v_pessoa is null then
    -- D5: sem identificador forte (força >= 2) não se cria pessoa
    if not exists (select 1 from jsonb_array_elements(v_ids) x where (x->>'forca')::int >= 2) then
      return jsonb_build_object('pessoa_id', null, 'criada', false,
        'motivo','sem_identificador_forte', 'conflito', null,
        'ancorada', false, 'identidades', '[]'::jsonb);
    end if;
    -- D5: quem chamou pediu para ligar sem criar (fase A ainda não terminou)
    if not p_criar then
      return jsonb_build_object('pessoa_id', null, 'criada', false,
        'motivo','criacao_desligada', 'conflito', null,
        'ancorada', false, 'identidades', '[]'::jsonb);
    end if;

    v_primeiro  := nullif(split_part(coalesce(v_nome,''), ' ', 1), '');
    v_sobrenome := nullif(btrim(substr(coalesce(v_nome,''), coalesce(length(v_primeiro),0) + 2)), '');
    v_tel  := (select x->>'identificador' from jsonb_array_elements(v_ids) x where x->>'canal'='whatsapp' limit 1);
    v_mail := (select x->>'identificador' from jsonb_array_elements(v_ids) x where x->>'canal'='email'    limit 1);

    if v_mail is not null and exists (select 1 from pessoas.pessoas p where lower(p.email) = v_mail)
      then v_mail := null; end if;
    if v_tel is not null and exists (select 1 from pessoas.pessoas p where p.whatsapp = v_tel)
      then v_tel := null; end if;

    v_origem := case
      when p_canal in ('contato_espelho','hubspot') then 'hubspot'
      when p_canal in ('pedidos','compradores','checkout') then 'checkout'
      when p_canal in ('participantes','yazo_espelho','credenciamento') or p_canal ilike 'relatorio%' or p_canal ilike 'yazo%' then 'credenciamento'
      when p_canal in ('ingressos','vendas','eduzz') then 'eduzz'
      when p_canal in ('leads_capturados','site') then 'site'
      else 'bot' end;

    -- nasce ja enriquecida: veio com tudo que a entrada sabia dela
    insert into pessoas.pessoas (primeiro_nome, sobrenome, whatsapp, email, origem, enriquecida_em)
    values (v_primeiro, v_sobrenome, v_tel, v_mail, v_origem, now())
    returning id into v_pessoa;
    v_criada := true;
  elsif v_nome is not null then
    v_primeiro  := nullif(split_part(v_nome, ' ', 1), '');
    v_sobrenome := nullif(btrim(substr(v_nome, coalesce(length(v_primeiro),0) + 2)), '');
    update pessoas.pessoas
       set primeiro_nome = coalesce(primeiro_nome, v_primeiro),
           sobrenome     = coalesce(sobrenome, v_sobrenome),
           atualizado_em = now()
     where id = v_pessoa and (primeiro_nome is null or sobrenome is null);
  end if;

  for v_item in select * from jsonb_array_elements(v_ids) loop
    select i.pessoa_id into v_dono
      from engagement.identidades i
     where i.canal = v_item->>'canal' and i.identificador = v_item->>'identificador';
    if v_dono is null then
      insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca)
      values (v_pessoa, v_item->>'canal', v_item->>'identificador',
              (v_item->>'verificado')::boolean, v_item->>'confianca')
      on conflict (canal, identificador) do nothing;
      v_vinculadas := v_vinculadas || jsonb_build_array(v_item);

      if v_item->>'canal' = 'email' then
        update pessoas.pessoas p set email = v_item->>'identificador', atualizado_em = now()
         where p.id = v_pessoa and p.email is null
           and not exists (select 1 from pessoas.pessoas q where lower(q.email) = v_item->>'identificador');
      elsif v_item->>'canal' = 'whatsapp' then
        update pessoas.pessoas p set whatsapp = v_item->>'identificador', atualizado_em = now()
         where p.id = v_pessoa and p.whatsapp is null
           and not exists (select 1 from pessoas.pessoas q where q.whatsapp = v_item->>'identificador');
      elsif v_item->>'canal' = 'hubspot' then
        update pessoas.pessoas p set hubspot_id = v_item->>'identificador', atualizado_em = now()
         where p.id = v_pessoa and p.hubspot_id is null
           and not exists (select 1 from pessoas.pessoas q where q.hubspot_id = v_item->>'identificador');
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'pessoa_id', v_pessoa, 'criada', v_criada, 'conflito', v_conflito,
    'ancorada', p_pessoa_ancora is not null, 'identidades', v_vinculadas);
end $function$;

-- Assinatura nova = privilegios novos: sem isto o Postgres daria EXECUTE a PUBLIC e a
-- porta de identidade ficaria chamavel por anon via PostgREST. Espelha os grants da
-- funcao antiga (postgres como dona, service_role).
revoke all on function public.mind_identidade_resolver(jsonb, text, text, uuid, boolean) from public;
grant execute on function public.mind_identidade_resolver(jsonb, text, text, uuid, boolean) to service_role;
comment on function public.mind_identidade_resolver(jsonb, text, text, uuid, boolean) is
  'A única porta que escreve identidade. Normaliza os identificadores, procura em engagement.identidades, escolhe a pessoa pela força da evidência (ou pela âncora, quando há), cria a pessoa quando não acha e existe identificador forte (e p_criar permite), registra conflito com proposta quando identificadores fortes apontam para pessoas diferentes — e nunca funde. CPF/CNPJ (força 1) são apoio: não escolhem, não criam, não abrem conflito. D5: toda fonte passa por aqui antes de escrever (trigger mind_pessoa_antes_de_escrever).';

-- ----------------------------------------------------------------------------
-- 4. Causa-raiz das 586: ligar um contato do CRM à pessoa passa a trazer o
--    e-mail, os telefones e o nome do contato — não só o id do HubSpot.
-- ----------------------------------------------------------------------------
create or replace function public.mind_crm_vincular_pessoa(p_pessoa_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, engagement, pessoas, crm
as $function$
declare
  v_hub    text[];
  v_mail   text[];
  v_tel10  text[];
  v_tel_ok text[] := array[]::text[];   -- telefones que identificam 1 contato so
  t        text;
  v_n      int;
  v_hubs   text[];
  v_amb    jsonb := '[]'::jsonb;        -- evidencia dos telefones ambiguos
  c        record;
  v_r      jsonb;
  v_vinc   int := 0;
  v_ja     int := 0;
  v_conf   int := 0;
  v_ident  int := 0;
  v_lista  jsonb := '[]'::jsonb;
begin
  if p_pessoa_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa');
  end if;

  select array_agg(i.identificador) filter (where i.canal = 'hubspot'),
         array_agg(i.identificador) filter (where i.canal = 'email'),
         array_agg(right(i.identificador, 10)) filter
           (where i.canal in ('whatsapp','telefone') and length(i.identificador) >= 10)
    into v_hub, v_mail, v_tel10
  from engagement.identidades i
  where i.pessoa_id = p_pessoa_id;

  if v_tel10 is not null then
    foreach t in array v_tel10 loop
      select count(*), array_agg(e.hubspot_id)
        into v_n, v_hubs
        from crm.contato_espelho e
       where (length(regexp_replace(coalesce(e.phone,''), '\D','','g')) >= 10
              and right(regexp_replace(coalesce(e.phone,''), '\D','','g'), 10) = t)
          or (length(regexp_replace(coalesce(e.hs_whatsapp_phone_number,''), '\D','','g')) >= 10
              and right(regexp_replace(coalesce(e.hs_whatsapp_phone_number,''), '\D','','g'), 10) = t);

      if v_n = 1 then
        v_tel_ok := v_tel_ok || t;
      elsif v_n > 1 then
        v_amb := v_amb || jsonb_build_array(jsonb_build_object(
          'telefone', t, 'contatos', v_n, 'hubspot_ids', to_jsonb(v_hubs)));
      end if;
    end loop;

    if jsonb_array_length(v_amb) > 0 then
      perform public.mind_conflito_registrar(
        p_pessoa_id, 'suspeita_sobre_merge',
        'telefone compartilhado por varios contatos do CRM; nao vincula por telefone',
        null,
        jsonb_build_object('telefones_ambiguos', v_amb));
    end if;
  end if;

  if v_hub is null and v_mail is null and coalesce(array_length(v_tel_ok,1),0) = 0 then
    return jsonb_build_object('ok', true, 'motivo', 'sem_identificador_utilizavel',
      'telefones_ambiguos', v_amb, 'contatos', '[]'::jsonb);
  end if;

  for c in
    select e.id, e.hubspot_id, e.pessoa_id, e.email, e.phone, e.hs_whatsapp_phone_number, e.firstname, e.lastname,
           case
             when v_hub  is not null and e.hubspot_id = any(v_hub) then 'hubspot_id'
             when v_mail is not null and lower(btrim(coalesce(e.email,''))) = any(v_mail) then 'email'
             else 'telefone'
           end as via
      from crm.contato_espelho e
     where (v_hub  is not null and e.hubspot_id = any(v_hub))
        or (v_mail is not null and lower(btrim(coalesce(e.email,''))) = any(v_mail))
        or (coalesce(array_length(v_tel_ok,1),0) > 0
            and ((length(regexp_replace(coalesce(e.phone,''), '\D','','g')) >= 10
                  and right(regexp_replace(coalesce(e.phone,''), '\D','','g'), 10) = any(v_tel_ok))
              or (length(regexp_replace(coalesce(e.hs_whatsapp_phone_number,''), '\D','','g')) >= 10
                  and right(regexp_replace(coalesce(e.hs_whatsapp_phone_number,''), '\D','','g'), 10) = any(v_tel_ok))))
  loop
    if c.pessoa_id = p_pessoa_id then
      v_ja := v_ja + 1;

    elsif c.pessoa_id is null then
      update crm.contato_espelho set pessoa_id = p_pessoa_id, atualizado_em = now()
       where id = c.id;
      v_vinc := v_vinc + 1;

    else
      perform public.mind_conflito_registrar(
        p_pessoa_id, 'contato_crm_de_outra_pessoa',
        'contato do CRM ja pertence a outra pessoa', c.pessoa_id,
        jsonb_build_object('hubspot_id', c.hubspot_id, 'contato_espelho_id', c.id, 'via', c.via));
      perform public.mind_fusao_propor(p_pessoa_id, c.pessoa_id, c.via);
      v_conf := v_conf + 1;
      v_lista := v_lista || jsonb_build_array(jsonb_build_object(
        'hubspot_id', c.hubspot_id, 'situacao', 'conflito', 'via', c.via, 'dono', c.pessoa_id));
      continue;
    end if;

    -- D5 (causa-raiz das 586): o contato inteiro vira identidade da pessoa, ancorado.
    -- Antes so o hubspot_id entrava; o e-mail ficava no espelho e a pessoa nascia de
    -- novo no proximo login. Ancorado, a porta nunca cria: acrescenta o que esta
    -- livre e registra conflito (com proposta) para o que ja e de outra pessoa.
    if nullif(btrim(coalesce(c.hubspot_id,'')),'') is not null then
      v_r := public.mind_identidade_resolver(
        jsonb_build_object(
          'hubspot_id', c.hubspot_id,
          'emails', jsonb_build_array(coalesce(c.email,'')),
          'telefones', jsonb_build_array(coalesce(c.phone,''), coalesce(c.hs_whatsapp_phone_number,''))),
        nullif(btrim(concat_ws(' ', c.firstname, c.lastname)), ''),
        'hubspot', p_pessoa_id);
      if jsonb_array_length(coalesce(v_r->'identidades','[]'::jsonb)) > 0 then
        v_ident := v_ident + 1;
      end if;
    end if;

    v_lista := v_lista || jsonb_build_array(jsonb_build_object(
      'hubspot_id', c.hubspot_id, 'via', c.via,
      'situacao', case when c.pessoa_id is null then 'vinculado' else 'ja_ligado' end));
  end loop;

  return jsonb_build_object(
    'ok', true, 'pessoa_id', p_pessoa_id,
    'contatos_vinculados', v_vinc, 'contatos_ja_ligados', v_ja,
    'conflitos', v_conf, 'identidades_hubspot_novas', v_ident,
    'telefones_ambiguos', v_amb, 'contatos', v_lista);
end $function$;

comment on function public.mind_crm_vincular_pessoa(uuid) is
  'Único escritor de crm.contato_espelho.pessoa_id. Liga a pessoa aos contatos do HubSpot por hubspot_id, e-mail ou telefone inequívoco. D5 (23/09): ao ligar, registra na pessoa o e-mail, os telefones e o nome do contato — antes só entrava o id do HubSpot, e a pessoa renascia no próximo login (586 duplicatas).';

-- ----------------------------------------------------------------------------
-- 5. O trigger genérico: resolver ou criar ANTES de escrever
-- ----------------------------------------------------------------------------
-- TG_ARGV[0] é um mapa jsonb de chave do normalizador -> coluna(s) da tabela:
--   {"emails":["email"], "telefones":["telefone_norm"], "cpf":"cpf",
--    "credenciamento_id":"id", "yazo_id":"yazo_user_id", "nome":["name"]}
-- Valores aninhados: "attributes.cpf" lê NEW.attributes->>'cpf'; um objeto
-- {"value": ...} devolve o value (cellphone da Yazo).
-- Lê um valor da linha (to_jsonb(NEW)) pelo nome da coluna; "attributes.cpf"
-- entra no jsonb; um objeto {"value": ...} devolve o value (cellphone da Yazo).
create or replace function public.mind_pessoa_ler_valor(p_linha jsonb, p_col text)
returns text
language plpgsql
immutable
as $function$
declare v jsonb; v_base text; v_chave text;
begin
  if position('.' in p_col) > 0 then
    v_base := split_part(p_col, '.', 1); v_chave := substr(p_col, length(v_base) + 2);
    v := p_linha->v_base;
    if v is null or jsonb_typeof(v) <> 'object' then return null; end if;
    v := v->v_chave;
  else
    v := p_linha->p_col;
  end if;
  if v is null or jsonb_typeof(v) = 'null' then return null; end if;
  if jsonb_typeof(v) = 'object' then return v->>'value'; end if;
  return v #>> '{}';
end $function$;
revoke all on function public.mind_pessoa_ler_valor(jsonb, text) from public;
comment on function public.mind_pessoa_ler_valor(jsonb, text) is 'Apoio do trigger D5: lê uma coluna (ou um campo de jsonb, "coluna.campo") da linha serializada.';

create or replace function public.mind_pessoa_antes_de_escrever()
returns trigger
language plpgsql
security definer
set search_path = public, engagement, pessoas
as $function$
declare
  v_map   jsonb := coalesce(nullif(TG_ARGV[0], '')::jsonb, '{}'::jsonb);
  v_new   jsonb := to_jsonb(NEW);
  v_old   jsonb := case when TG_OP = 'UPDATE' then to_jsonb(OLD) else null end;
  v_ids   jsonb := '{}'::jsonb;
  v_nome  text;
  v_r     jsonb;
  v_k     text;
  v_cols  jsonb;
  v_col   text;
  v_val   text;
  v_vals  jsonb;
  v_mudou boolean := (TG_OP = 'INSERT');
  v_norm  jsonb;
  v_criar boolean;
begin
  -- monta os identificadores a partir do mapa
  for v_k, v_cols in select key, value from jsonb_each(v_map) loop
    if jsonb_typeof(v_cols) <> 'array' then v_cols := jsonb_build_array(v_cols); end if;
    v_vals := '[]'::jsonb;
    for v_col in select x #>> '{}' from jsonb_array_elements(v_cols) x loop
      v_val := public.mind_pessoa_ler_valor(v_new, v_col);
      if v_val is not null and btrim(v_val) <> '' then v_vals := v_vals || jsonb_build_array(v_val); end if;
      if v_old is not null and v_val is distinct from public.mind_pessoa_ler_valor(v_old, v_col) then v_mudou := true; end if;
    end loop;
    if jsonb_array_length(v_vals) = 0 then continue; end if;
    if v_k = 'nome' then
      select string_agg(x #>> '{}', ' ') into v_nome from jsonb_array_elements(v_vals) x;
    elsif v_k in ('emails','telefones','hubspot_ids','yazo_ids') then
      v_ids := v_ids || jsonb_build_object(v_k, v_vals);
    else
      v_ids := v_ids || jsonb_build_object(v_k, v_vals->>0);
    end if;
  end loop;

  -- update que nao mexeu em identificador e ja tem pessoa: nao repete a porta
  if not v_mudou and NEW.pessoa_id is not null then
    return NEW;
  end if;

  begin
    -- Enriquecer e unificar ANTES de criar (regra 4): enquanto houver pessoa que a
    -- fase A ainda nao passou, a porta so liga — nao cria. Sem isso, o sync do
    -- HubSpot (cron) criaria pessoas no intervalo entre a migration e a passada,
    -- repetindo a causa das 586. Pessoa nova nasce com enriquecida_em preenchido.
    v_criar := not exists (select 1 from pessoas.pessoas where enriquecida_em is null and fundida_em is null);
    v_r := public.mind_identidade_resolver(v_ids, v_nome, TG_TABLE_NAME::text, null, v_criar);
    NEW.pessoa_id := (v_r->>'pessoa_id')::uuid;
    NEW.pessoa_resolvido_em := now();
    if NEW.pessoa_id is null then
      NEW.pessoa_criterio := case when v_r->>'motivo' = 'criacao_desligada' then 'aguardando_fase_a' else coalesce(v_r->>'motivo', 'sem_pessoa') end;
    else
      v_norm := public.mind_identificadores_normalizar(v_ids);
      select coalesce(string_agg(distinct i.canal, ',' order by i.canal), 'ancora')
        into NEW.pessoa_criterio
        from engagement.identidades i
        join jsonb_array_elements(v_norm) x on x->>'canal' = i.canal and x->>'identificador' = i.identificador
       where i.pessoa_id = NEW.pessoa_id;
      if (v_r->>'criada')::boolean then NEW.pessoa_criterio := NEW.pessoa_criterio || ' (criada)'; end if;
      if v_r->'conflito' is not null and jsonb_typeof(v_r->'conflito') <> 'null' then
        NEW.pessoa_criterio := NEW.pessoa_criterio || ' (conflito)';
      end if;
    end if;
  exception when others then
    -- identidade nunca bloqueia a escrita: a linha entra, o motivo fica visivel
    NEW.pessoa_criterio := 'erro: ' || left(sqlerrm, 200);
    NEW.pessoa_resolvido_em := now();
  end;
  return NEW;
end $function$;

revoke all on function public.mind_pessoa_antes_de_escrever() from public;
comment on function public.mind_pessoa_antes_de_escrever() is
  'Trigger BEFORE INSERT OR UPDATE das tabelas que falam de pessoa (D5). Lê os identificadores da linha pelo mapa em TG_ARGV[0], passa pela porta única mind_identidade_resolver e preenche pessoa_id, pessoa_criterio (quais canais casaram; "(criada)" quando a pessoa nasceu aqui; "aguardando_fase_a" quando a criação ainda está travada) e pessoa_resolvido_em. Só cria pessoa quando nenhuma pessoa existente está por enriquecer (enriquecida_em nulo): enriquecer e unificar antes de criar. Falha de identidade não bloqueia a escrita. Update que não mexe em identificador não repete a porta.';

-- Indices por expressao: o enriquecimento e o trigger procuram telefone e e-mail
-- normalizados nas fontes; sem isto cada pessoa varreria 13 mil contatos.
create index if not exists contato_espelho_telefone_norm_idx on crm.contato_espelho (public.telefone_normalizar(phone)) where phone is not null;
create index if not exists contato_espelho_whatsapp_norm_idx on crm.contato_espelho (public.telefone_normalizar(hs_whatsapp_phone_number)) where hs_whatsapp_phone_number is not null;
create index if not exists contato_espelho_email_lower_idx   on crm.contato_espelho (lower(btrim(email))) where email is not null;
create index if not exists participantes_email_lower_idx     on credenciamento_summit_2026.participantes (lower(btrim(email))) where email is not null;
create index if not exists participantes_telefone_norm_idx   on credenciamento_summit_2026.participantes (telefone_norm) where telefone_norm is not null;
create index if not exists participantes_yazo_user_id_idx    on credenciamento_summit_2026.participantes (yazo_user_id) where yazo_user_id is not null;
create index if not exists yazo_espelho_telefone_norm_idx    on credenciamento_summit_2026.yazo_espelho
  (public.telefone_normalizar(case when jsonb_typeof(attributes->'cellphone') = 'object' then attributes->'cellphone'->>'value' else attributes->>'cellphone' end));
create index if not exists ingressos_email_lower_idx         on eduzz.ingressos (lower(btrim(email))) where email is not null;
create index if not exists ingressos_telefone_norm_idx       on eduzz.ingressos (telefone_norm) where telefone_norm is not null;
create index if not exists ingressos_cod_participante_idx    on eduzz.ingressos (cod_participante) where cod_participante is not null;
create index if not exists vendas_cliente_email_lower_idx    on eduzz.vendas (lower(btrim(cliente_email))) where cliente_email is not null;
create index if not exists vendas_cliente_telefone_norm_idx  on eduzz.vendas (cliente_telefone_norm) where cliente_telefone_norm is not null;

-- Liga a regra a uma tabela: colunas + trigger, numa chamada. E como uma tabela
-- nova de pessoa (um relatorio da Yazo que a Adriana subir, por exemplo) entra
-- na regra sem escrever DDL a mao.
create or replace function public.mind_pessoa_ligar_tabela(p_tabela regclass, p_mapa jsonb)
returns text
language plpgsql
security definer
set search_path = public
as $function$
declare v_sch text; v_tab text; v_q text;
begin
  select n.nspname, c.relname into v_sch, v_tab
    from pg_class c join pg_namespace n on n.oid = c.relnamespace where c.oid = p_tabela;
  v_q := format('%I.%I', v_sch, v_tab);
  execute format('alter table %s add column if not exists pessoa_id uuid references pessoas.pessoas(id)', v_q);
  execute format('alter table %s add column if not exists pessoa_criterio text', v_q);
  execute format('alter table %s add column if not exists pessoa_resolvido_em timestamptz', v_q);
  execute format('create index if not exists %I on %s (pessoa_id) where pessoa_id is not null',
                 left(v_tab, 40) || '_pessoa_id_idx', v_q);
  execute format('comment on column %s.pessoa_id is %L', v_q,
    'D5: a pessoa desta linha, resolvida ou criada pela porta única (mind_identidade_resolver) antes da escrita. Nulo = sem identificador forte ou erro; ver pessoa_criterio.');
  execute format('comment on column %s.pessoa_criterio is %L', v_q,
    'Como a pessoa foi encontrada: canais que casaram (email, whatsapp, cpf, hubspot…), "(criada)" quando nasceu nesta linha, "(conflito)" quando havia mais de uma candidata, ou o motivo de não ter pessoa.');
  execute format('comment on column %s.pessoa_resolvido_em is %L', v_q, 'Quando a porta única resolveu esta linha pela última vez.');
  execute format('drop trigger if exists zz_d5_pessoa_antes_de_escrever on %s', v_q);
  execute format('create trigger zz_d5_pessoa_antes_de_escrever before insert or update on %s for each row execute function public.mind_pessoa_antes_de_escrever(%L)',
                 v_q, p_mapa::text);
  return v_q;
end $function$;

revoke all on function public.mind_pessoa_ligar_tabela(regclass, jsonb) from public;
comment on function public.mind_pessoa_ligar_tabela(regclass, jsonb) is
  'Coloca uma tabela sob a regra D5: acrescenta pessoa_id/pessoa_criterio/pessoa_resolvido_em e o trigger mind_pessoa_antes_de_escrever com o mapa de colunas informado. Use para toda tabela nova que fale de pessoa (ex.: um relatório da Yazo importado): select mind_pessoa_ligar_tabela(''schema.tabela'', ''{"emails":["Email"],"telefones":["WhatsApp"],"cpf":"CPF","nome":["Nome"]}'').';

-- As fontes de pessoa que existem hoje. Cada uma com o seu mapa.
-- E-mail do COMPRADOR de ingresso corporativo nao e e-mail da pessoa: fica fora.
do $$
begin
  perform public.mind_pessoa_ligar_tabela('crm.contato_espelho',
    '{"hubspot_ids":["hubspot_id"],"emails":["email"],"telefones":["phone","hs_whatsapp_phone_number"],"nome":["firstname","lastname"]}');
  -- credenciamento e Yazo: o CPF da linha e o do COMPRADOR (igual ao "CPF do
  -- Comprador" em 100% do export de 21/09) — fica fora do mapa da pessoa.
  perform public.mind_pessoa_ligar_tabela('credenciamento_summit_2026.participantes',
    '{"emails":["email"],"telefones":["telefone_norm","cellphone"],"credenciamento_id":"id","yazo_id":"yazo_user_id","nome":["name"]}');
  perform public.mind_pessoa_ligar_tabela('credenciamento_summit_2026.yazo_espelho',
    '{"emails":["email"],"telefones":["attributes.cellphone"],"yazo_id":"yazo_id","nome":["name"]}');
  perform public.mind_pessoa_ligar_tabela('eduzz.ingressos',
    '{"emails":["email"],"telefones":["telefone_norm","telefone"],"documento":"cpf_cnpj","eduzz_participante":"cod_participante","nome":["participante"]}');
  perform public.mind_pessoa_ligar_tabela('eduzz.vendas',
    '{"emails":["cliente_email"],"telefones":["cliente_telefone_norm"],"documento":"cliente_documento","nome":["cliente_nome"]}');
  perform public.mind_pessoa_ligar_tabela('crm.leads_capturados',
    '{"emails":["email"],"telefones":["phone"],"nome":["firstname","lastname"]}');
  perform public.mind_pessoa_ligar_tabela('checkout.pedidos',
    '{"emails":["comprador_email"],"telefones":["comprador_telefone"],"documento":"comprador_documento","nome":["comprador_nome"]}');
  if to_regclass('credenciamento_summit_2026."Relatorio Yazzo Consolidado"') is not null then
    perform public.mind_pessoa_ligar_tabela('credenciamento_summit_2026."Relatorio Yazzo Consolidado"',
      '{"emails":["Email Participante"],"telefones":["WhatsApp"],"nome":["Nome Participante"]}');
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 6. Fase A da passada: enriquecer quem já existe. Nunca cria.
-- ----------------------------------------------------------------------------
-- Junta, para uma pessoa, tudo que as fontes ja ligadas a ela sabem, e entrega
-- a porta unica COM A PESSOA ANCORADA: acrescenta o que esta livre, completa
-- nome/e-mail/WhatsApp nulos, e registra conflito com proposta para o que ja e
-- de outra pessoa. Uma fonte esta "ligada" quando alguma coluna dela casa com
-- um identificador atual da pessoa, ou quando a linha ja tem pessoa_id = ela.
create or replace function public.mind_pessoa_enriquecer(p_pessoa_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, engagement, pessoas
as $function$
declare
  v_emails text[]; v_tels text[]; v_hubs text[]; v_cpfs text[]; v_docs text[] := '{}'; v_yazo text[]; v_cred text[]; v_edz text[]; v_lw text[];
  v_nome text; v_ids jsonb := '{}'::jsonb; v_r jsonb; v_antes int; v_depois int;
begin
  if p_pessoa_id is null then return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa'); end if;
  if exists (select 1 from pessoas.pessoas where id = p_pessoa_id and fundida_em is not null) then
    return jsonb_build_object('ok', false, 'motivo', 'pessoa_fundida');
  end if;

  select count(*) into v_antes from engagement.identidades where pessoa_id = p_pessoa_id;

  -- identificadores atuais (identidades + colunas da propria pessoa)
  with atual as (
    select canal, identificador from engagement.identidades where pessoa_id = p_pessoa_id
    union select 'email', lower(email) from pessoas.pessoas where id = p_pessoa_id and email is not null
    union select 'whatsapp', whatsapp from pessoas.pessoas where id = p_pessoa_id and whatsapp is not null
    union select 'hubspot', hubspot_id from pessoas.pessoas where id = p_pessoa_id and hubspot_id is not null
  ),
  -- HubSpot: por hubspot_id, e-mail, telefone, ou linha ja carimbada
  hs as (
    select c.hubspot_id, lower(btrim(c.email)) as email, c.phone, c.hs_whatsapp_phone_number,
           nullif(btrim(concat_ws(' ', c.firstname, c.lastname)), '') as nome
      from crm.contato_espelho c
     where c.pessoa_id = p_pessoa_id
        or c.hubspot_id in (select identificador from atual where canal = 'hubspot')
        or lower(btrim(c.email)) in (select identificador from atual where canal = 'email')
        or public.telefone_normalizar(c.phone) in (select identificador from atual where canal = 'whatsapp')
        or public.telefone_normalizar(c.hs_whatsapp_phone_number) in (select identificador from atual where canal = 'whatsapp')
  ),
  -- credenciamento (o comprador do ingresso nao e a pessoa; o CPF da linha e o dele)
  cred as (
    select p.id::text as cred_id, lower(btrim(p.email)) as email, p.telefone_norm, null::text as cpf, p.yazo_user_id::text as yazo_id, p.name as nome
      from credenciamento_summit_2026.participantes p
     where p.pessoa_id = p_pessoa_id
        or lower(btrim(p.email)) in (select identificador from atual where canal = 'email')
        or p.telefone_norm in (select identificador from atual where canal = 'whatsapp')
        or p.id in (select identificador::uuid from atual where canal = 'credenciamento')
        or p.yazo_user_id in (select identificador::bigint from atual where canal = 'yazo' and identificador ~ '^[0-9]+$')
  ),
  yz as (
    select y.yazo_id::text as yazo_id, lower(btrim(y.email)) as email, null::text as cpf,
           case when jsonb_typeof(y.attributes->'cellphone') = 'object' then y.attributes->'cellphone'->>'value' else y.attributes->>'cellphone' end as tel,
           y.name as nome
      from credenciamento_summit_2026.yazo_espelho y
     where y.pessoa_id = p_pessoa_id
        or lower(y.email) in (select identificador from atual where canal = 'email')
        or y.yazo_id in (select identificador::bigint from atual where canal = 'yazo' and identificador ~ '^[0-9]+$')
        or public.telefone_normalizar(case when jsonb_typeof(y.attributes->'cellphone') = 'object' then y.attributes->'cellphone'->>'value' else y.attributes->>'cellphone' end)
           in (select identificador from atual where canal = 'whatsapp')
  ),
  -- CPF nao liga fonte a pessoa (e evidencia, e muitas vezes do comprador)
  edz as (
    select i.cod_participante, lower(btrim(i.email)) as email, i.telefone_norm, i.cpf_cnpj as doc, i.participante as nome
      from eduzz.ingressos i
     where i.pessoa_id = p_pessoa_id
        or lower(btrim(i.email)) in (select identificador from atual where canal = 'email')
        or i.telefone_norm in (select identificador from atual where canal = 'whatsapp')
        or i.cod_participante in (select identificador from atual where canal = 'eduzz')
  ),
  vnd as (
    select lower(btrim(v.cliente_email)) as email, v.cliente_telefone_norm, v.cliente_documento as doc, v.cliente_nome as nome
      from eduzz.vendas v
     where v.pessoa_id = p_pessoa_id
        or lower(btrim(v.cliente_email)) in (select identificador from atual where canal = 'email')
        or v.cliente_telefone_norm in (select identificador from atual where canal = 'whatsapp')
  ),
  lw as (
    select a.destino_user_id
      from learnworlds.acessos a
      join checkout.compradores k on k.id = a.comprador_id
     where a.destino_user_id is not null
       and (k.pessoa_id = p_pessoa_id
            or lower(btrim(coalesce(k.email,''))) in (select identificador from atual where canal = 'email'))
  )
  select
    (select array_agg(distinct e) from (select email e from hs union select email from cred union select email from yz union select email from edz union select email from vnd) s where e is not null and e <> ''),
    (select array_agg(distinct t) from (select phone t from hs union select hs_whatsapp_phone_number from hs union select telefone_norm from cred union select tel from yz union select telefone_norm from edz union select cliente_telefone_norm from vnd) s where t is not null and t <> ''),
    (select array_agg(distinct hubspot_id) from hs where hubspot_id is not null),
    (select array_agg(distinct c) from (select cpf c from cred union select cpf from yz) s where c is not null and c <> ''),
    (select array_agg(distinct d) from (select doc d from edz union select doc from vnd) s where d is not null and d <> ''),
    (select array_agg(distinct y) from (select yazo_id y from cred union select yazo_id from yz) s where y is not null and y <> ''),
    (select array_agg(distinct cred_id) from cred where cred_id is not null),
    (select array_agg(distinct cod_participante) from edz where cod_participante is not null and cod_participante <> ''),
    (select array_agg(distinct destino_user_id) from lw),
    (select nome from (select nome, 1 o from hs union all select nome, 2 from cred union all select nome, 3 from yz union all select nome, 4 from edz union all select nome, 5 from vnd) n where nome is not null and btrim(nome) <> '' order by o limit 1)
  into v_emails, v_tels, v_hubs, v_cpfs, v_docs, v_yazo, v_cred, v_edz, v_lw, v_nome;

  v_ids := jsonb_strip_nulls(jsonb_build_object(
    'emails', to_jsonb(coalesce(v_emails, '{}')),
    'telefones', to_jsonb(coalesce(v_tels, '{}')),
    'hubspot_ids', to_jsonb(coalesce(v_hubs, '{}')),
    'yazo_ids', to_jsonb(coalesce(v_yazo, '{}')),
    'cpf', v_cpfs[1],
    'documento', v_docs[1],
    'credenciamento_id', v_cred[1],
    'eduzz_participante', v_edz[1],
    'learnworlds_user_id', v_lw[1]));

  v_r := public.mind_identidade_resolver(v_ids, v_nome, 'enriquecimento', p_pessoa_id);

  -- completa as colunas da propria pessoa com o que ela ja tem em identidades (unico-seguro)
  update pessoas.pessoas p
     set email = coalesce(p.email, (select i.identificador from engagement.identidades i where i.pessoa_id = p.id and i.canal = 'email'
                                    and not exists (select 1 from pessoas.pessoas q where lower(q.email) = i.identificador) order by i.criado_em limit 1)),
         whatsapp = coalesce(p.whatsapp, (select i.identificador from engagement.identidades i where i.pessoa_id = p.id and i.canal = 'whatsapp'
                                    and not exists (select 1 from pessoas.pessoas q where q.whatsapp = i.identificador) order by i.criado_em limit 1)),
         hubspot_id = coalesce(p.hubspot_id, (select i.identificador from engagement.identidades i where i.pessoa_id = p.id and i.canal = 'hubspot'
                                    and not exists (select 1 from pessoas.pessoas q where q.hubspot_id = i.identificador) order by i.criado_em limit 1)),
         enriquecida_em = now()
   where p.id = p_pessoa_id;

  select count(*) into v_depois from engagement.identidades where pessoa_id = p_pessoa_id;

  return jsonb_build_object('ok', true, 'pessoa_id', p_pessoa_id,
    'identidades_antes', v_antes, 'identidades_depois', v_depois,
    'novas', coalesce(v_r->'identidades', '[]'::jsonb),
    'conflito', v_r->'conflito',
    'fontes', jsonb_build_object('hubspot', coalesce(array_length(v_hubs,1),0), 'credenciamento', coalesce(array_length(v_cred,1),0),
                                 'yazo', coalesce(array_length(v_yazo,1),0), 'eduzz', coalesce(array_length(v_edz,1),0), 'learnworlds', coalesce(array_length(v_lw,1),0)));
end $function$;

revoke all on function public.mind_pessoa_enriquecer(uuid) from public;
comment on function public.mind_pessoa_enriquecer(uuid) is
  'Fase A da passada D5. Reúne os identificadores que as fontes já ligadas à pessoa conhecem (HubSpot, credenciamento, Yazo, Eduzz, LearnWorlds) e os entrega à porta única com a pessoa ancorada: acrescenta o que está livre, completa nome/e-mail/WhatsApp nulos, registra conflito com proposta para o que já é de outra pessoa. Nunca cria pessoa. Nunca funde.';

-- O motor da fase A, em lotes, retomavel. p_simular=true faz tudo e desfaz no
-- fim levantando uma excecao cujo texto e o resumo — no SQL Editor, o resumo
-- aparece como mensagem e nada fica gravado.
create or replace function public.mind_identidade_enriquecer_todas(p_lote int default 1500, p_simular boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, engagement, pessoas
as $function$
declare
  r record; v_r jsonb; v_n int := 0; v_com_novas int := 0; v_conflitos int := 0;
  v_por_canal jsonb := '{}'::jsonb; v_x jsonb; v_restantes int; v_resumo jsonb;
  v_pessoas_antes int; v_pessoas_depois int;
begin
  select count(*) into v_pessoas_antes from pessoas.pessoas;
  for r in
    select id from pessoas.pessoas
     where enriquecida_em is null and fundida_em is null
     order by criado_em
     limit p_lote
  loop
    v_r := public.mind_pessoa_enriquecer(r.id);
    v_n := v_n + 1;
    if jsonb_array_length(coalesce(v_r->'novas','[]'::jsonb)) > 0 then v_com_novas := v_com_novas + 1; end if;
    if v_r->'conflito' is not null and jsonb_typeof(v_r->'conflito') <> 'null' then v_conflitos := v_conflitos + 1; end if;
    for v_x in select x from jsonb_array_elements(coalesce(v_r->'novas','[]'::jsonb)) x loop
      v_por_canal := jsonb_set(v_por_canal, array[v_x->>'canal'],
                       to_jsonb(coalesce((v_por_canal->>(v_x->>'canal'))::int, 0) + 1));
    end loop;
  end loop;
  select count(*) into v_restantes from pessoas.pessoas where enriquecida_em is null and fundida_em is null;
  select count(*) into v_pessoas_depois from pessoas.pessoas;

  v_resumo := jsonb_build_object(
    'fase', 'A_enriquecer', 'simulacao', p_simular,
    'pessoas_processadas', v_n, 'pessoas_com_identificador_novo', v_com_novas,
    'identificadores_novos_por_canal', v_por_canal,
    'pessoas_com_conflito', v_conflitos,
    'pessoas_criadas', v_pessoas_depois - v_pessoas_antes,   -- tem que ser 0
    'restantes_nesta_rodada', v_restantes,
    'propostas_pendentes_por_padrao', (select coalesce(jsonb_object_agg(padrao, n), '{}'::jsonb)
                                       from (select coalesce(padrao,'(sem padrao)') padrao, count(*) n from engagement.identidade_fusoes where status = 'pendente' group by 1) s));
  if p_simular then
    raise exception using errcode = 'P0001', message = 'SIMULACAO — nada gravado. ' || v_resumo::text;
  end if;
  return v_resumo;
end $function$;

revoke all on function public.mind_identidade_enriquecer_todas(int, boolean) from public;
comment on function public.mind_identidade_enriquecer_todas(int, boolean) is
  'Roda a fase A (mind_pessoa_enriquecer) sobre as pessoas ainda não enriquecidas nesta rodada, em lotes. p_simular=true faz o trabalho e desfaz no fim, devolvendo o resumo como mensagem de erro — nada fica gravado. Para uma rodada nova: update pessoas.pessoas set enriquecida_em = null.';

-- Fase C da passada: as linhas de uma fonte que ainda nao tem pessoa passam pela
-- porta (o proprio trigger faz o trabalho ao tocar a linha). Recusa-se a rodar
-- enquanto a fase A nao terminou. p_simular devolve o resumo como mensagem e
-- desfaz tudo. Linha que ficou sem pessoa por falta de identificador forte nao e
-- tentada de novo (pessoa_resolvido_em preenchido); para tentar de novo:
-- update <fonte> set pessoa_resolvido_em = null where pessoa_id is null.
create or replace function public.mind_identidade_criar_faltantes(p_fonte regclass, p_lote int default 2000, p_simular boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, engagement, pessoas
as $function$
declare
  v_sch text; v_tab text; v_q text; v_n int; v_antes int; v_depois int; v_restantes int;
  v_ligadas int; v_criadas int; v_sem int; v_resumo jsonb; v_motivos jsonb;
begin
  if exists (select 1 from pessoas.pessoas where enriquecida_em is null and fundida_em is null) then
    raise exception using errcode = 'P0001', message = 'fase_a_incompleta: rode 11_enriquecer_aplicar.sql ate restantes_nesta_rodada = 0 antes de criar pessoas';
  end if;
  select n.nspname, c.relname into v_sch, v_tab from pg_class c join pg_namespace n on n.oid = c.relnamespace where c.oid = p_fonte;
  v_q := format('%I.%I', v_sch, v_tab);
  if not exists (select 1 from pg_trigger t where t.tgrelid = p_fonte and t.tgname = 'zz_d5_pessoa_antes_de_escrever') then
    raise exception using errcode = 'P0001', message = 'fonte sem o trigger D5: ' || v_q || ' — use mind_pessoa_ligar_tabela primeiro';
  end if;

  select count(*) into v_antes from pessoas.pessoas;
  -- linhas nunca tentadas, e as que foram tentadas enquanto a fase A ainda travava a criacao
  execute format('update %s set pessoa_resolvido_em = now() where ctid in (select ctid from %s where pessoa_id is null and (pessoa_resolvido_em is null or pessoa_criterio = %L) limit %s)',
                 v_q, v_q, 'aguardando_fase_a', p_lote);
  get diagnostics v_n = row_count;
  select count(*) into v_depois from pessoas.pessoas;
  -- now() e constante na transacao: as linhas desta chamada sao exatamente as com pessoa_resolvido_em = now()
  execute format('select count(*) filter (where pessoa_id is not null and pessoa_criterio not like %L),
                         count(*) filter (where pessoa_criterio like %L),
                         count(*) filter (where pessoa_id is null),
                         coalesce(jsonb_object_agg(m, n) filter (where m is not null), %L::jsonb)
                    from (select pessoa_id, pessoa_criterio, case when pessoa_id is null then pessoa_criterio end m, count(*) over (partition by case when pessoa_id is null then pessoa_criterio end) n
                            from %s where pessoa_resolvido_em = now()) s',
                 '%(criada)%', '%(criada)%', '{}', v_q)
    into v_ligadas, v_criadas, v_sem, v_motivos;
  execute format('select count(*) from %s where pessoa_id is null and (pessoa_resolvido_em is null or pessoa_criterio = %L)', v_q, 'aguardando_fase_a') into v_restantes;

  v_resumo := jsonb_build_object('fase', 'C_criar', 'fonte', v_q, 'simulacao', p_simular,
    'linhas_processadas', v_n, 'ligadas_a_pessoa_existente', v_ligadas, 'pessoas_criadas', v_criadas,
    'pessoas_criadas_conferencia', v_depois - v_antes, 'sem_pessoa', v_sem, 'motivos_sem_pessoa', v_motivos,
    'restantes_nesta_fonte', v_restantes);
  if p_simular then
    raise exception using errcode = 'P0001', message = 'SIMULACAO — nada gravado. ' || v_resumo::text;
  end if;
  return v_resumo;
end $function$;

revoke all on function public.mind_identidade_criar_faltantes(regclass, int, boolean) from public;
comment on function public.mind_identidade_criar_faltantes(regclass, int, boolean) is
  'Fase C da passada D5: toca as linhas de uma fonte que ainda não têm pessoa_id, em lotes, para que o trigger as passe pela porta única (liga quem existe, cria quem não existe). Recusa-se enquanto a fase A não terminou. p_simular=true faz e desfaz, devolvendo o resumo como mensagem.';

-- ----------------------------------------------------------------------------
-- 7. Fusão: só existe dentro de uma decisão da Adriana
-- ----------------------------------------------------------------------------
create or replace function public.mind_pessoa_canonica(p_id uuid)
returns uuid
language sql
stable
set search_path = public, pessoas
as $function$
  with recursive c as (
    select id, fundida_em, 0 as n from pessoas.pessoas where id = p_id
    union all
    select p.id, p.fundida_em, c.n + 1 from pessoas.pessoas p join c on p.id = c.fundida_em where c.n < 20
  )
  select id from c where fundida_em is null limit 1;
$function$;
revoke all on function public.mind_pessoa_canonica(uuid) from public;
grant execute on function public.mind_pessoa_canonica(uuid) to service_role, authenticated;
comment on function public.mind_pessoa_canonica(uuid) is 'Segue fundida_em até a pessoa sobrevivente. Um id antigo continua resolvendo depois da fusão (D5: nenhum id morre).';

create or replace function public.mind_pessoa_fundir(p_sobrevive uuid, p_absorvida uuid, p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, engagement, pessoas
as $function$
declare
  fk record; v_sql text; v_movidas int; v_descartadas int; v_total_movidas int := 0; v_total_descartadas int := 0;
  v_detalhe jsonb := '[]'::jsonb; rid record; v_abs pessoas.pessoas%rowtype; v_sob pessoas.pessoas%rowtype;
begin
  -- so dentro de mind_fusao_decidir: nunca funde sem decisao explicita da Adriana
  if current_setting('mind.fusao_autorizada', true) is distinct from p_absorvida::text then
    raise exception using errcode = '42501', message = 'fusao_exige_decisao: use mind_fusao_decidir';
  end if;
  if p_sobrevive is null or p_absorvida is null or p_sobrevive = p_absorvida then
    raise exception using errcode = '22023', message = 'par_invalido';
  end if;
  select * into v_sob from pessoas.pessoas where id = p_sobrevive for update;
  select * into v_abs from pessoas.pessoas where id = p_absorvida for update;
  if v_sob.id is null or v_abs.id is null then raise exception using errcode = '22023', message = 'pessoa_inexistente'; end if;
  if v_sob.fundida_em is not null then raise exception using errcode = '22023', message = 'sobrevivente_ja_fundida'; end if;
  if v_abs.fundida_em is not null then return jsonb_build_object('ok', true, 'motivo', 'ja_fundida', 'em', v_abs.fundida_em); end if;

  -- libera os valores unicos da absorvida para que a sobrevivente possa herda-los
  update pessoas.pessoas set email = null, whatsapp = null, hubspot_id = null where id = p_absorvida;

  -- repointa TODA FK para pessoas.pessoas, dinamicamente (46 hoje, qualquer futura)
  for fk in
    select con.conrelid::regclass as tab, a.attname as col
      from pg_constraint con
      join pg_attribute a on a.attrelid = con.conrelid and a.attnum = any(con.conkey)
     where con.contype = 'f' and con.confrelid = 'pessoas.pessoas'::regclass
       and con.conrelid <> 'pessoas.pessoas'::regclass
     order by 1, 2
  loop
    v_descartadas := 0;
    begin
      execute format('update %s set %I = $1 where %I = $2', fk.tab, fk.col, fk.col) using p_sobrevive, p_absorvida;
      get diagnostics v_movidas = row_count;
    exception when unique_violation then
      -- uma linha por pessoa (contexto, perfil, PK composta): a da sobrevivente fica,
      -- a da absorvida e descartada e registrada
      v_movidas := 0;
      for rid in execute format('select ctid as t from %s where %I = $1', fk.tab, fk.col) using p_absorvida loop
        begin
          execute format('update %s set %I = $1 where ctid = $2', fk.tab, fk.col) using p_sobrevive, rid.t;
          v_movidas := v_movidas + 1;
        exception when unique_violation then
          execute format('delete from %s where ctid = $1', fk.tab) using rid.t;
          v_descartadas := v_descartadas + 1;
        end;
      end loop;
    end;
    if v_movidas > 0 or v_descartadas > 0 then
      v_detalhe := v_detalhe || jsonb_build_array(jsonb_build_object('tabela', fk.tab::text, 'coluna', fk.col, 'movidas', v_movidas, 'descartadas', v_descartadas));
    end if;
    v_total_movidas := v_total_movidas + v_movidas;
    v_total_descartadas := v_total_descartadas + v_descartadas;
  end loop;

  -- a sobrevivente herda o que lhe falta
  update pessoas.pessoas s
     set primeiro_nome = coalesce(s.primeiro_nome, v_abs.primeiro_nome),
         sobrenome     = coalesce(s.sobrenome, v_abs.sobrenome),
         empresa       = coalesce(s.empresa, v_abs.empresa),
         cargo         = coalesce(s.cargo, v_abs.cargo),
         email         = coalesce(s.email, case when not exists (select 1 from pessoas.pessoas q where lower(q.email) = lower(v_abs.email)) then v_abs.email end),
         whatsapp      = coalesce(s.whatsapp, case when not exists (select 1 from pessoas.pessoas q where q.whatsapp = v_abs.whatsapp) then v_abs.whatsapp end),
         hubspot_id    = coalesce(s.hubspot_id, case when not exists (select 1 from pessoas.pessoas q where q.hubspot_id = v_abs.hubspot_id) then v_abs.hubspot_id end),
         atualizado_em = now()
   where s.id = p_sobrevive;

  -- a absorvida fica, como apelido
  update pessoas.pessoas set fundida_em = p_sobrevive, fundida_quando = now(), atualizado_em = now() where id = p_absorvida;

  -- pendencias entre as duas ficam fechadas
  update engagement.identidade_fusoes f
     set status = 'fundido', resolvido_em = now(),
         decisao = coalesce(f.decisao, '{}'::jsonb) || jsonb_build_object('fundida_por_par', true)
   where f.status = 'pendente' and f.participante_origem is not null
     and least(f.participante_id, f.participante_origem) = least(p_sobrevive, p_absorvida)
     and greatest(f.participante_id, f.participante_origem) = greatest(p_sobrevive, p_absorvida);

  insert into public.mind_admin_audit (actor_user_id, action, resource, record_id, record_label, before_data, after_data, request_id)
  values (auth.uid(), 'fundir', 'pessoa', p_absorvida::text,
          coalesce(p_motivo, 'fusao D5'),
          jsonb_build_object('absorvida', to_jsonb(v_abs)),
          jsonb_build_object('sobrevive', p_sobrevive, 'linhas_movidas', v_total_movidas, 'linhas_descartadas', v_total_descartadas, 'detalhe', v_detalhe),
          gen_random_uuid());

  return jsonb_build_object('ok', true, 'sobrevive', p_sobrevive, 'absorvida', p_absorvida,
                            'linhas_movidas', v_total_movidas, 'linhas_descartadas', v_total_descartadas, 'detalhe', v_detalhe);
end $function$;

revoke all on function public.mind_pessoa_fundir(uuid, uuid, text) from public;
comment on function public.mind_pessoa_fundir(uuid, uuid, text) is
  'Funde a absorvida na sobrevivente: repointa dinamicamente toda FK para pessoas.pessoas (uma linha por pessoa: a da sobrevivente fica, a da absorvida é descartada e auditada), move identidades, completa o que falta na sobrevivente, e mantém a absorvida com fundida_em (nenhum id morre). Recusa-se a rodar fora de mind_fusao_decidir (42501): nada funde sem decisão explícita da Adriana.';

create or replace function public.mind_fusao_decidir(p_alvo text, p_decisao text, p_quem text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, engagement, pessoas
as $function$
declare
  v_role text; v_quem text; f record; v_r jsonb; v_ok int := 0; v_rej int := 0; v_erro int := 0; v_lista jsonb := '[]'::jsonb; v_id uuid;
begin
  if p_decisao not in ('aprovar','rejeitar') then
    raise exception using errcode = '22023', message = 'decisao_invalida: aprovar ou rejeitar';
  end if;
  -- gate: pelo painel/API exige papel; no SQL Editor (session_user postgres) e a propria Adriana
  if session_user <> 'postgres' then
    select role into v_role from public.mind_admin_users where user_id = auth.uid() and active;
    if v_role is null or v_role not in ('administrador','aprovador') then
      raise exception using errcode = '42501', message = 'admin_forbidden';
    end if;
    select display_name into v_quem from public.mind_admin_users where user_id = auth.uid();
  end if;
  v_quem := coalesce(p_quem, v_quem, session_user::text);

  begin v_id := p_alvo::uuid; exception when others then v_id := null; end;
  if v_id is null and p_alvo in ('telefone_compartilhado','nomes_divergentes') and p_decisao = 'aprovar' then
    raise exception using errcode = '22023', message = 'padrao_so_linha_a_linha: ' || p_alvo;
  end if;

  -- Na duvida, perguntar e nao unificar (Adriana, 23/09): aprovar um PADRAO
  -- inteiro so alcanca as propostas de confianca alta; as demais do mesmo
  -- padrao continuam pendentes, para decisao linha a linha pelo id.
  for f in
    select * from engagement.identidade_fusoes
     where status = 'pendente' and proposta is not null
       and ((v_id is not null and id = v_id)
         or (v_id is null and padrao = p_alvo and (p_decisao = 'rejeitar' or proposta->>'confianca' = 'alta')))
     order by criado_em
  loop
    if p_decisao = 'rejeitar' then
      update engagement.identidade_fusoes set status = 'descartado', resolvido_em = now(), resolvido_por = v_quem,
             decisao = jsonb_build_object('decisao', 'rejeitar', 'quem', v_quem, 'quando', now())
       where id = f.id;
      v_rej := v_rej + 1;
      continue;
    end if;
    begin
      perform set_config('mind.fusao_autorizada', (f.proposta->>'absorvida'), true);
      v_r := public.mind_pessoa_fundir((f.proposta->>'sobrevive')::uuid, (f.proposta->>'absorvida')::uuid,
                                        'decisao de ' || v_quem || ' sobre ' || coalesce(f.padrao,'?'));
      perform set_config('mind.fusao_autorizada', '', true);
      update engagement.identidade_fusoes set status = 'fundido', resolvido_em = now(), resolvido_por = v_quem,
             decisao = jsonb_build_object('decisao', 'aprovar', 'quem', v_quem, 'quando', now(), 'resultado', v_r)
       where id = f.id;
      v_ok := v_ok + 1;
    exception when others then
      perform set_config('mind.fusao_autorizada', '', true);
      v_erro := v_erro + 1;
      v_lista := v_lista || jsonb_build_array(jsonb_build_object('pendencia', f.id, 'erro', sqlerrm));
    end;
  end loop;

  return jsonb_build_object('alvo', p_alvo, 'decisao', p_decisao, 'quem', v_quem,
                            'fundidas', v_ok, 'rejeitadas', v_rej, 'erros', v_erro, 'detalhe_erros', v_lista,
                            'ficaram_para_linha_a_linha', (select count(*) from engagement.identidade_fusoes
                                                            where status = 'pendente' and v_id is null and padrao = p_alvo));
end $function$;

revoke all on function public.mind_fusao_decidir(text, text, text) from public;
grant execute on function public.mind_fusao_decidir(text, text, text) to service_role, authenticated;
comment on function public.mind_fusao_decidir(text, text, text) is
  'A decisão da Adriana sobre duplicatas propostas: p_alvo é o id de uma pendência ou o nome de um padrão inteiro; p_decisao é aprovar (funde, via mind_pessoa_fundir) ou rejeitar (descarta). Aprovar um padrão só alcança propostas de confiança alta; média e baixa ficam para decisão pelo id. telefone_compartilhado e nomes_divergentes nunca em bloco. Pelo painel exige papel administrador/aprovador; no SQL Editor vale o próprio postgres. É o único caminho que funde alguém.';

-- ----------------------------------------------------------------------------
-- 8. A tabela que a Adriana descreveu: a pessoa com todos os seus ids
-- ----------------------------------------------------------------------------
create or replace view pessoas.v_pessoa_360 as
select p.id as pessoa_id,
       p.primeiro_nome, p.sobrenome,
       p.email,
       x.outros_emails,
       p.whatsapp,
       x.outros_whatsapps,
       x.cpf, x.cnpjs,
       x.hubspot_ids, x.yazo_ids, x.credenciamento_ids, x.eduzz_codigos, x.learnworlds_user_id, x.auth_user_id,
       p.empresa, p.cargo, p.origem,
       x.canais,
       p.criado_em, p.atualizado_em, p.enriquecida_em,
       p.fundida_em, p.fundida_quando
  from pessoas.pessoas p
  left join lateral (
    select array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'email' and i.identificador <> coalesce(lower(p.email),'')) as outros_emails,
           array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'whatsapp' and i.identificador <> coalesce(p.whatsapp,'')) as outros_whatsapps,
           (array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'cpf'))[1] as cpf,
           array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'cnpj') as cnpjs,
           array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'hubspot') as hubspot_ids,
           array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'yazo') as yazo_ids,
           array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'credenciamento') as credenciamento_ids,
           array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'eduzz') as eduzz_codigos,
           (array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'learnworlds'))[1] as learnworlds_user_id,
           (array_agg(i.identificador order by i.criado_em) filter (where i.canal = 'auth_user'))[1] as auth_user_id,
           array_agg(distinct i.canal) as canais
      from engagement.identidades i
     where i.pessoa_id = p.id
  ) x on true;

comment on view pessoas.v_pessoa_360 is
  'A pessoa com todos os ids que a identificam, numa linha (D5): id do sistema, nome, e-mail principal e outros, WhatsApp principal e outros, CPF, CNPJs, ids do HubSpot, da Yazo, do credenciamento, da Eduzz, do LearnWorlds e do login. Pivô de engagement.identidades; a casa continua normalizada. Uma pessoa fundida aparece com fundida_em preenchido.';

-- ----------------------------------------------------------------------------
-- 9. Prova de que a migration deixou o banco no estado prometido
-- ----------------------------------------------------------------------------
do $$
declare n int;
begin
  select count(*) into n from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where t.tgname = 'zz_d5_pessoa_antes_de_escrever' and not t.tgisinternal;
  if n < 7 then raise exception 'd5: esperava o trigger em pelo menos 7 tabelas-fonte, achei %', n; end if;
  if to_regprocedure('public.mind_pessoa_fundir(uuid,uuid,text)') is null
     or to_regprocedure('public.mind_fusao_decidir(text,text,text)') is null
     or to_regprocedure('public.mind_pessoa_enriquecer(uuid)') is null then
    raise exception 'd5: funcao ausente';
  end if;
  if not exists (select 1 from pg_views where schemaname = 'pessoas' and viewname = 'v_pessoa_360') then
    raise exception 'd5: view ausente';
  end if;
end $$;
