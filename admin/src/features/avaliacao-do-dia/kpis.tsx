import type { Distribuicao, NotaGeral } from '@/services/avaliacao-api';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';

/* ============================================================
   KPIs — média sempre ao lado do tamanho da amostra
   ============================================================
   Uma média sem denominador mente por omissão: 5,0 com uma resposta e
   5,0 com duzentas são números diferentes na cabeça de quem decide. Aqui
   os dois andam juntos, sempre, e nenhum componente daqui aceita
   desenhar um sem o outro.

   NÃO É NPS. Nada nesta tela subtrai detrator de promotor, e a escala é
   0 a 5. O que substitui o índice é o percentual de 4 e 5 — que é o que
   a pergunta realmente mede. */

const NOTAS: (keyof Distribuicao)[] = ['0', '1', '2', '3', '4', '5'];

export function Numero({ valor }: { valor: number | null }) {
  if (valor === null || valor === undefined) {
    return <span className="text-muted-foreground">—</span>;
  }
  return <>{valor.toFixed(2).replace('.', ',')}</>;
}

export function BarrasDeDistribuicao({
  distribuicao,
  total,
}: {
  distribuicao: Distribuicao;
  total: number;
}) {
  const maior = Math.max(...NOTAS.map((n) => distribuicao[n] ?? 0), 1);
  return (
    <ul className="flex items-end gap-1.5" aria-label="Distribuição das notas de 0 a 5">
      {NOTAS.map((n) => {
        const quantos = distribuicao[n] ?? 0;
        const proporcao = total > 0 ? Math.round((quantos / total) * 100) : 0;
        return (
          <li key={n} className="flex flex-1 flex-col items-center gap-1">
            <span className="text-[10px] font-bold tabular-nums text-muted-foreground">
              {quantos}
            </span>
            <div
              className="w-full rounded-sm bg-verde-400"
              style={{ height: `${8 + (quantos / maior) * 44}px` }}
              title={`Nota ${n}: ${quantos} (${proporcao}%)`}
            />
            <span className="text-[11px] font-bold tabular-nums">{n}</span>
          </li>
        );
      })}
    </ul>
  );
}

export function CartaoDeNota({ titulo, nota }: { titulo: string; nota: NotaGeral }) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-bold">{titulo}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex items-baseline gap-2">
          <p className="text-3xl font-black tabular-nums">
            <Numero valor={nota.media} />
          </p>
          <span className="text-sm text-muted-foreground">de 5</span>
        </div>
        <p className="text-xs text-muted-foreground">
          {nota.amostra === 0
            ? 'Sem respostas'
            : `${nota.amostra} ${nota.amostra === 1 ? 'resposta' : 'respostas'}`}
          {nota.percentual45 !== null ? (
            <>
              {' · '}
              <Badge variant="sucesso">
                {String(nota.percentual45).replace('.', ',')}% deram 4 ou 5
              </Badge>
            </>
          ) : null}
        </p>
        {nota.amostra > 0 ? (
          <BarrasDeDistribuicao distribuicao={nota.distribuicao} total={nota.amostra} />
        ) : null}
      </CardContent>
    </Card>
  );
}

export function CartaoSimples({
  titulo,
  valor,
  apoio,
}: {
  titulo: string;
  valor: number | string;
  apoio?: string;
}) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-bold">{titulo}</CardTitle>
      </CardHeader>
      <CardContent>
        <p className="text-3xl font-black tabular-nums">{valor}</p>
        {apoio ? <p className="mt-1 text-xs text-muted-foreground">{apoio}</p> : null}
      </CardContent>
    </Card>
  );
}
