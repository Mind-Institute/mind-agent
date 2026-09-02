-- CORREÇÃO DA CORREÇÃO ANTERIOR (20260902030000), medida no runtime logo depois dela.
--
-- A regra passou a nomear `sessions_total` e o modelo passou a usá-lo — mas falando do
-- encanamento em vez do evento: "Recebi 38 sessões para o dia 17, mas aqui só chegaram
-- 11" — e ainda errando a contagem (listou 12). Duas coisas erradas de uma vez:
--   * a pessoa não tem nada a ver com quantas sessões o retrieval entregou naquele turno;
--   * pedir para o modelo contar o que recebeu é pedir um número que ele erra.
-- O total, esse sim, vem pronto no contexto e é o único que interessa a quem perguntou.
--
-- Também no mesmo turno: "• 17/09 08:00–09:00 — Credenciamento —", travessão sozinho
-- onde a sessão não tem local. O formato precisa dizer o que fazer quando o campo falta.

update agentes.prompts set conteudo = replace(
  conteudo,
  E'- Nunca apresente uma lista parcial como se fosse completa. O contexto traz `sessions_total`: se ele for maior que o número de sessões que chegou até você, diga na abertura quantas existem no total e ofereça um recorte útil — parte do dia, tipo de sessão, tema. Pedir "a programação do dia" e receber uma dúzia sem aviso faz a pessoa acreditar que viu o dia inteiro.',
  E'- Nunca apresente uma lista parcial como se fosse completa. O contexto traz `sessions_total`: quando ele for maior que a lista que chegou até você, abra dizendo quantas sessões existem no total e ofereça um caminho para chegar no resto — parte do dia, tipo de sessão, tema.\n'
  || E'- Diga o TOTAL, e só ele. Nunca diga quantas sessões chegaram até você, nem descreva a busca ("recebi", "chegaram", "neste recorte", "com o que tenho em mãos"): quem pergunta quer a programação do evento, não o funcionamento do sistema. Contar o que você recebeu também é errar — o número já vem pronto no contexto.'
) where chave = 'playbook_concierge_summit';

update agentes.prompts set conteudo = replace(
  conteudo,
  E'- Sem tabela e sem título em Markdown.',
  E'- Sessão sem local termina no título: "• DD/MM HH:MM–HH:MM — Título". Travessão sozinho no fim da linha é defeito, e "sem local informado" é ruído.\n'
  || E'- Sem tabela e sem título em Markdown.'
) where chave = 'playbook_concierge_summit';

do $$
declare p text;
begin
  select conteudo into p from agentes.prompts where chave = 'playbook_concierge_summit';
  if p is null then raise exception 'playbook_concierge_summit sumiu'; end if;

  if position('Diga o TOTAL, e só ele' in p) = 0 then
    raise exception 'a regra de dizer so o total nao entrou';
  end if;
  if position('quantas sessões existem no total' in p) = 0 then
    raise exception 'a regra da lista parcial se perdeu';
  end if;
  if position('Travessão sozinho no fim da linha é defeito' in p) = 0 then
    raise exception 'a regra do local ausente nao entrou';
  end if;
  -- a versao anterior da regra nao pode sobreviver ao lado da nova
  if position('faz a pessoa acreditar que viu o dia inteiro' in p) > 0 then
    raise exception 'a redacao antiga da regra continua no playbook';
  end if;
  -- o que ja estava certo continua no lugar
  if position('`sessions_total`' in p) = 0 then
    raise exception 'sessions_total sumiu do playbook';
  end if;
  if position('a lista inteira é a resposta certa' in p) = 0 then
    raise exception 'a regra de nao cortar a lista se perdeu';
  end if;
  if position('INFORMAÇÃO QUE NÃO EXISTE NÃO É CASO DE ATENDIMENTO' in p) = 0 then
    raise exception 'o criterio de escalonamento se perdeu';
  end if;
  if position('DD/MM HH:MM–HH:MM — Título — Local' in p) = 0 then
    raise exception 'o formato de sessao se perdeu';
  end if;
end $$;
