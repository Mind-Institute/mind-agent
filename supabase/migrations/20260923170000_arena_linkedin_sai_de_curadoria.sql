-- As 5 sessões da Arena LinkedIn já têm título, espaço e horário definidos pela
-- planilha do app. A marca tipo='em-curadoria' é a única coisa que ainda as
-- descreve como indefinidas, e é falsa.
--
-- A planilha não informa o tipo da sessão (a coluna Categoria dela é "AGENDAR"
-- em todas as 85 linhas, é o comportamento do card no app, não o formato da
-- sessão). Então o tipo fica nulo: o backend deixa de afirmar o que não sabe,
-- em vez de trocar uma afirmação errada por um palpite.
update summit_2026.sessions
   set tipo = null, atualizado_em = now()
 where tipo = 'em-curadoria';
