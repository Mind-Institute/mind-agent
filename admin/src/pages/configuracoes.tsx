import { AlertTriangle, Database, KeyRound, Server } from 'lucide-react';
import { useAdminData } from '@/services/provider-context';
import { useSessao } from '@/hooks/use-sessao';
import { ROTULO_PAPEL } from '@/contracts';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { EstadoSemPermissao } from '@/components/admin/estados';
import { motivoDaRecusa } from '@/lib/permissions';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';

/** Só o nome da variável e se ela está preenchida. Valor nunca é exibido. */
function LinhaVariavel({ nome, valor }: { nome: string; valor: string | undefined }) {
  const preenchida = Boolean(valor?.trim());
  return (
    <li className="flex items-center justify-between gap-3 border-b py-2 last:border-0">
      <code className="font-mono text-xs">{nome}</code>
      <Badge variant={preenchida ? 'sucesso' : 'neutro'}>
        {preenchida ? 'definida' : 'vazia'}
      </Badge>
    </li>
  );
}

export function PaginaConfiguracoes() {
  const provedor = useAdminData();
  const sessao = useSessao();

  if (!sessao.pode('configurar')) {
    return (
      <div className="space-y-5">
        <CabecalhoPagina titulo="Configurações" />
        <EstadoSemPermissao motivo={motivoDaRecusa(sessao.papel, 'configurar')} />
      </div>
    );
  }

  return (
    <div className="space-y-5">
      <CabecalhoPagina
        titulo="Configurações"
        descricao="De onde o painel lê os dados hoje, o que já está preparado e o que ainda não existe."
      />

      <Alert variant="atencao">
        <AlertTriangle />
        <AlertTitle>Nenhuma credencial administrativa vive no navegador</AlertTitle>
        <AlertDescription>
          <code className="font-mono">service_role</code> e secret key não existem neste código — nem
          em variável, nem em header. Toda variável <code className="font-mono">VITE_*</code> é
          embutida no bundle e é pública por definição; por isso só cabem aqui a URL da API e a chave
          publicável. Consulta administrativa direta ao Postgres, a partir do navegador, também não
          acontece: quem fala com o banco é a Edge Function.
        </AlertDescription>
      </Alert>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Database className="size-4" /> Origem dos dados
            </CardTitle>
            <CardDescription>Qual implementação do AdminDataProvider está ativa.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3 text-sm">
            <p>
              Implementação:{' '}
              <Badge
                variant={
                  provedor.modo === 'mock'
                    ? 'destructive'
                    : provedor.modo === 'hybrid'
                      ? 'atencao'
                      : 'sucesso'
                }
              >
                {provedor.modo === 'mock'
                  ? 'MockAdminDataProvider'
                  : provedor.modo === 'hybrid'
                    ? 'HybridAdminDataProvider'
                    : 'HttpAdminDataProvider'}
              </Badge>
            </p>

            {provedor.modo === 'mock' ? (
              <p className="text-muted-foreground">
                Os dados são simulados e vivem na memória do navegador. Evento, temas, sessões e
                pessoas vêm de <code className="font-mono">../dados/summit.json</code>; espaços,
                rotas, estandes, ofertas, conteúdo, documentos, conversas e auditoria são mocks
                pequenos. Recarregar a página desfaz qualquer alteração.
              </p>
            ) : provedor.modo === 'hybrid' ? (
              <div className="space-y-2 text-muted-foreground">
                <p>
                  <strong className="text-foreground">Dashboard real:</strong> a visão geral vem de{' '}
                  <code className="font-mono">GET /admin/dashboard</code>, com o token da sessão no
                  header <code className="font-mono">Authorization</code>.
                </p>
                <p>
                  <strong className="text-foreground">Cadastros em demonstração:</strong> todo o
                  resto continua no banco em memória. Nenhuma escrita chega ao backend nesta etapa —
                  salvar, publicar, arquivar e reindexar mexem só nesta aba.
                </p>
              </div>
            ) : (
              <p className="text-muted-foreground">
                O painel está falando com a API administrativa. Nenhuma página mudou para isso — a
                troca acontece só na fábrica do provedor.
              </p>
            )}

            <p className="text-muted-foreground">
              Papel agora: <strong>{ROTULO_PAPEL[sessao.papel]}</strong>
              {sessao.simulada ? (
                <> — simulado pelo seletor do topo, muda só o que a interface mostra.</>
              ) : (
                <>
                  {' '}
                  — veio de <code className="font-mono">/admin/me</code>, validado no backend.
                </>
              )}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <KeyRound className="size-4" /> Variáveis de ambiente
            </CardTitle>
            <CardDescription>
              Presença, nunca o valor. Modelo completo em <code className="font-mono">.env.example</code>.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <ul>
              <LinhaVariavel
                nome="VITE_ADMIN_API_BASE_URL"
                valor={import.meta.env.VITE_ADMIN_API_BASE_URL}
              />
              <LinhaVariavel nome="VITE_SUPABASE_URL" valor={import.meta.env.VITE_SUPABASE_URL} />
              <LinhaVariavel
                nome="VITE_SUPABASE_PUBLISHABLE_KEY"
                valor={import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY}
              />
            </ul>
          </CardContent>
        </Card>

        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <KeyRound className="size-4" /> Autenticação
            </CardTitle>
            <CardDescription>Quem valida o acesso, e de onde vem o papel.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2 text-sm text-muted-foreground">
            {sessao.simulada ? (
              <p>
                <strong className="text-foreground">Modo simulado.</strong> Sem{' '}
                <code className="font-mono">VITE_SUPABASE_URL</code> o painel não pede login e o
                papel sai do seletor do topo.
              </p>
            ) : (
              <>
                <p>
                  <strong className="text-foreground">Supabase Auth ligado.</strong> A sessão é
                  restaurada com <code className="font-mono">getSession()</code> e acompanhada por{' '}
                  <code className="font-mono">onAuthStateChange()</code>. O token vai no header{' '}
                  <code className="font-mono">Authorization</code> — nunca na URL, nunca no console.
                </p>
                <p>
                  Papel e permissões vêm exclusivamente de{' '}
                  <code className="font-mono">GET /admin/me</code>.{' '}
                  <code className="font-mono">user_metadata</code> não é consultado em lugar nenhum
                  deste código: ele é editável pelo próprio usuário e não autoriza nada.
                </p>
                <p>
                  Sessão de <strong className="text-foreground">{sessao.email ?? '—'}</strong> ·
                  permissões{' '}
                  {sessao.permissoes
                    ? `enviadas pelo backend (${sessao.permissoes.length})`
                    : 'derivadas do papel informado pelo backend'}
                  .
                </p>
              </>
            )}
          </CardContent>
        </Card>

        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Server className="size-4" /> Endpoints
            </CardTitle>
            <CardDescription>O que o HttpAdminDataProvider já sabe chamar.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <ul className="space-y-1 font-mono text-xs">
              <li>GET&nbsp;&nbsp;&nbsp;&nbsp;/admin/dashboard</li>
              <li>GET&nbsp;&nbsp;&nbsp;&nbsp;/admin/:resource</li>
              <li>GET&nbsp;&nbsp;&nbsp;&nbsp;/admin/:resource/:id</li>
              <li>POST&nbsp;&nbsp;&nbsp;/admin/:resource</li>
              <li>PATCH&nbsp;&nbsp;/admin/:resource/:id</li>
              <li>POST&nbsp;&nbsp;&nbsp;/admin/:resource/:id/publish</li>
              <li>POST&nbsp;&nbsp;&nbsp;/admin/:resource/:id/archive</li>
              <li>POST&nbsp;&nbsp;&nbsp;/admin/documents/:id/reindex</li>
            </ul>
            <div className="space-y-1 text-sm text-muted-foreground">
              <p>
                <strong className="text-foreground">Supabase Auth:</strong> o painel vai obter o
                token da sessão e mandá-lo no header <code className="font-mono">Authorization</code>
                . O papel vem de uma tabela do banco, validada na Edge Function — nunca de{' '}
                <code className="font-mono">user_metadata</code>.
              </p>
              <p>
                <strong className="text-foreground">Nada é persistido hoje.</strong> Salvar,
                publicar, arquivar e reindexar mexem apenas na memória desta aba. Nenhuma tabela foi
                criada, nenhuma migration foi aplicada, nenhum documento foi indexado.
              </p>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
