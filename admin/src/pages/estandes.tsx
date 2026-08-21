import { useMemo } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { zodResolver } from '@hookform/resolvers/zod';
import { AlertTriangle } from 'lucide-react';
import {
  CATEGORIAS_ESTANDE,
  ROTULO_CATEGORIA_ESTANDE,
  estandeFormSchema,
  type Estande,
  type EstandeForm,
} from '@/contracts';
import { useLista, TODAS_AS_OPCOES } from '@/hooks/use-recurso';
import { useSessao } from '@/hooks/use-sessao';
import { useEdicaoRecurso } from '@/features/comum/use-edicao-recurso';
import { PaginaListagem, type Coluna } from '@/components/admin/pagina-listagem';
import { DrawerEdicao } from '@/components/admin/drawer-edicao';
import { Campo } from '@/components/admin/campo';
import { AcoesEditoriais } from '@/components/admin/acoes-editoriais';
import { DialogoConflito } from '@/components/admin/dialogos';
import { AvisoErroEscrita } from '@/components/admin/aviso-escrita';
import { EstadoCarregando, EstadoErro, EstadoVazio } from '@/components/admin/estados';
import { SeloAtivo } from '@/components/admin/selos';
import { Badge } from '@/components/ui/badge';
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

const ID_FORM = 'form-estande';

const PADRAO: EstandeForm = {
  nome: '',
  slug: '',
  categoria: 'institucional',
  descricao: '',
  espacoId: null,
  site: '',
  contato: '',
  ativo: true,
};

function DrawerEstande({ id, aoFechar }: { id: string | undefined; aoFechar: () => void }) {
  const sessao = useSessao();
  const espacos = useLista('spaces', { ordenar: 'nome', ...TODAS_AS_OPCOES });

  const edicao = useEdicaoRecurso<'booths', EstandeForm>({
    recurso: 'booths',
    id,
    resolver: zodResolver(estandeFormSchema),
    padrao: PADRAO,
    paraFormulario: (e: Estande) => ({
      nome: e.nome,
      slug: e.slug,
      categoria: e.categoria,
      descricao: e.descricao,
      espacoId: e.espacoId,
      site: e.site,
      contato: e.contato,
      ativo: e.ativo,
    }),
  });

  const { formulario, registro } = edicao;
  const { errors } = formulario.formState;
  const podeEditar = sessao.pode('editar');

  return (
    <>
      <DrawerEdicao
        aberto={Boolean(id)}
        titulo={registro?.nome || 'Estande'}
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
            <AvisoErroEscrita erro={edicao.erroEscrita} />

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
                <Campo rotulo="Categoria" erro={errors.categoria?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('categoria')}
                      onValueChange={(v) =>
                        formulario.setValue('categoria', v as EstandeForm['categoria'], {
                          shouldDirty: true,
                        })
                      }
                    >
                      <SelectTrigger id={p.id}>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {CATEGORIAS_ESTANDE.map((c) => (
                          <SelectItem key={c} value={c}>
                            {ROTULO_CATEGORIA_ESTANDE[c]}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>
                <Campo rotulo="Espaço" erro={errors.espacoId?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('espacoId') ?? 'nenhum'}
                      onValueChange={(v) =>
                        formulario.setValue('espacoId', v === 'nenhum' ? null : v, {
                          shouldDirty: true,
                        })
                      }
                    >
                      <SelectTrigger id={p.id}>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="nenhum">Sem espaço definido</SelectItem>
                        {(espacos.data?.itens ?? []).map((e) => (
                          <SelectItem key={e.id} value={e.id}>
                            {e.nome}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>
              </div>

              <Campo rotulo="Descrição" erro={errors.descricao?.message}>
                {(p) => <Textarea rows={3} {...p} {...formulario.register('descricao')} />}
              </Campo>

              <div className="grid gap-4 sm:grid-cols-2">
                <Campo rotulo="Site" erro={errors.site?.message} dica="URL completa, com https://.">
                  {(p) => <Input {...p} {...formulario.register('site')} />}
                </Campo>
                <Campo
                  rotulo="Contato"
                  erro={errors.contato?.message}
                  dica="Contato comercial do expositor — não use dado pessoal de participante."
                >
                  {(p) => <Input {...p} {...formulario.register('contato')} />}
                </Campo>
              </div>

              <div className="flex items-center gap-3">
                <Switch
                  id="estande-ativo"
                  checked={formulario.watch('ativo')}
                  onCheckedChange={(v) => formulario.setValue('ativo', v, { shouldDirty: true })}
                />
                <Label htmlFor="estande-ativo">Estande ativo</Label>
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

export function PaginaEstandes() {
  const { id } = useParams();
  const navegar = useNavigate();
  const espacos = useLista('spaces', { ordenar: 'nome', ...TODAS_AS_OPCOES });

  const nomeEspaco = useMemo(() => {
    const mapa = new Map((espacos.data?.itens ?? []).map((e) => [e.id, e.nome]));
    return (idEspaco: string | null) => (idEspaco ? (mapa.get(idEspaco) ?? '—') : null);
  }, [espacos.data]);

  const colunas: Coluna<Estande>[] = [
    {
      chave: 'nome',
      cabecalho: 'Estande',
      celula: (e) => (
        <div className="min-w-48">
          <p className="font-semibold">{e.nome}</p>
          <p className="font-mono text-xs text-muted-foreground">{e.slug}</p>
        </div>
      ),
    },
    {
      chave: 'categoria',
      cabecalho: 'Categoria',
      celula: (e) => <Badge variant="outline">{ROTULO_CATEGORIA_ESTANDE[e.categoria]}</Badge>,
    },
    {
      chave: 'espaco',
      cabecalho: 'Espaço',
      celula: (e) =>
        e.espacoId ? (
          nomeEspaco(e.espacoId)
        ) : (
          <Badge variant="atencao">sem espaço</Badge>
        ),
    },
    {
      chave: 'site',
      cabecalho: 'Site',
      celula: (e) =>
        e.site ? (
          <span className="text-xs text-muted-foreground">{e.site.replace(/^https?:\/\//, '')}</span>
        ) : (
          <span className="text-xs text-muted-foreground">—</span>
        ),
    },
    { chave: 'ativo', cabecalho: 'Situação', celula: (e) => <SeloAtivo ativo={e.ativo} /> },
  ];

  return (
    <>
      <PaginaListagem
        recurso="booths"
        titulo="Estandes"
        descricao="Quem expõe no Summit e onde cada um fica."
        colunas={colunas}
        ordenar="nome"
        placeholderBusca="Buscar por nome ou descrição…"
        destinoItem={(e) => `/estandes/${e.id}`}
        definicoesFiltro={[
          {
            chave: 'categoria',
            rotulo: 'Categoria',
            opcoes: CATEGORIAS_ESTANDE.map((c) => ({
              valor: c,
              rotulo: ROTULO_CATEGORIA_ESTANDE[c],
            })),
          },
          {
            chave: 'ativo',
            rotulo: 'Situação',
            opcoes: [
              { valor: 'true', rotulo: 'Ativos' },
              { valor: 'false', rotulo: 'Inativos' },
            ],
          },
        ]}
        estadoVazio={
          <EstadoVazio
            titulo="Nenhum estande cadastrado"
            descricao="Quando os expositores forem confirmados, eles entram aqui e o agente passa a saber indicar cada um."
          />
        }
      />

      <DrawerEstande id={id} aoFechar={() => navegar('/estandes')} />
    </>
  );
}
