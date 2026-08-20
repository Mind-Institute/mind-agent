import { ImageOff } from 'lucide-react';
import type { Tema } from '@/contracts';
import { urlDaFoto } from '@/lib/fotos';

/* ============================================================
   PRÉVIA DO CARTÃO NO CHAT
   ============================================================
   Reprodução do cartão de palestrante como ele aparece no chat — que
   é escuro, ao contrário do painel. A cor de fundo é o token `--bg`
   do `styles.css` da raiz; o verde e o coral são os mesmos.

   Serve para uma coisa só: mostrar a quem edita o efeito real de um
   campo vazio. Biografia em branco aqui vira cartão mudo lá. */
export function PreviaCartaoPalestrante({
  palestrante,
  temas,
}: {
  palestrante: {
    nome: string;
    cargo: string;
    organizacao: string;
    biografia: string;
    foto: string;
    temas: string[];
    destaque: boolean;
  };
  temas: Tema[];
}) {
  const foto = urlDaFoto(palestrante.foto);
  const rotuloTema = (codigo: string) => temas.find((t) => t.codigo === codigo)?.rotulo ?? codigo;
  const credencial = [palestrante.organizacao, palestrante.cargo].filter(Boolean).join(' · ');

  return (
    <div className="rounded-xl bg-[#13131a] p-4 text-white shadow-inner">
      <p className="mb-3 text-[10px] font-black uppercase tracking-widest text-white/40">
        Prévia · como aparece no chat
      </p>

      <div className="rounded-[18px] bg-[#2c2d3d] p-4">
        <div className="flex items-start gap-3">
          {foto ? (
            <img
              src={foto}
              alt=""
              className="size-14 shrink-0 rounded-full object-cover"
              loading="lazy"
            />
          ) : (
            <div className="flex size-14 shrink-0 items-center justify-center rounded-full border border-dashed border-white/25 text-white/40">
              <ImageOff className="size-5" />
            </div>
          )}

          <div className="min-w-0 flex-1">
            <p className="truncate text-[15px] font-bold leading-tight">
              {palestrante.nome || 'Sem nome'}
            </p>
            <p className="mt-0.5 truncate text-xs text-[#68ee95]">
              {credencial || 'sem credencial cadastrada'}
            </p>
            {palestrante.destaque ? (
              <span className="mt-1.5 inline-block rounded-full bg-[#ff7057] px-2 py-0.5 text-[10px] font-black uppercase tracking-wide text-[#13131a]">
                destaque
              </span>
            ) : null}
          </div>
        </div>

        <p className="mt-3 text-[13px] leading-relaxed text-[#e3e3ed]">
          {palestrante.biografia || (
            <em className="text-[#ff7057] not-italic">
              Sem biografia — o cartão sai vazio e o agente não tem o que dizer sobre esta pessoa.
            </em>
          )}
        </p>

        {palestrante.temas.length > 0 ? (
          <ul className="mt-3 flex flex-wrap gap-1.5">
            {palestrante.temas.map((tema) => (
              <li
                key={tema}
                className="rounded-full border border-[#68ee95]/40 px-2 py-0.5 text-[11px] text-[#68ee95]"
              >
                {rotuloTema(tema)}
              </li>
            ))}
          </ul>
        ) : (
          <p className="mt-3 text-[11px] text-white/40">Sem temas — não entra em nenhuma trilha.</p>
        )}
      </div>
    </div>
  );
}
