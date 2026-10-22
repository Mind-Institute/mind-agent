import { useMemo, useState } from 'react';
import { ArrowRight, DoorOpen, Radio, Route } from 'lucide-react';
import type { Agent, AgentChannel, ChannelEntry } from '@/contracts';
import { useAtualizar, useLista } from '@/hooks/use-recurso';
import { useSessao } from '@/hooks/use-sessao';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { DialogoConfirmacao } from '@/components/admin/dialogos';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { EditorPrompt, registrarNomesDeAgentes, rotuloAgente } from '@/pages/agent-intelligence';

/* ============================================================
   CANAIS E ROTEADOR
   ============================================================
   O que acontece quando uma pessoa chega por cada canal: por onde ela
   entra, quem atende primeiro e para quem o roteador pode passar. Tudo
   com liga/desliga, porque é regra, não agente (Adriana, 22/10/2026).

   O roteador é uma IA pequena com prompt próprio. Ele escolhe, a cada
   mensagem, entre os agentes marcados como "o roteador pode escolher"
   no canal (`agentes.canal_competencia.roteavel`). Uma entrada com porta
   direta (`entradas_diretas`) abre no agente dela sem passar por ele.
   Só administrador edita; o banco confere de novo. */

const CANAIS = [
  {
    canal: 'mindagent-web',
    rotulo: 'App (web)',
    comoChega: 'A pessoa abre o chat dentro de um app da Mind. O app manda o código da entrada (origem_codigo) na abertura da conversa.',
  },
  {
    canal: 'whatsapp',
    rotulo: 'WhatsApp',
    comoChega:
      'A pessoa clica num botão ou popup do site e cai no fluxo de mensagens da Treble. Quando a conversa chega a um agente nosso, o roteador escolhe entre os roteáveis abaixo (frases claramente comerciais vão direto para a venda).',
  },
] as const;

function mensagemDe(e: unknown) {
  return e instanceof Error ? e.message : 'Não foi possível salvar.';
}

function MensagemErro({ texto }: { texto: string | null }) {
  if (!texto) return null;
  return <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800">{texto}</div>;
}

export function PaginaCanais() {
  const canais = useLista('agent_channels', { porPagina: 500 });
  const agentes = useLista('agents', { porPagina: 500 });
  const entradas = useLista('channel_entries', { porPagina: 500 });
  registrarNomesDeAgentes(agentes.data?.itens ?? []);

  const carregando = canais.isLoading || agentes.isLoading || entradas.isLoading;
  const erro = [canais.error, agentes.error, entradas.error].find(Boolean);

  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Canais e Roteador"
        descricao="O que acontece quando uma pessoa chega por cada canal: por onde entra, quem atende primeiro e para quem o roteador pode passar."
      />
      {carregando ? <div className="text-sm text-muted-foreground">Carregando canais…</div> : null}
      {erro ? <MensagemErro texto={erro instanceof Error ? erro.message : 'Erro ao carregar os canais.'} /> : null}
      {!carregando && !erro
        ? CANAIS.map((c) => (
            <SecaoCanal
              key={c.canal}
              rotulo={c.rotulo}
              comoChega={c.comoChega}
              linhas={(canais.data?.itens ?? []).filter((x) => x.canal === c.canal)}
              agentes={agentes.data?.itens ?? []}
              entradas={(entradas.data?.itens ?? []).filter((x) => x.canal === c.canal)}
            />
          ))
        : null}
      {!carregando && !erro ? <SecaoRoteador /> : null}
    </div>
  );
}

