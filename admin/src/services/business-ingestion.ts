import { z } from 'zod';
import { erroDaResposta } from './http-erros';

const agentSchema = z.object({
  agent_key: z.string(),
  role_name: z.string(),
  stage: z.string(),
  execution_kind: z.enum(['code','llm']),
  model: z.string().nullable(),
  reasoning_effort: z.string().nullable(),
  prompt_version: z.number(),
  active: z.boolean(),
  instructions: z.string(),
});

const runSchema = z.object({
  id: z.string(),
  source_id: z.string(),
  protocol_version: z.string(),
  status: z.string(),
  current_stage: z.string().nullable(),
  started_at: z.string().nullable(),
  completed_at: z.string().nullable(),
  error: z.string().nullable(),
  metrics: z.record(z.unknown()).default({}),
  metadata: z.record(z.unknown()).default({}),
  created_at: z.string(),
  updated_at: z.string(),
  source: z.object({
    id: z.string(),
    title: z.string(),
    authors: z.array(z.string()).default([]),
    validation_status: z.string(),
  }).optional(),
});

const stageSchema = z.object({
  id: z.string(),
  run_id: z.string(),
  source_section_id: z.string().nullable(),
  stage: z.string(),
  agent_key: z.string().nullable(),
  status: z.string(),
  attempt: z.number(),
  model: z.string().nullable(),
  prompt_version: z.number().nullable(),
  output_summary: z.string().nullable(),
  metrics: z.record(z.unknown()).default({}),
  error: z.string().nullable(),
  started_at: z.string().nullable(),
  completed_at: z.string().nullable(),
  created_at: z.string(),
});

const findingSchema = z.object({
  id: z.string(),
  run_id: z.string(),
  finding_type: z.string(),
  severity: z.enum(['info','warning','critical']),
  entity_type: z.string().nullable(),
  entity_id: z.string().nullable(),
  description: z.string(),
  status: z.enum(['open','accepted','resolved','dismissed']),
  resolution: z.string().nullable(),
  created_at: z.string(),
});

const detailSchema = z.object({
  run: runSchema,
  stages: z.array(stageSchema),
  candidates: z.array(z.object({
    id: z.string(),
    provisional_name: z.string(),
    family: z.string(),
    object_type: z.string(),
    candidate_status: z.string(),
    source_section_id: z.string().nullable(),
    canonical_object_id: z.string().nullable(),
  })),
  findings: z.array(findingSchema),
  relationships: z.array(z.record(z.unknown())),
  job_links: z.array(z.record(z.unknown())),
});

export type IngestionAgent = z.infer<typeof agentSchema>;
export type IngestionRun = z.infer<typeof runSchema>;
export type IngestionRunDetail = z.infer<typeof detailSchema>;

type Opcoes = { token: string; sinal?: AbortSignal; fetchImpl?: typeof fetch };

function supabaseBase() {
  const base = import.meta.env.VITE_SUPABASE_URL?.trim().replace(/\/+$/, '') ?? '';
  if (!base.startsWith('http://') && !base.startsWith('https://')) throw new Error('Supabase não configurado.');
  return base;
}
function baseUrl() { return `${supabaseBase()}/functions/v1/mindagent-business-ingestion`; }
function sourceBaseUrl() { return `${supabaseBase()}/functions/v1/mindagent-business-source`; }

async function chamar(caminho: string, opcoes: Opcoes, init?: RequestInit) {
  const headers: Record<string,string> = {
    Authorization: `Bearer ${opcoes.token}`,
    Accept: 'application/json',
    ...(init?.body ? { 'Content-Type': 'application/json' } : {}),
  };
  const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (key) headers.apikey = key;
  const r = await (opcoes.fetchImpl ?? fetch)(`${baseUrl()}${caminho}`, {
    ...init,
    headers: { ...headers, ...(init?.headers ?? {}) },
    signal: opcoes.sinal,
  });
  if (!r.ok) throw await erroDaResposta(r);
  return r.json();
}

export async function buscarAgentesIngestao(opcoes: Opcoes): Promise<IngestionAgent[]> {
  const raw = z.object({ items: z.array(agentSchema) }).parse(await chamar('/admin/agents', opcoes));
  return raw.items;
}

export async function buscarRunsIngestao(opcoes: Opcoes): Promise<IngestionRun[]> {
  const raw = z.object({ items: z.array(runSchema) }).parse(await chamar('/admin/runs', opcoes));
  return raw.items;
}

export async function buscarRunIngestao(id: string, opcoes: Opcoes): Promise<IngestionRunDetail> {
  return detailSchema.parse(await chamar(`/admin/runs/${encodeURIComponent(id)}`, opcoes));
}


async function chamarSource(caminho: string, opcoes: Opcoes, init?: RequestInit) {
  const headers: Record<string,string> = {
    Authorization: `Bearer ${opcoes.token}`,
    Accept: 'application/json',
  };
  const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (key) headers.apikey = key;
  const r = await (opcoes.fetchImpl ?? fetch)(`${sourceBaseUrl()}${caminho}`, {
    ...init,
    headers: { ...headers, ...(init?.headers ?? {}) },
    signal: opcoes.sinal,
  });
  if (!r.ok) throw await erroDaResposta(r);
  return r.json();
}

export async function enviarPdfIngestao(
  arquivo: File,
  dados: { titulo?: string; autores?: string; ano?: string; isbn?: string },
  opcoes: Opcoes,
) {
  const form = new FormData();
  form.set('file', arquivo);
  if (dados.titulo) form.set('title', dados.titulo);
  if (dados.autores) form.set('authors', dados.autores);
  if (dados.ano) form.set('publication_year', dados.ano);
  if (dados.isbn) form.set('isbn', dados.isbn);
  return chamarSource('/admin/upload', opcoes, { method: 'POST', body: form });
}

export async function mapearFonte(runId: string, opcoes: Opcoes) {
  return chamarSource(`/admin/runs/${encodeURIComponent(runId)}/map`, opcoes, { method: 'POST' });
}

export async function gerarChunksFonte(runId: string, opcoes: Opcoes) {
  return chamarSource(`/admin/runs/${encodeURIComponent(runId)}/chunk`, opcoes, { method: 'POST' });
}

export async function abrirPdfOriginal(sourceId: string, opcoes: Opcoes) {
  const raw = z.object({ url: z.string().url() }).parse(
    await chamarSource(`/admin/sources/${encodeURIComponent(sourceId)}/file`, opcoes),
  );
  return raw.url;
}

export async function abrirPdfSecao(sectionId: string, opcoes: Opcoes) {
  const raw = z.object({ url: z.string().url() }).parse(
    await chamarSource(`/admin/sections/${encodeURIComponent(sectionId)}/file`, opcoes),
  );
  return raw.url;
}

export async function processarSecao(runId: string, sectionId: string, opcoes: Opcoes) {
  return chamar(`/admin/runs/${encodeURIComponent(runId)}/extract-section`, opcoes, {
    method: 'POST',
    body: JSON.stringify({ section_id: sectionId }),
  });
}

export async function finalizarIngestao(runId: string, opcoes: Opcoes) {
  return chamar(`/admin/runs/${encodeURIComponent(runId)}/finalize`, opcoes, { method: 'POST' });
}

export async function publicarIngestao(runId: string, opcoes: Opcoes) {
  return chamar(`/admin/runs/${encodeURIComponent(runId)}/publish`, opcoes, { method: 'POST' });
}
