-- treble_agent_prompt ganha CAMADA: o Decisioning para de viajar dentro do Agent.
--
-- O PROBLEMA. A funcao compunha cinco partes numa string so, e o runtime mandava tudo
-- para a mesma chamada que precisa ESCREVER a mensagem:
--
--   1 base + playbook_router     identidade, dados e limites   -> Agent
--   2 tom_de_voz                 como o Mind fala              -> Agent
--   3 sales_decision_engine      como decidir a estrategia     -> DECISIONING
--   4 playbook_<rota>            como vender aquela rota       -> Agent
--   5 objecoes                   como ler e resolver barreira  -> DECISIONING
--
-- As partes 3 e 5 somam ~35k caracteres de RACIOCINIO COMERCIAL. Manda-las junto com a
-- instrucao de redacao comprime PLAYBOOK + DECISIONING + AGENT numa etapa unica -- e
-- contradiz as quatro camadas do Core. Pior: a §20 do proprio sales_decision_engine
-- chama-se "SAIDA INTERNA" e lista os 14 campos que o modelo deveria determinar antes
-- de escrever. O contrato do Decisioning ja estava desenhado; nunca foi executado.
--
-- O QUE MUDA. Nada de conteudo: as mesmas cinco pecas, os mesmos textos, a mesma ordem.
-- Muda apenas QUEM RECEBE O QUE:
--
--   camada 'agent'        -> 1, 2, 4
--   camada 'decisioning'  -> 3, 5
--   camada 'completo'     -> todas (DEFAULT, byte a byte igual ao de hoje)
--
-- Medido em producao:
--
--   completo  summit_b2c   71.414   (inalterado)
--   agent     summit_b2c   36.360
--   decision  summit_b2c   35.052
--   agent     summit_b2b   23.070
--
--   36.360 + 35.052 + 2 (o separador) = 71.414  -> nada se perdeu na separacao.
--
-- O default 'completo' existe para que nenhum chamador atual mude de comportamento no
-- momento em que esta migration entra -- inclusive a Edge v1.5.0, que ainda chama a
-- funcao com um argumento so.
--
-- ACL: a assinatura nova nasceria com EXECUTE para PUBLIC, e esta funcao e
-- SECURITY DEFINER e devolve o playbook comercial inteiro. O revoke/grant abaixo a
-- deixa igual as funcoes irmas (mind_agent_kit, treble_agent_context): so service_role.

create or replace function public.treble_agent_prompt(
  p_audience text default 'desconhecido',
  p_camada   text default 'completo'
) returns text
language sql security definer
set search_path to 'public', 'agentes'
as $function$
  select string_agg(conteudo, E'\n\n' order by ordem)
  from (
    select conteudo, 1 as ordem from agentes.prompts
     where chave in ('base','playbook_router') and ativo
       and coalesce(p_camada,'completo') in ('completo','agent')
    union all
    select conteudo, 2 from agentes.prompts where chave = 'tom_de_voz' and ativo
       and coalesce(p_camada,'completo') in ('completo','agent')
    union all
    select conteudo, 3 from agentes.prompts
     where chave = 'sales_decision_engine' and ativo
       and coalesce(p_camada,'completo') in ('completo','decisioning')
       and coalesce(p_audience,'desconhecido') in
           ('b2c','b2b','desconhecido','summit_b2c','summit_b2b')
    union all
    select conteudo, 4 from agentes.prompts
     where chave in ('playbook_' || coalesce(nullif(p_audience,''), 'desconhecido'),
                     'playbook_summit_' || coalesce(nullif(p_audience,''), 'desconhecido'))
       and ativo
       and coalesce(p_camada,'completo') in ('completo','agent')
    union all
    select conteudo, 5 from agentes.prompts
     where chave = 'objecoes' and ativo
       and coalesce(p_camada,'completo') in ('completo','decisioning')
       and coalesce(p_audience,'desconhecido') in
           ('b2c','desconhecido','b2b','summit_b2c','summit_b2b')
  ) partes;
$function$;

-- A assinatura de 1 argumento sai: com as duas coexistindo, uma chamada com um
-- argumento so vira "function is not unique" e o runtime quebra.
drop function if exists public.treble_agent_prompt(text);

revoke all on function public.treble_agent_prompt(text, text) from public, anon, authenticated;
grant execute on function public.treble_agent_prompt(text, text) to service_role;

comment on function public.treble_agent_prompt(text, text) is
  'Compoe o prompt por CAMADA: agent (base+router, tom_de_voz, playbook da rota), decisioning (sales_decision_engine, objecoes) ou completo (todas, default e comportamento historico). A separacao existe para o Decisioning nao viajar dentro da chamada que escreve a mensagem.';

notify pgrst, 'reload schema';
