import { zodResolver } from '@hookform/resolvers/zod';
import { AlertTriangle, MessageSquareQuote } from 'lucide-react';
import {
  ROTULO_TIPO_ESPACO,
  TIPOS_ESPACO,
  espacoFormSchema,
  type Espaco,
  type EspacoForm,
} from '@/contracts';
import { useLista } from '@/hooks/use-recurso';
import { useSessao } from '@/hooks/use-sessao';
import { useEdicaoRecurso } from '@/features/comum/use-edicao-recurso';
import { DrawerEdicao } from '@/components/admin/drawer-edicao';
import { Campo } from '@/components/admin/campo';
import { EditorDeLista } from '@/components/admin/editor-lista';
import { AcoesEditoriais } from '@/components/admin/acoes-editoriais';
import { DialogoConflito } from '@/components/admin/dialogos';
import { EstadoCarregando, EstadoErro } from '@/components/admin/estados';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

const ID_FORM = 'form-espaco';

const PADRAO: EspacoForm = {
  nome: '',
  slug: '',
  tipo: 'sala',
  aliases: [],
  descricao: '',
  comoChegar: '',
  localPrincipal: '',
  espacoPaiId: null,
  andar: '',
  coordenadaX: null,
  coordenadaY: null,
  acessivel: true,
  observacaoAcessibilidade: '',
  ativo: true,
};

function paraFormulario(e: Espaco): EspacoForm {
  return {
    nome: e.nome,
    slug: e.slug,
    tipo: e.tipo,
    aliases: e.aliases,
    descricao: e.descricao,
    comoChegar: e.comoChegar,
    localPrincipal: e.localPrincipal,
    espacoPaiId: e.espacoPaiId,
    andar: e.andar,
    coordenadaX: e.coordenadaX,
    coordenadaY: e.coordenadaY,
    acessivel: e.acessivel,
    observacaoAcessibilidade: e.observacaoAcessibilidade,
    ativo: e.ativo,
  };
}

