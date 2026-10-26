import { useLocation, useNavigate, useParams } from 'react-router-dom';
import { DIAS_SUMMIT_2026, type SessaoSummit2026 } from '@/contracts';
import { useItem } from '@/hooks/use-recurso';
import { formatarData } from '@/lib/format';
import { PaginaListagem, type Coluna } from '@/components/admin/pagina-listagem';
import { EstadoCarregando, EstadoErro, EstadoVazio } from '@/components/admin/estados';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetFooter,
  SheetHeader,
  SheetTitle,
} from '@/components/ui/sheet';

/* ============================================================
   MIND SUMMIT 2026 — PROGRAMAÇÃO, COMO ESTÁ NO BANCO
   ============================================================
   Pedido da Adriana (26/09/2026): no menu SUMMIT, "Mind Summit 2026", e
   dentro dele a tabela de programação "conforme está no backend". A casa é
   `summit_2026.sessions`; a porta, a `mindagent-summit`. SÓ LEITURA.

   A lista mostra as colunas que dão para ler a grade; abrir uma sessão
   mostra TODAS as colunas, com os nomes do banco — é o "como está". O
   horário aparece no fuso do evento, São Paulo. */

const RECURSO = 'summit_2026_sessions' as const;
const CAMINHO = '/summit/2026/programacao';

/* Os tipos que a tabela usa hoje, com o código do banco. Tipo novo aparece
   cru na lista, e o filtro se estende quando ele surgir. */
const TIPOS = [
  'abertura', 'almoco', 'alumni-talk', 'autografos', 'credenciamento', 'entrevista', 'experiencia',
  'intervalo', 'lancamento', 'masterclass', 'painel', 'palestra', 'workshop',
];

const HORA = new Intl.DateTimeFormat('pt-BR', {
  hour: '2-digit',
  minute: '2-digit',
  timeZone: 'America/Sao_Paulo',
});

function hora(iso: string | null | undefined): string {
  if (!iso) return '';
  const data = new Date(iso);
  return Number.isNaN(data.getTime()) ? iso : HORA.format(data);
}

/** Valor de coluna como texto legível, sem esconder o que o banco guarda. */
function valorDaColuna(valor: unknown): string {
  if (valor === null || valor === undefined || valor === '') return '—';
  if (typeof valor === 'boolean') return valor ? 'sim' : 'não';
  if (Array.isArray(valor)) {
    if (valor.length === 0) return '—';
    return valor.every((v) => typeof v !== 'object') ? valor.join(', ') : JSON.stringify(valor, null, 2);
  }
  if (typeof valor === 'object') return JSON.stringify(valor, null, 2);
  return String(valor);
}

/* Leituras que o banco acrescenta à linha, fora das colunas da tabela. */
const LEITURAS = new Set(['espaco', 'palestrantes']);

function DetalheSessao({ id, aoFechar }: { id: string | undefined; aoFechar: () => void }) {
  const consulta = useItem(RECURSO, id);
  const sessao = consulta.data;

  return (
    <Sheet open={Boolean(id)} onOpenChange={(aberto) => (!aberto ? aoFechar() : undefined)}>
      <SheetContent side="right" className="w-full p-0 sm:max-w-2xl">
        <SheetHeader>
          <SheetTitle>{sessao?.titulo ?? 'Sessão'}</SheetTitle>
          <SheetDescription>
            {sessao
              ? `${formatarData(sessao.dia)} · ${hora(sessao.inicio)}${sessao.fim ? `–${hora(sessao.fim)}` : ''}`
              : 'Carregando…'}
          </SheetDescription>
        </SheetHeader>

        <div className="flex-1 space-y-5 overflow-y-auto p-5">
          {consulta.isPending ? (
            <EstadoCarregando linhas={8} />
          ) : consulta.error ? (
            <EstadoErro erro={consulta.error} aoTentarNovamente={() => void consulta.refetch()} />
          ) : sessao ? (
            <>
              <dl className="grid gap-3 rounded-lg border bg-muted/30 p-4 text-sm sm:grid-cols-2">
                <div className="space-y-0.5">
                  <dt className="text-xs font-semibold text-muted-foreground">Espaço</dt>
                  <dd>{sessao.espaco ?? '—'}</dd>
                </div>
                <div className="space-y-0.5">
                  <dt className="text-xs font-semibold text-muted-foreground">Palestrantes</dt>
                  <dd>{sessao.palestrantes.length ? sessao.palestrantes.join(', ') : '—'}</dd>
                </div>
              </dl>

              <section className="space-y-2" data-testid="colunas-da-sessao">
                <h3 className="text-xs font-black uppercase tracking-wide text-muted-foreground">
                  Colunas de <span className="font-mono normal-case">summit_2026.sessions</span>
                </h3>
                <dl className="divide-y rounded-lg border text-sm">
                  {Object.entries(sessao)
                    .filter(([coluna]) => !LEITURAS.has(coluna))
                    .map(([coluna, valor]) => {
                      const texto = valorDaColuna(valor);
                      return (
                        <div key={coluna} className="grid gap-1 px-3 py-2 sm:grid-cols-[12rem_1fr]">
                          <dt className="font-mono text-xs text-muted-foreground">{coluna}</dt>
                          <dd className="min-w-0 break-words">
                            {texto.includes('\n') ? (
                              <pre className="whitespace-pre-wrap font-mono text-xs">{texto}</pre>
                            ) : (
                              texto
                            )}
                          </dd>
                        </div>
                      );
                    })}
                </dl>
              </section>
            </>
          ) : null}
        </div>

        <SheetFooter>
          <p className="mr-auto text-xs text-muted-foreground">Só leitura: a programação não se edita pelo painel.</p>
          <Button variant="outline" type="button" onClick={aoFechar}>
            Fechar
          </Button>
        </SheetFooter>
      </SheetContent>
    </Sheet>
  );
}

