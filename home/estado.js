/* ============================================================
   HOME V3 — o conteúdo, separado do layout
   ============================================================
   Tudo que a home mostra mora aqui, e só aqui. Os componentes de
   `cards.js` não guardam texto nenhum: recebem estes objetos e desenham.
   É essa separação que faz a troca pelo backend ser uma troca de fonte,
   não uma reescrita de tela.

   O evento tem quatro momentos, e a home é outra em cada um. Hoje o
   momento vem de um seletor; amanhã virá da data do evento cruzada com a
   agenda do participante — por isso `momentoAtual()` é a única porta.

   MOCK: todo o conteúdo abaixo é demonstrativo. Onde entra dado real
   está marcado com `/* API: ... *\/`. */

/** Os quatro momentos, na ordem em que acontecem. */
export const MOMENTOS = [
  { id: 'antes',      rotulo: 'Antes' },
  { id: 'no-evento',  rotulo: 'No evento' },
  { id: 'entre-dias', rotulo: 'Entre dias' },
  { id: 'depois',     rotulo: 'Depois' },
];

/* Enquanto não há regra de data, o momento é escolhido à mão e guardado
   na aba. `?momento=` existe para abrir direto num deles. */
const CHAVE = 'mindagent:v1:home-momento';

/* `?momento=` semeia o valor e sai da URL — não fica mandando para
   sempre, senão o seletor não conseguiria trocar de momento depois. */
(function semearPelaUrl() {
  try {
    const url = new URL(location.href);
    const pedido = url.searchParams.get('momento');
    if (!pedido || !MOMENTOS.some((m) => m.id === pedido)) return;
    sessionStorage.setItem(CHAVE, pedido);
    url.searchParams.delete('momento');
    history.replaceState(null, '', url.pathname + url.search + url.hash);
  } catch (e) { /* sem URL ou aba anônima */ }
})();

/* O que o painel administrativo deixou no ar. Chega pelo bootstrap e é
   a verdade em produção — mas perde para o seletor local de propósito:
   ferramenta de desenvolvimento que não vence o servidor não serve para
   testar as outras três telas. */
let momentoServidor = null;

/** Recebe o momento do payload do bootstrap. Ignora o que não conhece. */
export function definirMomentoDoServidor(id) {
  if (id && MOMENTOS.some((m) => m.id === id)) momentoServidor = id;
}

/** Existe alguém mandando de fora? Quem pergunta é a contagem regressiva:
 *  com o painel no comando, não é ela que vira a tela. */
export function momentoDoServidor() {
  return momentoServidor;
}

export function momentoAtual() {
  try {
    const guardado = sessionStorage.getItem(CHAVE);
    if (guardado && MOMENTOS.some((m) => m.id === guardado)) return guardado;
  } catch (e) { /* aba anônima */ }
  return momentoServidor || 'antes';
}

export function definirMomento(id) {
  try { sessionStorage.setItem(CHAVE, id); } catch (e) { /* aba anônima */ }
}

/* ---------- Ícones ----------
   Traço, não preenchimento: é a linguagem que o app já usa. */
