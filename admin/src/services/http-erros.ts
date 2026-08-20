import { AdminApiError, type CodigoErroAdmin } from '@/contracts';

/* ============================================================
   TRADUÇÃO DE ERRO HTTP
   ============================================================
   Um lugar só, usado pelo `HttpAdminDataProvider` e pela busca de
   `/admin/me`. As duas coisas falam com a mesma Edge Function e
   precisam produzir o mesmo `AdminApiError` — senão a tela de erro
   acerta em um caminho e erra no outro.

   A Edge Function do Mind Agent já responde no formato do contrato:

       { "codigo": "sem_permissao", "mensagem": "Sessão ausente." }

   Quando o corpo traz `codigo`, ele manda. O mapa por status é a rede
   de segurança para respostas que não seguem o formato (um 502 do
   gateway, por exemplo). */

const CODIGO_POR_STATUS: Record<number, CodigoErroAdmin> = {
  400: 'validacao',
  401: 'sessao_expirada',
  403: 'sem_permissao',
  404: 'nao_encontrado',
  409: 'conflito',
  422: 'validacao',
  429: 'indisponivel',
  500: 'desconhecido',
  502: 'indisponivel',
  503: 'indisponivel',
  504: 'indisponivel',
};

const CODIGOS_VALIDOS: CodigoErroAdmin[] = [
  'nao_encontrado',
  'sem_permissao',
  'sessao_expirada',
  'credenciais_invalidas',
  'conflito',
  'validacao',
  'rede',
  'indisponivel',
  'desconhecido',
];

function ehCodigoConhecido(valor: unknown): valor is CodigoErroAdmin {
  return typeof valor === 'string' && (CODIGOS_VALIDOS as string[]).includes(valor);
}

/**
 * Converte uma resposta com falha no `AdminApiError` correspondente.
 *
 * `401` vira `sessao_expirada` e `403` vira `sem_permissao` — a
 * diferença importa: no primeiro caso a pessoa precisa entrar de novo,
 * no segundo ela já entrou e simplesmente não tem o papel.
 */
export async function erroDaResposta(resposta: Response): Promise<AdminApiError> {
  const requestId = resposta.headers.get('x-request-id') ?? undefined;
  let codigo: CodigoErroAdmin = CODIGO_POR_STATUS[resposta.status] ?? 'desconhecido';
  let mensagem = `A API respondeu ${resposta.status}.`;
  let detalhes: unknown;

  try {
    const corpo = (await resposta.json()) as {
      codigo?: unknown;
      mensagem?: unknown;
      message?: unknown;
      detalhes?: unknown;
    };
    if (ehCodigoConhecido(corpo?.codigo)) codigo = corpo.codigo;
    if (typeof corpo?.mensagem === 'string') mensagem = corpo.mensagem;
    else if (typeof corpo?.message === 'string') mensagem = corpo.message;
    detalhes = corpo?.detalhes;
  } catch {
    /* Resposta sem JSON: a mensagem por status já basta. */
  }

  /* O backend usa `sem_permissao` para os dois casos de sessão; o
     status separa "não entrou" de "entrou e não pode". */
  if (resposta.status === 401 && codigo === 'sem_permissao') codigo = 'sessao_expirada';

  return new AdminApiError(codigo, mensagem, { detalhes, requestId });
}

/** Falha de rede — a requisição nem chegou a receber resposta. */
export function erroDeRede(causa: unknown): AdminApiError {
  return new AdminApiError('rede', 'Não foi possível falar com a API administrativa.', {
    detalhes: causa instanceof Error ? causa.message : String(causa),
  });
}
