import * as React from 'react';
import { IconMessage, IconPencil } from '@tabler/icons-react';
import {
  Sidebar,
  SidebarFooter,
  SidebarHeader,
  SidebarItem,
  SidebarNav,
  SidebarSection,
  SidebarToggle,
  useSidebar,
} from '@/components/ui/sidebar';
import { ThinkingPromptInput } from '@/components/ui/thinking-prompt-input';
import type { ThinkingStatus, ThinkingStep } from '@/components/ui/thinking-prompt-input';

/* ============================================================================
 * VITRINE — a lateral do `sidebar.tsx` com a conversa do `ThinkingPromptInput`
 * ============================================================================
 * É para VER o desenho composto antes de decidir levá-lo para a MIA. Não é o
 * painel, não é a MIA, e nada aqui fala com servidor: os passos e a resposta
 * são de mentira, gerados por `setTimeout` nesta página.
 *
 * As conversas da lista são as do Vinícius de verdade, lidas do banco em 29/10,
 * porque uma vitrine com "Conversa 1, Conversa 2" não deixa julgar como títulos
 * reais se comportam numa coluna estreita — que é metade do que se está
 * olhando aqui.
 *
 * Não é importada por nenhuma tela do painel. Para descartar: apague o arquivo.
 * ==========================================================================*/

type Conversa = { id: string; titulo: string; quando: string; mensagens: number };

const CONVERSAS: Conversa[] = [
  { id: 'c1', titulo: 'Tipos de fracasso', quando: 'hoje', mensagens: 4 },
  { id: 'c2', titulo: 'Burnout e desenho do trabalho', quando: '28/10', mensagens: 12 },
  { id: 'c3', titulo: 'Plano de 30 dias para engajamento', quando: '27/10', mensagens: 7 },
  { id: 'c4', titulo: 'O que o Summit disse sobre NR-1', quando: '27/10', mensagens: 5 },
  { id: 'c5', titulo: 'Seis áreas do burnout, com os minutos', quando: '26/10', mensagens: 9 },
  { id: 'c6', titulo: 'ola, o que eu posso assistir depois do almoço?', quando: '26/10', mensagens: 2 },
];

const PERGUNTA = 'O que a Amy Edmondson falou sobre tipos de fracasso?';
const RESPOSTA =
  'Ela separa três tipos, e o ponto é que só um deles vale a pena pagar.\n' +
  'O fracasso básico vem de desatenção num processo conhecido — não tem nada a ensinar.\n' +
  'O complexo vem de muitas causas num sistema que já se conhece; dá para reduzir.\n' +
  'O inteligente acontece em território novo, com hipótese declarada e o menor custo possível — e é esse que gera conhecimento.';

/* OS PASSOS SÃO OS DA MIA, copiados de `passosDaEspera` no bloco do
   LearnWorlds. Escrever outros aqui faria a vitrine prometer uma espera que o
   produto não entrega. */
const PASSOS: ThinkingStep[] = [
  { id: 'lendo', text: 'Lendo sua pergunta', status: 'active' },
  { id: 'busca', text: 'Procurando no acervo do Summit', status: 'active' },
  { id: 'achou', text: 'Lendo o que encontrou', status: 'complete' },
];

/* ============================================================
   A PALETA E A FONTE DA MIA
   ============================================================
   Os dois componentes leem os tokens do shadcn (`hsl(var(--foreground))` e
   companhia), então a troca de identidade acontece REDEFININDO esses tokens
   neste contêiner — não reescrevendo classe por classe. Qualquer peça que
   entrar aqui dentro passa a falar roxo sozinha.

   Os valores são os mesmos do bloco (`--mia-roxo: #9843ff`, `--mia-texto:
   #1b1b24`, `--mia-mudo: #70708a`, `--mia-dela: #f5eeff`), convertidos para a
   tripla HSL que o shadcn espera. Hex aqui não funcionaria: o token entra
   dentro de `hsl(...)`.

   A FONTE é a mesma pilha do bloco, com o mesmo motivo: Satoshi quando a
   página tiver, e uma pilha de sistema atrás — sem buscar fonte em servidor
   nenhum. */
