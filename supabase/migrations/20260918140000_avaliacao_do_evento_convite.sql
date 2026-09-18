-- ============================================================
-- Avaliação do evento — o convite por link
-- ============================================================
-- Projeto: mind-agent (ymnmotgglsrxmjmonwjz)
--
-- ⚠ GATE. Esta migration cria um jeito de a pessoa ser reconhecida SEM
-- login: um token no link vale como identidade para responder uma
-- pesquisa. Isso é identidade e é auth, e pelo `CLAUDE.md` não entra em
-- produção sem gate explícito da Adriana. O disparo do link por WhatsApp
-- ou e-mail é outro gate, separado deste.
--
-- Escrita e NÃO aplicada.
--
-- O QUE ISTO RESOLVE
-- A pesquisa do evento só alcança quem abre o app. Quem parou de abrir
-- depois do Summit — que é justamente quem tem mais a dizer sobre o
-- Summit inteiro — nunca vê o card. O convite alcança essa pessoa.
--
-- O QUE O TOKEN PODE E O QUE NÃO PODE
--   pode ... abrir a pesquisa do evento como aquela pessoa e gravar UMA
--            resposta, com `origem = 'convite'`.
--   não pode. ler resposta de ninguém, ver cadastro, entrar no app,
--            abrir chat, mexer em ingresso, valer depois de expirar,
--            valer depois de revogado, valer para outro evento.
--
-- O TOKEN NUNCA É GRAVADO. O banco guarda só o SHA-256 dele, do mesmo
-- jeito que se guarda senha: um vazamento desta tabela não entrega link
-- que funcione. Quem calcula o hash é a Edge Function, que já tem
-- `sha256` — assim o token cru não atravessa nem o log de consulta do
-- banco. Sem esta escolha, um `select *` daria acesso à resposta de
-- todo mundo que ainda não respondeu.
--
-- O TOKEN VAI NO FRAGMENTO DA URL (`#c=...`), e não na query string: o
-- fragmento não é enviado ao servidor, então não entra em log de borda,
-- em Referer nem em histórico de proxy.
--
-- O QUE ISTO NÃO TOCA
--   tabela nova ........... engagement.avaliacao_do_evento_convite
--   funções novas ......... 4
--   função reescrita ...... public.mind_avaliacao_do_evento_registrar,
--                           para passar a delegar a gravação ao mesmo
--                           lugar que o convite usa. É função da MESMA
--                           entrega, ainda não aplicada em produção — e
--                           duplicar a validação em dois corpos seria
--                           garantir que eles divirjam.
--   modificado ............ nada de terceiros
--
-- DEPENDE de `20260918120000_avaliacao_do_evento.sql` e de
-- `20260918180000_avaliacao_do_evento_atividades.sql` aplicadas. A
-- segunda trouxe as notas por atividade DEPOIS desta ser escrita, e o
-- corpo comum daqui foi atualizado para tratá-las: sem isso, aplicar
-- esta migration apagaria as notas de atividade sem erro nenhum.
--
-- DESFAZER
--   drop function if exists public.mind_avaliacao_do_evento_registrar_por_convite(text,jsonb);
--   drop function if exists public.mind_avaliacao_do_evento_estado_por_convite(text);
--   drop function if exists public.mind_avaliacao_do_evento_convite_criar(text,uuid,text,timestamptz);
--   drop function if exists public.mind_avaliacao_do_evento_convite_resolver(text,text);
--   drop function if exists engagement.avaliacao_do_evento_gravar(uuid,uuid,jsonb,text);
--   drop table if exists engagement.avaliacao_do_evento_convite;
--   (e reponha a versão anterior de mind_avaliacao_do_evento_registrar)

-- ============================================================
-- 1 · O convite
-- ============================================================