export function PaginaSummitProgramacao() {
  const { id } = useParams();
  const navegar = useNavigate();
  /* Fechar a sessão volta à lista como estava: busca, filtros, página e ordem. */
  const { search } = useLocation();

  const colunas: Coluna<SessaoSummit2026>[] = [
    {
      chave: 'dia',
      cabecalho: 'Dia',
      ordenarPor: 'dia',
      className: 'whitespace-nowrap tabular',
      celula: (s) => formatarData(s.dia),
    },
    {
      chave: 'horario',
      cabecalho: 'Horário',
      ordenarPor: 'inicio',
      className: 'whitespace-nowrap tabular',
      celula: (s) => `${hora(s.inicio)}${s.fim ? `–${hora(s.fim)}` : ''}`,
    },
    {
      chave: 'titulo',
      cabecalho: 'Sessão',
      ordenarPor: 'titulo',
      celula: (s) => <p className="min-w-56 font-semibold">{s.titulo}</p>,
    },
    {
      chave: 'tipo',
      cabecalho: 'Tipo',
      ordenarPor: 'tipo',
      celula: (s) =>
        s.tipo ? <Badge variant="outline" className="font-mono">{s.tipo}</Badge> : <span className="text-muted-foreground">—</span>,
    },
    {
      chave: 'espaco',
      cabecalho: 'Espaço',
      ordenarPor: 'espaco',
      celula: (s) => s.espaco ?? <span className="text-muted-foreground">—</span>,
    },
    {
      chave: 'palestrantes',
      cabecalho: 'Palestrantes',
      celula: (s) =>
        s.palestrantes.length ? (
          <span className="text-xs">{s.palestrantes.join(', ')}</span>
        ) : (
          <span className="text-muted-foreground">—</span>
        ),
    },
    {
      chave: 'reserva',
      cabecalho: 'Reserva',
      ordenarPor: 'vagas_disponiveis',
      className: 'whitespace-nowrap',
      celula: (s) =>
        s.precisa_reserva ? (
          <span className="text-xs">
            <Badge variant="atencao">com reserva</Badge>
            {s.vagas_disponiveis !== null ? (
              <span className="ml-1 tabular text-muted-foreground">
                {s.vagas_disponiveis}
                {s.vagas_total !== null ? ` de ${s.vagas_total}` : ''} vagas
              </span>
            ) : null}
          </span>
        ) : (
          <span className="text-xs text-muted-foreground">livre</span>
        ),
    },
  ];

  return (
    <>
      <PaginaListagem
        recurso={RECURSO}
        titulo="Programação · Mind Summit 2026"
        descricao="A tabela summit_2026.sessions como está no banco, só leitura. Abra uma sessão para ver todas as colunas."
        colunas={colunas}
        placeholderBusca="Buscar por título, descrição, espaço ou palestrante…"
        destinoItem={(s) => `${CAMINHO}/${s.id}`}
        definicoesFiltro={[
          { chave: 'dia', rotulo: 'Dia', opcoes: DIAS_SUMMIT_2026 },
          { chave: 'tipo', rotulo: 'Tipo', opcoes: TIPOS.map((t) => ({ valor: t, rotulo: t })) },
          {
            chave: 'precisa_reserva',
            rotulo: 'Reserva',
            opcoes: [
              { valor: 'true', rotulo: 'Com reserva' },
              { valor: 'false', rotulo: 'Livre' },
            ],
          },
        ]}
        estadoVazio={
          <EstadoVazio titulo="Nenhuma sessão no recorte" descricao="Nenhuma sessão bate com a busca e os filtros atuais." />
        }
      />

      <DetalheSessao id={id} aoFechar={() => navegar({ pathname: CAMINHO, search })} />
    </>
  );
}
