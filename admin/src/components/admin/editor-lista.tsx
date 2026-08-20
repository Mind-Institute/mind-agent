import { useState, type KeyboardEvent } from 'react';
import { Plus, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';

/**
 * Editor de lista de textos — aliases de espaço, resultados esperados
 * de sessão. Enter adiciona; o X remove.
 */
export function EditorDeLista({
  valor,
  aoMudar,
  placeholder = 'Digite e pressione Enter',
  rotuloAdicionar = 'Adicionar',
  vazio = 'Nenhum item.',
  id,
  'aria-invalid': invalido,
  'aria-describedby': descrito,
}: {
  valor: string[];
  aoMudar: (proximo: string[]) => void;
  placeholder?: string;
  rotuloAdicionar?: string;
  vazio?: string;
  id?: string;
  'aria-invalid'?: boolean;
  'aria-describedby'?: string;
}) {
  const [rascunho, setRascunho] = useState('');

  function adicionar() {
    const texto = rascunho.trim();
    if (!texto) return;
    if (valor.some((v) => v.toLowerCase() === texto.toLowerCase())) {
      setRascunho('');
      return;
    }
    aoMudar([...valor, texto]);
    setRascunho('');
  }

  function aoTeclar(evento: KeyboardEvent<HTMLInputElement>) {
    if (evento.key === 'Enter') {
      evento.preventDefault();
      adicionar();
    }
  }

  return (
    <div className="space-y-2">
      <div className="flex gap-2">
        <Input
          id={id}
          value={rascunho}
          onChange={(e) => setRascunho(e.target.value)}
          onKeyDown={aoTeclar}
          placeholder={placeholder}
          aria-invalid={invalido}
          aria-describedby={descrito}
        />
        <Button type="button" variant="outline" onClick={adicionar} aria-label={rotuloAdicionar}>
          <Plus />
        </Button>
      </div>
      {valor.length === 0 ? (
        <p className="text-xs text-muted-foreground">{vazio}</p>
      ) : (
        <ul className="flex flex-wrap gap-1.5">
          {valor.map((item) => (
            <li key={item}>
              <Badge variant="secondary" className="gap-1 py-1 pl-2.5 pr-1">
                {item}
                <button
                  type="button"
                  className="rounded-full p-0.5 hover:bg-coral-100 hover:text-coral-700"
                  onClick={() => aoMudar(valor.filter((v) => v !== item))}
                  aria-label={`Remover ${item}`}
                >
                  <X className="size-3" />
                </button>
              </Badge>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

/** Grupo de caixas de seleção — temas, trilhas, agentes. */
export function SelecaoMultipla<T extends string>({
  opcoes,
  valor,
  aoMudar,
  id,
  colunas = 2,
}: {
  opcoes: { valor: T; rotulo: string }[];
  valor: T[];
  aoMudar: (proximo: T[]) => void;
  id?: string;
  colunas?: number;
}) {
  function alternar(opcao: T) {
    aoMudar(valor.includes(opcao) ? valor.filter((v) => v !== opcao) : [...valor, opcao]);
  }

  return (
    <div
      id={id}
      role="group"
      className="grid gap-1.5"
      style={{ gridTemplateColumns: `repeat(${colunas}, minmax(0, 1fr))` }}
    >
      {opcoes.map((opcao) => (
        <label
          key={opcao.valor}
          className="flex cursor-pointer items-center gap-2 rounded-md border bg-card px-2.5 py-1.5 text-sm hover:bg-accent"
        >
          <input
            type="checkbox"
            className="size-4 accent-verde-600"
            checked={valor.includes(opcao.valor)}
            onChange={() => alternar(opcao.valor)}
          />
          <span className="truncate">{opcao.rotulo}</span>
        </label>
      ))}
    </div>
  );
}
