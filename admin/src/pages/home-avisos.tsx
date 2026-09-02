import { useState } from 'react';
import { Plus, Send, Trash2 } from 'lucide-react';
import {
  ICONES_AVISO,
  CATEGORIAS_AVISO,
  ROTULO_CATEGORIA_AVISO,
  type CategoriaAviso,
  ROTULO_ICONE_AVISO,
  ROTULO_SITUACAO_AVISO,
  type AvisoHome,
  type IconeAviso,
} from '@/contracts';
import { useArquivar, useAtualizar, useCriar, useLista } from '@/hooks/use-recurso';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { AvisoErroEscrita } from '@/components/admin/aviso-escrita';
import { EstadoVazio } from '@/components/admin/estados';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Skeleton } from '@/components/ui/skeleton';
import { PreviaAviso } from '@/features/home-v3/previa-aviso';

/* ============================================================
   HOME V3 · AVISOS
   ============================================================
   O que aparece em "Avisos importantes" na home do participante.

   Três campos de texto porque são três lugares diferentes: o TÍTULO é a
   linha forte do card, o SUBTÍTULO é o apoio embaixo dele, e a
   DESCRIÇÃO é o que abre quando a pessoa toca. Escrever os três é o que
   evita o card que promete e não entrega.

   Disparo imediato e disparo agendado são o mesmo aviso com hora
   diferente — não são dois tipos de registro. */

const VAZIO = {
  icone: 'megafone' as IconeAviso,
  categoria: 'antes_de_ir' as CategoriaAviso,
  titulo: '',
  subtitulo: '',
  descricao: '',
  imediato: false,
  disparoEm: '',
};

function formatarQuando(iso: string): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString('pt-BR', {
    day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit',
  });
}

