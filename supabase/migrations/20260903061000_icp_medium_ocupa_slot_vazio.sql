-- ICP `medium` OCUPA O SLOT VAZIO.
--
-- `icp_atual` é um slot único por pessoa. O `analise_concierge` só emite ICP a partir
-- de cargo/autoidentificação inequívocos, e classifica a confiança: `high` quando a
-- evidência é inequívoca, `medium` quando a inferência de cargo ainda admite alguma
-- ambiguidade. O writer transformava `medium` em `proposta`, e nenhum leitor lê
-- `proposta` (`mind_customer_intelligence` e o Kit só entregam `ativa`).
--
-- Medido em 03/09: dos 3 ICPs que o sistema já emitiu, 3 eram `medium`. A memória
-- tinha zero linhas de ICP visíveis; o CRM tem `icp` canônico em 13 de 12.394
-- contatos. O sistema não sabia o ICP de ninguém.
--
-- A regra do Passo 4 continua: uma inferência ambígua NÃO derruba um ICP ativo.
-- O que muda é o caso do slot vazio: sem ICP ativo, o `medium` é o melhor que
-- sabemos e entra `ativa` com a confiança 0,70 exposta pelo leitor — o `base` já
-- instrui o Agent a tratar ICP como contexto, nunca como dor ou prioridade. Um
-- `high` posterior substitui (`substituida_por`), como antes.
--
-- Patch cirúrgico no mesmo padrão do Passo 4 §4: lê a definição viva, exige a
-- âncora exata (uma ocorrência) e falha se a forma mudou. Idempotente pela marca.
do $do$
declare v_def text; v_old text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'analise_projetar_memoria'
    and pg_get_function_identity_arguments(p.oid)
        = 'p_participante uuid, p_analisador text, p_memorias jsonb, p_analise_id uuid';

  if v_def is null then raise exception 'analise_projetar_memoria_ausente'; end if;
  if position('ICP MEDIUM OCUPA SLOT VAZIO' in v_def) > 0 then return; end if;

  v_old := E'\n\n      if v_tipo = ''jtbd'' then\n';
  v_new := E'\n\n'
        || E'      -- ICP MEDIUM OCUPA SLOT VAZIO (03/09). Sem ICP ativo, a inferência medium\n'
        || E'      -- é o melhor que sabemos e entra ativa com a confiança exposta pelo leitor.\n'
        || E'      -- Com ICP ativo, continua valendo a regra do Passo 4: medium não derruba.\n'
        || E'      if v_tipo = ''icp'' and v_conf = ''medium'' and not exists (\n'
        || E'           select 1 from intelligence.participante_memoria pm\n'
        || E'            where pm.participante_id = p_participante\n'
        || E'              and pm.chave = ''icp_atual'' and pm.status = ''ativa'') then\n'
        || E'        v_status := ''ativa'';\n'
        || E'      end if;\n'
        || E'\n'
        || E'      if v_tipo = ''jtbd'' then\n';

  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'analise_projetar_memoria_forma_inesperada';
  end if;
  execute replace(v_def, v_old, v_new);
end
$do$;
