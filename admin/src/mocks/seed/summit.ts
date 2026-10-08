import type { SessaoSummit2026 } from '@/contracts';

/* ============================================================
   PROGRAMAÇÃO DO SUMMIT 2026 — semente de demonstração
   ============================================================
   Sessões inventadas, com as colunas do banco, para os testes e o
   preview de cada versão (montado sem as variáveis do Supabase). Em
   produção a programação vem da `mindagent-summit`. */

function sessao(s: Partial<SessaoSummit2026> & Pick<SessaoSummit2026, 'id' | 'titulo' | 'dia' | 'inicio'>): SessaoSummit2026 {
  return {
    fim: null,
    tipo: null,
    espaco_id: null,
    espaco: null,
    palestrantes: [],
    precisa_reserva: false,
    vagas_total: null,
    vagas_disponiveis: null,
    atualizado_em: '2026-09-15T12:00:00+00:00',
    descricao: null,
    trilhas: [],
    ...s,
  };
}

export const sessoesSummit2026Semente: SessaoSummit2026[] = [
  sessao({
    id: 'ses_abertura',
    titulo: 'Abertura do Mind Summit',
    dia: '2026-09-16',
    inicio: '2026-09-16T12:00:00+00:00',
    fim: '2026-09-16T12:30:00+00:00',
    tipo: 'abertura',
    espaco_id: 'esp_palco',
    espaco: 'Palco Exemplo',
    palestrantes: ['Ana Exemplo'],
  }),
  sessao({
    id: 'ses_workshop',
    titulo: 'Workshop de bem-estar no trabalho',
    dia: '2026-09-16',
    inicio: '2026-09-16T14:00:00+00:00',
    fim: '2026-09-16T15:30:00+00:00',
    tipo: 'workshop',
    espaco_id: 'esp_sala',
    espaco: 'Sala Exemplo',
    palestrantes: ['Bruno Exemplo', 'Carla Exemplo'],
    precisa_reserva: true,
    vagas_total: 40,
    vagas_disponiveis: 12,
    descricao: 'Prática em grupo.',
  }),
  sessao({
    id: 'ses_almoco',
    titulo: 'Almoço',
    dia: '2026-09-17',
    inicio: '2026-09-17T15:00:00+00:00',
    fim: '2026-09-17T16:00:00+00:00',
    tipo: 'almoco',
  }),
];
