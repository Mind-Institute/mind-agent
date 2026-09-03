-- O CLASSIFICADOR NÃO MANDAVA A PESSOA PARA QUEM SABE APRENDÊ-LA.
--
-- `analise_classificador` (v2, 28/08) é anterior ao Passo 4. Ele escolhe
-- `analise_concierge` por "interesses, preferências, objetivos, experiência" — e
-- `analise_concierge` é o ÚNICO analisador que conhece ICP e JTBD. Cargo, empresa e
-- desafio profissional não estavam no critério, então a conversa mais valiosa para
-- Customer Intelligence ("sou CHRO e preciso levar 30 gestores") ia só para
-- `analise_vendas_summit`, cujo prompt não emite ICP/JTBD.
--
-- Medido em 03/09: 258 análises de vendas trazem cargo/empresa/identidade em
-- `customer_memory`; só 16 delas também passaram pelo concierge (6%).
--
-- A menor mudança são três âncoras no prompt: os exemplos da seção 5, a pergunta 5
-- de COMO CLASSIFICAR e o exemplo do RH com 30 gestores, que passa a acionar os dois
-- analisadores — como o próprio prompt já fazia para "compra + interesses". O schema
-- de saída é estrito (enum fechado): a mudança não pode quebrar o formato.
-- Guardado por versão e pelas três âncoras; falha alto se não aplicar.
update agentes.prompts
set conteudo = replace(replace(replace(conteudo,
  $a1$- informações úteis para futuras recomendações.$a1$,
  $b1$- informações úteis para futuras recomendações;
- cargo, função ou área que a própria pessoa declara (ex.: "sou HRBP", "sou CEO", "trabalho no RH");
- empresa ou contexto profissional declarado pela pessoa;
- problema, desafio, progresso ou resultado profissional que a pessoa quer alcançar (ex.: desenvolver gestores, conduzir conversas difíceis, provar ROI ao board, estruturar riscos psicossociais).$b1$),
  $a2$5. Existe conteúdo substantivo sobre interesses, objetivos, preferências ou experiência da pessoa que seja útil para personalização futura?$a2$,
  $b2$5. Existe conteúdo substantivo sobre interesses, objetivos, preferências ou experiência da pessoa, ou sobre quem ela é profissionalmente (cargo, função, empresa, desafio ou resultado que busca), que seja útil para personalização futura?$b2$),
  $a3$RH conversa sobre levar 30 gestores ao Summit e precisa conseguir aprovação do diretor.

OUTPUT:
["analise_vendas_summit"]$a3$,
  $b3$RH conversa sobre levar 30 gestores ao Summit e precisa conseguir aprovação do diretor.

OUTPUT:
["analise_vendas_summit", "analise_concierge"]

O segundo entra porque a pessoa revelou de onde fala (RH), um resultado que busca (desenvolver 30 gestores) e um ator da decisão (o diretor).


CONVERSA:
Pessoa diz que é CHRO, quer estruturar bem-estar como gestão de riscos psicossociais e pergunta o preço do Summit.

OUTPUT:
["analise_vendas_summit", "analise_concierge"]$b3$),
    versao = 3,
    atualizado_em = now()
where chave = 'analise_classificador'
  and versao = 2
  and conteudo like '%- informações úteis para futuras recomendações.%'
  and conteudo like '%5. Existe conteúdo substantivo sobre interesses, objetivos, preferências ou experiência da pessoa que seja útil para personalização futura?%'
  and conteudo like '%RH conversa sobre levar 30 gestores ao Summit e precisa conseguir aprovação do diretor.%';

do $do$
begin
  if not exists (
    select 1 from agentes.prompts
    where chave = 'analise_classificador' and versao = 3
      and conteudo like '%quem ela é profissionalmente%'
      and conteudo like '%cargo, função ou área que a própria pessoa declara%'
      and conteudo like '%O segundo entra porque a pessoa revelou de onde fala%') then
    raise exception 'analise_classificador_nao_atualizado';
  end if;
end
$do$;