export const ICO = {
  bussola: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M15.5 8.5l-2 5-5 2 2-5z"/></svg>',
  grafico: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/></svg>',
  fone:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 14v-2a8 8 0 0 1 16 0v2"/><rect x="2" y="14" width="4.5" height="6" rx="2"/><rect x="17.5" y="14" width="4.5" height="6" rx="2"/></svg>',
  ingresso:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 8V6a1 1 0 0 1 1-1h16a1 1 0 0 1 1 1v2a2.5 2.5 0 0 0 0 5v3a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-3a2.5 2.5 0 0 0 0-5z"/><path d="M9.5 5v14" stroke-dasharray="2 2.5"/></svg>',
  play:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M10.2 8.6l5 3.4-5 3.4z"/></svg>',
  lugar:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21s7-5.6 7-11a7 7 0 1 0-14 0c0 5.4 7 11 7 11z"/><circle cx="12" cy="10" r="2.6"/></svg>',
  agenda:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4.5" width="18" height="16" rx="4"/><path d="M8 2.5v4M16 2.5v4M3 10h18"/></svg>',
  ideia:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18h6M10 21.5h4"/><path d="M12 2.5a6.5 6.5 0 0 1 3.8 11.8c-.5.4-.8 1-.8 1.7H9c0-.7-.3-1.3-.8-1.7A6.5 6.5 0 0 1 12 2.5z"/></svg>',
  relogio: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5.2l3.2 2"/></svg>',
  sino:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M18 9a6 6 0 1 0-12 0c0 5-2 6.5-2 6.5h16S18 14 18 9z"/><path d="M10.5 19a2 2 0 0 0 3 0"/></svg>',
  ciclo:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20.5 12a8.5 8.5 0 1 1-2.9-6.4"/><path d="M20.5 4v4.5H16"/></svg>',
  megafone:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 9v6h3l9 4.5V4.5L7 9z"/><path d="M19 9.5a4 4 0 0 1 0 5"/><path d="M7 15v4.5"/></svg>',
  alerta:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3.8 2.8 19.5h18.4z"/><path d="M12 9.5v4M12 16.6v.1"/></svg>',
  estrela: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m12 3.5 2.6 5.4 5.9.8-4.3 4.1 1 5.9-5.2-2.8-5.2 2.8 1-5.9L3.5 9.7l5.9-.8z"/></svg>',
  /* Os quatro dos Atalhos, copiados do handoff de 02/09 — mesmos glifos,
     mesmo traço 1.6. `qr` e `pin` existem separados de `ingresso` e
     `lugar` porque ali o desenho é outro: o QR do atalho é o código
     inteiro, não o bilhete; o pin é o alfinete cheio, não o balão. */
  qr:      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="3.5" y="3.5" width="7" height="7" rx="1.2"/><rect x="13.5" y="3.5" width="7" height="7" rx="1.2"/><rect x="3.5" y="13.5" width="7" height="7" rx="1.2"/><path d="M6.5 6.5h1M16.5 6.5h1M6.5 16.5h1M13.5 13.5h3M20.5 13.5v3M13.5 17v3.5M17 20.5h3.5M17 17h.01"/></svg>',
  agendaBloco: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="18" height="16" rx="2.5"/><path d="M3 10h18M8 3v4M16 3v4"/><rect x="9" y="13" width="6" height="5" rx="1" fill="currentColor" stroke="none"/></svg>',
  brilho:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9z"/><path d="M18.5 16.5l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7z"/></svg>',
  pin:     '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21s7-5.2 7-11a7 7 0 10-14 0c0 5.8 7 11 7 11z"/><circle cx="12" cy="10" r="2.6"/></svg>',
};

/* ---------- Categorias de aviso ----------
   O handoff pinta a caixa do ícone e o ponto do chip pela categoria. As
   três cores já eram tokens da marca — o design não trouxe paleta nova,
   usou a que o app tem.

   `ingressos` fica no verde e SEM ponto no chip, como no desenho: é a
   categoria de serviço, e um quarto ponto colorido só somaria ruído.

   Categoria desconhecida cai no verde em vez de sumir: um aviso é para
   ser lido, e é melhor lê-lo sem a cor certa do que não vê-lo. */
/* OS RÓTULOS SÃO OS TÍTULOS QUE A ADRIANA ESCREVEU ao mandar os avisos —
   ela os agrupou em três, e os três são exatamente estes chips. A ordem
   também é a dela: antes, reservas, durante/depois. */
export const CATEGORIAS_AVISO = [
  { id: 'antes_de_ir', rotulo: 'Antes de ir ao Summit',     ponto: true },
  { id: 'reservas',    rotulo: 'Reservas e agenda',         ponto: true },
  { id: 'no_evento',   rotulo: 'Durante e depois',          ponto: true },
  { id: 'ingressos',   rotulo: 'Ingressos',                 ponto: false },
];

export function categoriaValida(id) {
  return CATEGORIAS_AVISO.some((c) => c.id === id) ? id : 'antes_de_ir';
}

/* Os nomes que o painel administrativo usa, e o desenho de cada um aqui.
   A lista é fechada dos dois lados: ícone livre viraria emoji. */
