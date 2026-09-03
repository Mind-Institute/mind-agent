-- Contrato pós-migração do Core compartilhado. Leitura apenas.

do $test$
declare
  v_b2b text;
  v_b2c text;
  v_busca jsonb;
begin
  select public.treble_agent_prompt('summit_b2b','completo') into v_b2b;
  select public.treble_agent_prompt('summit_b2c','completo') into v_b2c;

  if length(v_b2b)>=25000 or length(v_b2c)>=28000 then
    raise exception 'contexto excessivo: b2b %, b2c %',length(v_b2b),length(v_b2c);
  end if;
  if position('DECISIONING COMERCIAL UNIVERSAL' in v_b2b)=0
     or position('DECISIONING COMERCIAL UNIVERSAL' in v_b2c)=0 then
    raise exception 'B2B/B2C não compartilham o decisioning';
  end if;
  if exists (
    select 1 from agentes.kit_blocos
    where rota in ('summit_b2b','summit_b2c') and secao='decisioning'
      and ativo and bloco<>'decisioning_vendas_universal'
  ) then
    raise exception 'há dois decisionings concorrentes em rota de venda';
  end if;
  if (select count(*) from agentes.kit_blocos
      where rota in ('summit_b2b','summit_b2c') and secao='tools' and ativo
        and bloco in ('buscar_intelligence','ler_intelligence'))<>4 then
    raise exception 'lupa não está ativa nas duas rotas de venda';
  end if;

  v_busca:=public.mind_intelligence_buscar_contextual(
    'saúde mental e liderança',6,'summit_b2b','whatsapp','mind-summit-2026',null
  );
  if v_busca->>'motor'<>'lexical' or jsonb_typeof(v_busca->'candidatos')<>'array' then
    raise exception 'fallback lexical da lupa quebrou: %',v_busca;
  end if;

  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='engagement'
      and c.relname in ('identidades','pessoa_perfil','treble_eventos')
      and not c.relrowsecurity
  ) then
    raise exception 'RLS defensivo não está ativo';
  end if;
  if (select count(*) from engagement.avaliacoes where caso like 'core_v9_%')<>5 then
    raise exception 'casos de avaliação do Core ausentes';
  end if;
end
$test$;
