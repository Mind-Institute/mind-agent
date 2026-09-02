import { useMemo, useState } from 'react';
import { CalendarClock, Check, Plus, Trash2 } from 'lucide-react';
import {
  MOMENTOS_HOME,
  RESUMO_MOMENTO,
  ROTULO_MOMENTO,
  type EstadoHome,
  type MomentoHome,
  type TrocaHome,
} from '@/contracts';
import { useArquivar, useAtualizar, useCriar, useLista } from '@/hooks/use-recurso';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { AvisoErroEscrita } from '@/components/admin/aviso-escrita';
import { EstadoVazio } from '@/components/admin/estados';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Skeleton } from '@/components/ui/skeleton';

/* ============================================================
   HOME V3 · VISUALIZAÇÃO
   ============================================================
   Uma pergunta só: qual das quatro telas o participante está vendo
   agora. Duas formas de responder — trocar na mão, ou deixar a
   programação trocar por você.

   O modo existe para o dia do evento: alguém precisa poder assumir o
   controle no meio de um imprevisto sem apagar a agenda que já estava
   montada. Em `manual`, a programação fica visível mas parada. */

/** Ordena por horário e diz qual troca é a próxima a valer. */
function proximaTroca(trocas: TrocaHome[], agora: Date): TrocaHome | null {
  const pendentes = trocas
    .filter((t) => !t.aplicada)
    .sort((a, b) => a.quando.localeCompare(b.quando));
  return pendentes.find((t) => new Date(t.quando).getTime() > agora.getTime()) ?? null;
}

function formatarQuando(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString('pt-BR', {
    day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit',
  });
}

