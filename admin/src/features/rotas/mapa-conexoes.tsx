import type { Espaco, Rota } from '@/contracts';
import { formatarDistancia } from '@/lib/format';

/* ============================================================
   CONEXÕES ENTRE ESPAÇOS
   ============================================================
   Não é um editor de mapas — é um diagrama de conferência. Ele existe
   para responder de relance: "todo espaço tem como sair dele?".

   Espaço sem coordenada não aparece no desenho, e isso é dito em
   texto abaixo: sumir em silêncio seria pior que não desenhar. */
export function MapaConexoes({
  espacos,
  rotas,
}: {
  espacos: Espaco[];
  rotas: Rota[];
}) {
  const posicionados = espacos.filter(
    (e) => e.ativo && e.coordenadaX !== null && e.coordenadaY !== null,
  );
  const semCoordenada = espacos.filter(
    (e) => e.ativo && (e.coordenadaX === null || e.coordenadaY === null),
  );
  const porId = new Map(posicionados.map((e) => [e.id, e]));

  const arestas = rotas
    .filter((r) => r.ativo && porId.has(r.origemId) && porId.has(r.destinoId))
    .map((rota) => ({
      rota,
      origem: porId.get(rota.origemId) as Espaco,
      destino: porId.get(rota.destinoId) as Espaco,
    }));

  const conectados = new Set(arestas.flatMap((a) => [a.origem.id, a.destino.id]));
  const isolados = posicionados.filter((e) => !conectados.has(e.id));

  return (
    <div className="space-y-3">
      <div className="overflow-hidden rounded-lg border bg-card p-2">
        <svg
          viewBox="0 0 100 90"
          className="h-72 w-full"
          role="img"
          aria-label="Diagrama de conexões entre espaços"
        >
          {arestas.map(({ rota, origem, destino }) => (
            <g key={rota.id}>
              <line
                x1={origem.coordenadaX ?? 0}
                y1={origem.coordenadaY ?? 0}
                x2={destino.coordenadaX ?? 0}
                y2={destino.coordenadaY ?? 0}
                stroke={rota.acessivel ? '#0f9549' : '#ff7057'}
                strokeWidth={0.6}
                strokeDasharray={rota.bidirecional ? undefined : '2 1.2'}
              >
                <title>
                  {`${origem.nome} → ${destino.nome} · ${formatarDistancia(rota.distanciaMetros)}${
                    rota.acessivel ? '' : ' · sem rota acessível'
                  }`}
                </title>
              </line>
            </g>
          ))}

          {posicionados.map((espaco) => (
            <g key={espaco.id}>
              <circle
                cx={espaco.coordenadaX ?? 0}
                cy={espaco.coordenadaY ?? 0}
                r={2}
                fill={conectados.has(espaco.id) ? '#0f9549' : '#ff7057'}
              />
              <text
                x={espaco.coordenadaX ?? 0}
                y={(espaco.coordenadaY ?? 0) - 3}
                textAnchor="middle"
                fontSize={2.6}
                fill="#334155"
              >
                {espaco.nome}
              </text>
            </g>
          ))}
        </svg>
      </div>

      <div className="flex flex-wrap gap-x-5 gap-y-1 text-xs text-muted-foreground">
        <span>
          <span className="mr-1 inline-block size-2 rounded-full bg-verde-600" />
          conectado / rota acessível
        </span>
        <span>
          <span className="mr-1 inline-block size-2 rounded-full bg-coral-400" />
          isolado / rota não acessível
        </span>
        <span>linha tracejada = mão única</span>
      </div>

      {isolados.length > 0 ? (
        <p className="text-xs text-coral-700">
          Sem nenhuma rota cadastrada: {isolados.map((e) => e.nome).join(', ')}.
        </p>
      ) : null}

      {semCoordenada.length > 0 ? (
        <p className="text-xs text-muted-foreground">
          Fora do diagrama por falta de coordenada: {semCoordenada.map((e) => e.nome).join(', ')}.
        </p>
      ) : null}
    </div>
  );
}