const PALETA_DA_MIA = {
  '--background': '0 0% 100%',
  '--foreground': '240 14% 12%',
  '--muted': '250 30% 96%',
  '--muted-foreground': '240 10% 49%',
  '--card': '0 0% 100%',
  '--card-foreground': '240 14% 12%',
  '--primary': '267 100% 63%',
  '--primary-foreground': '0 0% 100%',
  '--border': '240 7% 89%',
  '--ring': '267 100% 63%',
  /* OS `--primitive-*` SÃO A PORTA DE IDENTIDADE do sidebar. Sem eles valem as
     reservas, que são cinza puro — e um item selecionado em cinza, numa peça
     da MIA, não diz onde a pessoa está: diz que alguém esqueceu de pintar.
     `surface-selected` é o mesmo lilás das bolhas dela (`--mia-dela`). */
  '--primitive-surface-selected': 'hsl(265 100% 96%)',
  '--primitive-surface-hover': 'hsl(265 100% 98%)',
  '--primitive-ring': 'hsl(267 100% 63% / 0.45)',
  fontFamily:
    'Satoshi, "Satoshi Variable", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, "Noto Sans", sans-serif',
} as React.CSSProperties;

/* O símbolo da Mind, o mesmo desenho do bloco. Ele é a marca no cabeçalho e a
   pétala que gira enquanto ela procura — um desenho só, dois usos, como lá. */
function Petala({ className }: { className?: string }) {
  return (
    <svg viewBox="698.13 264.35 522.24 522.24" className={className} aria-hidden="true">
      <path
        fill="currentColor"
        d="M1143.23,448.33c-21.02,0-40.08,8.41-53.99,22.05-32.36,27.8-75.06,45.12-121.83,46.93,1.81-46.77,19.14-89.47,46.93-121.83,13.64-13.91,22.05-32.97,22.05-53.99,0-42.6-34.54-77.14-77.14-77.14s-77.14,34.54-77.14,77.14c0,21.02,8.41,40.08,22.05,53.99,27.79,32.36,45.12,75.06,46.93,121.83-46.77-1.81-89.47-19.14-121.83-46.93-13.91-13.64-32.97-22.05-53.99-22.05-42.6,0-77.14,34.54-77.14,77.14s34.54,77.14,77.14,77.14c21.02,0,40.08-8.41,53.99-22.05,32.36-27.79,75.06-45.12,121.83-46.93-1.81,46.77-19.14,89.47-46.93,121.83-13.64,13.91-22.05,32.97-22.05,53.99,0,42.6,34.54,77.14,77.14,77.14s77.14-34.54,77.14-77.14c0-21.02-8.41-40.08-22.05-53.99-27.8-32.36-45.12-75.06-46.93-121.83,46.77,1.81,89.47,19.14,121.83,46.93,13.91,13.64,32.97,22.05,53.99,22.05,42.6,0,77.14-34.54,77.14-77.14s-34.54-77.14-77.14-77.14Z"
      />
    </svg>
  );
}

/* O "Novo chat" não é item de navegação: é ação. Fica no cabeçalho, acima da
   lista, como no desenho que o Vinícius escolheu. */
function MarcaDaMia() {
  const { collapsed } = useSidebar();
  return (
    <div className="flex min-w-0 items-center gap-2.5">
      <span className="flex size-6 shrink-0 items-center justify-center rounded-[7px] bg-[hsl(var(--primary))] text-[hsl(var(--primary-foreground))]">
        <Petala className="size-3.5" />
      </span>
      {!collapsed && (
        <span className="truncate text-[13.5px] font-semibold leading-none">MIA Summit</span>
      )}
    </div>
  );
}

function RodapeDoAluno() {
  const { collapsed } = useSidebar();
  if (collapsed) {
    return (
      <div className="flex size-6 items-center justify-center rounded-full bg-[color-mix(in_srgb,hsl(var(--foreground))_8%,transparent)] text-[10px] font-bold">
        V
      </div>
    );
  }
  return (
    <div className="min-w-0 flex-1">
      <div className="truncate text-[12.5px] font-medium leading-tight">Vinius Muniz</div>
      <div className="truncate text-[11px] leading-tight text-[hsl(var(--muted-foreground))]">
        vinicius@joinmind.com.br
      </div>
    </div>
  );
}

