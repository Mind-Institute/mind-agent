import { zodResolver } from '@hookform/resolvers/zod';
import { AlertTriangle } from 'lucide-react';
import {
  FORMATOS_SESSAO,
  NIVEIS_SESSAO,
  ROTULO_FORMATO_SESSAO,
  ROTULO_NIVEL_SESSAO,
  ROTULO_STATUS_EDITORIAL,
  ROTULO_TIPO_SESSAO,
  ROTULO_TRILHA,
  STATUS_EDITORIAL,
  TIPOS_SESSAO,
  TRILHAS,
  sessaoFormSchema,
  type Sessao,
  type SessaoForm,
} from '@/contracts';
import { useLista, TODAS_AS_OPCOES } from '@/hooks/use-recurso';
import { opcoesComAtual } from '@/lib/rotulos';
import { useSessao } from '@/hooks/use-sessao';
import { useEdicaoRecurso } from '@/features/comum/use-edicao-recurso';
import { DrawerEdicao } from '@/components/admin/drawer-edicao';
import { Campo } from '@/components/admin/campo';
import { EditorDeLista, SelecaoMultipla } from '@/components/admin/editor-lista';
import { AcoesEditoriais, InfoPublicacao } from '@/components/admin/acoes-editoriais';
import { DialogoConflito } from '@/components/admin/dialogos';
import { AvisoErroEscrita } from '@/components/admin/aviso-escrita';
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

const ID_FORM = 'form-sessao';

const PADRAO: SessaoForm = {
  titulo: '',
  descricao: '',
  dia: '',
  inicio: '',
  fim: '',
  espacoId: '',
  tipo: 'palestra',
  formato: 'presencial',
  trilhas: ['mind'],
  temas: [],
  palestranteIds: [],
  necessitaReserva: false,
  vagasTotais: null,
  vagasDisponiveis: null,
  nivel: null,
  resultadosEsperados: [],
  status: 'rascunho',
};

function paraFormulario(sessao: Sessao): SessaoForm {
  return {
    titulo: sessao.titulo,
    descricao: sessao.descricao,
    dia: sessao.dia,
    inicio: sessao.inicio,
    fim: sessao.fim ?? '',
    espacoId: sessao.espacoId ?? '',
    tipo: sessao.tipo,
    formato: sessao.formato,
    trilhas: sessao.trilhas,
    temas: sessao.temas,
    palestranteIds: sessao.palestranteIds,
    necessitaReserva: sessao.necessitaReserva,
    vagasTotais: sessao.vagasTotais,
    vagasDisponiveis: sessao.vagasDisponiveis,
    nivel: sessao.nivel,
    resultadosEsperados: sessao.resultadosEsperados,
    status: sessao.status,
  };
}

