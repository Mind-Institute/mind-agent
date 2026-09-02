-- PASSO 5 — MEMÓRIA DURÁVEL. Duas correções, só para `analise_concierge`.
--
-- 1) GATE DE SENSIBILIDADE. Hoje a função não olha `sensitivity`. O prompt novo do
--    analisador passa a emitir o campo; sem ler aqui, ele seria decorativo. Fail-closed:
--    só `none` projeta.
--
-- 2) STATUS. A regra viva é `stable + high => ativa`, todo o resto `proposta`. Um fato
--    explícito do Summit ("quero focar segurança psicológica neste evento") é `opportunity`
--    por natureza — ficaria eternamente em `proposta` e nunca voltaria ao Agent, tornando
--    a memória durável inútil justamente para o caso que a motivou. Passa a valer
--    `high + (stable|opportunity) => ativa`, e `temporary` não vira durável.
--
-- A semântica dos OUTROS analisadores fica intacta: o ramo é condicionado ao analisador.

create or replace function public.analise_projetar_memoria(
  p_participante uuid, p_analisador text, p_memorias jsonb, p_analise_id uuid default null::uuid)
returns integer
language plpgsql
security definer
set search_path to 'public','intelligence'
as $function$
declare
  mem jsonb; v_cat text; v_texto text; v_scope text; v_conf text; v_sens text;
  v_tipo text; v_chave text; v_valor jsonb; v_num numeric; v_status text;
  v_concierge boolean;
  v_exist intelligence.participante_memoria%rowtype; v_novo uuid; v_n int := 0;
begin
  if p_participante is null or jsonb_typeof(p_memorias) <> 'array' then return 0; end if;

  v_concierge := (p_analisador = 'analise_concierge');

  for mem in select * from jsonb_array_elements(p_memorias)
  loop
    begin
      v_cat   := lower(nullif(trim(coalesce(mem->>'category','')),''));
      v_texto := nullif(trim(coalesce(mem->>'value','')),'');
      v_scope := lower(coalesce(nullif(trim(coalesce(mem->>'scope','')),''), 'opportunity'));
      v_conf  := lower(coalesce(nullif(trim(coalesce(mem->>'confidence','')),''), 'low'));
      v_sens  := lower(btrim(coalesce(mem->>'sensitivity','')));

      continue when v_texto is null or v_cat is null or v_cat like '%|%';

      -- Gate do Concierge: só o que é declaradamente não sensível vira memória durável,
      -- e estado momentâneo não vira memória nenhuma.
      if v_concierge then
        continue when v_sens is distinct from 'none';
        continue when v_scope = 'temporary';
      end if;

      v_tipo := case v_cat
        when 'identity' then 'identidade'      when 'role' then 'cargo'
        when 'company' then 'empresa'          when 'goal' then 'objetivo'
        when 'interest' then 'interesse'       when 'preference' then 'preferencia'
        when 'constraint' then 'restricao'     when 'commercial_preference' then 'preferencia_comercial'
        when 'stakeholder' then 'stakeholder'  when 'delegation' then 'delegacao'
        when 'sponsorship' then 'patrocinio'   when 'logistics' then 'logistica'
        else 'outro' end;

      v_chave := case v_tipo
        when 'identidade' then 'identidade'
        when 'cargo'      then 'cargo_atual'
        when 'empresa'    then 'empresa_atual'
        else v_tipo || ':' || public.mind_slug(v_texto) end;

      v_valor := jsonb_build_object('text', v_texto, 'scope', v_scope)
                 || case when v_sens <> '' then jsonb_build_object('sensitivity', v_sens)
                         else '{}'::jsonb end;
      v_num   := case v_conf when 'high' then 0.90 when 'medium' then 0.70 else 0.50 end;

      v_status := case
        when v_concierge then
          case when v_conf = 'high' and v_scope in ('stable','opportunity') then 'ativa' else 'proposta' end
        else
          case when v_scope = 'stable' and v_conf = 'high' then 'ativa' else 'proposta' end
      end;

      select * into v_exist from intelligence.participante_memoria pm
       where pm.participante_id = p_participante and pm.chave = v_chave
         and pm.status in ('ativa','proposta')
       order by (pm.status = 'ativa') desc, pm.atualizado_em desc nulls last
       limit 1;

      if found then
        if v_exist.valor->>'text' is not distinct from v_texto then
          update intelligence.participante_memoria
             set confianca           = greatest(coalesce(confianca, 0), v_num),
                 status              = case when status = 'ativa' or v_status = 'ativa'
                                            then 'ativa' else status end,
                 analise_conversa_id = coalesce(p_analise_id, analise_conversa_id),
                 atualizado_em       = now()
           where id = v_exist.id;
        elsif v_chave in ('identidade','cargo_atual','empresa_atual') then
          insert into intelligence.participante_memoria
            (participante_id, tipo, chave, valor, confianca, origem, status,
             evidencia_message_id, analise_conversa_id)
          values (p_participante, v_tipo, v_chave, v_valor, v_num, p_analisador, v_status,
                  null, p_analise_id)
          returning id into v_novo;
          update intelligence.participante_memoria
             set status = 'substituida', substituida_por = v_novo, atualizado_em = now()
           where id = v_exist.id;
          v_n := v_n + 1;
        end if;
      else
        insert into intelligence.participante_memoria
          (participante_id, tipo, chave, valor, confianca, origem, status,
           evidencia_message_id, analise_conversa_id)
        values (p_participante, v_tipo, v_chave, v_valor, v_num, p_analisador, v_status,
                null, p_analise_id);
        v_n := v_n + 1;
      end if;
    exception when others then
      raise warning 'projecao_memoria falhou p/ item: %', sqlerrm;
    end;
  end loop;

  return v_n;
end $function$;

do $g$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='analise_projetar_memoria';
  if d !~ 'analise_concierge' then raise exception 'o ramo do concierge nao entrou'; end if;
  if d !~ 'v_sens is distinct from ''none''' then raise exception 'gate de sensibilidade ausente'; end if;
  if d !~ 'v_scope in \(''stable'',''opportunity''\)' then raise exception 'opportunity nao vira ativa'; end if;
  if d !~ 'v_scope = ''stable'' and v_conf = ''high''' then
    raise exception 'a regra dos outros analisadores foi perdida'; end if;
end $g$;
