import type { Evento } from '@/contracts';
import { SUMMIT } from '@/mocks/seed/summit';

/* ============================================================
   DIVERGÊNCIA DE LOCAL
   ============================================================
   O local do evento é dito em mais de um lugar, e os lugares não
   concordam:

   - o CADASTRO OFICIAL, no campo `local` do evento;
   - as REGRAS LOGÍSTICAS, que às vezes nomeiam o pavilhão no meio do
     texto de reserva ou de vagas;
   - a CÓPIA CONGELADA em `dados/summit.json`, que o chat ainda usa
     como rede de segurança.

   O painel não escolhe entre elas. Ele junta, mostra com a origem de
   cada uma e pede confirmação — escolher seria inventar dado, que é
   exatamente o que o agente não pode fazer.

   Quando a API manda `locaisCandidatos`, essa lista tem precedência:
   ela é a versão do backend sobre a própria divergência. */

export interface CandidatoLocal {
  valor: string;
  origem: string;
}

/** Nomes de local que o projeto já usou, para achá-los em texto livre. */
const NOMES_CONHECIDOS = ['São Paulo Expo', 'Transamérica Expo Center'];

function normalizar(valor: string): string {
  return valor
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

/** `Pavilhão 3 · Transamérica Expo Center` e `Transamérica Expo Center`
 *  são a mesma afirmação — um contém o outro. */
function mesmoLocal(a: string, b: string): boolean {
  const na = normalizar(a);
  const nb = normalizar(b);
  return na === nb || na.includes(nb) || nb.includes(na);
}

function acrescentar(lista: CandidatoLocal[], candidato: CandidatoLocal) {
  if (!candidato.valor.trim()) return;
  const existente = lista.find((c) => mesmoLocal(c.valor, candidato.valor));
  if (existente) {
    /* Mesma afirmação por outra fonte: soma a origem em vez de repetir. */
    if (!existente.origem.includes(candidato.origem)) {
      existente.origem = `${existente.origem} · ${candidato.origem}`;
    }
    /* Fica com a descrição mais completa das duas. */
    if (candidato.valor.length > existente.valor.length) existente.valor = candidato.valor;
    return;
  }
  lista.push({ ...candidato });
}

export function divergenciasDeLocal(evento: Evento): CandidatoLocal[] {
  /* A lista do backend, quando existe, é a palavra final. */
  if (evento.locaisCandidatos.length > 0) return evento.locaisCandidatos;

  const candidatos: CandidatoLocal[] = [];

  acrescentar(candidatos, { valor: evento.local, origem: 'cadastro oficial do evento' });

  const textoLogistico = [evento.regraReserva, evento.regraVagas, evento.descricao].join(' \n ');
  for (const nome of NOMES_CONHECIDOS) {
    if (normalizar(textoLogistico).includes(normalizar(nome))) {
      acrescentar(candidatos, { valor: nome, origem: 'regras logísticas do evento' });
    }
  }

  const congelado = SUMMIT.evento?.local ?? '';
  acrescentar(candidatos, { valor: congelado, origem: 'dados/summit.json (cópia congelada)' });

  return candidatos.length > 1 ? candidatos : [];
}
