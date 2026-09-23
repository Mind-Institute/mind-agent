-- ============================================================
-- Contrato: D5 — identidade universal
-- ============================================================
-- Rodar:  psql "$DATABASE_URL" -f tests/d5_identidade_universal_contract.sql
--
-- Não escreve nada: abre transação, monta um cenário sintético (e-mails em
-- *.exemplo.invalid, telefones 55119000000xx), exercita a porta única, a
-- fase A (enriquecer), a proposta, a decisão e a fusão, confere cada promessa
-- da migration 20260923013000_d5_identidade_universal.sql — e desfaz no fim.
--
-- O cenário é o das 586 duplicatas medidas em 23/09/2026:
--   A nasceu de uma mensagem de WhatsApp e foi ligada ao HubSpot só pelo id do
--     contato (sem e-mail, sem nome — o contato tinha os dois);
--   B nasceu do login no app, com o mesmo e-mail do contato, e com nome.
-- ============================================================

begin;

-- O trigger da tabela-fonte fica desligado só durante a montagem do estado
-- legado (contato ligado sem o e-mail virar identidade). Volta antes dos testes.
alter table crm.contato_espelho disable trigger zz_d5_pessoa_antes_de_escrever;

do $$
declare
  a uuid; b uuid; c uuid; d uuid; e uuid; f uuid; g uuid;
  r jsonb; prop jsonb; crit text; n int; n2 int; sess uuid; auth_b uuid := gen_random_uuid();
  pessoas_antes int; falhou boolean;
