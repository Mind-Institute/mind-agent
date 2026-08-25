-- "Pode transferir mesmo assim, se ela nao quiser dar o email, mas acho que tem
-- que insistir pelo menos umas tres vezes." (Adriana, 23/08)
--
-- Duas vezes enquanto atende; tres quando vai transferir, porque ai o e-mail e o
-- que permite retornar. Passou disso, transfere assim mesmo: pessoa presa numa
-- pergunta e pior que lead incompleto.
update treble.prompts
   set conteudo = replace(
         conteudo,
         'A regra de pedir o e-mail no máximo duas vezes vale enquanto você atende. Para transferir, ele é necessário: peça de novo explicando que é assim que a pessoa consegue te retornar.',
         'A regra de pedir o e-mail no máximo duas vezes vale enquanto você atende. Para transferir, insista até três vezes, explicando que é assim que a pessoa consegue receber retorno. Se ainda assim ela não quiser dar, transfira do mesmo jeito e registre que o e-mail ficou faltando — deixar alguém preso numa pergunta é pior que um lead incompleto.'),
       versao = versao + 1,
       atualizado_em = now()
 where chave = 'base';