import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { AlertTriangle, Save } from 'lucide-react';
import { eventoFormSchema, type Evento, type EventoForm } from '@/contracts';
import { codigoDoErro } from '@/contracts';
import { useAtualizar, useLista } from '@/hooks/use-recurso';
import { useAlteracoesNaoSalvas } from '@/hooks/use-alteracoes-nao-salvas';
import { useSessao } from '@/hooks/use-sessao';
import { motivoDaRecusa } from '@/lib/permissions';
import { divergenciasDeLocal } from '@/lib/local-evento';
import { useRecursoReal } from '@/services/provider-context';
import { formatarDataExtenso, formatarDataHora } from '@/lib/format';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { Campo, SecaoFormulario } from '@/components/admin/campo';
import {
  EstadoCarregando,
  EstadoErro,
  EstadoSemPermissao,
  Salvando,
} from '@/components/admin/estados';
import { DialogoAlteracoesNaoSalvas, DialogoConflito } from '@/components/admin/dialogos';
import { AvisoErroEscrita } from '@/components/admin/aviso-escrita';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';

function paraFormulario(evento: Evento): EventoForm {
  return {
    nome: evento.nome,
    slug: evento.slug,
    dataInicio: evento.dataInicio,
    dataFim: evento.dataFim,
    local: evento.local,
    cidade: evento.cidade,
    fusoHorario: evento.fusoHorario,
    descricao: evento.descricao,
    regraReserva: evento.regraReserva,
    regraVagas: evento.regraVagas,
    ativo: evento.ativo,
  };
}

