import { useEffect, useMemo, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { AlertTriangle, Bot, Database, FileText, History, Plus, Radio, ShieldCheck, Sparkles, Wrench } from 'lucide-react';
import type {
  Agent,
  AgentChannel,
  AgentInstructionPart,
  AgentInstructions,
  AgentIntelligenceAccess,
  AgentKitBlock,
  AgentPrompt,
} from '@/contracts';
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
import { enderecoDoKnowledge } from '@/services/provider-context';
import { chaves } from '@/services/query-keys';

/* ============================================================
   AGENT INTELLIGENCE
   ============================================================
   Cada agente num lugar só, como se monta um GPT: as instruções que ele
   recebe (na ordem real), o conhecimento que pode consultar, as skills, os
   dados oficiais e os canais em que atende. A matriz completa (todos os
   agentes × todo o conhecimento) continua na outra aba.

   Tudo isso muda o comportamento do agente na hora: só administrador edita
   (Adriana, 22/10/2026). O banco confere de novo. */

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

/* Os nomes vêm do cadastro (`agentes.rotas`) quando a tela os carrega; a lista
   fixa é só o reserva para o que ainda não está cadastrado. */
const NOMES_CADASTRADOS = new Map<string, string>();

export function registrarNomesDeAgentes(agentes: Agent[]) {
  for (const a of agentes) NOMES_CADASTRADOS.set(a.rota, a.nome);
}

export function rotuloAgente(chave: string) {
  const cadastrado = NOMES_CADASTRADOS.get(chave);
  if (cadastrado) return cadastrado;
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
  const instrucoes = useLista('agent_instructions', { porPagina: 500 });
  const cadastro = useLista('agents', { porPagina: 500 });
  registrarNomesDeAgentes(cadastro.data?.itens ?? []);

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

  const carregando = matriz.isLoading || canais.isLoading || kit.isLoading || prompts.isLoading || instrucoes.isLoading || cadastro.isLoading;
  const erroLeitura = [matriz.error, canais.error, kit.error, prompts.error, instrucoes.error, cadastro.error].find(Boolean);

  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Agent Intelligence"
        descricao="Cada agente em um lugar só: as instruções que ele recebe, o conhecimento que consulta, as skills, os dados oficiais e os canais em que atende."
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
                    instrucoes={(instrucoes.data?.itens ?? []).find((x) => x.rota === agente) ?? null}
                    cadastro={(cadastro.data?.itens ?? []).find((x) => x.rota === agente) ?? null}
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
  instrucoes,
  cadastro,
}: {
  agente: string;
  matriz: AgentIntelligenceAccess[];
  canais: AgentChannel[];
  /** O kit de todos os agentes: os blocos dos outros são o catálogo do "acrescentar". */
  kit: AgentKitBlock[];
  prompts: AgentPrompt[];
  instrucoes: AgentInstructions | null;
  cadastro: Agent | null;
}) {
  const blocos = kit.filter((b) => b.rota === agente);
  const playbook = prompts.find((p) => p.chave === `playbook_${agente}`);
  const canaisLigados = canais.filter((c) => c.ativo);
  const temInformacao = blocos.some((b) => b.ativo && b.secao === 'structured');

  /* Os mesmos requisitos que o runtime confere antes de deixar o agente
     atender: playbook ligado, texto obrigatório presente (mind_agent_instrucoes),
     dados oficiais e canal (mind_rota_capacidade). */
  const textosFaltando = (instrucoes?.faltando ?? []).filter((c) => c !== `playbook_${agente}`);
  const pendencias = [
    !playbook ? 'não tem playbook' : !playbook.ativo ? 'o playbook está desligado' : null,
    textosFaltando.length > 0 ? `falta o texto obrigatório ${textosFaltando.join(', ')}` : null,
    !temInformacao ? 'não tem dados oficiais ligados' : null,
    canaisLigados.length === 0 ? 'nenhum canal está ligado' : null,
  ].filter((x): x is string => Boolean(x));

  return (
    <div className="space-y-4">
      <Card>
        <CardContent className="space-y-3 py-4 text-sm">
          <div className="flex flex-wrap items-center gap-3">
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
          </div>
          {cadastro ? <OQueFaz cadastro={cadastro} /> : null}
        </CardContent>
      </Card>

      <Tabs defaultValue="instrucoes">
        <TabsList>
          <TabsTrigger value="instrucoes">Instruções</TabsTrigger>
          <TabsTrigger value="conhecimento">Conhecimento</TabsTrigger>
          <TabsTrigger value="skills">Skills</TabsTrigger>
          <TabsTrigger value="dados">Dados oficiais</TabsTrigger>
          <TabsTrigger value="canais">Canais</TabsTrigger>
        </TabsList>
        <TabsContent value="instrucoes" className="pt-4">
          <SecaoInstrucoes agente={agente} prompts={prompts} />
        </TabsContent>
        <TabsContent value="conhecimento" className="pt-4">
          <SecaoConhecimento itens={matriz} />
        </TabsContent>
        <TabsContent value="skills" className="pt-4">
          <SecaoSkills agente={agente} blocos={blocos} />
        </TabsContent>
        <TabsContent value="dados" className="pt-4">
          <SecaoKit agente={agente} blocos={blocos} todos={kit} />
        </TabsContent>
        <TabsContent value="canais" className="pt-4">
          <SecaoCanais agente={agente} canais={canais} />
        </TabsContent>
      </Tabs>
    </div>
  );
}

