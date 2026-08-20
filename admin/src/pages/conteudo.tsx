import { useNavigate, useParams } from 'react-router-dom';
import { zodResolver } from '@hookform/resolvers/zod';
import { AlertTriangle } from 'lucide-react';
import {
  CATEGORIAS_CONTEUDO,
  PUBLICOS_CONTEUDO,
  ROTULO_CATEGORIA_CONTEUDO,
  ROTULO_PUBLICO_CONTEUDO,
  ROTULO_STATUS_EDITORIAL,
  STATUS_EDITORIAL,
  conteudoFormSchema,
  type Conteudo,
  type ConteudoForm,
} from '@/contracts';
import { useSessao } from '@/hooks/use-sessao';
import { useEdicaoRecurso } from '@/features/comum/use-edicao-recurso';
import { formatarData } from '@/lib/format';
import { PaginaListagem, type Coluna } from '@/components/admin/pagina-listagem';
import { DrawerEdicao } from '@/components/admin/drawer-edicao';
import { Campo } from '@/components/admin/campo';
import { AcoesEditoriais, InfoPublicacao } from '@/components/admin/acoes-editoriais';
import { DialogoConflito } from '@/components/admin/dialogos';
import { EstadoCarregando, EstadoErro, EstadoVazio } from '@/components/admin/estados';
import { SeloEditorial } from '@/components/admin/selos';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

const ID_FORM = 'form-conteudo';

const PADRAO: ConteudoForm = {
  categoria: 'sobre',
  slug: '',
  titulo: '',
  conteudo: '',
  publico: 'publico',
  validoAte: '',
  status: 'rascunho',
};

