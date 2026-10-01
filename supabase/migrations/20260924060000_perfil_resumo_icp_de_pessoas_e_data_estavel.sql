-- Resumo da inteligência (HubSpot `mind_resumo_inteligencia`):
-- 1. a linha do ICP lê pessoas.pessoas.icp (a fonte única desde 24/09, com icp_fonte); a memória fica de
--    reserva. Antes dizia "não classificado" para quem tinha ICP pelo cargo do HubSpot.
-- 2. "Atualizado em" usa a última mudança real (memória ou pessoas.pessoas), nunca now(): com now() o texto
--    mudava a cada rodada e o write-back horário reescrevia milhares de contatos sem dado novo
--    (4.806 na segunda execução de 24/09).
do $migra$
declare d text := pg_get_functiondef('intelligence.perfil_resumo(uuid)'::regprocedure); o text;
begin
  o := d;
  d := replace(d, $x$  v_jobs text; v_hip text; v_obj text; v_prod text; v_quando text; v_fit text; v_atualizado timestamptz;$x$,
                  $x$  v_jobs text; v_hip text; v_obj text; v_prod text; v_quando text; v_fit text; v_atualizado timestamptz;
  v_pessoa_icp text; v_pessoa_icp_fonte text; v_pessoa_atualizado timestamptz;$x$);
  d := replace(d, $x$  select nullif(btrim(p.cargo), ''), nullif(btrim(p.empresa), '') into v_cargo, v_empresa
    from pessoas.pessoas p where p.id = p_mind and p.fundida_em is null;$x$,
                  $x$  select nullif(btrim(p.cargo), ''), nullif(btrim(p.empresa), ''), i.rotulo, p.icp_fonte, p.atualizado_em
    into v_cargo, v_empresa, v_pessoa_icp, v_pessoa_icp_fonte, v_pessoa_atualizado
    from pessoas.pessoas p left join intelligence.icp i on i.codigo = p.icp
   where p.id = p_mind and p.fundida_em is null;$x$);
  d := replace(d, $x$   where pm.mind_id = p_mind and pm.chave = 'icp_atual' and pm.status = 'ativa'
   order by pm.atualizado_em desc limit 1;$x$,
                  $x$   where pm.mind_id = p_mind and pm.chave = 'icp_atual' and pm.status = 'ativa'
   order by pm.atualizado_em desc limit 1;
  -- a fonte única do ICP é pessoas.pessoas (24/09); a memória só vale quando lá não há nada
  if v_pessoa_icp is not null then
    v_icp := v_pessoa_icp;
    v_icp_origem := null;
    v_icp_fonte := case v_pessoa_icp_fonte
      when 'credenciamento' then 'cargo_credenciamento_yazo'
      when 'hubspot_cargo' then 'cargo_hubspot'
      when 'conversa_cargo' then 'cargo_conversa'
      when 'cadastro' then 'cargo_pessoa'
      when 'hubspot_icp' then 'hubspot_icp'
      when 'conversa' then 'conversa'
      else v_pessoa_icp_fonte end;
  end if;$x$);
  d := replace(d, $x$        when v_icp_origem like 'analise_%' then 'observado em conversa'$x$,
                  $x$        when v_icp_fonte = 'hubspot_icp' then 'marcado no HubSpot'
        when v_icp_fonte = 'conversa' or v_icp_origem like 'analise_%' then 'observado em conversa'$x$);
  d := replace(d, $x$to_char(coalesce(v_atualizado, now()) at time zone$x$,
                  $x$to_char(coalesce(greatest(v_atualizado, v_pessoa_atualizado), v_atualizado, v_pessoa_atualizado) at time zone$x$);
  if d = o or strpos(d, 'v_pessoa_icp_fonte') = 0 or strpos(d, 'marcado no HubSpot') = 0 or strpos(d, 'now()') > 0 then
    raise exception 'perfil_resumo: algum trecho esperado não foi encontrado; nada alterado';
  end if;
  execute d;
end $migra$;
