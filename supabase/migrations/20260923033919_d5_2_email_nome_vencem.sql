-- ============================================================================
-- D5.2 — e-mail, nome e sobrenome vencem; depois WhatsApp; depois CPF; depois CNPJ
-- ============================================================================
-- Regras da Adriana, 23/09/2026 (madrugada), nas palavras dela:
--
--   "Às vezes uma secretária vai fazer um credenciamento para alguém. Ela pode
--    colocar um telefone igual, um CPF igual, mas não o nome igual. O nome e o
--    sobrenome devem ser sempre fontes de verdade."
--   "O que interessa para nós é e-mail, nome, sobrenome: vencem. Depois, o
--    WhatsApp. Depois, CPF. Depois, CNPJ."
--   "Nome e sobrenome às vezes vêm com grafia errada, com um sobrenome a mais ou
--    a menos — tem similaridade suficiente, e o e-mail é o mesmo: é a mesma pessoa."
--   "Pessoas com e-mails distintos e nomes distintos não podem ser consideradas a
--    mesma pessoa." — mesmo com telefone e CPF idênticos: são pessoas diferentes
--    inscritas por um terceiro.
--   "E-mail distinto e nome igual: suspeita de que é a mesma pessoa" (proposta).
--   "Antes de criar qualquer coisa, sempre bater com a tabela pessoas.pessoas."
--
-- O que a primeira migration D5 (20260923024555) fazia de errado, medido entre
-- 02:47 e 03:03 UTC, quando o sync da Eduzz e o espelho do credenciamento
-- dispararam os triggers novos: uma linha casava por TELEFONE (força 3 > e-mail
-- força 2) e colava à pessoa dona do telefone o e-mail, o CPF e o id de quem quer
-- que estivesse na linha — inclusive os colegas inscritos pelo comprador.
-- Exemplos reais: uma compradora da Vale recebeu os e-mails de cinco colegas; um
-- comprador da Eduzz, dezenas de CPFs e códigos de participante. 13.205
-- identificadores nasceram nesse intervalo; os triggers foram desligados às 03:1x
-- e são religados aqui, já com a regra nova. A reconstrução do intervalo é um
-- script à parte (scripts/infra/identidade/20_desfazer_janela_2309.sql).
--
-- O que muda, e só isso:
--   1. mind_nomes_compativeis: nome parecido (sem acento, grafia, sobrenome a
--      mais ou a menos, apelido) é o mesmo nome; primeiro nome diferente não é.
--   2. precedência quando identificadores discordam: login > id de terceiro >
--      e-mail > WhatsApp > CPF > CNPJ (mind_identidade_precedencia). A força
--      continua dizendo quem reconhece sozinho (>= 2); a precedência diz quem
--      vence.
--   3. a porta única: pessoa achada só por telefone/CPF com nome divergente é
--      OUTRA pessoa; achada só por telefone com e-mail divergente é outra pessoa
--      (ou suspeita, se o nome for igual: proposta média); achada por e-mail
--      com nome claramente diferente não se liga (e-mail de comprador/porta-voz)
--      e vira proposta baixa. Antes de criar, procura também nas colunas de
--      pessoas.pessoas. Nunca cria pessoa quando todos os identificadores fortes
--      já são de gente recusada pela regra.
--   4. o trigger: linha comprada por terceiro (e-mail do participante diferente
--      do e-mail do comprador) entrega e-mail, nome e ids — não telefone nem
--      CPF, que são do comprador. pessoa_criterio passa a dizer POR ONDE a
--      pessoa foi encontrada e o que foi acrescentado. Chave de manutenção
--      mind.d5_pular_trigger.
--   5. fase A (enriquecer) e ligação com o HubSpot obedecem às mesmas regras.
--   6. mind_pessoa_fundir: auditoria com action 'atualizar' (o CHECK de
--      mind_admin_audit não aceita 'fundir' — falhou no contrato em produção).
--   7. padrão novo mesmo_email_nomes_diferentes (baixa, nunca em bloco).
--
-- Idempotente. Provada no Postgres descartável com o contrato
-- tests/d5_identidade_universal_contract.sql (cenários D5.9–D5.12 novos).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Nome: normalizar, tokenizar, comparar com tolerância
-- ----------------------------------------------------------------------------
create or replace function public.mind_nome_normalizar(p_nome text)
returns text
language sql
immutable
parallel safe
as $function$
  select nullif(btrim(regexp_replace(
           regexp_replace(
             translate(lower(replace(coalesce(p_nome,''), 'Ã¯Â¿Â½', '')),   -- mojibake do caractere de substituição
                       'áàâãäåéèêëíìîïóòôõöúùûüçñýÿ', 'aaaaaaeeeeiiiiooooouuuucnyy'),
             '[^a-z ]', ' ', 'g'),
           '\s+', ' ', 'g')), '');
$function$;
comment on function public.mind_nome_normalizar(text) is 'Nome em minúsculas, sem acento, sem pontuação, sem o mojibake do caractere de substituição; nulo quando não sobra nada.';

create or replace function public.mind_nome_tokens(p_nome text)
returns text[]
language sql
immutable
parallel safe
as $function$
  select coalesce(array_agg(t order by ord), '{}'::text[])
    from unnest(string_to_array(coalesce(public.mind_nome_normalizar(p_nome), ''), ' ')) with ordinality as u(t, ord)
   where t <> '' and length(t) > 1
     and t not in ('de','da','do','das','dos','e','di','del','della','van','von','der','la','le',
                   'dr','dra','sr','sra','prof','profa','eng');
$function$;
comment on function public.mind_nome_tokens(text) is 'Tokens do nome normalizado, sem conectivos (de, da, dos…) nem títulos (dr, sra…).';

create or replace function public.mind_nomes_compativeis(p_a text, p_b text)
returns boolean
language sql
immutable
parallel safe
as $function$
  with a as (select public.mind_nome_tokens(p_a) t, coalesce(public.mind_nome_normalizar(p_a), '') s),
       b as (select public.mind_nome_tokens(p_b) t, coalesce(public.mind_nome_normalizar(p_b), '') s)
  select case
    when cardinality(a.t) = 0 or cardinality(b.t) = 0 then true              -- sem nome de um lado: nada contradiz
    when a.t[1] = b.t[1] then true                                            -- mesmo primeiro nome
    when public.similarity(a.t[1], b.t[1]) >= 0.5 then true                   -- grafia (Geovanna/Geovana)
    when public.similarity(a.s, b.s) >= 0.6 then true                         -- sobrenome a mais/a menos, acento, mojibake
    when least(length(a.t[1]), length(b.t[1])) >= 3
         and (a.t[1] like b.t[1] || '%' or b.t[1] like a.t[1] || '%')
         and a.t[cardinality(a.t)] = b.t[cardinality(b.t)] then true         -- apelido (Sol Conforto / Solismar … Conforto)
    when (a.t[1] = any(b.t) or b.t[1] = any(a.t))
         and a.t[cardinality(a.t)] = b.t[cardinality(b.t)]
         and (select count(*) from unnest(a.t) x where x = any(b.t)) >= 2 then true   -- nome composto (Ana Paula Souza / Paula Souza)
    else false end
  from a, b;
$function$;
comment on function public.mind_nomes_compativeis(text, text) is
  'A regra do nome (Adriana, 23/09): dois nomes são compatíveis quando um dos lados não tem nome, quando o primeiro nome é o mesmo (ou parecido: grafia, acento), quando o nome inteiro é parecido (sobrenome a mais ou a menos), ou quando um é apelido/parte composta do outro com o mesmo último sobrenome. Primeiro nome claramente diferente = pessoa diferente. Usa pg_trgm.';

