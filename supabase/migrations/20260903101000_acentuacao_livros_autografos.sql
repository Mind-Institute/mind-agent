-- A migration anterior foi aplicada com o contrato correto, mas o texto
-- apresentado a pessoas e ao Agent precisa preservar o portugues editorial.

update summit_2026.event_rules
set
  titulo = 'Livros para os autógrafos dos Legends',
  texto = 'Recomendar que participantes Prime levem seus próprios exemplares se quiserem garantir um livro para assinatura dos Legends. A Livraria da Vila terá livros para venda, mas a disponibilidade não é garantida. Livros importados podem existir em quantidades extremamente limitadas. Jan-Emmanuel De Neve, Christina Maslach e Sonja Lyubomirsky podem não ter livros publicados ou disponíveis no Brasil em volume suficiente. Não prometer estoque, título, quantidade, idioma ou possibilidade de assinatura de item que não seja livro sem confirmação oficial. A operação e o estoque dependem da Livraria da Vila; mesmo com esforço de abastecimento, um título pode acabar.',
  atualizado_em = now()
where chave = 'livros-autografos';

update concierge.avisos
set
  titulo = 'Leve seu livro para os autógrafos dos Legends',
  subtitulo = 'Se você é Prime e quer garantir um exemplar para assinatura, recomendamos levar o seu próprio livro.',
  descricao = 'A Livraria da Vila terá livros à venda, mas a disponibilidade não é garantida. Livros importados podem estar disponíveis em quantidades muito limitadas, e Jan-Emmanuel De Neve, Christina Maslach e Sonja Lyubomirsky podem não ter livros publicados ou disponíveis no Brasil em volume suficiente. Não conte com um título, idioma ou quantidade específicos.',
  atualizado_em = now()
where chave = 'livros_autografos';

update concierge.ferramentas
set
  descricao = case nome
    when 'buscar_intelligence' then
      'Procura em toda a Intelligence aprovada do Mind Summit: palestrantes, sessões, Knowledge Documents, regras, avisos, locais e expositores. Formule a necessidade nos termos do domínio. Devolve candidatos compactos com tipo e id; combine mais de uma fonte quando a pergunta exigir.'
    when 'ler_intelligence' then
      'Abre em profundidade um objeto encontrado por buscar_intelligence. Use tipo e id exatamente como devolvidos e leia todos os objetos necessários antes de responder perguntas que combinem sessão, acesso, regra, aviso ou local.'
  end
where nome in ('buscar_intelligence','ler_intelligence');