/* "O que este agente faz", nas palavras da Adriana (agentes.rotas.descricao). */
function OQueFaz({ cadastro }: { cadastro: Agent }) {
  const sessao = useSessao();
  const podeEditar = sessao.pode('configurar');
  const atualizar = useAtualizar('agents');
  const [editando, setEditando] = useState(false);
  const [texto, setTexto] = useState(cadastro.descricao ?? '');
  const [erro, setErro] = useState<string | null>(null);

  async function salvar() {
    setErro(null);
    try {
      await atualizar.mutateAsync({ id: cadastro.id, payload: { descricao: texto }, opcoes: { atualizadoEmEsperado: cadastro.atualizadoEm } });
      setEditando(false);
    } catch (e) {
      setErro(mensagemDe(e));
    }
  }

  if (editando) {
    return (
      <div className="space-y-2">
        <MensagemErro texto={erro} />
        <Label htmlFor={`o-que-faz-${cadastro.rota}`}>O que este agente faz</Label>
        <Textarea id={`o-que-faz-${cadastro.rota}`} value={texto} onChange={(e) => setTexto(e.target.value)} className="min-h-20" />
        <div className="flex gap-2">
          <Button size="sm" onClick={() => void salvar()} disabled={atualizar.isPending}>Salvar</Button>
          <Button size="sm" variant="outline" onClick={() => { setTexto(cadastro.descricao ?? ''); setEditando(false); }}>Cancelar</Button>
        </div>
      </div>
    );
  }
  return (
    <div className="flex flex-wrap items-start gap-2 text-muted-foreground">
      <span>{cadastro.descricao ?? 'Ainda sem descrição do que este agente faz.'}</span>
      {podeEditar ? (
        <Button size="sm" variant="ghost" className="h-auto px-1 py-0" onClick={() => setEditando(true)}>
          {cadastro.descricao ? 'Editar' : 'Descrever'}
        </Button>
      ) : null}
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
      <GerarEmbeddingsSummit />
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

/* Sem embedding, um trecho só é achado pelas palavras exatas; com ele, também
   pelo sentido. O indexador pede a chave secreta, então o painel passa pela
   mindagent-knowledge, que confere quem pediu. Cada chamada é uma rodada de
   até 100 trechos; o botão repete até não sobrar nada. */
const RODADAS_MAXIMAS = 40;

function GerarEmbeddingsSummit() {
  const sessao = useSessao();
  const [gerando, setGerando] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  async function gerar() {
    setGerando(true);
    setErro(null);
    setStatus(null);
    let total = 0;
    try {
      const base = enderecoDoKnowledge();
      if (!base) throw new Error('Knowledge API não configurada.');
      const token = await sessao.obterToken();
      if (!token) throw new Error('Sessão ausente.');
      const chave = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim();
      for (let rodada = 0; rodada < RODADAS_MAXIMAS; rodada += 1) {
        const resposta = await fetch(`${base}/admin/knowledge_embeddings`, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
            ...(chave ? { apikey: chave } : {}),
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ schema: 'summit_2026' }),
        });
        const payload = await resposta.json().catch(() => ({})) as { processados?: number; restantes?: boolean; mensagem?: string };
        if (!resposta.ok) throw new Error(payload.mensagem ?? 'Não foi possível gerar embeddings.');
        total += payload.processados ?? 0;
        if (!payload.restantes) {
          setStatus(total === 0 ? 'Nada pendente: todos os trechos já têm embedding.' : `Pronto: ${total} trechos ganharam embedding.`);
          return;
        }
        setStatus(`${total} trechos processados… continuando.`);
      }
      setStatus(`${total} trechos processados nesta vez. Ainda há pendentes: clique de novo.`);
    } catch (e) {
      setErro(`${e instanceof Error ? e.message : 'Não foi possível gerar embeddings.'}${total ? ` (${total} trechos já foram processados.)` : ''}`);
    } finally {
      setGerando(false);
    }
  }

  return (
    <Card>
      <CardContent className="flex flex-col gap-3 py-4 text-sm sm:flex-row sm:items-center sm:justify-between">
        <div className="text-muted-foreground">
          Busca por sentido no conteúdo do Summit: gera os embeddings que faltam nas transcrições e slides. Vale para
          todos os agentes que leem esse conteúdo.
          {status ? <div className="mt-1 text-foreground" role="status">{status}</div> : null}
          <MensagemErro texto={erro} />
        </div>
        <Button variant="outline" className="shrink-0" onClick={() => void gerar()} disabled={gerando || !sessao.pode('editar')}>
          <Sparkles className="mr-2 size-4" />{gerando ? 'Gerando…' : 'Gerar embeddings do Summit'}
        </Button>
      </CardContent>
    </Card>
  );
}

