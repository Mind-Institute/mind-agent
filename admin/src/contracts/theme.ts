import { z } from 'zod';

/* ============================================================
   TEMA
   ============================================================
   Os dez temas do Summit. Somente leitura no painel: a API expõe
   apenas `GET /admin/themes`.

   A API devolve `id` igual ao `codigo` — os dois são exigidos, e nenhum
   dos dois é preenchido pelo painel. Sem `codigo` o filtro de tema não
   casa com nada, e um tema sem rótulo aparece como caixa vazia na
   seleção múltipla: nos dois casos é melhor falhar dizendo que o
   contrato mudou. */
export const temaSchema = z.object({
  id: z.string().min(1),
  codigo: z.string().min(1),
  rotulo: z.string().min(1),
});

export type Tema = z.infer<typeof temaSchema>;