const ICO_POR_NOME = {
  megafone: ICO.megafone, lugar: ICO.lugar, relogio: ICO.relogio,
  sino: ICO.sino, ingresso: ICO.ingresso, fone: ICO.fone,
  agenda: ICO.agenda, alerta: ICO.alerta, estrela: ICO.estrela,
};

/* ---------- Avisos do evento ----------
   Um lugar só: os cards da home mostram os primeiros, e "Ver todos" abre
   a lista inteira. Cada aviso tem a mensagem que aparece ao abrir.

   `em` é o horário de disparo em ISO, e é por ele que a lista é ordenada:
   guardar a data legível como texto ("16 set, 09:02") daria uma ordem
   alfabética, que não é ordem nenhuma. O rótulo sai daí, formatado.

   MOCK: API: virá da tabela de avisos do Summit. */
/* A LISTA EMBUTIDA É O QUE APARECE SE A REDE FALHAR, e por isso tem que
   ser a mesma do banco — não a de ontem. São os sete que a Adriana definiu
   em 02/09, com as mesmas categorias e a mesma ordem.

   `mensagem` repete `resumo` porque cada aviso veio com um parágrafo só;
   `leituraDeAviso` sabe disso e não mostra o mesmo texto duas vezes. */
const CRUS = [
  { id: 'reserve_exp', ico: ICO.estrela, cat: 'reservas', em: '2026-09-15T18:00', situacao: 'no-ar',
    titulo: 'Reserve agora as experiências que você não quer perder',
    resumo: 'Arena LinkedIn, Arena Sextante, Workshops e Masterclasses têm lugares limitados.',
    mensagem: 'Faça o agendamento no app e confirme em Minha Agenda. No dia, sua vaga ficará garantida somente até 5 minutos antes do início.' },

  { id: 'doc_fisico', ico: ICO.fone, cat: 'antes_de_ir', em: '2026-09-15T17:50', situacao: 'no-ar',
    titulo: 'Leve um documento oficial físico com foto',
    resumo: 'Para retirar o fone de tradução simultânea, você precisará deixar um documento oficial físico com foto, que ficará retido durante o uso do equipamento.',
    mensagem: 'Ao devolver o fone, seu documento será devolvido imediatamente. Documentos digitais ou apresentados pelo celular não serão aceitos.\n\nSepare o documento com antecedência para não esquecer.' },

  { id: 'credenciamento', ico: ICO.relogio, cat: 'antes_de_ir', em: '2026-09-15T17:40', situacao: 'no-ar',
    titulo: 'Chegue cedo e siga para o Pavilhão 3',
    resumo: 'O credenciamento abre às 7h30 nos dois dias, no Pavilhão 3 do São Paulo Expo.',
    mensagem: 'Acesse o app antes de sair de casa e deixe o QR Code do ingresso pronto para agilizar sua entrada.' },

  { id: 'rhino', ico: ICO.estrela, cat: 'antes_de_ir', em: '2026-09-15T17:30', situacao: 'no-ar',
    titulo: 'Use o benefício da Rhino para chegar ao Summit',
    resumo: 'Use o cupom MINDSUMMIT no app da Rhino. Quem nunca utilizou o serviço recebe R$ 200 de desconto na primeira corrida.',
    mensagem: 'Em trajetos de até 10 km, o valor é fixo de R$ 49. Acima de 10 km, o valor mínimo é de R$ 149.\n\nO cupom fica ativo até 31 de dezembro e, depois do cadastro no app, deve ser utilizado em até 30 dias.' },

  { id: 'tour_summit', ico: ICO.lugar, cat: 'antes_de_ir', em: '2026-09-15T17:20', situacao: 'no-ar',
    titulo: 'Veja como o Summit funciona antes de chegar',
    resumo: 'O evento acontece em diferentes arenas, salas e espaços de experiência.',
    mensagem: 'Assista ao tour do Summit para conhecer a estrutura e se orientar melhor durante os dois dias.',
    verNoApp: 'https://www.youtube.com/watch?v=Lw2lqkwxzMg', botaoVerNoApp: 'Assistir ao tour do Summit' },

  { id: 'acesso_app', ico: ICO.ingresso, cat: 'antes_de_ir', em: '2026-09-15T17:00', situacao: 'no-ar',
    titulo: 'Faça o acesso ao app com antecedência',
    resumo: 'No app você encontra o QR Code do ingresso, a programação completa e as experiências que reservou.',
    mensagem: 'Acesse antes de sair de casa para evitar problemas no credenciamento e chegar com sua agenda organizada.' },

  { id: 'pavilhao_3', ico: ICO.lugar, cat: 'antes_de_ir', em: '2026-09-15T16:40', situacao: 'no-ar',
    titulo: 'O Mind Summit é no Pavilhão 3',
    resumo: 'Ao chegar ao São Paulo Expo, siga as indicações para o Pavilhão 3.',
    mensagem: 'O credenciamento e o acesso ao Mind Summit serão realizados nesse pavilhão.' },

  { id: 'chegada_expo', ico: ICO.lugar, cat: 'antes_de_ir', em: '2026-09-15T16:20', situacao: 'no-ar',
    titulo: 'Como chegar ao São Paulo Expo',
    resumo: 'O São Paulo Expo fica a 900 metros da estação Jabaquara, da Linha 1, Azul, a cerca de 10 minutos do Aeroporto de Congonhas e no km 1,5 da Rodovia dos Imigrantes.',
    mensagem: 'O estacionamento é coberto e tem acesso ao pavilhão por uma passarela.' },

  { id: 'confira_reserva', ico: ICO.agenda, cat: 'reservas', em: '2026-09-15T15:50', situacao: 'no-ar',
    titulo: 'Confira se a reserva foi concluída',
    resumo: 'Depois de reservar, abra Minha Agenda. Se uma experiência que exige agendamento não aparecer ali, ela não está reservada.',
    mensagem: 'A aba Programação mostra todos os conteúdos do Summit. Minha Agenda mostra somente as experiências que você efetivamente agendou.' },

  { id: 'chegue_5min', ico: ICO.relogio, cat: 'reservas', em: '2026-09-15T15:40', situacao: 'no-ar',
    titulo: 'Sua reserva vale até 5 minutos antes',
    resumo: 'A reserva protege sua vaga até 5 minutos antes do início da experiência. Depois desse horário, os lugares ainda não ocupados poderão ser liberados para a fila de espera.',
    mensagem: 'Mesmo com reserva, chegar depois desse prazo não mantém a garantia de entrada.' },

  { id: 'fila_espera', ico: ICO.alerta, cat: 'reservas', em: '2026-09-15T15:30', situacao: 'no-ar',
    titulo: 'Não conseguiu reservar? Entre na fila de espera',
    resumo: 'Os lugares que não tiverem sido ocupados até 5 minutos antes do início poderão ser liberados para a fila de espera, conforme a disponibilidade.',
    mensagem: 'A fila de espera não altera os acessos do ingresso: Mind não tem acesso a Workshops ou Masterclasses, VIP pode tentar vagas remanescentes em Workshops e Prime pode tentar vagas remanescentes em Workshops e Masterclasses.' },

  { id: 'acessos_ingresso', ico: ICO.ingresso, cat: 'reservas', em: '2026-09-15T15:20', situacao: 'no-ar',
    titulo: 'Confira os acessos do seu ingresso',
    resumo: 'Participantes VIP e Prime têm acesso aos Workshops.',
    mensagem: 'As Masterclasses são exclusivas para participantes Prime.' },

  { id: 'conflitos_agenda', ico: ICO.lugar, cat: 'reservas', em: '2026-09-15T15:10', situacao: 'no-ar',
    titulo: 'Evite conflitos na sua agenda',
    resumo: 'Antes de reservar, confira os horários e considere o deslocamento entre arenas e salas.',
    mensagem: 'Se duas experiências acontecerem ao mesmo tempo, você precisará escolher qual delas quer acompanhar. Veja o mapa do evento para entender os deslocamentos necessários e onde acontecerá cada experiência.',
    verNoApp: 'mapa', botaoVerNoApp: 'Ver o mapa do evento' },

  { id: 'ajuda_reservar', ico: ICO.megafone, cat: 'reservas', em: '2026-09-15T15:00', situacao: 'no-ar',
    titulo: 'Precisa de ajuda para reservar?',
    resumo: 'Peça ajuda ao Concierge.',
    mensagem: 'Ele pode explicar como funciona a reserva e abrir o tutorial passo a passo para você.',
    verNoApp: 'chat', botaoVerNoApp: 'Falar com o Concierge' },

  { id: 'consulte_app', ico: ICO.agenda, cat: 'no_evento', em: '2026-09-15T14:50', situacao: 'no-ar',
    titulo: 'Consulte o app ao longo do evento',
    resumo: 'Use Programação para consultar todos os conteúdos e Minha Agenda para conferir suas reservas.',
    mensagem: 'Antes de seguir para uma experiência, confirme o horário e o local no app.',
    verNoApp: 'reserva', botaoVerNoApp: 'Ver como consultar e reservar' },

  { id: 'certificados', ico: ICO.estrela, cat: 'no_evento', em: '2026-09-15T14:40', situacao: 'no-ar',
    titulo: 'Certificados',
    resumo: 'O certificado geral será enviado a quem tiver participado do Summit, a partir de 30 dias após o evento, para o e-mail associado ao ingresso.',
    mensagem: 'Workshops e Masterclasses terão certificados específicos, condicionados ao registro de entrada na experiência.' },

  { id: 'gravacoes', ico: ICO.sino, cat: 'no_evento', em: '2026-09-15T14:30', situacao: 'no-ar',
    titulo: 'Gravações',
    resumo: 'O ingresso Mind não inclui as gravações.',
    mensagem: 'Participantes VIP receberão as gravações das Arenas Mind, LinkedIn e Sextante, com liberação prevista em até 45 dias.\n\nParticipantes Prime também receberão as quatro Masterclasses, que poderão levar até 60 dias devido à tradução e à legendagem.\n\nCada gravação ficará disponível durante 90 dias, contados a partir de sua liberação na plataforma do Mind Institute.' },
];

