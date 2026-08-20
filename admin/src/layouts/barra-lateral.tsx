import { NavLink } from 'react-router-dom';
import { Lock } from 'lucide-react';
import simboloMind from '@marca/simbolo-mind-verde.png';
import { NAVEGACAO } from '@/routes/navegacao';
import { useSessao } from '@/hooks/use-sessao';
import { cn } from '@/lib/utils';

/**
 * Barra lateral fixa — o painel é desktop-first porque é ferramenta de
 * trabalho, não landing page. Abaixo de `lg` ela vira gaveta (ver
 * `AdminLayout`).
 */
export function BarraLateral({ aoNavegar }: { aoNavegar?: () => void }) {
  const sessao = useSessao();

  return (
    <nav aria-label="Navegação principal" className="flex h-full flex-col gap-1 overflow-y-auto p-3">
      <div className="mb-3 flex items-center gap-2.5 px-2 py-1">
        <img src={simboloMind} alt="" className="size-7" />
        <div className="leading-tight">
          <p className="text-sm font-black tracking-tight">Mind Agent</p>
          <p className="text-[11px] font-semibold uppercase tracking-widest text-muted-foreground">
            Administração
          </p>
        </div>
      </div>

      {NAVEGACAO.map((grupo) => (
        <div key={grupo.id} className="mb-1">
          {grupo.rotulo ? (
            <p className="px-2 pb-1 pt-3 text-[10px] font-black uppercase tracking-widest text-muted-foreground">
              {grupo.rotulo}
            </p>
          ) : null}
          <ul className="space-y-0.5">
            {grupo.itens.map((item) => {
              const permitido = item.permissao ? sessao.pode(item.permissao) : true;
              const Icone = item.icone;
              return (
                <li key={item.id}>
                  <NavLink
                    to={item.caminho}
                    end={item.caminho === '/'}
                    onClick={aoNavegar}
                    title={permitido ? item.descricao : `Sem permissão · ${item.descricao}`}
                    className={({ isActive }) =>
                      cn(
                        'flex items-center gap-2.5 rounded-md px-2.5 py-2 text-sm font-semibold transition-colors',
                        isActive
                          ? 'bg-verde-100 text-verde-900'
                          : 'text-slate-600 hover:bg-muted hover:text-foreground',
                        !permitido && 'opacity-50',
                      )
                    }
                  >
                    <Icone className="size-4 shrink-0" />
                    <span className="truncate">{item.rotulo}</span>
                    {!permitido ? <Lock className="ml-auto size-3 shrink-0" /> : null}
                  </NavLink>
                </li>
              );
            })}
          </ul>
        </div>
      ))}

      <p className="mt-auto px-2 pt-4 text-[11px] leading-relaxed text-muted-foreground">
        Mind Summit 2026 · 16 e 17 de setembro
        <br />
        São Paulo · America/Sao_Paulo
      </p>
    </nav>
  );
}
