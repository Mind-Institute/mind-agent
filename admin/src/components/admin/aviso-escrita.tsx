import { AlertTriangle } from 'lucide-react';
import { codigoDoErro, ehErroAdmin } from '@/contracts';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';

const TITULOS: Record<string, string> = {
  validacao: 'A API recusou estes dados',
  sem_permissao: 'Seu papel não permite esta alteração',
  nao_encontrado: 'O registro não existe mais',
  indisponivel: 'A API administrativa está indisponível',
  rede: 'Não foi possível falar com a API',
  sessao_expirada: 'Sua sessão expirou',
  desconhecido: 'Não foi possível salvar',
};

/**
 * Erro de escrita que não é conflito.
 *
 * Com a API real no caminho, 422 e 403 são rotina — e o formulário
 * precisa dizer o que aconteceu em vez de simplesmente não salvar. A
 * mensagem vem do backend; o `requestId` fica visível porque é por ele
 * que se acha a requisição no log.
 */
export function AvisoErroEscrita({ erro }: { erro: unknown }) {
  if (!erro) return null;

  const codigo = codigoDoErro(erro);
  const mensagem =
    erro instanceof Error ? erro.message : 'A API não explicou o motivo da recusa.';
  const requestId = ehErroAdmin(erro) ? erro.requestId : undefined;
  const detalhes = ehErroAdmin(erro) ? erro.detalhes : undefined;

  return (
    <Alert variant="erro" data-testid="erro-escrita">
      <AlertTriangle />
      <AlertTitle>{TITULOS[codigo] ?? TITULOS.desconhecido}</AlertTitle>
      <AlertDescription>
        <p>{mensagem}</p>
        {Array.isArray(detalhes) && detalhes.length > 0 ? (
          <ul className="mt-1 list-disc pl-4 text-xs">
            {detalhes.map((d) => (
              <li key={String(d)}>{String(d)}</li>
            ))}
          </ul>
        ) : null}
        {requestId ? (
          <p className="mt-1 font-mono text-xs opacity-70">requisição {requestId}</p>
        ) : null}
        <p className="mt-1 text-xs">O formulário continua com o que você editou.</p>
      </AlertDescription>
    </Alert>
  );
}
