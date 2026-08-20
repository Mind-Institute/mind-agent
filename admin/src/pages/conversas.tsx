import { useNavigate, useParams } from 'react-router-dom';
import { EyeOff, PhoneForwarded } from 'lucide-react';
import {
  CANAIS,
  ROTULO_CANAL,
  ROTULO_STATUS_CONVERSA,
  STATUS_CONVERSA,
  type Conversa,
} from '@/contracts';
import { useItem } from '@/hooks/use-recurso';
import { formatarDataHora, formatarRelativo } from '@/lib/format';
import { mascararNome, mascararTextoLivre } from '@/lib/mask';
import { PaginaListagem, type Coluna } from '@/components/admin/pagina-listagem';
import { ContatoMascarado } from '@/components/admin/dado-pessoal';
import { EstadoCarregando, EstadoErro, EstadoVazio } from '@/components/admin/estados';
import { Badge } from '@/components/ui/badge';
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from '@/components/ui/sheet';
import { cn } from '@/lib/utils';

/* ============================================================
   CONVERSAS — SOMENTE LEITURA
   ============================================================
   O painel não responde por aqui e não edita histórico.

   Dado pessoal nunca aparece inteiro: nome vira "Fulana S.", contato
   vira "••••-7777", e o texto das mensagens ainda passa por
   `mascararTextoLivre` — porque participante digita e-mail e telefone
   no meio da frase, e isso não pode vazar para a tela do painel. */

function BolhaMensagem({
  autor,
  texto,
  enviadaEm,
}: {
  autor: 'participante' | 'agente' | 'humano';
  texto: string;
  enviadaEm: string;
}) {
  const doParticipante = autor === 'participante';
  return (
    <li className={cn('flex', doParticipante ? 'justify-start' : 'justify-end')}>
      <div
        className={cn(
          'max-w-[85%] rounded-2xl px-3.5 py-2.5 text-sm',
          doParticipante
            ? 'rounded-tl-sm bg-muted text-foreground'
            : autor === 'humano'
              ? 'rounded-tr-sm bg-coral-100 text-coral-900'
              : 'rounded-tr-sm bg-verde-100 text-verde-900',
        )}
      >
        <p className="mb-1 text-[10px] font-black uppercase tracking-wide opacity-60">
          {autor === 'participante' ? 'Participante' : autor === 'agente' ? 'Mind Agent' : 'Atendimento humano'}
        </p>
        {/* Rede de segurança: mascara e-mail/telefone digitados no texto. */}
        <p className="whitespace-pre-wrap">{mascararTextoLivre(texto)}</p>
        <p className="mt-1 text-[10px] opacity-50">{formatarDataHora(enviadaEm)}</p>
      </div>
    </li>
  );
}

function PainelConversa({ id, aoFechar }: { id: string | undefined; aoFechar: () => void }) {
  const consulta = useItem('conversations', id);
  const conversa = consulta.data;

  return (
    <Sheet open={Boolean(id)} onOpenChange={(aberto) => (!aberto ? aoFechar() : undefined)}>
      <SheetContent side="right" className="w-full p-0 sm:max-w-xl">
        <SheetHeader>
          <SheetTitle>
            {conversa ? mascararNome(conversa.participanteNome) : 'Conversa'}
          </SheetTitle>
          <SheetDescription asChild>
            <div className="flex flex-wrap items-center gap-2 text-xs">
              {conversa ? (
                <>
                  <Badge variant="outline">{ROTULO_CANAL[conversa.canal]}</Badge>
                  <ContatoMascarado valor={conversa.participanteContato} />
                  <span className="text-muted-foreground">
                    {conversa.totalMensagens} mensagens · início {formatarDataHora(conversa.iniciadaEm)}
                  </span>
                </>
              ) : null}
            </div>
          </SheetDescription>
        </SheetHeader>

        <div className="flex-1 overflow-y-auto p-5">
          {consulta.isPending ? (
            <EstadoCarregando linhas={5} />
          ) : consulta.error ? (
            <EstadoErro erro={consulta.error} aoTentarNovamente={() => void consulta.refetch()} />
          ) : !conversa ? null : conversa.mensagens.length === 0 ? (
            <EstadoVazio titulo="Conversa sem mensagens registradas" />
          ) : (
            <ul className="space-y-3">
              {conversa.mensagens.map((m) => (
                <BolhaMensagem key={m.id} autor={m.autor} texto={m.texto} enviadaEm={m.enviadaEm} />
              ))}
            </ul>
          )}
        </div>

        <div className="border-t bg-muted/40 px-5 py-3 text-xs text-muted-foreground">
          <p className="flex items-center gap-1.5">
            <EyeOff className="size-3.5" />
            Somente leitura. Dados pessoais mascarados: o painel não mostra e-mail nem telefone
            inteiros.
          </p>
        </div>
      </SheetContent>
    </Sheet>
  );
}

