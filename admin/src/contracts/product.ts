import { z } from 'zod';
import { registroBaseSchema } from './common';

/* ============================================================
   CATÁLOGO — `catalogo.produtos`
   ============================================================
   Um registro por produto do Mind. É a origem de tudo: CRM,
   conhecimento e agentes referenciam estes códigos.

   `tipo` e `vertical` seguem os CHECKs da tabela. No REGISTRO eles são
   `string`, não enum: valor novo no banco aparece cru na tela em vez de
   travar a listagem — a mesma regra de `sessions.tipo`. */

export const TIPOS_PRODUTO = ['empresa', 'evento', 'formacao', 'assinatura', 'conteudo', 'outro'] as const;
export type TipoProduto = (typeof TIPOS_PRODUTO)[number];
export const ROTULO_TIPO_PRODUTO: Record<TipoProduto, string> = {
  empresa: 'Empresa',
  evento: 'Evento',
  formacao: 'Formação',
  assinatura: 'Assinatura',
  conteudo: 'Conteúdo',
  outro: 'Outro',
};

export const VERTICAIS_PRODUTO = ['summit', 'institute', 'eventos', 'dash', 'outro'] as const;
export type VerticalProduto = (typeof VERTICAIS_PRODUTO)[number];
export const ROTULO_VERTICAL_PRODUTO: Record<VerticalProduto, string> = {
  summit: 'Summit',
  institute: 'Institute',
  eventos: 'Eventos',
  dash: 'Dash',
  outro: 'Outro',
};

export const produtoCatalogoSchema = registroBaseSchema.extend({
  /* Identidade: sem estes o registro não abre, e preencher por conta
     própria esconderia a quebra de contrato. */
  codigo: z.string().min(1),
  nome: z.string().min(1),
  tipo: z.string().min(1),
  /* Obrigatórios também: são o estado que o catálogo existe para mostrar.
     Chutar `false` faria o painel dizer que um produto não vende quando
     talvez venda. */
  ativo: z.boolean(),
  vende: z.boolean(),
  /* Vazio é estado legítimo no catálogo — metade dos produtos não tem
     vertical, descrição ou janela. O banco guarda `null`. */
  vertical: z.string().nullable().default(null),
  categoria: z.string().nullable().default(null),
  descricaoCurta: z.string().nullable().default(null),
  descricao: z.string().nullable().default(null),
  vendeDe: z.string().nullable().default(null),
  vendeAte: z.string().nullable().default(null),
  comecaEm: z.string().nullable().default(null),
  encerraEm: z.string().nullable().default(null),
  periodo: z.string().nullable().default(null),
  schemaDados: z.string().nullable().default(null),
  pipelinesHubspot: z.array(z.string()).default([]),
});
export type ProdutoCatalogo = z.infer<typeof produtoCatalogoSchema>;

const DATA = /^\d{4}-\d{2}-\d{2}$/;
/* O `<input type="datetime-local" step="1">` devolve com ou sem segundos —
   e há navegador que acrescenta milissegundos (`23:59:59.000`). */
const DATA_HORA = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,3})?)?$/;

/* O formulário trabalha com texto: vazio é `''` aqui e vira `null` no
   payload (ver `src/lib/catalogo.ts`). `codigo` e `schemaDados` não estão
   aqui porque não se editam — a tela só os mostra. */
export const produtoCatalogoFormSchema = z
  .object({
    nome: z.string().trim().min(2, 'Informe o nome do produto.'),
    tipo: z.string().min(1, 'Escolha o tipo.'),
    vertical: z.string(),
    categoria: z.string().max(120, 'Use até 120 caracteres.'),
    descricaoCurta: z.string().max(500, 'Use até 500 caracteres.'),
    descricao: z.string().max(5000, 'Use até 5.000 caracteres.'),
    periodo: z.string().max(200, 'Use até 200 caracteres.'),
    ativo: z.boolean(),
    vende: z.boolean(),
    vendeDe: z.string().regex(DATA_HORA, 'Informe data e hora.').or(z.literal('')),
    vendeAte: z.string().regex(DATA_HORA, 'Informe data e hora.').or(z.literal('')),
    comecaEm: z.string().regex(DATA, 'Use o formato AAAA-MM-DD.').or(z.literal('')),
    encerraEm: z.string().regex(DATA, 'Use o formato AAAA-MM-DD.').or(z.literal('')),
    pipelinesHubspot: z.array(z.string()),
  })
  .superRefine((v, ctx) => {
    if (v.vendeDe && v.vendeAte && v.vendeAte < v.vendeDe) {
      ctx.addIssue({ code: 'custom', path: ['vendeAte'], message: 'O fim da venda não pode ser antes do início.' });
    }
    if (v.comecaEm && v.encerraEm && v.encerraEm < v.comecaEm) {
      ctx.addIssue({ code: 'custom', path: ['encerraEm'], message: 'O fim não pode ser antes do começo.' });
    }
  });
export type ProdutoCatalogoForm = z.infer<typeof produtoCatalogoFormSchema>;
