import { useEffect, useRef, useState, type ReactNode } from 'react';
import { useLocation, useNavigate, useParams } from 'react-router-dom';
import { Controller, useFieldArray, useForm, type UseFormReturn } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { AlertTriangle, Archive, CheckCircle2, Copy, History, Info, Lock, Plus, Rocket, Trash2 } from 'lucide-react';
import {
  SITUACOES_OFERTA,
  TIPOS_OFERTA,
  ofertaFormSchema,
  type OfertaCatalogo,
  type OfertaForm,
  type PrecoOferta,
} from '@/contracts';
import { useCriar, useItem, useLista } from '@/hooks/use-recurso';
import { useSessao } from '@/hooks/use-sessao';
import { useOrigemRecurso } from '@/services/provider-context';
import { useEdicaoRecurso } from '@/features/comum/use-edicao-recurso';
import { formatarDataHora, formatarReais } from '@/lib/format';
import {
  BONUS_VAZIO,
  EXIGENCIA_VAZIA,
  FORMULARIO_VAZIO,
  PRECO_VAZIO,
  conferirParcelas,
  duplicarOferta,
  motivoDoBloqueio,
  mudancasDePreco,
  paraFormularioOferta,
  payloadDaOferta,
  resumoDaAlteracao,
} from '@/lib/ofertas';
import { PaginaListagem, type Coluna } from '@/components/admin/pagina-listagem';
import { DrawerEdicao } from '@/components/admin/drawer-edicao';
import { Campo as CampoForm } from '@/components/admin/campo';
import { DialogoConfirmacao, DialogoConflito } from '@/components/admin/dialogos';
import { AvisoErroEscrita } from '@/components/admin/aviso-escrita';
import { EstadoCarregando, EstadoErro, EstadoVazio } from '@/components/admin/estados';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Badge, type BadgeProps } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetFooter,
  SheetHeader,
  SheetTitle,
} from '@/components/ui/sheet';

/* ============================================================
   OFERTAS — o schema `catalogo`, lido e editado pelo painel
   ============================================================
   Decisão da Adriana (26/09/2026): preço, oferta, order bump e cupom
   moram no schema `catalogo`, e "o painel é o controle deste schema".
   Cada oferta tem os preços (um por produto, com o código vendável), o
   bônus e o que ela exige — order bump (no carrinho) e upgrade (já
   comprado) —, e a situação calculada pelo banco com as mesmas pontas de
   janela do site.

   Passo 4 de docs/PLANO_OFERTAS_PASSO_A_PASSO.md: criar (a oferta nasce
   desligada, como rascunho), editar, duplicar, pôr no ar e tirar do ar.
   Nada se apaga. As regras moram no banco (`mind_admin_mutate_ofertas`) e
   voltam com frase própria; "pôr no ar" fica travado, com o motivo, até
   um site ler o catálogo — o Institute, na virada (Passo 5). O histórico
   importado é só consulta: dá para duplicar. */

const RECURSO = 'offers' as const;
const CAMINHO = '/ofertas';

const VERTICAIS = [
  { valor: 'institute', rotulo: 'Institute' },
  { valor: 'summit', rotulo: 'Summit' },
  { valor: 'dash', rotulo: 'Dash' },
  { valor: 'eventos', rotulo: 'Eventos' },
  { valor: 'outro', rotulo: 'Outro' },
];

const MEIOS = [
  { valor: 'cartao', rotulo: 'Cartão' },
  { valor: 'pix', rotulo: 'Pix' },
  { valor: 'boleto', rotulo: 'Boleto' },
];

/* Radix não aceita item de valor vazio; "nenhum" usa este. */
const NENHUM = '__nenhum__';

const COR_SITUACAO: Record<string, BadgeProps['variant']> = {
  no_ar: 'sucesso',
  so_link: 'roxo',
  agendada: 'atencao',
  encerrada: 'neutro',
  desligada: 'neutro',
  historico: 'outline',
};

export function SeloSituacaoOferta({ situacao }: { situacao: string }) {
  const def = SITUACOES_OFERTA.find((s) => s.valor === situacao);
  return (
    <Badge variant={COR_SITUACAO[situacao] ?? 'outline'} title={def?.dica}>
      {def?.rotulo ?? situacao}
    </Badge>
  );
}

function rotuloTipo(tipo: string): string {
  return TIPOS_OFERTA.find((t) => t.valor === tipo)?.rotulo ?? tipo;
}

/** "R$ 1.200,00 · 12× de R$ 100,00", como o preço aparece para quem compra. */
function precoPorExtenso(p: PrecoOferta): string {
  const avista = formatarReais(p.valor, p.moeda);
  if (p.parcelas && p.valorParcela !== null) {
    return `${avista} · ${p.parcelas}× de ${formatarReais(p.valorParcela, p.moeda)}`;
  }
  return avista;
}

function prazo(o: Pick<OfertaCatalogo, 'iniciaEm' | 'encerraEm'>): string {
  if (!o.iniciaEm && !o.encerraEm) return 'sem prazo';
  if (!o.iniciaEm) return `até ${formatarDataHora(o.encerraEm)}`;
  if (!o.encerraEm) return `a partir de ${formatarDataHora(o.iniciaEm)}`;
  return `${formatarDataHora(o.iniciaEm)} → ${formatarDataHora(o.encerraEm)}`;
}

/** Valor de coluna como texto legível, sem esconder o que o banco guarda. */
function valorDaColuna(valor: unknown): string {
  if (valor === null || valor === undefined || valor === '') return '—';
  if (typeof valor === 'boolean') return valor ? 'sim' : 'não';
  if (Array.isArray(valor)) {
    if (valor.length === 0) return '—';
    return valor.every((v) => typeof v !== 'object') ? valor.join(', ') : JSON.stringify(valor, null, 2);
  }
  if (typeof valor === 'object') return JSON.stringify(valor, null, 2);
  return String(valor);
}

function Campo({ rotulo, children }: { rotulo: string; children: ReactNode }) {
  return (
    <div className="space-y-0.5">
      <dt className="text-xs font-semibold text-muted-foreground">{rotulo}</dt>
      <dd>{children}</dd>
    </div>
  );
}

function Secao({ titulo, children, testId, acoes }: { titulo: string; children: ReactNode; testId?: string; acoes?: ReactNode }) {
  return (
    <section className="space-y-2" data-testid={testId}>
      <div className="flex items-center justify-between gap-2">
        <h3 className="text-xs font-black uppercase tracking-wide text-muted-foreground">{titulo}</h3>
        {acoes}
      </div>
      {children}
    </section>
  );
}

/** As colunas do banco, uma a uma — o que a tela resume, cru. */
function ColunasDoBanco({ oferta }: { oferta: OfertaCatalogo }) {
  return (
    <dl className="divide-y rounded-lg border text-sm" data-testid="colunas-da-oferta">
      {Object.entries(oferta)
        .filter(([coluna]) => !['precos', 'bonus', 'requer', 'origem', 'alteracoes'].includes(coluna))
        .map(([coluna, valor]) => {
          const texto = valorDaColuna(valor);
          return (
            <div key={coluna} className="grid gap-1 px-3 py-2 sm:grid-cols-[12rem_1fr]">
              <dt className="font-mono text-xs text-muted-foreground">{coluna}</dt>
              <dd className="min-w-0 break-words">
                {texto.includes('\n') ? <pre className="whitespace-pre-wrap font-mono text-xs">{texto}</pre> : texto}
              </dd>
            </div>
          );
        })}
    </dl>
  );
}

