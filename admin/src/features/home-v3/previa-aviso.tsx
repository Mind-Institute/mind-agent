import type { IconeAviso } from '@/contracts';
import { IconeDoApp } from './icones-app';

/* ============================================================
   PRÉVIA DO AVISO
   ============================================================
   O painel é claro e o app é escuro. Mostrar o card no tema do painel
   enganaria quem escreve: contraste, peso da fonte e o quanto o texto
   cabe são outros lá. Então a prévia carrega os tokens do app —
   #13131a de fundo, #68ee95 de acento, Satoshi — e desenha o card do
   jeito que a pessoa vai ver.

   Dois estados, porque o aviso tem dois momentos: o card na lista e o
   texto que abre quando alguém toca. Só o primeiro é visto por todos;
   escrever a descrição sem ver esse segundo é como escrever no escuro.

   É espelho de `styles.css` (.v3-linha e .p-aviso) na raiz. Se o card
   mudar lá, muda aqui. */

const FUNDO = '#13131a';
const SUPERFICIE = '#2c2d3d';
const VERDE = '#68ee95';
const TEXTO = '#ffffff';
const MUDO = '#8f8fa3';
const FIO = 'rgba(143, 143, 163, 0.27)';

export interface PreviaAvisoProps {
  icone: IconeAviso;
  titulo: string;
  subtitulo: string;
  descricao: string;
}

export function PreviaAviso({ icone, titulo, subtitulo, descricao }: PreviaAvisoProps) {
  /* Placeholders só na prévia: um card sem título nenhum não mostraria
     nada, e a pessoa não veria o efeito do que está digitando. Eles não
     vão para o registro. */
  const tituloVisivel = titulo.trim() || 'Título do aviso';
  const subtituloVisivel = subtitulo.trim() || 'A linha de apoio aparece aqui';
  const descricaoVisivel = descricao.trim() || 'A mensagem completa aparece aqui, quando a pessoa toca no aviso.';
  const semTexto = titulo.trim() === '';

  return (
    <div
      className="space-y-4 rounded-xl p-4"
      style={{ background: FUNDO, fontFamily: 'Satoshi, system-ui, sans-serif' }}
    >
      {/* ---- Na lista ---- */}
      <div>
        <p
          className="mb-2 text-[10px] font-black uppercase tracking-[0.14em]"
          style={{ color: VERDE }}
        >
          Na lista de avisos
        </p>
        <div
          className="flex items-center gap-3 rounded-[18px] p-[14px_16px]"
          style={{ border: `1px solid ${FIO}`, minHeight: 68, opacity: semTexto ? 0.55 : 1 }}
        >
          <span
            className="grid size-10 shrink-0 place-items-center rounded-xl"
            style={{ background: SUPERFICIE, color: VERDE }}
          >
            <IconeDoApp nome={icone} className="size-[19px]" />
          </span>
          <span className="flex min-w-0 flex-1 flex-col gap-[3px]">
            <strong className="text-[15px] font-bold leading-tight" style={{ color: TEXTO }}>
              {tituloVisivel}
            </strong>
            <small className="text-[12.5px] leading-snug" style={{ color: MUDO }}>
              {subtituloVisivel}
            </small>
          </span>
          <svg
            viewBox="0 0 24 24" fill="none" stroke={MUDO} strokeWidth={2}
            strokeLinecap="round" strokeLinejoin="round"
            className="size-[17px] shrink-0" aria-hidden="true"
          >
            <path d="M9 5.5L15.5 12 9 18.5" />
          </svg>
        </div>
      </div>

      {/* ---- Ao tocar ---- */}
      <div>
        <p
          className="mb-2 text-[10px] font-black uppercase tracking-[0.14em]"
          style={{ color: VERDE }}
        >
          Quando a pessoa toca
        </p>
        <div
          className="rounded-[18px] p-4"
          style={{ border: `1px solid ${FIO}`, opacity: semTexto ? 0.55 : 1 }}
        >
          <p className="text-[17px] font-bold leading-tight" style={{ color: TEXTO }}>
            {tituloVisivel}
          </p>
          <p
            className="mt-3 whitespace-pre-line text-[14px] leading-relaxed"
            style={{ color: '#e3e3ed' }}
          >
            {descricaoVisivel}
          </p>
        </div>
      </div>

      <p className="text-[11px] leading-snug" style={{ color: MUDO }}>
        Aproximação do app: mesmas cores, mesma fonte e mesmos tamanhos. A largura
        real do celular é mais estreita, então título longo quebra antes.
      </p>
    </div>
  );
}
