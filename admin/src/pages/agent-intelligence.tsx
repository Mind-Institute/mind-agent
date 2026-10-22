import { useMemo, useState } from 'react';
import { AlertTriangle, Bot, Database, Plug, ShieldCheck } from 'lucide-react';
import type { AgentIntelligenceAccess, AgentRuntime, AgentRuntimeBloco, AgentRuntimeCanal } from '@/contracts';
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

/* Os nomes técnicos de `agentes.canal_competencia` e de `agentes.kit_blocos.secao`. O que não
   está aqui aparece com o nome do banco — nada é escondido por falta de rótulo. */
const ROTULO_CANAL: Record<string, string> = { 'mindagent-web': 'App', whatsapp: 'WhatsApp' };

const ROTULO_SECAO: Record<string, string> = {
  structured: 'Fatos estruturados',
  decisioning: 'Decisioning',
  tools: 'Ferramentas de busca',
};
const ORDEM_SECAO = ['structured', 'decisioning', 'tools'];

/* O motivo é o `reason` do Capability Gate (`mind_rota_capacidade`), o mesmo que o runtime usa. */
const ROTULO_MOTIVO: Record<string, string> = {
  missing_playbook: 'sem playbook',
  missing_kit: 'Kit incompleto',
  canal_incompativel: 'canal desligado',
};

function SeloCanal({ canal }: { canal: AgentRuntimeCanal }) {
  const nome = ROTULO_CANAL[canal.canal] ?? canal.canal;
  if (!canal.ativo) {
    return <Badge variant="neutro" title={canal.observacao ?? undefined}>{nome}: desligado</Badge>;
  }
  if (canal.podeExecutar) {
    return <Badge variant="sucesso" title={canal.observacao ?? undefined}>{nome}: executa</Badge>;
  }
  const motivo = canal.motivo ? ROTULO_MOTIVO[canal.motivo] ?? canal.motivo : 'gate recusa';
  return <Badge variant="atencao" title={canal.observacao ?? undefined}>{nome}: ligado, não executa ({motivo})</Badge>;
}

function BlocosDaSecao({ blocos }: { blocos: AgentRuntimeBloco[] }) {
  return (
    <div className="flex flex-wrap gap-1">
      {blocos.map((b) => (
        <Badge
          key={b.bloco}
          variant={b.ativo ? 'outline' : 'neutro'}
          className={b.ativo ? undefined : 'line-through'}
          title={[b.provider, b.obrigatorio ? 'obrigatório' : 'opcional', b.ativo ? null : 'desligado'].filter(Boolean).join(' · ')}
        >
          {b.bloco}{b.obrigatorio ? ' *' : ''}
        </Badge>
      ))}
    </div>
  );
}

function CartaoAgente({ agente, plugaveis }: { agente: AgentRuntime; plugaveis: Record<string, number> | undefined }) {
  const secoes = useMemo(() => {
    const chaves = Array.from(new Set(agente.kit.map((b) => b.secao)));
    chaves.sort((a, b) => {
      const ia = ORDEM_SECAO.indexOf(a);
      const ib = ORDEM_SECAO.indexOf(b);
      return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib) || a.localeCompare(b);
    });
    return chaves.map((secao) => ({ secao, blocos: agente.kit.filter((b) => b.secao === secao) }));
  }, [agente.kit]);

  const totalPlugavel = plugaveis ? Object.values(plugaveis).reduce((a, b) => a + b, 0) : 0;

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="flex items-center gap-2 text-base">
          <Bot className="size-4" />
          {rotuloAgente(agente.agentKey)}
          <span className="font-mono text-xs font-normal text-muted-foreground">{agente.agentKey}</span>
        </CardTitle>
        <CardDescription>
          {agente.playbook
            ? <>Playbook: {agente.playbook.titulo ?? agente.playbook.chave}{agente.playbook.versao != null ? ` · v${agente.playbook.versao}` : ''}{agente.playbook.ativo ? '' : ' · desligado'}</>
            : 'Sem playbook próprio.'}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4 text-sm">
        <div>
          <div className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">Onde está</div>
          <div className="flex flex-wrap gap-1">
            {agente.canais.length ? agente.canais.map((c) => <SeloCanal key={c.canal} canal={c} />) : <span className="text-muted-foreground">Nenhum canal configurado.</span>}
          </div>
        </div>

        <div>
          <div className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">Lê hoje (Kit da rota)</div>
          {secoes.length ? (
            <div className="space-y-2">
              {secoes.map(({ secao, blocos }) => (
                <div key={secao}>
                  <div className="mb-1 text-xs text-muted-foreground">{ROTULO_SECAO[secao] ?? secao}</div>
                  <BlocosDaSecao blocos={blocos} />
                </div>
              ))}
            </div>
          ) : <span className="text-muted-foreground">Kit vazio.</span>}
        </div>

        <div>
          <div className="mb-1 flex items-center gap-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
            <Plug className="size-3" /> Plugável (matriz abaixo)
          </div>
          {totalPlugavel ? (
            <div className="flex flex-wrap gap-1">
              {ORDEM_NAMESPACE.filter((ns) => plugaveis?.[ns]).map((ns) => (
                <Badge key={ns} variant="roxo">{plugaveis![ns]} {ROTULO_NAMESPACE[ns]}</Badge>
              ))}
            </div>
          ) : <span className="text-muted-foreground">Nada ligado na matriz.</span>}
        </div>
      </CardContent>
    </Card>
  );
}

