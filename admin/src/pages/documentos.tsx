import { useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { zodResolver } from '@hookform/resolvers/zod';
import { AlertTriangle, RefreshCw } from 'lucide-react';
import {
  AGENTES,
  ROTULO_AGENTE,
  ROTULO_STATUS_INDEXACAO,
  ROTULO_TIPO_DOCUMENTO,
  STATUS_INDEXACAO,
  TIPOS_CONTEUDO_DOCUMENTO,
  documentoFormSchema,
  type Documento,
  type DocumentoForm,
  type ReciboReindexacao,
} from '@/contracts';
import { useLista, useReindexar } from '@/hooks/use-recurso';
import { useSessao } from '@/hooks/use-sessao';
import { useEdicaoRecurso } from '@/features/comum/use-edicao-recurso';
import { formatarDataHora } from '@/lib/format';
import { PaginaListagem, type Coluna } from '@/components/admin/pagina-listagem';
import { DrawerEdicao } from '@/components/admin/drawer-edicao';
import { Campo } from '@/components/admin/campo';
import { SelecaoMultipla } from '@/components/admin/editor-lista';
import { AcoesEditoriais } from '@/components/admin/acoes-editoriais';
import { DialogoConflito } from '@/components/admin/dialogos';
import { EstadoCarregando, EstadoErro, EstadoVazio, Salvando } from '@/components/admin/estados';
import { SeloIndexacao } from '@/components/admin/selos';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

const ID_FORM = 'form-documento';

const PADRAO: DocumentoForm = {
  titulo: '',
  fonteId: '',
  tipoConteudo: 'faq',
  urlOrigem: '',
  previa: '',
  agentes: ['mind_agent'],
  ativo: true,
};

/**
 * Botão de reindexação.
 *
 * Ele NÃO indexa. Enfileira o documento e mostra, em texto, que nada
 * foi indexado — porque um painel que diz "pronto!" sem o pipeline
 * ligado faz o time confiar num índice que não existe.
 */
function BotaoReindexar({
  documentoId,
  aoConcluir,
}: {
  documentoId: string;
  aoConcluir?: (recibo: ReciboReindexacao) => void;
}) {
  const sessao = useSessao();
  const reindexar = useReindexar();

  if (!sessao.pode('reindexar')) return null;

  return (
    <Button
      type="button"
      variant="secondary"
      disabled={reindexar.isPending}
      onClick={() => {
        reindexar.mutate(documentoId, { onSuccess: (recibo) => aoConcluir?.(recibo) });
      }}
    >
      {reindexar.isPending ? <Salvando /> : <RefreshCw />}
      Solicitar reindexação
    </Button>
  );
}

function DrawerDocumento({ id, aoFechar }: { id: string | undefined; aoFechar: () => void }) {
  const sessao = useSessao();
  const fontes = useLista('sources', {});
  const [recibo, setRecibo] = useState<ReciboReindexacao | null>(null);

  const edicao = useEdicaoRecurso<'documents', DocumentoForm>({
    recurso: 'documents',
    id,
    resolver: zodResolver(documentoFormSchema),
    padrao: PADRAO,
    paraFormulario: (d: Documento) => ({
      titulo: d.titulo,
      fonteId: d.fonteId,
      tipoConteudo: d.tipoConteudo,
      urlOrigem: d.urlOrigem,
      previa: d.previa,
      agentes: d.agentes,
      ativo: d.ativo,
    }),
  });

  const { formulario, registro } = edicao;
  const { errors } = formulario.formState;
  const podeEditar = sessao.pode('editar');

  return (
    <>
      <DrawerEdicao
        aberto={Boolean(id)}
        titulo={registro?.titulo || 'Documento'}
        descricao={registro ? ROTULO_STATUS_INDEXACAO[registro.statusIndexacao] : undefined}
        sujo={edicao.sujo}
        salvando={edicao.salvando}
        podeSalvar={podeEditar}
        idFormulario={ID_FORM}
        aoFechar={() => {
          setRecibo(null);
          aoFechar();
        }}
        informacao={
          registro?.indexadoEm
            ? `Indexado pela última vez em ${formatarDataHora(registro.indexadoEm)}.`
            : 'Nunca indexado.'
        }
        acoes={
          registro ? (
            <>
              <BotaoReindexar documentoId={registro.id} aoConcluir={setRecibo} />
              <AcoesEditoriais
                rotulo={registro.titulo}
                salvando={edicao.salvando}
                aoArquivar={() => void edicao.arquivar()}
              />
            </>
          ) : null
        }
      >
        {edicao.carregando ? (
          <EstadoCarregando linhas={6} />
        ) : edicao.erro ? (
          <EstadoErro erro={edicao.erro} aoTentarNovamente={edicao.recarregar} />
        ) : (
          <form
            id={ID_FORM}
            onSubmit={formulario.handleSubmit((v) => void edicao.salvar(v))}
            className="space-y-4"
            noValidate
          >
            {recibo ? (
              <Alert variant="atencao">
                <AlertTriangle />
                <AlertTitle>Pedido registrado — nada foi indexado</AlertTitle>
                <AlertDescription>
                  <p>{recibo.mensagem}</p>
                  <p className="mt-1 text-xs">
                    {ROTULO_STATUS_INDEXACAO[recibo.statusAnterior]} →{' '}
                    {ROTULO_STATUS_INDEXACAO[recibo.statusAtual]} ·{' '}
                    {formatarDataHora(recibo.enfileiradoEm)}
                  </p>
                </AlertDescription>
              </Alert>
            ) : null}

            {registro?.erroIndexacao ? (
              <Alert variant="erro">
                <AlertTriangle />
                <AlertTitle>Erro na última indexação</AlertTitle>
                <AlertDescription>{registro.erroIndexacao}</AlertDescription>
              </Alert>
            ) : null}

            {edicao.sujo ? (
              <Alert variant="atencao">
                <AlertTriangle />
                <AlertTitle>Alterações não salvas</AlertTitle>
                <AlertDescription>Fechar sem salvar descarta o que foi editado.</AlertDescription>
              </Alert>
            ) : null}

            <fieldset disabled={!podeEditar} className="space-y-4">
              <Campo rotulo="Título" obrigatorio erro={errors.titulo?.message}>
                {(p) => <Input {...p} {...formulario.register('titulo')} />}
              </Campo>

              <div className="grid gap-4 sm:grid-cols-2">
                <Campo rotulo="Fonte" obrigatorio erro={errors.fonteId?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('fonteId')}
                      onValueChange={(v) => formulario.setValue('fonteId', v, { shouldDirty: true })}
                    >
                      <SelectTrigger id={p.id} aria-invalid={p['aria-invalid']}>
                        <SelectValue placeholder="Escolha a fonte" />
                      </SelectTrigger>
                      <SelectContent>
                        {(fontes.data?.itens ?? []).map((f) => (
                          <SelectItem key={f.id} value={f.id}>
                            {f.nome}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>
                <Campo rotulo="Tipo de conteúdo" erro={errors.tipoConteudo?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('tipoConteudo')}
                      onValueChange={(v) =>
                        formulario.setValue('tipoConteudo', v as DocumentoForm['tipoConteudo'], {
                          shouldDirty: true,
                        })
                      }
                    >
                      <SelectTrigger id={p.id}>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {TIPOS_CONTEUDO_DOCUMENTO.map((t) => (
                          <SelectItem key={t} value={t}>
                            {ROTULO_TIPO_DOCUMENTO[t]}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>
              </div>

              <Campo rotulo="URL de origem" erro={errors.urlOrigem?.message}>
                {(p) => <Input {...p} {...formulario.register('urlOrigem')} />}
              </Campo>

              <Campo
                rotulo="Prévia do conteúdo"
                erro={errors.previa?.message}
                dica="Trecho representativo — é o que aparece na conferência antes de indexar."
              >
                {(p) => <Textarea rows={5} {...p} {...formulario.register('previa')} />}
              </Campo>

              <Campo
                rotulo="Agentes que podem usar"
                obrigatorio
                erro={errors.agentes?.message}
                dica="Um documento do comercial não precisa chegar ao chat do participante."
              >
                {(p) => (
                  <SelecaoMultipla
                    id={p.id}
                    colunas={1}
                    opcoes={AGENTES.map((a) => ({ valor: a, rotulo: ROTULO_AGENTE[a] }))}
                    valor={formulario.watch('agentes')}
                    aoMudar={(v) => formulario.setValue('agentes', v, { shouldDirty: true })}
                  />
                )}
              </Campo>

              <div className="flex items-center gap-3">
                <Switch
                  id="documento-ativo"
                  checked={formulario.watch('ativo')}
                  onCheckedChange={(v) => formulario.setValue('ativo', v, { shouldDirty: true })}
                />
                <Label htmlFor="documento-ativo">Documento ativo</Label>
              </div>
            </fieldset>
          </form>
        )}
      </DrawerEdicao>

      <DialogoConflito
        aberto={edicao.conflito}
        aoRecarregar={edicao.recarregar}
        aoFechar={edicao.fecharConflito}
      />
    </>
  );
}

export function PaginaDocumentos() {
  const { id } = useParams();
  const navegar = useNavigate();
  const fontes = useLista('sources', {});

  const nomeFonte = useMemo(() => {
    const mapa = new Map((fontes.data?.itens ?? []).map((f) => [f.id, f.nome]));
    return (idFonte: string) => mapa.get(idFonte) ?? idFonte;
  }, [fontes.data]);

  const colunas: Coluna<Documento>[] = [
    {
      chave: 'titulo',
      cabecalho: 'Documento',
      celula: (d) => (
        <div className="min-w-56">
          <p className="font-semibold">{d.titulo}</p>
          <p className="line-clamp-1 text-xs text-muted-foreground">{d.previa}</p>
        </div>
      ),
    },
    { chave: 'fonte', cabecalho: 'Fonte', celula: (d) => nomeFonte(d.fonteId) },
    {
      chave: 'tipo',
      cabecalho: 'Tipo',
      celula: (d) => <Badge variant="outline">{ROTULO_TIPO_DOCUMENTO[d.tipoConteudo]}</Badge>,
    },
    {
      chave: 'agentes',
      cabecalho: 'Agentes',
      celula: (d) => (
        <div className="flex flex-wrap gap-1">
          {d.agentes.map((a) => (
            <Badge key={a} variant="secondary">
              {a === 'treble' ? 'Treble' : 'Mind Agent'}
            </Badge>
          ))}
        </div>
      ),
    },
    {
      chave: 'indexacao',
      cabecalho: 'Indexação',
      celula: (d) => (
        <div className="space-y-1">
          <SeloIndexacao status={d.statusIndexacao} />
          <p className="text-xs text-muted-foreground">
            {d.indexadoEm ? formatarDataHora(d.indexadoEm) : 'nunca indexado'}
          </p>
        </div>
      ),
    },
    {
      chave: 'acao',
      cabecalho: '',
      celula: (d) => (
        <div onClick={(e) => e.stopPropagation()} onKeyDown={(e) => e.stopPropagation()}>
          <BotaoReindexar documentoId={d.id} />
        </div>
      ),
    },
  ];

  return (
    <>
      <PaginaListagem
        recurso="documents"
        titulo="FAQ e documentos"
        descricao="As fontes que alimentam a resposta do agente. Reindexação nesta versão apenas enfileira — nada é indexado de verdade."
        colunas={colunas}
        ordenar="titulo"
        placeholderBusca="Buscar por título, prévia ou URL…"
        destinoItem={(d) => `/documentos/${d.id}`}
        definicoesFiltro={[
          {
            chave: 'fonteId',
            rotulo: 'Fonte',
            opcoes: (fontes.data?.itens ?? []).map((f) => ({ valor: f.id, rotulo: f.nome })),
          },
          {
            chave: 'statusIndexacao',
            rotulo: 'Indexação',
            opcoes: STATUS_INDEXACAO.map((s) => ({ valor: s, rotulo: ROTULO_STATUS_INDEXACAO[s] })),
          },
          {
            chave: 'agente',
            rotulo: 'Agente',
            opcoes: AGENTES.map((a) => ({ valor: a, rotulo: ROTULO_AGENTE[a] })),
          },
          {
            chave: 'tipoConteudo',
            rotulo: 'Tipo',
            opcoes: TIPOS_CONTEUDO_DOCUMENTO.map((t) => ({
              valor: t,
              rotulo: ROTULO_TIPO_DOCUMENTO[t],
            })),
          },
        ]}
        estadoVazio={
          <EstadoVazio
            titulo="Nenhum documento encontrado"
            descricao="Sem documento indexado, o agente responde só com o que está nas tabelas do evento."
          />
        }
        rodape={() => (
          <Card>
            <CardHeader>
              <CardTitle>Fontes</CardTitle>
              <CardDescription>
                De onde os documentos vêm. Cadastrar fonte nova é função da fase de integração.
              </CardDescription>
            </CardHeader>
            <CardContent>
              {fontes.isPending ? (
                <EstadoCarregando linhas={2} />
              ) : (fontes.data?.itens.length ?? 0) === 0 ? (
                <EstadoVazio titulo="Nenhuma fonte cadastrada" />
              ) : (
                <ul className="grid gap-2 md:grid-cols-3">
                  {(fontes.data?.itens ?? []).map((f) => (
                    <li key={f.id} className="rounded-md border p-3">
                      <p className="text-sm font-semibold">{f.nome}</p>
                      <p className="text-xs text-muted-foreground">{f.descricao}</p>
                      <Badge variant="neutro" className="mt-2">
                        {f.tipo}
                      </Badge>
                    </li>
                  ))}
                </ul>
              )}
            </CardContent>
          </Card>
        )}
      />

      <DrawerDocumento id={id} aoFechar={() => navegar('/documentos')} />
    </>
  );
}
