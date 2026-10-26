import { z } from 'zod';
import { erroDaResposta } from './http-erros';

const objetoSchema = z.object({
  nome: z.string(),
  tipo: z.string(),
  comentario: z.string().nullable().optional(),
});

const registroSchema = z.object({
  schema_name: z.string(),
  categoria: z.string(),
  funcao: z.string(),
  fronteira: z.string().nullable(),
  tipo: z.string(),
  objetos: z.array(objetoSchema),
  auditado_em: z.string(),
  observacoes: z.string().nullable(),
  atualizado_em: z.string(),
});

const respostaSchema = z.object({
  fonte: z.literal('arquitetura.mapa_schemas'),
  itens: z.array(registroSchema),
});

export type ObjetoDoSchema = z.infer<typeof objetoSchema>;
export type MapaSchema = z.infer<typeof registroSchema>;

export async function buscarMapaSchemas({
  token,
  sinal,
  baseUrl,
  fetchImpl = fetch,
}: {
  token: string;
  sinal?: AbortSignal;
  baseUrl?: string;
  fetchImpl?: typeof fetch;
}): Promise<MapaSchema[]> {
  const url = baseUrl
    ?? `${import.meta.env.VITE_SUPABASE_URL?.trim().replace(/\/+$/, '') ?? ''}/functions/v1/mindagent-home`;
  if (!url.startsWith('https://') && !url.startsWith('http://')) {
    throw new Error('Leitura do mapa de schemas não configurada.');
  }
  const headers: Record<string, string> = {
    Authorization: `Bearer ${token}`,
    Accept: 'application/json',
  };
  const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (key) headers.apikey = key;

  const r = await fetchImpl(`${url.replace(/\/+$/, '')}/admin/mapa-schemas`, {
    headers,
    signal: sinal,
  });
  if (!r.ok) throw await erroDaResposta(r);
  return respostaSchema.parse(await r.json()).itens;
}