create table if not exists engagement.avaliacao_do_evento_convite (
  id uuid primary key default gen_random_uuid(),

  participante_id uuid not null
    references pessoas.pessoas(id) on delete restrict,
  event_id uuid not null
    references summit_2026.events(id) on delete restrict,

  -- SHA-256 do token, em hexadecimal minúsculo. Nunca o token.
  token_hash text not null,

  -- Sempre tem fim. Convite sem prazo é credencial permanente, e nenhum
  -- link que identifica alguém deveria durar para sempre.
  expira_em timestamptz not null,

  -- Revogar não apaga: apaga-se a capacidade de entrar, não o registro
  -- de que o convite existiu e foi usado.
  revogado_em timestamptz,

  -- Quando a resposta foi gravada por este convite. Depois disso ele não
  -- abre mais nada — a pesquisa é de uma resposta só.
  usado_em timestamptz,

  -- Quantas vezes o link foi aberto, e quando foi a última. Serve para
  -- ler a taxa de abertura e para enxergar uso estranho.
  aberturas integer not null default 0,
  ultimo_acesso_em timestamptz,

  criado_em timestamptz not null default now(),

  -- UM CONVITE POR PESSOA, POR EVENTO. Reenviar troca o token do mesmo
  -- convite em vez de criar um segundo válido: dois links vivos para a
  -- mesma pessoa é uma credencial a mais para esquecer de revogar.
  constraint avaliacao_do_evento_convite_unico
    unique (participante_id, event_id),

  -- O hash tem tamanho fixo e alfabeto fixo. Qualquer outra coisa aqui é
  -- erro de quem escreveu, não dado.
  constraint avaliacao_do_evento_convite_hash_valido
    check (token_hash ~ '^[0-9a-f]{64}$')
);

comment on table engagement.avaliacao_do_evento_convite is
  'Convite por link para a Avaliação do evento. Guarda o SHA-256 do token, nunca o token. Vale para uma resposta, expira, e pode ser revogado.';
comment on column engagement.avaliacao_do_evento_convite.token_hash is
  'SHA-256 do token em hex minúsculo, calculado fora do banco. O token cru não existe aqui nem no log.';

create unique index if not exists avaliacao_do_evento_convite_hash_ix
  on engagement.avaliacao_do_evento_convite (token_hash);

alter table engagement.avaliacao_do_evento_convite enable row level security;

-- ============================================================
-- 2 · A gravação, num lugar só
-- ============================================================
-- As duas portas — app logado e convite — validam a MESMA resposta e
-- gravam na MESMA tabela. O que muda entre elas é só como se descobre
-- quem é a pessoa. Por isso a validação e a gravação moram aqui, e as
-- duas portas chamam este corpo.
--
-- Esta função NÃO é chamável de fora: ela recebe o participante já
-- resolvido, e quem a chama é quem provou a identidade. É por isso que
-- ela vive em `engagement` e não em `public`, e não ganha grant nenhum.

create or replace function engagement.avaliacao_do_evento_gravar(
  p_participante_id uuid,
  p_event_id uuid,
  p_payload jsonb,
  p_origem text
)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_existente engagement.avaliacao_do_evento%rowtype;
  v_id uuid;
  v_experiencia text;
  v_profissao text;
  v_expectativas text;
  v_nota_rel smallint;
  v_nota_prog smallint;
  v_mais_gostou text;
  v_melhorar text;
  v_comentario text;
  v_atividades jsonb;
  v_invalidas int;
  v_iguais boolean;
