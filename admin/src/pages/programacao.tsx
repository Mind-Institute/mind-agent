import { useMemo } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { AlertTriangle } from 'lucide-react';
import {
  ROTULO_TIPO_SESSAO,
  STATUS_EDITORIAL,
  ROTULO_STATUS_EDITORIAL,
  TIPOS_SESSAO,
  type Sessao,
} from '@/contracts';
import { useLista } from '@/hooks/use-recurso';
import { camposFaltantesDaSessao, detectarConflitos } from '@/lib/pendencias';
import { formatarData } from '@/lib/format';
import { PaginaListagem, type Coluna } from '@/components/admin/pagina-listagem';
import { SeloEditorial, SeloFaltando } from '@/components/admin/selos';
import { EstadoVazio } from '@/components/admin/estados';
import { DrawerSessao } from '@/features/programacao/drawer-sessao';
import { Badge } from '@/components/ui/badge';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';

export function PaginaProgramacao() {
  const { id } = useParams();
  const navegar = useNavigate();

  /* A detecção de conflito precisa da grade inteira, não da página
     filtrada: duas sessões podem colidir mesmo que só uma esteja
     visível no recorte atual. */
  const todas = useLista('sessions', {});
  const espacos = useLista('spaces', { ordenar: 'nome' });
  const temas = useLista('themes');
  const palestrantes = useLista('speakers', { ordenar: 'nome' });

  const conflitos = useMemo(
    () => detectarConflitos(todas.data?.itens ?? []),
    [todas.data],
  );

  const nomeDoEspaco = useMemo(() => {
    const mapa = new Map((espacos.data?.itens ?? []).map((e) => [e.id, e.nome]));
    return (idEspaco: string | null) => (idEspaco ? (mapa.get(idEspaco) ?? '—') : null);
  }, [espacos.data]);

  const tituloDaSessao = useMemo(() => {
    const mapa = new Map((todas.data?.itens ?? []).map((s) => [s.id, s.titulo]));
    return (idSessao: string) => mapa.get(idSessao) ?? idSessao;
  }, [todas.data]);

  const dias = useMemo(() => {
    const conjunto = new Set((todas.data?.itens ?? []).map((s) => s.dia));
    return Array.from(conjunto).sort();
  }, [todas.data]);

  const colunas: Coluna<Sessao>[] = [
    {
      chave: 'horario',
      cabecalho: 'Quando',
      className: 'whitespace-nowrap tabular',
      celula: (s) => (
        <div>
          <p className="font-semibold">{formatarData(s.dia)}</p>
          <p className="text-xs text-muted-foreground">
            {s.inicio}–{s.fim ?? 'aberta'}
          </p>
        </div>
      ),
    },
    {
      chave: 'titulo',
      cabecalho: 'Sessão',
      celula: (s) => {
        const conflitantes = conflitos.get(s.id) ?? [];
        const faltando = camposFaltantesDaSessao(s);
        return (
          <div className="min-w-64 space-y-1">
            <p className="font-semibold">{s.titulo}</p>
            <p className="line-clamp-1 text-xs text-muted-foreground">
              {s.quemTexto || 'Sem palestrante'}
            </p>
            <div className="flex flex-wrap gap-1">
              {conflitantes.length > 0 ? (
                <Badge
                  variant="destructive"
                  title={`Choca com: ${conflitantes.map(tituloDaSessao).join(' · ')}`}
                >
                  <AlertTriangle className="size-3" />
                  conflito de horário
                </Badge>
              ) : null}
              <SeloFaltando campos={faltando} />
            </div>
          </div>
        );
      },
    },
    {
      chave: 'espaco',
      cabecalho: 'Espaço',
      celula: (s) =>
        s.espacoId ? (
          <span className="text-sm">{nomeDoEspaco(s.espacoId)}</span>
        ) : (
          <Badge variant="destructive">sem espaço</Badge>
        ),
    },
    {
      chave: 'tipo',
      cabecalho: 'Tipo',
      celula: (s) => <Badge variant="outline">{ROTULO_TIPO_SESSAO[s.tipo]}</Badge>,
    },
    {
      chave: 'reserva',
      cabecalho: 'Vagas',
      className: 'tabular whitespace-nowrap',
      celula: (s) =>
        s.necessitaReserva ? (
          <span className="text-sm">
            {s.vagasDisponiveis ?? '?'}/{s.vagasTotais ?? '?'}
          </span>
        ) : (
          <span className="text-xs text-muted-foreground">livre</span>
        ),
    },
    {
      chave: 'status',
      cabecalho: 'Status',
      celula: (s) => <SeloEditorial status={s.status} />,
    },
  ];

  const totalConflitos = conflitos.size;

  return (
    <>
      <PaginaListagem
        recurso="sessions"
        titulo="Programação"
        descricao="As sessões do Summit. Conflito de horário e campo faltante aparecem na própria linha — o agente responde com o que estiver aqui."
        colunas={colunas}
        placeholderBusca="Buscar por título, descrição ou palestrante…"
        ordenar="dia"
        destinoItem={(s) => `/programacao/${s.id}`}
        definicoesFiltro={[
          {
            chave: 'dia',
            rotulo: 'Dia',
            opcoes: dias.map((dia) => ({ valor: dia, rotulo: formatarData(dia) })),
          },
          {
            chave: 'espacoId',
            rotulo: 'Espaço',
            opcoes: [
              { valor: 'null', rotulo: 'Sem espaço' },
              ...(espacos.data?.itens ?? []).map((e) => ({ valor: e.id, rotulo: e.nome })),
            ],
          },
          {
            chave: 'tema',
            rotulo: 'Tema',
            opcoes: (temas.data?.itens ?? []).map((t) => ({ valor: t.codigo, rotulo: t.rotulo })),
          },
          {
            chave: 'palestranteId',
            rotulo: 'Palestrante',
            opcoes: (palestrantes.data?.itens ?? []).map((p) => ({ valor: p.id, rotulo: p.nome })),
          },
          {
            chave: 'tipo',
            rotulo: 'Tipo',
            opcoes: TIPOS_SESSAO.map((t) => ({ valor: t, rotulo: ROTULO_TIPO_SESSAO[t] })),
          },
          {
            chave: 'status',
            rotulo: 'Status',
            opcoes: STATUS_EDITORIAL.map((s) => ({ valor: s, rotulo: ROTULO_STATUS_EDITORIAL[s] })),
          },
        ]}
        antesDaTabela={() =>
          totalConflitos > 0 ? (
            <Alert variant="atencao">
              <AlertTriangle />
              <AlertTitle>
                {totalConflitos} sessão(ões) com conflito de horário no mesmo espaço
              </AlertTitle>
              <AlertDescription>
                Duas sessões que dividem espaço, dia e horário. As linhas afetadas estão marcadas —
                passe o mouse no selo para ver com qual sessão cada uma choca.
              </AlertDescription>
            </Alert>
          ) : null
        }
        estadoVazio={
          <EstadoVazio
            titulo="Nenhuma sessão encontrada"
            descricao="Nenhum registro bate com a busca e os filtros atuais. Limpe os filtros para ver a grade inteira."
          />
        }
      />

      <DrawerSessao id={id} aoFechar={() => navegar('/programacao')} />
    </>
  );
}
