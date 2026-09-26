import { useRef } from 'react';
import { useLocation, useNavigate, useParams } from 'react-router-dom';
import { zodResolver } from '@hookform/resolvers/zod';
import { AlertTriangle, CheckCircle2, Lock } from 'lucide-react';
import { produtoCatalogoFormSchema, type ProdutoCatalogo, type ProdutoCatalogoForm } from '@/contracts';
import { useSessao } from '@/hooks/use-sessao';
import { useOrigemRecurso } from '@/services/provider-context';
import { useEdicaoRecurso } from '@/features/comum/use-edicao-recurso';
import {
  OPCOES_TIPO_PRODUTO,
  OPCOES_VERTICAL_PRODUTO,
  paraFormularioProduto,
  payloadDaEdicaoProduto,
  rotuloTipoProduto,
  rotuloVerticalProduto,
} from '@/lib/catalogo';
import { opcoesComAtual } from '@/lib/rotulos';
import { formatarData, formatarDataHora } from '@/lib/format';
import { PaginaListagem, type Coluna } from '@/components/admin/pagina-listagem';
import { DrawerEdicao } from '@/components/admin/drawer-edicao';
import { Campo } from '@/components/admin/campo';
import { EditorDeLista } from '@/components/admin/editor-lista';
import { DialogoConflito } from '@/components/admin/dialogos';
import { AvisoErroEscrita } from '@/components/admin/aviso-escrita';
import { EstadoCarregando, EstadoErro, EstadoVazio } from '@/components/admin/estados';
import { SeloAtivo } from '@/components/admin/selos';
import { SeloCategoria } from '@/components/admin/selo-categoria';
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

/* ============================================================
   CATÁLOGO — `catalogo.produtos`, lido e editado pelo painel
   ============================================================
   A origem de tudo: CRM, conhecimento e agentes referenciam estes
   códigos. A listagem espelha o banco; o drawer edita e, ao salvar,
   manda para o banco SÓ o que mudou (ver `payloadDaEdicaoProduto`).

   O que a tela não deixa editar, e por quê:
   - `codigo` é a chave de 13 tabelas de outros schemas — renomear é
     migração, não formulário;
   - `schemaDados` diz onde mora a base de conhecimento do produto.
   O banco recusa os dois de novo, caso alguém contorne a tela. */

const ID_FORM = 'form-produto';

/* Ativo e Vende são duas perguntas diferentes sobre cada produto — o texto
   é o que a Adriana pediu na tela (26/09/2026). Conferido no banco:
   "vendável agora" é `ativo and vende` (`mind_produto_da_rota_status`), o
   kit do agente só lista quem vende e o CRM comercial só olha os
   pipelines de produto ativo que vende (`mind_crm_comercial`). */
const EXPLICACAO_ATIVO =
  'O produto existe hoje no vocabulário do Mind: os agentes falam dele, o CRM registra negócios com ele e a base de conhecimento está ligada a ele. Inativo é o que ficou para trás, como as edições de 2025, e fica guardado por causa do histórico de vendas e do NPS.';
const EXPLICACAO_VENDE =
  'Dá para comprar agora. O agente só oferece compra quando os dois estão ligados — "vendável agora" é ativo e vende —, e o CRM comercial também só olha os pipelines desses produtos.';

function AtivoEVende() {
  return (
    <div
      className="grid gap-3 rounded-lg border bg-muted/30 p-4 text-sm sm:grid-cols-2"
      data-testid="explicacao-ativo-vende"
    >
      <p>
        <strong>Ativo</strong> — {EXPLICACAO_ATIVO}
      </p>
      <p>
        <strong>Vende</strong> — {EXPLICACAO_VENDE}
      </p>
    </div>
  );
}

/* Radix não aceita item de valor vazio; "sem vertical" usa este. */
const SEM_VERTICAL = '__sem_vertical__';

const PADRAO: ProdutoCatalogoForm = {
  nome: '',
  tipo: '',
  vertical: '',
  categoria: '',
  descricaoCurta: '',
  descricao: '',
  periodo: '',
  ativo: true,
  vende: false,
  vendeDe: '',
  vendeAte: '',
  comecaEm: '',
  encerraEm: '',
  pipelinesHubspot: [],
};

