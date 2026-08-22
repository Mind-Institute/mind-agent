insert into templates (chave, texto, variaveis) values
('agente.nao_agendo',
 'Quem faz é você. Eu ainda não consigo agendar no seu lugar — te mostro o print da tela para você achar o botão e tocar.',
 '{}');

update templates
   set texto = 'Quem faz é você: eu ainda não consigo agendar no seu lugar. {{resumo}} Te mostro exatamente onde fica, no print da tela:'
 where chave = 'agente.ensina_caminho';

update ferramentas
   set descricao = 'Mostra à pessoa ONDE FICA alguma coisa no app: devolve o print da tela real com o botão destacado, o caminho em texto, o aviso de que QUEM EXECUTA É ELA (você não agenda, não reserva e não altera nada por ninguém) e, quando houver, a regra do evento que precisa ser dita junto — por exemplo, que as reservas caem 5 minutos antes. Use sempre que a pergunta for sobre onde algo está ou como fazer algo.'
 where nome = 'mostrar_como_fazer';

insert into config (chave, valor, descricao) values
('quem_executa',
 '{
    "agente_executa": false,
    "frase_chave": "agente.nao_agendo",
    "dizer_antes_do_print": true,
    "acoes_que_sao_da_pessoa": ["reservar","cancelar","favoritar","check-in","escanear","editar perfil"]
  }',
 'O agente ensina o caminho; a ação é sempre da pessoa. Ligar agente_executa exigiria escrita na Yazo e alguém assumindo o conflito de vaga.');

update prompts set ativo = false where nome = 'sistema';

insert into prompts (nome, versao, conteudo, ativo, notas)
select 'sistema', 6, conteudo || $$

Sobre quem executa:
Você não agenda, não reserva, não cancela e não altera nada no app por ninguém. Quem faz é a pessoa — e isso precisa ficar dito, não subentendido.

Sempre que a conversa chegar em uma ação (reservar, favoritar, check-in, escanear, trocar algo no perfil):
- Diga, antes de mostrar qualquer coisa, que você ainda não consegue fazer aquilo no lugar dela.
- Mostre o print da tela com o botão destacado e o caminho até ele, para ela achar sozinha.
- Diga junto a regra do evento que se aplica àquela ação, quando houver.

Nunca use "reservei", "agendei", "coloquei na sua agenda" nem qualquer construção que sugira que a ação já aconteceu. O que você entrega é o caminho; o toque é dela.$$,
       true, 'v6: quem executa é a pessoa — dito antes do print, nunca como ressalva.'
from prompts where nome = 'sistema' and versao = 5;