begin
  v_experiencia  := lower(btrim(coalesce(p_payload->>'experiencia', '')));
  v_profissao    := btrim(coalesce(p_payload->>'profissao', ''));
  v_expectativas := btrim(coalesce(p_payload->>'expectativas', ''));
  v_mais_gostou  := nullif(btrim(coalesce(p_payload->>'maisGostou', '')), '');
  v_melhorar     := nullif(btrim(coalesce(p_payload->>'melhorar', '')), '');
  v_comentario   := nullif(btrim(coalesce(p_payload->>'comentario', '')), '');

  if v_experiencia not in ('mind', 'vip', 'prime') then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:experiencia';
  end if;
  if char_length(v_profissao) < 1 or char_length(v_profissao) > 120 then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:profissao';
  end if;
  if char_length(v_expectativas) < 1 or char_length(v_expectativas) > 1000 then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:expectativas';
  end if;
  if coalesce(char_length(v_mais_gostou), 0) > 1000
     or coalesce(char_length(v_melhorar), 0) > 1000
     or coalesce(char_length(v_comentario), 0) > 1000 then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:texto_longo';
  end if;

  -- `jsonb_typeof` antes do cast: `"3"` e `3` chegam diferentes de
  -- clientes diferentes, e um cast direto de texto vazio explodiria com
  -- erro de banco em vez de erro de validação.
  if jsonb_typeof(p_payload->'notaRelevancia') <> 'number'
     or jsonb_typeof(p_payload->'notaProgramacao') <> 'number' then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:nota_obrigatoria';
  end if;
  v_nota_rel  := (p_payload->>'notaRelevancia')::numeric;
  v_nota_prog := (p_payload->>'notaProgramacao')::numeric;
  if v_nota_rel not between 0 and 5 or v_nota_prog not between 0 and 5
     or (p_payload->>'notaRelevancia')::numeric <> v_nota_rel
     or (p_payload->>'notaProgramacao')::numeric <> v_nota_prog then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:nota_fora_da_faixa';
  end if;

  /* AS NOTAS POR ATIVIDADE ATRAVESSAM AS DUAS PORTAS. Elas entraram na
     pesquisa depois desta migration ser escrita (20260918180000), e
     precisam ser tratadas AQUI: esta função é o corpo único, e a porta
     do app delega para ela. Sem isto, aplicar esta migration depois
     daquela apagaria as notas de atividade sem erro nenhum. */
  v_atividades := coalesce(p_payload->'atividades', '[]'::jsonb);
  if jsonb_typeof(v_atividades) <> 'array' then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:atividades';
  end if;

  select count(*) into v_invalidas
  from jsonb_array_elements(v_atividades) a
  where jsonb_typeof(a->'nota') <> 'number'
     or (a->>'nota')::numeric not between 0 and 5
     or (a->>'nota')::numeric <> floor((a->>'nota')::numeric)
     or not exists (
       select 1 from summit_2026.sessions s
       where s.id = nullif(a->>'sessaoId', '')::uuid
         and s.event_id = p_event_id
         and s.tipo is distinct from 'credenciamento'
         and s.tipo is distinct from 'intervalo'
         and s.tipo is distinct from 'almoco'
     );
  if v_invalidas > 0 then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:sessao_invalida';
  end if;

  if (select count(*) from jsonb_array_elements(v_atividades) a)
     <> (select count(distinct a->>'sessaoId') from jsonb_array_elements(v_atividades) a) then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:sessao_repetida';
  end if;

  -- A MESMA TRAVA PARA AS DUAS PORTAS. Ela é sobre a pessoa e o evento,
  -- e não sobre por onde a pessoa entrou: abrir o app numa aba e o
  -- convite noutra não pode virar duas respostas.
  perform pg_advisory_xact_lock(
    hashtext('avaliacao_do_evento'),
    hashtext(p_participante_id::text || p_event_id::text)
  );

  select * into v_existente from engagement.avaliacao_do_evento a
  where a.participante_id = p_participante_id and a.event_id = p_event_id;

  if found then
    v_iguais :=
      v_existente.experiencia = v_experiencia
      and v_existente.profissao = v_profissao
      and v_existente.expectativas = v_expectativas
      and v_existente.nota_relevancia = v_nota_rel
      and v_existente.nota_programacao = v_nota_prog
      and v_existente.mais_gostou is not distinct from v_mais_gostou
      and v_existente.melhorar is not distinct from v_melhorar
      and v_existente.comentario is not distinct from v_comentario
      and (
        select coalesce(jsonb_object_agg(at.sessao_id::text, at.nota), '{}'::jsonb)
        from engagement.avaliacao_do_evento_atividade at
        where at.avaliacao_id = v_existente.id
      ) = (
        select coalesce(jsonb_object_agg(novo.sid::text, novo.nota), '{}'::jsonb)
        from (
          select nullif(a->>'sessaoId', '')::uuid as sid, (a->>'nota')::smallint as nota
          from jsonb_array_elements(v_atividades) a
        ) novo
      );

    if v_iguais then
      return jsonb_build_object('id', v_existente.id, 'jaRegistrado', true,
                                'enviadoEm', v_existente.enviado_em);
    end if;
    raise exception using errcode = '23505', message = 'avaliacao_ja_enviada';
  end if;

  insert into engagement.avaliacao_do_evento (
    participante_id, event_id, formulario_versao, experiencia, profissao,
    expectativas, nota_relevancia, nota_programacao, mais_gostou, melhorar,
    comentario, origem
  ) values (
    p_participante_id, p_event_id, 2, v_experiencia, v_profissao,
    v_expectativas, v_nota_rel, v_nota_prog, v_mais_gostou, v_melhorar,
    v_comentario, p_origem
  ) returning id into v_id;

  insert into engagement.avaliacao_do_evento_atividade (avaliacao_id, sessao_id, nota)
  select v_id, nullif(a->>'sessaoId','')::uuid, (a->>'nota')::smallint
  from jsonb_array_elements(v_atividades) a
  on conflict (avaliacao_id, sessao_id) do nothing;

  return jsonb_build_object('id', v_id, 'jaRegistrado', false,
    'enviadoEm', (select enviado_em from engagement.avaliacao_do_evento where id = v_id));
