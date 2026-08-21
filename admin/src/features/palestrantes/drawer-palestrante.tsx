import { zodResolver } from '@hookform/resolvers/zod';
import { AlertTriangle } from 'lucide-react';
import { Link } from 'react-router-dom';
import {
  ROTULO_STATUS_EDITORIAL,
  STATUS_EDITORIAL,
  palestranteFormSchema,
  type Palestrante,
  type PalestranteForm,
} from '@/contracts';
import { useLista, TODAS_AS_OPCOES } from '@/hooks/use-recurso';
import { useSessao } from '@/hooks/use-sessao';
import { useEdicaoRecurso } from '@/features/comum/use-edicao-recurso';
import { PreviaCartaoPalestrante } from './previa-cartao';
import { DrawerEdicao } from '@/components/admin/drawer-edicao';
import { Campo } from '@/components/admin/campo';
import { SelecaoMultipla } from '@/components/admin/editor-lista';
import { AcoesEditoriais, InfoPublicacao } from '@/components/admin/acoes-editoriais';
import { DialogoConflito } from '@/components/admin/dialogos';
import { AvisoErroEscrita } from '@/components/admin/aviso-escrita';
import { EstadoCarregando, EstadoErro } from '@/components/admin/estados';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

const ID_FORM = 'form-palestrante';

const PADRAO: PalestranteForm = {
  nome: '',
  cargo: '',
  organizacao: '',
  biografia: '',
  foto: '',
  temas: [],
  destaque: false,
  status: 'rascunho',
};

function paraFormulario(p: Palestrante): PalestranteForm {
  return {
    nome: p.nome,
    cargo: p.cargo,
    organizacao: p.organizacao,
    biografia: p.biografia,
    foto: p.foto,
    temas: p.temas,
    destaque: p.destaque,
    status: p.status,
  };
}

