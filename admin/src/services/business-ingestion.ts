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

function baseUrl() {
  const base = import.meta.env.VITE_SUPABASE_URL?.trim().replace(/\/+$/, '') ?? '';
  if (!base.startsWith('http://') && !base.startsWith('https://')) {
    throw new Error('Ingestion Engine não configurado.');
  }
  return `${base}/functions/v1/mindagent-business-ingestion`;
}

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
