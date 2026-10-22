import { useEffect, useMemo, useState } from 'react';
import { AlertTriangle, Bot, Database, History, Plus, Radio, ShieldCheck } from 'lucide-react';
import type { AgentChannel, AgentIntelligenceAccess, AgentKitBlock, AgentPrompt } from '@/contracts';
import { useAtualizar, useCriar, useItem, useLista } from '@/hooks/use-recurso';
import { useSessao } from '@/hooks/use-sessao';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { DialogoConfirmacao } from '@/components/admin/dialogos';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Textarea } from '@/components/ui/textarea';

/* ============================================================
   AGENT INTELLIGENCE
   ============================================================
   Cada agente num lugar só: o conhecimento que ele pode usar, o kit que
   recebe, os canais em que atende e os prompts que o guiam. A matriz
   completa (todos os agentes × todo o conhecimento) continua na outra aba.

   Canais, kit e prompts mudam o comportamento do agente na hora: só
   administrador edita (Adriana, 22/10/2026). O banco confere de novo. */

const ORDEM_NAMESPACE: AgentIntelligenceAccess['namespace'][] = ['global', 'business', 'customer'];

const ROTULO_NAMESPACE: Record<AgentIntelligenceAccess['namespace'], string> = {
  global: 'Global Knowledge',
  business: 'Business Intelligence',
  customer: 'Customer Intelligence',
};

const ROTULO_AGENTE: Record<string, string> = {
  concierge_summit: 'Concierge Summit',
  summit_b2c: 'Summit B2C',
  summit_b2b: 'Summit B2B',
  institute: 'Institute',
  dash: 'Dash',
  cliente_suporte: 'Suporte',
  mia_summit_2026: 'MIA Summit 2026',
};

const ROTULO_CANAL: Record<string, string> = {
  'mindagent-web': 'App (web)',
  whatsapp: 'WhatsApp',
};

const ROTULO_SECAO: Record<string, string> = {
  structured: 'Informação do banco',
  knowledge: 'Conhecimento',
  tools: 'Ferramenta',
  decisioning: 'Decisioning',
};

export function rotuloAgente(chave: string) {
  return ROTULO_AGENTE[chave] ?? chave;
}

function rotuloCanal(canal: string) {
  return ROTULO_CANAL[canal] ?? canal;
}

function MensagemErro({ texto }: { texto: string | null }) {
  if (!texto) return null;
  return <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800">{texto}</div>;
}

function mensagemDe(e: unknown) {
  return e instanceof Error ? e.message : 'Não foi possível salvar.';
}

