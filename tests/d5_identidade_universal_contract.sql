-- ============================================================
-- Contrato: D5 — identidade universal
-- ============================================================
-- Rodar:  psql "$DATABASE_URL" -f tests/d5_identidade_universal_contract.sql
--
-- Não escreve nada: abre transação, monta um cenário sintético, exercita a
-- porta única, a fase A (enriquecer), a proposta, a decisão e a fusão, confere
-- cada promessa da migration 20260923024555_d5_identidade_universal.sql — e
-- desfaz no fim. Os identificadores do cenário são gerados e conferidos contra
-- o banco: em 23/09 um telefone "de teste" fixo colidiu com uma pessoa real.
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
  a uuid; b uuid; c uuid; d uuid; e uuid; f uuid; g uuid; s uuid; k uuid; k2 uuid; s2 uuid; r2 uuid;
  r jsonb; prop jsonb; crit text; n int; n2 int; sess uuid; auth_b uuid := gen_random_uuid();
  pessoas_antes int; falhou boolean;
  suf text := substr(md5(random()::text), 1, 8);
  tel_a text; tel_g text; tel_s text; hub_a text; hub_z text;
  mail_s  text := 'd5.sueli.'   || suf || '@exemplo.invalid';
  mail_s2 text := 'd5.sueli2.'  || suf || '@exemplo.invalid';
  mail_k  text := 'd5.carlos.'  || suf || '@exemplo.invalid';
  mail_k2 text := 'd5.marcos.'  || suf || '@exemplo.invalid';
  mail_z  text := 'd5.zeca.'    || suf || '@exemplo.invalid';
  mail_e text := 'd5.elisama.' || suf || '@exemplo.invalid';
  mail_c text := 'd5.comprador.' || suf || '@exemplo.invalid';
  mail_d text := 'd5.dora.' || suf || '@exemplo.invalid';
  mail_cedo text := 'd5.cedo.' || suf || '@exemplo.invalid';
  mail_ana text := 'd5.ana.' || suf || '@exemplo.invalid';
  cod_edz text := 'D5P' || suf;
