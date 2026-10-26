import { useState } from 'react';
import { ScanSearch } from 'lucide-react';
import type { AnalysisRun } from '@/contracts';
import { useAtualizar, useItem, useLista } from '@/hooks/use-recurso';
import { useSessao } from '@/hooks/use-sessao';
import { formatarDataHora } from '@/lib/format';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Switch } from '@/components/ui/switch';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { EditorPrompt, registrarNomesDeAgentes, rotuloAgente } from '@/pages/agent-intelligence';

/* ============================================================
   ANÁLISE PÓS-CONVERSA
   ============================================================
   O que roda depois de cada conversa (a cada 15 minutos): um classificador
   escolhe os analisadores, cada analisador lê a conversa e grava o que
   concluiu; daí saem as memórias sobre a pessoa, a continuidade comercial
   e o que vai para o HubSpot. Aqui: os prompts (editáveis, com histórico),
   o liga/desliga por agente, as últimas execuções e o que cada uma gravou.
   Só administrador vê as execuções (Adriana, 22/10/2026). */

const PROMPTS_DA_ANALISE: { chave: string; papel: string }[] = [
  { chave: 'analise_classificador', papel: 'Classificador: decide quais analisadores rodam em cada conversa' },
  { chave: 'analise_concierge', papel: 'Analisador: experiência no Summit (app e WhatsApp)' },
  { chave: 'analise_vendas_summit', papel: 'Analisador: conversa comercial do Summit' },
  { chave: 'analise_vendas_institute', papel: 'Analisador: conversa comercial do Institute' },
  { chave: 'analise_vendas_dash', papel: 'Analisador: conversa comercial do Dash' },
  { chave: 'analise_atendimento', papel: 'Analisador: atendimento e pós-venda' },
  { chave: 'analise_contexto_geral', papel: 'Reserva: usado quando o analisador escolhido está desligado' },
];

const ROTULO_ORIGEM: Record<string, string> = {
  'mindagent-chat': 'App',
  'treble-inbound-agent': 'WhatsApp (agente)',
  treble: 'WhatsApp (fluxo da Treble)',
};

function MensagemErro({ texto }: { texto: string | null }) {
  if (!texto) return null;
  return <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800">{texto}</div>;
}

export function PaginaAnalise() {
  const prompts = useLista('agent_prompts', { porPagina: 500 });
  const agentes = useLista('agents', { porPagina: 500 });
  registrarNomesDeAgentes(agentes.data?.itens ?? []);
  const [chave, setChave] = useState<string>('analise_classificador');

  const carregando = prompts.isLoading || agentes.isLoading;
  const erro = [prompts.error, agentes.error].find(Boolean);
  const existe = (c: string) => (prompts.data?.itens ?? []).some((p) => p.chave === c);
  const info = (c: string) => (prompts.data?.itens ?? []).find((p) => p.chave === c);

  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Análise pós-conversa"
        descricao="O que roda depois de cada conversa: a cada 15 minutos, um classificador escolhe os analisadores, cada um lê a conversa e grava o que concluiu. Daí saem as memórias sobre a pessoa, a continuidade comercial e o que vai para o HubSpot."
      />
      {carregando ? <div className="text-sm text-muted-foreground">Carregando…</div> : null}
      {erro ? <MensagemErro texto={erro instanceof Error ? erro.message : 'Erro ao carregar.'} /> : null}
      {!carregando && !erro ? (
        <>
          <SecaoAgentes />

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <ScanSearch className="size-4" /> Os prompts da análise
              </CardTitle>
              <CardDescription>
                Desligar um analisador faz a conversa cair no reserva; com o reserva também desligado, ela é marcada como
                "sem analisador" e sai da fila. Desligar o classificador não desliga a análise: ela assume o analisador
                comercial do Summit.
              </CardDescription>
            </CardHeader>
            <CardContent className="grid gap-4 lg:grid-cols-[20rem_1fr]">
              <div className="flex flex-col gap-2" role="group" aria-label="Prompts da análise">
                {PROMPTS_DA_ANALISE.map((p) => (
                  <Button
                    key={p.chave}
                    variant={p.chave === chave ? 'default' : 'outline'}
                    className="h-auto justify-start whitespace-normal py-2 text-left"
                    aria-pressed={p.chave === chave}
                    disabled={!existe(p.chave)}
                    onClick={() => setChave(p.chave)}
                  >
                    <span className="flex flex-col items-start gap-1">
                      <span className="font-mono text-xs">{p.chave}</span>
                      <span className="text-xs opacity-80">{p.papel}</span>
                      <span className="text-xs opacity-80">
                        {!existe(p.chave) ? 'não existe' : `${info(p.chave)?.ativo ? 'ligado' : 'desligado'} · versão ${info(p.chave)?.versao ?? '—'}`}
                      </span>
                    </span>
                  </Button>
                ))}
              </div>
              {existe(chave) ? (
                <EditorPrompt
                  key={chave}
                  chave={chave}
                  rotuloAtivo={(ativo) => (ativo ? 'Ligado: a análise usa este texto' : 'Desligado: a análise não usa este texto')}
                />
              ) : null}
            </CardContent>
          </Card>

          <SecaoExecucoes />
        </>
      ) : null}
    </div>
  );
}