create or replace function public.mind_identidade_precedencia(p_canal text)
returns int
language sql
immutable
parallel safe
as $function$
  select case p_canal
    when 'auth_user' then 1
    when 'hubspot' then 2 when 'yazo' then 2 when 'credenciamento' then 2 when 'eduzz' then 2 when 'learnworlds' then 2
    when 'email' then 3
    when 'whatsapp' then 4 when 'telefone' then 4
    when 'cpf' then 5
    when 'cnpj' then 6
    else 9 end;
$function$;
comment on function public.mind_identidade_precedencia(text) is
  'Quem vence quando os identificadores de uma entrada apontam para pessoas diferentes (Adriana, 23/09): login (1) > id de terceiro (2) > e-mail (3) > WhatsApp (4) > CPF (5) > CNPJ (6). A força (mind_identificadores_normalizar) diz quem reconhece sozinho; a precedência, quem ganha a disputa.';

-- procurar nas colunas da propria pessoa sem varrer a tabela
create index if not exists pessoas_email_lower_idx on pessoas.pessoas (lower(email)) where email is not null;

-- ----------------------------------------------------------------------------
-- 2. Bater com pessoas.pessoas: o que está nas colunas da pessoa está em identidades
-- ----------------------------------------------------------------------------
insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca)
select p.id, 'hubspot', p.hubspot_id, true, 'alta'
  from pessoas.pessoas p
 where p.hubspot_id is not null and p.fundida_em is null
   and not exists (select 1 from engagement.identidades i where i.canal = 'hubspot' and i.identificador = p.hubspot_id)
on conflict (canal, identificador) do nothing;
insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca)
select p.id, 'email', lower(p.email), false, 'media'
  from pessoas.pessoas p
 where p.email is not null and p.fundida_em is null
   and not exists (select 1 from engagement.identidades i where i.canal = 'email' and i.identificador = lower(p.email))
on conflict (canal, identificador) do nothing;
insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca)
select p.id, 'whatsapp', p.whatsapp, true, 'alta'
  from pessoas.pessoas p
 where p.whatsapp is not null and p.fundida_em is null
   and not exists (select 1 from engagement.identidades i where i.canal = 'whatsapp' and i.identificador = p.whatsapp)
on conflict (canal, identificador) do nothing;