export function DrawerEspaco({ id, aoFechar }: { id: string | undefined; aoFechar: () => void }) {
  const sessao = useSessao();
  const espacos = useLista('spaces', { ordenar: 'nome' });

  const edicao = useEdicaoRecurso<'spaces', EspacoForm>({
    recurso: 'spaces',
    id,
    resolver: zodResolver(espacoFormSchema),
    padrao: PADRAO,
    paraFormulario,
  });

  const { formulario, registro } = edicao;
  const { errors } = formulario.formState;
  const podeEditar = sessao.pode('editar');
  const aliases = formulario.watch('aliases');

  return (
    <>
      <DrawerEdicao
        aberto={Boolean(id)}
        titulo={registro?.nome || 'Espaço'}
        descricao={registro ? ROTULO_TIPO_ESPACO[registro.tipo] : undefined}
        sujo={edicao.sujo}
        salvando={edicao.salvando}
        podeSalvar={podeEditar}
        idFormulario={ID_FORM}
        aoFechar={aoFechar}
        acoes={
          registro ? (
            <AcoesEditoriais
              rotulo={registro.nome}
              salvando={edicao.salvando}
              aoArquivar={() => void edicao.arquivar()}
            />
          ) : null
        }
      >
        {edicao.carregando ? (
          <EstadoCarregando linhas={7} />
        ) : edicao.erro ? (
          <EstadoErro erro={edicao.erro} aoTentarNovamente={edicao.recarregar} />
        ) : (
          <form
            id={ID_FORM}
            onSubmit={formulario.handleSubmit((v) => void edicao.salvar(v))}
            className="space-y-4"
            noValidate
          >
            {edicao.sujo ? (
              <Alert variant="atencao">
                <AlertTriangle />
                <AlertTitle>Alterações não salvas</AlertTitle>
                <AlertDescription>Fechar sem salvar descarta o que foi editado.</AlertDescription>
              </Alert>
            ) : null}

            <fieldset disabled={!podeEditar} className="space-y-4">
              <div className="grid gap-4 sm:grid-cols-2">
                <Campo rotulo="Nome" obrigatorio erro={errors.nome?.message}>
                  {(p) => <Input {...p} {...formulario.register('nome')} />}
                </Campo>
                <Campo rotulo="Slug" obrigatorio erro={errors.slug?.message}>
                  {(p) => <Input {...p} {...formulario.register('slug')} />}
                </Campo>
                <Campo rotulo="Tipo" erro={errors.tipo?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('tipo')}
                      onValueChange={(v) =>
                        formulario.setValue('tipo', v as EspacoForm['tipo'], { shouldDirty: true })
                      }
                    >
                      <SelectTrigger id={p.id}>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {TIPOS_ESPACO.map((tipo) => (
                          <SelectItem key={tipo} value={tipo}>
                            {ROTULO_TIPO_ESPACO[tipo]}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>
                <Campo rotulo="Andar" erro={errors.andar?.message}>
                  {(p) => <Input {...p} {...formulario.register('andar')} />}
                </Campo>
              </div>

              {/* Aliases em destaque: é o campo que decide se o agente
                  entende "vou pro palco principal". */}
              <section className="rounded-lg border-2 border-verde-200 bg-verde-50/60 p-4">
                <div className="mb-2 flex items-start gap-2">
                  <MessageSquareQuote className="mt-0.5 size-4 shrink-0 text-verde-700" />
                  <div>
                    <h3 className="text-sm font-black">Aliases</h3>
                    <p className="text-xs text-muted-foreground">
                      Como o participante chama este lugar quando fala com o agente. Sem alias,
                      &ldquo;palco principal&rdquo; não encontra a Arena Mind.
                    </p>
                  </div>
                </div>

                <Campo rotulo="Apelidos reconhecidos" erro={errors.aliases?.message}>
                  {(p) => (
                    <EditorDeLista
                      id={p.id}
                      valor={aliases}
                      aoMudar={(v) => formulario.setValue('aliases', v, { shouldDirty: true })}
                      placeholder="Ex.: palco principal"
                      vazio="Nenhum alias cadastrado."
                    />
                  )}
                </Campo>

                {aliases.length === 0 ? (
                  <p className="mt-2 text-xs font-semibold text-coral-700">
                    Palco ou arena sem alias vira pendência na visão geral.
                  </p>
                ) : null}
              </section>

              <Campo rotulo="Descrição" erro={errors.descricao?.message}>
                {(p) => <Textarea rows={2} {...p} {...formulario.register('descricao')} />}
              </Campo>

              <Campo
                rotulo="Como chegar"
                erro={errors.comoChegar?.message}
                dica="Texto em primeira pessoa, do jeito que o agente vai repetir."
              >
                {(p) => <Textarea rows={3} {...p} {...formulario.register('comoChegar')} />}
              </Campo>

              <div className="grid gap-4 sm:grid-cols-2">
                <Campo rotulo="Local principal" erro={errors.localPrincipal?.message}>
                  {(p) => <Input {...p} {...formulario.register('localPrincipal')} />}
                </Campo>
                <Campo rotulo="Espaço pai" erro={errors.espacoPaiId?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('espacoPaiId') ?? 'nenhum'}
                      onValueChange={(v) =>
                        formulario.setValue('espacoPaiId', v === 'nenhum' ? null : v, {
                          shouldDirty: true,
                        })
                      }
                    >
                      <SelectTrigger id={p.id}>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="nenhum">Nenhum</SelectItem>
                        {(espacos.data?.itens ?? [])
                          .filter((e) => e.id !== id)
                          .map((e) => (
                            <SelectItem key={e.id} value={e.id}>
                              {e.nome}
                            </SelectItem>
                          ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>
                <Campo
                  rotulo="Coordenada X"
                  erro={errors.coordenadaX?.message}
                  dica="Percentual horizontal no mapa (0–100)."
                >
                  {(p) => (
                    <Input
                      type="number"
                      {...p}
                      {...formulario.register('coordenadaX', {
                        setValueAs: (v) => (v === '' || v === null ? null : Number(v)),
                      })}
                    />
                  )}
                </Campo>
                <Campo
                  rotulo="Coordenada Y"
                  erro={errors.coordenadaY?.message}
                  dica="Percentual vertical no mapa (0–100)."
                >
                  {(p) => (
                    <Input
                      type="number"
                      {...p}
                      {...formulario.register('coordenadaY', {
                        setValueAs: (v) => (v === '' || v === null ? null : Number(v)),
                      })}
                    />
                  )}
                </Campo>
              </div>

              <div className="grid gap-4 sm:grid-cols-2">
                <div className="flex items-center gap-3 pt-6">
                  <Switch
                    id="espaco-acessivel"
                    checked={formulario.watch('acessivel')}
                    onCheckedChange={(v) =>
                      formulario.setValue('acessivel', v, { shouldDirty: true })
                    }
                  />
                  <Label htmlFor="espaco-acessivel">Acessível</Label>
                </div>
                <div className="flex items-center gap-3 pt-6">
                  <Switch
                    id="espaco-ativo"
                    checked={formulario.watch('ativo')}
                    onCheckedChange={(v) => formulario.setValue('ativo', v, { shouldDirty: true })}
                  />
                  <Label htmlFor="espaco-ativo">Espaço ativo</Label>
                </div>
              </div>

              <Campo
                rotulo="Observação de acessibilidade"
                erro={errors.observacaoAcessibilidade?.message}
              >
                {(p) => (
                  <Textarea
                    rows={2}
                    {...p}
                    {...formulario.register('observacaoAcessibilidade')}
                  />
                )}
              </Campo>
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
