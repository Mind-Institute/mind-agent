-- O HANDOFF SAI DO ROUTER E VIRA `base`: o playbook injetado em toda conversa.
--
-- CORREÇÃO DE ENDEREÇO. Na 20260831080000 eu coloquei a conduta de "quando você não
-- souber" dentro de `playbook_router`, argumentando que a casa universal já existia.
-- Estava errado quanto ao ENDEREÇO: `playbook_router` é identidade e roteamento, e
-- misturar conduta ali significa que qualquer agente que não passe pelo router não
-- recebe a regra. Regra de handoff é de TODO agente, não do que roteia.
--
-- `treble_agent_prompt` já compõe `chave in ('base','playbook_router')` na camada
-- `agent`. A chave `base` era um slot RESERVADO E VAZIO — nenhuma linha existia. Ela
-- passa a existir agora, e é onde mora o que vale em toda conversa.
--
-- ORDEM DETERMINÍSTICA. Com `base` e `playbook_router` os dois em `ordem 1`, o
-- `string_agg(... order by ordem)` deixava a ordem entre eles indefinida — o mesmo
-- prompt podia sair montado de dois jeitos entre chamadas. A ambiguidade nasce com
-- esta migration, então ela se resolve aqui: passa a ordenar por (ordem, chave), e
-- 'base' vem antes de 'playbook_router'. Nenhum outro trecho muda de lugar, porque
-- cada um dos outros já tem `ordem` própria.
--
-- NADA DE CONTEÚDO NOVO. O bloco é o mesmo texto da 20260831080000, movido. Quem já
-- aplicou a anterior fica exatamente com o mesmo prompt final, em outra casa.

do $mover$
declare
  v_bloco constant text :=
'QUANDO VOCÊ NÃO SOUBER — nunca fique calado nem desconverse. Deixar a pessoa sem resposta é pior que qualquer resposta honesta: ela conclui que foi ignorada e vai embora.
Dois tempos, nesta ordem:
1. ADMITA que você não tem essa informação — com naturalidade, sem rodeio e sem se desculpar demais. Não invente meio-caminho nem responda outra coisa no lugar.
2. OFEREÇA A SAÍDA que de fato existe neste canal. A redação é sua, escolha a que couber no momento; o que não muda é o conteúdo:
- se você pode transferir, diga que vai passar a conversa para alguém do time (needs_human=true);
- se este canal não transfere, diga que alguém do time entra em contato assim que possível.
Nunca prometa transferência que não acontece nem retorno que ninguém vai dar: prometer o que o canal não faz é uma forma de inventar.
Antes de encerrar o assunto, responda o que você AINDA consegue responder — quase sempre sobra algo útil, e assim a pessoa fica.
Isso não atropela o resto: continua valendo entregar valor e recolher quem é a pessoa antes de transferir de fato.';
  v_router_antes  text;
  v_router_depois text;
begin
  select conteudo into v_router_antes from agentes.prompts where chave = 'playbook_router';
  if v_router_antes is null then
    raise exception 'playbook_router não existe — revise antes de aplicar';
  end if;

  -- 1. TIRA do router, se a 20260831080000 já tiver rodado. Se não rodou, não há o que
  --    remover e a migration segue para criar o `base` do mesmo jeito.
  if position(v_bloco in v_router_antes) > 0 then
    v_router_depois := replace(v_router_antes, v_bloco || E'\n\n', '');
    if length(v_router_depois) <> length(v_router_antes) - length(v_bloco) - 2 then
      raise exception 'remoção do bloco do router deu tamanho inesperado: % vs %',
        length(v_router_depois), length(v_router_antes) - length(v_bloco) - 2;
    end if;
    if position(v_bloco in v_router_depois) > 0 then
      raise exception 'bloco ainda presente no router depois da remoção';
    end if;
    if position('CHAMAR HUMANO (needs_human=true)' in v_router_depois) = 0 then
      raise exception 'a âncora do router se perdeu na remoção';
    end if;
    update agentes.prompts
       set conteudo = v_router_depois, versao = versao + 1, atualizado_em = now()
     where chave = 'playbook_router';
    raise notice 'playbook_router: % -> % chars (bloco removido)',
      length(v_router_antes), length(v_router_depois);
  else
    raise notice 'playbook_router não tinha o bloco; nada a remover';
  end if;

  -- 2. CRIA (ou atualiza) o `base`. Idempotente: rodar de novo não duplica nada.
  insert into agentes.prompts (chave, titulo, conteudo, ativo, versao, produto_codigo)
  values ('base', 'Regras que valem em toda conversa (injetado sempre)', v_bloco, true, 1, null)
  on conflict (chave) do update
     set titulo        = excluded.titulo,
         conteudo      = excluded.conteudo,
         ativo         = true,
         versao        = agentes.prompts.versao + 1,
         atualizado_em = now()
   where agentes.prompts.conteudo is distinct from excluded.conteudo;

  raise notice 'base: % chars', length(v_bloco);