-- ----------------------------------------------------------------------------
-- 3. Proposta de fusão: nome com tolerância, padrão novo para e-mail com nomes diferentes
-- ----------------------------------------------------------------------------
create or replace function public.mind_fusao_propor(p_a uuid, p_b uuid, p_canal_conflito text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, engagement, pessoas
as $function$
declare
  ca text[]; cb text[]; nome_a text; nome_b text; n_a int; n_b int; c_a timestamptz; c_b timestamptz;
  v_padrao text; v_sob uuid; v_abs uuid; v_conf text; v_motivo text; v_tel_pessoas int := 0;
  v_prop jsonb; cpf_a text; cpf_b text; v_nota text := ''; v_nomes_ok boolean; v_nome_igual boolean;
begin
  if p_a is null or p_b is null or p_a = p_b then return null; end if;
  -- CPF/CNPJ nunca abrem proposta sozinhos (Adriana, 23/09)
  if p_canal_conflito in ('cpf','cnpj') then return null; end if;

  select coalesce(array_agg(distinct canal), '{}'), count(*) into ca, n_a from engagement.identidades where pessoa_id = p_a;
  select coalesce(array_agg(distinct canal), '{}'), count(*) into cb, n_b from engagement.identidades where pessoa_id = p_b;
  select concat_ws(' ', primeiro_nome, sobrenome), criado_em into nome_a, c_a from pessoas.pessoas where id = p_a;
  select concat_ws(' ', primeiro_nome, sobrenome), criado_em into nome_b, c_b from pessoas.pessoas where id = p_b;
  select identificador into cpf_a from engagement.identidades where pessoa_id = p_a and canal = 'cpf' limit 1;
  select identificador into cpf_b from engagement.identidades where pessoa_id = p_b and canal = 'cpf' limit 1;
  v_nomes_ok   := public.mind_nomes_compativeis(nome_a, nome_b);
  v_nome_igual := cardinality(public.mind_nome_tokens(nome_a)) > 0 and cardinality(public.mind_nome_tokens(nome_b)) > 0 and v_nomes_ok;

  if p_canal_conflito = 'whatsapp' then
    select count(distinct i.pessoa_id) into v_tel_pessoas
      from engagement.identidades i
     where i.canal = 'whatsapp'
       and i.identificador in (select identificador from engagement.identidades where pessoa_id in (p_a, p_b) and canal = 'whatsapp');
  end if;

  v_padrao := case
    when not v_nomes_ok and p_canal_conflito = 'email' then 'mesmo_email_nomes_diferentes'
    when not v_nomes_ok then 'nomes_divergentes'
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
    when 'mesmo_email' then 'mesmo e-mail em duas pessoas, nomes compatíveis'
    when 'mesmo_email_nomes_diferentes' then 'mesmo e-mail com nomes claramente diferentes: e-mail de comprador ou porta-voz? decidir linha a linha'
    when 'mesmo_telefone_emails_diferentes' then 'mesmo telefone, nomes compatíveis, e-mails diferentes: suspeita de mesma pessoa com dois e-mails — caso a caso'
    when 'telefone_compartilhado' then 'telefone em mais de duas pessoas (central/empresa/comprador): nunca aprovar em bloco'
    when 'nomes_divergentes' then 'mesmo telefone com nomes diferentes: provavelmente inscrição por terceiro — decidir linha a linha'
    else 'identificador em comum sem padrão conhecido' end;

  if cpf_a is not null and cpf_b is not null and cpf_a <> cpf_b then
    v_conf := 'baixa'; v_nota := v_nota || '; CPFs diferentes nas duas pessoas: conferir';
  elsif cpf_a is not null and cpf_a = cpf_b then
    v_nota := v_nota || '; mesmo CPF nas duas';
  end if;
  if v_nome_igual then v_nota := v_nota || '; nomes compatíveis'; end if;
  v_motivo := v_motivo || v_nota;

  v_prop := jsonb_build_object('sobrevive', v_sob, 'absorvida', v_abs, 'padrao', v_padrao,
                               'motivo', v_motivo, 'confianca', v_conf, 'canal', p_canal_conflito,
                               'cpf_igual', (cpf_a is not null and cpf_a = cpf_b), 'nome_igual', v_nome_igual,
                               'nomes', jsonb_build_array(nome_a, nome_b));

  update engagement.identidade_fusoes f
     set padrao = v_padrao, proposta = v_prop
   where f.status = 'pendente'
     and f.participante_origem is not null
     and least(f.participante_id, f.participante_origem) = least(p_a, p_b)
     and greatest(f.participante_id, f.participante_origem) = greatest(p_a, p_b);
  return v_prop;
end $function$;

comment on function public.mind_fusao_propor(uuid, uuid, text) is
  'Dado um par de pessoas que compartilham um identificador, classifica o padrão da duplicata e propõe quem sobrevive (login no app > mais identificadores > mais antiga). Nome compara com tolerância (mind_nomes_compativeis). Só grava a proposta na pendência já registrada em identidade_fusoes. Não funde: isso é mind_fusao_decidir.';

comment on column engagement.identidade_fusoes.padrao is
  'Padrão da duplicata: mesmo_email_hubspot_x_login, mesmo_email_dois_hubspot, mesmo_email (alta: podem ser aprovados em bloco); mesmo_telefone_emails_diferentes (média: nomes compatíveis, e-mails diferentes — suspeita, linha a linha); mesmo_email_nomes_diferentes, telefone_compartilhado e nomes_divergentes (baixa: sempre linha a linha); outro. CPF nunca gera padrão sozinho.';

-- ----------------------------------------------------------------------------
-- 4. A porta única: e-mail, nome e sobrenome vencem
-- ----------------------------------------------------------------------------
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
  v_recusados jsonb := '[]'::jsonb;
  v_cand      record;
  v_pessoa    uuid;
  v_outro     uuid;
  v_criada    boolean := false;
  v_conflito  jsonb := null;
  v_nome      text := nullif(left(btrim(coalesce(p_nome,'')),160),'');
  v_nome_pessoa text;
  v_primeiro  text;
  v_sobrenome text;
  v_tel       text;
  v_mail      text;
  v_dono      uuid;
  v_vinculadas jsonb := '[]'::jsonb;
  v_origem    text;
  v_canal_conf text;
  v_tem_email_entrada boolean;
  v_casou_por text[];
  v_nome_divergente boolean := false;
  v_r         jsonb;
begin
  if jsonb_array_length(v_ids) = 0 then
    return jsonb_build_object('pessoa_id', p_pessoa_ancora, 'criada', false,
      'motivo','sem_identificador_deterministico', 'conflito', null,
      'ancorada', p_pessoa_ancora is not null, 'identidades', '[]'::jsonb, 'casou_por', '[]'::jsonb, 'recusados', '[]'::jsonb);
  end if;

  -- Serializa somente entradas que compartilham o mesmo identificador.
  for v_item in
    select x.value from jsonb_array_elements(v_ids) as x(value)
     order by x.value->>'canal', x.value->>'identificador'
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('mind_identidade:' || (v_item->>'canal') || ':' || (v_item->>'identificador'), 0));
  end loop;

  v_tem_email_entrada := exists (select 1 from jsonb_array_elements(v_ids) x where x->>'canal' = 'email');

  -- Procura em identidades e, faltando ali, nas colunas da propria pessoas.pessoas
  -- (Adriana, 23/09: "antes de criar, sempre bater com a tabela pessoas.pessoas").
  for v_item in select * from jsonb_array_elements(v_ids) loop
    select i.pessoa_id into v_outro
      from engagement.identidades i
     where i.canal = v_item->>'canal' and i.identificador = v_item->>'identificador'
     limit 1;
    if v_outro is null then
      select p.id into v_outro from pessoas.pessoas p
       where p.fundida_em is null
         and ((v_item->>'canal' = 'email'    and lower(p.email) = v_item->>'identificador')
           or (v_item->>'canal' = 'whatsapp' and p.whatsapp = v_item->>'identificador')
           or (v_item->>'canal' = 'hubspot'  and p.hubspot_id = v_item->>'identificador'))
       limit 1;
    end if;
    if v_outro is not null then
      v_outro := coalesce(public.mind_pessoa_canonica(v_outro), v_outro);
      v_achados := v_achados || jsonb_build_array(jsonb_build_object(
        'pessoa_id', v_outro, 'forca', (v_item->>'forca')::int, 'canal', v_item->>'canal', 'identificador', v_item->>'identificador'));
    end if;
  end loop;

  -- A regra da Adriana (23/09), so quando a entrada nao vem ancorada numa pessoa:
  --   * achada so por telefone/CPF/CNPJ com nome que contradiz o da entrada -> outra pessoa (inscrita por terceiro);
  --   * achada so por telefone, com e-mail dos dois lados e nenhum em comum -> outra pessoa
  --     (se os nomes forem compativeis, vira suspeita: proposta media);
  --   * achada por e-mail com nome claramente diferente -> nao se liga (e-mail de comprador/porta-voz): proposta baixa;
  --   * login e ids de terceiro identificam o registro naquele sistema: ligam sempre; nome divergente fica marcado.
  if p_pessoa_ancora is null then
    for v_cand in
      select a.pessoa_id,
             min(public.mind_identidade_precedencia(a.canal)) as prec,
             array_agg(distinct a.canal) as canais,
             bool_or(a.forca >= 2) as forte
        from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text, identificador text)
       group by a.pessoa_id
    loop
      if not v_cand.forte or v_cand.prec <= 2 then continue; end if;   -- apoio (CPF/CNPJ) ou id deterministico: nada a recusar
      select concat_ws(' ', p.primeiro_nome, p.sobrenome) into v_nome_pessoa from pessoas.pessoas p where p.id = v_cand.pessoa_id;
      if v_nome is not null and not public.mind_nomes_compativeis(v_nome, v_nome_pessoa) then
        v_recusados := v_recusados || jsonb_build_array(jsonb_build_object(
          'pessoa_id', v_cand.pessoa_id, 'canais', to_jsonb(v_cand.canais), 'canal', v_cand.canais[1],
          'motivo', case when v_cand.prec = 3 then 'email_igual_nome_diferente'
                         when v_tem_email_entrada and exists (select 1 from engagement.identidades i where i.pessoa_id = v_cand.pessoa_id and i.canal = 'email')
                              then 'nome_e_email_diferentes' else 'nome_diferente' end,
          'nome_pessoa', v_nome_pessoa));
      elsif v_cand.prec = 4 and v_tem_email_entrada
            and exists (select 1 from engagement.identidades i where i.pessoa_id = v_cand.pessoa_id and i.canal = 'email') then
        v_recusados := v_recusados || jsonb_build_array(jsonb_build_object(
          'pessoa_id', v_cand.pessoa_id, 'canais', to_jsonb(v_cand.canais), 'canal', 'whatsapp',
          'motivo', 'email_diferente', 'nome_pessoa', v_nome_pessoa));
      end if;
    end loop;
    if jsonb_array_length(v_recusados) > 0 then
      select coalesce(jsonb_agg(a), '[]'::jsonb) into v_achados
        from jsonb_array_elements(v_achados) a
       where not exists (select 1 from jsonb_array_elements(v_recusados) r where r->>'pessoa_id' = a->>'pessoa_id');
    end if;
  end if;

  -- Escolha: a ancora manda; sem ancora, a precedencia decide entre evidencias fortes (forca >= 2).
  if p_pessoa_ancora is not null then
    v_pessoa := p_pessoa_ancora;
  else
    select a.pessoa_id into v_pessoa
      from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text, identificador text)
      join pessoas.pessoas p on p.id = a.pessoa_id
     where a.forca >= 2
     order by public.mind_identidade_precedencia(a.canal), (a.canal = p_canal) desc, p.criado_em asc
     limit 1;
  end if;

  if exists (select 1 from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text, identificador text)
              where v_pessoa is not null and a.pessoa_id <> v_pessoa and a.forca >= 2) then
    v_conflito := jsonb_build_object('pessoa_escolhida', v_pessoa,
                                     'ancorada', p_pessoa_ancora is not null,
                                     'evidencias', v_achados);
    for v_outro in
      select distinct a.pessoa_id
        from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text, identificador text)
       where a.pessoa_id <> v_pessoa and a.forca >= 2
    loop
      perform public.mind_conflito_registrar(
        v_pessoa, 'conflito_identidade',
        case when p_pessoa_ancora is not null
             then 'evidencia nova aponta para outra pessoa; conversa ancorada permanece'
             else 'identificadores da mesma entrada apontam para pessoas diferentes' end,
        v_outro, v_ids);
      select a.canal into v_canal_conf
        from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text, identificador text)
       where a.pessoa_id = v_outro and a.forca >= 2
       order by public.mind_identidade_precedencia(a.canal) limit 1;
      perform public.mind_fusao_propor(v_pessoa, v_outro, v_canal_conf);
    end loop;
  end if;

  if v_pessoa is null then
    -- D5: sem identificador forte (força >= 2) não se cria pessoa
    if not exists (select 1 from jsonb_array_elements(v_ids) x where (x->>'forca')::int >= 2) then
      return jsonb_build_object('pessoa_id', null, 'criada', false,
        'motivo','sem_identificador_forte', 'conflito', null,
        'ancorada', false, 'identidades', '[]'::jsonb, 'casou_por', '[]'::jsonb, 'recusados', v_recusados);
    end if;
    -- Todos os identificadores fortes ja sao de pessoas recusadas pela regra do nome/e-mail:
    -- nao ha o que criar (a pessoa nova nasceria sem identificador proprio). Fica para decisao.
    if not exists (select 1 from jsonb_array_elements(v_ids) x
                    where (x->>'forca')::int >= 2
                      and not exists (select 1 from jsonb_array_elements(v_recusados) r
                                       join jsonb_array_elements(v_ids) y on y->>'canal' = x->>'canal' and y->>'identificador' = x->>'identificador'
                                      where (r->'canais') ? (x->>'canal')
                                        and exists (select 1 from engagement.identidades i where i.pessoa_id = (r->>'pessoa_id')::uuid
                                                       and i.canal = x->>'canal' and i.identificador = x->>'identificador'))) then
      return jsonb_build_object('pessoa_id', null, 'criada', false,
        'motivo','identificador_forte_de_outra_pessoa', 'conflito', null,
        'ancorada', false, 'identidades', '[]'::jsonb, 'casou_por', '[]'::jsonb, 'recusados', v_recusados);
    end if;
    -- D5: quem chamou pediu para ligar sem criar (fase A ainda não terminou)
    if not p_criar then
      return jsonb_build_object('pessoa_id', null, 'criada', false,
        'motivo','criacao_desligada', 'conflito', null,
        'ancorada', false, 'identidades', '[]'::jsonb, 'casou_por', '[]'::jsonb, 'recusados', v_recusados);
    end if;

    v_primeiro  := nullif(split_part(coalesce(v_nome,''), ' ', 1), '');
    v_sobrenome := nullif(btrim(substr(coalesce(v_nome,''), coalesce(length(v_primeiro),0) + 2)), '');
    v_tel  := (select x->>'identificador' from jsonb_array_elements(v_ids) x where x->>'canal'='whatsapp' limit 1);
    v_mail := (select x->>'identificador' from jsonb_array_elements(v_ids) x where x->>'canal'='email'    limit 1);

    if v_mail is not null and (exists (select 1 from pessoas.pessoas p where lower(p.email) = v_mail)
                               or exists (select 1 from engagement.identidades i where i.canal = 'email' and i.identificador = v_mail))
      then v_mail := null; end if;
    if v_tel is not null and (exists (select 1 from pessoas.pessoas p where p.whatsapp = v_tel)
                              or exists (select 1 from engagement.identidades i where i.canal = 'whatsapp' and i.identificador = v_tel))
      then v_tel := null; end if;

    v_origem := case
      when p_canal in ('contato_espelho','hubspot') then 'hubspot'
      when p_canal in ('pedidos','compradores','checkout') then 'checkout'
      when p_canal in ('participantes','yazo_espelho','credenciamento') or p_canal ilike 'relatorio%' or p_canal ilike 'yazo%' then 'credenciamento'
      when p_canal in ('ingressos','vendas','eduzz') then 'eduzz'
      when p_canal in ('leads_capturados','site') then 'site'
      else 'bot' end;

    insert into pessoas.pessoas (primeiro_nome, sobrenome, whatsapp, email, origem, enriquecida_em)
    values (v_primeiro, v_sobrenome, v_tel, v_mail, v_origem, now())
    returning id into v_pessoa;
    v_criada := true;
  elsif v_nome is not null then
    select concat_ws(' ', p.primeiro_nome, p.sobrenome) into v_nome_pessoa from pessoas.pessoas p where p.id = v_pessoa;
    v_nome_divergente := not public.mind_nomes_compativeis(v_nome, v_nome_pessoa);
    if not v_nome_divergente then
      v_primeiro  := nullif(split_part(v_nome, ' ', 1), '');
      v_sobrenome := nullif(btrim(substr(v_nome, coalesce(length(v_primeiro),0) + 2)), '');
      update pessoas.pessoas
         set primeiro_nome = coalesce(primeiro_nome, v_primeiro),
             sobrenome     = coalesce(sobrenome, v_sobrenome),
             atualizado_em = now()
       where id = v_pessoa and (primeiro_nome is null or sobrenome is null);
    end if;
  end if;

  -- por onde a pessoa foi encontrada (antes de acrescentar o que faltava)
  select coalesce(array_agg(distinct a.canal order by a.canal), '{}') into v_casou_por
    from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text, identificador text)
   where a.pessoa_id = v_pessoa;

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

  -- Recusados que ainda merecem um olhar da Adriana: nome igual com e-mail diferente (suspeita, media)
  -- e e-mail igual com nome diferente (comprador/porta-voz?, baixa). Nome E e-mail diferentes sao,
  -- por decisao dela, pessoas diferentes inscritas por terceiro: nao viram proposta.
  for v_r in select r from jsonb_array_elements(v_recusados) r
              where r->>'motivo' in ('email_diferente', 'email_igual_nome_diferente')
  loop
    if (v_r->>'pessoa_id')::uuid <> v_pessoa then
      perform public.mind_conflito_registrar(
        v_pessoa, 'conflito_identidade',
        case v_r->>'motivo'
          when 'email_diferente' then 'mesmo telefone, nomes compatíveis, e-mails diferentes: suspeita de mesma pessoa'
          else 'mesmo e-mail com nomes claramente diferentes: e-mail de comprador ou porta-voz?' end,
        (v_r->>'pessoa_id')::uuid, v_ids);
      perform public.mind_fusao_propor(v_pessoa, (v_r->>'pessoa_id')::uuid, v_r->>'canal');
    end if;
  end loop;

  return jsonb_build_object(
    'pessoa_id', v_pessoa, 'criada', v_criada, 'conflito', v_conflito,
    'ancorada', p_pessoa_ancora is not null, 'identidades', v_vinculadas,
    'casou_por', to_jsonb(v_casou_por), 'nome_divergente', v_nome_divergente, 'recusados', v_recusados);
