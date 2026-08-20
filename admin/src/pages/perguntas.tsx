import { useNavigate, useParams } from 'react-router-dom';
import { zodResolver } from '@hookform/resolvers/zod';
import { FilePlus2, Link2 } from 'lucide-react';
import {
  CANAIS,
  ROTULO_CANAL,
  ROTULO_STATUS_PERGUNTA,
  STATUS_PERGUNTA,
  perguntaFormSchema,
  type PerguntaForm,
  type PerguntaSemResposta,
} from '@/contracts';
import { useLista } from '@/hooks/use-recurso';
import { useSessao } from '@/hooks/use-sessao';
import { useEdicaoRecurso } from '@/features/comum/use-edicao-recurso';
import { formatarRelativo } from '@/lib/format';
import { mascararTextoLivre } from '@/lib/mask';
import { PaginaListagem, type Coluna } from '@/components/admin/pagina-listagem';
import { DrawerEdicao } from '@/components/admin/drawer-edicao';
import { Campo } from '@/components/admin/campo';
import { DialogoConflito } from '@/components/admin/dialogos';
import { EstadoCarregando, EstadoErro, EstadoVazio } from '@/components/admin/estados';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

const ID_FORM = 'form-pergunta';

const PADRAO: PerguntaForm = {
  categoriaSugerida: '',
  responsavel: null,
  status: 'nova',
  conteudoVinculadoId: null,
};