end
$mover$;

-- 3. ORDEM DETERMINÍSTICA entre `base` e `playbook_router`, que agora dividem ordem 1.
--    Só isso muda na função: o resto do corpo é idêntico ao da 20260831071000.
create or replace function public.treble_agent_prompt(
  p_audience text default 'desconhecido',
  p_camada   text default 'completo'
) returns text
language sql security definer
set search_path to 'public', 'agentes'
as $function$
  select string_agg(conteudo, E'\n\n' order by ordem, chave)
  from (
    select conteudo, chave, 1 as ordem from agentes.prompts
     where chave in ('base','playbook_router') and ativo
       and coalesce(p_camada,'completo') in ('completo','agent')
    union all
    select conteudo, chave, 2 from agentes.prompts where chave = 'tom_de_voz' and ativo
       and coalesce(p_camada,'completo') in ('completo','agent')
    union all
    select conteudo, chave, 3 from agentes.prompts
     where chave = 'sales_decision_engine' and ativo
       and coalesce(p_camada,'completo') in ('completo','decisioning')
       and coalesce(p_audience,'desconhecido') in
           ('b2c','b2b','desconhecido','summit_b2c','summit_b2b')
    union all
    select conteudo, chave, 4 from agentes.prompts
     where chave in ('playbook_' || coalesce(nullif(p_audience,''), 'desconhecido'),
                     'playbook_summit_' || coalesce(nullif(p_audience,''), 'desconhecido'))
       and ativo
       and coalesce(p_camada,'completo') in ('completo','agent')
    union all
    select conteudo, chave, 5 from agentes.prompts
     where chave = 'objecoes' and ativo
       and coalesce(p_camada,'completo') in ('completo','decisioning')
       and coalesce(p_audience,'desconhecido') in
           ('b2c','desconhecido','b2b','summit_b2c','summit_b2b')
  ) partes;
$function$;

revoke all on function public.treble_agent_prompt(text, text) from public, anon, authenticated;
grant execute on function public.treble_agent_prompt(text, text) to service_role;

-- 4. Confere o estado final.
do $check$
declare v_base text; v_router text; v_rota text;
begin
  select conteudo into v_base   from agentes.prompts where chave = 'base' and ativo;
  select conteudo into v_router from agentes.prompts where chave = 'playbook_router';

  if v_base is null then
    raise exception 'base não ficou ativo';
  end if;
  if position('QUANDO VOCÊ NÃO SOUBER' in v_base) = 0 then
    raise exception 'a conduta de handoff não ficou no base';
  end if;
  if position('QUANDO VOCÊ NÃO SOUBER' in v_router) > 0 then
    raise exception 'a conduta de handoff continua no router';
  end if;

  -- Injetado em TODA rota, na camada que roda hoje.
  foreach v_rota in array array['summit_b2c','summit_b2b','institute','dash',
                                'cliente_suporte','concierge_summit','desconhecido']
  loop
    if position('QUANDO VOCÊ NÃO SOUBER' in public.treble_agent_prompt(v_rota)) = 0 then
      raise exception 'handoff não chega na rota %', v_rota;
    end if;
    if position('QUANDO VOCÊ NÃO SOUBER' in public.treble_agent_prompt(v_rota, 'agent')) = 0 then
      raise exception 'handoff não chega na camada agent da rota %', v_rota;
    end if;
  end loop;
end
$check$;

notify pgrst, 'reload schema';
