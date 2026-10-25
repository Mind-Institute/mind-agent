import { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { BookOpen, CheckCircle2, FileUp, Loader2, Play, SplitSquareVertical } from 'lucide-react';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { useSessao } from '@/hooks/use-sessao';
import {
  abrirPdfOriginal,
  abrirPdfSecao,
  buscarRunIngestao,
  buscarRunsIngestao,
  enviarPdfIngestao,
  gerarChunksFonte,
  mapearFonte,
  processarSecao,
} from '@/services/business-ingestion';

export function PaginaBusinessConsultingIngestion() {
  const { simulada, obterToken, marcarSessaoExpirada } = useSessao();
  const qc = useQueryClient();
  const [arquivo, setArquivo] = useState<File | null>(null);
  const [arrastando, setArrastando] = useState(false);
  const [erroArquivo, setErroArquivo] = useState<string | null>(null);
  const [titulo, setTitulo] = useState('');
  const [autores, setAutores] = useState('');
  const [ano, setAno] = useState('');
  const [runId, setRunId] = useState<string | null>(null);

  const opcoes = async () => {
    const token = await obterToken();
    if (!token) {
      marcarSessaoExpirada();
      throw new Error('Sessão expirada. Entre novamente.');
    }
    return { token };
  };

  const runs = useQuery({
    queryKey: ['business-ingestion','runs'],
    enabled: !simulada,
    queryFn: async () => buscarRunsIngestao(await opcoes()),
    refetchInterval: 20_000,
  });
  const detalhe = useQuery({
    queryKey: ['business-ingestion','run',runId],
    enabled: !simulada && Boolean(runId),
    queryFn: async () => buscarRunIngestao(runId!, await opcoes()),
    refetchInterval: 15_000,
  });

  const upload = useMutation({
    mutationFn: async () => {
      if (!arquivo) throw new Error('Selecione um PDF.');
      return enviarPdfIngestao(arquivo, { titulo, autores, ano }, await opcoes());
    },
    onSuccess: async (r: any) => {
      setRunId(r.run.id);
      await qc.invalidateQueries({queryKey:['business-ingestion']});
    },
  });
  const mapear = useMutation({
    mutationFn: async () => mapearFonte(runId!, await opcoes()),
    onSuccess: async () => qc.invalidateQueries({queryKey:['business-ingestion']}),
  });
  const chunk = useMutation({
    mutationFn: async () => gerarChunksFonte(runId!, await opcoes()),
    onSuccess: async () => qc.invalidateQueries({queryKey:['business-ingestion']}),
  });
  const processar = useMutation({
    mutationFn: async (sectionId:string) => processarSecao(runId!, sectionId, await opcoes()),
    onSuccess: async () => qc.invalidateQueries({queryKey:['business-ingestion']}),
  });

  const selecionado = useMemo(
    () => runs.data?.find((r) => r.id === runId) ?? detalhe.data?.run,
    [runs.data, detalhe.data?.run, runId],
  );

  function selecionarPdf(file: File | null) {
    if (!file) return;
    if (file.type !== 'application/pdf' && !file.name.toLowerCase().endsWith('.pdf')) {
      setErroArquivo('Use um arquivo PDF.');
      return;
    }
    setErroArquivo(null);
    setArquivo(file);
    if (!titulo.trim()) setTitulo(file.name.replace(/\.pdf$/i, '').replace(/[_-]+/g, ' '));
  }

  async function abrirOriginal() {
    if (!selecionado) return;
    window.open(await abrirPdfOriginal(selecionado.source_id, await opcoes()), '_blank', 'noopener,noreferrer');
  }

  async function abrirSecao(id:string) {
    window.open(await abrirPdfSecao(id, await opcoes()), '_blank', 'noopener,noreferrer');
  }

  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Business Consulting · Ingestão"
        descricao="PDF original → mapa do livro → chunks por seção → extração → grounding → normalização → consulting mapping → Red Team."
      />

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><FileUp className="size-4"/>Nova fonte</CardTitle>
          <CardDescription>O PDF original é preservado em Storage privado. Os capítulos são derivados dele e nunca substituem o original.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <label
            className={`flex min-h-40 cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed px-6 py-8 text-center transition-colors ${
              arrastando ? 'border-foreground bg-muted/60' : 'border-muted-foreground/30 hover:bg-muted/30'
            }`}
            onDragEnter={(e) => { e.preventDefault(); setArrastando(true); }}
            onDragOver={(e) => { e.preventDefault(); setArrastando(true); }}
            onDragLeave={(e) => {
              e.preventDefault();
              if (e.currentTarget === e.target) setArrastando(false);
            }}
            onDrop={(e) => {
              e.preventDefault();
              setArrastando(false);
              selecionarPdf(e.dataTransfer.files?.[0] ?? null);
            }}
          >
            <input
              type="file"
              accept="application/pdf,.pdf"
              className="sr-only"
              onChange={(e) => selecionarPdf(e.target.files?.[0] ?? null)}
            />
            <FileUp className="mb-3 size-7 text-muted-foreground" />
            {arquivo ? (
              <>
                <p className="font-bold">{arquivo.name}</p>
                <p className="mt-1 text-sm text-muted-foreground">
                  {(arquivo.size / 1024 / 1024).toFixed(1)} MB · solte outro PDF aqui para trocar
                </p>
              </>
            ) : (
              <>
                <p className="font-bold">Arraste o PDF aqui</p>
                <p className="mt-1 text-sm text-muted-foreground">ou clique para escolher o arquivo</p>
              </>
            )}
          </label>
          {erroArquivo ? <p className="text-sm text-destructive">{erroArquivo}</p> : null}
          <div className="grid gap-3 md:grid-cols-3">
            <Input placeholder="Título do livro" value={titulo} onChange={(e)=>setTitulo(e.target.value)} />
            <Input placeholder="Autor(es)" value={autores} onChange={(e)=>setAutores(e.target.value)} />
            <Input placeholder="Ano" value={ano} onChange={(e)=>setAno(e.target.value)} />
          </div>
          <Button disabled={!arquivo || upload.isPending} onClick={()=>upload.mutate()}>
            {upload.isPending ? <Loader2 className="mr-2 size-4 animate-spin"/> : <FileUp className="mr-2 size-4"/>}
            Salvar PDF original
          </Button>
          {upload.error ? <p className="text-sm text-destructive">{upload.error.message}</p> : null}
        </CardContent>
      </Card>

      <div className="grid gap-4 lg:grid-cols-[320px,1fr]">
        <Card>
          <CardHeader><CardTitle>Runs</CardTitle><CardDescription>Escolha uma ingestão para acompanhar.</CardDescription></CardHeader>
          <CardContent className="space-y-2">
            {(runs.data ?? []).map((r)=>(
              <button key={r.id} type="button" onClick={()=>setRunId(r.id)}
                className="w-full rounded-md border p-3 text-left hover:bg-muted/40">
                <p className="font-semibold">{r.source?.title ?? String(r.metadata.source_title ?? r.source_id)}</p>
                <p className="mt-1 text-xs text-muted-foreground">{r.current_stage ?? r.status}</p>
              </button>
            ))}
            {(runs.data ?? []).length===0 ? <p className="text-sm text-muted-foreground">Nenhuma ingestão nova.</p> : null}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Pipeline da fonte</CardTitle>
            <CardDescription>{selecionado ? String(selecionado.metadata.source_title ?? selecionado.source_id) : 'Selecione um run.'}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-5">
            {selecionado ? (
              <>
                <div className="flex flex-wrap gap-2">
                  <Button variant="outline" onClick={abrirOriginal}><BookOpen className="mr-2 size-4"/>Abrir PDF original</Button>
                  <Button variant="outline" disabled={mapear.isPending} onClick={()=>mapear.mutate()}>
                    {mapear.isPending ? <Loader2 className="mr-2 size-4 animate-spin"/> : <Play className="mr-2 size-4"/>}
                    Mapear capítulos
                  </Button>
                  <Button variant="outline" disabled={chunk.isPending || !(detalhe.data?.sections.length)} onClick={()=>chunk.mutate()}>
                    {chunk.isPending ? <Loader2 className="mr-2 size-4 animate-spin"/> : <SplitSquareVertical className="mr-2 size-4"/>}
                    Gerar chunks
                  </Button>
                </div>

                <div className="space-y-2">
                  {(detalhe.data?.sections ?? []).map((s)=>(
                    <div key={s.id} className="flex flex-wrap items-center justify-between gap-3 rounded-md border p-3">
                      <div>
                        <p className="font-semibold">{s.section_number ? `${s.section_number} · ` : ''}{s.title}</p>
                        <p className="text-xs text-muted-foreground">
                          {s.page_start ? `p. ${s.page_start}${s.page_end && s.page_end!==s.page_start ? `–${s.page_end}` : ''}` : 'páginas não definidas'}
                        </p>
                      </div>
                      <div className="flex items-center gap-2">
                        <Badge variant={s.processing_status==='processed' ? 'sucesso' : 'outline'}>
                          {s.processing_status}
                        </Badge>
                        <Button size="sm" variant="ghost" onClick={()=>void abrirSecao(s.id)}>Abrir chunk</Button>
                        <Button size="sm" disabled={processar.isPending || s.processing_status==='processed'} onClick={()=>processar.mutate(s.id)}>
                          {s.processing_status==='processed' ? <CheckCircle2 className="mr-1 size-4"/> : <Play className="mr-1 size-4"/>}
                          Processar
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>

                {detalhe.data?.stages.length ? (
                  <div>
                    <p className="mb-2 text-xs font-black uppercase tracking-widest text-muted-foreground">Execução</p>
                    <div className="space-y-2">
                      {detalhe.data.stages.map((s)=>(
                        <div key={s.id} className="rounded-md border p-3 text-sm">
                          <div className="flex items-center justify-between gap-2">
                            <strong>{s.stage} · {s.agent_key}</strong>
                            <Badge variant={s.status==='completed' ? 'sucesso' : s.status==='failed' ? 'destructive' : 'neutro'}>{s.status}</Badge>
                          </div>
                          {s.output_summary ? <p className="mt-1 text-muted-foreground">{s.output_summary}</p> : null}
                        </div>
                      ))}
                    </div>
                  </div>
                ) : null}
              </>
            ) : <p className="text-sm text-muted-foreground">Nenhum run selecionado.</p>}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
