import { zodResolver } from '@hookform/resolvers/zod';
import { AlertTriangle } from 'lucide-react';
import { rotaFormSchema, type Rota, type RotaForm } from '@/contracts';
import { useLista } from '@/hooks/use-recurso';
import { useSessao } from '@/hooks/use-sessao';
import { useEdicaoRecurso } from '@/features/comum/use-edicao-recurso';
import { DrawerEdicao } from '@/components/admin/drawer-edicao';
import { Campo } from '@/components/admin/campo';
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

const ID_FORM = 'form-rota';

const PADRAO: RotaForm = {
  origemId: '',
  destinoId: '',
  instrucoes: '',
  distanciaMetros: null,
  tempoEstimadoMinutos: null,
  acessivel: true,
  bidirecional: true,
  ativo: true,
};

function paraFormulario(r: Rota): RotaForm {
  return {
    origemId: r.origemId,
    destinoId: r.destinoId,
    instrucoes: r.instrucoes,
    distanciaMetros: r.distanciaMetros,
    tempoEstimadoMinutos: r.tempoEstimadoMinutos,
    acessivel: r.acessivel,
    bidirecional: r.bidirecional,
    ativo: r.ativo,
  };
}

export function DrawerRota({ id, aoFechar }: { id: string | undefined; aoFechar: () => void }) {
  const sessao = useSessao();
  const espacos = useLista('spaces', { ordenar: 'nome' });

  const edicao = useEdicaoRecurso<'routes', RotaForm>({
    recurso: 'routes',
    id,
    resolver: zodResolver(rotaFormSchema),
    padrao: PADRAO,
    paraFormulario,
  });

  const { formulario, registro } = edicao;
  const { errors } = formulario.formState;
  const podeEditar = sessao.pode('editar');
  const opcoes = espacos.data?.itens ?? [];
  const nome = (idEspaco: string) => opcoes.find((e) => e.id === idEspaco)?.nome ?? idEspaco;

  return (
    <>
      <DrawerEdicao
        aberto={Boolean(id)}
        titulo={registro ? `${nome(registro.origemId)} → ${nome(registro.destinoId)}` : 'Rota'}
        sujo={edicao.sujo}
        salvando={edicao.salvando}
        podeSalvar={podeEditar}
        idFormulario={ID_FORM}
        aoFechar={aoFechar}
        acoes={
          registro ? (
            <AcoesEditoriais
              rotulo={`${nome(registro.origemId)} → ${nome(registro.destinoId)}`}
              salvando={edicao.salvando}
              aoArquivar={() => void edicao.arquivar()}
            />
          ) : null
        }
      >
        {edicao.carregando ? (
          <EstadoCarregando linhas={5} />
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
                <Campo rotulo="Origem" obrigatorio erro={errors.origemId?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('origemId')}
                      onValueChange={(v) =>
                        formulario.setValue('origemId', v, { shouldDirty: true })
                      }
                    >
                      <SelectTrigger id={p.id} aria-invalid={p['aria-invalid']}>
                        <SelectValue placeholder="Escolha a origem" />
                      </SelectTrigger>
                      <SelectContent>
                        {opcoes.map((e) => (
                          <SelectItem key={e.id} value={e.id}>
                            {e.nome}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>

                <Campo rotulo="Destino" obrigatorio erro={errors.destinoId?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('destinoId')}
                      onValueChange={(v) =>
                        formulario.setValue('destinoId', v, { shouldDirty: true })
                      }
                    >
                      <SelectTrigger id={p.id} aria-invalid={p['aria-invalid']}>
                        <SelectValue placeholder="Escolha o destino" />
                      </SelectTrigger>
                      <SelectContent>
                        {opcoes.map((e) => (
                          <SelectItem key={e.id} value={e.id}>
                            {e.nome}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>
              </div>

              <Campo
                rotulo="Instruções"
                obrigatorio
                erro={errors.instrucoes?.message}
                dica="O texto que o agente lê em voz alta. Referências visuais funcionam melhor que metros."
              >
                {(p) => <Textarea rows={4} {...p} {...formulario.register('instrucoes')} />}
              </Campo>

              <div className="grid gap-4 sm:grid-cols-2">
                <Campo rotulo="Distância (metros)" erro={errors.distanciaMetros?.message}>
                  {(p) => (
                    <Input
                      type="number"
                      min={0}
                      {...p}
                      {...formulario.register('distanciaMetros', {
                        setValueAs: (v) => (v === '' || v === null ? null : Number(v)),
                      })}
                    />
                  )}
                </Campo>
                <Campo rotulo="Tempo estimado (minutos)" erro={errors.tempoEstimadoMinutos?.message}>
                  {(p) => (
                    <Input
                      type="number"
                      min={0}
                      {...p}
                      {...formulario.register('tempoEstimadoMinutos', {
                        setValueAs: (v) => (v === '' || v === null ? null : Number(v)),
                      })}
                    />
                  )}
                </Campo>
              </div>

              <div className="grid gap-3 sm:grid-cols-3">
                <div className="flex items-center gap-3">
                  <Switch
                    id="rota-acessivel"
                    checked={formulario.watch('acessivel')}
                    onCheckedChange={(v) =>
                      formulario.setValue('acessivel', v, { shouldDirty: true })
                    }
                  />
                  <Label htmlFor="rota-acessivel">Acessível</Label>
                </div>
                <div className="flex items-center gap-3">
                  <Switch
                    id="rota-bidirecional"
                    checked={formulario.watch('bidirecional')}
                    onCheckedChange={(v) =>
                      formulario.setValue('bidirecional', v, { shouldDirty: true })
                    }
                  />
                  <Label htmlFor="rota-bidirecional">Bidirecional</Label>
                </div>
                <div className="flex items-center gap-3">
                  <Switch
                    id="rota-ativa"
                    checked={formulario.watch('ativo')}
                    onCheckedChange={(v) => formulario.setValue('ativo', v, { shouldDirty: true })}
                  />
                  <Label htmlFor="rota-ativa">Rota ativa</Label>
                </div>
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
