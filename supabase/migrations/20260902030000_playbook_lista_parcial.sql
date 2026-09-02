-- PLAYBOOK DO CONCIERGE: DUAS CORREÇÕES MEDIDAS, NENHUMA REGRA NOVA.
--
-- 1) LISTA PARCIAL. Medido em runtime (v1.8.0, 02/09): "Qual a programação do dia 17?"
--    devolveu 12 sessões de 38. A resposta não mentiu — abriu com "neste recorte
--    oficial" — mas a pessoa saiu achando que tinha visto o dia inteiro.
--    A regra JÁ EXISTIA ("nunca apresente uma lista parcial como se fosse completa")
--    e o Kit JÁ ENVIAVA `sessions_total: 38` junto das 12. O que faltava era ligar as
--    duas coisas: a regra falava de "quando souber que há mais", e o modelo não
--    reconhecia o campo como esse saber. Aqui ela passa a nomear o campo.
--
-- 2) INVESTIGAÇÃO DUPLICADA. `DE ONDE VÊM OS FATOS` e `QUANDO INVESTIGAR` diziam a
--    mesma coisa em dois lugares — inclusive a mesma frase sobre formular a busca.
--    Vira um bloco só, sem perder nada do que cada um tinha de próprio. Duas casas
--    para a mesma regra é como playbook começa a divergir de si mesmo.
--
-- Substituição por trecho, não reescrita: o resto do playbook fica byte a byte igual.

update agentes.prompts set conteudo = replace(
  conteudo,
  E'DE ONDE VÊM OS FATOS:\n'
  || E'- Quando o dado exato já está no contexto oficial que você recebeu, responda direto. Não vá buscar por hábito.\n'
  || E'- Quando não está, consulte: `buscar_intelligence` para encontrar candidatos e `ler_intelligence` para abrir um deles em profundidade.\n'
  || E'- Quem formula a busca é você. Traduza o que a pessoa quer para os termos do domínio em vez de repetir a frase dela.\n'
  || E'- Se a busca não trouxer nada que responda, diga que não encontrou. Nunca complete com conhecimento próprio, e nunca estime horário, sala ou número.',
  E'DE ONDE VÊM OS FATOS:\n'
  || E'- O contexto oficial que você recebe é o que a busca daquele turno alcançou — não é o catálogo inteiro.\n'
  || E'- Quando o dado exato já está nele, responda direto. Não vá buscar por hábito.\n'
  || E'- Quando não está, consulte: `buscar_intelligence` para encontrar candidatos e `ler_intelligence` para abrir um deles em profundidade. É o caso de quem é uma pessoa, do que ela defende, e de conteúdo que trata de um problema descrito com as palavras de quem fala com você.\n'
  || E'- Quem formula a busca é você. Traduza o que a pessoa quer para os termos do domínio em vez de repetir a frase dela.\n'
  || E'- Achou algo que importa? Abra em profundidade antes de afirmar qualquer coisa sobre aquilo — citar um título não é conhecer o conteúdo.\n'
  || E'- Se a busca não trouxer nada que responda, diga que não encontrou. Nunca complete com conhecimento próprio, e nunca estime horário, sala ou número.'
) where chave = 'playbook_concierge_summit';

update agentes.prompts set conteudo = replace(
  conteudo,
  E'QUANDO INVESTIGAR:\n'
  || E'O contexto oficial que você recebe é o que a busca daquele turno alcançou. Quando ele já responde exatamente o que foi perguntado, responda direto — não procure por hábito.\n'
  || E'Procure quando precisar de algo que não veio: quem é uma pessoa, o que ela defende, qual conteúdo trata de um problema descrito com as palavras da pessoa. Quem formula a busca é você: traduza o pedido para os termos do domínio em vez de repetir a frase dela.\n'
  || E'Achou algo que importa? Abra em profundidade antes de afirmar qualquer coisa sobre aquilo — citar um título não é conhecer o conteúdo.\n\n',
  ''
) where chave = 'playbook_concierge_summit';

update agentes.prompts set conteudo = replace(
  conteudo,
  E'- Nunca apresente uma lista parcial como se fosse completa. Quando souber que há mais do que você está mostrando, diga quantos são no total.',
  E'- Nunca apresente uma lista parcial como se fosse completa. O contexto traz `sessions_total`: se ele for maior que o número de sessões que chegou até você, diga na abertura quantas existem no total e ofereça um recorte útil — parte do dia, tipo de sessão, tema. Pedir "a programação do dia" e receber uma dúzia sem aviso faz a pessoa acreditar que viu o dia inteiro.'
) where chave = 'playbook_concierge_summit';

-- GUARDAS. Falhar aqui aborta a transação inteira e o playbook fica como estava.
do $$
declare p text;
begin
  select conteudo into p from agentes.prompts where chave = 'playbook_concierge_summit';
  if p is null then raise exception 'playbook_concierge_summit sumiu'; end if;

  -- 1) a regra da lista parcial agora nomeia o campo que o Kit realmente manda
  if position('`sessions_total`' in p) = 0 then
    raise exception 'a regra da lista parcial nao nomeia sessions_total';
  end if;

  -- 2) investigacao mora em UM lugar so
  if position('QUANDO INVESTIGAR' in p) > 0 then
    raise exception 'bloco QUANDO INVESTIGAR ainda existe: a duplicacao continua';
  end if;
  if (length(p) - length(replace(p, 'Quem formula a busca é você', ''))) / length('Quem formula a busca é você') <> 1 then
    raise exception 'a instrucao de formular a busca aparece mais de uma vez';
  end if;
  if position('Abra em profundidade antes de afirmar' in p) = 0 then
    raise exception 'a regra de abrir em profundidade se perdeu na fusao';
  end if;
  if position('buscar_intelligence' in p) = 0 or position('ler_intelligence' in p) = 0 then
    raise exception 'as ferramentas sumiram do playbook';
  end if;

  -- 3) o que ja estava certo continua no lugar
  if position('INFORMAÇÃO QUE NÃO EXISTE NÃO É CASO DE ATENDIMENTO' in p) = 0 then
    raise exception 'o criterio de escalonamento se perdeu';
  end if;
  if position('a lista inteira é a resposta certa' in p) = 0 then
    raise exception 'a regra de nao cortar a lista se perdeu';
  end if;
  if position('DD/MM HH:MM–HH:MM' in p) = 0 then
    raise exception 'o formato de sessao se perdeu';
  end if;
end $$;
