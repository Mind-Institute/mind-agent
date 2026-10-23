import { useMemo, useState } from 'react';
import { Scale } from 'lucide-react';
import type { PesoMia, SummitPeso } from '@/contracts';
import { PESOS_MIA, ROTULO_PESO } from '@/contracts';
import { useAtualizar, useLista } from '@/hooks/use-recurso';
import { useSessao } from '@/hooks/use-sessao';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';

/* ============================================================
   PESOS PARA A MIA — quem pesa mais num resumo do Summit
   ============================================================
   Três níveis por palestrante e por sessão (principal, relevante,
   complementar). A busca da MIA pondera o score pelo peso efetivo da
   sessão (o maior entre o dela e o dos seus palestrantes) e o agente vê
   o peso em cada resultado. A sugestão inicial veio de uma regra
   (destaque, tipo de sessão) em 22/10/2026; a Adriana confirma ou troca
   aqui. */

const TIPOS_SEM_CONTEUDO = new Set(['almoco', 'intervalo', 'credenciamento', 'autografos']);

function mensagemDe(e: unknown) {
  return e instanceof Error ? e.message : 'Não foi possível salvar o peso.';
}

function SeletorPeso({ item, disabled, aoTrocar }: { item: SummitPeso; disabled: boolean; aoTrocar: (peso: PesoMia) => void }) {
  return (
    <Select value={item.peso} onValueChange={(v) => aoTrocar(v as PesoMia)} disabled={disabled}>
      <SelectTrigger className="h-8 w-40" aria-label={`Peso de ${item.nome}`}>
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {PESOS_MIA.map((p) => (
          <SelectItem key={p} value={p}>{ROTULO_PESO[p]}</SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

export function PesosParaMia() {
  const sessao = useSessao();
  const podeEditar = sessao.pode('configurar');
  const lista = useLista('summit_pesos', { porPagina: 500 });
  const atualizar = useAtualizar('summit_pesos');
  const [busca, setBusca] = useState('');
  const [erro, setErro] = useState<string | null>(null);

  const itens = lista.data?.itens ?? [];
  const filtro = busca.trim().toLowerCase();
  const combina = (x: SummitPeso) => !filtro || `${x.nome} ${x.detalhe ?? ''}`.toLowerCase().includes(filtro);
  const palestrantes = useMemo(
    () => itens.filter((x) => x.tipo === 'palestrante' && x.sessoes.length > 0 && combina(x))
      .sort((a, b) => a.nome.localeCompare(b.nome, 'pt-BR')),
    [itens, filtro],
  );
  const sessoes = useMemo(
    () => itens.filter((x) => x.tipo === 'sessao' && !TIPOS_SEM_CONTEUDO.has(x.tipoSessao ?? '') && combina(x))
      .sort((a, b) => (a.detalhe ?? '').localeCompare(b.detalhe ?? '', 'pt-BR') || a.nome.localeCompare(b.nome, 'pt-BR')),
    [itens, filtro],
  );

  async function trocar(item: SummitPeso, peso: PesoMia) {
    setErro(null);
    try {
      await atualizar.mutateAsync({ id: item.id, payload: { peso } });
    } catch (e) {
      setErro(mensagemDe(e));
    }
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><Scale className="size-4" /> Pesos para a MIA</CardTitle>
          <CardDescription>
            Quem pesa mais quando alguém pede um resumo ou uma indicação. A busca da MIA dá prioridade ao que é
            principal e deixa o complementar para quando a pergunta pede. O peso de uma sessão vale o maior entre o
            dela e o dos seus palestrantes. A sugestão inicial veio de uma regra (destaque, tipo de sessão): confirme ou
            troque aqui.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {!podeEditar ? <div className="text-sm text-muted-foreground">Só administrador troca os pesos.</div> : null}
          {erro ? <div className="text-sm text-destructive">{erro}</div> : null}
          <Input
            value={busca}
            onChange={(e) => setBusca(e.target.value)}
            placeholder="Filtrar por nome, cargo ou tipo de sessão"
            aria-label="Filtrar pesos"
          />
          {lista.isLoading ? <div className="text-sm text-muted-foreground">Carregando pesos…</div> : null}
          {lista.error ? <div className="text-sm text-destructive">Não foi possível carregar os pesos.</div> : null}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Palestrantes ({palestrantes.length})</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Palestrante</TableHead>
                <TableHead>Sessões</TableHead>
                <TableHead className="w-44">Peso</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {palestrantes.map((p) => (
                <TableRow key={p.id}>
                  <TableCell>
                    <div className="font-semibold">{p.nome}</div>
                    {p.detalhe ? <div className="text-xs text-muted-foreground">{p.detalhe}</div> : null}
                    <div className="mt-1 flex flex-wrap gap-1">
                      {p.destaque ? <Badge variant="outline">destaque no site</Badge> : null}
                      {p.fichaCurada ? <Badge variant="outline">ficha curada</Badge> : null}
                    </div>
                  </TableCell>
                  <TableCell className="text-xs text-muted-foreground">
                    {p.sessoes.map((s) => `${s.tipo ?? 'sessão'}: ${s.titulo}`).join(' · ')}
                  </TableCell>
                  <TableCell>
                    <SeletorPeso item={p} disabled={!podeEditar || atualizar.isPending} aoTrocar={(peso) => void trocar(p, peso)} />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Sessões ({sessoes.length})</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Sessão</TableHead>
                <TableHead>Palestrantes</TableHead>
                <TableHead className="w-44">Peso</TableHead>
                <TableHead className="w-28">Vale</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {sessoes.map((s) => (
                <TableRow key={s.id}>
                  <TableCell>
                    <div className="font-semibold">{s.nome}</div>
                    <div className="text-xs text-muted-foreground">
                      {s.detalhe}
                      {s.temTranscricao ? '' : ' · sem transcrição'}
                    </div>
                  </TableCell>
                  <TableCell className="text-xs text-muted-foreground">
                    {s.palestrantes.map((p) => `${p.nome} (${ROTULO_PESO[p.peso].toLowerCase()})`).join(', ')}
                  </TableCell>
                  <TableCell>
                    <SeletorPeso item={s} disabled={!podeEditar || atualizar.isPending} aoTrocar={(peso) => void trocar(s, peso)} />
                  </TableCell>
                  <TableCell>
                    <Badge variant={s.pesoEfetivo === 'principal' ? 'sucesso' : 'outline'}>
                      {ROTULO_PESO[s.pesoEfetivo ?? s.peso]}
                    </Badge>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