const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

/** "16 set, 09:02" a partir do ISO. Montado em partes, não por `new
 *  Date(iso)`: string sem fuso é lida como UTC em alguns navegadores. */
function quandoLegivel(em) {
  const [data, hora] = em.split('T');
  const [, mes, dia] = data.split('-');
  return Number(dia) + ' ' + MESES[Number(mes) - 1] + ', ' + hora;
}

/** Agora no formato de `em`, montado em partes para a comparação de
 *  texto valer: '2026-09-16T09:02' < '2026-09-16T20:00'. */
function agoraTexto() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) +
         'T' + p(d.getHours()) + ':' + p(d.getMinutes());
}

/* O que está em circulação, mais recente em cima.

   `no-ar` está na rua independente do relógio — é o disparo imediato e
   é o que o painel liga na mão. `agendado` entra sozinho quando o
   horário chega, sem depender de rotina no banco: quem lê aplica a
   regra. `rascunho` e `encerrado` não aparecem. */
function ordenar(lista) {
  const agora = agoraTexto();
  return lista
    .filter((a) => a.situacao === 'no-ar' ||
                   (a.situacao === 'agendado' && String(a.em) <= agora))
    .map((a) => ({ ...a, quando: quandoLegivel(a.em) }))
    .sort((a, b) => b.em.localeCompare(a.em));
}