function DrawerConteudo({ id, aoFechar }: { id: string | undefined; aoFechar: () => void }) {
  const sessao = useSessao();

  const edicao = useEdicaoRecurso<'content', ConteudoForm>({
    recurso: 'content',
    id,
    resolver: zodResolver(conteudoFormSchema),
    padrao: PADRAO,
    paraFormulario: (c: Conteudo) => ({
      categoria: c.categoria,
      slug: c.slug,
      titulo: c.titulo,
      conteudo: c.conteudo,
      publico: c.publico,
      validoAte: c.validoAte,
      status: c.status,
    }),
  });

  const { formulario, registro } = edicao;
  const { errors } = formulario.formState;
  const podeEditar = sessao.pode('editar');

  return (
    <>
      <DrawerEdicao
        aberto={Boolean(id)}
        titulo={registro?.titulo || 'Conteúdo'}
        descricao={
          registro
            ? `${ROTULO_CATEGORIA_CONTEUDO[registro.categoria]} · ${ROTULO_STATUS_EDITORIAL[registro.status]}`
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
            {edicao.sujo ? (
              <Alert variant="atencao">
                <AlertTriangle />
                <AlertTitle>Alterações não salvas</AlertTitle>
                <AlertDescription>Fechar sem salvar descarta o que foi editado.</AlertDescription>
              </Alert>
            ) : null}

            <fieldset disabled={!podeEditar} className="space-y-4">
              <div className="grid gap-4 sm:grid-cols-2">
                <Campo rotulo="Categoria" erro={errors.categoria?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('categoria')}
                      onValueChange={(v) =>
                        formulario.setValue('categoria', v as ConteudoForm['categoria'], {
                          shouldDirty: true,
                        })
                      }
                    >
                      <SelectTrigger id={p.id}>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {CATEGORIAS_CONTEUDO.map((c) => (
                          <SelectItem key={c} value={c}>
                            {ROTULO_CATEGORIA_CONTEUDO[c]}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>
                <Campo rotulo="Slug" obrigatorio erro={errors.slug?.message}>
                  {(p) => <Input {...p} {...formulario.register('slug')} />}
                </Campo>
              </div>

              <Campo rotulo="Título" obrigatorio erro={errors.titulo?.message}>
                {(p) => <Input {...p} {...formulario.register('titulo')} />}
              </Campo>

              <Campo
                rotulo="Conteúdo"
                obrigatorio
                erro={errors.conteudo?.message}
                dica="É a fonte que o agente usa para falar da Mind. Escreva como resposta, não como página de site."
              >
                {(p) => <Textarea rows={10} {...p} {...formulario.register('conteudo')} />}
              </Campo>

              <div className="grid gap-4 sm:grid-cols-3">
                <Campo rotulo="Público" erro={errors.publico?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('publico')}
                      onValueChange={(v) =>
                        formulario.setValue('publico', v as ConteudoForm['publico'], {
                          shouldDirty: true,
                        })
                      }
                    >
                      <SelectTrigger id={p.id}>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {PUBLICOS_CONTEUDO.map((pub) => (
                          <SelectItem key={pub} value={pub}>
                            {ROTULO_PUBLICO_CONTEUDO[pub]}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>
                <Campo
                  rotulo="Validade"
                  erro={errors.validoAte?.message}
                  dica="Deixe vazio se não expira."
                >
                  {(p) => <Input type="date" {...p} {...formulario.register('validoAte')} />}
                </Campo>
                <Campo rotulo="Status editorial" erro={errors.status?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('status')}
                      onValueChange={(v) =>
                        formulario.setValue('status', v as ConteudoForm['status'], {
                          shouldDirty: true,
                        })
                      }
                    >
                      <SelectTrigger id={p.id}>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {STATUS_EDITORIAL.map((s) => (
                          <SelectItem key={s} value={s}>
                            {ROTULO_STATUS_EDITORIAL[s]}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>
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

export function PaginaConteudo() {
  const { id } = useParams();
  const navegar = useNavigate();

  const colunas: Coluna<Conteudo>[] = [
    {
      chave: 'titulo',
      cabecalho: 'Conteúdo',
      celula: (c) => (
        <div className="min-w-56">
          <p className="font-semibold">{c.titulo}</p>
          <p className="font-mono text-xs text-muted-foreground">{c.slug}</p>
        </div>
      ),
    },
    {
      chave: 'categoria',
      cabecalho: 'Categoria',
      celula: (c) => <Badge variant="outline">{ROTULO_CATEGORIA_CONTEUDO[c.categoria]}</Badge>,
    },
    {
      chave: 'publico',
      cabecalho: 'Público',
      celula: (c) => <Badge variant="secondary">{ROTULO_PUBLICO_CONTEUDO[c.publico]}</Badge>,
    },
    {
      chave: 'validade',
      cabecalho: 'Validade',
      className: 'tabular whitespace-nowrap',
      celula: (c) =>
        c.validoAte ? (
          formatarData(c.validoAte)
        ) : (
          <span className="text-xs text-muted-foreground">sem prazo</span>
        ),
    },
    { chave: 'status', cabecalho: 'Status', celula: (c) => <SeloEditorial status={c.status} /> },
  ];

  return (
    <>
      <PaginaListagem
        recurso="content"
        titulo="Conteúdo da Mind"
        descricao="Os textos institucionais que o agente usa quando a conversa sai do evento e entra na Mind."
        colunas={colunas}
        ordenar="categoria"
        placeholderBusca="Buscar por título ou texto…"
        destinoItem={(c) => `/conteudo/${c.id}`}
        definicoesFiltro={[
          {
            chave: 'categoria',
            rotulo: 'Categoria',
            opcoes: CATEGORIAS_CONTEUDO.map((c) => ({
              valor: c,
              rotulo: ROTULO_CATEGORIA_CONTEUDO[c],
            })),
          },
          {
            chave: 'publico',
            rotulo: 'Público',
            opcoes: PUBLICOS_CONTEUDO.map((p) => ({ valor: p, rotulo: ROTULO_PUBLICO_CONTEUDO[p] })),
          },
          {
            chave: 'status',
            rotulo: 'Status',
            opcoes: STATUS_EDITORIAL.map((s) => ({ valor: s, rotulo: ROTULO_STATUS_EDITORIAL[s] })),
          },
        ]}
        estadoVazio={
          <EstadoVazio
            titulo="Nenhum conteúdo encontrado"
            descricao="Sem conteúdo institucional publicado, o agente muda de assunto quando perguntam sobre a Mind."
          />
        }
      />

      <DrawerConteudo id={id} aoFechar={() => navegar('/conteudo')} />
    </>
  );
}
