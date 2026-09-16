/* ============================================================
   Avaliação do dia — o cliente do relatório
   ============================================================
   Cliente próprio, pequeno e SOMENTE LEITURA. Não passa pelo
   `AdminDataProvider` de propósito: aquele contrato é de recurso com
   CRUD (`list`, `get`, `create`, `update`, `archive`), e a pesquisa não
   tem nenhuma escrita administrativa — resposta enviada não se edita,
   inclusive pelo painel. Encaixá-la lá exigiria mexer em `resources.ts`,
   no mock e nas tabelas do provedor híbrido para descrever operações
   que não existem.

   As MESMAS regras do `HttpAdminDataProvider` valem aqui:
   - o navegador nunca fala com o Postgres, só com a Edge Function;
   - `service_role` não existe neste código;
   - o token vai no header `Authorization`, nunca na URL;
   - nada de `console.log` de token, corpo ou dado pessoal.
*/

/** A raiz da Edge Function, ou `null` quando a pesquisa não foi configurada. */
export function baseDaAvaliacao(): string | null {
  const base = import.meta.env.VITE_AVALIACAO_API_BASE_URL?.trim();
  return base ? base.replace(/\/+$/, '') : null;
}

export interface FiltroDoRelatorio {
  dia?: string | null;
  experiencia?: string | null;
  sessaoId?: string | null;
}

export interface Distribuicao {
  '0': number; '1': number; '2': number; '3': number; '4': number; '5': number;
}

export interface NotaGeral {
  amostra: number;
  media: number | null;
  distribuicao: Distribuicao;
  percentual45: number | null;
}

export interface Relatorio {
  evento: { slug: string; nome: string; dias: string[]; fuso: string };
  filtro: { dia: string | null; experiencia: string | null };
  kpis: {
    respondentes: number;
    porExperiencia: { mind: number; vip: number; prime: number };
    expectativas: NotaGeral;
    programacao: NotaGeral;
  };
  avaliacoesDeAtividades: number;
  porAtividade: LinhaDeAtividade[];
}

export interface LinhaDeAtividade {
  id: string;
  titulo: string;
  dia: string;
  inicio: string;
  espaco: string | null;
  tipo: string | null;
  ingressos: string[];
  avaliacoes: number;
  /** `null` quando ninguém avaliou. NUNCA zero por ausência. */
  media: number | null;
  distribuicao: Distribuicao;
}

export interface Resposta {
  id: string;
  dia: string;
  enviadoEm: string;
  experiencia: string;
  profissao: string;
  expectativas: string;
  notaExpectativas: number;
  notaProgramacao: number;
  maisGostou: string | null;
  melhorar: string | null;
  comentario: string | null;
  atividadesAvaliadas: number;
}

export interface PaginaDeRespostas {
  total: number;
  pagina: number;
  porPagina: number;
  itens: Resposta[];
}

export class ErroDaAvaliacao extends Error {
  constructor(readonly codigo: string, mensagem: string) {
    super(mensagem);
    this.name = 'ErroDaAvaliacao';
  }
}

async function pedir<T>(
  caminho: string,
  parametros: Record<string, string | number | null | undefined>,
  obterToken: () => Promise<string | null>,
): Promise<T> {
  const base = baseDaAvaliacao();
  if (!base) {
    throw new ErroDaAvaliacao(
      'indisponivel',
      'VITE_AVALIACAO_API_BASE_URL não está definida. Sem ela o painel não inventa endereço.',
    );
  }

  const url = new URL(`${base}/admin/${caminho}`);
  for (const [chave, valor] of Object.entries(parametros)) {
    if (valor === undefined || valor === null || valor === '' || valor === 'todos') continue;
    url.searchParams.set(chave, String(valor));
  }

  const token = await obterToken();
  const cabecalhos: Record<string, string> = { Accept: 'application/json' };
  const chave = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (chave) cabecalhos.apikey = chave;
  if (token) cabecalhos.Authorization = `Bearer ${token}`;

  let resposta: Response;
  try {
    resposta = await fetch(url.toString(), { headers: cabecalhos, cache: 'no-store' });
  } catch {
    throw new ErroDaAvaliacao('rede', 'A API da avaliação não respondeu.');
  }

  const corpo = (await resposta.json().catch(() => null)) as
    | { codigo?: string; mensagem?: string }
    | null;

  if (!resposta.ok) {
    throw new ErroDaAvaliacao(
      corpo?.codigo ?? 'desconhecido',
      corpo?.mensagem ?? 'Não foi possível carregar o relatório.',
    );
  }
  return corpo as T;
}

/* CONFERÊNCIA DE CONTRATO. Um relatório que renderiza vazio porque o
   formato mudou é pior que uma tela de erro: ele parece que funcionou.
   É a mesma decisão do `conferirResumo` do provedor híbrido. */
function conferirRelatorio(dado: unknown): Relatorio {
  const r = dado as Partial<Relatorio> | null;
  if (!r || typeof r !== 'object' || !r.kpis || !Array.isArray(r.porAtividade)) {
    throw new ErroDaAvaliacao(
      'desconhecido',
      'A resposta do relatório não segue o contrato do painel.',
    );
  }
  return r as Relatorio;
}

export function lerRelatorio(filtro: FiltroDoRelatorio, obterToken: () => Promise<string | null>) {
  return pedir<unknown>(
    'relatorio',
    { dia: filtro.dia, experiencia: filtro.experiencia },
    obterToken,
  ).then(conferirRelatorio);
}

export function lerRespostas(
  filtro: FiltroDoRelatorio & { pagina?: number; porPagina?: number },
  obterToken: () => Promise<string | null>,
) {
  return pedir<PaginaDeRespostas>(
    'respostas',
    {
      dia: filtro.dia,
      experiencia: filtro.experiencia,
      sessao_id: filtro.sessaoId,
      pagina: filtro.pagina ?? 1,
      porPagina: filtro.porPagina ?? 50,
    },
    obterToken,
  );
}