/* A lista viva. Começa nos avisos embutidos e é trocada pela do banco
   quando o payload traz `avisos` — inclusive quando vem vazia, que é
   uma resposta legítima: nenhum aviso em circulação. Sem a chave no
   payload, a origem continua sendo esta daqui. */
export let AVISOS = ordenar(CRUS);

/** Recebe os avisos do bootstrap, no formato do banco. */
export function definirAvisos(doBanco) {
  if (!Array.isArray(doBanco)) return;
  AVISOS = ordenar(doBanco.map((a) => ({
    id: a.id,
    ico: ICO_POR_NOME[a.icone] || ICO.megafone,
    /* Aviso gravado antes da coluna existir chega sem categoria, e cai no
       verde. Ler `categoria` e `cat` porque a porta pública devolve o nome
       da coluna e os avisos embutidos usam a forma curta. */
    cat: categoriaValida(a.categoria || a.cat),
    em: a.em,
    situacao: a.situacao,
    titulo: a.titulo,
    resumo: a.resumo || '',
    mensagem: a.mensagem || '',
    verNoApp: a.verNoApp || undefined,
    botaoVerNoApp: a.botaoVerNoApp || undefined,
  })));
}

/* ---------- O conteúdo de cada momento ----------
   `blocos` é uma lista ordenada. Cada bloco tem um `tipo`, que é o nome
   do componente que sabe desenhá-lo. Acrescentar um card ao evento é
   acrescentar um item aqui — não é mexer no layout. */
