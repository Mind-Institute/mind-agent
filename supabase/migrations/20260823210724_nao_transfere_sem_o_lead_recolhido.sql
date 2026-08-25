-- "Nunca faca handoff pra vendedor sem coletar o lead" (Adriana, 23/08).
--
-- Entra no prompt universal porque vale para os dois lados: passar um lead para
-- o vendedor e passar um cliente para o atendimento. Quem recebe sem isso comeca
-- do zero, e a pessoa conta a historia de novo.
update treble.prompts
   set conteudo = conteudo || E'\n\nANTES DE PASSAR PARA UMA PESSOA — nunca transfira sem ter recolhido quem é e o que quer.\nO mínimo é nome, WhatsApp e e-mail. Se for empresa pagando, também a empresa. E sempre: o que a pessoa está buscando, ou qual é o problema dela.\nPeça o que falta antes de transferir, uma coisa por vez, dizendo por quê — quem vai continuar precisa saber com quem está falando e sobre o quê.\nA regra de pedir o e-mail no máximo duas vezes vale enquanto você atende. Para transferir, ele é necessário: peça de novo explicando que é assim que a pessoa consegue te retornar.',
       versao = versao + 1,
       atualizado_em = now()
 where chave = 'base';
