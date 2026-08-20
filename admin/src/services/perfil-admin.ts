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
