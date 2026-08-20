import { useNavigate, useParams } from 'react-router-dom';
import { zodResolver } from '@hookform/resolvers/zod';
import { AlertTriangle } from 'lucide-react';
import {
  PUBLICOS_OFERTA,
  ROTULO_PUBLICO_OFERTA,
  ofertaFormSchema,
  type Oferta,
  type OfertaForm,
} from '@/contracts';
import { useSessao } from '@/hooks/use-sessao';
import { useEdicaoRecurso } from '@/features/comum/use-edicao-recurso';
import { alertasDaOferta } from '@/lib/pendencias';
import { formatarData, formatarMoeda } from '@/lib/format';
import { PaginaListagem, type Coluna } from '@/components/admin/pagina-listagem';
import { DrawerEdicao } from '@/components/admin/drawer-edicao';
import { Campo } from '@/components/admin/campo';
import { AcoesEditoriais } from '@/components/admin/acoes-editoriais';
import { DialogoConflito } from '@/components/admin/dialogos';
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

const ID_FORM = 'form-oferta';

const PADRAO: OfertaForm = {
  codigo: '',
  nome: '',
  descricao: '',
  moeda: 'BRL',
  valorCentavos: null,
  condicoesPagamento: '',
  checkoutUrl: '',
  elegibilidade: '',
  publico: 'geral',
  dataInicio: '',
  dataFim: '',
  ativo: true,
};

function hojeISO() {
  return new Date().toISOString().slice(0, 10);
}