export function PaginaConversas() {
  const { id } = useParams();
  const navegar = useNavigate();

  const colunas: Coluna<Conversa>[] = [
    {
      chave: 'participante',
      cabecalho: 'Participante',
      celula: (c) => (
        <div className="min-w-44">
          <p className="font-semibold">{mascararNome(c.participanteNome) || 'Anônimo'}</p>
          <ContatoMascarado valor={c.participanteContato} />
        </div>
      ),
    },
    {
      chave: 'canal',
      cabecalho: 'Canal',
      celula: (c) => <Badge variant="outline">{ROTULO_CANAL[c.canal]}</Badge>,
    },
    {
      chave: 'inicio',
      cabecalho: 'Data',
      className: 'whitespace-nowrap tabular',
      celula: (c) => <span className="text-xs">{formatarDataHora(c.iniciadaEm)}</span>,
    },
    {
      chave: 'atividade',
      cabecalho: 'Última atividade',
      className: 'whitespace-nowrap',
      celula: (c) => <span className="text-xs">{formatarRelativo(c.ultimaAtividadeEm)}</span>,
    },
    {
      chave: 'mensagens',
      cabecalho: 'Mensagens',
      className: 'tabular',
      celula: (c) => c.totalMensagens,
    },
    {
      chave: 'assuntos',
      cabecalho: 'Assuntos',
      celula: (c) => (
        <div className="flex max-w-56 flex-wrap gap-1">
          {c.assuntos.map((a) => (
            <Badge key={a} variant="secondary">
              {a}
            </Badge>
          ))}
        </div>
      ),
    },
    {
      chave: 'handoff',
      cabecalho: 'Handoff',
      celula: (c) =>
        c.handoff ? (
          <Badge variant="atencao">
            <PhoneForwarded className="size-3" />
            sim
          </Badge>
        ) : (
          <span className="text-xs text-muted-foreground">não</span>
        ),
    },
    {
      chave: 'status',
      cabecalho: 'Status',
      celula: (c) => (
        <Badge
          variant={
            c.status === 'resolvida' ? 'sucesso' : c.status === 'aberta' ? 'atencao' : 'neutro'
          }
        >
          {ROTULO_STATUS_CONVERSA[c.status]}
        </Badge>
      ),
    },
  ];

  return (
    <>
      <PaginaListagem
        recurso="conversations"
        titulo="Conversas"
        descricao="Histórico somente leitura do chat próprio e do Treble. Dados pessoais aparecem mascarados — aqui e no detalhe."
        colunas={colunas}
        ordenar="-ultimaAtividadeEm"
        placeholderBusca="Buscar por assunto…"
        permissaoNecessaria="ver_conversas"
        destinoItem={(c) => `/conversas/${c.id}`}
        definicoesFiltro={[
          {
            chave: 'canal',
            rotulo: 'Canal',
            opcoes: CANAIS.map((c) => ({ valor: c, rotulo: ROTULO_CANAL[c] })),
          },
          {
            chave: 'status',
            rotulo: 'Status',
            opcoes: STATUS_CONVERSA.map((s) => ({ valor: s, rotulo: ROTULO_STATUS_CONVERSA[s] })),
          },
          {
            chave: 'handoff',
            rotulo: 'Handoff',
            opcoes: [
              { valor: 'true', rotulo: 'Com handoff' },
              { valor: 'false', rotulo: 'Sem handoff' },
            ],
          },
        ]}
        estadoVazio={
          <EstadoVazio
            titulo="Nenhuma conversa no recorte"
            descricao="Nenhuma conversa bate com a busca e os filtros atuais."
          />
        }
      />

      <PainelConversa id={id} aoFechar={() => navegar('/conversas')} />
    </>
  );
}
