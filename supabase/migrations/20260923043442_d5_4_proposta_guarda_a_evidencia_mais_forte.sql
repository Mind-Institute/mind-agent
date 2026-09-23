-- ============================================================================
-- D5.4 — a proposta de fusão guarda a evidência mais forte, não a última
-- ============================================================================
-- Visto na fase A em produção (23/09, 04:26 UTC): um par de pessoas que
-- compartilha e-mail E telefone recebia a classificação da última evidência
-- registrada. A pendência nascia por e-mail (mesmo_email_hubspot_x_login, alta)
-- e, quando o enriquecimento encontrava também o telefone em comum,
-- mind_fusao_propor sobrescrevia padrão e confiança pelo telefone
-- (mesmo_telefone_emails_diferentes, média). 1.291 propostas caíram de alta
-- para média sem motivo.
--
-- Correção: mind_fusao_propor passa a olhar a proposta pendente já gravada e a
-- classificar pelo canal de MAIOR precedência entre o antigo e o novo (login >
-- id de terceiro > e-mail > WhatsApp), guardando em `canais` tudo o que o par
-- compartilha. E um bloco reclassifica todas as propostas pendentes a partir
-- da evidência gravada (identificador jsonb): os identificadores da entrada que
-- pertencem à outra pessoa do par dizem exatamente o que as duas compartilham.
-- Idempotente.
-- ============================================================================

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
  v_existente jsonb; v_canal text := p_canal_conflito; v_canais text[];