function DrawerOferta({ id, aoFechar }: { id: string | undefined; aoFechar: () => void }) {
  const sessao = useSessao();

  const edicao = useEdicaoRecurso<'offers', OfertaForm>({
    recurso: 'offers',
    id,
    resolver: zodResolver(ofertaFormSchema),
    padrao: PADRAO,
    paraFormulario: (o: Oferta) => ({
      codigo: o.codigo,
      nome: o.nome,
      descricao: o.descricao,
      moeda: o.moeda,
      valorCentavos: o.valorCentavos,
      condicoesPagamento: o.condicoesPagamento,
      checkoutUrl: o.checkoutUrl,
      elegibilidade: o.elegibilidade,
      publico: o.publico,
      dataInicio: o.dataInicio,
      dataFim: o.dataFim,
      ativo: o.ativo,
    }),
  });

  const { formulario, registro } = edicao;
  const { errors } = formulario.formState;
  const podeEditar = sessao.pode('editar');
  const alertas = registro ? alertasDaOferta(registro, hojeISO()) : [];

  return (
    <>
      <DrawerEdicao
        aberto={Boolean(id)}
        titulo={registro?.nome || 'Oferta'}
        descricao={registro ? `${registro.codigo} · ${formatarMoeda(registro.valorCentavos, registro.moeda)}` : undefined}
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
            {alertas.length > 0 ? (
              <Alert variant={alertas.some((a) => a.nivel === 'erro') ? 'erro' : 'atencao'}>
                <AlertTriangle />
                <AlertTitle>Esta oferta tem problema</AlertTitle>
                <AlertDescription>
                  <ul className="list-disc pl-4">
                    {alertas.map((a) => (
                      <li key={a.mensagem}>{a.mensagem}</li>
                    ))}
                  </ul>
                </AlertDescription>
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
              <div className="grid gap-4 sm:grid-cols-2">
                <Campo rotulo="Código" obrigatorio erro={errors.codigo?.message}>
                  {(p) => <Input {...p} {...formulario.register('codigo')} />}
                </Campo>
                <Campo rotulo="Nome" obrigatorio erro={errors.nome?.message}>
                  {(p) => <Input {...p} {...formulario.register('nome')} />}
                </Campo>
              </div>

              <Campo rotulo="Descrição" erro={errors.descricao?.message}>
                {(p) => <Textarea rows={2} {...p} {...formulario.register('descricao')} />}
              </Campo>

              <div className="grid gap-4 sm:grid-cols-3">
                <Campo rotulo="Moeda" erro={errors.moeda?.message}>
                  {(p) => <Input {...p} {...formulario.register('moeda')} />}
                </Campo>
                <Campo
                  rotulo="Valor (centavos)"
                  erro={errors.valorCentavos?.message}
                  dica={formatarMoeda(
                    formulario.watch('valorCentavos'),
                    formulario.watch('moeda') || 'BRL',
                  )}
                  className="sm:col-span-2"
                >
                  {(p) => (
                    <Input
                      type="number"
                      min={0}
                      {...p}
                      {...formulario.register('valorCentavos', {
                        setValueAs: (v) => (v === '' || v === null ? null : Number(v)),
                      })}
                    />
                  )}
                </Campo>
              </div>

              <Campo rotulo="Condições de pagamento" erro={errors.condicoesPagamento?.message}>
                {(p) => <Textarea rows={2} {...p} {...formulario.register('condicoesPagamento')} />}
              </Campo>

              <Campo
                rotulo="Checkout"
                erro={errors.checkoutUrl?.message}
                dica="Sem esta URL, o agente não tem para onde mandar quem quer comprar."
              >
                {(p) => <Input {...p} {...formulario.register('checkoutUrl')} />}
              </Campo>

              <Campo rotulo="Elegibilidade" erro={errors.elegibilidade?.message}>
                {(p) => <Textarea rows={2} {...p} {...formulario.register('elegibilidade')} />}
              </Campo>

              <div className="grid gap-4 sm:grid-cols-3">
                <Campo rotulo="Público" erro={errors.publico?.message}>
                  {(p) => (
                    <Select
                      value={formulario.watch('publico')}
                      onValueChange={(v) =>
                        formulario.setValue('publico', v as OfertaForm['publico'], {
                          shouldDirty: true,
                        })
                      }
                    >
                      <SelectTrigger id={p.id}>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {PUBLICOS_OFERTA.map((pub) => (
                          <SelectItem key={pub} value={pub}>
                            {ROTULO_PUBLICO_OFERTA[pub]}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                </Campo>
                <Campo rotulo="Data inicial" obrigatorio erro={errors.dataInicio?.message}>
                  {(p) => <Input type="date" {...p} {...formulario.register('dataInicio')} />}
                </Campo>
                <Campo rotulo="Data final" obrigatorio erro={errors.dataFim?.message}>
                  {(p) => <Input type="date" {...p} {...formulario.register('dataFim')} />}
                </Campo>
              </div>

              <div className="flex items-center gap-3">
                <Switch
                  id="oferta-ativa"
                  checked={formulario.watch('ativo')}
                  onCheckedChange={(v) => formulario.setValue('ativo', v, { shouldDirty: true })}
                />
                <Label htmlFor="oferta-ativa">Oferta ativa</Label>
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

export function PaginaOfertas() {
  const { id } = useParams();
  const navegar = useNavigate();
  const hoje = hojeISO();

  const colunas: Coluna<Oferta>[] = [
    {
      chave: 'oferta',
      cabecalho: 'Oferta',
      celula: (o) => (
        <div className="min-w-48">
          <p className="font-semibold">{o.nome}</p>
          <p className="font-mono text-xs text-muted-foreground">{o.codigo}</p>
        </div>
      ),
    },
    {
      chave: 'valor',
      cabecalho: 'Valor',
      className: 'tabular whitespace-nowrap',
      celula: (o) =>
        o.valorCentavos === null ? (
          <Badge variant="destructive">sem valor</Badge>
        ) : (
          <span className="font-semibold">{formatarMoeda(o.valorCentavos, o.moeda)}</span>
        ),
    },
    {
      chave: 'publico',
      cabecalho: 'Público',
      celula: (o) => <Badge variant="outline">{ROTULO_PUBLICO_OFERTA[o.publico]}</Badge>,
    },
    {
      chave: 'vigencia',
      cabecalho: 'Vigência',
      className: 'tabular whitespace-nowrap',
      celula: (o) => (
        <span className="text-xs text-muted-foreground">
          {formatarData(o.dataInicio)} → {formatarData(o.dataFim)}
        </span>
      ),
    },
    {
      chave: 'alertas',
      cabecalho: 'Alertas',
      celula: (o) => {
        const alertas = alertasDaOferta(o, hoje);
        if (alertas.length === 0) return <span className="text-xs text-muted-foreground">—</span>;
        return (
          <ul className="flex max-w-72 flex-wrap gap-1">
            {alertas.map((a) => (
              <li key={a.mensagem}>
                <Badge variant={a.nivel === 'erro' ? 'destructive' : 'atencao'} title={a.mensagem}>
                  {a.mensagem.split(':')[0].replace('.', '')}
                </Badge>
              </li>
            ))}
          </ul>
        );
      },
    },
    { chave: 'ativo', cabecalho: 'Situação', celula: (o) => <SeloAtivo ativo={o.ativo} /> },
  ];

  return (
    <>
      <PaginaListagem
        recurso="offers"
        titulo="Ingressos e ofertas"
        descricao="Códigos, valores e checkout. Valores em BRL; oferta sem checkout ou vencida é marcada na linha."
        colunas={colunas}
        ordenar="codigo"
        placeholderBusca="Buscar por código, nome ou elegibilidade…"
        destinoItem={(o) => `/ofertas/${o.id}`}
        definicoesFiltro={[
          {
            chave: 'publico',
            rotulo: 'Público',
            opcoes: PUBLICOS_OFERTA.map((p) => ({ valor: p, rotulo: ROTULO_PUBLICO_OFERTA[p] })),
          },
          {
            chave: 'ativo',
            rotulo: 'Situação',
            opcoes: [
              { valor: 'true', rotulo: 'Ativas' },
              { valor: 'false', rotulo: 'Inativas' },
            ],
          },
        ]}
        estadoVazio={
          <EstadoVazio
            titulo="Nenhuma oferta encontrada"
            descricao="Sem oferta cadastrada, o agente não consegue responder quanto custa nem para onde ir comprar."
          />
        }
      />

      <DrawerOferta id={id} aoFechar={() => navegar('/ofertas')} />
    </>
  );
}
