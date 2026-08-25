-- Quem pode ser essa pessoa? Duas combinacoes valem:
--   nome+sobrenome + e-mail      (o e-mail dela pode nao ser o da compra)
--   nome+sobrenome + WhatsApp
-- Mais o WhatsApp sozinho, que e forte por ser o aparelho de quem fala.
--
-- Devolve TODOS os candidatos com o motivo do match. Quem decide o que fazer
-- com 0, 1 ou varios e quem chama -- e com varios, o desempate sai do que
-- difere entre as linhas, nao de uma pergunta fixa.

create or replace function public.treble_candidatos_identidade(
  p_nome text default null,
  p_sobrenome text default null,
  p_email text default null,
  p_whatsapp text default null)
returns jsonb
language plpgsql stable security definer
set search_path to 'public','crm','engagement'
as $function$
declare
  v_email   text := lower(nullif(trim(coalesce(p_email,'')),''));
  v_dig     text := regexp_replace(coalesce(p_whatsapp,''), '\D', '', 'g');
  v_nome    text := public.mind_nome_simples(nullif(trim(coalesce(p_nome,'')),''));
  v_completo text := public.mind_nome_simples(
                       nullif(trim(concat_ws(' ', p_nome, p_sobrenome)),''));
  v_out jsonb;
begin
  if length(v_dig) < 10 then v_dig := null; end if;

  with base as (
    select p.*,
           public.mind_nome_simples(p.primeiro_nome) as n_simples,
           public.mind_nome_simples(concat_ws(' ', p.primeiro_nome, p.sobrenome)) as n_completo,
           regexp_replace(coalesce(p.whatsapp,''), '\D', '', 'g') as wa_dig
    from crm.pessoas p
  ),
  por_identidade as (
    select i.pessoa_id, i.canal from engagement.identidades i
    where (v_dig   is not null and i.canal = 'whatsapp' and i.identificador = v_dig)
       or (v_email is not null and i.canal = 'email'    and i.identificador = v_email)
  ),
  cand as (
    select b.*,
           case
             when v_dig is not null and (b.wa_dig = v_dig
                  or exists (select 1 from por_identidade pi where pi.pessoa_id = b.id and pi.canal='whatsapp'))
               then 'whatsapp'
             when v_email is not null and (lower(b.email) = v_email
                  or exists (select 1 from por_identidade pi where pi.pessoa_id = b.id and pi.canal='email'))
               then 'email'
             when v_completo is not null and b.n_completo = v_completo
               then 'nome_completo'
             else null
           end as motivo
    from base b
  ),
  filtrado as (
    select * from cand where motivo is not null
      -- nome completo sozinho so entra se tambem houver e-mail ou WhatsApp em jogo
      and (motivo <> 'nome_completo' or v_email is not null or v_dig is not null)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'pessoa_id', f.id,
      'nome', trim(concat_ws(' ', f.primeiro_nome, f.sobrenome)),
      'motivo', f.motivo,
      'nome_bate', case
         when v_completo is not null and f.n_completo is not null then (f.n_completo = v_completo)
         when v_nome is not null and f.n_simples is not null then (f.n_simples = v_nome)
         else null end,
      'email', f.email,
      'whatsapp', f.whatsapp,
      'empresa', f.empresa,
      'cargo', f.cargo,
      'estagio', f.estagio,
      'comprou', exists (select 1 from crm.pessoa_produtos pp where pp.pessoa_id = f.id)
    ) order by case f.motivo when 'whatsapp' then 1 when 'email' then 2 else 3 end), '[]'::jsonb)
  into v_out from filtrado f;

  return v_out;
end;
$function$;

-- O que difere entre os candidatos? E a pergunta de desempate sai daqui.
create or replace function public.treble_desempate(p_candidatos jsonb)
returns jsonb
language sql stable
as $function$
  with c as (select value as p from jsonb_array_elements(coalesce(p_candidatos,'[]'::jsonb))),
  campos as (
    select 'comprou' as campo, count(distinct (p->>'comprou')) as distintos,
           'Voce ja comprou ingresso para o Summit?' as pergunta from c
    union all
    select 'empresa', count(distinct (p->>'empresa')),
           'De qual empresa voce e?' from c where (select count(*) from c) > 1
    union all
    select 'cargo', count(distinct (p->>'cargo')),
           'Qual e o seu cargo?' from c
    union all
    select 'email', count(distinct (p->>'email')),
           'Qual e-mail voce usou no cadastro?' from c
  )
  select case when (select count(*) from c) < 2 then null
         else (select jsonb_build_object('campo', campo, 'pergunta', pergunta)
                 from campos where distintos > 1
                order by case campo when 'comprou' then 1 when 'empresa' then 2
                                    when 'cargo' then 3 else 4 end
                limit 1) end;
$function$;

revoke all on function public.treble_candidatos_identidade(text,text,text,text) from public, anon, authenticated;
revoke all on function public.treble_desempate(jsonb) from public, anon, authenticated;
grant execute on function public.treble_candidatos_identidade(text,text,text,text) to service_role;
grant execute on function public.treble_desempate(jsonb) to service_role;

comment on function public.treble_candidatos_identidade(text,text,text,text) is
  'Todos os candidatos a ser essa pessoa, por WhatsApp, e-mail ou nome completo combinado com um dos dois. Devolve o motivo do match e se a pessoa ja comprou, para desempate.';
comment on function public.treble_desempate(jsonb) is
  'Dado mais de um candidato, devolve o primeiro campo que difere entre eles e a pergunta que o agente deve fazer. A pergunta sai dos dados, nao de uma lista fixa.';
