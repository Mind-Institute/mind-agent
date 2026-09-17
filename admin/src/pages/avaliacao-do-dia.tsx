import { useCallback, useEffect, useMemo, useState } from 'react';
import { Download, Star } from 'lucide-react';
import { useSessao } from '@/hooks/use-sessao';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { EstadoCarregando, EstadoVazio } from '@/components/admin/estados';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import {
  baseDaAvaliacao,
  lerRelatorio,
  lerRespostas,
  type LinhaDeAtividade,
  type PaginaDeRespostas,
  type Relatorio,
} from '@/services/avaliacao-api';
import { BarrasDeDistribuicao, CartaoDeNota, CartaoSimples, Numero } from '@/features/avaliacao-do-dia/kpis';
import { baixarCsv, montarCsv } from '@/features/avaliacao-do-dia/csv';

/* ============================================================
   AVALIAÇÃO DO DIA — o relatório
   ============================================================
   Somente leitura. Não existe edição de resposta no painel: uma resposta
   enviada é definitiva também para quem administra.

   TRÊS CUIDADOS QUE A TELA INTEIRA RESPEITA

   1. Média nunca aparece sem o tamanho da amostra ao lado.
   2. Atividade sem avaliação mostra "Sem avaliações" — nunca média zero.
      Zero é uma nota que alguém deu, e confundir as duas coisas inverte
      a leitura da grade.
   3. As respostas e as notas por atividade são contadas separadamente.
      Nenhum número desta tela junta as duas listas, porque juntá-las
      multiplicaria cada respondente pelo número de atividades que ele
      avaliou.

   TAXA DE PARTICIPAÇÃO NÃO APARECE. Ela exigiria um denominador
   confiável de presentes no dia, que não existe hoje: o espelho do
   credenciamento tem quem comprou, não quem entrou. Um percentual sobre
   o denominador errado seria pior que a ausência dele. */

const EXPERIENCIAS = [
  { valor: 'mind', rotulo: 'Mind' },
  { valor: 'vip', rotulo: 'VIP' },
  { valor: 'prime', rotulo: 'Prime' },
];

type Ordem = 'grade' | 'media' | 'avaliacoes';

function diaCurto(iso: string) {
  const p = iso.split('-');
  return p.length === 3 ? `${p[2]}/${p[1]}` : iso;
}

function quandoLegivel(iso: string) {
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? iso
    : d.toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' });
}