export function PaginaAgentIntelligence() {
  const matriz = useLista('agent_intelligence_access', { porPagina: 500 });
  const canais = useLista('agent_channels', { porPagina: 500 });
  const kit = useLista('agent_kit_blocks', { porPagina: 500 });
  const prompts = useLista('agent_prompts', { porPagina: 500 });

  /* Agente é o que tem canal, kit ou linha na matriz. `knowledge_admin` é a
     persona técnica do playground de busca, não um agente que conversa. */
  const agentes = useMemo(() => {
    const chaves = new Set<string>();
    for (const x of matriz.data?.itens ?? []) if (x.agentKey !== 'knowledge_admin') chaves.add(x.agentKey);
    for (const x of canais.data?.itens ?? []) chaves.add(x.rota);
    for (const x of kit.data?.itens ?? []) chaves.add(x.rota);
    return Array.from(chaves).sort((a, b) => rotuloAgente(a).localeCompare(rotuloAgente(b), 'pt-BR'));
  }, [matriz.data, canais.data, kit.data]);

  const [escolhido, setEscolhido] = useState<string | null>(null);
  const agente = escolhido && agentes.includes(escolhido) ? escolhido : agentes[0] ?? null;

  const carregando = matriz.isLoading || canais.isLoading || kit.isLoading || prompts.isLoading;
  const erroLeitura = [matriz.error, canais.error, kit.error, prompts.error].find(Boolean);

  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Agent Intelligence"
        descricao="Cada agente em um lugar só: o conhecimento que ele pode usar, o kit que recebe, os canais em que atende e os prompts que o guiam."
      />

      {carregando ? <div className="text-sm text-muted-foreground">Carregando Agent Intelligence…</div> : null}
      {erroLeitura ? (
        <MensagemErro texto={erroLeitura instanceof Error ? erroLeitura.message : 'Erro ao carregar Agent Intelligence.'} />
      ) : null}

      {!carregando && !erroLeitura ? (
        <Tabs defaultValue="agente">
          <TabsList>
            <TabsTrigger value="agente">Por agente</TabsTrigger>
            <TabsTrigger value="matriz">Matriz de conhecimento</TabsTrigger>
          </TabsList>

          <TabsContent value="agente" className="space-y-4 pt-4">
            {agentes.length === 0 ? (
              <div className="text-sm text-muted-foreground">Nenhum agente cadastrado.</div>
            ) : (
              <>
                <div className="flex flex-wrap gap-2" role="group" aria-label="Agentes">
                  {agentes.map((a) => (
                    <Button
                      key={a}
                      size="sm"
                      variant={a === agente ? 'default' : 'outline'}
                      aria-pressed={a === agente}
                      onClick={() => setEscolhido(a)}
                    >
                      {rotuloAgente(a)}
                    </Button>
                  ))}
                </div>
                {agente ? (
                  <PainelDoAgente
                    key={agente}
                    agente={agente}
                    matriz={(matriz.data?.itens ?? []).filter((x) => x.agentKey === agente)}
                    canais={(canais.data?.itens ?? []).filter((x) => x.rota === agente)}
                    kit={kit.data?.itens ?? []}
                    prompts={prompts.data?.itens ?? []}
                  />
                ) : null}
              </>
            )}
          </TabsContent>

          <TabsContent value="matriz" className="pt-4">
            <MatrizCompleta dados={matriz.data?.itens ?? []} />
          </TabsContent>
        </Tabs>
      ) : null}
    </div>
  );
}

/* ------------------------------------------------------------ */
/* Um agente                                                     */
/* ------------------------------------------------------------ */

function PainelDoAgente({
  agente,
  matriz,
  canais,
  kit,
  prompts,
}: {
  agente: string;
  matriz: AgentIntelligenceAccess[];
  canais: AgentChannel[];
  /** O kit de todos os agentes: os blocos dos outros são o catálogo do "acrescentar". */
  kit: AgentKitBlock[];
  prompts: AgentPrompt[];
}) {
  const blocos = kit.filter((b) => b.rota === agente);
  const playbook = prompts.find((p) => p.chave === `playbook_${agente}`);
  const canaisLigados = canais.filter((c) => c.ativo);
  const temInformacao = blocos.some((b) => b.ativo && b.secao === 'structured');

  /* Os mesmos três requisitos que o runtime confere antes de deixar o agente
     atender (mind_rota_capacidade): playbook ligado, kit e canal. */
  const pendencias = [
    !playbook ? 'não tem playbook' : !playbook.ativo ? 'o playbook está desligado' : null,
    !temInformacao ? 'o kit não tem informação do banco ligada' : null,
    canaisLigados.length === 0 ? 'nenhum canal está ligado' : null,
  ].filter((x): x is string => Boolean(x));

  return (
    <div className="space-y-4">
      <Card>
        <CardContent className="flex flex-wrap items-center gap-3 py-4 text-sm">
          <Bot className="size-4 shrink-0" />
          <span className="font-semibold">{rotuloAgente(agente)}</span>
          {pendencias.length === 0 ? (
            <Badge variant="sucesso">Atendendo em {canaisLigados.map((c) => rotuloCanal(c.canal)).join(' e ')}</Badge>
          ) : (
            <>
              <Badge variant="neutro">Não atende</Badge>
              <span className="text-muted-foreground">Porque {pendencias.join(', ')}.</span>
            </>
          )}
        </CardContent>
      </Card>

      <Tabs defaultValue="conhecimento">
        <TabsList>
          <TabsTrigger value="conhecimento">Conhecimento</TabsTrigger>
          <TabsTrigger value="kit">Kit</TabsTrigger>
          <TabsTrigger value="canais">Canais</TabsTrigger>
          <TabsTrigger value="prompts">Prompts</TabsTrigger>
        </TabsList>
        <TabsContent value="conhecimento" className="pt-4">
          <SecaoConhecimento itens={matriz} />
        </TabsContent>
        <TabsContent value="kit" className="pt-4">
          <SecaoKit agente={agente} blocos={blocos} todos={kit} />
        </TabsContent>
        <TabsContent value="canais" className="pt-4">
          <SecaoCanais agente={agente} canais={canais} />
        </TabsContent>
        <TabsContent value="prompts" className="pt-4">
          <SecaoPrompts agente={agente} blocos={blocos} prompts={prompts} />
        </TabsContent>
      </Tabs>
    </div>
  );
}

