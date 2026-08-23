-- O NOME NAO DEDUPLICA. Medido nesta base:
--   Beatriz/Bia (mesma pessoa)        = 0.091
--   Maria Silva/Maria Souza (outra)   = 0.375
-- Apelido pontua MENOS que pessoa diferente. Nenhum limiar separa os dois.
--
-- Entao o nome tem um papel so: VETAR o caso obviamente errado (Joao contra
-- Maria, similaridade 0), e apenas na entrada por E-MAIL, que e chave fraca
-- porque quem compra varios ingressos usa o proprio e-mail para outras pessoas.
-- WhatsApp nao sofre veto: e o aparelho de quem esta falando.

create or replace function public.mind_nome_conflita(
  p_nome text, p_sobrenome text, q_nome text, q_sobrenome text)
returns boolean language sql stable as $function$
  with a as (select public.mind_nome_simples(nullif(trim(concat_ws(' ',p_nome,p_sobrenome)),'')) c),
       b as (select public.mind_nome_simples(nullif(trim(concat_ws(' ',q_nome,q_sobrenome)),'')) c)
  select case
    -- sem nome de um dos lados: nao da para vetar
    when (select c from a) is null or (select c from b) is null then false
    when (select c from a) = (select c from b) then false
    -- apelido/abreviacao: um contido no outro nao conflita (Rafa/Rafael)
    when (select c from a) like '%'||(select c from b)||'%'
      or (select c from b) like '%'||(select c from a)||'%' then false
    -- conflita so quando nao compartilham NADA
    else similarity((select c from a), (select c from b)) = 0
  end;
$function$;

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
  v_email text := lower(nullif(trim(coalesce(p_email,'')),''));
  v_dig   text := regexp_replace(coalesce(p_whatsapp,''), '\D', '', 'g');
  v_out   jsonb;
begin
  if length(v_dig) < 10 then v_dig := null; end if;
  if v_email is null and v_dig is null then return '[]'::jsonb; end if;

  with por_identidade as (
    select i.pessoa_id, i.canal from engagement.identidades i
    where (v_dig   is not null and i.canal = 'whatsapp' and i.identificador = v_dig)
       or (v_email is not null and i.canal = 'email'    and i.identificador = v_email)
  ),
  cand as (
    select p.*,
           case
             when v_dig is not null and (regexp_replace(coalesce(p.whatsapp,''),'\D','','g') = v_dig
                  or exists (select 1 from por_identidade i where i.pessoa_id=p.id and i.canal='whatsapp'))
               then 'whatsapp'
             when v_email is not null and (lower(p.email) = v_email
                  or exists (select 1 from por_identidade i where i.pessoa_id=p.id and i.canal='email'))
               then 'email'
             else null end as motivo,
           public.mind_nome_conflita(p_nome, p_sobrenome, p.primeiro_nome, p.sobrenome) as conflita,
           round(similarity(
             coalesce(public.mind_nome_simples(nullif(trim(concat_ws(' ',p_nome,p_sobrenome)),'')),''),
             coalesce(public.mind_nome_simples(concat_ws(' ',p.primeiro_nome,p.sobrenome)),'')
           )::numeric,3) as parecenca
    from crm.pessoas p
  ),
  -- O veto so vale na entrada por e-mail. WhatsApp e o aparelho de quem fala.
  filtrado as (
    select * from cand
    where motivo is not null
      and not (motivo = 'email' and conflita)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'pessoa_id', f.id,
      'nome', trim(concat_ws(' ', f.primeiro_nome, f.sobrenome)),
      'motivo', f.motivo,
      'parecenca_do_nome', f.parecenca,
      'email', f.email, 'whatsapp', f.whatsapp,
      'empresa', f.empresa, 'cargo', f.cargo, 'estagio', f.estagio,
      'comprou', exists (select 1 from crm.pessoa_produtos pp where pp.pessoa_id = f.id)
    ) order by case f.motivo when 'whatsapp' then 1 else 2 end, f.parecenca desc), '[]'::jsonb)
  into v_out from filtrado f;

  return v_out;
end;
$function$;

revoke all on function public.mind_nome_conflita(text,text,text,text) from public, anon, authenticated;
revoke all on function public.treble_candidatos_identidade(text,text,text,text) from public, anon, authenticated;
grant execute on function public.mind_nome_conflita(text,text,text,text) to service_role;
grant execute on function public.treble_candidatos_identidade(text,text,text,text) to service_role;

comment on function public.mind_nome_conflita(text,text,text,text) is
  'O nome NAO confirma identidade -- apelido pontua menos que pessoa diferente. Ele so VETA quando os nomes nao compartilham nada (Joao contra Maria). Contido no outro (Rafa/Rafael) nao conflita.';