end $function$;

revoke all on function public.mind_identidade_resolver(jsonb, text, text, uuid, boolean) from public;
grant execute on function public.mind_identidade_resolver(jsonb, text, text, uuid, boolean) to service_role;
comment on function public.mind_identidade_resolver(jsonb, text, text, uuid, boolean) is
  'A única porta que escreve identidade. Normaliza os identificadores, procura em engagement.identidades e nas colunas de pessoas.pessoas, escolhe a pessoa pela precedência (login > id de terceiro > e-mail > WhatsApp; CPF/CNPJ são apoio), cria a pessoa quando não acha e existe identificador forte livre (e p_criar permite), registra conflito com proposta quando identificadores fortes apontam para pessoas diferentes — e nunca funde. Regra do nome (Adriana, 23/09): pessoa achada só por telefone/CPF com nome divergente é outra pessoa; só por telefone com e-mail divergente é outra pessoa (suspeita se o nome for igual); por e-mail com nome claramente diferente não se liga (proposta). Devolve casou_por (por onde achou), identidades (o que acrescentou) e recusados.';

-- ----------------------------------------------------------------------------
-- 5. Ligar um contato do CRM à pessoa obedece à mesma regra
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
  v_tel_ok text[] := array[]::text[];
  t        text;
  v_n      int;
  v_hubs   text[];
  v_amb    jsonb := '[]'::jsonb;
  c        record;
  v_r      jsonb;
  v_vinc   int := 0;
  v_ja     int := 0;
  v_conf   int := 0;
  v_ident  int := 0;
  v_recus  int := 0;
  v_lista  jsonb := '[]'::jsonb;
  v_nome_pessoa text;
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
  select concat_ws(' ', p.primeiro_nome, p.sobrenome),
         case when p.email is not null and not (lower(p.email) = any(coalesce(v_mail, '{}'))) then coalesce(v_mail, '{}') || lower(p.email) else v_mail end
    into v_nome_pessoa, v_mail
    from pessoas.pessoas p where p.id = p_pessoa_id;

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
    -- Regra do nome/e-mail (Adriana, 23/09): por e-mail ou telefone, o nome do contato nao pode
    -- contradizer o da pessoa; por telefone, o e-mail do contato nao pode ser outro.
    if c.via <> 'hubspot_id' and not public.mind_nomes_compativeis(v_nome_pessoa, concat_ws(' ', c.firstname, c.lastname)) then
      v_recus := v_recus + 1;
      v_lista := v_lista || jsonb_build_array(jsonb_build_object(
        'hubspot_id', c.hubspot_id, 'via', c.via,
        'situacao', case when c.pessoa_id = p_pessoa_id then 'ja_ligado_nome_divergente' else 'nao_vinculado_nome_divergente' end,
        'nome_contato', concat_ws(' ', c.firstname, c.lastname)));
      continue;
    end if;
    if c.via = 'telefone' and nullif(btrim(coalesce(c.email,'')),'') is not null and v_mail is not null
       and not (lower(btrim(c.email)) = any(v_mail)) then
      v_recus := v_recus + 1;
      v_lista := v_lista || jsonb_build_array(jsonb_build_object(
        'hubspot_id', c.hubspot_id, 'via', c.via,
        'situacao', case when c.pessoa_id = p_pessoa_id then 'ja_ligado_email_divergente' else 'nao_vinculado_email_divergente' end,
        'email_contato', lower(btrim(c.email))));
      if c.pessoa_id is null or c.pessoa_id = p_pessoa_id then continue; end if;
    end if;

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
      perform public.mind_fusao_propor(p_pessoa_id, c.pessoa_id, case c.via when 'hubspot_id' then 'hubspot' when 'telefone' then 'whatsapp' else c.via end);
      v_conf := v_conf + 1;
      v_lista := v_lista || jsonb_build_array(jsonb_build_object(
        'hubspot_id', c.hubspot_id, 'situacao', 'conflito', 'via', c.via, 'dono', c.pessoa_id));
      continue;
    end if;

    -- D5 (causa-raiz das 586): o contato inteiro vira identidade da pessoa, ancorado.
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
    'conflitos', v_conf, 'identidades_hubspot_novas', v_ident, 'recusados_pela_regra_do_nome', v_recus,
    'telefones_ambiguos', v_amb, 'contatos', v_lista);