/** Quem mudou o quê e quando, da auditoria. */
function HistoricoDeAlteracoes({ oferta }: { oferta: OfertaCatalogo }) {
  const linhas = oferta.alteracoes ?? [];
  return (
    <Secao titulo="Histórico de alterações" testId="historico-alteracoes">
      {linhas.length === 0 ? (
        <p className="text-sm text-muted-foreground">Nenhuma alteração pelo painel ainda.</p>
      ) : (
        <ul className="divide-y rounded-lg border text-sm">
          {linhas.map((a) => (
            <li key={`${a.em}-${a.acao}`} className="flex flex-wrap items-baseline justify-between gap-2 px-3 py-2">
              <span className="font-medium">{resumoDaAlteracao(a)}</span>
              <span className="text-xs text-muted-foreground">
                {a.por ?? 'alguém do painel'} · {formatarDataHora(a.em)}
              </span>
            </li>
          ))}
        </ul>
      )}
    </Secao>
  );
}

/* ============================================================
   SÓ CONSULTA — o histórico importado
   ============================================================ */

function DetalheOferta({
  oferta,
  podeDuplicar,
  aoDuplicar,
  aoFechar,
}: {
  oferta: OfertaCatalogo;
  podeDuplicar: boolean;
  aoDuplicar: () => void;
  aoFechar: () => void;
}) {
  return (
    <Sheet open onOpenChange={(aberto) => (!aberto ? aoFechar() : undefined)}>
      <SheetContent side="right" className="w-full p-0 sm:max-w-3xl">
        <SheetHeader>
          <SheetTitle>{oferta.nome}</SheetTitle>
          <SheetDescription>
            <span className="font-mono text-xs">{oferta.codigo}</span>
          </SheetDescription>
        </SheetHeader>

        <div className="flex-1 space-y-6 overflow-y-auto p-5">
          <dl className="grid gap-3 rounded-lg border bg-muted/30 p-4 text-sm sm:grid-cols-3">
            <Campo rotulo="Situação">
              <SeloSituacaoOferta situacao={oferta.situacao} />
              <p className="mt-1 text-xs text-muted-foreground">
                {SITUACOES_OFERTA.find((s) => s.valor === oferta.situacao)?.dica}
              </p>
            </Campo>
            <Campo rotulo="Tipo">{rotuloTipo(oferta.tipo)}</Campo>
            <Campo rotulo="Prazo (horário de Brasília)">{prazo(oferta)}</Campo>
            <Campo rotulo="No site">{oferta.noSite ? 'Sim — o site lê esta oferta agora' : 'Não'}</Campo>
            <Campo rotulo="Aparece no site">{oferta.publico ? 'Sim' : 'Não (só por link)'}</Campo>
            <Campo rotulo="Meios de pagamento">
              {oferta.meiosPagamento.length ? oferta.meiosPagamento.join(', ') : '—'}
            </Campo>
          </dl>

          <Secao titulo={`Preços (${oferta.precos.length})`} testId="precos-da-oferta">
            {oferta.precos.length === 0 ? (
              <p className="text-sm text-muted-foreground">Nenhum preço cadastrado.</p>
            ) : (
              <ul className="divide-y rounded-lg border text-sm">
                {oferta.precos.map((p) => (
                  <li key={p.codigo} className="space-y-1 px-3 py-2">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-semibold">{p.nome ?? p.produtoNome ?? p.produtoCodigo}</span>
                      {p.noSite ? <Badge variant="sucesso">no site</Badge> : null}
                    </div>
                    <p className="tabular">{precoPorExtenso(p)}</p>
                    {p.valorRiscado !== null ? (
                      <p className="text-xs text-muted-foreground">de {formatarReais(p.valorRiscado, p.moeda)} (riscado)</p>
                    ) : null}
                    <p className="text-xs text-muted-foreground">
                      Produto <span className="font-mono">{p.produtoCodigo}</span> · código vendável{' '}
                      <span className="font-mono">{p.codigo}</span>
                    </p>
                    {p.checkoutUrl ? (
                      <p className="break-all text-xs text-muted-foreground">Link de compra: {p.checkoutUrl}</p>
                    ) : null}
                    {p.eduzz ? (
                      <p className="text-xs text-muted-foreground" data-testid={`eduzz-${p.codigo}`}>
                        Eduzz ({p.skuExterno}): preço de lista atual {formatarReais(p.eduzz.preco)}
                        {p.eduzz.lidoEm ? ` · lido em ${formatarDataHora(p.eduzz.lidoEm)}` : ''}
                        {p.eduzz.arquivado ? ' · arquivado lá' : ''}
                      </p>
                    ) : null}
                  </li>
                ))}
              </ul>
            )}
          </Secao>

          {oferta.bonus.length ? (
            <Secao titulo={`Bônus (${oferta.bonus.length})`} testId="bonus-da-oferta">
              <ul className="divide-y rounded-lg border text-sm">
                {oferta.bonus.map((b) => (
                  <li key={`${b.produtoCodigo}-${b.inclusoCodigo}`} className="space-y-1 px-3 py-2">
                    <p className="font-semibold">{b.nome ?? b.inclusoNome ?? b.inclusoCodigo}</p>
                    {b.descricao ? <p className="text-xs">{b.descricao}</p> : null}
                    <p className="text-xs text-muted-foreground">
                      Entrega <span className="font-mono">{b.inclusoCodigo}</span>
                      {b.valorReferencia !== null ? ` · vale ${formatarReais(b.valorReferencia)}` : ''}
                      {b.encerraEm ? ` · até ${formatarDataHora(b.encerraEm)}` : ''}
                    </p>
                  </li>
                ))}
              </ul>
            </Secao>
          ) : null}

          {oferta.requer.length ? (
            <Secao titulo="Exige (order bump / upgrade)" testId="exigencias-da-oferta">
              <ul className="divide-y rounded-lg border text-sm">
                {oferta.requer.map((r) => (
                  <li key={r.produtoCodigo} className="px-3 py-2">
                    <p>
                      {r.modo === 'posse' ? 'Só para quem já comprou ' : 'Aparece no checkout de '}
                      <span className="font-semibold">{r.produtoNome ?? r.produtoCodigo}</span>
                    </p>
                    <p className="text-xs text-muted-foreground">
                      {r.modo === 'posse' ? 'upgrade' : 'order bump'}
                      {r.grupoExclusivo ? ` · grupo ${r.grupoExclusivo}` : ''}
                      {r.prioridade !== null ? ` · prioridade ${r.prioridade}` : ''}
                      {r.ativo ? '' : ' · desligada'}
                    </p>
                  </li>
                ))}
              </ul>
            </Secao>
          ) : null}

          {oferta.origem ? (
            <Secao titulo="De onde veio" testId="origem-da-oferta">
              <pre className="max-h-64 overflow-auto whitespace-pre-wrap rounded-lg border bg-muted/30 p-3 font-mono text-xs">
                {JSON.stringify(oferta.origem, null, 2)}
              </pre>
            </Secao>
          ) : null}

          <Secao titulo="Como está no banco">
            <ColunasDoBanco oferta={oferta} />
          </Secao>
        </div>

        <SheetFooter>
          <p className="mr-auto text-xs text-muted-foreground">Histórico: só consulta.</p>
          {podeDuplicar ? (
            <Button variant="outline" type="button" onClick={aoDuplicar}>
              <Copy /> Duplicar
            </Button>
          ) : null}
          <Button variant="outline" type="button" onClick={aoFechar}>
            Fechar
          </Button>
        </SheetFooter>
      </SheetContent>
    </Sheet>
  );
}

