-- DOIS DEFEITOS DE HONESTIDADE, medidos depois de 20260902050000.
--
-- E) O SISTEMA VAZANDO NA FALA. A proibição anterior era uma lista de frases ("recebi",
--    "chegaram", "neste recorte", "com o que tenho em mãos") e o modelo simplesmente
--    arrumou outras: "com o que veio neste turno", "o contexto oficial não trouxe a
--    descrição dela". Lista de frase proibida não fecha; a regra tem que ser a regra.
--    Vai para `base` porque vale nos dois canais.
--
-- F) NÚMERO CERTO NO LUGAR ERRADO. "Qual a programação do dia 17?" respondeu "O Mind
--    Summit 2026 tem 38 sessões no total." 38 é o total DO DIA 17; o evento tem 77, e
--    esse número está no mesmo bloco, em `totais.sessoes`. O agente não inventou nada —
--    trocou dois campos —, e mesmo assim disse à pessoa um fato falso sobre o evento.
--    Vai para o playbook porque é leitura do Kit desta competência.

update agentes.prompts set conteudo = replace(
  conteudo,
  E'- Escreva em português do Brasil, com os nomes oficiais. Nunca misture caracteres de outro alfabeto dentro de palavras portuguesas.',
  E'- NUNCA DESCREVA O SISTEMA PARA A PESSOA. Ela não sabe — e não precisa saber — que existe turno, contexto, bloco, busca, recorte ou base. Quando faltar informação, a frase é sobre o mundo e não sobre o mecanismo: "não encontrei", "não consigo confirmar", "isso ainda não está publicado". Nunca "o contexto não trouxe", "com o que veio neste turno", "na minha base".\n'
  || E'- Escreva em português do Brasil, com os nomes oficiais. Nunca misture caracteres de outro alfabeto dentro de palavras portuguesas.'
) where chave = 'base';

update agentes.prompts set conteudo = replace(
  conteudo,
  E'- Isso vale só quando pediram uma LISTA — a programação de um dia, todos os workshops. Em recomendação ninguém perguntou o tamanho do catálogo: abrir com o total do evento é ruído, e a resposta começa pelo que interessa a ela.',
  E'- Isso vale só quando pediram uma LISTA — a programação de um dia, todos os workshops. Em recomendação ninguém perguntou o tamanho do catálogo: abrir com o total do evento é ruído, e a resposta começa pelo que interessa a ela.\n'
  || E'- `sessions_total` é o total DO QUE FOI PEDIDO — as sessões daquele dia, daquele tipo —, não do evento inteiro; o total do evento é `totais.sessoes`, no mesmo bloco. Trocar um pelo outro é dizer um número falso com cara de oficial: "o dia 17 tem 38 sessões" está certo, "o Summit tem 38 sessões" está errado.'
) where chave = 'playbook_concierge_summit';

do $$
declare b text; p text;
begin
  select conteudo into b from agentes.prompts where chave = 'base';
  select conteudo into p from agentes.prompts where chave = 'playbook_concierge_summit';
  if b is null or p is null then raise exception 'prompt canonico sumiu'; end if;

  if position('NUNCA DESCREVA O SISTEMA PARA A PESSOA' in b) = 0 then
    raise exception 'a regra de nao descrever o sistema nao entrou em base';
  end if;
  if position('o total do evento é `totais.sessoes`' in p) = 0 then
    raise exception 'a distincao entre sessions_total e totais.sessoes nao entrou';
  end if;

  -- o que ja estava certo continua no lugar
  if position('A CONVERSA TAMBÉM É FONTE' in b) = 0 then
    raise exception 'a regra do seguimento se perdeu';
  end if;
  if position('Nunca misture caracteres de outro alfabeto' in b) = 0 then
    raise exception 'a regra do alfabeto se perdeu';
  end if;
  if position('cada sessão é UM tópico só' in p) = 0 then
    raise exception 'a regra do porque se perdeu';
  end if;
  if position('O QUE A PRÓPRIA PESSOA FAZ NO APP TAMBÉM NÃO É ENCAMINHAMENTO' in p) = 0 then
    raise exception 'a regra do que e da pessoa se perdeu';
  end if;
end $$;
