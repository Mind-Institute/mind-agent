-- "Leticia" contra "Mariana" (outra pessoa) e "Leticia" contra "Fofinha"
-- (apelido) sao IDENTICOS para a maquina: nenhum dos dois compartilha nada.
-- Nao existe regra que separe. So a propria pessoa sabe.
--
-- Entao o nome nunca decide: ele so levanta a mao. Chave forte resolve;
-- nome destoante vira PERGUNTA, com o nome do cadastro na mao para o agente
-- poder perguntar de um jeito natural.

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
           public.mind_nome_conflita(p_nome, p_sobrenome, p.primeiro_nome, p.sobrenome) as nome_destoa
    from crm.pessoas p
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'pessoa_id', c.id,
      'nome', trim(concat_ws(' ', c.primeiro_nome, c.sobrenome)),
      'motivo', c.motivo,
      -- nome destoante NAO elimina o candidato: vira pergunta.
      -- So vale para a entrada por e-mail; WhatsApp e o aparelho de quem fala.
      'precisa_confirmar_nome', (c.motivo = 'email' and c.nome_destoa),
      'email', c.email, 'whatsapp', c.whatsapp,
      'empresa', c.empresa, 'cargo', c.cargo, 'estagio', c.estagio,
      'comprou', exists (select 1 from crm.pessoa_produtos pp where pp.pessoa_id = c.id)
    ) order by case c.motivo when 'whatsapp' then 1 else 2 end), '[]'::jsonb)
  into v_out from cand c where c.motivo is not null;

  return v_out;
end;
$function$;

-- A pergunta que o agente faz. Sai dos dados, nunca de uma lista fixa.
create or replace function public.treble_pergunta_de_identidade(p_candidatos jsonb)
returns jsonb
language sql stable
as $function$
  with c as (select value p from jsonb_array_elements(coalesce(p_candidatos,'[]'::jsonb))),
  n as (select count(*) q from c)
  select case
    when (select q from n) = 0 then null
    -- um so candidato, mas o nome destoa: confirma se e ela
    when (select q from n) = 1 and (select (p->>'precisa_confirmar_nome')::boolean from c) then
      jsonb_build_object('tipo','confirmar_titular',
        'pergunta', 'Achei um cadastro no nome de ' ||
                    (select p->>'nome' from c) ||
                    ' com esse e-mail. E voce, ou voce usou o e-mail de outra pessoa?')
    when (select q from n) = 1 then null
    -- varios candidatos: pergunta o primeiro campo que difere entre eles
    else coalesce(
      (select jsonb_build_object('tipo','desempate','campo',campo,'pergunta',pergunta)
         from (
           select 'comprou' campo, count(distinct p->>'comprou') d,
                  'So confirmando: voce ja comprou ingresso para o Summit?' pergunta from c
           union all
           select 'empresa', count(distinct p->>'empresa'), 'De qual empresa voce e?' from c
           union all
           select 'cargo', count(distinct p->>'cargo'), 'Qual e o seu cargo?' from c
           union all
           select 'email', count(distinct p->>'email'), 'Qual e-mail voce usou no cadastro?' from c
         ) x where d > 1
         order by case campo when 'comprou' then 1 when 'empresa' then 2
                             when 'cargo' then 3 else 4 end limit 1),
      jsonb_build_object('tipo','desempate','campo',null,
        'pergunta','Voce ja comprou ingresso para o Summit?'))
  end;
$function$;

revoke all on function public.treble_pergunta_de_identidade(jsonb) from public, anon, authenticated;
grant execute on function public.treble_pergunta_de_identidade(jsonb) to service_role;

drop function if exists public.treble_desempate(jsonb);

comment on function public.treble_pergunta_de_identidade(jsonb) is
  'A pergunta que desfaz a duvida de identidade. Um candidato com nome destoante -> confirma se e ela. Varios candidatos -> pergunta o primeiro campo que DIFERE entre eles (ja comprou? empresa? cargo?). Nunca lista fixa.';