/* ------------------------------------------------------------ */
/* Conhecimento: a linha deste agente na matriz                  */
/* ------------------------------------------------------------ */

function useAlternarConhecimento() {
  const atualizar = useAtualizar('agent_intelligence_access');
  const [erro, setErro] = useState<string | null>(null);
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
      setErro(mensagemDe(e));
    }
  }
  return { alternar, erro, salvando: atualizar.isPending };
}

function SecaoConhecimento({ itens }: { itens: AgentIntelligenceAccess[] }) {
  const sessao = useSessao();
  const { alternar, erro, salvando } = useAlternarConhecimento();

  return (
    <div className="space-y-4">
      <Card>
        <CardContent className="flex gap-3 py-4 text-sm text-muted-foreground">
          <ShieldCheck className="mt-0.5 size-4 shrink-0" />
          Ligar um conhecimento deixa o agente consultá-lo. Em "Conteúdo do Summit", ligar libera as transcrições e os
          slides das palestras para este agente; desligar tira na hora.
        </CardContent>
      </Card>
      <MensagemErro texto={erro} />
      {ORDEM_NAMESPACE.map((namespace) => {
        const doGrupo = itens
          .filter((x) => x.namespace === namespace)
          .sort((a, b) => a.knowledgeName.localeCompare(b.knowledgeName, 'pt-BR'));
        if (doGrupo.length === 0) return null;
        return (
          <Card key={namespace}>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Database className="size-4" />
                {ROTULO_NAMESPACE[namespace]}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <Table>
                <TableBody>
                  {doGrupo.map((item) => (
                    <TableRow key={item.id}>
                      <TableCell>
                        <div className="font-semibold">{item.knowledgeName}</div>
                        {item.description ? <div className="mt-1 text-xs text-muted-foreground">{item.description}</div> : null}
                      </TableCell>
                      <TableCell className="w-24 text-right">
                        <div className="flex items-center justify-end gap-2">
                          {item.pendingDecision ? <AlertTriangle className="size-3 text-amber-600" aria-label="Há decisão pendente" /> : null}
                          <Switch
                            checked={item.enabled}
                            disabled={!sessao.pode('editar') || salvando}
                            onCheckedChange={(v) => void alternar(item, v)}
                            aria-label={item.knowledgeName}
                          />
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}

/* ------------------------------------------------------------ */
/* Kit                                                           */
/* ------------------------------------------------------------ */

function SecaoKit({ agente, blocos, todos }: { agente: string; blocos: AgentKitBlock[]; todos: AgentKitBlock[] }) {
  const sessao = useSessao();
  const podeEditar = sessao.pode('configurar');
  const atualizar = useAtualizar('agent_kit_blocks');
  const criar = useCriar('agent_kit_blocks');
  const [erro, setErro] = useState<string | null>(null);
  const [novo, setNovo] = useState<string>('');

  /* O que dá para acrescentar: blocos que já existem em outro agente. */
  const catalogo = useMemo(() => {
    const doAgente = new Set(blocos.map((b) => b.bloco));
    const vistos = new Map<string, AgentKitBlock>();
    for (const b of todos) if (!doAgente.has(b.bloco) && !vistos.has(b.bloco)) vistos.set(b.bloco, b);
    return Array.from(vistos.values()).sort((a, b) => a.bloco.localeCompare(b.bloco));
  }, [blocos, todos]);

  async function salvar(bloco: AgentKitBlock, mudanca: { ativo?: boolean; obrigatorio?: boolean }) {
    setErro(null);
    try {
      await atualizar.mutateAsync({ id: bloco.id, payload: mudanca, opcoes: { atualizadoEmEsperado: bloco.atualizadoEm } });
    } catch (e) {
      setErro(mensagemDe(e));
    }
  }

  async function acrescentar() {
    if (!novo) return;
    setErro(null);
    try {
      await criar.mutateAsync({ rota: agente, bloco: novo, ativo: true, obrigatorio: false });
      setNovo('');
    } catch (e) {
      setErro(mensagemDe(e));
    }
  }

  const ordenados = [...blocos].sort((a, b) => a.secao.localeCompare(b.secao) || a.bloco.localeCompare(b.bloco));

  return (
    <div className="space-y-4">
      <MensagemErro texto={erro} />
      <Card>
        <CardHeader>
          <CardTitle>Kit de {rotuloAgente(agente)}</CardTitle>
          <CardDescription>
            O que o agente recebe a cada mensagem. Bloco obrigatório que falha impede o agente de responder; opcional
            que falha é só omitido.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {ordenados.length === 0 ? (
            <div className="text-sm text-muted-foreground">Este agente ainda não tem kit.</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Bloco</TableHead>
                  <TableHead>Tipo</TableHead>
                  <TableHead className="text-center">Obrigatório</TableHead>
                  <TableHead className="text-center">Ligado</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {ordenados.map((b) => (
                  <TableRow key={b.id}>
                    <TableCell>
                      <div className="font-semibold">{b.bloco}</div>
                      <div className="font-mono text-xs text-muted-foreground">{b.provider}</div>
                    </TableCell>
                    <TableCell>
                      <Badge variant="outline">{ROTULO_SECAO[b.secao] ?? b.secao}</Badge>
                    </TableCell>
                    <TableCell className="text-center">
                      <Switch
                        checked={b.obrigatorio}
                        disabled={!podeEditar || atualizar.isPending}
                        onCheckedChange={(v) => void salvar(b, { obrigatorio: v })}
                        aria-label={`${b.bloco}: obrigatório`}
                      />
                    </TableCell>
                    <TableCell className="text-center">
                      <Switch
                        checked={b.ativo}
                        disabled={!podeEditar || atualizar.isPending}
                        onCheckedChange={(v) => void salvar(b, { ativo: v })}
                        aria-label={`${b.bloco}: ligado`}
                      />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {podeEditar && catalogo.length > 0 ? (
        <Card>
          <CardContent className="flex flex-wrap items-end gap-3 py-4">
            <div className="min-w-64 space-y-1">
              <Label>Acrescentar bloco que já existe em outro agente</Label>
              <Select value={novo || undefined} onValueChange={setNovo}>
                <SelectTrigger aria-label="Bloco para acrescentar">
                  <SelectValue placeholder="Escolha um bloco" />
                </SelectTrigger>
                <SelectContent>
                  {catalogo.map((b) => (
                    <SelectItem key={b.bloco} value={b.bloco}>
                      {b.bloco} · {ROTULO_SECAO[b.secao] ?? b.secao}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <Button onClick={() => void acrescentar()} disabled={!novo || criar.isPending}>
              <Plus className="size-4" /> Acrescentar
            </Button>
          </CardContent>
        </Card>
      ) : null}
    </div>
  );
}

/* ------------------------------------------------------------ */
/* Canais                                                        */
/* ------------------------------------------------------------ */

function SecaoCanais({ agente, canais }: { agente: string; canais: AgentChannel[] }) {
  const sessao = useSessao();
  const podeEditar = sessao.pode('configurar');
  const atualizar = useAtualizar('agent_channels');
  const [erro, setErro] = useState<string | null>(null);
  const [pedido, setPedido] = useState<{ canal: AgentChannel; ativo: boolean } | null>(null);

  async function confirmar() {
    if (!pedido) return;
    setErro(null);
    try {
      await atualizar.mutateAsync({
        id: pedido.canal.id,
        payload: { ativo: pedido.ativo },
        opcoes: { atualizadoEmEsperado: pedido.canal.atualizadoEm },
      });
    } catch (e) {
      setErro(mensagemDe(e));
    } finally {
      setPedido(null);
    }
  }

  return (
    <div className="space-y-4">
      <MensagemErro texto={erro} />
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Radio className="size-4" /> Canais de {rotuloAgente(agente)}
          </CardTitle>
          <CardDescription>Ligar um canal deixa o agente atender conversas nele na hora.</CardDescription>
        </CardHeader>
        <CardContent>
          {canais.length === 0 ? (
            <div className="text-sm text-muted-foreground">Este agente não está cadastrado em nenhum canal.</div>
          ) : (
            <Table>
              <TableBody>
                {canais.map((c) => (
                  <TableRow key={c.id}>
                    <TableCell>
                      <div className="font-semibold">{rotuloCanal(c.canal)}</div>
                      {c.observacao ? <div className="mt-1 text-xs text-muted-foreground">{c.observacao}</div> : null}
                    </TableCell>
                    <TableCell className="w-24 text-right">
                      <Switch
                        checked={c.ativo}
                        disabled={!podeEditar || atualizar.isPending}
                        onCheckedChange={(v) => setPedido({ canal: c, ativo: v })}
                        aria-label={`${rotuloAgente(agente)} no ${rotuloCanal(c.canal)}`}
                      />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <DialogoConfirmacao
        aberto={Boolean(pedido)}
        titulo={pedido?.ativo ? 'Ligar este canal?' : 'Desligar este canal?'}
        descricao={
          pedido
            ? pedido.ativo
              ? `${rotuloAgente(agente)} passa a poder atender conversas no ${rotuloCanal(pedido.canal.canal)} agora.`
              : `${rotuloAgente(agente)} deixa de atender no ${rotuloCanal(pedido.canal.canal)} agora.`
            : ''
        }
        rotuloConfirmar={pedido?.ativo ? 'Ligar' : 'Desligar'}
        destrutivo={pedido ? !pedido.ativo : false}
        carregando={atualizar.isPending}
        aoConfirmar={() => void confirmar()}
        aoCancelar={() => setPedido(null)}
      />
    </div>
  );
}

/* ------------------------------------------------------------ */
/* Prompts                                                       */
/* ------------------------------------------------------------ */

function SecaoPrompts({ agente, blocos, prompts }: { agente: string; blocos: AgentKitBlock[]; prompts: AgentPrompt[] }) {
  /* Os prompts que guiam este agente: o playbook dele, os decisionings do
     kit e a base, que entra em toda conversa de todos os agentes. */
  const doAgente = useMemo(() => {
    const decisioning = new Set(blocos.filter((b) => b.secao === 'decisioning').map((b) => b.bloco));
    const lista = prompts.filter(
      (p) => p.chave === `playbook_${agente}` || decisioning.has(p.chave) || p.chave === 'base',
    );
    const peso = (p: AgentPrompt) => (p.chave === `playbook_${agente}` ? 0 : p.chave === 'base' ? 2 : 1);
    return lista.sort((a, b) => peso(a) - peso(b) || a.chave.localeCompare(b.chave));
  }, [agente, blocos, prompts]);

  const [chave, setChave] = useState<string | null>(null);
  const atual = chave && doAgente.some((p) => p.chave === chave) ? chave : doAgente[0]?.chave ?? null;

  if (doAgente.length === 0) {
    return <div className="text-sm text-muted-foreground">Este agente ainda não tem prompt.</div>;
  }

  return (
    <div className="grid gap-4 lg:grid-cols-[16rem_1fr]">
      <div className="flex flex-col gap-2" role="group" aria-label="Prompts do agente">
        {doAgente.map((p) => (
          <Button
            key={p.chave}
            variant={p.chave === atual ? 'default' : 'outline'}
            className="h-auto justify-start whitespace-normal py-2 text-left"
            aria-pressed={p.chave === atual}
            onClick={() => setChave(p.chave)}
          >
            <span className="flex flex-col items-start gap-1">
              <span className="text-sm font-semibold">
                {p.chave === `playbook_${agente}` ? 'Playbook' : p.chave === 'base' ? 'Base (todos os agentes)' : p.chave}
              </span>
              <span className="text-xs opacity-80">
                {p.ativo ? 'ligado' : 'desligado'} · versão {p.versao ?? '—'}
              </span>
            </span>
          </Button>
        ))}
      </div>
      {atual ? <EditorPrompt key={atual} chave={atual} /> : null}
    </div>
  );
}

function EditorPrompt({ chave }: { chave: string }) {
  const sessao = useSessao();
  const podeEditar = sessao.pode('configurar');
  const item = useItem('agent_prompts', chave);
  const atualizar = useAtualizar('agent_prompts');
  const [titulo, setTitulo] = useState('');
  const [conteudo, setConteudo] = useState('');
  const [ativo, setAtivo] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [salvo, setSalvo] = useState(false);
  const [aberta, setAberta] = useState<number | null>(null);

  const prompt = item.data;
  /* O editor recomeça do que está no banco ao abrir e depois de cada salvamento. */
  useEffect(() => {
    if (!prompt) return;
    setTitulo(prompt.titulo ?? '');
    setConteudo(prompt.conteudo ?? '');
    setAtivo(prompt.ativo);
  }, [prompt?.id, prompt?.atualizadoEm]);

  if (item.isLoading) return <div className="text-sm text-muted-foreground">Carregando prompt…</div>;
  if (item.error || !prompt) return <MensagemErro texto={item.error instanceof Error ? item.error.message : 'Prompt não encontrado.'} />;

  const mudou = titulo !== (prompt.titulo ?? '') || conteudo !== (prompt.conteudo ?? '') || ativo !== prompt.ativo;

  async function salvar() {
    if (!prompt) return;
    setErro(null);
    setSalvo(false);
    try {
      await atualizar.mutateAsync({
        id: prompt.id,
        payload: { titulo, conteudo, ativo },
        opcoes: { atualizadoEmEsperado: prompt.atualizadoEm },
      });
      setSalvo(true);
    } catch (e) {
      setErro(mensagemDe(e));
    }
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle className="font-mono text-base">{prompt.chave}</CardTitle>
          <CardDescription>
            Versão {prompt.versao ?? '—'}. Salvar guarda a versão atual no histórico antes de trocar.
            {prompt.usadoPor.length > 0 ? ` Usado por: ${prompt.usadoPor.map(rotuloAgente).join(', ')}.` : ''}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <MensagemErro texto={erro} />
          {salvo && !mudou ? <div className="text-sm text-verde-800">Salvo.</div> : null}
          <div className="space-y-1">
            <Label htmlFor={`titulo-${chave}`}>Título</Label>
            <Input
              id={`titulo-${chave}`}
              value={titulo}
              disabled={!podeEditar}
              onChange={(e) => setTitulo(e.target.value)}
            />
          </div>
          <div className="flex items-center gap-3">
            <Switch
              id={`ativo-${chave}`}
              checked={ativo}
              disabled={!podeEditar}
              onCheckedChange={setAtivo}
            />
            <Label htmlFor={`ativo-${chave}`}>
              {ativo ? 'Ligado: o agente usa este prompt' : 'Desligado: o agente não usa este prompt'}
            </Label>
          </div>
          <div className="space-y-1">
            <Label htmlFor={`conteudo-${chave}`}>Texto</Label>
            <Textarea
              id={`conteudo-${chave}`}
              value={conteudo}
              disabled={!podeEditar}
              onChange={(e) => setConteudo(e.target.value)}
              className="min-h-[28rem] font-mono text-xs leading-relaxed"
            />
            <div className="text-xs text-muted-foreground">{conteudo.length.toLocaleString('pt-BR')} caracteres</div>
          </div>
          {podeEditar ? (
            <div className="flex gap-2">
              <Button onClick={() => void salvar()} disabled={!mudou || atualizar.isPending || conteudo.trim() === ''}>
                Salvar nova versão
              </Button>
              <Button
                variant="outline"
                disabled={!mudou || atualizar.isPending}
                onClick={() => {
                  setTitulo(prompt.titulo ?? '');
                  setConteudo(prompt.conteudo ?? '');
                  setAtivo(prompt.ativo);
                }}
              >
                Descartar mudanças
              </Button>
            </div>
          ) : (
            <div className="text-xs text-muted-foreground">Só administrador edita prompts.</div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <History className="size-4" /> Histórico
          </CardTitle>
          <CardDescription>As versões que este prompt já teve, da mais recente para a mais antiga.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-2">
          {prompt.historico.length === 0 ? (
            <div className="text-sm text-muted-foreground">Ainda não houve edição pelo painel.</div>
          ) : (
            prompt.historico.map((v, i) => (
              <div key={`${v.substituidaEm}-${i}`} className="rounded-md border p-3 text-sm">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-semibold">Versão {v.versao ?? '—'}</span>
                  <Badge variant={v.ativo ? 'sucesso' : 'neutro'}>{v.ativo ? 'ligada' : 'desligada'}</Badge>
                  <span className="text-xs text-muted-foreground">
                    substituída em {new Date(v.substituidaEm).toLocaleString('pt-BR')}
                    {v.substituidaPor ? ` por ${v.substituidaPor}` : ''}
                  </span>
                  <Button size="sm" variant="ghost" onClick={() => setAberta(aberta === i ? null : i)}>
                    {aberta === i ? 'Fechar' : 'Ver texto'}
                  </Button>
                  {podeEditar ? (
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => {
                        setTitulo(v.titulo ?? '');
                        setConteudo(v.conteudo ?? '');
                        setAtivo(v.ativo);
                      }}
                    >
                      Usar esta versão
                    </Button>
                  ) : null}
                </div>
                {aberta === i ? (
                  <pre className="mt-2 max-h-96 overflow-auto whitespace-pre-wrap rounded bg-muted p-2 font-mono text-xs">
                    {v.conteudo ?? ''}
                  </pre>
                ) : null}
              </div>
            ))
          )}
        </CardContent>
      </Card>
    </div>
  );
}

/* ------------------------------------------------------------ */
/* Matriz completa: todos os agentes × todo o conhecimento       */
/* ------------------------------------------------------------ */

function MatrizCompleta({ dados }: { dados: AgentIntelligenceAccess[] }) {
  const sessao = useSessao();
  const { alternar, erro, salvando } = useAlternarConhecimento();

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

  return (
    <div className="space-y-6">
      <Card>
        <CardContent className="flex gap-3 py-4 text-sm text-muted-foreground">
          <ShieldCheck className="mt-0.5 size-4 shrink-0" />
          Customer Intelligence tem uma proteção adicional: habilitar uma knowledge não concede acesso a qualquer cliente. O escopo de pessoa/conta continua sendo imposto na fonte.
        </CardContent>
      </Card>
      <MensagemErro texto={erro} />
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
                                disabled={!sessao.pode('editar') || salvando}
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
  );
}