/* ============================================================
   O FORMULÁRIO — a oferta, os preços, o bônus e as exigências
   ============================================================ */

interface OpcaoProduto {
  valor: string;
  rotulo: string;
}

/** Os produtos do Catálogo para os selects. */
function useOpcoesDeProduto(): OpcaoProduto[] {
  const consulta = useLista('products', { porPagina: 500, ordenar: 'nome' });
  return (consulta.data?.itens ?? []).map((p) => ({
    valor: p.codigo,
    rotulo: `${p.nome}${p.ativo ? '' : ' (inativo)'}`,
  }));
}

/* O valor atual sempre aparece, mesmo fora da lista carregada: sem isso o
   select abriria em branco e salvar outro campo apagaria o vínculo. */
function comAtual(opcoes: OpcaoProduto[], atual: string): OpcaoProduto[] {
  if (!atual || opcoes.some((o) => o.valor === atual)) return opcoes;
  return [...opcoes, { valor: atual, rotulo: atual }];
}

function SeletorDeProduto({
  valor,
  aoMudar,
  opcoes,
  rotulo,
  desabilitado,
  invalido,
}: {
  valor: string;
  aoMudar: (v: string) => void;
  opcoes: OpcaoProduto[];
  rotulo: string;
  desabilitado?: boolean;
  invalido?: boolean;
}) {
  return (
    <Select value={valor || undefined} onValueChange={aoMudar} disabled={desabilitado}>
      <SelectTrigger aria-label={rotulo} aria-invalid={invalido}>
        <SelectValue placeholder="Escolha o produto" />
      </SelectTrigger>
      <SelectContent>
        {comAtual(opcoes, valor).map((o) => (
          <SelectItem key={o.valor} value={o.valor}>
            {o.rotulo} <span className="font-mono text-xs text-muted-foreground">{o.valor}</span>
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

function CamposDaOferta({
  formulario,
  produtos,
  original,
  desabilitado,
}: {
  formulario: UseFormReturn<OfertaForm>;
  produtos: OpcaoProduto[];
  /** A oferta como está no banco, quando é edição: diz o que travou. */
  original?: OfertaCatalogo;
  desabilitado: boolean;
}) {
  const { register, control, watch, setValue, formState } = formulario;
  const erros = formState.errors;
  const precos = useFieldArray({ control, name: 'precos' });
  const bonus = useFieldArray({ control, name: 'bonus' });
  const requer = useFieldArray({ control, name: 'requer' });
  const tipo = watch('tipo');
  const valoresPrecos = watch('precos');
  /* Oferta que já esteve no ar: códigos travados, e as linhas que vieram do
     banco não saem (o banco recusa de novo, se alguém contornar a tela). */
  const travada = Boolean(original?.jaFoiAoAr);
  const linhasOriginais = {
    precos: travada ? (original?.precos.length ?? 0) : 0,
    bonus: travada ? (original?.bonus.length ?? 0) : 0,
    requer: travada ? (original?.requer.length ?? 0) : 0,
  };
  const produtosDosPrecos = valoresPrecos.map((p) => p.produtoCodigo).filter(Boolean);
  const opcoesDoPreco = produtosDosPrecos.map(
    (codigo) => produtos.find((o) => o.valor === codigo) ?? { valor: codigo, rotulo: codigo },
  );

  return (
    <fieldset disabled={desabilitado} className="space-y-6">
      {/* ---------- a oferta ---------- */}
      <section className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <CampoForm
            rotulo="Código da oferta"
            obrigatorio
            erro={erros.codigo?.message}
            dica={travada ? 'Já esteve no ar: o código não muda mais.' : 'Letras minúsculas, números e hífen.'}
          >
            {(p) =>
              travada ? (
                <div className="relative">
                  <Lock className="pointer-events-none absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground" />
                  <Input {...p} {...register('codigo')} readOnly className="pl-8 font-mono" />
                </div>
              ) : (
                <Input {...p} {...register('codigo')} className="font-mono" placeholder="lideranca-consciente-condicao" />
              )
            }
          </CampoForm>
          <CampoForm rotulo="Nome" obrigatorio erro={erros.nome?.message}>
            {(p) => <Input {...p} {...register('nome')} />}
          </CampoForm>
        </div>

        <CampoForm rotulo="Descrição" erro={erros.descricao?.message} dica="Para o painel e o agente; nenhuma página dos sites mostra.">
          {(p) => <Textarea rows={2} {...p} {...register('descricao')} />}
        </CampoForm>

        <div className="grid gap-4 sm:grid-cols-3">
          <CampoForm rotulo="Tipo" obrigatorio erro={erros.tipo?.message}>
            {(p) => (
              <Controller
                control={control}
                name="tipo"
                render={({ field }) => (
                  <Select
                    value={field.value || undefined}
                    onValueChange={(v) => {
                      field.onChange(v);
                      /* Preço sem prazo não tem janela. */
                      if (v === 'base') {
                        setValue('iniciaEm', '', { shouldDirty: true });
                        setValue('encerraEm', '', { shouldDirty: true });
                      }
                    }}
                  >
                    <SelectTrigger id={p.id} aria-invalid={p['aria-invalid']}>
                      <SelectValue placeholder="Escolha" />
                    </SelectTrigger>
                    <SelectContent>
                      {TIPOS_OFERTA.map((t) => (
                        <SelectItem key={t.valor} value={t.valor}>
                          {t.rotulo}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                )}
              />
            )}
          </CampoForm>
          <CampoForm
            rotulo="Começa em"
            erro={erros.iniciaEm?.message}
            dica={tipo === 'base' ? 'Preço sem prazo não tem início.' : 'Horário de Brasília. Vazio = já vale.'}
          >
            {(p) => <Input type="datetime-local" step={1} {...p} {...register('iniciaEm')} disabled={tipo === 'base'} />}
          </CampoForm>
          <CampoForm
            rotulo="Termina em"
            erro={erros.encerraEm?.message}
            dica={tipo === 'base' ? 'Preço sem prazo não tem fim.' : 'Horário de Brasília. Vazio = sem fim.'}
          >
            {(p) => <Input type="datetime-local" step={1} {...p} {...register('encerraEm')} disabled={tipo === 'base'} />}
          </CampoForm>
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-1">
            <div className="flex items-center gap-3">
              <Controller
                control={control}
                name="publico"
                render={({ field }) => (
                  <Switch id="oferta-publica" checked={field.value} onCheckedChange={field.onChange} />
                )}
              />
              <Label htmlFor="oferta-publica">Aparece no site</Label>
            </div>
            <p className="text-xs text-muted-foreground">Desligado, a oferta vale só por link direto.</p>
          </div>
          <div className="space-y-1">
            <p className="text-sm font-medium">Meios de pagamento</p>
            <Controller
              control={control}
              name="meiosPagamento"
              render={({ field }) => (
                <div className="flex flex-wrap gap-4">
                  {MEIOS.map((m) => (
                    <label key={m.valor} className="flex items-center gap-2 text-sm">
                      <input
                        type="checkbox"
                        className="size-4"
                        checked={field.value.includes(m.valor)}
                        onChange={(e) =>
                          field.onChange(
                            e.target.checked
                              ? MEIOS.map((x) => x.valor).filter((v) => v === m.valor || field.value.includes(v))
                              : field.value.filter((v) => v !== m.valor),
                          )
                        }
                      />
                      {m.rotulo}
                    </label>
                  ))}
                </div>
              )}
            />
          </div>
        </div>
      </section>

      {/* ---------- preços ---------- */}
      <Secao
        titulo={`Preços por produto (${precos.fields.length})`}
        testId="form-precos"
        acoes={
          <Button type="button" variant="outline" size="sm" onClick={() => precos.append({ ...PRECO_VAZIO })}>
            <Plus /> Adicionar preço
          </Button>
        }
      >
        {precos.fields.length === 0 ? (
          <p className="text-sm text-muted-foreground">Nenhum preço. Uma oferta só vai ao ar com preço.</p>
        ) : null}
        {precos.fields.map((campo, i) => {
          const original = i < linhasOriginais.precos;
          const e = erros.precos?.[i];
          const valores = valoresPrecos[i] ?? PRECO_VAZIO;
          const conta = conferirParcelas(valores.valor, valores.parcelas, valores.valorParcela);
          return (
            <div key={campo.id} className="space-y-3 rounded-lg border p-3" data-testid={`preco-${i}`}>
              <div className="flex items-center justify-between gap-2">
                <p className="text-sm font-semibold">Preço {i + 1}</p>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={() => precos.remove(i)}
                  disabled={original}
                  title={original ? 'Esta oferta já esteve no ar: o preço não sai, só muda.' : undefined}
                >
                  <Trash2 /> Tirar
                </Button>
              </div>
              <div className="grid gap-3 sm:grid-cols-2">
                <CampoForm rotulo="Produto" obrigatorio erro={e?.produtoCodigo?.message}>
                  {() => (
                    <Controller
                      control={control}
                      name={`precos.${i}.produtoCodigo`}
                      render={({ field }) => (
                        <SeletorDeProduto
                          valor={field.value}
                          aoMudar={field.onChange}
                          opcoes={produtos}
                          rotulo={`Produto do preço ${i + 1}`}
                          desabilitado={original}
                          invalido={Boolean(e?.produtoCodigo)}
                        />
                      )}
                    />
                  )}
                </CampoForm>
                <CampoForm
                  rotulo="Código vendável"
                  obrigatorio
                  erro={e?.codigo?.message}
                  dica={original ? 'Já esteve no ar: não muda mais.' : 'O que links, pedidos e acessos usam.'}
                >
                  {(p) => <Input {...p} {...register(`precos.${i}.codigo`)} readOnly={original} className="font-mono" />}
                </CampoForm>
              </div>
              <div className="grid gap-3 sm:grid-cols-4">
                <CampoForm rotulo="À vista (R$)" erro={e?.valor?.message}>
                  {(p) => <Input inputMode="decimal" {...p} {...register(`precos.${i}.valor`)} className="tabular" />}
                </CampoForm>
                <CampoForm rotulo="Parcelas" erro={e?.parcelas?.message}>
                  {(p) => <Input inputMode="numeric" {...p} {...register(`precos.${i}.parcelas`)} className="tabular" />}
                </CampoForm>
                <CampoForm rotulo="Valor da parcela (R$)" erro={e?.valorParcela?.message}>
                  {(p) => <Input inputMode="decimal" {...p} {...register(`precos.${i}.valorParcela`)} className="tabular" />}
                </CampoForm>
                <CampoForm rotulo="Riscado — de (R$)" erro={e?.valorRiscado?.message}>
                  {(p) => <Input inputMode="decimal" {...p} {...register(`precos.${i}.valorRiscado`)} className="tabular" />}
                </CampoForm>
              </div>
              {conta ? (
                <p
                  className={conta.fecha ? 'text-xs text-muted-foreground' : 'text-xs font-semibold text-coral-700'}
                  data-testid={`conta-parcelas-${i}`}
                >
                  {conta.texto}
                  {conta.fecha ? '' : ' — não fecha: a parcela é o à vista dividido pelas parcelas, arredondado para cima.'}
                </p>
              ) : null}
              <div className="grid gap-3 sm:grid-cols-3">
                <CampoForm rotulo="Nome no checkout" erro={e?.nome?.message} dica="Opcional.">
                  {(p) => <Input {...p} {...register(`precos.${i}.nome`)} />}
                </CampoForm>
                <CampoForm rotulo="Sistema do checkout">
                  {(p) => (
                    <Controller
                      control={control}
                      name={`precos.${i}.sistemaExterno`}
                      render={({ field }) => (
                        <Select value={field.value || NENHUM} onValueChange={(v) => field.onChange(v === NENHUM ? '' : v)}>
                          <SelectTrigger id={p.id}>
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value={NENHUM}>Nenhum</SelectItem>
                            <SelectItem value="eduzz">Eduzz</SelectItem>
                            <SelectItem value="infinitepay">InfinitePay</SelectItem>
                          </SelectContent>
                        </Select>
                      )}
                    />
                  )}
                </CampoForm>
                <CampoForm rotulo="Código no sistema" dica="O código do produto lá (na Eduzz, o número).">
                  {(p) => <Input {...p} {...register(`precos.${i}.skuExterno`)} className="font-mono" />}
                </CampoForm>
              </div>
              <CampoForm rotulo="Link do checkout" erro={e?.checkoutUrl?.message} dica="Opcional. Começa com https://.">
                {(p) => <Input {...p} {...register(`precos.${i}.checkoutUrl`)} />}
              </CampoForm>
            </div>
          );
        })}
      </Secao>

      {/* ---------- bônus ---------- */}
      <Secao
        titulo={`Bônus (${bonus.fields.length})`}
        testId="form-bonus"
        acoes={
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={() => bonus.append({ ...BONUS_VAZIO, produtoCodigo: produtosDosPrecos[0] ?? '' })}
            disabled={produtosDosPrecos.length === 0}
          >
            <Plus /> Adicionar bônus
          </Button>
        }
      >
        {bonus.fields.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Nenhum bônus. O bônus entra junto com o preço de um produto (por exemplo, meses de Journey).
          </p>
        ) : null}
        {bonus.fields.map((campo, i) => {
          const original = i < linhasOriginais.bonus;
          const e = erros.bonus?.[i];
          return (
            <div key={campo.id} className="space-y-3 rounded-lg border p-3" data-testid={`bonus-${i}`}>
              <div className="flex items-center justify-between gap-2">
                <p className="text-sm font-semibold">Bônus {i + 1}</p>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={() => bonus.remove(i)}
                  disabled={original}
                  title={original ? 'Esta oferta já esteve no ar: o bônus não sai, só muda.' : undefined}
                >
                  <Trash2 /> Tirar
                </Button>
              </div>
              <div className="grid gap-3 sm:grid-cols-2">
                <CampoForm rotulo="Vem com o preço de" obrigatorio erro={e?.produtoCodigo?.message}>
                  {() => (
                    <Controller
                      control={control}
                      name={`bonus.${i}.produtoCodigo`}
                      render={({ field }) => (
                        <SeletorDeProduto
                          valor={field.value}
                          aoMudar={field.onChange}
                          opcoes={opcoesDoPreco}
                          rotulo={`Preço do bônus ${i + 1}`}
                          desabilitado={original}
                          invalido={Boolean(e?.produtoCodigo)}
                        />
                      )}
                    />
                  )}
                </CampoForm>
                <CampoForm rotulo="Entrega o produto" obrigatorio erro={e?.inclusoCodigo?.message}>
                  {() => (
                    <Controller
                      control={control}
                      name={`bonus.${i}.inclusoCodigo`}
                      render={({ field }) => (
                        <SeletorDeProduto
                          valor={field.value}
                          aoMudar={field.onChange}
                          opcoes={produtos}
                          rotulo={`Produto que o bônus ${i + 1} entrega`}
                          desabilitado={original}
                          invalido={Boolean(e?.inclusoCodigo)}
                        />
                      )}
                    />
                  )}
                </CampoForm>
              </div>
              <div className="grid gap-3 sm:grid-cols-3">
                <CampoForm rotulo="Nome" erro={e?.nome?.message}>
                  {(p) => <Input {...p} {...register(`bonus.${i}.nome`)} />}
                </CampoForm>
                <CampoForm rotulo="Custa (R$)" erro={e?.valor?.message} dica="Vazio ou 0 = grátis.">
                  {(p) => <Input inputMode="decimal" {...p} {...register(`bonus.${i}.valor`)} className="tabular" />}
                </CampoForm>
                <CampoForm rotulo="Vale (R$)" erro={e?.valorReferencia?.message} dica="Quanto custaria à parte.">
                  {(p) => <Input inputMode="decimal" {...p} {...register(`bonus.${i}.valorReferencia`)} className="tabular" />}
                </CampoForm>
              </div>
              <CampoForm rotulo="Descrição" erro={e?.descricao?.message}>
                {(p) => <Textarea rows={2} {...p} {...register(`bonus.${i}.descricao`)} />}
              </CampoForm>
              <div className="grid gap-3 sm:grid-cols-2">
                <CampoForm rotulo="Detalhe" erro={e?.detalhe?.message}>
                  {(p) => <Input {...p} {...register(`bonus.${i}.detalhe`)} />}
                </CampoForm>
                <CampoForm rotulo="Nota" erro={e?.nota?.message}>
                  {(p) => <Input {...p} {...register(`bonus.${i}.nota`)} />}
                </CampoForm>
              </div>
              <div className="grid gap-3 sm:grid-cols-2">
                <CampoForm rotulo="Bônus vale a partir de" erro={e?.iniciaEm?.message} dica="Vazio = junto com a oferta.">
                  {(p) => <Input type="datetime-local" step={1} {...p} {...register(`bonus.${i}.iniciaEm`)} />}
                </CampoForm>
                <CampoForm rotulo="Bônus vale até" erro={e?.encerraEm?.message} dica="O site faz a contagem regressiva até aqui.">
                  {(p) => <Input type="datetime-local" step={1} {...p} {...register(`bonus.${i}.encerraEm`)} />}
                </CampoForm>
              </div>
            </div>
          );
        })}
      </Secao>

      {/* ---------- exigências: order bump e upgrade ---------- */}
      {tipo === 'condicional' || requer.fields.length > 0 ? (
        <Secao
          titulo={`Exige — order bump e upgrade (${requer.fields.length})`}
          testId="form-exigencias"
          acoes={
            <Button type="button" variant="outline" size="sm" onClick={() => requer.append({ ...EXIGENCIA_VAZIA })}>
              <Plus /> Adicionar exigência
            </Button>
          }
        >
          {requer.fields.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              Sem exigência, o order bump não aparece em checkout nenhum. Diga em que checkout ele aparece (no
              carrinho) ou quem pode comprar o upgrade (já comprou).
            </p>
          ) : null}
          {requer.fields.map((campo, i) => {
            const original = i < linhasOriginais.requer;
            const e = erros.requer?.[i];
            return (
              <div key={campo.id} className="space-y-3 rounded-lg border p-3" data-testid={`exigencia-${i}`}>
                <div className="flex items-center justify-between gap-2">
                  <p className="text-sm font-semibold">Exigência {i + 1}</p>
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    onClick={() => requer.remove(i)}
                    disabled={original}
                    title={original ? 'Esta oferta já esteve no ar: a exigência não sai; desligue-a.' : undefined}
                  >
                    <Trash2 /> Tirar
                  </Button>
                </div>
                <div className="grid gap-3 sm:grid-cols-3">
                  <CampoForm rotulo="Produto" obrigatorio erro={e?.produtoCodigo?.message}>
                    {() => (
                      <Controller
                        control={control}
                        name={`requer.${i}.produtoCodigo`}
                        render={({ field }) => (
                          <SeletorDeProduto
                            valor={field.value}
                            aoMudar={field.onChange}
                            opcoes={produtos}
                            rotulo={`Produto exigido ${i + 1}`}
                            desabilitado={original}
                            invalido={Boolean(e?.produtoCodigo)}
                          />
                        )}
                      />
                    )}
                  </CampoForm>
                  <CampoForm rotulo="Como">
                    {(p) => (
                      <Controller
                        control={control}
                        name={`requer.${i}.modo`}
                        render={({ field }) => (
                          <Select value={field.value} onValueChange={field.onChange}>
                            <SelectTrigger id={p.id}>
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              <SelectItem value="carrinho">No carrinho (order bump)</SelectItem>
                              <SelectItem value="posse">Já comprou (upgrade)</SelectItem>
                            </SelectContent>
                          </Select>
                        )}
                      />
                    )}
                  </CampoForm>
                  <div className="flex items-end gap-3 pb-2">
                    <Controller
                      control={control}
                      name={`requer.${i}.ativo`}
                      render={({ field }) => (
                        <Switch id={`exigencia-ativa-${i}`} checked={field.value} onCheckedChange={field.onChange} />
                      )}
                    />
                    <Label htmlFor={`exigencia-ativa-${i}`}>Ligada</Label>
                  </div>
                </div>
                <div className="grid gap-3 sm:grid-cols-4">
                  <CampoForm rotulo="Prioridade" erro={e?.prioridade?.message} dica="Menor aparece antes. Vazio = 100.">
                    {(p) => <Input inputMode="numeric" {...p} {...register(`requer.${i}.prioridade`)} />}
                  </CampoForm>
                  <CampoForm rotulo="Grupo exclusivo" dica="Do mesmo grupo, aparece um só.">
                    {(p) => <Input {...p} {...register(`requer.${i}.grupoExclusivo`)} />}
                  </CampoForm>
                  <CampoForm rotulo="Vale a partir de" erro={e?.iniciaEm?.message}>
                    {(p) => <Input type="datetime-local" step={1} {...p} {...register(`requer.${i}.iniciaEm`)} />}
                  </CampoForm>
                  <CampoForm rotulo="Vale até" erro={e?.encerraEm?.message}>
                    {(p) => <Input type="datetime-local" step={1} {...p} {...register(`requer.${i}.encerraEm`)} />}
                  </CampoForm>
                </div>
                <CampoForm rotulo="Observação">
                  {(p) => <Input {...p} {...register(`requer.${i}.observacao`)} />}
                </CampoForm>
              </div>
            );
          })}
        </Secao>
      ) : null}
    </fieldset>
  );
}

/* ============================================================
   EDITAR — uma oferta que não é histórico
   ============================================================ */

type Confirmacao = { tipo: 'salvar'; valores: OfertaForm } | { tipo: 'publicar' } | { tipo: 'arquivar' };

function ListaDeMudancas({ oferta, valores }: { oferta: OfertaCatalogo; valores: OfertaForm }) {
  const mudancas = mudancasDePreco(oferta, valores);
  if (mudancas.length === 0) return null;
  return (
    <ul className="list-disc space-y-1 pl-4" data-testid="mudancas-de-preco">
      {mudancas.map((m) => (
        <li key={m.produto}>
          <strong className="text-foreground">{m.produto}</strong>: {m.antes ?? 'sem preço'} → {m.depois ?? 'sem preço'}
          {m.eduzz ? ` (a Eduzz continua cobrando ${m.eduzz} até alguém trocar lá)` : ''}
        </li>
      ))}
    </ul>
  );
}

function DrawerOferta({ id, aoFechar, aoDuplicar }: { id: string; aoFechar: () => void; aoDuplicar: () => void }) {
  const sessao = useSessao();
  const origem = useOrigemRecurso(RECURSO);
  const produtos = useOpcoesDeProduto();
  const aberto = useRef<OfertaCatalogo | undefined>(undefined);
  const [confirmacao, setConfirmacao] = useState<Confirmacao | null>(null);

  const edicao = useEdicaoRecurso<'offers', OfertaForm>({
    recurso: RECURSO,
    id,
    resolver: zodResolver(ofertaFormSchema),
    padrao: FORMULARIO_VAZIO,
    paraFormulario: paraFormularioOferta,
    paraPayload: (valores) => payloadDaOferta(valores, aberto.current) as Partial<OfertaCatalogo>,
  });
  aberto.current = edicao.registro;
  const { registro, formulario } = edicao;
  const podeEditar = sessao.pode('editar');
  const bloqueio = registro && !registro.ativo ? motivoDoBloqueio(registro.bloqueioPorNoAr) : null;

  async function confirmar() {
    const atual = confirmacao;
    setConfirmacao(null);
    if (!atual) return;
    if (atual.tipo === 'salvar') await edicao.salvar(atual.valores);
    if (atual.tipo === 'publicar') await edicao.publicar();
    if (atual.tipo === 'arquivar') await edicao.arquivar();
  }

  const acoes = registro ? (
    <>
      {sessao.pode('criar') ? (
        <Button type="button" variant="outline" onClick={aoDuplicar} disabled={edicao.salvando}>
          <Copy /> Duplicar
        </Button>
      ) : null}
      {registro.ativo
        ? sessao.pode('arquivar') && (
            <Button
              type="button"
              variant="outline"
              onClick={() => setConfirmacao({ tipo: 'arquivar' })}
              disabled={edicao.salvando || edicao.sujo}
              title={edicao.sujo ? 'Salve ou descarte as alterações antes.' : undefined}
            >
              <Archive /> Tirar do ar
            </Button>
          )
        : sessao.pode('publicar') && (
            <Button
              type="button"
              variant="secondary"
              onClick={() => setConfirmacao({ tipo: 'publicar' })}
              disabled={edicao.salvando || edicao.sujo || Boolean(bloqueio)}
              title={bloqueio ?? (edicao.sujo ? 'Salve ou descarte as alterações antes.' : undefined)}
            >
              <Rocket /> Pôr no ar
            </Button>
          )}
    </>
  ) : null;

  return (
    <>
      <DrawerEdicao
        aberto
        larga
        titulo={registro?.nome || 'Oferta'}
        descricao={
          registro ? (
            <span className="flex flex-wrap items-center gap-2">
              <span className="font-mono text-xs">{registro.codigo}</span>
              <SeloSituacaoOferta situacao={registro.situacao} />
            </span>
          ) : undefined
        }
        sujo={edicao.sujo}
        salvando={edicao.salvando}
        podeSalvar={podeEditar}
        idFormulario="form-oferta"
        acoes={acoes}
        aoFechar={aoFechar}
        informacao={registro ? `Atualizada em ${formatarDataHora(registro.atualizadoEm)}` : undefined}
      >
        {edicao.carregando ? (
          <EstadoCarregando linhas={10} />
        ) : edicao.erro ? (
          <EstadoErro erro={edicao.erro} aoTentarNovamente={edicao.recarregar} />
        ) : registro ? (
          <form
            id="form-oferta"
            noValidate
            className="space-y-5"
            onSubmit={formulario.handleSubmit((valores) =>
              registro.ativo ? setConfirmacao({ tipo: 'salvar', valores }) : void edicao.salvar(valores),
            )}
          >
            {edicao.salvo && !edicao.sujo ? (
              <Alert variant="info" data-testid="oferta-salva">
                <CheckCircle2 />
                <AlertTitle>Salvo</AlertTitle>
                <AlertDescription>
                  {origem === 'http'
                    ? 'A alteração está no banco, com o antes e o depois no histórico.'
                    : 'Modo demonstração: a alteração ficou só nesta aba e some ao recarregar.'}
                </AlertDescription>
              </Alert>
            ) : null}
            <AvisoErroEscrita erro={edicao.erroEscrita} />

            <dl className="grid gap-3 rounded-lg border bg-muted/30 p-4 text-sm sm:grid-cols-3">
              <Campo rotulo="Situação">
                <SeloSituacaoOferta situacao={registro.situacao} />
                <p className="mt-1 text-xs text-muted-foreground">
                  {SITUACOES_OFERTA.find((s) => s.valor === registro.situacao)?.dica}
                </p>
              </Campo>
              <Campo rotulo="No site">{registro.noSite ? 'Sim — o site lê esta oferta agora' : 'Não'}</Campo>
              <Campo rotulo="Já esteve no ar">{registro.jaFoiAoAr ? 'Sim: códigos travados' : 'Não: é rascunho'}</Campo>
            </dl>

            {bloqueio ? (
              <Alert variant="atencao" data-testid="bloqueio-por-no-ar">
                <Lock />
                <AlertTitle>Pôr no ar está travado</AlertTitle>
                <AlertDescription>{bloqueio}</AlertDescription>
              </Alert>
            ) : null}
            {registro.sobrepostas.length ? (
              <Alert variant="atencao" data-testid="aviso-sobrepostas">
                <AlertTriangle />
                <AlertTitle>Vale junto com outra oferta</AlertTitle>
                <AlertDescription>
                  No mesmo produto, com prazo, valendo ao mesmo tempo:{' '}
                  <span className="font-mono">{registro.sobrepostas.join(', ')}</span>. Confira qual preço o site deve
                  mostrar.
                </AlertDescription>
              </Alert>
            ) : null}
            {registro.situacao === 'encerrada' || registro.bloqueioPorNoAr === 'prazo_vencido' ? (
              <Alert variant="info" data-testid="dica-prorrogar">
                <Info />
                <AlertDescription>
                  O prazo terminou. Para prorrogar, mude "Termina em" e salve
                  {registro.ativo ? ' — como ela está ligada, volta a valer na hora.' : '.'}
                </AlertDescription>
              </Alert>
            ) : null}
            {edicao.sujo ? (
              <Alert variant="atencao">
                <AlertTriangle />
                <AlertTitle>Alterações não salvas</AlertTitle>
                <AlertDescription>
                  Salvar manda para o banco só o que você mudou{registro.ativo ? ', depois de confirmar' : ''}. Fechar
                  sem salvar descarta.
                </AlertDescription>
              </Alert>
            ) : null}

            <CamposDaOferta formulario={formulario} produtos={produtos} original={registro} desabilitado={!podeEditar} />

            <HistoricoDeAlteracoes oferta={registro} />

            <details className="rounded-lg border p-3 text-sm">
              <summary className="cursor-pointer font-semibold">Como está no banco</summary>
              <div className="mt-3 space-y-3">
                {registro.origem ? (
                  <pre
                    className="max-h-64 overflow-auto whitespace-pre-wrap rounded-lg border bg-muted/30 p-3 font-mono text-xs"
                    data-testid="origem-da-oferta"
                  >
                    {JSON.stringify(registro.origem, null, 2)}
                  </pre>
                ) : null}
                <ColunasDoBanco oferta={registro} />
              </div>
            </details>
          </form>
        ) : null}
      </DrawerEdicao>

      {registro && confirmacao ? (
        <DialogoConfirmacao
          aberto
          icone={
            confirmacao.tipo === 'arquivar' ? (
              <Archive className="size-5 text-amber-600" />
            ) : confirmacao.tipo === 'publicar' ? (
              <Rocket className="size-5 text-verde-700" />
            ) : undefined
          }
          titulo={
            confirmacao.tipo === 'salvar'
              ? 'Salvar oferta que está ligada?'
              : confirmacao.tipo === 'publicar'
                ? 'Pôr esta oferta no ar?'
                : 'Tirar esta oferta do ar?'
          }
          descricao={
            <div className="space-y-2" data-testid="confirmacao-oferta">
              {confirmacao.tipo === 'salvar' ? (
                <>
                  <p>
                    {registro.noSite
                      ? 'O site e o agente passam a mostrar o que você mudou em até 1 minuto.'
                      : 'A oferta está ligada. A mudança vale na hora para quem lê o catálogo.'}
                  </p>
                  <ListaDeMudancas oferta={registro} valores={confirmacao.valores} />
                </>
              ) : confirmacao.tipo === 'publicar' ? (
                <>
                  <p>
                    O site e o agente passam a mostrar esta oferta em até 1 minuto, dentro do prazo (
                    {prazo(registro)}).
                  </p>
                  <ul className="list-disc pl-4">
                    {registro.precos.map((p) => (
                      <li key={p.codigo}>
                        <strong className="text-foreground">{p.produtoNome ?? p.produtoCodigo}</strong>: {precoPorExtenso(p)}
                      </li>
                    ))}
                  </ul>
                  <p>O preço cobrado na Eduzz não muda por aqui: se for o caso, troque também lá.</p>
                </>
              ) : (
                <p>
                  O site e o agente deixam de mostrar esta oferta em até 1 minuto. Nada é apagado: dá para pôr no ar de
                  novo.
                </p>
              )}
            </div>
          }
          rotuloConfirmar={confirmacao.tipo === 'salvar' ? 'Salvar' : confirmacao.tipo === 'publicar' ? 'Pôr no ar' : 'Tirar do ar'}
          destrutivo={confirmacao.tipo === 'arquivar'}
          carregando={edicao.salvando}
          aoConfirmar={() => void confirmar()}
          aoCancelar={() => setConfirmacao(null)}
        />
      ) : null}

      <DialogoConflito aberto={edicao.conflito} aoRecarregar={edicao.recarregar} aoFechar={edicao.fecharConflito} />
    </>
  );
}

/* ============================================================
   CRIAR — do zero ou duplicando
   ============================================================ */

function DrawerNovaOferta({
  de,
  aoFechar,
  aoCriar,
}: {
  /** A oferta de onde a cópia sai, quando é duplicar. */
  de?: string;
  aoFechar: () => void;
  aoCriar: (id: string) => void;
}) {
  const sessao = useSessao();
  const produtos = useOpcoesDeProduto();
  const fonte = useItem(RECURSO, de);
  const criar = useCriar(RECURSO);
  const formulario = useForm<OfertaForm>({ resolver: zodResolver(ofertaFormSchema), defaultValues: FORMULARIO_VAZIO });

  useEffect(() => {
    formulario.reset(fonte.data ? duplicarOferta(fonte.data) : FORMULARIO_VAZIO);
    // O formulário é estável; reagir à oferta de origem basta.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fonte.data]);

  async function salvar(valores: OfertaForm) {
    try {
      const nova = await criar.mutateAsync(payloadDaOferta(valores) as Partial<OfertaCatalogo>);
      formulario.reset(valores);
      aoCriar(nova.id);
    } catch {
      /* A recusa fica em `criar.error` e aparece no topo do formulário. */
    }
  }

  return (
    <DrawerEdicao
      aberto
      larga
      titulo={de ? `Duplicar ${fonte.data?.nome ?? 'oferta'}` : 'Nova oferta'}
      descricao="Nasce desligada, como rascunho. Pôr no ar é outro passo, com confirmação."
      sujo={formulario.formState.isDirty}
      salvando={criar.isPending}
      podeSalvar={sessao.pode('criar')}
      idFormulario="form-nova-oferta"
      rotuloSalvar="Criar rascunho"
      aoFechar={aoFechar}
    >
      {de && fonte.isPending ? (
        <EstadoCarregando linhas={8} />
      ) : de && fonte.error ? (
        <EstadoErro erro={fonte.error} aoTentarNovamente={() => void fonte.refetch()} />
      ) : (
        <form
          id="form-nova-oferta"
          noValidate
          className="space-y-5"
          onSubmit={formulario.handleSubmit((valores) => void salvar(valores))}
        >
          <AvisoErroEscrita erro={criar.error} />
          {de ? (
            <Alert variant="info" data-testid="aviso-duplicar">
              <Copy />
              <AlertDescription>
                Cópia de <span className="font-mono">{fonte.data?.codigo}</span>: preços, bônus e exigências vieram
                junto; o prazo e os códigos ficam em branco para você preencher.
              </AlertDescription>
            </Alert>
          ) : null}
          <CamposDaOferta formulario={formulario} produtos={produtos} desabilitado={!sessao.pode('criar')} />
        </form>
      )}
    </DrawerEdicao>
  );
}

/* ============================================================
   A PÁGINA
   ============================================================ */

/**
 * Oferta aberta: histórico importado só se consulta; as outras se editam.
 * Escolhe depois de a oferta chegar — abrir o formulário e trocá-lo pela
 * consulta um instante depois deixaria um clique cair no botão errado.
 */
function OfertaAberta({ id, aoFechar, aoDuplicar }: { id: string; aoFechar: () => void; aoDuplicar: () => void }) {
  const sessao = useSessao();
  const consulta = useItem(RECURSO, id);
  if (consulta.data?.historico) {
    return (
      <DetalheOferta oferta={consulta.data} podeDuplicar={sessao.pode('criar')} aoDuplicar={aoDuplicar} aoFechar={aoFechar} />
    );
  }
  if (consulta.isPending) {
    return (
      <Sheet open onOpenChange={(aberto) => (!aberto ? aoFechar() : undefined)}>
        <SheetContent side="right" className="w-full p-0 sm:max-w-4xl">
          <SheetHeader>
            <SheetTitle>Oferta</SheetTitle>
            <SheetDescription>Carregando…</SheetDescription>
          </SheetHeader>
          <div className="p-5">
            <EstadoCarregando linhas={10} />
          </div>
        </SheetContent>
      </Sheet>
    );
  }
  return <DrawerOferta id={id} aoFechar={aoFechar} aoDuplicar={aoDuplicar} />;
}

export function PaginaOfertas({ criando = false }: { criando?: boolean }) {
  const { id, de } = useParams();
  const navegar = useNavigate();
  const sessao = useSessao();
  /* Fechar a oferta volta à lista como estava: busca, filtros, página e ordem. */
  const { search } = useLocation();
  const irPara = (pathname: string) => navegar({ pathname, search });

  const colunas: Coluna<OfertaCatalogo>[] = [
    {
      chave: 'oferta',
      cabecalho: 'Oferta',
      ordenarPor: 'nome',
      celula: (o) => (
        <div className="min-w-56">
          <p className="font-semibold">{o.nome}</p>
          <p className="font-mono text-xs text-muted-foreground">{o.codigo}</p>
        </div>
      ),
    },
    {
      chave: 'tipo',
      cabecalho: 'Tipo',
      ordenarPor: 'tipo',
      className: 'whitespace-nowrap',
      celula: (o) => <span className="text-xs">{rotuloTipo(o.tipo)}</span>,
    },
    {
      chave: 'precos',
      cabecalho: 'Produtos e preços',
      celula: (o) =>
        o.precos.length ? (
          <ul className="space-y-1 text-xs">
            {o.precos.map((p) => (
              <li key={p.codigo}>
                <span className="font-medium">{p.produtoNome ?? p.produtoCodigo}</span>{' '}
                <span className="tabular text-muted-foreground">{precoPorExtenso(p)}</span>
                {p.noSite ? (
                  <Badge variant="sucesso" className="ml-1">
                    no site
                  </Badge>
                ) : null}
              </li>
            ))}
          </ul>
        ) : (
          <span className="text-muted-foreground">—</span>
        ),
    },
    {
      chave: 'situacao',
      cabecalho: 'Situação',
      ordenarPor: 'situacaoOrdem',
      className: 'whitespace-nowrap',
      celula: (o) => <SeloSituacaoOferta situacao={o.situacao} />,
    },
    {
      chave: 'prazo',
      cabecalho: 'Prazo',
      ordenarPor: 'iniciaEm',
      className: 'whitespace-nowrap text-xs tabular',
      celula: (o) => prazo(o),
    },
    {
      chave: 'verticais',
      cabecalho: 'Vertical',
      celula: (o) =>
        o.verticais.length ? (
          <span className="text-xs">{o.verticais.join(', ')}</span>
        ) : (
          <span className="text-muted-foreground">—</span>
        ),
    },
  ];

  return (
    <>
      <PaginaListagem
        recurso={RECURSO}
        titulo="Ofertas"
        descricao="O schema catalogo: cada oferta com os preços, o bônus e o que ela exige (order bump e upgrade). Crie como rascunho, edite, ponha no ar e tire do ar — nada se apaga."
        colunas={colunas}
        placeholderBusca="Buscar por nome, código, código vendável ou produto…"
        destinoItem={(o) => `${CAMINHO}/${o.id}`}
        acoes={
          sessao.pode('criar') ? (
            <Button type="button" onClick={() => irPara(`${CAMINHO}/nova`)}>
              <Plus /> Nova oferta
            </Button>
          ) : null
        }
        antesDaTabela={() => (
          <Alert variant="info" data-testid="aviso-virada">
            <Info />
            <AlertDescription>
              As ofertas do Institute entram aqui na virada. Até lá, o site do Institute ainda lê a casa antiga (
              <code className="font-mono">institute.ofertas</code>): dá para preparar rascunhos, mas "pôr no ar" fica
              travado até um site ler o <code className="font-mono">catalogo</code>. O selo <strong>no site</strong>{' '}
              marca o preço que o site lê agora. <History className="inline size-3.5" aria-hidden /> Cada oferta guarda o
              histórico de alterações.
            </AlertDescription>
          </Alert>
        )}
        definicoesFiltro={[
          { chave: 'situacao', rotulo: 'Situação', opcoes: SITUACOES_OFERTA.map((s) => ({ valor: s.valor, rotulo: s.rotulo })) },
          { chave: 'tipo', rotulo: 'Tipo', opcoes: TIPOS_OFERTA },
          { chave: 'verticais', rotulo: 'Vertical', opcoes: VERTICAIS },
          {
            chave: 'noSite',
            rotulo: 'No site',
            opcoes: [
              { valor: 'true', rotulo: 'O site lê agora' },
              { valor: 'false', rotulo: 'Fora do site' },
            ],
          },
        ]}
        estadoVazio={
          <EstadoVazio titulo="Nenhuma oferta no recorte" descricao="Nenhuma oferta bate com a busca e os filtros atuais." />
        }
      />

      {criando ? (
        <DrawerNovaOferta
          key={de ?? 'nova'}
          de={de}
          aoFechar={() => irPara(CAMINHO)}
          aoCriar={(novo) => irPara(`${CAMINHO}/${novo}`)}
        />
      ) : id ? (
        <OfertaAberta
          key={id}
          id={id}
          aoFechar={() => irPara(CAMINHO)}
          aoDuplicar={() => irPara(`${CAMINHO}/nova/${id}`)}
        />
      ) : null}
    </>
  );
}