export function PaginaEvento() {
  const sessao = useSessao();
  const consulta = useLista('event');
  const evento = consulta.data?.itens[0];
  const atualizar = useAtualizar('event');
  const real = useRecursoReal('event');
  const [conflito, setConflito] = useState(false);
  const [salvo, setSalvo] = useState(false);
  const [erroEscrita, setErroEscrita] = useState<unknown>(null);
  const divergencias = evento ? divergenciasDeLocal(evento) : [];

  const podeEditar = sessao.pode('editar');

  const formulario = useForm<EventoForm>({
    resolver: zodResolver(eventoFormSchema),
    defaultValues: {
      nome: '',
      slug: '',
      dataInicio: '',
      dataFim: '',
      local: '',
      cidade: '',
      fusoHorario: 'America/Sao_Paulo',
      descricao: '',
      regraReserva: '',
      regraVagas: '',
      ativo: true,
    },
  });

  useEffect(() => {
    if (evento) formulario.reset(paraFormulario(evento));
  }, [evento, formulario]);

  const sujo = formulario.formState.isDirty;
  const bloqueio = useAlteracoesNaoSalvas(sujo);
  const { errors } = formulario.formState;

  async function salvar(valores: EventoForm) {
    if (!evento) return;
    setSalvo(false);
    setErroEscrita(null);
    try {
      await atualizar.mutateAsync({
        id: evento.id,
        payload: valores,
        opcoes: { atualizadoEmEsperado: evento.atualizadoEm },
      });
      formulario.reset(valores);
      setSalvo(true);
    } catch (erro) {
      /* Conflito tem diálogo próprio; o resto (422, 403, rede) precisa
         aparecer, ou o formulário só "não salva" e não explica. */
      if (codigoDoErro(erro) === 'conflito') setConflito(true);
      else setErroEscrita(erro);
    }
  }

  if (!sessao.pode('ver')) {
    return <EstadoSemPermissao motivo={motivoDaRecusa(sessao.papel, 'ver')} />;
  }

  return (
    <div className="space-y-5">
      <CabecalhoPagina
        titulo="Evento"
        descricao="A identidade do Mind Summit 2026. Estes valores aparecem em toda resposta do agente sobre datas, local e regras."
        acoes={
          <Button
            type="submit"
            form="form-evento"
            disabled={!podeEditar || !sujo || atualizar.isPending}
          >
            {atualizar.isPending ? <Salvando /> : <Save />}
            Salvar alterações
          </Button>
        }
      />

      {consulta.isPending ? (
        <EstadoCarregando linhas={6} />
      ) : consulta.error ? (
        <EstadoErro erro={consulta.error} aoTentarNovamente={() => void consulta.refetch()} />
      ) : !evento ? (
        <EstadoErro
          erro={
            new Error(
              real
                ? 'A API administrativa não devolveu nenhum evento em GET /admin/event.'
                : 'O evento padrão não foi encontrado na base de demonstração.',
            )
          }
        />
      ) : (
        <>
          {/* Divergência de local: o painel mostra as versões e não
              escolhe. Escolher seria inventar dado. */}
          {divergencias.length > 1 ? (
            <Alert variant="atencao">
              <AlertTriangle />
              <AlertTitle>Local do evento em divergência — precisa de revisão humana</AlertTitle>
              <AlertDescription>
                <ul className="mt-1 space-y-0.5">
                  {divergencias.map((candidato) => (
                    <li key={candidato.valor}>
                      <strong>{candidato.valor}</strong>{' '}
                      <span className="text-muted-foreground">— {candidato.origem}</span>
                    </li>
                  ))}
                </ul>
                <p className="mt-2">
                  O painel não decide qual está correto. O campo <em>Local</em> abaixo guarda o valor
                  em uso ({evento.local}); confirme com a produção antes de publicar.
                </p>
              </AlertDescription>
            </Alert>
          ) : null}

          <AvisoErroEscrita erro={erroEscrita} />

          {sujo ? (
            <Alert variant="atencao">
              <AlertTriangle />
              <AlertTitle>Alterações não salvas</AlertTitle>
              <AlertDescription>
                Você mudou este formulário e ainda não salvou. Sair da página agora perde o trabalho.
              </AlertDescription>
            </Alert>
          ) : null}

          {salvo && !sujo ? (
            <Alert variant="info">
              <AlertTitle>Alterações salvas</AlertTitle>
              <AlertDescription>
                {real
                  ? 'Gravado na API administrativa. O agente já responde com estes valores.'
                  : 'Gravado na base de demonstração. Nada foi enviado ao Supabase.'}
              </AlertDescription>
            </Alert>
          ) : null}

          <form
            id="form-evento"
            onSubmit={formulario.handleSubmit(salvar)}
            className="space-y-4"
            noValidate
          >
            <fieldset disabled={!podeEditar} className="space-y-4">
              <SecaoFormulario titulo="Identificação">
                <Campo rotulo="Nome" obrigatorio erro={errors.nome?.message}>
                  {(props) => <Input {...props} {...formulario.register('nome')} />}
                </Campo>
                <Campo
                  rotulo="Slug"
                  obrigatorio
                  erro={errors.slug?.message}
                  dica="Identificador usado nas rotas da API e no chat."
                >
                  {(props) => <Input {...props} {...formulario.register('slug')} />}
                </Campo>
                <Campo
                  rotulo="Descrição"
                  erro={errors.descricao?.message}
                  className="md:col-span-2"
                >
                  {(props) => (
                    <Textarea rows={3} {...props} {...formulario.register('descricao')} />
                  )}
                </Campo>
              </SecaoFormulario>

              <SecaoFormulario
                titulo="Quando e onde"
                descricao="Datas e fuso alimentam todo cálculo de horário na programação."
              >
                <Campo
                  rotulo="Data inicial"
                  obrigatorio
                  erro={errors.dataInicio?.message}
                  dica={formatarDataExtenso(formulario.watch('dataInicio'))}
                >
                  {(props) => <Input type="date" {...props} {...formulario.register('dataInicio')} />}
                </Campo>
                <Campo
                  rotulo="Data final"
                  obrigatorio
                  erro={errors.dataFim?.message}
                  dica={formatarDataExtenso(formulario.watch('dataFim'))}
                >
                  {(props) => <Input type="date" {...props} {...formulario.register('dataFim')} />}
                </Campo>
                <Campo rotulo="Local" obrigatorio erro={errors.local?.message}>
                  {(props) => <Input {...props} {...formulario.register('local')} />}
                </Campo>
                <Campo rotulo="Cidade" obrigatorio erro={errors.cidade?.message}>
                  {(props) => <Input {...props} {...formulario.register('cidade')} />}
                </Campo>
                <Campo
                  rotulo="Fuso horário"
                  obrigatorio
                  erro={errors.fusoHorario?.message}
                  dica="Formato IANA, por exemplo America/Sao_Paulo."
                >
                  {(props) => <Input {...props} {...formulario.register('fusoHorario')} />}
                </Campo>
              </SecaoFormulario>

              <SecaoFormulario
                titulo="Regras"
                descricao="O agente repete estes textos quando alguém pergunta sobre reserva e vaga."
              >
                <Campo
                  rotulo="Regras de reserva"
                  erro={errors.regraReserva?.message}
                  className="md:col-span-2"
                >
                  {(props) => (
                    <Textarea rows={2} {...props} {...formulario.register('regraReserva')} />
                  )}
                </Campo>
                <Campo
                  rotulo="Regras de vagas"
                  erro={errors.regraVagas?.message}
                  className="md:col-span-2"
                >
                  {(props) => (
                    <Textarea rows={2} {...props} {...formulario.register('regraVagas')} />
                  )}
                </Campo>
              </SecaoFormulario>

              <SecaoFormulario titulo="Situação">
                <div className="flex items-center gap-3">
                  <Switch
                    id="evento-ativo"
                    checked={formulario.watch('ativo')}
                    onCheckedChange={(v) =>
                      formulario.setValue('ativo', v, { shouldDirty: true })
                    }
                  />
                  <Label htmlFor="evento-ativo">Evento ativo</Label>
                </div>
                <div className="text-sm text-muted-foreground">
                  <p>
                    Última atualização: <strong>{formatarDataHora(evento.atualizadoEm)}</strong>
                  </p>
                  <p>Por: {evento.atualizadoPor ?? '—'}</p>
                </div>
              </SecaoFormulario>
            </fieldset>

            {!podeEditar ? (
              <p className="text-sm text-muted-foreground">
                {motivoDaRecusa(sessao.papel, 'editar')} Os campos estão em modo leitura.
              </p>
            ) : null}
          </form>
        </>
      )}

      <DialogoAlteracoesNaoSalvas
        aberto={bloqueio.bloqueado}
        aoDescartar={bloqueio.confirmar}
        aoFicar={bloqueio.cancelar}
      />
      <DialogoConflito
        aberto={conflito}
        aoRecarregar={() => {
          setConflito(false);
          void consulta.refetch();
        }}
        aoFechar={() => setConflito(false)}
      />
    </div>
  );
}