function DrawerProduto({ id, aoFechar }: { id: string | undefined; aoFechar: () => void }) {
  const sessao = useSessao();
  const origem = useOrigemRecurso('products');
  /* O registro que a tela abriu, para o payload levar só o que mudou.
     Um ref porque o hook que carrega o registro é o mesmo que recebe a
     função — e ela só é chamada na hora de salvar. */
  const aberto = useRef<ProdutoCatalogo | undefined>(undefined);

  const edicao = useEdicaoRecurso<'products', ProdutoCatalogoForm>({
    recurso: 'products',
    id,
    resolver: zodResolver(produtoCatalogoFormSchema),
    padrao: PADRAO,
    paraFormulario: paraFormularioProduto,
    paraPayload: (valores) => payloadDaEdicaoProduto(valores, aberto.current),
  });
  aberto.current = edicao.registro;

  const { formulario, registro } = edicao;
  const { errors } = formulario.formState;
  const podeEditar = sessao.pode('editar');
  const vertical = formulario.watch('vertical');
  /* Produto do Institute com turma: as datas vêm dela e ficam travadas. */
  const turma = registro?.datasDaTurma ?? null;

  return (
    <>
      <DrawerEdicao
        aberto={Boolean(id)}
        titulo={registro?.nome || 'Produto'}
        descricao={
          registro ? <span className="font-mono text-xs">{registro.codigo}</span> : undefined
        }
        sujo={edicao.sujo}
        salvando={edicao.salvando}
        podeSalvar={podeEditar}
        idFormulario={ID_FORM}
        aoFechar={aoFechar}
        informacao={registro ? `Atualizado em ${formatarDataHora(registro.atualizadoEm)}` : undefined}
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
            {edicao.salvo && !edicao.sujo ? (
              <Alert variant="info">
                <CheckCircle2 />
                <AlertTitle>Salvo</AlertTitle>
                <AlertDescription>
                  {origem === 'http'
                    ? 'A alteração está no banco. CRM, conhecimento e agentes já leem o valor novo.'
                    : 'Modo demonstração: a alteração ficou só nesta aba e some ao recarregar.'}
                </AlertDescription>
              </Alert>
            ) : null}

            <AvisoErroEscrita erro={edicao.erroEscrita} />

            {edicao.sujo ? (
              <Alert variant="atencao">
                <AlertTriangle />
                <AlertTitle>Alterações não salvas</AlertTitle>
                <AlertDescription>
                  Salvar manda para o banco só o que você mudou. Fechar sem salvar descarta.
                </AlertDescription>
              </Alert>
            ) : null}

            <div className="grid gap-4 sm:grid-cols-2">
              <Campo
                rotulo="Código"
                dica="A chave do produto: 13 tabelas apontam para ela. Não se edita pelo painel."
              >
                {(p) => (
                  <div className="relative">
                    <Lock className="pointer-events-none absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground" />
                    <Input {...p} value={registro?.codigo ?? ''} readOnly disabled className="pl-8 font-mono" />
                  </div>
                )}
              </Campo>
              <Campo
                rotulo="Schema de dados"
                dica="Onde mora a base de conhecimento deste produto. Não se edita pelo painel."
              >
                {(p) => (
                  <Input {...p} value={registro?.schemaDados ?? '—'} readOnly disabled className="font-mono" />
                )}
              </Campo>
            </div>

            <fieldset disabled={!podeEditar} className="space-y-4">
              <Campo rotulo="Nome" obrigatorio erro={errors.nome?.message}>
                {(p) => <Input {...p} {...formulario.register('nome')} />}
              </Campo>

              <div className="grid gap-4 sm:grid-cols-3">
                <Campo rotulo="Tipo" obrigatorio erro={errors.tipo?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('tipo')}
                      onValueChange={(v) => formulario.setValue('tipo', v, { shouldDirty: true })}
                    >
                      <SelectTrigger id={p.id} aria-invalid={p['aria-invalid']}>
                        <SelectValue placeholder="Escolha" />
                      </SelectTrigger>
                      <SelectContent>
                        {opcoesComAtual(OPCOES_TIPO_PRODUTO, formulario.watch('tipo')).map((o) => (
                          <SelectItem key={o.valor} value={o.valor}>
                            {o.rotulo}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>
                <Campo rotulo="Vertical" erro={errors.vertical?.message}>
                  {(p) => (
                    <Select
                      value={vertical || SEM_VERTICAL}
                      onValueChange={(v) =>
                        formulario.setValue('vertical', v === SEM_VERTICAL ? '' : v, { shouldDirty: true })
                      }
                    >
                      <SelectTrigger id={p.id}>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value={SEM_VERTICAL}>Sem vertical</SelectItem>
                        {opcoesComAtual(OPCOES_VERTICAL_PRODUTO, vertical).map((o) => (
                          <SelectItem key={o.valor} value={o.valor}>
                            {o.rotulo}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>
                <Campo rotulo="Categoria" erro={errors.categoria?.message} dica="Mind, VIP, Prime…">
                  {(p) => <Input {...p} {...formulario.register('categoria')} />}
                </Campo>
              </div>

              <Campo rotulo="Descrição curta" erro={errors.descricaoCurta?.message}>
                {(p) => <Textarea rows={2} {...p} {...formulario.register('descricaoCurta')} />}
              </Campo>
              <Campo rotulo="Descrição" erro={errors.descricao?.message}>
                {(p) => <Textarea rows={4} {...p} {...formulario.register('descricao')} />}
              </Campo>

              <div className="grid gap-4 sm:grid-cols-2">
                <div className="space-y-1">
                  <div className="flex items-center gap-3">
                    <Switch
                      id="produto-ativo"
                      checked={formulario.watch('ativo')}
                      onCheckedChange={(v) => formulario.setValue('ativo', v, { shouldDirty: true })}
                    />
                    <Label htmlFor="produto-ativo">Produto ativo</Label>
                  </div>
                  <p className="text-xs text-muted-foreground">{EXPLICACAO_ATIVO}</p>
                </div>
                <div className="space-y-1">
                  <div className="flex items-center gap-3">
                    <Switch
                      id="produto-vende"
                      checked={formulario.watch('vende')}
                      onCheckedChange={(v) => formulario.setValue('vende', v, { shouldDirty: true })}
                    />
                    <Label htmlFor="produto-vende">Está à venda</Label>
                  </div>
                  <p className="text-xs text-muted-foreground">{EXPLICACAO_VENDE}</p>
                </div>
              </div>

              <div className="grid gap-4 sm:grid-cols-2">
                <Campo
                  rotulo="Vende a partir de"
                  erro={errors.vendeDe?.message}
                  dica="Horário de Brasília. Vazio = desde sempre."
                >
                  {(p) => <Input type="datetime-local" step={1} {...p} {...formulario.register('vendeDe')} />}
                </Campo>
                <Campo
                  rotulo="Vende até"
                  erro={errors.vendeAte?.message}
                  dica="Horário de Brasília. Vazio = sem prazo."
                >
                  {(p) => <Input type="datetime-local" step={1} {...p} {...formulario.register('vendeAte')} />}
                </Campo>
              </div>

              {turma ? (
                <Alert variant="info" data-testid="datas-da-turma">
                  <Lock />
                  <AlertDescription>
                    Estas datas vêm da turma <code className="font-mono">{turma.programa}</code>, em{' '}
                    <code className="font-mono">institute.programas</code> — é de lá que o site, o
                    checkout e os agentes leem. Aqui elas só aparecem; mudam na turma.
                    {turma.inicioPrevisto ? ' O início ainda é previsão.' : ''}
                  </AlertDescription>
                </Alert>
              ) : null}
              <div className="grid gap-4 sm:grid-cols-3">
                <Campo
                  rotulo="Começa em"
                  erro={errors.comecaEm?.message}
                  dica={turma ? 'Da turma. Não se edita aqui.' : 'Quando acontece.'}
                >
                  {(p) => (
                    <Input type="date" {...p} {...formulario.register('comecaEm')} disabled={Boolean(turma)} />
                  )}
                </Campo>
                <Campo
                  rotulo="Encerra em"
                  erro={errors.encerraEm?.message}
                  dica={turma ? 'Da turma. Não se edita aqui.' : undefined}
                >
                  {(p) => (
                    <Input type="date" {...p} {...formulario.register('encerraEm')} disabled={Boolean(turma)} />
                  )}
                </Campo>
                <Campo rotulo="Período" erro={errors.periodo?.message} dica="Em texto: outubro de 2025.">
                  {(p) => <Input {...p} {...formulario.register('periodo')} />}
                </Campo>
              </div>

              <Campo
                rotulo="Pipelines do HubSpot"
                dica="IDs dos pipelines de negócio em que este produto é vendido hoje."
              >
                {(p) => (
                  <EditorDeLista
                    {...p}
                    valor={formulario.watch('pipelinesHubspot')}
                    aoMudar={(proximo) =>
                      formulario.setValue('pipelinesHubspot', proximo, { shouldDirty: true })
                    }
                    placeholder="ID do pipeline e Enter"
                    vazio="Nenhum pipeline."
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

function JanelaDeVenda({ p }: { p: ProdutoCatalogo }) {
  if (!p.vendeDe && !p.vendeAte) return <span className="text-xs text-muted-foreground">sem prazo</span>;
  return (
    <span className="text-xs text-muted-foreground">
      {p.vendeDe ? formatarDataHora(p.vendeDe) : 'desde sempre'} → {p.vendeAte ? formatarDataHora(p.vendeAte) : 'sem prazo'}
    </span>
  );
}

export function PaginaCatalogo() {
  const { id } = useParams();
  const navegar = useNavigate();
  /* Fechar o drawer volta à lista como estava: busca, filtros, página e ordem. */
  const { search } = useLocation();

  const colunas: Coluna<ProdutoCatalogo>[] = [
    {
      chave: 'produto',
      cabecalho: 'Produto',
      ordenarPor: 'nome',
      celula: (p) => (
        <div className="min-w-56">
          <p className="font-semibold">{p.nome}</p>
          <p className="font-mono text-xs text-muted-foreground">{p.codigo}</p>
        </div>
      ),
    },
    {
      chave: 'vertical',
      cabecalho: 'Vertical',
      ordenarPor: 'vertical',
      celula: (p) =>
        p.vertical ? (
          <SeloCategoria rotulo={rotuloVerticalProduto(p.vertical)} />
        ) : (
          <span className="text-xs text-muted-foreground">—</span>
        ),
    },
    {
      chave: 'tipo',
      cabecalho: 'Tipo',
      ordenarPor: 'tipo',
      celula: (p) => <SeloCategoria rotulo={rotuloTipoProduto(p.tipo)} variante="secondary" />,
    },
    { chave: 'ativo', cabecalho: 'Situação', ordenarPor: 'ativo', celula: (p) => <SeloAtivo ativo={p.ativo} /> },
    {
      chave: 'vende',
      cabecalho: 'Venda',
      ordenarPor: 'vende',
      celula: (p) =>
        p.vende ? <Badge variant="sucesso">à venda</Badge> : <Badge variant="neutro">não vende</Badge>,
    },
    {
      chave: 'janela',
      cabecalho: 'Janela de venda',
      /* Pela data em que sai de venda: é a que quase todo produto com
         janela tem preenchida. */
      ordenarPor: 'vendeAte',
      className: 'whitespace-nowrap tabular',
      celula: (p) => <JanelaDeVenda p={p} />,
    },
    {
      chave: 'acontece',
      cabecalho: 'Acontece',
      ordenarPor: 'comecaEm',
      className: 'whitespace-nowrap tabular',
      celula: (p) =>
        p.comecaEm || p.encerraEm ? (
          <span className="text-xs text-muted-foreground">
            {formatarData(p.comecaEm)} → {formatarData(p.encerraEm)}
          </span>
        ) : (
          <span className="text-xs text-muted-foreground">{p.periodo || '—'}</span>
        ),
    },
  ];

  return (
    <>
      <PaginaListagem
        recurso="products"
        titulo="Catálogo"
        descricao="A lista oficial de produtos do Mind — a origem de tudo: CRM, conhecimento e agentes usam estes códigos. Abra um produto para editar; salvar grava no banco."
        colunas={colunas}
        placeholderBusca="Buscar por nome, código ou descrição…"
        destinoItem={(p) => `/catalogo/${p.id}`}
        definicoesFiltro={[
          {
            chave: 'vertical',
            rotulo: 'Vertical',
            opcoes: [
              ...OPCOES_VERTICAL_PRODUTO.map((o) => ({ valor: o.valor, rotulo: o.rotulo })),
              { valor: 'null', rotulo: 'Sem vertical' },
            ],
          },
          {
            chave: 'tipo',
            rotulo: 'Tipo',
            opcoes: OPCOES_TIPO_PRODUTO.map((o) => ({ valor: o.valor, rotulo: o.rotulo })),
          },
          {
            chave: 'ativo',
            rotulo: 'Situação',
            opcoes: [
              { valor: 'true', rotulo: 'Ativos' },
              { valor: 'false', rotulo: 'Inativos' },
            ],
          },
          {
            chave: 'vende',
            rotulo: 'Venda',
            opcoes: [
              { valor: 'true', rotulo: 'À venda' },
              { valor: 'false', rotulo: 'Não vende' },
            ],
          },
        ]}
        antesDaTabela={() => <AtivoEVende />}
        estadoVazio={
          <EstadoVazio
            titulo="Nenhum produto no recorte"
            descricao="Nenhum produto bate com a busca e os filtros atuais."
          />
        }
      />

      <DrawerProduto id={id} aoFechar={() => navegar({ pathname: '/catalogo', search })} />
    </>
  );
}
