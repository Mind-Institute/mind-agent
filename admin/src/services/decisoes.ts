import { z } from 'zod';
import type { Decisao } from '@/lib/arquitetura';
import { erroDaResposta } from './http-erros';

const registro = z.object({
  codigo: z.string(), titulo: z.string(), texto: z.string(), significado: z.string(),
  decidida_em: z.string(), aprovada_por: z.string(),
  vigencia: z.enum(['vigente', 'substituida']), substituida_por: z.string().nullable(),
  situacao: z.enum(['aplicada', 'parcial', 'so-documento']).nullable(),
  leitura: z.string().nullable(), medido_em: z.string().nullable(),
  lugares: z.array(z.object({
    camada: z.enum(['documentos', 'banco', 'funcoes', 'edge', 'contratos', 'painel']),
    onde: z.string(), oQueFaz: z.string(),
  })).nullable(),
});
export const respostaDecisoes = z.object({ fonte: z.literal('arquitetura.decisoes'), itens: z.array(registro) });
const data = (valor: string) => valor.split('-').reverse().join('/');
export function paraDecisoes(corpo: unknown): Decisao[] {
  return respostaDecisoes.parse(corpo).itens.map((d) => ({
    id: d.codigo, titulo: d.titulo, texto: d.texto, significado: d.significado,
    data: data(d.decidida_em), aprovadaPor: d.aprovada_por,
    vigencia: d.vigencia, substituidaPor: d.substituida_por,
    situacao: d.situacao, leitura: d.leitura ?? 'Implementação ainda não aferida.',
    lugares: d.lugares ?? [], medidoEm: d.medido_em ? data(d.medido_em) : null,
  }));
}

export async function buscarDecisoes({ token, sinal, baseUrl, fetchImpl = fetch }: {
  token: string; sinal?: AbortSignal; baseUrl?: string; fetchImpl?: typeof fetch;
}): Promise<Decisao[]> {
  const url = baseUrl ?? `${import.meta.env.VITE_SUPABASE_URL?.trim().replace(/\/+$/, '') ?? ''}/functions/v1/mindagent-home`;
  if (!url.startsWith('https://') && !url.startsWith('http://')) throw new Error('Leitura das decisões não configurada.');
  const headers: Record<string, string> = { Authorization: `Bearer ${token}`, Accept: 'application/json' };
  const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (key) headers.apikey = key;
  const r = await fetchImpl(`${url.replace(/\/+$/, '')}/admin/decisoes`, { headers, signal: sinal });
  if (!r.ok) throw await erroDaResposta(r);
  return paraDecisoes(await r.json());
}
