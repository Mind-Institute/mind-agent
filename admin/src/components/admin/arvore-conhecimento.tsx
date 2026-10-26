import { useMemo, useState } from 'react';
import { ChevronDown, ChevronRight } from 'lucide-react';
import type { BusinessConsulting, ObjetoConsulting, SecaoConsulting } from '@/services/business-consulting';
import { Badge } from '@/components/ui/badge';

/* A ÁRVORE DO CONHECIMENTO (Adriana, 24/10/2026): "ir clicando para abrir cada vez mais" e
   entender o que orienta a IA. Livro → seções na ordem do livro → objetos de cada seção → as
   relações de cada objeto, que abrem de novo, sem fim. Nada é carregado a mais: tudo vem na
   mesma leitura da página. Um objeto que já está aberto acima não reabre embaixo dele mesmo —
   relação circular aparece, mas não vira poço infinito. */

const legivel = (valor: string) => valor.replaceAll('_', ' ');

type Indices = {
  objetos: Map<string, ObjetoConsulting>;
  saindo: Map<string, { para: string; tipo: string }[]>;
  chegando: Map<string, { de: string; tipo: string }[]>;
};

export function ArvoreConhecimento({
  dados,
  aoAbrirFicha,
}: {
  dados: BusinessConsulting;
  aoAbrirFicha: (id: string) => void;
}) {
  const indices = useMemo<Indices>(() => {
    const saindo = new Map<string, { para: string; tipo: string }[]>();
    const chegando = new Map<string, { de: string; tipo: string }[]>();
    for (const r of dados.relacoes) {
      saindo.set(r.de, [...(saindo.get(r.de) ?? []), { para: r.para, tipo: r.tipo }]);
      chegando.set(r.para, [...(chegando.get(r.para) ?? []), { de: r.de, tipo: r.tipo }]);
    }
    return { objetos: new Map(dados.objetos.map((o) => [o.id, o])), saindo, chegando };
  }, [dados]);

  return (
    <ul className="space-y-2" aria-label="Árvore do conhecimento">
      {dados.livros.map((livro) => {
        const secoes = dados.secoes.filter((s) => s.livro_id === livro.id);
        return (
          <No
            key={livro.id}
            nivel={0}
            titulo={<span className="text-base font-black">{livro.titulo}</span>}
            sufixo={<span className="text-xs text-muted-foreground">{(livro.autores ?? []).join(', ')} · {livro.objetos} objetos</span>}
          >
            {secoes.map((secao) => (
              <NoSecao
                key={secao.id}
                secao={secao}
                objetos={dados.objetos.filter((o) => o.secao_id === secao.id)}
                indices={indices}
                aoAbrirFicha={aoAbrirFicha}
              />
            ))}
          </No>
        );
      })}
    </ul>
  );
}

function NoSecao({
  secao,
  objetos,
  indices,
  aoAbrirFicha,
}: {
  secao: SecaoConsulting;
  objetos: ObjetoConsulting[];
  indices: Indices;
  aoAbrirFicha: (id: string) => void;
}) {
  const paginas = secao.pagina_inicio != null
    ? ` · p. ${secao.pagina_inicio}${secao.pagina_fim != null && secao.pagina_fim !== secao.pagina_inicio ? `–${secao.pagina_fim}` : ''}`
    : '';
  // Parte sem objetos próprios é divisória do livro, não nó que abre.
  if (objetos.length === 0) {
    return (
      <li className="pl-6 pt-2 text-[11px] font-black uppercase tracking-widest text-muted-foreground">
        {secao.titulo}
        <span className="font-normal normal-case tracking-normal">{secao.tipo ? ` · ${legivel(secao.tipo)}` : ''}{paginas}</span>
      </li>
    );
  }
  return (
    <No
      nivel={1}
      titulo={<span className="font-bold">{secao.titulo}</span>}
      sufixo={<span className="text-xs text-muted-foreground">{secao.tipo ? legivel(secao.tipo) : ''}{paginas} · {objetos.length} objetos</span>}
    >
      {objetos.map((o) => (
        <NoObjeto key={o.id} objeto={o} nivel={2} acima={new Set()} indices={indices} aoAbrirFicha={aoAbrirFicha} />
      ))}
    </No>
  );
}

function NoObjeto({
  objeto,
  nivel,
  acima,
  indices,
  aoAbrirFicha,
  relacao,
}: {
  objeto: ObjetoConsulting;
  nivel: number;
  acima: Set<string>;
  indices: Indices;
  aoAbrirFicha: (id: string) => void;
  relacao?: string;
}) {
  const ligados = [
    ...(indices.saindo.get(objeto.id) ?? []).map((r) => ({ id: r.para, rotulo: legivel(r.tipo) })),
    ...(indices.chegando.get(objeto.id) ?? []).map((r) => ({ id: r.de, rotulo: `← ${legivel(r.tipo)}` })),
  ].filter((r) => indices.objetos.has(r.id));
  const caminho = new Set(acima).add(objeto.id);

  return (
    <No
      nivel={nivel}
      folha={ligados.length === 0}
      titulo={
        <span className="flex flex-wrap items-center gap-2">
          {relacao ? <span className="text-xs italic text-muted-foreground">{relacao}</span> : null}
          <button
            type="button"
            className="text-left font-semibold underline-offset-2 hover:underline"
            onClick={(e) => { e.stopPropagation(); aoAbrirFicha(objeto.id); }}
          >
            {objeto.nome}
          </button>
          <Badge variant="neutro">{legivel(objeto.tipo)}</Badge>
        </span>
      }
      sufixo={objeto.resumo ? <span className="text-xs leading-5 text-muted-foreground">{objeto.resumo}</span> : null}
    >
      {ligados.map((r, i) => {
        const outro = indices.objetos.get(r.id)!;
        return caminho.has(r.id) ? (
          <li key={`${r.id}-${i}`} className="py-1 text-sm text-muted-foreground" style={{ paddingLeft: `${(nivel + 1) * 1.25 + 1.5}rem` }}>
            <span className="italic">{r.rotulo}</span> {outro.nome} <span className="text-xs">(já aberto acima)</span>
          </li>
        ) : (
          <NoObjeto
            key={`${r.id}-${i}`}
            objeto={outro}
            nivel={nivel + 1}
            acima={caminho}
            indices={indices}
            aoAbrirFicha={aoAbrirFicha}
            relacao={r.rotulo}
          />
        );
      })}
    </No>
  );
}

function No({
  nivel,
  titulo,
  sufixo,
  folha = false,
  children,
}: {
  nivel: number;
  titulo: React.ReactNode;
  sufixo?: React.ReactNode;
  folha?: boolean;
  children?: React.ReactNode;
}) {
  const [aberto, setAberto] = useState(false);
  return (
    <li>
      <div
        className="flex gap-2 rounded-md py-1.5 pr-2 hover:bg-muted/40"
        style={{ paddingLeft: `${nivel * 1.25}rem` }}
      >
        {folha ? (
          <span className="mt-0.5 h-4 w-4 shrink-0" />
        ) : (
          <button
            type="button"
            aria-expanded={aberto}
            aria-label={aberto ? 'Recolher' : 'Expandir'}
            className="mt-0.5 h-4 w-4 shrink-0"
            onClick={() => setAberto((v) => !v)}
          >
            {aberto ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
          </button>
        )}
        <div className="min-w-0 space-y-0.5">
          <div>{titulo}</div>
          {sufixo ? <div>{sufixo}</div> : null}
        </div>
      </div>
      {aberto && !folha ? <ul>{children}</ul> : null}
    </li>
  );
}
