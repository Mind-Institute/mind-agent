import { z } from 'zod';

/* ============================================================
   MIND SUMMIT 2026 — a programação como está no banco
   ============================================================
   Uma linha de `summit_2026.sessions`, com as colunas e os nomes do banco
   (é o pedido: "conforme está no backend"), mais duas leituras para gente
   que o banco monta: `espaco` (o nome do local) e `palestrantes` (os
   nomes). Só leitura: a tela não escreve na programação.

   O schema confere o que a tela usa e deixa passar o resto das colunas
   (`passthrough`): coluna nova no banco aparece no detalhe da sessão sem
   precisar de versão nova do painel. */

export const sessaoSummit2026Schema = z
  .object({
    /* Sem estes a linha não abre nem se ordena. */
    id: z.string().min(1),
    titulo: z.string().min(1),
    dia: z.string().min(1),
    inicio: z.string().min(1),
    fim: z.string().nullable().default(null),
    tipo: z.string().nullable().default(null),
    espaco_id: z.string().nullable().default(null),
    espaco: z.string().nullable().default(null),
    palestrantes: z.array(z.string()).default([]),
    precisa_reserva: z.boolean().default(false),
    vagas_total: z.number().nullable().default(null),
    vagas_disponiveis: z.number().nullable().default(null),
    atualizado_em: z.string().nullable().default(null),
  })
  .passthrough();
export type SessaoSummit2026 = z.infer<typeof sessaoSummit2026Schema>;

/* Os dois dias do evento, para o filtro. */
export const DIAS_SUMMIT_2026 = [
  { valor: '2026-09-16', rotulo: '16/09 · quarta' },
  { valor: '2026-09-17', rotulo: '17/09 · quinta' },
];
