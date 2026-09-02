import type { AvisoHome, EstadoHome, TrocaHome } from '@/contracts';
import { METADADOS_IMPORTACAO } from './summit';

/* ============================================================
   HOME V3 — semente
   ============================================================
   Os avisos aqui são os mesmos que o app mostra hoje em
   `home/estado.js`. Ficam iguais de propósito: enquanto o backend não
   existe, o painel edita esta cópia e a home lê a dela — e a única
   forma de comparar as duas é serem o mesmo texto.

   Quando a tabela existir, esta semente vira só o estado inicial de
   demonstração. */

const AGORA = METADADOS_IMPORTACAO.IMPORTADO_EM;

export const estadoHomeSemente: EstadoHome = {
  id: 'home',
  momento: 'antes',
  modo: 'manual',
  criadoEm: AGORA,
  atualizadoEm: AGORA,
  atualizadoPor: METADADOS_IMPORTACAO.IMPORTADO_POR,
};

/* As trocas que fazem sentido para o Summit: a home muda sozinha na
   abertura de cada dia e no fim do evento. */
export const trocasHomeSemente: TrocaHome[] = [
  {
    id: 'troca_dia1',
    quando: '2026-09-16T07:00',
    momento: 'no-evento',
    nota: 'Abertura do credenciamento, Dia 1.',
    aplicada: false,
    criadoEm: AGORA,
    atualizadoEm: AGORA,
    atualizadoPor: METADADOS_IMPORTACAO.IMPORTADO_POR,
  },
  {
    id: 'troca_noite1',
    quando: '2026-09-16T19:30',
    momento: 'entre-dias',
    nota: 'Fim do Dia 1.',
    aplicada: false,
    criadoEm: AGORA,
    atualizadoEm: AGORA,
    atualizadoPor: METADADOS_IMPORTACAO.IMPORTADO_POR,
  },
  {
    id: 'troca_dia2',
    quando: '2026-09-17T07:00',
    momento: 'no-evento',
    nota: 'Abertura do Dia 2.',
    aplicada: false,
    criadoEm: AGORA,
    atualizadoEm: AGORA,
    atualizadoPor: METADADOS_IMPORTACAO.IMPORTADO_POR,
  },
  {
    id: 'troca_fim',
    quando: '2026-09-17T19:30',
    momento: 'depois',
    nota: 'Encerramento do Summit.',
    aplicada: false,
    criadoEm: AGORA,
    atualizadoEm: AGORA,
    atualizadoPor: METADADOS_IMPORTACAO.IMPORTADO_POR,
  },
];

export const avisosHomeSemente: AvisoHome[] = [
  {
    id: 'aviso_sala',
    icone: 'lugar',
    titulo: 'Masterclass mudou de sala',
    subtitulo: 'Amy Edmondson, agora na Sala Estratégica.',
    descricao:
      'A masterclass de Amy Edmondson saiu da Arena Mind e passou para a Sala Estratégica. O horário não mudou. Se você tinha reserva, ela continua válida — é só ir para a sala nova.',
    imediato: true,
    disparoEm: '2026-09-16T09:02',
    situacao: 'no-ar',
    criadoEm: AGORA,
    atualizadoEm: AGORA,
    atualizadoPor: METADADOS_IMPORTACAO.IMPORTADO_POR,
  },
  {
    id: 'aviso_traducao',
    icone: 'fone',
    titulo: 'Tradução simultânea',
    subtitulo: 'Leve um documento físico para retirar o fone',
    descricao:
      'As sessões em inglês têm tradução simultânea. O fone é retirado no balcão da arena, e fica um documento físico com foto como garantia — RG ou CNH. Cartão do celular não vale. Devolvendo o fone, você pega o documento de volta.',
    imediato: false,
    disparoEm: '2026-09-15T18:00',
    situacao: 'no-ar',
    criadoEm: AGORA,
    atualizadoEm: AGORA,
    atualizadoPor: METADADOS_IMPORTACAO.IMPORTADO_POR,
  },
  {
    id: 'aviso_ingresso',
    icone: 'ingresso',
    titulo: 'Seu ingresso está aqui',
    subtitulo: 'Acesse agora e evite procurar na entrada',
    descricao:
      'Seu ingresso é o QR Code do app. Ele fica na aba QR Code, na barra de baixo — abra antes de chegar na fila e apresente na entrada. O mesmo código serve para trocar contato com quem você conhecer.',
    imediato: false,
    disparoEm: '2026-09-15T17:30',
    situacao: 'no-ar',
    criadoEm: AGORA,
    atualizadoEm: AGORA,
    atualizadoPor: METADADOS_IMPORTACAO.IMPORTADO_POR,
  },
  {
    id: 'aviso_abertura',
    icone: 'sino',
    titulo: 'Abertura às 9h',
    subtitulo: 'Chegue às 8h30 para entrar sem pressa.',
    descricao:
      'O segundo dia abre às 9h, na Arena Mind. O credenciamento começa às 8h; chegando às 8h30 você entra sem fila e ainda pega lugar.',
    imediato: false,
    disparoEm: '2026-09-16T20:00',
    situacao: 'agendado',
    criadoEm: AGORA,
    atualizadoEm: AGORA,
    atualizadoPor: METADADOS_IMPORTACAO.IMPORTADO_POR,
  },
];