export const CONTEUDO = {

  antes: {
    /* O número não mora aqui: é relógio, e `app.js` o alimenta a cada
       segundo a partir da data real do evento. */
    etiqueta: 'Mind Summit',
    contagem: true,
    /* O nome entra DENTRO do título, não numa linha de saudação acima —
       é assim no handoff. Sem nome, `heroSaudacao` maiusculiza a
       primeira letra e a frase segue de pé sozinha. */
    tituloComNome: true,
    /* A QUEBRA E O PONTO SÃO DECISÃO DE COPY, e vêm escritos assim.
       "começa agora" fica na própria linha, como a Adriana escreveu; o
       ponto final saiu, que é como ela escreveu também. A quebra chega
       como `\n` e não como `<br>`: conteúdo aqui é texto, não marcação —
       quem honra a linha é `white-space: pre-line` no `.v3-titulo`. */
    titulo: 'seu Mind Summit\ncomeça agora',
    resumo: 'Conte o que te trouxe aqui e monte uma experiência que faça sentido para você',
    decorado: true,
    blocos: [
      /* Este card é a porta da jornada personalizada. O texto diz o que
         acontece do outro lado — "receber recomendações" não dizia. */
      { tipo: 'destaque', marca: true, selo: 'Concierge Mind',
        pergunta: 'Monte sua jornada no Summit',
        texto: 'Conte seus interesses e receba uma programação personalizada de palestras e experiências.',
        cta: 'Montar minha jornada',
        micro: '~1 min',
        acao: 'jornada' },
      /* "Como usar o app", e não "Atalhos importantes". Os quatro não
         levam para dentro da função — todos abrem uma demonstração sobre
         a captura da tela real. Chamá-los de atalho prometia chegar lá;
         o que eles entregam é aprender onde fica. */
      { tipo: 'secao', titulo: 'Como usar o app' },
      /* Os quatro levam ao tour na tela correspondente do app do Summit.
         Não é atalho de mentira: o tour mostra a captura real e ensina
         onde tocar, que é o que este app sabe fazer sobre telas que são
         do hospedeiro. `tour` sozinho é a prática de reserva inteira —
         a mesma que o card coral de antes abria. */
      { tipo: 'atalhos', itens: [
        { ico: ICO.qr, titulo: 'Meu ingresso',
          texto: 'Acesse seu QR Code', acao: 'tour:qrcode' },
        { ico: ICO.agendaBloco, titulo: 'Minha Agenda',
          texto: 'Veja suas reservas', acao: 'tour:minha-agenda' },
        { ico: ICO.brilho, titulo: 'Reserve suas experiências',
          texto: 'Garanta suas escolhas agora', acao: 'tour' },
      ] },
      { tipo: 'secao', titulo: 'Avisos importantes', link: 'Ver todos', acao: 'avisos' },
      /* Os mais recentes em circulação, não avisos escolhidos a dedo:
         quem dispara um aviso no painel precisa vê-lo aparecer aqui. */
      /* Quatro, não três: os três atalhos passaram a caber numa linha só e
         a linha economizada dá exatamente a altura de mais um aviso. Foi o
         motivo do pedido — encolher os atalhos para caber mais recado. */
      /* CINCO, e são os cinco que a Adriana condensou para o card. Quem
         escolhe é a ordem de disparo: estes cinco são os mais recentes,
         e o resto continua atrás do "Ver todos". */
      { tipo: 'avisos', quantos: 5 },
    ],
  },

  'no-evento': {
    /* API: dia corrente do evento. */
    etiqueta: 'Hoje, 16 de setembro',
    /* Aqui o cumprimento é o título, e ele muda com a hora. */
    comoTitulo: true,
    /* O resumo e o card da próxima saem da grade, não daqui: quem calcula
       é `proximaExperiencia()`, que cruza horário com afinidade. */
    blocos: [
      /* Sem ação por enquanto: ele informa qual é a próxima sessão, e
         ainda não há para onde levar que valha o toque. */
      { tipo: 'proxima', daGrade: true },
      /* `daSessao`: depois que a pessoa diz em que palestra está, a home
         mostra o nome dela como selo — o registro ganha endereço. */
      { tipo: 'destaque', variante: 'urgente', ico: ICO.ideia, daSessao: true,
        pergunta: 'Registrar um insight',
        cta: 'Anote o que a palestra de agora te trouxe',
        ctaComSessao: 'Anotar mais sobre esta palestra', acao: 'insight' },
      { tipo: 'secao', titulo: 'Avisos importantes', link: 'Ver todos', acao: 'avisos' },
      { tipo: 'avisos', quantos: 2 },
    ],
  },

  'entre-dias': {
    etiqueta: 'Dia 1 concluído',
    titulo: 'Feche o dia. Prepare o próximo.',
    resumo: 'Registre o que ficou com você e use isso para tornar o segundo dia mais relevante.',
    blocos: [
      { tipo: 'destaque', ico: ICO.ciclo, selo: 'Fechamento rápido',
        pergunta: 'O que ficou com você hoje?',
        cta: 'Anote o que ficou do dia, em 2 min', acao: 'insight' },
      { tipo: 'linha', ico: ICO.relogio, titulo: 'Diagnóstico concluído',
        texto: 'Seu resultado será liberado depois do Summit', acao: 'em-breve:resultado' },
      { tipo: 'secao', titulo: 'Seu Dia 2', link: 'Ver agenda' },
      { tipo: 'linha', ico: ICO.agenda, titulo: 'Preparar meu Dia 2',
        texto: 'Recomendações baseadas no diagnóstico e no Dia 1', acao: 'chat:recomendacoes' },
      { tipo: 'secao', titulo: 'Amanhã, não esqueça', link: 'Ver avisos', acao: 'avisos' },
      { tipo: 'avisos', quantos: 1 },
    ],
  },

  depois: {
    etiqueta: 'Sua jornada continua',
    titulo: 'Transforme ideias em decisões.',
    resumo: 'Em 8 minutos, o Concierge ajuda você a escolher prioridades e construir um plano possível.',
    blocos: [
      { tipo: 'destaque', ico: ICO.bussola, selo: 'Plano pós-Summit',
        pergunta: 'O que você quer mudar primeiro?',
        cta: 'Começar entrevista guiada', acao: 'entrevista' },
      /* API: `feito` é a etapa concluída da entrevista. */
      { tipo: 'progresso', etapas: 4, feito: 1 },
      { tipo: 'painel', etiqueta: '12 insights registrados',
        titulo: 'Rever o que mais chamou sua atenção',
        texto: 'Seus registros já estão conectados às palestras e agrupados por tema.',
        botao: 'Explorar meus insights', acao: 'insights' },
      { tipo: 'painel', etiqueta: 'Seu diagnóstico',
        titulo: 'Maturidade em desenvolvimento',
        texto: 'Use as lacunas identificadas para escolher prioridades e ações para a empresa.',
        botao: 'Ver resultado e recomendações', acao: 'em-breve:resultado' },
      { tipo: 'painel', etiqueta: 'Sem registros? Tudo bem.',
        titulo: 'Construa o plano a partir da memória',
        texto: 'A entrevista recupera situações, ideias e compromissos sem exigir anotações.',
        acao: 'entrevista' },
    ],
  },
};

export const PLACEHOLDER_CONCIERGE = 'Pergunte qualquer coisa ao Concierge';