end;
$function$;

revoke execute on function engagement.avaliacao_do_evento_gravar(uuid, uuid, jsonb, text) from public;

comment on function engagement.avaliacao_do_evento_gravar(uuid, uuid, jsonb, text) is
  'Valida e grava a resposta do evento para um participante JÁ RESOLVIDO. Não é porta: quem chama é quem provou a identidade. Sem grant para ninguém.';

-- A janela também num lugar só, pelo mesmo motivo: ela é a mesma para as
-- duas portas, e um prazo que vale numa e não na outra é um buraco.
create or replace function engagement.avaliacao_do_evento_janela(
  p_config jsonb,
  p_fuso text
)
 returns void
 language plpgsql
 stable
 set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_hoje date := (now() at time zone p_fuso)::date;
  v_abre date := nullif(p_config->>'abre', '')::date;
  v_fecha date := nullif(p_config->>'fecha', '')::date;
begin
  if not coalesce((p_config->>'ativo')::boolean, false) then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:pesquisa_desligada';
  end if;
  if v_abre is not null and v_hoje < v_abre then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:ainda_nao_abriu';
  end if;
  if v_fecha is not null and v_hoje > v_fecha then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:ja_fechou';
  end if;
end;
$function$;

revoke execute on function engagement.avaliacao_do_evento_janela(jsonb, text) from public;

-- ============================================================
-- 3 · A porta do app passa a usar o mesmo corpo
-- ============================================================
-- Mesma assinatura, mesmo comportamento, mesma recusa. O que muda é que
-- a validação deixou de morar aqui — e por isso ela não tem mais como
-- divergir da validação do convite.

create or replace function public.mind_avaliacao_do_evento_registrar(
  p_auth_user_id uuid,
  p_event_slug text,
  p_payload jsonb
)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_config jsonb;
  v_evento summit_2026.events%rowtype;
  v_participante_id uuid;
begin
  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;

  select c.valor into v_config from concierge.config c where c.chave = 'avaliacao_do_evento';
  perform engagement.avaliacao_do_evento_janela(v_config, v_evento.fuso);

  -- Quem responde é o dono da sessão Auth, pelo vínculo canônico. Sem
  -- vínculo não há resposta para gravar — e não existe coleta anônima
  -- nesta pesquisa.
  select i.pessoa_id into v_participante_id
  from engagement.identidades i
  where i.canal = 'auth_user' and i.identificador = p_auth_user_id::text
  order by i.criado_em desc limit 1;
  if v_participante_id is null then
    raise exception using errcode = '28000', message = 'avaliacao_sem_identidade';
  end if;

  return engagement.avaliacao_do_evento_gravar(
    v_participante_id, v_evento.id, p_payload, 'app');
end;
$function$;

-- ============================================================
-- 4 · Resolver o convite
-- ============================================================
-- Recebe o HASH do token, nunca o token. Devolve quem é a pessoa, ou o
-- motivo de não devolver — e conta a abertura.
--
-- O MOTIVO NÃO VAZA O QUE NÃO EXISTE: token desconhecido e token
-- revogado devolvem o mesmo `invalido`. Dizer "este existe mas está
-- revogado" transformaria a função num oráculo para adivinhar tokens.
-- Expirado e já usado são ditos, porque quem os tem é a pessoa certa e
-- precisa entender o que aconteceu.

create or replace function public.mind_avaliacao_do_evento_convite_resolver(
  p_token_hash text,
  p_event_slug text default 'mind-summit-2026'
)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_evento summit_2026.events%rowtype;
  v_convite engagement.avaliacao_do_evento_convite%rowtype;