begin
  if p_a is null or p_b is null or p_a = p_b then return null; end if;
  -- CPF/CNPJ nunca abrem proposta sozinhos (Adriana, 23/09)
  if p_canal_conflito in ('cpf','cnpj') then return null; end if;

  -- o que o par ja compartilhava, segundo a proposta pendente: a evidencia mais forte vence
  select f.proposta into v_existente
    from engagement.identidade_fusoes f
   where f.status = 'pendente' and f.participante_origem is not null and f.proposta is not null
     and least(f.participante_id, f.participante_origem) = least(p_a, p_b)
     and greatest(f.participante_id, f.participante_origem) = greatest(p_a, p_b)
   order by f.criado_em limit 1;
  select coalesce(array_agg(distinct c), '{}') into v_canais
    from (select jsonb_array_elements_text(coalesce(v_existente->'canais', '[]'::jsonb)) c
          union select v_existente->>'canal' where v_existente->>'canal' is not null
          union select p_canal_conflito where p_canal_conflito is not null) s;
  select c into v_canal from unnest(v_canais) c order by public.mind_identidade_precedencia(c) limit 1;

  select coalesce(array_agg(distinct canal), '{}'), count(*) into ca, n_a from engagement.identidades where pessoa_id = p_a;
  select coalesce(array_agg(distinct canal), '{}'), count(*) into cb, n_b from engagement.identidades where pessoa_id = p_b;
  select concat_ws(' ', primeiro_nome, sobrenome), criado_em into nome_a, c_a from pessoas.pessoas where id = p_a;
  select concat_ws(' ', primeiro_nome, sobrenome), criado_em into nome_b, c_b from pessoas.pessoas where id = p_b;
  select identificador into cpf_a from engagement.identidades where pessoa_id = p_a and canal = 'cpf' limit 1;
  select identificador into cpf_b from engagement.identidades where pessoa_id = p_b and canal = 'cpf' limit 1;
  v_nomes_ok   := public.mind_nomes_compativeis(nome_a, nome_b);
  v_nome_igual := cardinality(public.mind_nome_tokens(nome_a)) > 0 and cardinality(public.mind_nome_tokens(nome_b)) > 0 and v_nomes_ok;

  if 'whatsapp' = any(v_canais) then
    select count(distinct i.pessoa_id) into v_tel_pessoas
      from engagement.identidades i
     where i.canal = 'whatsapp'
       and i.identificador in (select identificador from engagement.identidades where pessoa_id in (p_a, p_b) and canal = 'whatsapp');
  end if;

  v_padrao := case
    when not v_nomes_ok and v_canal = 'email' then 'mesmo_email_nomes_diferentes'
    when not v_nomes_ok then 'nomes_divergentes'
    when v_canal = 'email'
         and (('hubspot' = any(ca) and not 'auth_user' = any(ca) and 'auth_user' = any(cb))
           or ('hubspot' = any(cb) and not 'auth_user' = any(cb) and 'auth_user' = any(ca))) then 'mesmo_email_hubspot_x_login'
    when v_canal = 'email' and 'hubspot' = any(ca) and 'hubspot' = any(cb) then 'mesmo_email_dois_hubspot'
    when v_canal = 'email' then 'mesmo_email'
    when v_canal = 'whatsapp' and v_tel_pessoas > 2 then 'telefone_compartilhado'
    when v_canal = 'whatsapp' then 'mesmo_telefone_emails_diferentes'
    when v_canal in ('hubspot','yazo','credenciamento','eduzz','learnworlds','auth_user') then 'mesmo_id_de_terceiro'
    else 'outro' end;

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
    when 'mesmo_id_de_terceiro' then 'alta'
    when 'mesmo_telefone_emails_diferentes' then 'media'
    else 'baixa' end;
  v_motivo := case v_padrao
    when 'mesmo_email_hubspot_x_login' then 'mesmo e-mail: uma pessoa nasceu do WhatsApp/HubSpot sem e-mail registrado, a outra do login no app; sobrevive quem tem login'
    when 'mesmo_email_dois_hubspot' then 'mesmo e-mail em duas pessoas, ambas ligadas ao HubSpot (dois contatos para a mesma pessoa)'
    when 'mesmo_email' then 'mesmo e-mail em duas pessoas, nomes compatíveis'
    when 'mesmo_id_de_terceiro' then 'o mesmo registro de um sistema de terceiro (HubSpot, Yazo, credenciamento, Eduzz, login) aponta para as duas pessoas'
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
  if cardinality(v_canais) > 1 then v_nota := v_nota || '; em comum: ' || array_to_string(v_canais, ', '); end if;
  v_motivo := v_motivo || v_nota;

  v_prop := jsonb_build_object('sobrevive', v_sob, 'absorvida', v_abs, 'padrao', v_padrao,
                               'motivo', v_motivo, 'confianca', v_conf, 'canal', v_canal, 'canais', to_jsonb(v_canais),
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

revoke all on function public.mind_fusao_propor(uuid, uuid, text) from public;
comment on function public.mind_fusao_propor(uuid, uuid, text) is
  'Dado um par de pessoas que compartilham um identificador, classifica o padrão da duplicata e propõe quem sobrevive (login no app > mais identificadores > mais antiga). Classifica pelo canal de maior precedência entre o que o par já compartilhava (proposta pendente) e o novo; guarda todos em canais. Nome compara com tolerância. Só grava a proposta na pendência já registrada. Não funde: isso é mind_fusao_decidir.';

comment on column engagement.identidade_fusoes.padrao is
  'Padrão da duplicata: mesmo_email_hubspot_x_login, mesmo_email_dois_hubspot, mesmo_email, mesmo_id_de_terceiro (alta: podem ser aprovados em bloco); mesmo_telefone_emails_diferentes (média: nomes compatíveis, e-mails diferentes — suspeita, linha a linha); mesmo_email_nomes_diferentes, telefone_compartilhado e nomes_divergentes (baixa: sempre linha a linha); outro. Classificado pela evidência mais forte que o par compartilha. CPF nunca gera padrão sozinho.';

-- Reclassifica toda proposta pendente a partir da evidência gravada: os identificadores
-- da entrada que pertencem à OUTRA pessoa do par são o que as duas compartilham.
do $$
declare f record; v_canais text[]; v_canal text; n int := 0; m int := 0;
begin
  for f in
    select id, participante_id, participante_origem, identificador, proposta
      from engagement.identidade_fusoes
     where status = 'pendente' and participante_origem is not null
       and identificador is not null and jsonb_typeof(identificador) = 'array'
  loop
    select coalesce(array_agg(distinct i.canal), '{}') into v_canais
      from jsonb_array_elements(f.identificador) x
      join engagement.identidades i on i.canal = x->>'canal' and i.identificador = x->>'identificador'
     where i.pessoa_id in (f.participante_id, f.participante_origem)
       and i.canal not in ('cpf','cnpj');
    if cardinality(v_canais) = 0 then continue; end if;
    -- zera os canais guardados e reclassifica a partir do que a evidencia prova
    update engagement.identidade_fusoes set proposta = coalesce(proposta, '{}'::jsonb) - 'canais' - 'canal' where id = f.id;
    select c into v_canal from unnest(v_canais) c order by public.mind_identidade_precedencia(c) limit 1;
    perform public.mind_fusao_propor(f.participante_id, f.participante_origem, v_canal);
    -- os demais canais entram como "tambem em comum"
    for v_canal in select c from unnest(v_canais) c order by public.mind_identidade_precedencia(c) offset 1 loop
      perform public.mind_fusao_propor(f.participante_id, f.participante_origem, v_canal);
    end loop;
    n := n + 1;
  end loop;
  select count(*) into m from engagement.identidade_fusoes where status = 'pendente' and proposta is not null;
  raise notice 'd5.4: % propostas reclassificadas pela evidência; % pendências com proposta', n, m;
end $$;
