import { ShieldAlert } from 'lucide-react';
import { DESCRICAO_PAPEL, PAPEIS, ROTULO_PAPEL, type Usuario } from '@/contracts';
import { formatarDataHora } from '@/lib/format';
import { PaginaListagem, type Coluna } from '@/components/admin/pagina-listagem';
import { DadoPessoal } from '@/components/admin/dado-pessoal';
import { EstadoVazio } from '@/components/admin/estados';
import { SeloAtivo } from '@/components/admin/selos';
import { Badge } from '@/components/ui/badge';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';

export function PaginaUsuarios() {
  const colunas: Coluna<Usuario>[] = [
    {
      chave: 'nome',
      cabecalho: 'Pessoa',
      celula: (u) => (
        <div className="min-w-48">
          <p className="font-semibold">{u.nome}</p>
          {/* E-mail nunca aparece inteiro em listagem. */}
          <DadoPessoal valor={u.email} tipo="email" className="text-xs text-muted-foreground" />
        </div>
      ),
    },
    {
      chave: 'papel',
      cabecalho: 'Papel',
      celula: (u) => (
        <Badge variant="outline" title={DESCRICAO_PAPEL[u.papel]}>
          {ROTULO_PAPEL[u.papel]}
        </Badge>
      ),
    },
    {
      chave: 'acesso',
      cabecalho: 'Último acesso',
      className: 'whitespace-nowrap tabular',
      celula: (u) =>
        u.ultimoAcessoEm ? (
          <span className="text-xs">{formatarDataHora(u.ultimoAcessoEm)}</span>
        ) : (
          <span className="text-xs text-muted-foreground">nunca acessou</span>
        ),
    },
    { chave: 'ativo', cabecalho: 'Situação', celula: (u) => <SeloAtivo ativo={u.ativo} /> },
  ];

  return (
    <PaginaListagem
      recurso="users"
      titulo="Usuários e permissões"
      descricao="Quem trabalha no painel e com qual papel. Esta tela desenha a interface; a autorização é do backend."
      colunas={colunas}
      ordenar="nome"
      placeholderBusca="Buscar por nome ou papel…"
      permissaoNecessaria="gerir_usuarios"
      definicoesFiltro={[
        {
          chave: 'papel',
          rotulo: 'Papel',
          opcoes: PAPEIS.map((p) => ({ valor: p, rotulo: ROTULO_PAPEL[p] })),
        },
        {
          chave: 'ativo',
          rotulo: 'Situação',
          opcoes: [
            { valor: 'true', rotulo: 'Ativos' },
            { valor: 'false', rotulo: 'Inativos' },
          ],
        },
      ]}
      estadoVazio={
        <EstadoVazio
          titulo="Nenhum usuário encontrado"
          descricao="Quando o Supabase Auth for ligado, esta lista vem do banco."
        />
      }
      antesDaTabela={() => (
        <Alert variant="atencao">
          <ShieldAlert />
          <AlertTitle>Isto não é controle de acesso</AlertTitle>
          <AlertDescription>
            Os papéis desta tela escondem botão e marcam página como &ldquo;sem
            permissão&rdquo; — nada além disso. A autorização real precisa acontecer na Edge
            Function, contra o JWT do Supabase Auth, lendo o papel de uma <strong>tabela do
            banco</strong>, nunca de <code className="font-mono">user_metadata</code>, que o próprio
            usuário consegue editar. Enquanto o backend não existir, considere que qualquer pessoa
            com acesso ao painel enxerga tudo.
          </AlertDescription>
        </Alert>
      )}
      rodape={() => (
        <Card>
          <CardHeader>
            <CardTitle>O que cada papel enxerga</CardTitle>
            <CardDescription>
              Matriz aplicada pela interface. Use o seletor &ldquo;Ver como&rdquo; no topo para
              conferir cada papel.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <ul className="grid gap-2 md:grid-cols-2">
              {PAPEIS.map((papel) => (
                <li key={papel} className="rounded-md border p-3">
                  <p className="text-sm font-bold">{ROTULO_PAPEL[papel]}</p>
                  <p className="text-xs text-muted-foreground">{DESCRICAO_PAPEL[papel]}</p>
                </li>
              ))}
            </ul>
          </CardContent>
        </Card>
      )}
    />
  );
}