begin
  select id into sess from summit_2026.sessions order by inicio limit 1;
  if sess is null then raise exception 'contrato D5: precisa de uma sessão em summit_2026.sessions'; end if;

  -- identificadores que nao existem no banco (telefones celulares BR validos, id HubSpot numerico)
  loop
    tel_a := '55119' || lpad(floor(random() * 99999999)::bigint::text, 8, '0');
    exit when not exists (select 1 from engagement.identidades where canal = 'whatsapp' and identificador = tel_a)
         and not exists (select 1 from pessoas.pessoas where whatsapp = tel_a);
  end loop;
  loop
    tel_g := '55119' || lpad(floor(random() * 99999999)::bigint::text, 8, '0');
    exit when tel_g <> tel_a
         and not exists (select 1 from engagement.identidades where canal = 'whatsapp' and identificador = tel_g)
         and not exists (select 1 from pessoas.pessoas where whatsapp = tel_g);
  end loop;
  loop
    tel_s := '55119' || lpad(floor(random() * 99999999)::bigint::text, 8, '0');
    exit when tel_s not in (tel_a, tel_g)
         and not exists (select 1 from engagement.identidades where canal = 'whatsapp' and identificador = tel_s)
         and not exists (select 1 from pessoas.pessoas where whatsapp = tel_s)
         and not exists (select 1 from crm.contato_espelho where public.telefone_normalizar(phone) = tel_s or public.telefone_normalizar(hs_whatsapp_phone_number) = tel_s)
         and not exists (select 1 from credenciamento_summit_2026.participantes where telefone_norm = tel_s)
         and not exists (select 1 from eduzz.ingressos where telefone_norm = tel_s)
         and not exists (select 1 from eduzz.vendas where cliente_telefone_norm = tel_s);
  end loop;
  loop
    hub_a := '99' || lpad(floor(random() * 9999999)::bigint::text, 7, '0');
    exit when not exists (select 1 from crm.contato_espelho where hubspot_id = hub_a)
         and not exists (select 1 from engagement.identidades where canal = 'hubspot' and identificador = hub_a)
         and not exists (select 1 from pessoas.pessoas where hubspot_id = hub_a);
  end loop;
  loop
    hub_z := '98' || lpad(floor(random() * 9999999)::bigint::text, 7, '0');
    exit when hub_z <> hub_a
         and not exists (select 1 from crm.contato_espelho where hubspot_id = hub_z)
         and not exists (select 1 from engagement.identidades where canal = 'hubspot' and identificador = hub_z)
         and not exists (select 1 from pessoas.pessoas where hubspot_id = hub_z);
  end loop;

  -- ---------- montagem do cenário das 586 ----------
  insert into pessoas.pessoas (whatsapp, origem) values (tel_a, 'bot') returning id into a;
  insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca) values
    (a, 'whatsapp', tel_a, true, 'alta'),
    (a, 'hubspot',  hub_a, true, 'alta');
  insert into crm.contato_espelho (hubspot_id, email, phone, firstname, lastname, pessoa_id)
    values (hub_a, mail_e, '+' || tel_a, 'Elisama', 'Teste', a);

  insert into pessoas.pessoas (email, primeiro_nome, origem) values (mail_e, 'Elisama', 'bot') returning id into b;
  insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca) values
    (b, 'email',     mail_e,        false, 'media'),
    (b, 'auth_user', auth_b::text,  true,  'alta');

  -- linhas que apontam para A e B: PK composta (colide) e FK simples (move)
  insert into engagement.jornada_sessao (participante_id, sessao_id, planejou, atualizado_em) values (a, sess, true, now()), (b, sess, true, now());
  insert into crm.consents (participante_id, finalidade, concedido, politica_chave, politica_versao, texto_exibido, origem, criado_em)
    values (a, 'd5_teste_' || suf, true, 'd5', 1, 'texto de teste', 'contrato_d5', now());

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
  if (select pessoa_id from engagement.identidades where canal = 'email' and identificador = mail_e) <> b then
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
  -- decide pelo id da pendência (em produção o padrão inteiro pode ter propostas reais)
  r := public.mind_fusao_decidir((select id::text from engagement.identidade_fusoes where status = 'pendente' and participante_origem is not null
                                    and least(participante_id, participante_origem) = least(a, b) and greatest(participante_id, participante_origem) = greatest(a, b) limit 1),
                                 'aprovar', 'contrato_d5');
  if (r->>'fundidas')::int <> 1 then raise exception 'D5.3 decidir não fundiu: %', r; end if;
  if (select fundida_em from pessoas.pessoas where id = a) <> b then raise exception 'D5.3 A deveria apontar para B'; end if;
  if public.mind_pessoa_canonica(a) <> b then raise exception 'D5.3 o id antigo de A deixou de resolver'; end if;
  if (select count(*) from engagement.identidades where pessoa_id = b and canal in ('whatsapp','hubspot')) < 2 then
    raise exception 'D5.3 whatsapp e hubspot de A não passaram para B';
  end if;
  if (select count(*) from engagement.jornada_sessao where sessao_id = sess and participante_id in (a, b)) <> 1
     or (select participante_id from engagement.jornada_sessao where sessao_id = sess and participante_id in (a, b)) <> b then
    raise exception 'D5.3 PK composta: deveria sobrar só a linha de B';
  end if;
  if (select participante_id from crm.consents where finalidade = 'd5_teste_' || suf) <> b then raise exception 'D5.3 consents não foi repontado'; end if;
  if (select pessoa_id from crm.contato_espelho where hubspot_id = hub_a) <> b then raise exception 'D5.3 contato_espelho não foi repontado'; end if;
  if (select whatsapp from pessoas.pessoas where id = b) <> tel_a then raise exception 'D5.3 B não herdou o WhatsApp de A'; end if;
  if not exists (select 1 from public.mind_admin_audit where action = 'atualizar' and record_label like 'fundir:%' and record_id = a::text) then raise exception 'D5.3 fusão sem auditoria'; end if;
  if exists (select 1 from engagement.identidade_fusoes where status = 'pendente' and participante_origem is not null
              and least(participante_id, participante_origem) = least(a, b)) then
    raise exception 'D5.3 pendência do par continuou aberta';
  end if;

  -- ---------- 4a. enquanto a fase A não terminou, o trigger liga mas não cria ----------
  if not exists (select 1 from pessoas.pessoas where enriquecida_em is null and fundida_em is null) then
    update pessoas.pessoas set enriquecida_em = null where id = b;   -- garante uma pessoa por enriquecer
  end if;
  insert into crm.leads_capturados (firstname, lastname, email) values ('Cedo', 'Demais', mail_cedo) returning pessoa_id, pessoa_criterio into f, crit;
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
  r := public.mind_identidade_criar_faltantes('crm.leads_capturados', 100000, false);
  if (r->>'pessoas_criadas')::int < 1 or (select pessoa_id from crm.leads_capturados where email = mail_cedo) is null then
    raise exception 'D5.4a com a fase A concluída, a fase C deveria criar a pessoa do lead: %', r;
  end if;

  -- ---------- 4. CPF igual não é a mesma pessoa ----------
  r := public.mind_identidade_resolver(jsonb_build_object('emails', jsonb_build_array(mail_c), 'cpf', '529.982.247-25'), 'Carlos Comprador', 'contrato_d5');
  c := (r->>'pessoa_id')::uuid;
  if c is null or not (r->>'criada')::boolean then raise exception 'D5.4 esperava criar C: %', r; end if;
  -- o CPF de teste pode ja pertencer a alguem no banco; so exigimos que ele nao decida nada
  if (select pessoa_id from engagement.identidades where canal = 'cpf' and identificador = '52998224725') is null then
    raise exception 'D5.4 CPF válido deveria ficar como evidência de alguém';
  end if;
  -- ingresso com o mesmo CPF e o e-mail de outra pessoa: nasce D, sem proposta com C
  insert into eduzz.ingressos (uuid, participante, cpf_cnpj, email, cod_participante, sincronizado_em)
    values ('d5-ingresso-' || suf, 'Dora Participante', '52998224725', mail_d, cod_edz, now());
  select pessoa_id into d from eduzz.ingressos where uuid = 'd5-ingresso-' || suf;
  if d is null or d = c then raise exception 'D5.4 CPF igual com e-mail diferente deveria ser pessoa diferente (d=%, c=%)', d, c; end if;
  if exists (select 1 from engagement.identidade_fusoes where status = 'pendente' and participante_origem is not null
              and least(participante_id, participante_origem) = least(c, d) and greatest(participante_id, participante_origem) = greatest(c, d)) then
    raise exception 'D5.4 CPF sozinho abriu proposta de fusão';
  end if;
  if (select pessoa_criterio from eduzz.ingressos where uuid = 'd5-ingresso-' || suf) not like 'criada:%email%' then
    raise exception 'D5.4 critério esperado "criada: …email…", veio %', (select pessoa_criterio from eduzz.ingressos where uuid = 'd5-ingresso-' || suf);
  end if;
  -- CPF sozinho não cria pessoa
  r := public.mind_identidade_resolver(jsonb_build_object('cpf', '11144477735'), 'Só CPF', 'contrato_d5');
  if r->>'pessoa_id' is not null or r->>'motivo' <> 'sem_identificador_forte' then raise exception 'D5.4 CPF sozinho criou pessoa: %', r; end if;

  -- ---------- 5. o trigger carimba pessoa_id na escrita, e não repete a porta à toa ----------
  insert into credenciamento_summit_2026.participantes (id, name, email, cellphone, status, sincronizado_em)
    values (gen_random_uuid(), 'Elisama Teste', upper(left(mail_e, 1)) || substr(mail_e, 2), tel_a, 'ativo', now())
    returning pessoa_id into e;
  if e <> b then raise exception 'D5.5 participante deveria cair em B pelo e-mail/WhatsApp, caiu em %', e; end if;
  if (select pessoa_criterio from credenciamento_summit_2026.participantes where lower(email) = mail_e) !~ 'email' then
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

  -- ---------- 7. nomes divergentes: proposta baixa, nunca em bloco ----------
  insert into pessoas.pessoas (email, primeiro_nome, origem) values (mail_ana, 'Ana', 'bot') returning id into f;
  insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca) values (f, 'email', mail_ana, false, 'media');
  insert into pessoas.pessoas (whatsapp, primeiro_nome, origem) values (tel_g, 'Beatriz', 'bot') returning id into g;
  insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca) values (g, 'whatsapp', tel_g, true, 'alta');
  r := public.mind_identidade_resolver(jsonb_build_object('emails', jsonb_build_array(mail_ana)), 'Beatriz', 'contrato_d5', g);
  select proposta into prop from engagement.identidade_fusoes where status = 'pendente' and participante_origem is not null
    and least(participante_id, participante_origem) = least(f, g) and greatest(participante_id, participante_origem) = greatest(f, g) limit 1;
  -- e-mail em comum com nomes diferentes: padrão próprio desde D5.2 (comprador/porta-voz?), baixa, nunca em bloco
  if prop is null or prop->>'padrao' <> 'mesmo_email_nomes_diferentes' or prop->>'confianca' <> 'baixa' then raise exception 'D5.7 esperava mesmo_email_nomes_diferentes/baixa: %', prop; end if;
  falhou := false;
  begin
    perform public.mind_fusao_decidir('nomes_divergentes', 'aprovar', 'contrato_d5');
  exception when invalid_parameter_value then falhou := true;
  end;
  if not falhou then raise exception 'D5.7 aprovou nomes_divergentes em bloco'; end if;
  if (select fundida_em from pessoas.pessoas where id in (f, g) and fundida_em is not null limit 1) is not null then raise exception 'D5.7 fundiu sem decisão linha a linha'; end if;

  -- ---------- 9. inscrição por terceiro: a secretária e o colega (Adriana, 23/09) ----------
  -- Sueli compra dois credenciamentos com o telefone e o CPF dela: o dela e o de Carlos.
  -- Telefone igual, CPF igual, nome e e-mail diferentes = duas pessoas; o telefone é da Sueli.
  insert into credenciamento_summit_2026.participantes (id, name, email, cellphone, buyer_email, status, sincronizado_em)
    values (gen_random_uuid(), 'Sueli Secretaria', mail_s, tel_s, mail_s, 'ativo', now())
    returning pessoa_id, pessoa_criterio into s, crit;
  if s is null then raise exception 'D5.9 a compradora deveria ganhar pessoa (criterio=%)', crit; end if;
  if (select pessoa_id from engagement.identidades where canal = 'whatsapp' and identificador = tel_s) is distinct from s then
    raise exception 'D5.9 o telefone deveria ser da Sueli';
  end if;
  insert into credenciamento_summit_2026.participantes (id, name, email, cellphone, buyer_email, status, sincronizado_em)
    values (gen_random_uuid(), 'Carlos Colega', mail_k, tel_s, mail_s, 'ativo', now())
    returning pessoa_id, pessoa_criterio into k, crit;
  if k is null or k = s then raise exception 'D5.9 colega inscrito pela secretária deveria ser OUTRA pessoa (k=%, s=%, criterio=%)', k, s, crit; end if;
  if crit not like '%inscrito por terceiro%' then raise exception 'D5.9 critério deveria dizer inscrito por terceiro: %', crit; end if;
  if exists (select 1 from engagement.identidades where pessoa_id = k and canal = 'whatsapp') then raise exception 'D5.9 o telefone da compradora foi colado ao colega'; end if;
  if (select primeiro_nome from pessoas.pessoas where id = s) <> 'Sueli' or (select primeiro_nome from pessoas.pessoas where id = k) <> 'Carlos' then
    raise exception 'D5.9 nomes trocados entre compradora e colega';
  end if;
  if exists (select 1 from engagement.identidade_fusoes where status = 'pendente' and participante_origem is not null
              and least(participante_id, participante_origem) = least(s, k) and greatest(participante_id, participante_origem) = greatest(s, k)) then
    raise exception 'D5.9 pessoas diferentes inscritas por terceiro não viram proposta de fusão';
  end if;

  -- ---------- 10. mesmo telefone e CPF, nome E e-mail diferentes, sem dado de comprador: outra pessoa ----------
  insert into eduzz.vendas (linha_origem, fatura, cliente_nome, cliente_email, cliente_fones, cliente_documento, sincronizado_em)
    values (900000000 + floor(random() * 99999999)::int, 'D5V' || suf, 'Marcos Outro', mail_k2, tel_s, '11144477735', now())
    returning pessoa_id, pessoa_criterio into k2, crit;
  if k2 is null or k2 = s then raise exception 'D5.10 nome e e-mail distintos com telefone igual deveria ser outra pessoa (k2=%, criterio=%)', k2, crit; end if;
  if crit not like '%recusou: whatsapp de outra pessoa, nome e e-mail distintos%' then raise exception 'D5.10 critério deveria explicar a recusa: %', crit; end if;
  if exists (select 1 from engagement.identidade_fusoes where status = 'pendente' and participante_origem is not null
              and least(participante_id, participante_origem) = least(s, k2) and greatest(participante_id, participante_origem) = greatest(s, k2)) then
    raise exception 'D5.10 nome e e-mail distintos = pessoas diferentes: sem proposta';
  end if;

  -- ---------- 11. mesmo telefone, mesmo nome, e-mail diferente: suspeita (proposta média), não fusão ----------
  insert into eduzz.vendas (linha_origem, fatura, cliente_nome, cliente_email, cliente_fones, sincronizado_em)
    values (900000000 + floor(random() * 99999999)::int, 'D5W' || suf, 'Sueli Secretária', mail_s2, tel_s, now())
    returning pessoa_id, pessoa_criterio into s2, crit;
  if s2 is null or s2 = s then raise exception 'D5.11 e-mail diferente com telefone igual não liga sozinho (s2=%, criterio=%)', s2, crit; end if;
  select proposta into prop from engagement.identidade_fusoes where status = 'pendente' and participante_origem is not null
    and least(participante_id, participante_origem) = least(s, s2) and greatest(participante_id, participante_origem) = greatest(s, s2) limit 1;
  if prop is null or prop->>'padrao' <> 'mesmo_telefone_emails_diferentes' or prop->>'confianca' <> 'media' then
    raise exception 'D5.11 esperava proposta mesmo_telefone_emails_diferentes/media: %', prop;
  end if;
  if (select fundida_em from pessoas.pessoas where id in (s, s2) and fundida_em is not null limit 1) is not null then raise exception 'D5.11 fundiu sem decisão'; end if;

  -- ---------- 12. mesmo e-mail: nome parecido é a mesma pessoa; nome claramente diferente não se liga ----------
  insert into eduzz.ingressos (uuid, participante, email, email_comprador, cod_participante, sincronizado_em)
    values ('d5-sueli-' || suf, 'Sueli Secretaria Souza', upper(mail_s), mail_s, 'D5S' || suf, now())
    returning pessoa_id, pessoa_criterio into e, crit;
  if e <> s then raise exception 'D5.12 mesmo e-mail com sobrenome a mais deveria ser a Sueli (e=%, s=%)', e, s; end if;
  if crit not like 'email%' then raise exception 'D5.12 critério deveria começar por email: %', crit; end if;
  insert into eduzz.ingressos (uuid, participante, email, email_comprador, cod_participante, sincronizado_em)
    values ('d5-roberto-' || suf, 'Roberto Diferente', mail_s, mail_s, 'D5R' || suf, now())
    returning pessoa_id, pessoa_criterio into r2, crit;
  if r2 is null or r2 = s then raise exception 'D5.12 mesmo e-mail com nome claramente diferente não pode cair na Sueli (r2=%, criterio=%)', r2, crit; end if;
  if (select pessoa_id from engagement.identidades where canal = 'email' and identificador = mail_s) <> s then raise exception 'D5.12 o e-mail mudou de dona'; end if;
  select proposta into prop from engagement.identidade_fusoes where status = 'pendente' and participante_origem is not null
    and least(participante_id, participante_origem) = least(s, r2) and greatest(participante_id, participante_origem) = greatest(s, r2) limit 1;
  if prop is null or prop->>'padrao' <> 'mesmo_email_nomes_diferentes' or prop->>'confianca' <> 'baixa' then
    raise exception 'D5.12 esperava proposta mesmo_email_nomes_diferentes/baixa: %', prop;
  end if;
  falhou := false;
  begin
    perform public.mind_fusao_decidir('mesmo_email_nomes_diferentes', 'aprovar', 'contrato_d5');
  exception when invalid_parameter_value then falhou := true;
  end;
  if not falhou then raise exception 'D5.12 aprovou mesmo_email_nomes_diferentes em bloco'; end if;
  -- só e-mail de outra pessoa e nome diferente, sem outro identificador: não cria ninguém, a linha entra e explica
  insert into crm.leads_capturados (firstname, lastname, email) values ('Roberta', 'Diferente', mail_s) returning pessoa_id, pessoa_criterio into f, crit;
  if f is not null or crit not like 'identificador_forte_de_outra_pessoa%' then raise exception 'D5.12 lead com e-mail alheio e nome diferente: esperava sem pessoa, veio (%, %)', f, crit; end if;

  -- ---------- 13. fase A e HubSpot obedecem à mesma regra ----------
  r := public.mind_pessoa_enriquecer(s);
  if exists (select 1 from engagement.identidades where pessoa_id = s and identificador in (mail_k, mail_k2, mail_s2)) then
    raise exception 'D5.13 enriquecer colou à Sueli o e-mail de outra pessoa: %', r;
  end if;
  if (r->>'linhas_ignoradas_pela_regra')::int < 1 then raise exception 'D5.13 enriquecer deveria ter ignorado a linha do colega: %', r; end if;
  insert into crm.contato_espelho (hubspot_id, email, phone, firstname, lastname)
    values (hub_z, mail_z, '+' || tel_s, 'Zeca', 'Outro');
  r := public.mind_crm_vincular_pessoa(s);
  if (select pessoa_id from crm.contato_espelho where hubspot_id = hub_z) is not null then
    raise exception 'D5.13 contato do HubSpot com nome diferente foi ligado à Sueli pelo telefone: %', r;
  end if;
  if (r->>'recusados_pela_regra_do_nome')::int < 1 then raise exception 'D5.13 vincular deveria listar o contato recusado: %', r; end if;
  if exists (select 1 from engagement.identidades where pessoa_id = s and identificador in (mail_z, hub_z)) then raise exception 'D5.13 identificadores do Zeca colados à Sueli'; end if;

  -- ---------- 8. a pessoa com todos os ids, numa linha ----------
  if not exists (select 1 from pessoas.v_pessoa_360 v where v.pessoa_id = b
                  and hub_a = any(v.hubspot_ids) and v.whatsapp = tel_a
                  and v.credenciamento_ids is not null and v.auth_user_id = auth_b::text) then
    raise exception 'D5.8 v_pessoa_360 não mostra B com hubspot, whatsapp, credenciamento e login';
  end if;

  raise notice 'contrato D5 ok — enriquecer não cria, fundir só por decisão, CPF não decide, trigger carimba, id antigo resolve, nome e e-mail vencem (secretária/colega separados, nome parecido junta, e-mail alheio não cola)';
end $$;

rollback;
