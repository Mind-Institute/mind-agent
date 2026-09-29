import { useMemo, useState } from 'react';
import { AlertTriangle, Bot, Database, ShieldCheck } from 'lucide-react';
import type { AgentIntelligenceAccess } from '@/contracts';
import { useAtualizar, useLista } from '@/hooks/use-recurso';
import { useSessao } from '@/hooks/use-sessao';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Switch } from '@/components/ui/switch';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';

const ORDEM_NAMESPACE: AgentIntelligenceAccess['namespace'][] = ['global', 'business', 'customer'];

const ROTULO_NAMESPACE: Record<AgentIntelligenceAccess['namespace'], string> = {
  global: 'Global Knowledge',
  business: 'Business Intelligence',
  customer: 'Customer Intelligence',
};

function rotuloAgente(chave: string) {
  const mapa: Record<string, string> = {
    concierge_summit: 'Concierge Summit',
    summit_b2c: 'Summit B2C',
    summit_b2b: 'Summit B2B',
    institute: 'Institute',
    dash: 'Dash',
    cliente_suporte: 'Suporte',
  };
  return mapa[chave] ?? chave;
}

export function PaginaAgentIntelligence() {
  const query = useLista('agent_intelligence_access', { porPagina: 500 });
  const atualizar = useAtualizar('agent_intelligence_access');
  const sessao = useSessao();
  const [erro, setErro] = useState<string | null>(null);

  const dados = query.data?.itens ?? [];
  const agentes = useMemo(
    () => Array.from(new Set(dados.map((x) => x.agentKey)))
      .filter((a) => a !== 'knowledge_admin')
      .sort((a, b) => rotuloAgente(a).localeCompare(rotuloAgente(b), 'pt-BR')),
    [dados],
  );

  const porNamespace = useMemo(() => {
    return ORDEM_NAMESPACE.map((namespace) => {
      const itens = dados.filter((x) => x.namespace === namespace && x.agentKey !== 'knowledge_admin');
      const keys = Array.from(new Set(itens.map((x) => x.knowledgeKey)));
      const linhas = keys.map((key) => {
        const exemplar = itens.find((x) => x.knowledgeKey === key)!;
        return {
          key,
          exemplar,
          cells: new Map(itens.filter((x) => x.knowledgeKey === key).map((x) => [x.agentKey, x])),
        };
      }).sort((a, b) => a.exemplar.knowledgeName.localeCompare(b.exemplar.knowledgeName, 'pt-BR'));
      return { namespace, linhas };
    });
  }, [dados]);

  async function alternar(item: AgentIntelligenceAccess, enabled: boolean) {
    setErro(null);
    try {
      await atualizar.mutateAsync({
        id: item.id,
        payload: {
          enabled,
          priority: item.priority,
          accessMax: item.accessMax,
          customerScope: item.customerScope,
        },
        opcoes: { atualizadoEmEsperado: item.updatedAt },
      });
    } catch (e) {
      setErro(e instanceof Error ? e.message : 'Não foi possível salvar.');
    }
  }

  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Agent Intelligence"
        descricao="Uma visão única de Agent × Knowledge. Aqui você liga ou desliga qualquer knowledge global, de negócio ou de clientes para cada agente."
      />

      <Card>
        <CardContent className="flex gap-3 py-4 text-sm text-muted-foreground">
          <ShieldCheck className="mt-0.5 size-4 shrink-0" />
          Customer Intelligence tem uma proteção adicional: habilitar uma knowledge não concede acesso a qualquer cliente. O escopo de pessoa/conta continua sendo imposto na fonte.
        </CardContent>
      </Card>

      {query.isLoading ? <div className="text-sm text-muted-foreground">Carregando Agent Intelligence…</div> : null}
      {query.error ? (
        <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800">
          {query.error instanceof Error ? query.error.message : 'Erro ao carregar Agent Intelligence.'}
        </div>
      ) : null}
      {erro ? <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800">{erro}</div> : null}

      {!query.isLoading && !query.error ? (
        <div className="space-y-6">
          {porNamespace.map(({ namespace, linhas }) => (
            <Card key={namespace}>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  {namespace === 'global' ? <Database className="size-4" /> : <Bot className="size-4" />}
                  {ROTULO_NAMESPACE[namespace]}
                </CardTitle>
                <CardDescription>
                  {namespace === 'global'
                    ? 'Conhecimento científico e metodológico transversal do Mind.'
                    : namespace === 'business'
                      ? 'Conhecimento de produto, oferta, comercial e operação.'
                      : 'Conhecimento sobre clientes, empresas, conversas, intenção e sinais.'}
                </CardDescription>
              </CardHeader>
              <CardContent>
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="min-w-64">Knowledge</TableHead>
                      {agentes.map((a) => <TableHead key={a} className="text-center">{rotuloAgente(a)}</TableHead>)}
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {linhas.map(({ key, exemplar, cells }) => (
                      <TableRow key={key}>
                        <TableCell>
                          <div className="font-semibold">{exemplar.knowledgeName}</div>
                          <div className="mt-1 text-xs text-muted-foreground">{exemplar.description}</div>
                          <div className="mt-2 flex flex-wrap gap-1">
                            <Badge variant="outline">{exemplar.sourceCount} source{exemplar.sourceCount === 1 ? '' : 's'}</Badge>
                            {exemplar.sensitivity ? <Badge variant={exemplar.sensitivity === 'sensitive' ? 'destrutivo' : exemplar.sensitivity === 'personal' ? 'atencao' : 'secondary'}>{exemplar.sensitivity}</Badge> : null}
                          </div>
                        </TableCell>
                        {agentes.map((agent) => {
                          const item = cells.get(agent);
                          return (
                            <TableCell key={agent} className="text-center">
                              {item ? (
                                <div className="flex flex-col items-center gap-1">
                                  <Switch
                                    checked={item.enabled}
                                    disabled={!sessao.pode('editar') || atualizar.isPending}
                                    onCheckedChange={(v) => void alternar(item, v)}
                                    aria-label={`${rotuloAgente(agent)}: ${exemplar.knowledgeName}`}
                                  />
                                  {item.pendingDecision ? <AlertTriangle className="size-3 text-amber-600" aria-label="Há decisão pendente" /> : null}
                                </div>
                              ) : <span className="text-xs text-muted-foreground">—</span>}
                            </TableCell>
                          );
                        })}
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          ))}
        </div>
      ) : null}
    </div>
  );
}