begin
  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;

  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('valido', false, 'motivo', 'invalido');
  end if;

  select * into v_convite from engagement.avaliacao_do_evento_convite c
  where c.token_hash = p_token_hash and c.event_id = v_evento.id;

  if not found or v_convite.revogado_em is not null then
    return jsonb_build_object('valido', false, 'motivo', 'invalido');
  end if;
  if v_convite.expira_em <= now() then
    return jsonb_build_object('valido', false, 'motivo', 'expirado');
  end if;
  if v_convite.usado_em is not null then
    return jsonb_build_object('valido', false, 'motivo', 'ja_respondida');
  end if;

  update engagement.avaliacao_do_evento_convite
  set aberturas = aberturas + 1, ultimo_acesso_em = now()
  where id = v_convite.id;

  return jsonb_build_object(
    'valido', true,
    'participanteId', v_convite.participante_id,
    'eventId', v_evento.id
  );
end;
$function$;

comment on function public.mind_avaliacao_do_evento_convite_resolver(text, text) is
  'Troca o hash de um token de convite pela pessoa. Token desconhecido e revogado devolvem o mesmo motivo, para a função não virar oráculo.';

-- ============================================================
-- 5 · As duas portas do convite
-- ============================================================

create or replace function public.mind_avaliacao_do_evento_estado_por_convite(
  p_token_hash text,
  p_event_slug text default 'mind-summit-2026'
)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_evento summit_2026.events%rowtype;
  v_config jsonb;
  v_resolvido jsonb;
  v_participante_id uuid;
  v_hoje date;
  v_abre date;
  v_fecha date;
  v_motivo text;
  v_resposta engagement.avaliacao_do_evento%rowtype;
  v_sugerida text;
begin
  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;

  v_resolvido := public.mind_avaliacao_do_evento_convite_resolver(p_token_hash, p_event_slug);
  if not coalesce((v_resolvido->>'valido')::boolean, false) then
    return jsonb_build_object(
      'ativo', false,
      'motivo', v_resolvido->>'motivo',
      'identificado', false,
      'porConvite', true);
  end if;
  v_participante_id := (v_resolvido->>'participanteId')::uuid;

  select c.valor into v_config from concierge.config c where c.chave = 'avaliacao_do_evento';
  v_abre  := nullif(v_config->>'abre', '')::date;
  v_fecha := nullif(v_config->>'fecha', '')::date;
  v_hoje  := (now() at time zone v_evento.fuso)::date;
  v_motivo := case
    when not coalesce((v_config->>'ativo')::boolean, false) then 'desligada'
    when v_abre is not null and v_hoje < v_abre then 'ainda_nao_abriu'
    when v_fecha is not null and v_hoje > v_fecha then 'ja_fechou'
    else null
  end;

  select * into v_resposta from engagement.avaliacao_do_evento a
  where a.participante_id = v_participante_id and a.event_id = v_evento.id;

  select case lower(r.ticket_category)
           when 'mind' then 'mind' when 'vip' then 'vip' when 'prime' then 'prime'
         end into v_sugerida
  from summit_2026.registrations r
  where r.person_id = v_participante_id and r.event_id = v_evento.id and r.status = 'ativa'
  order by r.criado_em desc limit 1;

  -- O NOME VAI, o e-mail NÃO. A tela precisa dizer "Olá, Fulana" para a
  -- pessoa reconhecer que o link é dela; e-mail numa página aberta por
  -- link é dado pessoal em tela que qualquer um com o link enxerga.
  return jsonb_build_object(
    'ativo', v_motivo is null,
    'motivo', v_motivo,
    'identificado', true,
    'porConvite', true,
    'primeiroNome', (select p.primeiro_nome from pessoas.pessoas p where p.id = v_participante_id),
    'evento', jsonb_build_object('slug', v_evento.slug, 'nome', v_evento.nome,
                                 'fuso', v_evento.fuso, 'dias', to_jsonb(v_evento.dias)),
    'janela', jsonb_build_object('abre', v_abre, 'fecha', v_fecha),
    'formularioVersao', 1,
    'enviado', v_resposta.id is not null,
    'enviadoEm', v_resposta.enviado_em,
    'experienciaSugerida', v_sugerida
  );
end;
$function$;

create or replace function public.mind_avaliacao_do_evento_registrar_por_convite(
  p_token_hash text,
  p_payload jsonb,
  p_event_slug text default 'mind-summit-2026'
)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_evento summit_2026.events%rowtype;
  v_config jsonb;
  v_resolvido jsonb;
  v_participante_id uuid;
  v_saida jsonb;