function SecaoCanal({
  rotulo,
  comoChega,
  linhas,
  agentes,
  entradas,
}: {
  rotulo: string;
  comoChega: string;
  linhas: AgentChannel[];
  agentes: Agent[];
  entradas: ChannelEntry[];
}) {
  const sessao = useSessao();
  const podeEditar = sessao.pode('configurar');
  const atualizar = useAtualizar('agent_channels');
  const [erro, setErro] = useState<string | null>(null);
  const [pedido, setPedido] = useState<{ linha: AgentChannel; ativo: boolean } | null>(null);
  const [entradasEmEdicao, setEntradasEmEdicao] = useState<Record<string, string>>({});

  const descricaoDe = (rota: string) => agentes.find((a) => a.rota === rota)?.descricao ?? null;
  const ordenadas = useMemo(
    () => [...linhas].sort((a, b) => Number(b.ativo) - Number(a.ativo) || rotuloAgente(a.rota).localeCompare(rotuloAgente(b.rota), 'pt-BR')),
    [linhas],
  );
  /* As portas diretas deste canal: entrada → agente. */
  const portas = useMemo(
    () =>
      linhas
        .flatMap((l) => l.entradasDiretas.map((e) => ({ entrada: e, rota: l.rota, ativo: l.ativo })))
        .sort((a, b) => a.entrada.localeCompare(b.entrada)),
    [linhas],
  );
  const roteaveis = ordenadas.filter((l) => l.ativo && l.roteavel);

  async function salvar(linha: AgentChannel, mudanca: Partial<AgentChannel>) {
    setErro(null);
    try {
      await atualizar.mutateAsync({ id: linha.id, payload: mudanca, opcoes: { atualizadoEmEsperado: linha.atualizadoEm } });
    } catch (e) {
      setErro(mensagemDe(e));
    }
  }

  function entradasDigitadas(linha: AgentChannel) {
    return entradasEmEdicao[linha.id] ?? linha.entradasDiretas.join(', ');
  }

  async function salvarEntradas(linha: AgentChannel) {
    const lista = entradasDigitadas(linha)
      .split(/[,\s]+/)
      .map((e) => e.trim())
      .filter(Boolean);
    await salvar(linha, { entradasDiretas: lista });
    setEntradasEmEdicao((atual) => {
      const { [linha.id]: _descartada, ...resto } = atual;
      return resto;
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Radio className="size-4" /> {rotulo}
        </CardTitle>
        <CardDescription>{comoChega}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        <MensagemErro texto={erro} />

        <section className="space-y-2" aria-label={`Por onde a pessoa chega no ${rotulo}`}>
          <h3 className="flex items-center gap-2 text-sm font-semibold">
            <DoorOpen className="size-4" /> Por onde a pessoa chega e quem atende primeiro
          </h3>
          {entradas.length > 0 ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Entrada</TableHead>
                  <TableHead>Quem atende primeiro</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {entradas.map((e) => (
                  <TableRow key={e.id}>
                    <TableCell>
                      <div className="font-semibold">{e.rotulo ?? e.codigo}</div>
                      <div className="font-mono text-xs text-muted-foreground">{e.codigo}</div>
                      {e.descricao ? <div className="mt-1 text-xs text-muted-foreground">{e.descricao}</div> : null}
                    </TableCell>
                    <TableCell className="text-sm">
                      {e.ativo ? 'Fluxo da Treble; depois, o roteador decide' : <Badge variant="neutro">entrada desligada</Badge>}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : null}
          {portas.length > 0 ? (
            <ul className="space-y-1 text-sm" aria-label={`Portas diretas do ${rotulo}`}>
              {portas.map((p) => (
                <li key={`${p.entrada}-${p.rota}`} className="flex flex-wrap items-center gap-2">
                  <code className="rounded bg-muted px-1.5 py-0.5 text-xs">{p.entrada}</code>
                  <ArrowRight className="size-3 text-muted-foreground" />
                  <span className="font-semibold">{rotuloAgente(p.rota)}</span>
                  <span className="text-muted-foreground">atende direto, sem roteador</span>
                  {!p.ativo ? <Badge variant="neutro">agente desligado neste canal</Badge> : null}
                </li>
              ))}
            </ul>
          ) : null}
          <div className="text-sm text-muted-foreground">
            Qualquer outra entrada: o roteador decide entre{' '}
            {roteaveis.length > 0 ? roteaveis.map((l) => rotuloAgente(l.rota)).join(', ') : 'ninguém (nenhum agente roteável ligado)'}.
          </div>
        </section>

        <section className="space-y-2" aria-label={`Agentes no ${rotulo}`}>
          <h3 className="text-sm font-semibold">Agentes neste canal</h3>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Agente</TableHead>
                <TableHead className="text-center">Atende</TableHead>
                <TableHead className="text-center">Roteador pode escolher</TableHead>
                <TableHead>Entradas que abrem direto nele</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {ordenadas.map((l) => (
                <TableRow key={l.id}>
                  <TableCell>
                    <div className="font-semibold">{rotuloAgente(l.rota)}</div>
                    {descricaoDe(l.rota) ? <div className="mt-1 text-xs text-muted-foreground">{descricaoDe(l.rota)}</div> : null}
                    {l.observacao ? <div className="mt-1 text-xs text-muted-foreground">{l.observacao}</div> : null}
                  </TableCell>
                  <TableCell className="text-center">
                    <Switch
                      checked={l.ativo}
                      disabled={!podeEditar || atualizar.isPending}
                      onCheckedChange={(v) => setPedido({ linha: l, ativo: v })}
                      aria-label={`${rotuloAgente(l.rota)} atende no ${rotulo}`}
                    />
                  </TableCell>
                  <TableCell className="text-center">
                    <Switch
                      checked={l.roteavel}
                      disabled={!podeEditar || atualizar.isPending || !l.ativo}
                      onCheckedChange={(v) => void salvar(l, { roteavel: v })}
                      aria-label={`Roteador pode escolher ${rotuloAgente(l.rota)} no ${rotulo}`}
                    />
                  </TableCell>
                  <TableCell>
                    <div className="flex flex-wrap items-center gap-2">
                      <Label htmlFor={`entradas-${l.id}`} className="sr-only">
                        Entradas diretas de {rotuloAgente(l.rota)} no {rotulo}
                      </Label>
                      <Input
                        id={`entradas-${l.id}`}
                        className="min-w-48 flex-1 font-mono text-xs"
                        placeholder="ex.: mind_summit_app"
                        value={entradasDigitadas(l)}
                        disabled={!podeEditar}
                        onChange={(e) => setEntradasEmEdicao((atual) => ({ ...atual, [l.id]: e.target.value }))}
                      />
                      {podeEditar && entradasEmEdicao[l.id] !== undefined && entradasEmEdicao[l.id] !== l.entradasDiretas.join(', ') ? (
                        <Button size="sm" onClick={() => void salvarEntradas(l)} disabled={atualizar.isPending}>
                          Salvar entradas
                        </Button>
                      ) : null}
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          <div className="text-xs text-muted-foreground">
            "Atende" é o que o canal pode servir (por porta direta, pelo roteador ou quando outro agente passa a conversa).
            "Roteador pode escolher" só vale com "Atende" ligado. Entradas diretas: códigos separados por vírgula; uma
            entrada abre em um agente só.
          </div>
        </section>
      </CardContent>

      <DialogoConfirmacao
        aberto={Boolean(pedido)}
        titulo={pedido?.ativo ? 'Ligar este agente no canal?' : 'Desligar este agente no canal?'}
        descricao={
          pedido
            ? pedido.ativo
              ? `${rotuloAgente(pedido.linha.rota)} passa a poder atender no ${rotulo} agora.`
              : `${rotuloAgente(pedido.linha.rota)} deixa de atender no ${rotulo} agora, inclusive pelas portas diretas e pelo roteador.`
            : ''
        }
        rotuloConfirmar={pedido?.ativo ? 'Ligar' : 'Desligar'}
        destrutivo={pedido ? !pedido.ativo : false}
        carregando={atualizar.isPending}
        aoConfirmar={() => {
          const p = pedido;
          setPedido(null);
          if (p) void salvar(p.linha, { ativo: p.ativo });
        }}
        aoCancelar={() => setPedido(null)}
      />
    </Card>
  );
}

function SecaoRoteador() {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Route className="size-4" /> O roteador
        </CardTitle>
        <CardDescription>
          Uma IA pequena que, a cada mensagem sem porta direta, escolhe qual dos agentes roteáveis do canal responde. Ela não
          responde à pessoa nem vende: só decide. O que ela pode escolher vem dos interruptores acima; este texto diz como
          ela pensa. Ao ligar um agente novo como roteável, descreva aqui quando escolhê-lo.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <EditorPrompt
          chave="router_universal"
          rotuloAtivo={(ativo) => (ativo ? 'Ligado: o roteador usa este texto' : 'Desligado: sem texto, o roteador não decide e o canal fica sem roteamento')}
        />
      </CardContent>
    </Card>
  );
}
