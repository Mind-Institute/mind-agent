import { useMemo, useState } from 'react';
import { MessagesSquare } from 'lucide-react';
import type { AgentConversation } from '@/contracts';
import { useItem, useLista } from '@/hooks/use-recurso';
import { useSessao } from '@/hooks/use-sessao';
import { formatarDataHora } from '@/lib/format';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';

/* ============================================================
   CONVERSAS REAIS DE UM AGENTE
   ============================================================
   As últimas conversas em que o agente respondeu (90 dias), para
   consultar desempenho: o texto (já sem telefone e e-mail: a porta do
   banco mascara), por qual agente cada resposta saiu, as skills usadas e
   a análise pós-conversa. Só administrador vê (Adriana, 22/10/2026). */

const ROTULO_ORIGEM: Record<string, string> = {
  'mindagent-chat': 'App',
  'treble-inbound-agent': 'WhatsApp',
  'mindagent-playground': 'Teste (Playground)',
};

function MensagemErro({ texto }: { texto: string | null }) {
  if (!texto) return null;
  return <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800">{texto}</div>;
}

export function ConversasDoAgente({ agente, rotulo }: { agente: string; rotulo: string }) {
  const sessao = useSessao();
  const podeVer = sessao.pode('configurar');
  const lista = useLista('agent_conversations', { porPagina: 300 }, { enabled: podeVer });
  const [aberta, setAberta] = useState<string | null>(null);

  const doAgente = useMemo(
    () => (lista.data?.itens ?? []).filter((c) => c.rotas.includes(agente) || c.rota === agente),
    [lista.data, agente],
  );

  if (!podeVer) {
    return <div className="text-sm text-muted-foreground">Só administrador vê as conversas reais.</div>;
  }
  if (lista.isLoading) return <div className="text-sm text-muted-foreground">Carregando conversas…</div>;
  if (lista.error) return <MensagemErro texto={lista.error instanceof Error ? lista.error.message : 'Não foi possível carregar as conversas.'} />;

  if (aberta) {
    return <ConversaAberta id={aberta} aoVoltar={() => setAberta(null)} />;
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <MessagesSquare className="size-4" /> Conversas de {rotulo}
        </CardTitle>
        <CardDescription>
          As últimas conversas (90 dias) em que {rotulo} respondeu, da mais recente para a mais antiga. Sem telefone
          nem e-mail. Conversas de teste do Playground aparecem marcadas.
        </CardDescription>
      </CardHeader>
      <CardContent>
        {doAgente.length === 0 ? (
          <div className="text-sm text-muted-foreground">Nenhuma conversa atendida por {rotulo} nos últimos 90 dias.</div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Quando</TableHead>
                <TableHead>Pessoa</TableHead>
                <TableHead>Por onde</TableHead>
                <TableHead>Mensagens</TableHead>
                <TableHead>Agentes</TableHead>
                <TableHead>Skills</TableHead>
                <TableHead>Análise</TableHead>
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {doAgente.map((c) => (
                <TableRow key={c.id} data-testid={`conversa-${c.id}`}>
                  <TableCell className="whitespace-nowrap">{formatarDataHora(c.ultimaAtividade)}</TableCell>
                  <TableCell>{c.primeiroNome ?? '—'}</TableCell>
                  <TableCell>
                    {ROTULO_ORIGEM[c.agente ?? ''] ?? c.canal}
                    {c.teste ? <Badge variant="neutro" className="ml-1">teste</Badge> : null}
                  </TableCell>
                  <TableCell>{c.mensagens}</TableCell>
                  <TableCell className="text-xs">{c.rotas.join(', ')}</TableCell>
                  <TableCell className="text-xs">{c.skills.length > 0 ? c.skills.join(', ') : '—'}</TableCell>
                  <TableCell className="text-xs">{c.analisadores.length > 0 ? c.analisadores.join(', ') : 'ainda não'}</TableCell>
                  <TableCell className="text-right">
                    <Button size="sm" variant="ghost" onClick={() => setAberta(c.id)}>Abrir</Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}

function ConversaAberta({ id, aoVoltar }: { id: string; aoVoltar: () => void }) {
  const item = useItem('agent_conversations', id);
  const conversa: AgentConversation | undefined = item.data;

  return (
    <div className="space-y-4">
      <Button variant="outline" size="sm" onClick={aoVoltar}>← Voltar para a lista</Button>
      {item.isLoading ? <div className="text-sm text-muted-foreground">Carregando conversa…</div> : null}
      {item.error ? <MensagemErro texto={item.error instanceof Error ? item.error.message : 'Não foi possível abrir a conversa.'} /> : null}
      {conversa ? (
        <>
          <Card>
            <CardHeader>
              <CardTitle className="text-base">
                {conversa.primeiroNome ?? 'Pessoa'} · {ROTULO_ORIGEM[conversa.agente ?? ''] ?? conversa.canal}
                {conversa.teste ? <Badge variant="neutro" className="ml-2">teste</Badge> : null}
              </CardTitle>
              <CardDescription>
                De {formatarDataHora(conversa.iniciadaEm)} a {formatarDataHora(conversa.ultimaAtividade)} · {conversa.mensagens} mensagens
                {conversa.rotas.length > 0 ? ` · agentes: ${conversa.rotas.join(', ')}` : ''}
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="space-y-3" role="log" aria-label="Transcrição da conversa">
                {conversa.falas.map((f, i) => (
                  <div key={i} className={`text-sm ${f.papel === 'lead' ? 'text-right' : ''}`}>
                    <div
                      className={`inline-block max-w-[85%] whitespace-pre-wrap rounded-md px-3 py-2 text-left ${
                        f.papel === 'lead' ? 'bg-foreground text-background' : 'bg-muted'
                      }`}
                    >
                      {f.texto ?? ''}
                    </div>
                    <div className="mt-1 text-xs text-muted-foreground">
                      {formatarDataHora(f.criadoEm)}
                      {f.papel === 'agente' && f.rota ? ` · respondeu: ${f.rota}` : ''}
                      {f.papel === 'agente' && f.modelo ? ` · ${f.modelo}` : ''}
                      {f.papel === 'agente' && f.duracaoMs != null ? ` · ${(f.duracaoMs / 1000).toFixed(1)} s` : ''}
                      {f.papel === 'agente' && f.ferramentas.length > 0
                        ? ` · skills: ${f.ferramentas.map((t) => `${t.nome ?? '?'}${t.ok === false ? ' (falhou)' : ''}`).join(', ')}`
                        : ''}
                    </div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-base">Análise pós-conversa</CardTitle>
              <CardDescription>O que a análise automática concluiu desta conversa e gravou. Telefone e e-mail já mascarados.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-3">
              {conversa.analises.length === 0 ? (
                <div className="text-sm text-muted-foreground">Esta conversa ainda não passou pela análise.</div>
              ) : (
                conversa.analises.map((a, i) => (
                  <div key={i} className="rounded-md border p-3 text-sm">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-mono font-semibold">{a.analisador}</span>
                      <span className="text-xs text-muted-foreground">{formatarDataHora(a.analisadoEm)}{a.modelo ? ` · ${a.modelo}` : ''}</span>
                    </div>
                    <pre className="mt-2 max-h-96 overflow-auto whitespace-pre-wrap rounded bg-muted p-2 font-mono text-xs">
                      {JSON.stringify(a.dados ?? {}, null, 2)}
                    </pre>
                  </div>
                ))
              )}
            </CardContent>
          </Card>
        </>
      ) : null}
    </div>
  );
}
