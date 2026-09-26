import {
  AdminApiError,
  perfilAdminSchema,
  type PerfilAdmin,
} from '@/contracts';
import { erroDaResposta, erroDeRede } from './http-erros';

/* ============================================================
   GET /admin/me — de onde vêm papel e permissões
   ============================================================
   Esta é a única fonte de autorização do painel.

   O que NÃO é fonte, e nunca vai ser:
   - `user_metadata` e `app_metadata` do JWT. O primeiro é editável
     pelo próprio usuário; confiar nele é entregar o painel.
   - Qualquer coisa guardada no navegador entre sessões.

   A Edge Function valida o JWT, lê o papel de uma tabela do banco e
   responde. Se ela recusar, o painel não abre — não existe caminho
   alternativo, e é assim que tem que ser. */

export interface OpcoesPerfil {
  baseUrl: string;
  token: string;
  chavePublicavel?: string | null;
  fetchImpl?: typeof fetch;
  sinal?: AbortSignal;
}

/** Aceita o perfil na raiz ou embrulhado, que é variação comum de API. */
function desembrulhar(corpo: unknown): unknown {
  if (!corpo || typeof corpo !== 'object') return corpo;
  const objeto = corpo as Record<string, unknown>;
  for (const chave of ['usuario', 'perfil', 'data']) {
    const interno = objeto[chave];
    if (interno && typeof interno === 'object' && 'papel' in (interno as object)) return interno;
  }
  return corpo;
}

/* ============================================================
   POST /admin/vincular — o primeiro login com Google
   ============================================================
   Admin do sistema entra na lista pelo Mind ID, antes de ter conta de
   login. No primeiro login com o Google da Mind, `/admin/me` ainda não
   reconhece a conta; esta chamada pede ao banco que a ligue à pessoa.
   Quem decide é o banco (`mind_admin_vincular_login`): conta Google,
   e-mail @joinmind.com.br, pessoa única, acesso ativo e marca de equipe.
   Recusa volta como `sem_permissao`, com a frase que a tela mostra. */

/** Explícito, ou `<VITE_SUPABASE_URL>/functions/v1/mindagent-acesso`; `null` sem nenhum dos dois. */
export function enderecoDoAcesso(
  explicito = import.meta.env.VITE_ACESSO_API_BASE_URL,
  supabaseUrl = import.meta.env.VITE_SUPABASE_URL,
): string | null {
  const direto = explicito?.trim();
  if (direto) return direto;
  const base = supabaseUrl?.trim().replace(/\/+$/, '');
  return base ? `${base}/functions/v1/mindagent-acesso` : null;
}

export interface RespostaVinculo {
  vinculado: boolean;
  papel: string | null;
  nome: string | null;
}

export async function vincularLoginAdmin(opcoes: OpcoesPerfil): Promise<RespostaVinculo> {
  const base = opcoes.baseUrl.trim().replace(/\/+$/, '');
  const buscar = opcoes.fetchImpl ?? globalThis.fetch.bind(globalThis);
  const cabecalhos: Record<string, string> = {
    Accept: 'application/json',
    Authorization: `Bearer ${opcoes.token}`,
  };
  if (opcoes.chavePublicavel) cabecalhos.apikey = opcoes.chavePublicavel;

  let resposta: Response;
  try {
    resposta = await buscar(`${base}/admin/vincular`, {
      method: 'POST',
      headers: cabecalhos,
      signal: opcoes.sinal,
    });
  } catch (erro) {
    if (erro instanceof DOMException && erro.name === 'AbortError') throw erro;
    throw erroDeRede(erro);
  }
  if (!resposta.ok) throw await erroDaResposta(resposta);

  const corpo = (await resposta.json().catch(() => ({}))) as Partial<RespostaVinculo>;
  return {
    vinculado: Boolean(corpo.vinculado),
    papel: typeof corpo.papel === 'string' ? corpo.papel : null,
    nome: typeof corpo.nome === 'string' ? corpo.nome : null,
  };
}

export async function buscarPerfilAdmin(opcoes: OpcoesPerfil): Promise<PerfilAdmin> {
  const base = opcoes.baseUrl.trim().replace(/\/+$/, '');
  if (!base) {
    throw new AdminApiError(
      'indisponivel',
      'VITE_ADMIN_API_BASE_URL não está definida — sem ela não há de onde ler o papel.',
    );
  }

  const buscar = opcoes.fetchImpl ?? globalThis.fetch.bind(globalThis);
  const cabecalhos: Record<string, string> = {
    Accept: 'application/json',
    /* O token vai no header. Nunca na URL: endereço vaza em histórico,
       log de proxy e print de tela. */
    Authorization: `Bearer ${opcoes.token}`,
  };
  if (opcoes.chavePublicavel) cabecalhos.apikey = opcoes.chavePublicavel;

  let resposta: Response;
  try {
    resposta = await buscar(`${base}/admin/me`, {
      headers: cabecalhos,
      signal: opcoes.sinal,
    });
  } catch (erro) {
    if (erro instanceof DOMException && erro.name === 'AbortError') throw erro;
    throw erroDeRede(erro);
  }

  if (!resposta.ok) throw await erroDaResposta(resposta);

  let corpo: unknown;
  try {
    corpo = await resposta.json();
  } catch {
    throw new AdminApiError('desconhecido', 'A resposta de /admin/me não é JSON.');
  }

  const analise = perfilAdminSchema.safeParse(desembrulhar(corpo));
  if (!analise.success) {
    /* Papel irreconhecível é motivo para NÃO abrir o painel. Adivinhar
       um papel padrão aqui seria conceder acesso por conta própria. */
    throw new AdminApiError(
      'sem_permissao',
      'A resposta de /admin/me não traz um papel reconhecido pelo painel.',
      { detalhes: analise.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`) },
    );
  }

  const perfil = analise.data;
  return {
    id: perfil.id ?? null,
    email: perfil.email ?? null,
    nome: perfil.nome?.trim() || perfil.email || 'Usuário',
    papel: perfil.papel,
    permissoes: perfil.permissoes ?? null,
  };
}