end $function$;

comment on function public.mind_crm_vincular_pessoa(uuid) is
  'Único escritor de crm.contato_espelho.pessoa_id. Liga a pessoa aos contatos do HubSpot por hubspot_id, e-mail ou telefone inequívoco, e registra na pessoa o e-mail, os telefones e o nome do contato. Regra do nome (Adriana, 23/09): por e-mail ou telefone o nome do contato não pode contradizer o da pessoa; por telefone o e-mail do contato não pode ser outro — nesses casos não liga e lista o contato como recusado.';

-- ----------------------------------------------------------------------------
-- 6. O trigger: comprado por terceiro, critério legível, chave de manutenção
-- ----------------------------------------------------------------------------
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
  v_criar boolean;
  v_comprador text;
  v_terceiro boolean := false;
  v_crit  text;
  v_acresc text;
  v_flags text := '';
begin
  -- chave de manutencao: reconstrucoes e cargas controladas passam sem a porta
  if coalesce(current_setting('mind.d5_pular_trigger', true), '') = '1' then
    return NEW;
  end if;

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
    elsif v_k = 'comprador_email' then
      v_comprador := lower(btrim(v_vals->>0));
    elsif v_k in ('emails','telefones','hubspot_ids','yazo_ids') then
      v_ids := v_ids || jsonb_build_object(v_k, v_vals);
    else
      v_ids := v_ids || jsonb_build_object(v_k, v_vals->>0);
    end if;
  end loop;

  if not v_mudou and NEW.pessoa_id is not null then
    return NEW;
  end if;

  -- Inscricao feita por terceiro (Adriana, 23/09): o e-mail do participante e outro que o do
  -- comprador -> telefone e CPF da linha sao do comprador, nao da pessoa. Ficam de fora.
  if v_comprador is not null and jsonb_typeof(v_ids->'emails') = 'array'
     and not exists (select 1 from jsonb_array_elements_text(v_ids->'emails') e where lower(btrim(e)) = v_comprador) then
    v_terceiro := true;
    v_ids := v_ids - array['telefones','whatsapp','telefone','phone','cpf','documento','cnpj','eduzz_comprador'];
  end if;

  begin
    v_criar := not exists (select 1 from pessoas.pessoas where enriquecida_em is null and fundida_em is null);
    v_r := public.mind_identidade_resolver(v_ids, v_nome, TG_TABLE_NAME::text, null, v_criar);
    NEW.pessoa_id := (v_r->>'pessoa_id')::uuid;
    NEW.pessoa_resolvido_em := now();
    if v_terceiro then v_flags := v_flags || ' (inscrito por terceiro: telefone/CPF ignorados)'; end if;
    if jsonb_array_length(coalesce(v_r->'recusados', '[]'::jsonb)) > 0 then
      select ' (recusou: ' || string_agg((r->>'canal') || ' de outra pessoa, ' ||
               case r->>'motivo' when 'nome_e_email_diferentes' then 'nome e e-mail distintos'
                                 when 'nome_diferente' then 'nome distinto'
                                 when 'email_diferente' then 'e-mail distinto'
                                 else 'nome distinto para o mesmo e-mail' end, '; ') || ')'
        into v_acresc from jsonb_array_elements(v_r->'recusados') r;
      v_flags := v_flags || coalesce(v_acresc, '');
    end if;
    if NEW.pessoa_id is null then
      NEW.pessoa_criterio := (case when v_r->>'motivo' = 'criacao_desligada' then 'aguardando_fase_a' else coalesce(v_r->>'motivo', 'sem_pessoa') end) || v_flags;
    else
      select string_agg(x, ',' order by x) into v_acresc from (select distinct (y->>'canal') x from jsonb_array_elements(coalesce(v_r->'identidades','[]'::jsonb)) y) s;
      if (v_r->>'criada')::boolean then
        v_crit := 'criada: ' || coalesce(v_acresc, 'sem identificador');
      else
        select string_agg(x, ',' order by x) into v_crit from jsonb_array_elements_text(coalesce(v_r->'casou_por','[]'::jsonb)) x;
        v_crit := coalesce(v_crit, 'ancora');
        if v_acresc is not null then v_crit := v_crit || ' +' || v_acresc; end if;
      end if;
      if v_r->'conflito' is not null and jsonb_typeof(v_r->'conflito') <> 'null' then v_flags := ' (conflito)' || v_flags; end if;
      if (v_r->>'nome_divergente')::boolean then v_flags := ' (nome divergente)' || v_flags; end if;
      NEW.pessoa_criterio := v_crit || v_flags;
    end if;
  exception when others then
    NEW.pessoa_criterio := 'erro: ' || left(sqlerrm, 200);
    NEW.pessoa_resolvido_em := now();
  end;
  return NEW;
end $function$;