export function PaginaAvaliacaoDoDia() {
  const sessao = useSessao();
  const obterToken = sessao.obterToken;
  const configurada = Boolean(baseDaAvaliacao());

  const [dia, setDia] = useState<string>('todos');
  const [experiencia, setExperiencia] = useState<string>('todos');
  const [sessaoId, setSessaoId] = useState<string>('todos');
  const [ordem, setOrdem] = useState<Ordem>('grade');
  const [pagina, setPagina] = useState(1);

  const [relatorio, setRelatorio] = useState<Relatorio | null>(null);
  const [respostas, setRespostas] = useState<PaginaDeRespostas | null>(null);
  const [carregando, setCarregando] = useState(configurada);
  const [erro, setErro] = useState<string | null>(null);

  const filtro = useMemo(
    () => ({
      dia: dia === 'todos' ? null : dia,
      experiencia: experiencia === 'todos' ? null : experiencia,
      sessaoId: sessaoId === 'todos' ? null : sessaoId,
    }),
    [dia, experiencia, sessaoId],
  );

  const carregar = useCallback(async () => {
    if (!configurada) return;
    setCarregando(true);
    setErro(null);
    try {
      const [r, p] = await Promise.all([
        lerRelatorio(filtro, obterToken),
        lerRespostas({ ...filtro, pagina, porPagina: 25 }, obterToken),
      ]);
      setRelatorio(r);
      setRespostas(p);
    } catch (e) {
      setErro(e instanceof Error ? e.message : 'Não foi possível carregar o relatório.');
      setRelatorio(null);
      setRespostas(null);
    } finally {
      setCarregando(false);
    }
  }, [configurada, filtro, obterToken, pagina]);

  useEffect(() => {
    void carregar();
  }, [carregar]);

  /* Trocar o filtro volta para a primeira página: manter a página 3 de um
     recorte que agora tem uma página só mostraria uma lista vazia que
     parece "não há respostas". */
  const trocarFiltro = (aplicar: () => void) => {
    aplicar();
    setPagina(1);
  };

  const atividades = useMemo<LinhaDeAtividade[]>(() => {
    const lista = relatorio?.porAtividade ?? [];
    const copia = [...lista];
    if (ordem === 'media') {
      /* Sem avaliação vai para o fim, sempre — e não para o topo como
         "menor média", que é o que aconteceria tratando null como 0. */
      copia.sort((a, b) => {
        if (a.media === null && b.media === null) return 0;
        if (a.media === null) return 1;
        if (b.media === null) return -1;
        return b.media - a.media;
      });
    } else if (ordem === 'avaliacoes') {
      copia.sort((a, b) => b.avaliacoes - a.avaliacoes);
    }
    return copia;
  }, [relatorio, ordem]);

  const exportarRespostas = () => {
    if (!respostas) return;
    baixarCsv(
      `avaliacao-do-dia-respostas${filtro.dia ? '-' + filtro.dia : ''}.csv`,
      montarCsv(
        ['Dia', 'Enviado em', 'Nome', 'E-mail', 'Experiência', 'Profissão', 'Expectativas',
          'Nota relevância', 'Nota programação', 'Atividades avaliadas',
          'O que mais gostou', 'O que melhorar', 'Comentário'],
        respostas.itens.map((r) => [
          r.dia, quandoLegivel(r.enviadoEm), r.nome ?? '', r.email ?? '',
          r.experiencia, r.profissao, r.expectativas,
          r.notaRelevancia, r.notaProgramacao, r.atividadesAvaliadas,
          r.maisGostou ?? '', r.melhorar ?? '', r.comentario ?? '',
        ]),
      ),
    );
  };

  const exportarAtividades = () => {
    if (!relatorio) return;
    baixarCsv(
      `avaliacao-do-dia-atividades${filtro.dia ? '-' + filtro.dia : ''}.csv`,
      montarCsv(
        ['Dia', 'Horário', 'Atividade', 'Espaço', 'Acesso', 'Avaliações', 'Média',
          'Nota 0', 'Nota 1', 'Nota 2', 'Nota 3', 'Nota 4', 'Nota 5'],
        atividades.map((a) => [
          a.dia, a.inicio, a.titulo, a.espaco ?? '', (a.ingressos ?? []).join(', '),
          a.avaliacoes,
          /* Sem avaliação não vira 0 nem na planilha. */
          a.media === null ? '' : a.media,
          a.distribuicao['0'], a.distribuicao['1'], a.distribuicao['2'],
          a.distribuicao['3'], a.distribuicao['4'], a.distribuicao['5'],
        ]),
      ),
    );
  };

  const cabecalho = (
    <CabecalhoPagina
      titulo="Avaliação do dia"
      descricao="O que os participantes responderam sobre cada dia do Summit. Notas de 0 a 5 — não é NPS, e nenhuma média aqui vira índice de promotores."
    />
  );

  if (!configurada) {
    return (
      <div className="space-y-5">
        {cabecalho}
        <EstadoVazio
          icone={<Star className="size-7" />}
          titulo="A pesquisa ainda não foi ligada"
          descricao="Defina VITE_AVALIACAO_API_BASE_URL no build do painel e aplique a migration da Avaliação do dia. Até lá não há de onde ler — e o painel não inventa endereço."
        />
      </div>
    );
  }

  const dias = relatorio?.evento?.dias ?? [];
  const semRespostas = Boolean(relatorio && relatorio.kpis.respondentes === 0);

  return (
    <div className="space-y-5">
      {cabecalho}

      <div className="flex flex-wrap items-center gap-2">
        <Select value={dia} onValueChange={(v) => trocarFiltro(() => setDia(v))}>
          <SelectTrigger className="w-auto min-w-40" aria-label="Dia">
            <SelectValue placeholder="Dia" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="todos">Dia: todos</SelectItem>
            {dias.map((d) => (
              <SelectItem key={d} value={d}>
                {diaCurto(d)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        <Select value={experiencia} onValueChange={(v) => trocarFiltro(() => setExperiencia(v))}>
          <SelectTrigger className="w-auto min-w-48" aria-label="Experiência declarada">
            <SelectValue placeholder="Experiência" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="todos">Experiência: todas</SelectItem>
            {EXPERIENCIAS.map((e) => (
              <SelectItem key={e.valor} value={e.valor}>
                {e.rotulo}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        <Button variant="outline" onClick={exportarRespostas} disabled={!respostas?.itens.length}>
          <Download className="size-4" /> CSV das respostas
        </Button>
        <Button variant="outline" onClick={exportarAtividades} disabled={!atividades.length}>
          <Download className="size-4" /> CSV por atividade
        </Button>
      </div>

      {erro ? (
        <Alert variant="erro">
          <AlertTitle>Não deu para carregar</AlertTitle>
          <AlertDescription>{erro}</AlertDescription>
        </Alert>
      ) : null}

      {carregando ? <EstadoCarregando linhas={4} rotulo="Carregando o relatório…" /> : null}

      {!carregando && relatorio ? (
        <>
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <CartaoSimples
              titulo="Respondentes"
              valor={relatorio.kpis.respondentes}
              apoio={
                `Mind ${relatorio.kpis.porExperiencia.mind} · ` +
                `VIP ${relatorio.kpis.porExperiencia.vip} · ` +
                `Prime ${relatorio.kpis.porExperiencia.prime}`
              }
            />
            <CartaoDeNota titulo="Relevância do que vivenciaram" nota={relatorio.kpis.relevancia} />
            <CartaoDeNota titulo="Programação do dia" nota={relatorio.kpis.programacao} />
            <CartaoSimples
              titulo="Avaliações de atividades"
              valor={relatorio.avaliacoesDeAtividades}
              apoio="Notas individuais, contadas à parte das respostas"
            />
          </div>

          {semRespostas ? (
            <EstadoVazio
              titulo="Nenhuma resposta neste recorte"
              descricao="Troque o dia ou a experiência para ver outro recorte."
            />
          ) : null}

          <Card>
            <CardHeader className="flex flex-row flex-wrap items-center justify-between gap-3">
              <CardTitle className="text-base">Por atividade</CardTitle>
              <Select value={ordem} onValueChange={(v) => setOrdem(v as Ordem)}>
                <SelectTrigger className="w-auto min-w-48" aria-label="Ordenar atividades">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="grade">Ordem da grade</SelectItem>
                  <SelectItem value="media">Maior média</SelectItem>
                  <SelectItem value="avaliacoes">Mais avaliadas</SelectItem>
                </SelectContent>
              </Select>
            </CardHeader>
            <CardContent>
              {atividades.length === 0 ? (
                <EstadoVazio titulo="Sem atividades neste recorte" />
              ) : (
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Atividade</TableHead>
                        <TableHead className="w-28">Horário</TableHead>
                        <TableHead className="w-44">Espaço</TableHead>
                        <TableHead className="w-28 text-right">Avaliações</TableHead>
                        <TableHead className="w-24 text-right">Média</TableHead>
                        <TableHead className="w-48">Distribuição</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {atividades.map((a) => (
                        <TableRow key={a.id}>
                          <TableCell className="font-medium">{a.titulo}</TableCell>
                          <TableCell className="tabular-nums text-muted-foreground">
                            {diaCurto(a.dia)} {a.inicio}
                          </TableCell>
                          <TableCell className="text-muted-foreground">{a.espaco ?? '—'}</TableCell>
                          <TableCell className="text-right tabular-nums">{a.avaliacoes}</TableCell>
                          <TableCell className="text-right font-bold tabular-nums">
                            {a.avaliacoes === 0 ? (
                              <Badge variant="neutro">Sem avaliações</Badge>
                            ) : (
                              <Numero valor={a.media} />
                            )}
                          </TableCell>
                          <TableCell>
                            {a.avaliacoes === 0 ? (
                              <span className="text-muted-foreground">—</span>
                            ) : (
                              <BarrasDeDistribuicao
                                distribuicao={a.distribuicao}
                                total={a.avaliacoes}
                              />
                            )}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row flex-wrap items-center justify-between gap-3">
              <CardTitle className="text-base">Respostas abertas</CardTitle>
              <Select value={sessaoId} onValueChange={(v) => trocarFiltro(() => setSessaoId(v))}>
                <SelectTrigger className="w-auto min-w-64" aria-label="Filtrar por atividade">
                  <SelectValue placeholder="Atividade" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="todos">Atividade: todas</SelectItem>
                  {(relatorio.porAtividade ?? [])
                    .filter((a) => a.avaliacoes > 0)
                    .map((a) => (
                      <SelectItem key={a.id} value={a.id}>
                        {a.inicio} · {a.titulo}
                      </SelectItem>
                    ))}
                </SelectContent>
              </Select>
            </CardHeader>
            <CardContent className="space-y-4">
              {!respostas || respostas.itens.length === 0 ? (
                <EstadoVazio titulo="Nenhuma resposta neste recorte" />
              ) : (
                <>
                  <ul className="space-y-3">
                    {respostas.itens.map((r) => (
                      <li key={r.id} className="rounded-lg border p-4">
                        {/* QUEM RESPONDEU vem na primeira linha, e o e-mail é
                            selecionável: o uso desta tela é ler a reclamação e
                            responder a ela. Nome e e-mail inteiros, contra a
                            máscara do resto do painel — é a "decisão de backend"
                            que `dado-pessoal.tsx` prevê, tomada para este
                            relatório, que já exige sessão de administrador. */}
                        <div className="flex flex-wrap items-baseline gap-x-2 gap-y-1">
                          <Badge variant="neutro">{r.experiencia}</Badge>
                          <span className="text-sm font-bold">{r.nome ?? 'Sem nome no cadastro'}</span>
                          {r.email ? (
                            <a
                              href={`mailto:${r.email}`}
                              className="select-all text-xs text-primary underline underline-offset-2"
                            >
                              {r.email}
                            </a>
                          ) : (
                            <span className="text-xs text-muted-foreground">sem e-mail no cadastro</span>
                          )}
                        </div>
                        <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                          <span>{r.profissao}</span>
                          <span>·</span>
                          <span className="tabular-nums">
                            relevância {r.notaRelevancia} · programação {r.notaProgramacao}
                          </span>
                          <span>·</span>
                          <span className="tabular-nums">{quandoLegivel(r.enviadoEm)}</span>
                        </div>
                        <dl className="mt-3 space-y-2 text-sm">
                          <Aberta rotulo="Expectativas" texto={r.expectativas} />
                          <Aberta rotulo="O que mais gostou" texto={r.maisGostou} />
                          <Aberta rotulo="O que melhorar" texto={r.melhorar} />
                          <Aberta rotulo="Comentário" texto={r.comentario} />
                        </dl>
                      </li>
                    ))}
                  </ul>

                  <div className="flex items-center justify-between gap-3 text-sm text-muted-foreground">
                    <span className="tabular-nums">
                      {respostas.total} {respostas.total === 1 ? 'resposta' : 'respostas'} · página{' '}
                      {respostas.pagina} de{' '}
                      {Math.max(1, Math.ceil(respostas.total / respostas.porPagina))}
                    </span>
                    <span className="flex gap-2">
                      <Button
                        variant="outline"
                        size="sm"
                        disabled={pagina <= 1}
                        onClick={() => setPagina((p) => Math.max(1, p - 1))}
                      >
                        Anterior
                      </Button>
                      <Button
                        variant="outline"
                        size="sm"
                        disabled={pagina * respostas.porPagina >= respostas.total}
                        onClick={() => setPagina((p) => p + 1)}
                      >
                        Próxima
                      </Button>
                    </span>
                  </div>
                </>
              )}
            </CardContent>
          </Card>
        </>
      ) : null}
    </div>
  );
}

function Aberta({ rotulo, texto }: { rotulo: string; texto: string | null }) {
  if (!texto) return null;
  return (
    <div>
      <dt className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
        {rotulo}
      </dt>
      <dd className="whitespace-pre-line break-words">{texto}</dd>
    </div>
  );
}