function DrawerPergunta({ id, aoFechar }: { id: string | undefined; aoFechar: () => void }) {
  const sessao = useSessao();
  const navegar = useNavigate();
  const usuarios = useLista('users', {});
  const conteudos = useLista('content', {});

  const edicao = useEdicaoRecurso<'unanswered', PerguntaForm>({
    recurso: 'unanswered',
    id,
    resolver: zodResolver(perguntaFormSchema),
    padrao: PADRAO,
    paraFormulario: (p: PerguntaSemResposta) => ({
      categoriaSugerida: p.categoriaSugerida,
      responsavel: p.responsavel,
      status: p.status,
      conteudoVinculadoId: p.conteudoVinculadoId,
    }),
  });

  const { formulario, registro } = edicao;
  const { errors } = formulario.formState;
  const podeEditar = sessao.pode('editar') || sessao.pode('ver_conversas');

  return (
    <>
      <DrawerEdicao
        aberto={Boolean(id)}
        titulo="Pergunta sem resposta"
        descricao={registro ? `${registro.ocorrencias} ocorrência(s)` : undefined}
        sujo={edicao.sujo}
        salvando={edicao.salvando}
        podeSalvar={podeEditar}
        idFormulario={ID_FORM}
        aoFechar={aoFechar}
        acoes={
          registro ? (
            <>
              {/* "Criar FAQ" leva ao módulo de documentos com o contexto.
                  Ele não cria nada sozinho: a redação é humana. */}
              <Button
                type="button"
                variant="secondary"
                onClick={() => navegar('/documentos')}
                title="Abre o módulo de documentos para redigir a resposta."
              >
                <FilePlus2 /> Criar FAQ
              </Button>
              <Button type="button" variant="outline" onClick={() => navegar('/conteudo')}>
                <Link2 /> Ver conteúdos
              </Button>
            </>
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
            {registro ? (
              <Alert variant="default">
                <AlertTitle>Pergunta registrada</AlertTitle>
                <AlertDescription>
                  <p className="text-base font-semibold text-foreground">
                    {mascararTextoLivre(registro.pergunta)}
                  </p>
                  <p className="mt-1 text-xs">
                    {ROTULO_CANAL[registro.canal]} · última ocorrência{' '}
                    {formatarRelativo(registro.ultimaOcorrenciaEm)}
                  </p>
                </AlertDescription>
              </Alert>
            ) : null}

            <fieldset disabled={!podeEditar} className="space-y-4">
              <Campo
                rotulo="Categoria sugerida"
                obrigatorio
                erro={errors.categoriaSugerida?.message}
              >
                {(p) => <Input {...p} {...formulario.register('categoriaSugerida')} />}
              </Campo>

              <div className="grid gap-4 sm:grid-cols-2">
                <Campo rotulo="Responsável" erro={errors.responsavel?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('responsavel') ?? 'ninguem'}
                      onValueChange={(v) =>
                        formulario.setValue('responsavel', v === 'ninguem' ? null : v, {
                          shouldDirty: true,
                        })
                      }
                    >
                      <SelectTrigger id={p.id}>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="ninguem">Sem responsável</SelectItem>
                        {(usuarios.data?.itens ?? []).map((u) => (
                          <SelectItem key={u.id} value={u.nome}>
                            {u.nome}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>

                <Campo rotulo="Status" erro={errors.status?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('status')}
                      onValueChange={(v) =>
                        formulario.setValue('status', v as PerguntaForm['status'], {
                          shouldDirty: true,
                        })
                      }
                    >
                      <SelectTrigger id={p.id}>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {STATUS_PERGUNTA.map((s) => (
                          <SelectItem key={s} value={s}>
                            {ROTULO_STATUS_PERGUNTA[s]}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>
              </div>

              <Campo
                rotulo="Vincular a conteúdo existente"
                erro={errors.conteudoVinculadoId?.message}
                dica="Quando a resposta já existe em algum lugar, ligue aqui em vez de escrever de novo."
              >
                {(p) => (
                  <Select
                    value={formulario.watch('conteudoVinculadoId') ?? 'nenhum'}
                    onValueChange={(v) =>
                      formulario.setValue('conteudoVinculadoId', v === 'nenhum' ? null : v, {
                        shouldDirty: true,
                      })
                    }
                  >
                    <SelectTrigger id={p.id}>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="nenhum">Nenhum</SelectItem>
                      {(conteudos.data?.itens ?? []).map((c) => (
                        <SelectItem key={c.id} value={c.id}>
                          {c.titulo}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
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

export function PaginaPerguntas() {
  const { id } = useParams();
  const navegar = useNavigate();

  const colunas: Coluna<PerguntaSemResposta>[] = [
    {
      chave: 'pergunta',
      cabecalho: 'Pergunta',
      celula: (p) => (
        <p className="min-w-64 max-w-96 font-medium">{mascararTextoLivre(p.pergunta)}</p>
      ),
    },
    {
      chave: 'ocorrencias',
      cabecalho: 'Ocorrências',
      className: 'tabular',
      celula: (p) => (
        <Badge variant={p.ocorrencias >= 15 ? 'destructive' : 'neutro'}>{p.ocorrencias}</Badge>
      ),
    },
    {
      chave: 'canal',
      cabecalho: 'Canal',
      celula: (p) => <Badge variant="outline">{ROTULO_CANAL[p.canal]}</Badge>,
    },
    {
      chave: 'ultima',
      cabecalho: 'Última ocorrência',
      className: 'whitespace-nowrap',
      celula: (p) => <span className="text-xs">{formatarRelativo(p.ultimaOcorrenciaEm)}</span>,
    },
    {
      chave: 'categoria',
      cabecalho: 'Categoria sugerida',
      celula: (p) => <Badge variant="secondary">{p.categoriaSugerida}</Badge>,
    },
    {
      chave: 'responsavel',
      cabecalho: 'Responsável',
      celula: (p) =>
        p.responsavel ?? <span className="text-xs text-muted-foreground">sem responsável</span>,
    },
    {
      chave: 'status',
      cabecalho: 'Status',
      celula: (p) => (
        <Badge
          variant={
            p.status === 'respondida'
              ? 'sucesso'
              : p.status === 'nova'
                ? 'atencao'
                : p.status === 'descartada'
                  ? 'neutro'
                  : 'outline'
          }
        >
          {ROTULO_STATUS_PERGUNTA[p.status]}
        </Badge>
      ),
    },
  ];

  return (
    <>
      <PaginaListagem
        recurso="unanswered"
        titulo="Perguntas sem resposta"
        descricao="A fila de melhoria do agente: o que as pessoas perguntam e ele ainda não sabe responder."
        colunas={colunas}
        ordenar="-ocorrencias"
        placeholderBusca="Buscar por pergunta, categoria ou responsável…"
        destinoItem={(p) => `/perguntas/${p.id}`}
        definicoesFiltro={[
          {
            chave: 'canal',
            rotulo: 'Canal',
            opcoes: CANAIS.map((c) => ({ valor: c, rotulo: ROTULO_CANAL[c] })),
          },
          {
            chave: 'status',
            rotulo: 'Status',
            opcoes: STATUS_PERGUNTA.map((s) => ({ valor: s, rotulo: ROTULO_STATUS_PERGUNTA[s] })),
          },
        ]}
        estadoVazio={
          <EstadoVazio
            titulo="Nenhuma pergunta na fila"
            descricao="Quando o agente não souber responder algo, a pergunta aparece aqui para virar conteúdo."
          />
        }
      />

      <DrawerPergunta id={id} aoFechar={() => navegar('/perguntas')} />
    </>
  );
}