revoke all on function public.mind_pessoa_antes_de_escrever() from public;
comment on function public.mind_pessoa_antes_de_escrever() is
  'Trigger BEFORE INSERT OR UPDATE das tabelas que falam de pessoa (D5). Lê os identificadores da linha pelo mapa em TG_ARGV[0], passa pela porta única mind_identidade_resolver e preenche pessoa_id, pessoa_criterio e pessoa_resolvido_em. Critério: por onde a pessoa foi encontrada ("email,whatsapp"), o que foi acrescentado ("+cpf,eduzz"), "criada: …" quando nasceu aqui, "(conflito)", "(nome divergente)", "(inscrito por terceiro: telefone/CPF ignorados)" quando o e-mail do participante difere do e-mail do comprador (chave comprador_email do mapa), "(recusou: …)" quando a regra do nome/e-mail deixou alguém de fora. Só cria pessoa quando nenhuma pessoa existente está por enriquecer. Falha de identidade não bloqueia a escrita. set_config(''mind.d5_pular_trigger'',''1'',true) desliga a porta na transação (manutenção).';

-- Religa as fontes com os mapas novos (recria o trigger habilitado — os triggers
-- foram desligados manualmente as 03:1x UTC de 23/09 para estancar a colagem).
do $$
begin
  perform public.mind_pessoa_ligar_tabela('crm.contato_espelho',
    '{"hubspot_ids":["hubspot_id"],"emails":["email"],"telefones":["phone","hs_whatsapp_phone_number"],"nome":["firstname","lastname"]}');
  perform public.mind_pessoa_ligar_tabela('credenciamento_summit_2026.participantes',
    '{"emails":["email"],"telefones":["telefone_norm","cellphone"],"credenciamento_id":"id","yazo_id":"yazo_user_id","nome":["name"],"comprador_email":["buyer_email"]}');
  perform public.mind_pessoa_ligar_tabela('credenciamento_summit_2026.yazo_espelho',
    '{"emails":["email"],"telefones":["attributes.cellphone"],"yazo_id":"yazo_id","nome":["name"],"comprador_email":["attributes.text_40"]}');
  perform public.mind_pessoa_ligar_tabela('eduzz.ingressos',
    '{"emails":["email"],"telefones":["telefone_norm","telefone"],"documento":"cpf_cnpj","eduzz_participante":"cod_participante","nome":["participante"],"comprador_email":["email_comprador"]}');
  perform public.mind_pessoa_ligar_tabela('eduzz.vendas',
    '{"emails":["cliente_email"],"telefones":["cliente_telefone_norm"],"documento":"cliente_documento","nome":["cliente_nome"]}');
  perform public.mind_pessoa_ligar_tabela('crm.leads_capturados',
    '{"emails":["email"],"telefones":["phone"],"nome":["firstname","lastname"]}');
  perform public.mind_pessoa_ligar_tabela('checkout.pedidos',
    '{"emails":["comprador_email"],"telefones":["comprador_telefone"],"documento":"comprador_documento","nome":["comprador_nome"]}');
  if to_regclass('credenciamento_summit_2026."Relatorio Yazzo Consolidado"') is not null then
    perform public.mind_pessoa_ligar_tabela('credenciamento_summit_2026."Relatorio Yazzo Consolidado"',
      '{"emails":["Email Participante"],"telefones":["WhatsApp"],"nome":["Nome Participante"],"comprador_email":["Email do comprador"]}');
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 7. Fase A: enriquecer obedece à mesma regra
-- ----------------------------------------------------------------------------
-- Uma fonte contribui para a pessoa quando o nome da linha nao contradiz o dela.
-- Linha achada SO por telefone contribui apenas se: nao e inscricao por terceiro,
-- o e-mail dela nao e outro que o da pessoa, e o telefone aponta para um so
-- e-mail naquela fonte. Linha comprada por terceiro nunca entrega telefone nem
-- CPF (sao do comprador). HubSpot: telefone que identifica um so contato.
create or replace function public.mind_pessoa_enriquecer(p_pessoa_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, engagement, pessoas
as $function$
declare
  v_emails text[]; v_tels text[]; v_hubs text[]; v_docs text[]; v_yazo text[]; v_cred text[]; v_edz text[]; v_lw text[];
  v_nome text; v_ids jsonb := '{}'::jsonb; v_r jsonb; v_antes int; v_depois int; v_ignoradas int; v_usadas int;
  v_nome_pessoa text;
begin
  if p_pessoa_id is null then return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa'); end if;
  if exists (select 1 from pessoas.pessoas where id = p_pessoa_id and fundida_em is not null) then
    return jsonb_build_object('ok', false, 'motivo', 'pessoa_fundida');
  end if;

  select count(*) into v_antes from engagement.identidades where pessoa_id = p_pessoa_id;
  select concat_ws(' ', primeiro_nome, sobrenome) into v_nome_pessoa from pessoas.pessoas where id = p_pessoa_id;

  create temp table if not exists d5_fontes_tmp (
    fonte text, email text, tel text, doc text, id_canal text, id_valor text, nome text,
    via_forte boolean, terceiro boolean, tel_ambiguo boolean) on commit drop;
  delete from d5_fontes_tmp;

  with atual as (
    select canal, identificador from engagement.identidades where pessoa_id = p_pessoa_id
    union select 'email', lower(email) from pessoas.pessoas where id = p_pessoa_id and email is not null
    union select 'whatsapp', whatsapp from pessoas.pessoas where id = p_pessoa_id and whatsapp is not null
    union select 'hubspot', hubspot_id from pessoas.pessoas where id = p_pessoa_id and hubspot_id is not null
  )
  insert into d5_fontes_tmp
  -- HubSpot
  select 'hubspot', lower(btrim(c.email)), t.tel, null, 'hubspot', c.hubspot_id,
         nullif(btrim(concat_ws(' ', c.firstname, c.lastname)), ''),
         (c.pessoa_id = p_pessoa_id or c.hubspot_id in (select identificador from atual where canal = 'hubspot')
            or lower(btrim(c.email)) in (select identificador from atual where canal = 'email')),
         false,
         (select count(*) > 1 from crm.contato_espelho d
           where public.telefone_normalizar(d.phone) = t.tel or public.telefone_normalizar(d.hs_whatsapp_phone_number) = t.tel)
    from crm.contato_espelho c
    cross join lateral (select coalesce(public.telefone_normalizar(c.hs_whatsapp_phone_number), public.telefone_normalizar(c.phone)) as tel) t
   where c.pessoa_id = p_pessoa_id
      or c.hubspot_id in (select identificador from atual where canal = 'hubspot')
      or lower(btrim(c.email)) in (select identificador from atual where canal = 'email')
      or public.telefone_normalizar(c.phone) in (select identificador from atual where canal = 'whatsapp')
      or public.telefone_normalizar(c.hs_whatsapp_phone_number) in (select identificador from atual where canal = 'whatsapp')
  union all
  -- credenciamento (o CPF da linha e o do comprador: fora)
  select 'credenciamento', lower(btrim(p.email)), p.telefone_norm, null, 'credenciamento', p.id::text, p.name,
         (p.pessoa_id = p_pessoa_id or lower(btrim(p.email)) in (select identificador from atual where canal = 'email')
            or p.id in (select identificador::uuid from atual where canal = 'credenciamento')
            or p.yazo_user_id in (select identificador::bigint from atual where canal = 'yazo' and identificador ~ '^[0-9]+$')),
         (p.buyer_email is not null and lower(btrim(p.buyer_email)) <> lower(btrim(coalesce(p.email,'')))),
         (select count(distinct lower(btrim(q.email))) > 1 from credenciamento_summit_2026.participantes q where q.telefone_norm = p.telefone_norm)
    from credenciamento_summit_2026.participantes p
   where p.pessoa_id = p_pessoa_id
      or lower(btrim(p.email)) in (select identificador from atual where canal = 'email')
      or p.telefone_norm in (select identificador from atual where canal = 'whatsapp')
      or p.id in (select identificador::uuid from atual where canal = 'credenciamento')
      or p.yazo_user_id in (select identificador::bigint from atual where canal = 'yazo' and identificador ~ '^[0-9]+$')
  union all
  -- Yazo
  select 'yazo', lower(btrim(y.email)), t.tel, null, 'yazo', y.yazo_id::text, y.name,
         (y.pessoa_id = p_pessoa_id or lower(btrim(y.email)) in (select identificador from atual where canal = 'email')
            or y.yazo_id in (select identificador::bigint from atual where canal = 'yazo' and identificador ~ '^[0-9]+$')),
         (y.attributes->>'text_40' is not null and lower(btrim(y.attributes->>'text_40')) <> lower(btrim(coalesce(y.email,'')))),
         (select count(distinct lower(btrim(z.email))) > 1 from credenciamento_summit_2026.yazo_espelho z
           where public.telefone_normalizar(case when jsonb_typeof(z.attributes->'cellphone') = 'object' then z.attributes->'cellphone'->>'value' else z.attributes->>'cellphone' end) = t.tel)
    from credenciamento_summit_2026.yazo_espelho y
    cross join lateral (select public.telefone_normalizar(case when jsonb_typeof(y.attributes->'cellphone') = 'object' then y.attributes->'cellphone'->>'value' else y.attributes->>'cellphone' end) as tel) t
   where y.pessoa_id = p_pessoa_id
      or lower(btrim(y.email)) in (select identificador from atual where canal = 'email')
      or y.yazo_id in (select identificador::bigint from atual where canal = 'yazo' and identificador ~ '^[0-9]+$')
      or t.tel in (select identificador from atual where canal = 'whatsapp')
  union all
  -- Eduzz: ingressos (participante) e vendas (comprador)
  select 'eduzz', lower(btrim(i.email)), i.telefone_norm, i.cpf_cnpj, 'eduzz', i.cod_participante, i.participante,
         (i.pessoa_id = p_pessoa_id or lower(btrim(i.email)) in (select identificador from atual where canal = 'email')
            or i.cod_participante in (select identificador from atual where canal = 'eduzz')),
         (i.email_comprador is not null and lower(btrim(i.email_comprador)) <> lower(btrim(coalesce(i.email,'')))),
         (select count(distinct lower(btrim(j.email))) > 1 from eduzz.ingressos j where j.telefone_norm = i.telefone_norm)
    from eduzz.ingressos i
   where i.pessoa_id = p_pessoa_id
      or lower(btrim(i.email)) in (select identificador from atual where canal = 'email')
      or i.telefone_norm in (select identificador from atual where canal = 'whatsapp')
      or i.cod_participante in (select identificador from atual where canal = 'eduzz')
  union all
  select 'eduzz_vendas', lower(btrim(v.cliente_email)), v.cliente_telefone_norm, v.cliente_documento, null, null, v.cliente_nome,
         (v.pessoa_id = p_pessoa_id or lower(btrim(v.cliente_email)) in (select identificador from atual where canal = 'email')),
         false,
         (select count(distinct lower(btrim(w.cliente_email))) > 1 from eduzz.vendas w where w.cliente_telefone_norm = v.cliente_telefone_norm)
    from eduzz.vendas v
   where v.pessoa_id = p_pessoa_id
      or lower(btrim(v.cliente_email)) in (select identificador from atual where canal = 'email')
      or v.cliente_telefone_norm in (select identificador from atual where canal = 'whatsapp')
  union all
  -- LearnWorlds (pelo comprador do checkout)
  select 'learnworlds', lower(btrim(k.email)), null, null, 'learnworlds', a.destino_user_id, k.nome,
         true, false, false
    from learnworlds.acessos a
    join checkout.compradores k on k.id = a.comprador_id
   where a.destino_user_id is not null
     and (k.pessoa_id = p_pessoa_id
          or lower(btrim(coalesce(k.email,''))) in (select identificador from atual where canal = 'email'));

  -- a regra: nome compativel sempre; por telefone so quando nada contradiz
  with ok as (
    select * from d5_fontes_tmp f
     where public.mind_nomes_compativeis(v_nome_pessoa, f.nome)
       and (f.via_forte
            or (not f.terceiro and not f.tel_ambiguo
                and (f.email is null or f.email = ''
                     or f.email in (select identificador from engagement.identidades where pessoa_id = p_pessoa_id and canal = 'email')
                     or not exists (select 1 from engagement.identidades where pessoa_id = p_pessoa_id and canal = 'email')
                        and not exists (select 1 from pessoas.pessoas where id = p_pessoa_id and email is not null))))
  )
  select
    (select array_agg(distinct email) from ok where email is not null and email <> ''),
    (select array_agg(distinct tel) from ok where tel is not null and tel <> '' and not terceiro),
    (select array_agg(distinct id_valor) from ok where id_canal = 'hubspot' and id_valor is not null),
    (select array_agg(distinct doc) from ok where doc is not null and doc <> '' and not terceiro),
    (select array_agg(distinct id_valor) from ok where id_canal = 'yazo' and id_valor is not null),
    (select array_agg(distinct id_valor) from ok where id_canal = 'credenciamento' and id_valor is not null),
    (select array_agg(distinct id_valor) from ok where id_canal = 'eduzz' and id_valor is not null and id_valor <> ''),
    (select array_agg(distinct id_valor) from ok where id_canal = 'learnworlds' and id_valor is not null),
    (select nome from ok where nome is not null and btrim(nome) <> ''
      order by case fonte when 'hubspot' then 1 when 'credenciamento' then 2 when 'yazo' then 3 when 'eduzz' then 4 else 5 end limit 1),
    (select count(*) from ok),
    (select count(*) from d5_fontes_tmp) - (select count(*) from ok)
  into v_emails, v_tels, v_hubs, v_docs, v_yazo, v_cred, v_edz, v_lw, v_nome, v_usadas, v_ignoradas;

  v_ids := jsonb_strip_nulls(jsonb_build_object(
    'emails', to_jsonb(coalesce(v_emails, '{}')),
    'telefones', to_jsonb(coalesce(v_tels, '{}')),
    'hubspot_ids', to_jsonb(coalesce(v_hubs, '{}')),
    'yazo_ids', to_jsonb(coalesce(v_yazo, '{}')),
    'documento', v_docs[1],
    'credenciamento_id', v_cred[1],
    'eduzz_participante', v_edz[1],
    'learnworlds_user_id', v_lw[1]));

  v_r := public.mind_identidade_resolver(v_ids, v_nome, 'enriquecimento', p_pessoa_id);

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
    'linhas_usadas', v_usadas, 'linhas_ignoradas_pela_regra', v_ignoradas,
    'fontes', jsonb_build_object('hubspot', coalesce(array_length(v_hubs,1),0), 'credenciamento', coalesce(array_length(v_cred,1),0),
                                 'yazo', coalesce(array_length(v_yazo,1),0), 'eduzz', coalesce(array_length(v_edz,1),0), 'learnworlds', coalesce(array_length(v_lw,1),0)));