/* ------------------------------------------------------------ */
/* Dados oficiais: os blocos do kit que trazem informação do banco */
/* ------------------------------------------------------------ */

const SECOES_DE_DADOS = new Set(['structured', 'knowledge']);

function SecaoKit({ agente, blocos: doAgente, todos: kitInteiro }: { agente: string; blocos: AgentKitBlock[]; todos: AgentKitBlock[] }) {
  /* Instruções e skills também são blocos do kit, mas têm aba própria. */
  const blocos = doAgente.filter((b) => SECOES_DE_DADOS.has(b.secao));
  const todos = kitInteiro.filter((b) => SECOES_DE_DADOS.has(b.secao));
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
          <CardTitle>Dados oficiais de {rotuloAgente(agente)}</CardTitle>
          <CardDescription>
            Informações do banco que o agente recebe a cada mensagem, como evento e programação. Bloco obrigatório que
            falha impede o agente de responder; opcional que falha é só omitido.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {ordenados.length === 0 ? (
            <div className="text-sm text-muted-foreground">Este agente ainda não recebe dados oficiais.</div>
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
/* Instruções: o que o agente recebe antes de responder          */
/* ------------------------------------------------------------ */

const ROTULO_CAMADA: Record<string, string> = {
  base: 'Regras comuns',
  playbook: 'Playbook',
  instrucoes: 'Instrução',
  decisioning: 'Decisão',
};

function nomeDaParte(p: AgentInstructionPart, agente: string) {
  if (p.camada === 'base') return 'Regras comuns a todos os agentes';
  if (p.camada === 'playbook') return `Playbook de ${rotuloAgente(agente)}`;
  return p.titulo ?? p.chave;
}

/* A mesma montagem que o runtime usa (`mind_agent_instrucoes`), parte a parte.
   Base e playbook se ligam no próprio texto; instruções e decisões se ligam
   por agente, no kit. */
function SecaoInstrucoes({ agente, prompts }: { agente: string; prompts: AgentPrompt[] }) {
  const sessao = useSessao();
  const podeEditar = sessao.pode('configurar');
  const cliente = useQueryClient();
  const item = useItem('agent_instructions', agente);
  const atualizarBloco = useAtualizar('agent_kit_blocks');
  const criar = useCriar('agent_instructions');
  const [erro, setErro] = useState<string | null>(null);
  const [chave, setChave] = useState<string | null>(null);
  const [verTexto, setVerTexto] = useState(false);
  const [desligar, setDesligar] = useState<AgentInstructionPart | null>(null);
  const [copiar, setCopiar] = useState<AgentInstructionPart | null>(null);

  const dados = item.data;
  const partes = dados?.partes ?? [];
  const existe = (c: string) => prompts.some((p) => p.chave === c);
  const atual =
    chave && partes.some((p) => p.chave === chave)
      ? chave
      : (partes.find((p) => p.camada === 'playbook' && existe(p.chave)) ?? partes.find((p) => existe(p.chave)))?.chave ??
        null;
  const parteAtual = partes.find((p) => p.chave === atual) ?? null;

  function recarregar() {
    void cliente.invalidateQueries({ queryKey: chaves.recurso('agent_instructions') });
  }

  async function salvarBloco(p: AgentInstructionPart, ativo: boolean) {
    setErro(null);
    try {
      await atualizarBloco.mutateAsync({
        id: `${agente}::${p.chave}`,
        payload: { ativo },
        opcoes: { atualizadoEmEsperado: p.atualizadoEm },
      });
      recarregar();
    } catch (e) {
      setErro(mensagemDe(e));
    }
  }

  function alternar(p: AgentInstructionPart, ativo: boolean) {
    /* Texto de proteção (obrigatório) só desliga com confirmação. */
    if (!ativo && p.obrigatorio) setDesligar(p);
    else void salvarBloco(p, ativo);
  }

  async function criarVersaoPropria() {
    if (!copiar) return;
    const original = prompts.find((p) => p.chave === copiar.chave);
    const nova = `${copiar.chave}_${agente}`;
    setErro(null);
    try {
      /* Corpo da POST /admin/agent_instructions: não é o formato da leitura. */
      await criar.mutateAsync({
        rota: agente,
        chave: nova,
        titulo: `${original?.titulo ?? copiar.chave} — ${rotuloAgente(agente)}`,
        conteudo: original?.conteudo ?? '',
        substitui: copiar.chave,
      } as unknown as Partial<AgentInstructions>);
      void cliente.invalidateQueries({ queryKey: chaves.recurso('agent_prompts') });
      void cliente.invalidateQueries({ queryKey: chaves.recurso('agent_kit_blocks') });
      setChave(nova);
    } catch (e) {
      setErro(mensagemDe(e));
    } finally {
      setCopiar(null);
    }
  }

  if (item.isLoading) return <div className="text-sm text-muted-foreground">Carregando instruções…</div>;
  if (item.error || !dados) {
    return <MensagemErro texto={item.error instanceof Error ? item.error.message : 'Instruções não encontradas.'} />;
  }

  const rotulo = rotuloAgente(agente);
  const aviso = (p: AgentInstructionPart) =>
    p.camada === 'base'
      ? 'Este texto vale para todos os agentes: mudar aqui muda todos.'
      : p.compartilhadoCom.length > 0
        ? `Este texto também está ligado em: ${p.compartilhadoCom.map(rotuloAgente).join(', ')}. Mudar aqui muda todos eles.`
        : p.camada === 'playbook'
          ? null
          : 'O texto pode ser usado por outros agentes; o liga/desliga da lista vale só para este.';

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <FileText className="size-4" /> O que {rotulo} recebe antes de responder
          </CardTitle>
          <CardDescription>
            Os textos abaixo entram juntos, nesta ordem, a cada mensagem. Depois deles vêm os dados oficiais, as skills,
            o conhecimento consultado e a conversa.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {!dados.ok ? (
            <div className="rounded-md border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
              Hoje {rotulo} não recebe instrução e por isso não responde: falta {dados.faltando.join(', ')}.
            </div>
          ) : null}
          <div className="flex flex-wrap items-center gap-3">
            <Button variant="outline" onClick={() => setVerTexto(!verTexto)} disabled={!dados.ok}>
              {verTexto ? 'Fechar o texto completo' : 'Ver o texto completo que ele recebe'}
            </Button>
            <span className="text-xs text-muted-foreground">{dados.chars.toLocaleString('pt-BR')} caracteres</span>
          </div>
          {verTexto && dados.texto ? (
            <pre
              aria-label="Texto completo das instruções"
              className="max-h-[32rem] overflow-auto whitespace-pre-wrap rounded bg-muted p-3 font-mono text-xs"
            >
              {dados.texto}
            </pre>
          ) : null}
        </CardContent>
      </Card>

      <MensagemErro texto={erro} />

      <div className="grid gap-4 lg:grid-cols-[20rem_1fr]">
        <ol className="space-y-2" aria-label="Partes das instruções">
          {partes.map((p, i) => (
            <li key={p.chave} className={`rounded-md border p-3 ${p.chave === atual ? 'border-foreground' : ''}`}>
              <div className="flex items-start justify-between gap-2">
                <button
                  type="button"
                  className="flex-1 text-left"
                  aria-pressed={p.chave === atual}
                  disabled={!existe(p.chave)}
                  onClick={() => setChave(p.chave)}
                >
                  <div className="text-xs text-muted-foreground">
                    {i + 1}. {ROTULO_CAMADA[p.camada] ?? p.camada}
                    {p.obrigatorio && p.camada === 'instrucoes' ? ' · proteção' : ''}
                  </div>
                  <div className="text-sm font-semibold">{nomeDaParte(p, agente)}</div>
                  <div className="text-xs text-muted-foreground">
                    {!existe(p.chave)
                      ? 'não existe'
                      : `${p.entra ? 'entra' : 'não entra'} · ${p.chars.toLocaleString('pt-BR')} caracteres`}
                  </div>
                </button>
                {p.blocoAtivo !== null ? (
                  <Switch
                    checked={p.blocoAtivo}
                    disabled={!podeEditar || atualizarBloco.isPending}
                    onCheckedChange={(v) => alternar(p, v)}
                    aria-label={`${nomeDaParte(p, agente)}: ligado em ${rotulo}`}
                  />
                ) : null}
              </div>
              {podeEditar && p.camada === 'instrucoes' && !p.chave.endsWith(`_${agente}`) && existe(p.chave) ? (
                <Button size="sm" variant="ghost" className="mt-1 h-auto px-0 py-1" onClick={() => setCopiar(p)}>
                  Criar versão própria de {rotulo}
                </Button>
              ) : null}
            </li>
          ))}
          <li className="rounded-md border border-dashed p-3 text-xs text-muted-foreground">
            <div className="font-semibold">Formato da resposta e travas de segurança</div>
            Definidos no código do runtime: o formato da resposta, quais ferramentas podem rodar, o limite de rodadas e
            o tempo máximo por mensagem. Estão aqui para você saber que existem; não têm interruptor.
          </li>
        </ol>
        {parteAtual && existe(parteAtual.chave) ? (
          <EditorPrompt
            key={parteAtual.chave}
            chave={parteAtual.chave}
            aviso={aviso(parteAtual)}
            rotuloAtivo={(ativo) =>
              parteAtual.camada === 'playbook'
                ? ativo
                  ? `Ligado: ${rotulo} usa este playbook`
                  : `Desligado: sem playbook, ${rotulo} não responde`
                : ativo
                  ? 'Texto ligado em todo agente que o usa'
                  : 'Texto desligado em todo agente que o usa'
            }
            aoSalvar={recarregar}
          />
        ) : null}
      </div>

      <DialogoConfirmacao
        aberto={Boolean(desligar)}
        titulo={`Desligar ${desligar ? nomeDaParte(desligar, agente) : ''}?`}
        descricao={`Este texto é de proteção. Desligado, ${rotulo} deixa de recebê-lo já na próxima mensagem.`}
        rotuloConfirmar="Desligar"
        destrutivo
        carregando={atualizarBloco.isPending}
        aoConfirmar={() => {
          const p = desligar;
          setDesligar(null);
          if (p) void salvarBloco(p, false);
        }}
        aoCancelar={() => setDesligar(null)}
      />

      <DialogoConfirmacao
        aberto={Boolean(copiar)}
        titulo={`Criar versão própria de ${rotulo}?`}
        descricao={
          copiar
            ? `Cria "${copiar.chave}_${agente}" com uma cópia do texto atual, usada só por ${rotulo} e no mesmo estado (ligada ou desligada). O original continua valendo para os outros agentes. Depois é só editar o texto aqui.`
            : ''
        }
        rotuloConfirmar="Criar"
        carregando={criar.isPending}
        aoConfirmar={() => void criarVersaoPropria()}
        aoCancelar={() => setCopiar(null)}
      />
    </div>
  );
}

/* ------------------------------------------------------------ */
/* Skills: as ferramentas que o agente chama sozinho             */
/* ------------------------------------------------------------ */

function SecaoSkills({ agente, blocos }: { agente: string; blocos: AgentKitBlock[] }) {
  const sessao = useSessao();
  const podeEditar = sessao.pode('configurar');
  const atualizar = useAtualizar('agent_kit_blocks');
  const [erro, setErro] = useState<string | null>(null);
  const [aberta, setAberta] = useState<string | null>(null);
  const skills = blocos.filter((b) => b.secao === 'tools').sort((a, b) => a.bloco.localeCompare(b.bloco));

  async function salvar(bloco: AgentKitBlock, ativo: boolean) {
    setErro(null);
    try {
      await atualizar.mutateAsync({ id: bloco.id, payload: { ativo }, opcoes: { atualizadoEmEsperado: bloco.atualizadoEm } });
    } catch (e) {
      setErro(mensagemDe(e));
    }
  }

  return (
    <div className="space-y-4">
      <MensagemErro texto={erro} />
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Wrench className="size-4" /> Skills de {rotuloAgente(agente)}
          </CardTitle>
          <CardDescription>
            O que o agente sabe fazer além de responder: ferramentas que ele chama sozinho quando precisa. A descrição de
            cada uma também é instrução, porque o modelo a lê para decidir quando usar. Uma skill nova precisa de código
            que a execute; aqui se liga, desliga e reescreve a descrição.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {skills.length === 0 ? (
            <div className="text-sm text-muted-foreground">Este agente não usa nenhuma skill.</div>
          ) : (
            skills.map((b) => (
              <div key={b.id} className="rounded-md border p-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="font-mono text-sm font-semibold">{b.bloco}</div>
                  <div className="flex items-center gap-2">
                    <Button size="sm" variant="ghost" onClick={() => setAberta(aberta === b.bloco ? null : b.bloco)}>
                      {aberta === b.bloco ? 'Fechar' : 'Ver e editar a descrição'}
                    </Button>
                    <Switch
                      checked={b.ativo}
                      disabled={!podeEditar || atualizar.isPending}
                      onCheckedChange={(v) => void salvar(b, v)}
                      aria-label={`${b.bloco}: ligada em ${rotuloAgente(agente)}`}
                    />
                  </div>
                </div>
                {aberta === b.bloco ? <EditorFerramenta nome={b.bloco} /> : null}
              </div>
            ))
          )}
        </CardContent>
      </Card>
    </div>
  );
}

function EditorFerramenta({ nome }: { nome: string }) {
  const sessao = useSessao();
  const podeEditar = sessao.pode('configurar');
  const item = useItem('agent_tools', nome);
  const atualizar = useAtualizar('agent_tools');
  const [descricao, setDescricao] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [salvo, setSalvo] = useState(false);
  const ferramenta = item.data;

  useEffect(() => {
    if (ferramenta) setDescricao(ferramenta.descricao ?? '');
  }, [ferramenta?.id, ferramenta?.atualizadoEm]);

  if (item.isLoading) return <div className="mt-2 text-sm text-muted-foreground">Carregando…</div>;
  if (item.error || !ferramenta) {
    return <MensagemErro texto={item.error instanceof Error ? item.error.message : 'Ferramenta não encontrada.'} />;
  }
  const mudou = descricao !== (ferramenta.descricao ?? '');

  async function salvar() {
    if (!ferramenta) return;
    setErro(null);
    setSalvo(false);
    try {
      await atualizar.mutateAsync({
        id: ferramenta.id,
        payload: { descricao },
        opcoes: { atualizadoEmEsperado: ferramenta.atualizadoEm },
      });
      setSalvo(true);
    } catch (e) {
      setErro(mensagemDe(e));
    }
  }

  return (
    <div className="mt-3 space-y-3">
      <MensagemErro texto={erro} />
      {salvo && !mudou ? <div className="text-sm text-verde-800">Salvo.</div> : null}
      <div className="text-xs text-muted-foreground">
        Versão {ferramenta.versao ?? '—'}.
        {ferramenta.usadoPor.length > 0
          ? ` Ligada em: ${ferramenta.usadoPor.map(rotuloAgente).join(', ')}. Mudar a descrição muda todos.`
          : ''}
      </div>
      <div className="space-y-1">
        <Label htmlFor={`descricao-${nome}`}>Descrição</Label>
        <Textarea
          id={`descricao-${nome}`}
          value={descricao}
          disabled={!podeEditar}
          onChange={(e) => setDescricao(e.target.value)}
          className="min-h-32 text-sm"
        />
      </div>
      {podeEditar ? (
        <div className="flex gap-2">
          <Button size="sm" onClick={() => void salvar()} disabled={!mudou || atualizar.isPending || descricao.trim() === ''}>
            Salvar nova descrição
          </Button>
          <Button size="sm" variant="outline" disabled={!mudou} onClick={() => setDescricao(ferramenta.descricao ?? '')}>
            Descartar mudanças
          </Button>
        </div>
      ) : null}
      {ferramenta.historico.length > 0 ? (
        <div className="space-y-2">
          <div className="text-xs font-semibold">Descrições anteriores</div>
          {ferramenta.historico.map((v, i) => (
            <div key={`${v.substituidaEm}-${i}`} className="rounded border p-2 text-xs">
              <div className="flex flex-wrap items-center gap-2 text-muted-foreground">
                Versão {v.versao ?? '—'} · substituída em {new Date(v.substituidaEm).toLocaleString('pt-BR')}
                {v.substituidaPor ? ` por ${v.substituidaPor}` : ''}
                {podeEditar ? (
                  <Button size="sm" variant="outline" className="h-6 px-2" onClick={() => setDescricao(v.conteudo ?? '')}>
                    Usar esta versão
                  </Button>
                ) : null}
              </div>
              <div className="mt-1 whitespace-pre-wrap">{v.conteudo}</div>
            </div>
          ))}
        </div>
      ) : null}
      <details className="text-xs">
        <summary className="cursor-pointer text-muted-foreground">Parâmetros (definidos no código)</summary>
        <pre className="mt-1 max-h-64 overflow-auto rounded bg-muted p-2 font-mono">
          {JSON.stringify(ferramenta.parametros ?? {}, null, 2)}
        </pre>
      </details>
    </div>
  );
}

export function EditorPrompt({
  chave,
  aviso = null,
  rotuloAtivo = (ativo) => (ativo ? 'Ligado: o agente usa este prompt' : 'Desligado: o agente não usa este prompt'),
  aoSalvar,
}: {
  chave: string;
  /** Quem mais é afetado por mudar este texto. */
  aviso?: string | null;
  rotuloAtivo?: (ativo: boolean) => string;
  aoSalvar?: () => void;
}) {
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
      aoSalvar?.();
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
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {aviso ? (
            <div className="rounded-md border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">{aviso}</div>
          ) : null}
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
              {rotuloAtivo(ativo)}
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
