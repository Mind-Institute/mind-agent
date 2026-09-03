-- Avisos da home (03/09, pedido da Adriana): seis na ordem dela, sem "agora", datas e horários
-- nos textos que ela não reescreveu; o do ingresso volta ao ar em "Antes de ir ao Summit"; reserve_exp,
-- Rhino, credenciamento e autógrafos com o texto literal dela (título + resumo no card fechado; mensagem ao abrir).
-- A ordem da home é decidida por disparo_em desc (api.mindagent_home_publico), então os seis
-- recebem os seis horários mais recentes, um minuto de diferença cada, em 15/09 à noite.
-- Idempotente: cada update casa pela chave e grava o estado final.

update concierge.avisos set
  titulo = 'Reserve agora as experiências que você não quer perder',
  subtitulo = 'Arena LinkedIn, Arena Sextante, Workshops e Masterclasses têm lugares limitados.',
  descricao = 'Faça o agendamento no app e confirme em Minha Agenda. No dia, sua vaga ficará garantida somente até 5 minutos antes do início.',
  ver_no_app = 'reserva', botao_ver_no_app = 'Veja aqui como agendar as experiências',
  disparo_em = '2026-09-15 21:00:00+00', atualizado_em = now()
where chave = 'reserve_exp';

update concierge.avisos set
  titulo = 'Venha de Rhino para o Mind Summit',
  subtitulo = 'Quem nunca utilizou o serviço recebe R$ 200 de desconto na primeira corrida usando o cupom MINDSUMMIT.',
  descricao = E'💡 Dica para utilização: se for/voltar em mais de uma pessoa do evento, uma pode se cadastrar na ida e outra na volta, aproveitando o desconto nos dois momentos!\n\n📍 Regras de valor mínimo:\nCorridas de até 10 km: valor fixo de R$49\nCorridas acima de 10 km: valor mínimo de R$149\n\nCupom ativo e com validade até 31 de dezembro, depois de cadastrado no app precisa ser usado em 30 dias',
  disparo_em = '2026-09-15 20:59:00+00', atualizado_em = now()
where chave = 'rhino';

update concierge.avisos set
  disparo_em = '2026-09-15 20:58:00+00', atualizado_em = now()
where chave = 'doc_fisico';

update concierge.avisos set
  titulo = 'Seu ingresso está no app, no menu Ingresso!',
  subtitulo = 'Acesse e evite procurar na entrada',
  categoria = 'antes_de_ir', situacao = 'no-ar', arquivado_em = null,
  disparo_em = '2026-09-15 20:57:00+00', atualizado_em = now()
where chave = 'ingresso';

update concierge.avisos set
  titulo = 'Chegue cedo e siga para o Pavilhão 3',
  subtitulo = 'O credenciamento abre às 7h30 nos dois dias, no Pavilhão 3 do São Paulo Expo.',
  descricao = 'Acesse o app antes de sair de casa, o QR Code do ingresso está no app no menu Ingresso.',
  ver_no_app = 'ingresso', botao_ver_no_app = 'Onde está meu ingresso',
  disparo_em = '2026-09-15 20:56:00+00', atualizado_em = now()
where chave = 'credenciamento';

update concierge.avisos set
  titulo = 'Vai aos autógrafos dos Legends? Prefira levar o livro',
  subtitulo = 'A Livraria da Vila terá livros à venda no Mind Summit, mas não é garantida a disponibilidade de títulos ou idiomas.',
  descricao = E'Especialmente os livros importados poderão estar disponíveis em quantidades limitadas.\n\nSe você é Prime e quer garantir um exemplar para a assinatura de Jan-Emmanuel De Neve, Christina Maslach, Sonja Lyubomirsky ou Amy Edmondson, recomendamos levar seu próprio livro.',
  disparo_em = '2026-09-15 20:55:00+00', atualizado_em = now()
where chave = 'livros_autografos';