export function PaginaHomeVisualizacao() {
  const estado = useLista('home_state');
  const trocas = useLista('home_schedule', { porPagina: 200 });
  const atualizarEstado = useAtualizar('home_state');
  const criarTroca = useCriar('home_schedule');
  const arquivarTroca = useArquivar('home_schedule');

  const [novoQuando, setNovoQuando] = useState('');
  const [novoMomento, setNovoMomento] = useState<MomentoHome>('no-evento');
  const [nota, setNota] = useState('');

  const atual: EstadoHome | undefined = estado.data?.itens[0];
  const lista = useMemo(
    () => [...(trocas.data?.itens ?? [])].sort((a, b) => a.quando.localeCompare(b.quando)),
    [trocas.data],
  );
  const proxima = useMemo(() => proximaTroca(lista, new Date()), [lista]);

  const erro = atualizarEstado.error ?? criarTroca.error ?? arquivarTroca.error;

  function trocarAgora(momento: MomentoHome) {
    if (!atual || momento === atual.momento) return;
    atualizarEstado.mutate({ id: atual.id, payload: { momento, modo: 'manual' } });
  }

  function alternarModo() {
    if (!atual) return;
    atualizarEstado.mutate({
      id: atual.id,
      payload: { modo: atual.modo === 'manual' ? 'programado' : 'manual' },
    });
  }

  function agendar() {
    if (!novoQuando) return;
    criarTroca.mutate(
      { quando: novoQuando, momento: novoMomento, nota, aplicada: false },
      { onSuccess: () => { setNovoQuando(''); setNota(''); } },
    );
  }

  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Visualização da home"
        descricao="Qual das quatro telas o participante vê agora. Troque na hora ou programe o horário da mudança."
      />

      {erro ? <AvisoErroEscrita erro={erro} /> : null}

      {/* ---- O que está no ar ---- */}
      <section className="rounded-xl border bg-card p-5">
        <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="text-sm font-semibold">No ar agora</h2>
            <p className="text-xs text-muted-foreground">
              {atual
                ? 'Atualizado em ' + formatarQuando(atual.atualizadoEm)
                : 'Carregando o estado da home…'}
            </p>
          </div>
          {atual ? (
            <Button variant="outline" size="sm" onClick={alternarModo}>
              <CalendarClock className="mr-2 size-4" />
              {atual.modo === 'programado'
                ? 'Seguindo a programação'
                : 'Controle manual'}
            </Button>
          ) : null}
        </div>

        {estado.isLoading ? (
          <Skeleton className="h-28 w-full" />
        ) : (
          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            {MOMENTOS_HOME.map((m) => {
              const ativo = atual?.momento === m;
              return (
                <button
                  key={m}
                  type="button"
                  onClick={() => trocarAgora(m)}
                  disabled={ativo || atualizarEstado.isPending}
                  aria-pressed={ativo}
                  className={
                    'rounded-lg border p-4 text-left transition ' +
                    (ativo
                      ? 'border-primary bg-primary/5 ring-1 ring-primary'
                      : 'hover:border-primary/50 disabled:opacity-60')
                  }
                >
                  <span className="flex items-center justify-between gap-2">
                    <strong className="text-sm">{ROTULO_MOMENTO[m]}</strong>
                    {ativo ? <Check className="size-4 text-primary" /> : null}
                  </span>
                  <span className="mt-1 block text-xs leading-snug text-muted-foreground">
                    {RESUMO_MOMENTO[m]}
                  </span>
                </button>
              );
            })}
          </div>
        )}

        {atual?.modo === 'manual' && proxima ? (
          <p className="mt-4 text-xs text-muted-foreground">
            A programação está parada. Em <strong>Seguindo a programação</strong>, a
            próxima troca seria para <strong>{ROTULO_MOMENTO[proxima.momento]}</strong> em{' '}
            {formatarQuando(proxima.quando)}.
          </p>
        ) : null}
        {atual?.modo === 'programado' && proxima ? (
          <p className="mt-4 text-xs text-muted-foreground">
            Próxima troca automática: <strong>{ROTULO_MOMENTO[proxima.momento]}</strong> em{' '}
            {formatarQuando(proxima.quando)}.
          </p>
        ) : null}
      </section>

      {/* ---- Programação ---- */}
      <section className="rounded-xl border bg-card p-5">
        <h2 className="text-sm font-semibold">Trocas programadas</h2>
        <p className="mb-4 text-xs text-muted-foreground">
          Em que horário cada tela entra no ar. Só valem quando o controle está em
          &ldquo;Seguindo a programação&rdquo;.
        </p>

        <div className="mb-5 grid gap-3 rounded-lg border border-dashed p-4 md:grid-cols-[1fr_1fr_2fr_auto] md:items-end">
          <div>
            <Label htmlFor="troca-quando">Data e hora</Label>
            <Input
              id="troca-quando"
              type="datetime-local"
              value={novoQuando}
              onChange={(e) => setNovoQuando(e.target.value)}
            />
          </div>
          <div>
            <Label htmlFor="troca-momento">Tela</Label>
            <select
              id="troca-momento"
              value={novoMomento}
              onChange={(e) => setNovoMomento(e.target.value as MomentoHome)}
              className="flex h-10 w-full rounded-md border border-input bg-background px-3 text-sm"
            >
              {MOMENTOS_HOME.map((m) => (
                <option key={m} value={m}>{ROTULO_MOMENTO[m]}</option>
              ))}
            </select>
          </div>
          <div>
            <Label htmlFor="troca-nota">Nota (opcional)</Label>
            <Input
              id="troca-nota"
              value={nota}
              onChange={(e) => setNota(e.target.value)}
              placeholder="Por que essa troca acontece aqui"
            />
          </div>
          <Button onClick={agendar} disabled={!novoQuando || criarTroca.isPending}>
            <Plus className="mr-2 size-4" />
            Programar
          </Button>
        </div>

        {trocas.isLoading ? (
          <Skeleton className="h-24 w-full" />
        ) : lista.length === 0 ? (
          <EstadoVazio
            titulo="Nenhuma troca programada"
            descricao="Sem programação, a tela só muda quando alguém troca na mão."
          />
        ) : (
          <ul className="divide-y rounded-lg border">
            {lista.map((t) => (
              <li key={t.id} className="flex flex-wrap items-center gap-3 p-3">
                <span className="min-w-40 font-mono text-xs">{formatarQuando(t.quando)}</span>
                <Badge variant="neutro">{ROTULO_MOMENTO[t.momento]}</Badge>
                {t.aplicada ? <Badge variant="neutro">já aplicada</Badge> : null}
                <span className="flex-1 text-xs text-muted-foreground">{t.nota}</span>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => arquivarTroca.mutate({ id: t.id })}
                  aria-label={'Remover a troca de ' + formatarQuando(t.quando)}
                >
                  <Trash2 className="size-4" />
                </Button>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