export function DrawerPalestrante({
  id,
  aoFechar,
}: {
  id: string | undefined;
  aoFechar: () => void;
}) {
  const sessao = useSessao();
  const temas = useLista('themes', TODAS_AS_OPCOES);
  const sessoes = useLista('sessions', TODAS_AS_OPCOES);

  const edicao = useEdicaoRecurso<'speakers', PalestranteForm>({
    recurso: 'speakers',
    id,
    resolver: zodResolver(palestranteFormSchema),
    padrao: PADRAO,
    paraFormulario,
  });

  const { formulario, registro } = edicao;
  const { errors } = formulario.formState;
  const podeEditar = sessao.pode('editar');

  const relacionadas = (sessoes.data?.itens ?? []).filter((s) =>
    registro ? s.palestranteIds.includes(registro.id) : false,
  );

  const valores = formulario.watch();

  return (
    <>
      <DrawerEdicao
        aberto={Boolean(id)}
        titulo={registro?.nome || 'Palestrante'}
        descricao={registro ? ROTULO_STATUS_EDITORIAL[registro.status] : undefined}
        sujo={edicao.sujo}
        salvando={edicao.salvando}
        podeSalvar={podeEditar}
        idFormulario={ID_FORM}
        aoFechar={aoFechar}
        informacao={
          registro ? (
            <InfoPublicacao
              status={registro.status}
              publicadoEm={registro.publicadoEm}
              publicadoPor={registro.publicadoPor}
              atualizadoEm={registro.atualizadoEm}
              atualizadoPor={registro.atualizadoPor}
            />
          ) : null
        }
        acoes={
          registro ? (
            <AcoesEditoriais
              status={registro.status}
              rotulo={registro.nome}
              salvando={edicao.salvando}
              aoPublicar={() => void edicao.publicar()}
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
          <Tabs defaultValue="dados">
            <TabsList>
              <TabsTrigger value="dados">Dados</TabsTrigger>
              <TabsTrigger value="previa">Prévia no chat</TabsTrigger>
              <TabsTrigger value="sessoes">Sessões ({relacionadas.length})</TabsTrigger>
            </TabsList>

            <TabsContent value="dados">
              <form
                id={ID_FORM}
                onSubmit={formulario.handleSubmit((v) => void edicao.salvar(v))}
                className="space-y-4"
                noValidate
              >
                <AvisoErroEscrita erro={edicao.erroEscrita} />

                {edicao.sujo ? (
                  <Alert variant="atencao">
                    <AlertTriangle />
                    <AlertTitle>Alterações não salvas</AlertTitle>
                    <AlertDescription>
                      Fechar sem salvar descarta o que foi editado.
                    </AlertDescription>
                  </Alert>
                ) : null}

                <fieldset disabled={!podeEditar} className="space-y-4">
                  <Campo rotulo="Nome" obrigatorio erro={errors.nome?.message}>
                    {(p) => <Input {...p} {...formulario.register('nome')} />}
                  </Campo>

                  <div className="grid gap-4 sm:grid-cols-2">
                    <Campo rotulo="Cargo" erro={errors.cargo?.message}>
                      {(p) => <Input {...p} {...formulario.register('cargo')} />}
                    </Campo>
                    <Campo rotulo="Organização" erro={errors.organizacao?.message}>
                      {(p) => <Input {...p} {...formulario.register('organizacao')} />}
                    </Campo>
                  </div>

                  <Campo
                    rotulo="Biografia"
                    obrigatorio
                    erro={errors.biografia?.message}
                    dica="É o texto que o agente lê quando alguém pergunta quem é a pessoa."
                  >
                    {(p) => <Textarea rows={5} {...p} {...formulario.register('biografia')} />}
                  </Campo>

                  <Campo
                    rotulo="Foto"
                    erro={errors.foto?.message}
                    dica="Caminho relativo dentro de assets/, por exemplo palestrantes/amy.webp."
                  >
                    {(p) => <Input {...p} {...formulario.register('foto')} />}
                  </Campo>

                  <Campo rotulo="Temas" erro={errors.temas?.message}>
                    {(p) => (
                      <SelecaoMultipla
                        id={p.id}
                        opcoes={(temas.data?.itens ?? []).map((t) => ({
                          valor: t.codigo,
                          rotulo: t.rotulo,
                        }))}
                        valor={formulario.watch('temas')}
                        aoMudar={(v) => formulario.setValue('temas', v, { shouldDirty: true })}
                      />
                    )}
                  </Campo>

                  <div className="grid gap-4 sm:grid-cols-2">
                    <div className="flex items-center gap-3 pt-6">
                      <Switch
                        id="palestrante-destaque"
                        checked={formulario.watch('destaque')}
                        onCheckedChange={(v) =>
                          formulario.setValue('destaque', v, { shouldDirty: true })
                        }
                      />
                      <Label htmlFor="palestrante-destaque">Destaque</Label>
                    </div>

                    <Campo rotulo="Status editorial" erro={errors.status?.message}>
                      {(p) => (
                        <Select
                          value={formulario.watch('status')}
                          onValueChange={(v) =>
                            formulario.setValue('status', v as PalestranteForm['status'], {
                              shouldDirty: true,
                            })
                          }
                        >
                          <SelectTrigger id={p.id}>
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            {STATUS_EDITORIAL.map((status) => (
                              <SelectItem key={status} value={status}>
                                {ROTULO_STATUS_EDITORIAL[status]}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      )}
                    </Campo>
                  </div>
                </fieldset>
              </form>
            </TabsContent>

            <TabsContent value="previa">
              <PreviaCartaoPalestrante
                palestrante={valores}
                temas={temas.data?.itens ?? []}
              />
              <p className="mt-3 text-xs text-muted-foreground">
                A prévia acompanha o formulário em tempo real, inclusive antes de salvar.
              </p>
            </TabsContent>

            <TabsContent value="sessoes">
              {relacionadas.length === 0 ? (
                <p className="text-sm text-muted-foreground">
                  Nenhuma sessão vinculada a esta pessoa. A ligação é feita na aba Palestrantes de
                  cada sessão.
                </p>
              ) : (
                <ul className="space-y-2">
                  {relacionadas.map((s) => (
                    <li key={s.id}>
                      <Link
                        to={`/programacao/${s.id}`}
                        className="block rounded-md border p-3 text-sm hover:border-verde-300 hover:bg-verde-50/50"
                      >
                        <span className="font-semibold">{s.titulo}</span>
                        <span className="block text-xs text-muted-foreground">
                          {s.dia} · {s.inicio}–{s.fim ?? 'aberta'}
                        </span>
                      </Link>
                    </li>
                  ))}
                </ul>
              )}
            </TabsContent>
          </Tabs>
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