begin
  select id into sess from summit_2026.sessions order by inicio limit 1;
  if sess is null then raise exception 'contrato D5: precisa de uma sessão em summit_2026.sessions'; end if;

  -- ---------- montagem do cenário das 586 ----------
  insert into pessoas.pessoas (whatsapp, origem) values ('5511900000001', 'bot') returning id into a;
  insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca) values
    (a, 'whatsapp', '5511900000001', true, 'alta'),
    (a, 'hubspot',  '999000001',     true, 'alta');
  insert into crm.contato_espelho (hubspot_id, email, phone, firstname, lastname, pessoa_id)
    values ('999000001', 'd5.elisama@exemplo.invalid', '+55 11 90000-0001', 'Elisama', 'Teste', a);

  insert into pessoas.pessoas (email, primeiro_nome, origem) values ('d5.elisama@exemplo.invalid', 'Elisama', 'bot') returning id into b;
  insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca) values
    (b, 'email',     'd5.elisama@exemplo.invalid', false, 'media'),
    (b, 'auth_user', auth_b::text,                 true,  'alta');

  -- linhas que apontam para A e B: PK composta (colide) e FK simples (move)
  insert into engagement.jornada_sessao (participante_id, sessao_id, planejou, atualizado_em) values (a, sess, true, now()), (b, sess, true, now());
  insert into crm.consents (participante_id, finalidade, concedido, politica_chave, politica_versao, texto_exibido, origem, criado_em)
    values (a, 'd5_teste', true, 'd5', 1, 'texto de teste', 'contrato_d5', now());

  select count(*) into pessoas_antes from pessoas.pessoas;

  -- ---------- 1. fase A: enriquecer A NÃO cria pessoa, completa o nome, e propõe ----------
  r := public.mind_pessoa_enriquecer(a);
  select count(*) into n from pessoas.pessoas;
  if n <> pessoas_antes then raise exception 'D5.1 enriquecer criou pessoa (% -> %)', pessoas_antes, n; end if;
  if (select primeiro_nome from pessoas.pessoas where id = a) is distinct from 'Elisama' then
    raise exception 'D5.1 enriquecer não completou o nome de A a partir do contato';
  end if;
  if r->'conflito' is null or jsonb_typeof(r->'conflito') = 'null' then
    raise exception 'D5.1 o e-mail do contato pertence a B: esperava conflito, veio %', r;
  end if;
  select proposta into prop from engagement.identidade_fusoes
   where status = 'pendente' and participante_origem is not null
     and least(participante_id, participante_origem) = least(a, b)
     and greatest(participante_id, participante_origem) = greatest(a, b)
   limit 1;
  if prop is null then raise exception 'D5.1 conflito sem proposta'; end if;
  if prop->>'padrao' <> 'mesmo_email_hubspot_x_login' then raise exception 'D5.1 padrão errado: %', prop->>'padrao'; end if;
  if (prop->>'sobrevive')::uuid <> b or (prop->>'absorvida')::uuid <> a then raise exception 'D5.1 sobrevive deveria ser quem tem login (B): %', prop; end if;
  if prop->>'confianca' <> 'alta' then raise exception 'D5.1 confiança deveria ser alta: %', prop; end if;
  -- o e-mail continua só com B: ninguém tomou identificador de ninguém
  if (select pessoa_id from engagement.identidades where canal = 'email' and identificador = 'd5.elisama@exemplo.invalid') <> b then
    raise exception 'D5.1 o e-mail mudou de dona sem decisão';
  end if;

  -- ---------- 2. fundir direto é proibido ----------
  falhou := false;
  begin
    perform public.mind_pessoa_fundir(b, a, 'tentativa direta');
  exception when insufficient_privilege then falhou := true;
  end;
  if not falhou then raise exception 'D5.2 mind_pessoa_fundir aceitou rodar fora de mind_fusao_decidir'; end if;
  if (select fundida_em from pessoas.pessoas where id = a) is not null then raise exception 'D5.2 fundiu sem decisão'; end if;

  -- ---------- 3. a decisão da Adriana funde, e nenhum id morre ----------
  r := public.mind_fusao_decidir('mesmo_email_hubspot_x_login', 'aprovar', 'contrato_d5');
  if (r->>'fundidas')::int < 1 then raise exception 'D5.3 decidir não fundiu: %', r; end if;
  if (select fundida_em from pessoas.pessoas where id = a) <> b then raise exception 'D5.3 A deveria apontar para B'; end if;
  if public.mind_pessoa_canonica(a) <> b then raise exception 'D5.3 o id antigo de A deixou de resolver'; end if;
  if (select count(*) from engagement.identidades where pessoa_id = b and canal in ('whatsapp','hubspot')) < 2 then
    raise exception 'D5.3 whatsapp e hubspot de A não passaram para B';
  end if;
  if (select count(*) from engagement.jornada_sessao where sessao_id = sess and participante_id in (a, b)) <> 1
     or (select participante_id from engagement.jornada_sessao where sessao_id = sess and participante_id in (a, b)) <> b then
    raise exception 'D5.3 PK composta: deveria sobrar só a linha de B';
  end if;
  if (select participante_id from crm.consents where finalidade = 'd5_teste') <> b then raise exception 'D5.3 consents não foi repontado'; end if;
  if (select pessoa_id from crm.contato_espelho where hubspot_id = '999000001') <> b then raise exception 'D5.3 contato_espelho não foi repontado'; end if;
  if (select whatsapp from pessoas.pessoas where id = b) <> '5511900000001' then raise exception 'D5.3 B não herdou o WhatsApp de A'; end if;
  if not exists (select 1 from public.mind_admin_audit where action = 'fundir' and record_id = a::text) then raise exception 'D5.3 fusão sem auditoria'; end if;
  if exists (select 1 from engagement.identidade_fusoes where status = 'pendente' and participante_origem is not null
              and least(participante_id, participante_origem) = least(a, b)) then
    raise exception 'D5.3 pendência do par continuou aberta';
  end if;

  -- ---------- 4a. enquanto a fase A não terminou, o trigger liga mas não cria ----------
  if not exists (select 1 from pessoas.pessoas where enriquecida_em is null and fundida_em is null) then
    update pessoas.pessoas set enriquecida_em = null where id = b;   -- garante uma pessoa por enriquecer
  end if;
  insert into crm.leads_capturados (firstname, lastname, email) values ('Cedo', 'Demais', 'd5.cedo@exemplo.invalid') returning pessoa_id, pessoa_criterio into f, crit;
  if f is not null or crit <> 'aguardando_fase_a' then raise exception 'D5.4a criou pessoa antes da fase A terminar (pessoa=%, criterio=%)', f, crit; end if;
  -- a fase C recusa rodar enquanto a fase A não terminou
  falhou := false;
  begin
    perform public.mind_identidade_criar_faltantes('crm.leads_capturados', 10, false);
  exception when raise_exception then falhou := true;
  end;
  if not falhou then raise exception 'D5.4a criar_faltantes rodou com a fase A incompleta'; end if;
  -- fase A concluída: toda pessoa existente já passou pelo enriquecimento
  update pessoas.pessoas set enriquecida_em = coalesce(enriquecida_em, now()) where enriquecida_em is null;
  r := public.mind_identidade_criar_faltantes('crm.leads_capturados', 10, false);
  if (r->>'pessoas_criadas')::int <> 1 or (select pessoa_id from crm.leads_capturados where email = 'd5.cedo@exemplo.invalid') is null then
    raise exception 'D5.4a com a fase A concluída, a fase C deveria criar a pessoa do lead: %', r;
  end if;

  -- ---------- 4. CPF igual não é a mesma pessoa ----------
  r := public.mind_identidade_resolver(jsonb_build_object('emails', jsonb_build_array('d5.comprador@exemplo.invalid'), 'cpf', '529.982.247-25'), 'Carlos Comprador', 'contrato_d5');
  c := (r->>'pessoa_id')::uuid;
  if c is null or not (r->>'criada')::boolean then raise exception 'D5.4 esperava criar C: %', r; end if;
  if not exists (select 1 from engagement.identidades where pessoa_id = c and canal = 'cpf' and identificador = '52998224725') then
    raise exception 'D5.4 CPF válido deveria ficar como evidência de C';
  end if;
  -- ingresso com o CPF do comprador e o e-mail de outra pessoa: nasce D, sem proposta
  insert into eduzz.ingressos (uuid, participante, cpf_cnpj, email, cod_participante, sincronizado_em)
    values ('d5-ingresso-1', 'Dora Participante', '52998224725', 'd5.dora@exemplo.invalid', 'D5P1', now());
  select pessoa_id into d from eduzz.ingressos where uuid = 'd5-ingresso-1';
  if d is null or d = c then raise exception 'D5.4 CPF igual com e-mail diferente deveria ser pessoa diferente (d=%, c=%)', d, c; end if;
  if exists (select 1 from engagement.identidade_fusoes where status = 'pendente' and participante_origem is not null
              and least(participante_id, participante_origem) = least(c, d) and greatest(participante_id, participante_origem) = greatest(c, d)) then
    raise exception 'D5.4 CPF sozinho abriu proposta de fusão';
  end if;
  if (select pessoa_id from engagement.identidades where canal = 'cpf' and identificador = '52998224725') <> c then
    raise exception 'D5.4 o CPF mudou de dona';
  end if;
  if (select pessoa_criterio from eduzz.ingressos where uuid = 'd5-ingresso-1') not like '%email%(criada)%' then
    raise exception 'D5.4 critério esperado "email (criada)", veio %', (select pessoa_criterio from eduzz.ingressos where uuid = 'd5-ingresso-1');
  end if;
  -- CPF sozinho não cria pessoa
  r := public.mind_identidade_resolver(jsonb_build_object('cpf', '11144477735'), 'Só CPF', 'contrato_d5');
  if r->>'pessoa_id' is not null or r->>'motivo' <> 'sem_identificador_forte' then raise exception 'D5.4 CPF sozinho criou pessoa: %', r; end if;

  -- ---------- 5. o trigger carimba pessoa_id na escrita, e não repete a porta à toa ----------
  insert into credenciamento_summit_2026.participantes (id, name, email, cellphone, status, sincronizado_em)
    values (gen_random_uuid(), 'Elisama Teste', 'D5.Elisama@exemplo.invalid', '(11) 90000-0001', 'ativo', now())
    returning pessoa_id into e;
  if e <> b then raise exception 'D5.5 participante deveria cair em B pelo e-mail/WhatsApp, caiu em %', e; end if;
  if (select pessoa_criterio from credenciamento_summit_2026.participantes where email = 'D5.Elisama@exemplo.invalid') !~ 'email' then
    raise exception 'D5.5 critério deveria citar email';
  end if;
  if not exists (select 1 from engagement.identidades where pessoa_id = b and canal = 'credenciamento') then
    raise exception 'D5.5 o id do credenciamento deveria virar identidade de B';
  end if;
  -- só nome: não cria pessoa, e a linha entra mesmo assim
  insert into crm.leads_capturados (firstname, lastname) values ('Sem', 'Identificador') returning pessoa_id, pessoa_criterio into f, crit;
  if f is not null then raise exception 'D5.5 lead só com nome ganhou pessoa'; end if;
  if crit <> 'sem_identificador_deterministico' then raise exception 'D5.5 critério esperado sem_identificador_deterministico, veio %', crit; end if;

  -- ---------- 6. enriquecer de novo não acrescenta nada ----------
  select count(*) into n from engagement.identidades where pessoa_id = b;
  r := public.mind_pessoa_enriquecer(b);
  select count(*) into n2 from engagement.identidades where pessoa_id = b;
  if n2 <> n then raise exception 'D5.6 segunda passada acrescentou identificador (% -> %)', n, n2; end if;
  -- criadas de propósito até aqui: o lead "Cedo Demais", C (comprador) e D (Dora)
  if (select count(*) from pessoas.pessoas) <> pessoas_antes + 3 then raise exception 'D5.6 contagem de pessoas inesperada'; end if;

  -- ---------- 7. nomes divergentes: proposta baixa, nunca em bloco ----------
  insert into pessoas.pessoas (email, primeiro_nome, origem) values ('d5.ana@exemplo.invalid', 'Ana', 'bot') returning id into f;
  insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca) values (f, 'email', 'd5.ana@exemplo.invalid', false, 'media');
  insert into pessoas.pessoas (whatsapp, primeiro_nome, origem) values ('5511900000077', 'Beatriz', 'bot') returning id into g;
  insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca) values (g, 'whatsapp', '5511900000077', true, 'alta');
  r := public.mind_identidade_resolver(jsonb_build_object('emails', jsonb_build_array('d5.ana@exemplo.invalid')), 'Beatriz', 'contrato_d5', g);
  select proposta into prop from engagement.identidade_fusoes where status = 'pendente' and participante_origem is not null
    and least(participante_id, participante_origem) = least(f, g) and greatest(participante_id, participante_origem) = greatest(f, g) limit 1;
  if prop is null or prop->>'padrao' <> 'nomes_divergentes' or prop->>'confianca' <> 'baixa' then raise exception 'D5.7 esperava nomes_divergentes/baixa: %', prop; end if;
  falhou := false;
  begin
    perform public.mind_fusao_decidir('nomes_divergentes', 'aprovar', 'contrato_d5');
  exception when invalid_parameter_value then falhou := true;
  end;
  if not falhou then raise exception 'D5.7 aprovou nomes_divergentes em bloco'; end if;
  if (select fundida_em from pessoas.pessoas where id in (f, g) and fundida_em is not null limit 1) is not null then raise exception 'D5.7 fundiu sem decisão linha a linha'; end if;

  -- ---------- 8. a pessoa com todos os ids, numa linha ----------
  if not exists (select 1 from pessoas.v_pessoa_360 v where v.pessoa_id = b
                  and '999000001' = any(v.hubspot_ids) and v.whatsapp = '5511900000001'
                  and v.credenciamento_ids is not null and v.auth_user_id = auth_b::text) then
    raise exception 'D5.8 v_pessoa_360 não mostra B com hubspot, whatsapp, credenciamento e login';
  end if;

  raise notice 'contrato D5 ok — enriquecer não cria, fundir só por decisão, CPF não decide, trigger carimba, id antigo resolve';
end $$;

rollback;
