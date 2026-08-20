import type { Evento } from '@/contracts';
import { METADADOS_IMPORTACAO, SUMMIT } from './summit';

/* ============================================================
   EVENTO PADRÃO — Mind Summit 2026
   ============================================================
   O local NÃO é decidido aqui.

   `dados/summit.json` e o README do chat dizem "São Paulo Expo";
   material de divulgação do evento circula com "Transamérica Expo
   Center". São duas afirmações incompatíveis, e o painel não tem como
   saber qual é a verdadeira — escolher uma seria inventar dado, que é
   exatamente o que o agente não pode fazer.

   Então o campo `local` guarda o que veio do arquivo e
   `locaisCandidatos` guarda a divergência inteira, com a origem de
   cada versão. A tela mostra o alerta e pede revisão humana. */
export const eventoSemente: Evento = {
  id: 'evt_mind-summit-2026',
  nome: SUMMIT.evento.nome,
  slug: 'mind-summit-2026',
  dataInicio: SUMMIT.evento.dias[0] ?? '2026-09-16',
  dataFim: SUMMIT.evento.dias[1] ?? '2026-09-17',
  local: SUMMIT.evento.local,
  cidade: 'São Paulo',
  fusoHorario: 'America/Sao_Paulo',
  descricao:
    'O encontro anual da Mind sobre saúde mental, cultura e performance sustentável no trabalho. Dois dias de palestras, painéis, workshops e masterclasses.',
  regraReserva: SUMMIT.evento.regra_reserva,
  regraVagas: SUMMIT.evento.regra_vagas,
  ativo: true,
  locaisCandidatos: [
    { valor: 'São Paulo Expo', origem: 'dados/summit.json · README do chat' },
    { valor: 'Transamérica Expo Center', origem: 'material de divulgação do evento' },
  ],
  criadoEm: METADADOS_IMPORTACAO.IMPORTADO_EM,
  atualizadoEm: METADADOS_IMPORTACAO.IMPORTADO_EM,
  atualizadoPor: METADADOS_IMPORTACAO.IMPORTADO_POR,
};