export function PaginaHomeAvisos() {
  const avisos = useLista('home_notices', { porPagina: 200 });
  const criar = useCriar('home_notices');
  const atualizar = useAtualizar('home_notices');
  const arquivar = useArquivar('home_notices');

  const [form, setForm] = useState(VAZIO);
  const [aberto, setAberto] = useState(false);
  const [erroLocal, setErroLocal] = useState<string | null>(null);

  const erro = criar.error ?? atualizar.error ?? arquivar.error;
  const lista = avisos.data?.itens ?? [];

  function campo<K extends keyof typeof VAZIO>(chave: K, valor: (typeof VAZIO)[K]) {
    setForm((f) => ({ ...f, [chave]: valor }));
  }

  function enviar() {
    if (form.titulo.trim().length < 3) return setErroLocal('Informe o título do aviso.');
    if (form.descricao.trim().length < 3) return setErroLocal('Escreva a mensagem que a pessoa vai ler.');
    if (!form.imediato && !form.disparoEm) {
      return setErroLocal('Escolha o horário de disparo ou marque disparo imediato.');
    }
    setErroLocal(null);
    criar.mutate(
      {
        ...form,
        titulo: form.titulo.trim(),
        subtitulo: form.subtitulo.trim(),
        descricao: form.descricao.trim(),
        /* Imediato entra no ar já; agendado espera o horário. */
        disparoEm: form.imediato ? new Date().toISOString().slice(0, 16) : form.disparoEm,
        situacao: form.imediato ? 'no-ar' : 'agendado',
      },
      { onSuccess: () => { setForm(VAZIO); setAberto(false); } },
    );
  }

  function encerrar(a: AvisoHome) {
    atualizar.mutate({ id: a.id, payload: { situacao: 'encerrado' } });
  }

  function publicarAgora(a: AvisoHome) {
    atualizar.mutate({ id: a.id, payload: { situacao: 'no-ar' } });
  }

  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Avisos"
        descricao="O que aparece em Avisos importantes na home. Dispare agora ou programe o horário."
        acoes={
          <Button onClick={() => setAberto((v) => !v)}>
            <Plus className="mr-2 size-4" />
            {aberto ? 'Fechar' : 'Novo aviso'}
          </Button>
        }
      />

      {erro ? <AvisoErroEscrita erro={erro} /> : null}
      {erroLocal ? (
        <p className="rounded-md border border-destructive/40 bg-destructive/5 p-3 text-sm text-destructive">
          {erroLocal}
        </p>
      ) : null}

      {aberto ? (
        <section className="grid gap-5 rounded-xl border bg-card p-5 lg:grid-cols-[1fr_20rem]">
          <div className="space-y-4">
          <div className="grid gap-4 md:grid-cols-2">
            <div>
              <Label htmlFor="aviso-icone">Ícone</Label>
              <select
                id="aviso-icone"
                value={form.icone}
                onChange={(e) => campo('icone', e.target.value as IconeAviso)}
                className="flex h-10 w-full rounded-md border border-input bg-background px-3 text-sm"
              >
                {ICONES_AVISO.map((i) => (
                  <option key={i} value={i}>{ROTULO_ICONE_AVISO[i]}</option>
                ))}
              </select>
            </div>
            <div>
              <Label htmlFor="aviso-categoria">Categoria</Label>
              <select
                id="aviso-categoria"
                value={form.categoria}
                onChange={(e) => campo('categoria', e.target.value as CategoriaAviso)}
                className="flex h-10 w-full rounded-md border border-input bg-background px-3 text-sm"
              >
                {CATEGORIAS_AVISO.map((c) => (
                  <option key={c} value={c}>{ROTULO_CATEGORIA_AVISO[c]}</option>
                ))}
              </select>
            </div>
            <div>
              <Label htmlFor="aviso-titulo">Título</Label>
              <Input
                id="aviso-titulo"
                value={form.titulo}
                maxLength={80}
                onChange={(e) => campo('titulo', e.target.value)}
                placeholder="Masterclass mudou de sala"
              />
            </div>
          </div>

          <div>
            <Label htmlFor="aviso-subtitulo">Subtítulo</Label>
            <Input
              id="aviso-subtitulo"
              value={form.subtitulo}
              maxLength={120}
              onChange={(e) => campo('subtitulo', e.target.value)}
              placeholder="A linha de apoio que aparece embaixo do título, no card"
            />
          </div>

          <div>
            <Label htmlFor="aviso-descricao">Descrição</Label>
            <Textarea
              id="aviso-descricao"
              value={form.descricao}
              maxLength={1200}
              rows={5}
              onChange={(e) => campo('descricao', e.target.value)}
              placeholder="O texto completo, que abre quando a pessoa toca no aviso."
            />
            <p className="mt-1 text-xs text-muted-foreground">
              {form.descricao.length}/1200
            </p>
          </div>

          <div className="grid gap-4 md:grid-cols-[auto_1fr] md:items-end">
            <label className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                checked={form.imediato}
                onChange={(e) => campo('imediato', e.target.checked)}
                className="size-4"
              />
              Disparo imediato
            </label>
            <div>
              <Label htmlFor="aviso-quando">Horário de disparo</Label>
              <Input
                id="aviso-quando"
                type="datetime-local"
                value={form.disparoEm}
                disabled={form.imediato}
                onChange={(e) => campo('disparoEm', e.target.value)}
              />
            </div>
          </div>

          <Button onClick={enviar} disabled={criar.isPending}>
            <Send className="mr-2 size-4" />
            {form.imediato ? 'Disparar agora' : 'Programar aviso'}
          </Button>
          </div>

          {/* Escrever para uma tela escura olhando um painel claro é
              escrever no escuro. A prévia acompanha cada tecla. */}
          <aside aria-label="Prévia do aviso no app">
            <p className="mb-2 text-xs font-semibold text-muted-foreground">
              Como fica no app
            </p>
            <PreviaAviso
              icone={form.icone}
              titulo={form.titulo}
              subtitulo={form.subtitulo}
              descricao={form.descricao}
            />
          </aside>
        </section>
      ) : null}

      {avisos.isLoading ? (
        <Skeleton className="h-40 w-full" />
      ) : lista.length === 0 ? (
        <EstadoVazio
          titulo="Nenhum aviso"
          descricao="Os avisos aparecem na home do participante, em Avisos importantes."
        />
      ) : (
        <ul className="space-y-3">
          {lista.map((a) => (
            <li key={a.id} className="rounded-xl border bg-card p-4">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <strong className="text-sm">{a.titulo}</strong>
                    <Badge variant={a.situacao === 'no-ar' ? 'default' : 'neutro'}>
                      {ROTULO_SITUACAO_AVISO[a.situacao]}
                    </Badge>
                    <Badge variant="neutro">{a.icone}</Badge>
                  </div>
                  {a.subtitulo ? (
                    <p className="mt-1 text-xs text-muted-foreground">{a.subtitulo}</p>
                  ) : null}
                  <p className="mt-2 max-w-3xl text-sm leading-relaxed">{a.descricao}</p>
                  <p className="mt-2 text-xs text-muted-foreground">
                    {a.imediato ? 'Disparo imediato · ' : 'Programado para '}
                    {formatarQuando(a.disparoEm)}
                  </p>
                </div>
                <div className="flex shrink-0 gap-2">
                  {a.situacao !== 'no-ar' ? (
                    <Button variant="outline" size="sm" onClick={() => publicarAgora(a)}>
                      Colocar no ar
                    </Button>
                  ) : (
                    <Button variant="outline" size="sm" onClick={() => encerrar(a)}>
                      Encerrar
                    </Button>
                  )}
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => arquivar.mutate({ id: a.id })}
                    aria-label={'Arquivar o aviso ' + a.titulo}
                  >
                    <Trash2 className="size-4" />
                  </Button>
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