function SecaoAgentes() {
  const sessao = useSessao();
  const podeEditar = sessao.pode('configurar');
  const agentes = useLista('agents', { porPagina: 500 });
  const atualizar = useAtualizar('agents');
  const [erro, setErro] = useState<string | null>(null);

  async function alternar(id: string, atualizadoEm: string, analisaConversas: boolean) {
    setErro(null);
    try {
      await atualizar.mutateAsync({ id, payload: { analisaConversas }, opcoes: { atualizadoEmEsperado: atualizadoEm } });
    } catch (e) {
      setErro(e instanceof Error ? e.message : 'Não foi possível salvar.');
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Quais agentes têm as conversas analisadas</CardTitle>
        <CardDescription>
          Desligado, as conversas em que o agente respondeu por último não entram na fila. As conversas dos fluxos da
          Treble (WhatsApp sem agente nosso) continuam sendo analisadas.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <MensagemErro texto={erro} />
        <Table>
          <TableBody>
            {(agentes.data?.itens ?? []).map((a) => (
              <TableRow key={a.id}>
                <TableCell>
                  <div className="font-semibold">{a.nome}</div>
                  {a.descricao ? <div className="text-xs text-muted-foreground">{a.descricao}</div> : null}
                </TableCell>
                <TableCell className="w-24 text-right">
                  <Switch
                    checked={a.analisaConversas}
                    disabled={!podeEditar || atualizar.isPending}
                    onCheckedChange={(v) => void alternar(a.id, a.atualizadoEm, v)}
                    aria-label={`Analisar as conversas de ${a.nome}`}
                  />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}

function SecaoExecucoes() {
  const sessao = useSessao();
  const podeVer = sessao.pode('configurar');
  const execucoes = useLista('analysis_runs', { porPagina: 200 }, { enabled: podeVer });
  const [aberta, setAberta] = useState<string | null>(null);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Últimas execuções</CardTitle>
        <CardDescription>As análises dos últimos 30 dias, da mais recente para a mais antiga, e o que cada uma gravou. Sem telefone nem e-mail.</CardDescription>
      </CardHeader>
      <CardContent>
        {!podeVer ? <div className="text-sm text-muted-foreground">Só administrador vê as execuções.</div> : null}
        {podeVer && execucoes.isLoading ? <div className="text-sm text-muted-foreground">Carregando execuções…</div> : null}
        {podeVer && execucoes.error ? <MensagemErro texto={execucoes.error instanceof Error ? execucoes.error.message : 'Não foi possível carregar.'} /> : null}
        {podeVer && aberta ? <ExecucaoAberta id={aberta} aoVoltar={() => setAberta(null)} /> : null}
        {podeVer && !aberta && execucoes.data ? (
          execucoes.data.itens.length === 0 ? (
            <div className="text-sm text-muted-foreground">Nenhuma execução nos últimos 30 dias.</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Quando</TableHead>
                  <TableHead>Analisador</TableHead>
                  <TableHead>Conversa</TableHead>
                  <TableHead>Agente</TableHead>
                  <TableHead>Memórias</TableHead>
                  <TableHead>Continuidade</TableHead>
                  <TableHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {execucoes.data.itens.map((r) => (
                  <TableRow key={r.id} data-testid={`execucao-${r.id}`}>
                    <TableCell className="whitespace-nowrap">{formatarDataHora(r.analisadoEm)}</TableCell>
                    <TableCell className="font-mono text-xs">{r.analisador}</TableCell>
                    <TableCell className="text-xs">{r.primeiroNome ?? '—'} · {ROTULO_ORIGEM[r.agente ?? ''] ?? r.canal}</TableCell>
                    <TableCell className="text-xs">{r.rota ? rotuloAgente(r.rota) : <Badge variant="neutro">fluxo da Treble</Badge>}</TableCell>
                    <TableCell>{r.memoriasGravadas}</TableCell>
                    <TableCell className="text-xs">{r.continuidade ?? '—'}</TableCell>
                    <TableCell className="text-right">
                      <Button size="sm" variant="ghost" onClick={() => setAberta(r.id)}>Abrir</Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )
        ) : null}
      </CardContent>
    </Card>
  );
}

function ExecucaoAberta({ id, aoVoltar }: { id: string; aoVoltar: () => void }) {
  const item = useItem('analysis_runs', id);
  const r: AnalysisRun | undefined = item.data;
  return (
    <div className="space-y-3">
      <Button variant="outline" size="sm" onClick={aoVoltar}>← Voltar para a lista</Button>
      {item.isLoading ? <div className="text-sm text-muted-foreground">Carregando…</div> : null}
      {item.error ? <MensagemErro texto={item.error instanceof Error ? item.error.message : 'Não foi possível abrir.'} /> : null}
      {r ? (
        <>
          <div className="text-sm">
            <span className="font-mono font-semibold">{r.analisador}</span> · {formatarDataHora(r.analisadoEm)}
            {r.modelo ? ` · ${r.modelo}` : ''}{r.promptVersao != null ? ` · prompt v${r.promptVersao}` : ''}
          </div>
          <div className="text-xs font-semibold">O que a análise concluiu</div>
          <pre className="max-h-96 overflow-auto whitespace-pre-wrap rounded bg-muted p-2 font-mono text-xs" aria-label="Conclusão da análise">
            {JSON.stringify(r.dados ?? {}, null, 2)}
          </pre>
          <div className="text-xs font-semibold">Memórias gravadas sobre a pessoa ({r.memorias.length})</div>
          {r.memorias.length === 0 ? (
            <div className="text-sm text-muted-foreground">Nenhuma memória gravada por esta execução.</div>
          ) : (
            <ul className="space-y-1 text-xs" aria-label="Memórias gravadas">
              {r.memorias.map((m, i) => (
                <li key={i} className="rounded border p-2">
                  <span className="font-mono">{m.tipo ?? '?'} · {m.chave ?? '?'}</span> · {m.status ?? '?'}
                  {m.confianca != null ? ` · confiança ${m.confianca}` : ''}
                  <pre className="mt-1 whitespace-pre-wrap font-mono">{JSON.stringify(m.valor ?? null)}</pre>
                </li>
              ))}
            </ul>
          )}
        </>
      ) : null}
    </div>
  );
}