begin
  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;

  select c.valor into v_config from concierge.config c where c.chave = 'avaliacao_do_evento';
  perform engagement.avaliacao_do_evento_janela(v_config, v_evento.fuso);

  -- QUEM RESPONDE SAI DO TOKEN, e o cliente nunca manda participante.
  -- É a mesma garantia da porta do app, com outra prova de identidade.
  v_resolvido := public.mind_avaliacao_do_evento_convite_resolver(p_token_hash, p_event_slug);
  if not coalesce((v_resolvido->>'valido')::boolean, false) then
    raise exception using errcode = '28000',
      message = 'avaliacao_convite:' || coalesce(v_resolvido->>'motivo', 'invalido');
  end if;
  v_participante_id := (v_resolvido->>'participanteId')::uuid;

  v_saida := engagement.avaliacao_do_evento_gravar(
    v_participante_id, v_evento.id, p_payload, 'convite');

  -- O convite se queima na mesma transação da resposta. Se a gravação
  -- falhar, ele continua valendo; se passar, ele não abre mais.
  update engagement.avaliacao_do_evento_convite
  set usado_em = now()
  where participante_id = v_participante_id and event_id = v_evento.id and usado_em is null;

  return v_saida;
end;
$function$;

-- ============================================================
-- 6 · Emitir convite
-- ============================================================
-- Recebe o hash porque o token cru nasce e morre na Edge Function: ela
-- sorteia, guarda o hash aqui e devolve o link UMA vez, para o disparo.
-- Nem o banco nem o painel conseguem reconstruir um link já emitido —
-- perdeu, emite outro, e o de antes deixa de valer.

create or replace function public.mind_avaliacao_do_evento_convite_criar(
  p_event_slug text,
  p_participante_id uuid,
  p_token_hash text,
  p_expira_em timestamptz
)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_evento summit_2026.events%rowtype;
  v_id uuid;
begin
  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:token';
  end if;
  if p_expira_em is null or p_expira_em <= now() then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:expira_em';
  end if;
  if not exists (select 1 from pessoas.pessoas p where p.id = p_participante_id) then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:participante';
  end if;

  -- Já respondeu, não recebe convite: seria mandar alguém para uma porta
  -- que só sabe dizer não.
  if exists (
    select 1 from engagement.avaliacao_do_evento a
    where a.participante_id = p_participante_id and a.event_id = v_evento.id
  ) then
    raise exception using errcode = '23505', message = 'avaliacao_ja_enviada';
  end if;

  -- Reemitir TROCA o token do mesmo convite, e zera o uso. Dois links
  -- vivos para a mesma pessoa é uma credencial a mais para esquecer de
  -- revogar.
  insert into engagement.avaliacao_do_evento_convite (
    participante_id, event_id, token_hash, expira_em
  ) values (
    p_participante_id, v_evento.id, p_token_hash, p_expira_em
  )
  on conflict (participante_id, event_id) do update
  set token_hash = excluded.token_hash,
      expira_em = excluded.expira_em,
      revogado_em = null,
      usado_em = null,
      criado_em = now()
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'expiraEm', p_expira_em);
end;
$function$;

comment on function public.mind_avaliacao_do_evento_convite_criar(text, uuid, text, timestamptz) is
  'Emite ou reemite o convite de uma pessoa. Recebe o hash; o token cru nunca chega ao banco. Reemitir troca o token do mesmo convite em vez de criar um segundo válido.';

-- ============================================================
-- 7 · Permissões mínimas
-- ============================================================
-- Só `service_role`, como o resto da pesquisa. `anon` e `authenticated`
-- não alcançam nem o convite nem a resposta: quem confere o token é a
-- Edge Function, que é também quem calcula o hash.

revoke execute on function public.mind_avaliacao_do_evento_convite_resolver(text, text) from public;
revoke execute on function public.mind_avaliacao_do_evento_convite_criar(text, uuid, text, timestamptz) from public;
revoke execute on function public.mind_avaliacao_do_evento_estado_por_convite(text, text) from public;
revoke execute on function public.mind_avaliacao_do_evento_registrar_por_convite(text, jsonb, text) from public;

grant execute on function public.mind_avaliacao_do_evento_convite_resolver(text, text) to service_role;
grant execute on function public.mind_avaliacao_do_evento_convite_criar(text, uuid, text, timestamptz) to service_role;
grant execute on function public.mind_avaliacao_do_evento_estado_por_convite(text, text) to service_role;
grant execute on function public.mind_avaliacao_do_evento_registrar_por_convite(text, jsonb, text) to service_role;
