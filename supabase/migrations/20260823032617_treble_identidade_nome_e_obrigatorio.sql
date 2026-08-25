-- REGRA DURA: o nome sempre tem que bater. Ninguem tem um nome e depois outro.
-- Nome divergente elimina o candidato -- nao vira conflito, vira "nao e ela".
-- Unica tolerancia: sobrenome ACRESCENTADO ("Maria Silva" -> "Maria Silva Souza").
-- Apelido e sobrenome de casada vao falhar de proposito: o erro cai para o lado
-- de criar duplicata, nunca para o lado de fundir duas pessoas diferentes.

create or replace function public.mind_nome_bate(
  p_nome text, p_sobrenome text, q_nome text, q_sobrenome text)
returns boolean language sql immutable as $function$
  with a as (select public.mind_nome_simples(nullif(trim(concat_ws(' ',p_nome,p_sobrenome)),'')) c,
                    public.mind_nome_simples(nullif(trim(coalesce(p_nome,'')),'')) p),
       b as (select public.mind_nome_simples(nullif(trim(concat_ws(' ',q_nome,q_sobrenome)),'')) c,
                    public.mind_nome_simples(nullif(trim(coalesce(q_nome,'')),'')) p)
  select case
    when (select c from a) is null or (select c from b) is null then null
    when (select c from a) = (select c from b) then true
    -- sobrenome acrescentado: um comeca com o outro E o primeiro nome e o mesmo
    when (select p from a) is not distinct from (select p from b)
         and ((select c from a) like (select c from b) || '%'
           or (select c from b) like (select c from a) || '%') then true
    else false
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
           public.mind_nome_bate(p_nome, p_sobrenome, p.primeiro_nome, p.sobrenome) as nome_bate
    from crm.pessoas p
  ),
  -- O NOME MANDA: se bate false, nao e ela. null = nao da para saber (um dos
  -- lados nao tem nome), e ai a chave forte decide.
  filtrado as (select * from cand where motivo is not null and nome_bate is distinct from false)
  select coalesce(jsonb_agg(jsonb_build_object(
      'pessoa_id', f.id,
      'nome', trim(concat_ws(' ', f.primeiro_nome, f.sobrenome)),
      'motivo', f.motivo,
      'nome_confirmado', (f.nome_bate is true),
      'email', f.email, 'whatsapp', f.whatsapp,
      'empresa', f.empresa, 'cargo', f.cargo, 'estagio', f.estagio,
      'comprou', exists (select 1 from crm.pessoa_produtos pp where pp.pessoa_id = f.id)
    ) order by case f.motivo when 'whatsapp' then 1 else 2 end,
               (f.nome_bate is true) desc), '[]'::jsonb)
  into v_out from filtrado f;

  return v_out;
end;
$function$;

revoke all on function public.mind_nome_bate(text,text,text,text) from public, anon, authenticated;
revoke all on function public.treble_candidatos_identidade(text,text,text,text) from public, anon, authenticated;
grant execute on function public.mind_nome_bate(text,text,text,text) to service_role;
grant execute on function public.treble_candidatos_identidade(text,text,text,text) to service_role;

comment on function public.mind_nome_bate(text,text,text,text) is
  'O nome sempre tem que bater. Tolera apenas sobrenome acrescentado. Devolve null quando um dos lados nao tem nome.';