export function PaginaAgentIntelligence() {
  const runtime = useLista('agent_runtime', { porPagina: 100 });
  const query = useLista('agent_intelligence_access', { porPagina: 500 });
  const atualizar = useAtualizar('agent_intelligence_access');
  const sessao = useSessao();
  const [erro, setErro] = useState<string | null>(null);

  const dados = query.data?.itens ?? [];
  const agentesRuntime = useMemo(
    () => [...(runtime.data?.itens ?? [])].sort((a, b) => rotuloAgente(a.agentKey).localeCompare(rotuloAgente(b.agentKey), 'pt-BR')),
    [runtime.data],
  );
  const agentes = useMemo(
    () => Array.from(new Set(dados.map((x) => x.agentKey)))
      .filter((a) => a !== 'knowledge_admin')
      .sort((a, b) => rotuloAgente(a).localeCompare(rotuloAgente(b), 'pt-BR')),
    [dados],
  );

  /* Quantos itens ligados na matriz, por agente e namespace — o que está "plugável". */
  const plugaveisPorAgente = useMemo(() => {
    const mapa: Record<string, Record<string, number>> = {};
    for (const x of dados) {
      if (!x.enabled) continue;
      mapa[x.agentKey] ??= {};
      mapa[x.agentKey][x.namespace] = (mapa[x.agentKey][x.namespace] ?? 0) + 1;
    }
    return mapa;
  }, [dados]);

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
        descricao="Os agentes que existem, onde cada um está, o que ele lê de verdade hoje e o que está só plugável."
      />

      <section className="space-y-3" aria-label="Agentes">
        <h2 className="text-lg font-semibold">Agentes — o que lê hoje</h2>
        <p className="text-sm text-muted-foreground">
          Lido do banco: canais em <span className="font-mono">agentes.canal_competencia</span> (com o veredito do Capability Gate)
          e o Kit em <span className="font-mono">agentes.kit_blocos</span>. É isso que o agente recebe no turno. Blocos com * são obrigatórios.
        </p>
        {runtime.isLoading ? <div className="text-sm text-muted-foreground">Carregando agentes…</div> : null}
        {runtime.error ? (
          <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800">
            {runtime.error instanceof Error ? runtime.error.message : 'Erro ao carregar os agentes.'}
          </div>
        ) : null}
        {!runtime.isLoading && !runtime.error ? (
          agentesRuntime.length ? (
            <div className="grid gap-4 lg:grid-cols-2">
              {agentesRuntime.map((a) => <CartaoAgente key={a.agentKey} agente={a} plugaveis={plugaveisPorAgente[a.agentKey]} />)}
            </div>
          ) : <div className="text-sm text-muted-foreground">Nenhum agente configurado.</div>
        ) : null}
      </section>

      <section className="space-y-3" aria-label="Plugável">
        <h2 className="flex items-center gap-2 text-lg font-semibold"><Plug className="size-4" /> Plugável — ainda não conectado ao runtime</h2>
        <Card>
          <CardContent className="flex gap-3 py-4 text-sm text-amber-900">
            <AlertTriangle className="mt-0.5 size-4 shrink-0" />
            Esta matriz é configuração. Ligar um item aqui ainda não faz nenhum agente lê-lo: a busca que usa a matriz
            (<span className="font-mono">mind_knowledge_buscar_global</span>) não é chamada por nenhum agente hoje.
          </CardContent>
        </Card>
        <Card>
          <CardContent className="flex gap-3 py-4 text-sm text-muted-foreground">
            <ShieldCheck className="mt-0.5 size-4 shrink-0" />
            Customer Intelligence tem uma proteção adicional: habilitar uma knowledge não concede acesso a qualquer cliente. O escopo de pessoa/conta continua sendo imposto na fonte.
          </CardContent>
        </Card>

        {query.isLoading ? <div className="text-sm text-muted-foreground">Carregando a matriz…</div> : null}
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
                              {exemplar.sensitivity ? <Badge variant={exemplar.sensitivity === 'sensitive' ? 'destructive' : exemplar.sensitivity === 'personal' ? 'atencao' : 'secondary'}>{exemplar.sensitivity}</Badge> : null}
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
      </section>
    </div>
  );
}
