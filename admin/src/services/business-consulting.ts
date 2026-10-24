import { z } from 'zod';
import { erroDaResposta } from './http-erros';

/* Business Consulting Knowledge — o conhecimento de business (livros ingeridos em
   `business_strategy`) que o agente consultor interno usa para aconselhar a Adriana e o
   time. Leitura pela mindagent-home, que chama `mind_admin_read_business_consulting`. */

const livroSchema = z.object({
  id: z.string(),
  titulo: z.string(),
  autores: z.array(z.string()).nullable(),
  tipo: z.string().nullable(),
  ano: z.number().nullable(),
  acesso: z.string().nullable(),
  status: z.string().nullable(),
  paginas: z.number().nullable(),
  secoes: z.number(),
  secoes_processadas: z.number(),
  objetos: z.number(),
  criado_em: z.string(),
  atualizado_em: z.string(),
});

const objetoSchema = z.object({
  id: z.string(),
  livro_id: z.string(),
  familia: z.string(),
  tipo: z.string(),
  nome: z.string(),
  resumo: z.string().nullable(),
  escopo: z.string().nullable(),
  topicos: z.array(z.string()).nullable(),
  confianca: z.number().nullable(),
  status: z.string().nullable(),
  capitulo: z.string().nullable(),
  secao_id: z.string().nullable().optional(),
});

const secaoSchema = z.object({
  id: z.string(),
  livro_id: z.string(),
  pai_id: z.string().nullable(),
  tipo: z.string().nullable(),
  numero: z.string().nullable(),
  titulo: z.string(),
  ordem: z.number().nullable(),
  pagina_inicio: z.number().nullable(),
  pagina_fim: z.number().nullable(),
});

const respostaSchema = z.object({
  fonte: z.literal('business_strategy'),
  livros: z.array(livroSchema),
  objetos: z.array(objetoSchema),
  secoes: z.array(secaoSchema),
  relacoes: z.array(z.object({ de: z.string(), para: z.string(), tipo: z.string() })),
  jobs: z.array(z.object({
    id: z.string(),
    slug: z.string(),
    name: z.string(),
    description: z.string(),
    userQuestions: z.array(z.string()).default([]),
    expectedOutput: z.string().nullable(),
    status: z.string(),
    area: z.object({
      id: z.string(),
      slug: z.string(),
      name: z.string(),
      description: z.string(),
      sortOrder: z.number(),
    }),
    coverage: z.object({
      knowledgeCount: z.number(),
      sourceCount: z.number(),
    }),
    relatedJobs: z.array(z.object({
      direction: z.enum(['incoming', 'outgoing']),
      relationshipType: z.string(),
      rationale: z.string().nullable(),
      jobId: z.string(),
      jobSlug: z.string(),
      jobName: z.string(),
    })).default([]),
    knowledge: z.array(z.object({
      id: z.string(),
      name: z.string(),
      family: z.string(),
      objectType: z.string(),
      summary: z.string().nullable(),
      scope: z.string().nullable(),
      topics: z.array(z.string()).default([]),
      knowledgeRole: z.string(),
      relevance: z.number(),
      rationale: z.string(),
      source: z.object({
        id: z.string(),
        title: z.string(),
        authors: z.array(z.string()).default([]),
        sourceType: z.string().nullable(),
        publicationYear: z.number().nullable(),
        sourceFileRef: z.string().nullable(),
      }),
      groundings: z.array(z.object({
        id: z.string(),
        role: z.string().nullable(),
        locator: z.string().nullable(),
        pageStart: z.number().nullable(),
        pageEnd: z.number().nullable(),
        summary: z.string().nullable(),
        section: z.object({
          id: z.string(),
          number: z.string().nullable(),
          title: z.string().nullable(),
          type: z.string().nullable(),
        }).nullable(),
      })).default([]),
      relations: z.array(z.object({
        direction: z.enum(['incoming', 'outgoing']),
        relationshipType: z.string(),
        summary: z.string().nullable(),
        objectId: z.string(),
        objectName: z.string(),
        objectType: z.string().nullable(),
      })).default([]),
    })).default([]),
  })).default([]),
  totais: z.object({ livros: z.number(), objetos: z.number(), citacoes: z.number(), relacoes: z.number(), jobs: z.number().default(0) }),
});

const detalheSchema = z.object({
  fonte: z.literal('business_strategy'),
  objeto: objetoSchema.extend({
    livro: z.string(),
    aliases: z.array(z.string()).nullable(),
    condicoes: z.unknown(),
    limitacoes: z.unknown(),
    status_epistemico: z.string().nullable(),
    portabilidade: z.string().nullable(),
    dominios: z.array(z.string()).nullable(),
    niveis: z.array(z.string()).nullable(),
    detalhes: z.unknown(),
  }),
  citacoes: z.array(z.object({
    papel: z.string().nullable(),
    localizador: z.string().nullable(),
    pagina_inicio: z.number().nullable(),
    pagina_fim: z.number().nullable(),
    resumo: z.string().nullable(),
    capitulo: z.string().nullable(),
  })),
  relacoes: z.array(z.object({
    direcao: z.enum(['saida', 'entrada']),
    tipo: z.string(),
    outro_id: z.string(),
    outro_nome: z.string(),
    resumo: z.string().nullable(),
    confianca: z.number().nullable(),
  })),
});

export type LivroConsulting = z.infer<typeof livroSchema>;
export type ObjetoConsulting = z.infer<typeof objetoSchema>;
export type SecaoConsulting = z.infer<typeof secaoSchema>;
export type JobConsulting = z.infer<typeof respostaSchema>['jobs'][number];
export type BusinessConsulting = z.infer<typeof respostaSchema>;
export type DetalheConsulting = z.infer<typeof detalheSchema>;

type Opcoes = { token: string; sinal?: AbortSignal; baseUrl?: string; fetchImpl?: typeof fetch };

async function ler(caminho: string, { token, sinal, baseUrl, fetchImpl = fetch }: Opcoes) {
  const url = baseUrl
    ?? `${import.meta.env.VITE_SUPABASE_URL?.trim().replace(/\/+$/, '') ?? ''}/functions/v1/mindagent-home`;
  if (!url.startsWith('https://') && !url.startsWith('http://')) {
    throw new Error('Leitura do Business Consulting Knowledge não configurada.');
  }
  const headers: Record<string, string> = { Authorization: `Bearer ${token}`, Accept: 'application/json' };
  const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (key) headers.apikey = key;
  const r = await fetchImpl(`${url.replace(/\/+$/, '')}/admin/business-consulting${caminho}`, { headers, signal: sinal });
  if (!r.ok) throw await erroDaResposta(r);
  return r.json();
}

export async function buscarBusinessConsulting(opcoes: Opcoes): Promise<BusinessConsulting> {
  return respostaSchema.parse(await ler('', opcoes));
}

export async function buscarObjetoConsulting(id: string, opcoes: Opcoes): Promise<DetalheConsulting> {
  return detalheSchema.parse(await ler(`/${encodeURIComponent(id)}`, opcoes));
}