export function DrawerSessao({ id, aoFechar }: { id: string | undefined; aoFechar: () => void }) {
  const sessaoUsuario = useSessao();
  const espacos = useLista('spaces', { ordenar: 'nome', ...TODAS_AS_OPCOES });
  const temas = useLista('themes', TODAS_AS_OPCOES);
  const palestrantes = useLista('speakers', { ordenar: 'nome', ...TODAS_AS_OPCOES });

  const edicao = useEdicaoRecurso<'sessions', SessaoForm>({
    recurso: 'sessions',
    id,
    resolver: zodResolver(sessaoFormSchema),
    padrao: PADRAO,
    paraFormulario,
    /* Campo de horário vazio volta para o banco como `null`, não como
       string vazia — o vazio aqui significa "sessão sem hora de fim". */
    paraPayload: (valores) => ({ ...valores, fim: valores.fim === '' ? null : valores.fim }),
  });

  const { formulario, registro } = edicao;
  const { errors } = formulario.formState;
  const podeEditar = sessaoUsuario.pode('editar');

  return (
    <>
      <DrawerEdicao
        aberto={Boolean(id)}
        titulo={registro?.titulo || 'Sessão'}
        descricao={
          registro
            ? `${registro.dia} · ${registro.inicio}–${registro.fim ?? 'sem fim'} · ${ROTULO_STATUS_EDITORIAL[registro.status]}`
            : undefined
        }
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
              rotulo={registro.titulo}
              salvando={edicao.salvando}
              aoPublicar={() => void edicao.publicar()}
              aoArquivar={() => void edicao.arquivar()}
            />
          ) : null
        }
      >
        {edicao.carregando ? (
          <EstadoCarregando linhas={8} />
        ) : edicao.erro ? (
          <EstadoErro erro={edicao.erro} aoTentarNovamente={edicao.recarregar} />
        ) : (
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
                <AlertDescription>Fechar sem salvar descarta o que foi editado.</AlertDescription>
              </Alert>
            ) : null}

            <fieldset disabled={!podeEditar} className="space-y-4">
              <Campo rotulo="Título" obrigatorio erro={errors.titulo?.message}>
                {(p) => <Input {...p} {...formulario.register('titulo')} />}
              </Campo>

              <Campo rotulo="Descrição" erro={errors.descricao?.message}>
                {(p) => <Textarea rows={3} {...p} {...formulario.register('descricao')} />}
              </Campo>

              <div className="grid gap-4 sm:grid-cols-3">
                <Campo rotulo="Dia" obrigatorio erro={errors.dia?.message}>
                  {(p) => <Input type="date" {...p} {...formulario.register('dia')} />}
                </Campo>
                <Campo rotulo="Início" obrigatorio erro={errors.inicio?.message}>
                  {(p) => <Input type="time" {...p} {...formulario.register('inicio')} />}
                </Campo>
                <Campo
                  rotulo="Fim"
                  erro={errors.fim?.message}
                  dica="Vazio = sessão aberta, sem hora para terminar."
                >
                  {(p) => <Input type="time" {...p} {...formulario.register('fim')} />}
                </Campo>
              </div>

              <div className="grid gap-4 sm:grid-cols-2">
                <Campo
                  rotulo="Espaço"
                  obrigatorio
                  erro={errors.espacoId?.message}
                  dica="Sem espaço, o agente não responde onde a sessão acontece."
                >
                  {(p) => (
                    <Select
                      value={formulario.watch('espacoId')}
                      onValueChange={(v) =>
                        formulario.setValue('espacoId', v, { shouldDirty: true })
                      }
                    >
                      <SelectTrigger id={p.id} aria-invalid={p['aria-invalid']}>
                        <SelectValue placeholder="Escolha o espaço" />
                      </SelectTrigger>
                      <SelectContent>
                        {/* O espaço atual entra na lista mesmo que não
                            venha da API: sem ele o Radix devolveria vazio
                            ao formulário e salvar apagaria o vínculo. */}
                        {opcoesComAtual(
                          (espacos.data?.itens ?? []).map((e) => ({
                            valor: e.id,
                            rotulo: e.nome,
                          })),
                          formulario.watch('espacoId'),
                        ).map((opcao) => (
                          <SelectItem key={opcao.valor} value={opcao.valor}>
                            {opcao.rotulo}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>

                <Campo rotulo="Status editorial" erro={errors.status?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('status')}
                      onValueChange={(v) =>
                        formulario.setValue('status', v as SessaoForm['status'], {
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

                <Campo rotulo="Tipo" erro={errors.tipo?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('tipo')}
                      onValueChange={(v) =>
                        formulario.setValue('tipo', v as SessaoForm['tipo'], { shouldDirty: true })
                      }
                    >
                      <SelectTrigger id={p.id}>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {opcoesComAtual(
                          TIPOS_SESSAO.map((t) => ({ valor: t, rotulo: ROTULO_TIPO_SESSAO[t] })),
                          formulario.watch('tipo'),
                        ).map((opcao) => (
                          <SelectItem key={opcao.valor} value={opcao.valor}>
                            {opcao.rotulo}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>

                <Campo rotulo="Formato" erro={errors.formato?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('formato')}
                      onValueChange={(v) =>
                        formulario.setValue('formato', v as SessaoForm['formato'], {
                          shouldDirty: true,
                        })
                      }
                    >
                      <SelectTrigger id={p.id}>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {opcoesComAtual(
                          FORMATOS_SESSAO.map((f) => ({ valor: f, rotulo: ROTULO_FORMATO_SESSAO[f] })),
                          formulario.watch('formato'),
                        ).map((opcao) => (
                          <SelectItem key={opcao.valor} value={opcao.valor}>
                            {opcao.rotulo}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>

                <Campo rotulo="Nível" erro={errors.nivel?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('nivel') ?? 'nenhum'}
                      onValueChange={(v) =>
                        formulario.setValue(
                          'nivel',
                          v === 'nenhum' ? null : (v as NonNullable<SessaoForm['nivel']>),
                          { shouldDirty: true },
                        )
                      }
                    >
                      <SelectTrigger id={p.id}>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="nenhum">Não definido</SelectItem>
                        {NIVEIS_SESSAO.map((nivel) => (
                          <SelectItem key={nivel} value={nivel}>
                            {ROTULO_NIVEL_SESSAO[nivel]}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>
              </div>

              <Campo
                rotulo="Trilhas de ingresso"
                obrigatorio
                erro={errors.trilhas?.message}
                dica="Quem pode entrar nesta sessão."
              >
                {(p) => (
                  <SelecaoMultipla
                    id={p.id}
                    colunas={3}
                    opcoes={TRILHAS.map((t) => ({ valor: t, rotulo: ROTULO_TRILHA[t] }))}
                    valor={formulario.watch('trilhas')}
                    aoMudar={(v) => formulario.setValue('trilhas', v, { shouldDirty: true })}
                  />
                )}
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

              <Campo
                rotulo="Palestrantes"
                erro={errors.palestranteIds?.message}
                dica={
                  registro?.quemTexto
                    ? `Texto importado do summit.json: "${registro.quemTexto}"`
                    : undefined
                }
              >
                {(p) => (
                  <div className="max-h-56 overflow-y-auto rounded-md border p-2">
                    <SelecaoMultipla
                      id={p.id}
                      opcoes={(palestrantes.data?.itens ?? []).map((pal) => ({
                        valor: pal.id,
                        rotulo: pal.nome,
                      }))}
                      valor={formulario.watch('palestranteIds')}
                      aoMudar={(v) =>
                        formulario.setValue('palestranteIds', v, { shouldDirty: true })
                      }
                    />
                  </div>
                )}
              </Campo>

              <div className="grid gap-4 sm:grid-cols-3">
                <div className="flex items-center gap-3 pt-6">
                  <Switch
                    id="necessita-reserva"
                    checked={formulario.watch('necessitaReserva')}
                    onCheckedChange={(v) =>
                      formulario.setValue('necessitaReserva', v, { shouldDirty: true })
                    }
                  />
                  <Label htmlFor="necessita-reserva">Necessita reserva</Label>
                </div>
                <Campo rotulo="Vagas totais" erro={errors.vagasTotais?.message}>
                  {(p) => (
                    <Input
                      type="number"
                      min={0}
                      {...p}
                      {...formulario.register('vagasTotais', {
                        setValueAs: (v) => (v === '' || v === null ? null : Number(v)),
                      })}
                    />
                  )}
                </Campo>
                <Campo rotulo="Vagas disponíveis" erro={errors.vagasDisponiveis?.message}>
                  {(p) => (
                    <Input
                      type="number"
                      min={0}
                      {...p}
                      {...formulario.register('vagasDisponiveis', {
                        setValueAs: (v) => (v === '' || v === null ? null : Number(v)),
                      })}
                    />
                  )}
                </Campo>
              </div>

              <Campo
                rotulo="Resultados esperados"
                erro={errors.resultadosEsperados?.message}
                dica="O que a pessoa leva desta sessão. Uma linha por resultado."
              >
                {(p) => (
                  <EditorDeLista
                    id={p.id}
                    valor={formulario.watch('resultadosEsperados')}
                    aoMudar={(v) =>
                      formulario.setValue('resultadosEsperados', v, { shouldDirty: true })
                    }
                    placeholder="Ex.: sair com um plano de 30 dias"
                    vazio="Nenhum resultado descrito."
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