end $function$;

revoke all on function public.mind_pessoa_enriquecer(uuid) from public;
comment on function public.mind_pessoa_enriquecer(uuid) is
  'Fase A da passada D5. Reúne os identificadores que as fontes já ligadas à pessoa conhecem (HubSpot, credenciamento, Yazo, Eduzz, LearnWorlds) e os entrega à porta única com a pessoa ancorada. Regra do nome (Adriana, 23/09): só contribui a linha cujo nome não contradiz o da pessoa; linha achada só por telefone contribui apenas se não é inscrição por terceiro, o e-mail dela não é outro e o telefone aponta para um só e-mail na fonte; linha comprada por terceiro nunca entrega telefone nem CPF. Nunca cria pessoa. Nunca funde.';

-- ----------------------------------------------------------------------------
-- 8. Fase C conta "criada: …" no critério novo
-- ----------------------------------------------------------------------------
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
  if not exists (select 1 from pg_trigger t where t.tgrelid = p_fonte and t.tgname = 'zz_d5_pessoa_antes_de_escrever' and t.tgenabled <> 'D') then
    raise exception using errcode = 'P0001', message = 'fonte sem o trigger D5 ligado: ' || v_q || ' — use mind_pessoa_ligar_tabela primeiro';
  end if;

  select count(*) into v_antes from pessoas.pessoas;
  execute format('update %s set pessoa_resolvido_em = now() where ctid in (select ctid from %s where pessoa_id is null and (pessoa_resolvido_em is null or pessoa_criterio like %L) limit %s)',
                 v_q, v_q, 'aguardando_fase_a%', p_lote);
  get diagnostics v_n = row_count;
  select count(*) into v_depois from pessoas.pessoas;
  execute format('select count(*) filter (where pessoa_id is not null and pessoa_criterio not like %L),
                         count(*) filter (where pessoa_criterio like %L),
                         count(*) filter (where pessoa_id is null),
                         coalesce(jsonb_object_agg(m, n) filter (where m is not null), %L::jsonb)
                    from (select pessoa_id, pessoa_criterio, case when pessoa_id is null then split_part(pessoa_criterio, '' ('', 1) end m,
                                 count(*) over (partition by case when pessoa_id is null then split_part(pessoa_criterio, '' ('', 1) end) n
                            from %s where pessoa_resolvido_em = now()) s',
                 'criada:%', 'criada:%', '{}', v_q)
    into v_ligadas, v_criadas, v_sem, v_motivos;
  execute format('select count(*) from %s where pessoa_id is null and (pessoa_resolvido_em is null or pessoa_criterio like %L)', v_q, 'aguardando_fase_a%') into v_restantes;

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

-- ----------------------------------------------------------------------------
-- 9. Fusão: auditoria com action permitido; decisão em bloco exclui o padrão novo
-- ----------------------------------------------------------------------------
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

  update pessoas.pessoas set email = null, whatsapp = null, hubspot_id = null where id = p_absorvida;

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

  update pessoas.pessoas set fundida_em = p_sobrevive, fundida_quando = now(), atualizado_em = now() where id = p_absorvida;

  update engagement.identidade_fusoes f
     set status = 'fundido', resolvido_em = now(),
         decisao = coalesce(f.decisao, '{}'::jsonb) || jsonb_build_object('fundida_por_par', true)
   where f.status = 'pendente' and f.participante_origem is not null
     and least(f.participante_id, f.participante_origem) = least(p_sobrevive, p_absorvida)
     and greatest(f.participante_id, f.participante_origem) = greatest(p_sobrevive, p_absorvida);

  -- o CHECK de mind_admin_audit so aceita criar/atualizar/publicar/arquivar/reindexar/login:
  -- a fusao e um 'atualizar' da pessoa, com o rotulo dizendo o que foi
  insert into public.mind_admin_audit (actor_user_id, action, resource, record_id, record_label, before_data, after_data, request_id)
  values (auth.uid(), 'atualizar', 'pessoa', p_absorvida::text,
          'fundir: ' || coalesce(p_motivo, 'fusao D5'),
          jsonb_build_object('absorvida', to_jsonb(v_abs)),
          jsonb_build_object('operacao', 'fundir', 'sobrevive', p_sobrevive, 'linhas_movidas', v_total_movidas, 'linhas_descartadas', v_total_descartadas, 'detalhe', v_detalhe),
          gen_random_uuid());

  return jsonb_build_object('ok', true, 'sobrevive', p_sobrevive, 'absorvida', p_absorvida,
                            'linhas_movidas', v_total_movidas, 'linhas_descartadas', v_total_descartadas, 'detalhe', v_detalhe);
end $function$;

revoke all on function public.mind_pessoa_fundir(uuid, uuid, text) from public;

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
  if session_user <> 'postgres' then
    select role into v_role from public.mind_admin_users where user_id = auth.uid() and active;
    if v_role is null or v_role not in ('administrador','aprovador') then
      raise exception using errcode = '42501', message = 'admin_forbidden';
    end if;
    select display_name into v_quem from public.mind_admin_users where user_id = auth.uid();
  end if;
  v_quem := coalesce(p_quem, v_quem, session_user::text);

  begin v_id := p_alvo::uuid; exception when others then v_id := null; end;
  if v_id is null and p_alvo in ('telefone_compartilhado','nomes_divergentes','mesmo_email_nomes_diferentes') and p_decisao = 'aprovar' then
    raise exception using errcode = '22023', message = 'padrao_so_linha_a_linha: ' || p_alvo;
  end if;

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
  'A decisão da Adriana sobre duplicatas propostas: p_alvo é o id de uma pendência ou o nome de um padrão inteiro; p_decisao é aprovar (funde, via mind_pessoa_fundir) ou rejeitar (descarta). Aprovar um padrão só alcança propostas de confiança alta; média e baixa ficam para decisão pelo id. telefone_compartilhado, nomes_divergentes e mesmo_email_nomes_diferentes nunca em bloco. Pelo painel exige papel administrador/aprovador; no SQL Editor vale o próprio postgres. É o único caminho que funde alguém.';

-- ----------------------------------------------------------------------------
-- 10. Propostas pendentes reclassificadas com a regra do nome com tolerância
-- ----------------------------------------------------------------------------
do $$
declare f record; n int := 0;
begin
  for f in select participante_id, participante_origem, proposta->>'canal' as canal
             from engagement.identidade_fusoes
            where status = 'pendente' and participante_origem is not null and proposta is not null
  loop
    perform public.mind_fusao_propor(f.participante_id, f.participante_origem, f.canal);
    n := n + 1;
  end loop;
  raise notice 'd5.2: % propostas pendentes reclassificadas', n;
end $$;

-- ----------------------------------------------------------------------------
-- 11. Prova
-- ----------------------------------------------------------------------------
do $$
declare n int;
begin
  if not public.mind_nomes_compativeis('Geovanna Moura Brito dos Santos', 'Geovana Moura Brito dos Santos')
     or not public.mind_nomes_compativeis('Luís Felipe Rossi', 'LuÃ¯Â¿Â½s Felipe Rossi')
     or not public.mind_nomes_compativeis('Sol Conforto', 'Solismar Prado Almeida Conforto')
     or not public.mind_nomes_compativeis('Ana Paula Souza', 'Paula Souza')
     or not public.mind_nomes_compativeis(null, 'Qualquer Nome')
     or public.mind_nomes_compativeis('Thomas Maiani', 'Bruna Maiani')
     or public.mind_nomes_compativeis('Priscila Wetzlar', 'FERNANDO MORAES DE ARAUJO')
     or public.mind_nomes_compativeis('Eduarda Gallo', 'Paula Gallo') then
    raise exception 'd5.2: mind_nomes_compativeis nao se comporta como combinado';
  end if;
  select count(*) into n from pg_trigger t where t.tgname = 'zz_d5_pessoa_antes_de_escrever' and not t.tgisinternal and t.tgenabled <> 'D';
  if n < 7 then raise exception 'd5.2: esperava o trigger ligado em pelo menos 7 tabelas-fonte, achei %', n; end if;
  if exists (select 1 from pessoas.pessoas p where p.hubspot_id is not null and p.fundida_em is null
              and not exists (select 1 from engagement.identidades i where i.canal = 'hubspot' and i.identificador = p.hubspot_id)) then
    raise exception 'd5.2: hubspot_id de pessoa fora de identidades';
  end if;
end $$;
