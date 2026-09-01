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

export function momentoAtual() {
  let daUrl = null;
  try { daUrl = new URLSearchParams(location.search).get('momento'); } catch (e) { /* sem URL */ }
  if (daUrl && MOMENTOS.some((m) => m.id === daUrl)) return daUrl;
  try {
    const guardado = sessionStorage.getItem(CHAVE);
    if (guardado && MOMENTOS.some((m) => m.id === guardado)) return guardado;
  } catch (e) { /* aba anônima */ }
  return 'antes';   /* API: derivar da data do evento e da agenda da pessoa */
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
};

/* ---------- O conteúdo de cada momento ----------
   `blocos` é uma lista ordenada. Cada bloco tem um `tipo`, que é o nome
   do componente que sabe desenhá-lo. Acrescentar um card ao evento é
   acrescentar um item aqui — não é mexer no layout. */
export const CONTEUDO = {

  antes: {
    /* API: `faltam` sai da diferença entre hoje e a data do evento. */
    etiqueta: 'Concierge Mind, faltam 15 dias',
    saudacao: true,
    titulo: 'Seu Summit começa antes de chegar.',
    resumo: 'Conte o que você quer resolver e monte uma experiência que faça sentido para você.',
    blocos: [
      { tipo: 'destaque', ico: ICO.bussola, selo: 'Concierge Mind',
        pergunta: 'O que você quer levar do Summit?',
        cta: 'Receber recomendações', acao: 'chat:recomendacoes' },
      { tipo: 'linha', ico: ICO.grafico, titulo: 'Diagnóstico de maturidade',
        texto: 'Preencha agora, resultado após o Summit, 7 min', acao: 'diagnostico' },
      { tipo: 'secao', titulo: 'Avisos importantes', link: 'Ver todos' },
      { tipo: 'linha', ico: ICO.fone, titulo: 'Tradução simultânea',
        texto: 'Leve um documento físico para retirar o fone', acao: 'aviso' },
      { tipo: 'linha', ico: ICO.ingresso, titulo: 'Seu ingresso está aqui',
        texto: 'Acesse agora e evite procurar na entrada', acao: 'tour:qrcode' },
      { tipo: 'linha', ico: ICO.play, titulo: 'Tour rápido do app',
        texto: 'Como reservar e encontrar sua agenda, 1 min', acao: 'tour' },
    ],
  },

  'no-evento': {
    /* API: dia corrente do evento. */
    etiqueta: 'Hoje, 16 de setembro',
    saudacaoBomDia: true,
    /* API: minutos até a próxima sessão reservada. */
    resumo: 'Sua próxima experiência começa em 25 minutos.',
    blocos: [
      { tipo: 'proxima', hora: '09:15, Arena 1',
        titulo: 'Do benefício à transformação',
        texto: 'Adriana Drulla, abertura do Mind Summit', acao: 'tour:detalhe' },
      { tipo: 'destaque', variante: 'urgente', ico: ICO.ideia,
        pergunta: 'Registrar um insight',
        cta: 'Texto ou voz, conectamos à palestra', acao: 'insight' },
      { tipo: 'secao', titulo: 'Agora importa', link: 'Ver avisos' },
      { tipo: 'linha', ico: ICO.lugar, titulo: 'Masterclass mudou de sala',
        texto: 'Amy Edmondson, agora na Sala Estratégica.', acao: 'aviso' },
      { tipo: 'linha', ico: ICO.agenda, titulo: 'Ver minha agenda',
        texto: 'Reservas, horários e direções', acao: 'tour:minha-agenda' },
    ],
  },

  'entre-dias': {
    etiqueta: 'Dia 1 concluído',
    titulo: 'Feche o dia. Prepare o próximo.',
    resumo: 'Registre o que ficou com você e use isso para tornar o segundo dia mais relevante.',
    blocos: [
      { tipo: 'destaque', ico: ICO.ciclo, selo: 'Fechamento rápido',
        pergunta: 'O que ficou com você hoje?',
        cta: 'Registrar por voz ou texto, 2 min', acao: 'insight' },
      { tipo: 'linha', ico: ICO.relogio, titulo: 'Diagnóstico concluído',
        texto: 'Seu resultado será liberado depois do Summit', acao: 'diagnostico' },
      { tipo: 'secao', titulo: 'Seu Dia 2', link: 'Ver agenda' },
      { tipo: 'linha', ico: ICO.agenda, titulo: 'Preparar meu Dia 2',
        texto: 'Recomendações baseadas no diagnóstico e no Dia 1', acao: 'chat:recomendacoes' },
      { tipo: 'secao', titulo: 'Amanhã, não esqueça', link: 'Ver avisos' },
      { tipo: 'linha', ico: ICO.sino, titulo: 'Abertura às 9h',
        texto: 'Chegue às 8h30 para entrar sem pressa.', acao: 'aviso' },
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
        botao: 'Ver resultado e recomendações', acao: 'diagnostico' },
      { tipo: 'painel', etiqueta: 'Sem registros? Tudo bem.',
        titulo: 'Construa o plano a partir da memória',
        texto: 'A entrevista recupera situações, ideias e compromissos sem exigir anotações.',
        acao: 'entrevista' },
    ],
  },
};

export const PLACEHOLDER_CONCIERGE = 'Pergunte qualquer coisa ao Concierge';