export default function MiaVitrine() {
  const [aberta, setAberta] = React.useState('c1');
  const [status, setStatus] = React.useState<ThinkingStatus>('idle');
  const [pergunta, setPergunta] = React.useState('');
  const [passos, setPassos] = React.useState<ThinkingStep[]>([]);
  const [resposta, setResposta] = React.useState('');
  const [segundos, setSegundos] = React.useState(0);
  const relogios = React.useRef<number[]>([]);

  const limpar = React.useCallback(() => {
    relogios.current.forEach((t) => window.clearTimeout(t));
    relogios.current = [];
  }, []);

  React.useEffect(() => limpar, [limpar]);

  /* Um turno de mentira, com a mesma forma de um turno de verdade da MIA:
     busca, leitura, e só então a resposta — que chega aos pedaços. */
  const rodarTurno = React.useCallback(
    (texto: string) => {
      limpar();
      const depois = (ms: number, fn: () => void) => {
        relogios.current.push(window.setTimeout(fn, ms));
      };
      setPergunta(texto);
      setResposta('');
      setPassos([]);
      setSegundos(0);
      setStatus('thinking');

      [700, 1500, 2400].forEach((ms, i) =>
        depois(ms, () =>
          setPassos(
            PASSOS.slice(0, i + 1).map((p, j) => ({
              ...p,
              status: j < i ? ('complete' as const) : p.status,
            })),
          ),
        ),
      );
      [1, 2, 3].forEach((s) => depois(s * 900, () => setSegundos(s)));

      depois(3000, () => {
        setPassos(PASSOS.map((p) => ({ ...p, status: 'complete' as const })));
        setSegundos(4);
        setStatus('answering');
      });
      const corpo = texto === PERGUNTA ? RESPOSTA : `Esta vitrine não fala com servidor nenhum.\nVocê perguntou: "${texto}"`;
      depois(3300, () => {
        let i = 0;
        const passo = () => {
          i += 4;
          setResposta(corpo.slice(0, i));
          if (i < corpo.length) relogios.current.push(window.setTimeout(passo, 26));
          else setStatus('done');
        };
        passo();
      });
    },
    [limpar],
  );

  React.useEffect(() => {
    const t = window.setTimeout(() => rodarTurno(PERGUNTA), 600);
    return () => window.clearTimeout(t);
  }, [rodarTurno]);

  function novaConversa() {
    limpar();
    setStatus('idle');
    setPergunta('');
    setPassos([]);
    setResposta('');
    setAberta('');
  }

  return (
    <div
      style={PALETA_DA_MIA}
      className="flex h-screen w-full bg-[hsl(var(--background))] text-[hsl(var(--foreground))]"
    >
      <Sidebar variant="collapsible" width={268} aria-label="Suas conversas com a MIA">
        <SidebarHeader>
          <MarcaDaMia />
          <SidebarToggle className="ml-auto" />
        </SidebarHeader>
        <SidebarNav>
          <SidebarSection>
            <SidebarItem
              icon={<IconPencil className="size-[18px]" stroke={1.75} />}
              onClick={novaConversa}
            >
              Novo chat
            </SidebarItem>
          </SidebarSection>
          <SidebarSection label="Conversas">
            {CONVERSAS.map((c) => (
              <SidebarItem
                key={c.id}
                icon={<IconMessage className="size-[18px]" stroke={1.75} />}
                active={aberta === c.id}
                onClick={() => setAberta(c.id)}
              >
                {c.titulo}
              </SidebarItem>
            ))}
          </SidebarSection>
        </SidebarNav>
        <SidebarFooter>
          <RodapeDoAluno />
        </SidebarFooter>
      </Sidebar>

      {/* A conversa. `min-w-0` é o que deixa a coluna encolher quando a lateral
          abre — sem ele o flex usa a largura do conteúdo e a lateral empurra a
          conversa para fora em vez de dividir o espaço. */}
      <div className="flex min-w-0 flex-1 justify-center overflow-hidden px-6 py-8">
        <div className="flex h-full w-full max-w-[560px] flex-col">
          <ThinkingPromptInput
            className="max-w-none"
            status={status}
            prompt={pergunta}
            steps={passos}
            answer={resposta}
            elapsedSeconds={segundos}
            placeholder="Pergunte à MIA…"
            followUpPlaceholder="Pergunte outra coisa…"
            icon={<Petala className="size-3.5" />}
            showThink={false}
            labels={{
              thinking: 'Procurando no acervo',
              thoughtFor: (s) => `Pensou por ${s}s`,
              think: 'Buscar no acervo',
              stop: 'Parar',
              send: 'Enviar pergunta',
              conversation: 'Conversa',
              response: 'Resposta',
              stepComplete: 'Concluído',
              stepInProgress: 'Em andamento',
            }}
            onSubmit={(texto) => rodarTurno(texto)}
            onStop={novaConversa}
            answerNote={
              status === 'done' && pergunta === PERGUNTA
                ? 'As melhores equipes erram diferente · Amy Edmondson, 17/09'
                : undefined
            }
          />
        </div>
      </div>
    </div>
  );
}
