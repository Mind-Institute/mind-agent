-- Análise pós-conversa no painel (aprovado pela Adriana em 22/10/2026).
--
-- 1. O interruptor por agente passa a valer: `agentes.rotas.analisa_conversas = false`
--    tira da fila as conversas cujo último atendimento foi desse agente (o que o
--    runtime gravou em `mensagens.blocos.rota_aplicada`/`rota`). Conversas dos fluxos
--    da Treble (sem agente nosso) continuam entrando, como hoje.
-- 2. `mind_admin_update_agent` ganha `p_analisa_conversas` (assinatura nova; a de 5
--    parâmetros continua).
-- 3. `mind_admin_read_analysis_runs`: as últimas execuções da análise e o que cada
--    uma gravou (memórias e continuidade). Só administrador lê (a ponte confere);
--    textos mascarados, nunca telefone nem e-mail.

set lock_timeout = '10s';

create or replace function public.analise_pendentes(p_limite integer default 20)
 returns table(conversa_id uuid)
 language sql
 stable security definer
 set search_path to 'public', 'intelligence', 'engagement'
as $function$
  with conv as (
    select c.id,
           (select max(m.criado_em) from engagement.mensagens m where m.conversa_id = c.id) as ult_msg,
           -- o agente que atendeu por último (vazio nos fluxos da Treble)
           (select coalesce(m.blocos->>'rota_aplicada', m.blocos->>'rota')
              from engagement.mensagens m
             where m.conversa_id = c.id and m.papel = 'agente'
               and coalesce(m.blocos->>'rota_aplicada', m.blocos->>'rota') is not null
             order by m.criado_em desc limit 1) as rota
    from engagement.conversas c
    left join pessoas.pessoas p on p.id = c.mind_id
    where c.agente in ('treble','treble-inbound-agent','mindagent-chat')
      and exists (select 1 from engagement.mensagens m2
                   where m2.conversa_id = c.id and m2.papel = 'lead' and m2.conteudo is not null)
      -- quem não é lead (professor, palestrante, staff, parceiro de venda) não passa pelos prompts de
      -- inteligência (23/09); conversa sem pessoa continua na fila
      and (p.id is null or 'lead' = any(p.relacionamento_mind))
  )
  select conv.id
  from conv
  where not exists (
    select 1 from intelligence.analise_conversa a
    where a.conversa_id = conv.id
      and a.conversa_atualizada_ate >= conv.ult_msg)
    -- interruptor por agente (painel): desligado, a conversa não entra
    and not exists (
      select 1 from agentes.rotas r
       where r.rota = conv.rota and not r.analisa_conversas)
  order by conv.ult_msg desc, conv.id
  limit greatest(1, p_limite);
$function$;

create or replace function public.mind_admin_update_agent(
  p_rota text, p_nome text, p_descricao text, p_analisa_conversas boolean, p_ator uuid, p_atualizado_em_esperado timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role  text;
  v_atual agentes.rotas%rowtype;
begin
  select a.role into v_role from public.mind_admin_users a where a.user_id = p_ator and a.active;
  if v_role is distinct from 'administrador' then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  end if;
  select * into v_atual from agentes.rotas r where r.rota = p_rota for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'admin_not_found';
  end if;
  if p_atualizado_em_esperado is not null and v_atual.atualizado_em is distinct from p_atualizado_em_esperado then
    raise exception using errcode = '40001', message = 'admin_conflict';
  end if;
  if p_nome is not null and btrim(p_nome) = '' then
    raise exception using errcode = '22023', message = 'admin_validation:nome';
  end if;
  if p_descricao is not null and length(p_descricao) > 4000 then
    raise exception using errcode = '22023', message = 'admin_validation:descricao';
  end if;

  update agentes.rotas r
     set nome = coalesce(btrim(p_nome), r.nome),
         descricao = case when p_descricao is null then r.descricao else nullif(btrim(p_descricao), '') end,
         analisa_conversas = coalesce(p_analisa_conversas, r.analisa_conversas),
         atualizado_em = now()
   where r.rota = p_rota;

  return (select x from public.mind_admin_read_agents(p_rota) x limit 1);
end;
$$;
revoke all on function public.mind_admin_update_agent(text, text, text, boolean, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.mind_admin_update_agent(text, text, text, boolean, uuid, timestamptz) to service_role;

create or replace function public.mind_admin_read_analysis_runs(p_id text default null)
returns setof jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', a.id,
    'conversaId', a.conversa_id,
    'analisador', a.analisador,
    'funcao', a.funcao,
    'vertical', a.vertical,
    'modelo', a.modelo,
    'promptVersao', a.prompt_versao,
    'analisadoEm', a.analisado_em,
    'canal', c.canal,
    'agente', c.agente,
    'rota', (select coalesce(m.blocos->>'rota_aplicada', m.blocos->>'rota')
               from engagement.mensagens m
              where m.conversa_id = c.id and m.papel = 'agente'
                and coalesce(m.blocos->>'rota_aplicada', m.blocos->>'rota') is not null
              order by m.criado_em desc limit 1),
    'primeiroNome', nullif(split_part(coalesce(p.primeiro_nome, c.nome_contato, ''), ' ', 1), ''),
    'memoriasGravadas', (select count(*) from intelligence.participante_memoria pm where pm.analise_conversa_id = a.id),
    'continuidade', (select cc.continuation_status from intelligence.continuidade_comercial cc where cc.analise_conversa_id = a.id limit 1),
    'dados', case when p_id is null then null else public.mind_admin_mascarar_jsonb(a.dados) end,
    'memorias', case when p_id is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
               'tipo', pm.tipo, 'chave', pm.chave, 'status', pm.status, 'confianca', pm.confianca,
               'valor', public.mind_admin_mascarar_jsonb(pm.valor))
             order by pm.criado_em)
        from intelligence.participante_memoria pm where pm.analise_conversa_id = a.id), '[]'::jsonb) end)
  from intelligence.analise_conversa a
  join engagement.conversas c on c.id = a.conversa_id
  left join pessoas.pessoas p on p.id = c.mind_id
  where (p_id is null and a.analisado_em > now() - interval '30 days') or a.id::text = p_id
  order by a.analisado_em desc
  limit case when p_id is null then 200 else 1 end;
$$;
revoke all on function public.mind_admin_read_analysis_runs(text) from public, anon, authenticated;
grant execute on function public.mind_admin_read_analysis_runs(text) to service_role;
