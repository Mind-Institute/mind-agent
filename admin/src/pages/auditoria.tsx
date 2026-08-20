import { ACOES_AUDITORIA, ROTULO_ACAO_AUDITORIA, ROTULO_RECURSO, type RegistroAuditoria } from '@/contracts';
import { formatarDataHora } from '@/lib/format';
import { PaginaListagem, type Coluna } from '@/components/admin/pagina-listagem';
import { EstadoVazio } from '@/components/admin/estados';
import { Badge } from '@/components/ui/badge';
import type { NomeRecurso } from '@/contracts';

/** Antes/depois em formato legível, sem despejar JSON cru na tabela. */
function Diferenca({ valores }: { valores: Record<string, unknown> | null }) {
  if (!valores || Object.keys(valores).length === 0) {
    return <span className="text-xs text-muted-foreground">—</span>;
  }
  return (
    <ul className="max-w-56 space-y-0.5">
      {Object.entries(valores).map(([chave, valor]) => (
        <li key={chave} className="truncate font-mono text-[11px]">
          <span className="text-muted-foreground">{chave}:</span> {String(valor)}
        </li>
      ))}
    </ul>
  );
}

export function PaginaAuditoria() {
  const colunas: Coluna<RegistroAuditoria>[] = [
    {
      chave: 'data',
      cabecalho: 'Quando',
      className: 'whitespace-nowrap tabular',
      celula: (r) => <span className="text-xs">{formatarDataHora(r.ocorridoEm)}</span>,
    },
    { chave: 'usuario', cabecalho: 'Usuário', celula: (r) => r.usuario },
    {
      chave: 'acao',
      cabecalho: 'Ação',
      celula: (r) => (
        <Badge
          variant={
            r.acao === 'publicar'
              ? 'sucesso'
              : r.acao === 'arquivar'
                ? 'atencao'
                : r.acao === 'reindexar'
                  ? 'roxo'
                  : 'outline'
          }
        >
          {ROTULO_ACAO_AUDITORIA[r.acao]}
        </Badge>
      ),
    },
    {
      chave: 'recurso',
      cabecalho: 'Recurso',
      celula: (r) => (
        <span className="text-sm">{ROTULO_RECURSO[r.recurso as NomeRecurso] ?? r.recurso}</span>
      ),
    },
    {
      chave: 'registro',
      cabecalho: 'Registro',
      celula: (r) => (
        <div className="min-w-40">
          <p className="truncate text-sm font-medium">{r.registroRotulo}</p>
          <p className="truncate font-mono text-[11px] text-muted-foreground">{r.registroId}</p>
        </div>
      ),
    },
    { chave: 'antes', cabecalho: 'Antes', celula: (r) => <Diferenca valores={r.antes} /> },
    { chave: 'depois', cabecalho: 'Depois', celula: (r) => <Diferenca valores={r.depois} /> },
    {
      chave: 'requestId',
      cabecalho: 'Requisição',
      celula: (r) => <span className="font-mono text-[11px] text-muted-foreground">{r.requestId}</span>,
    },
  ];

  return (
    <PaginaListagem
      recurso="audit"
      titulo="Auditoria"
      descricao="Quem mudou o quê, quando, e o que havia antes. Toda escrita feita no painel entra aqui — inclusive as simuladas."
      colunas={colunas}
      ordenar="-ocorridoEm"
      placeholderBusca="Buscar por usuário, recurso ou identificador de requisição…"
      permissaoNecessaria="ver_auditoria"
      definicoesFiltro={[
        {
          chave: 'acao',
          rotulo: 'Ação',
          opcoes: ACOES_AUDITORIA.map((a) => ({ valor: a, rotulo: ROTULO_ACAO_AUDITORIA[a] })),
        },
      ]}
      estadoVazio={
        <EstadoVazio
          titulo="Nenhum registro de auditoria"
          descricao="Nada foi alterado ainda nesta sessão de demonstração."
        />
      }
    />
  );
}
