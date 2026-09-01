/* ============================================================
   BANCO EM MEMÓRIA
   ============================================================
   Um objeto por recurso, com o mesmo nome que a Edge Function vai usar
   na URL (`sessions`, `spaces`, `offers`…). O `MockAdminDataProvider`
   lê e escreve aqui; ao recarregar a página tudo volta ao estado
   inicial — nada é persistido, e o painel diz isso na tela.

   `criarBanco()` devolve uma instância NOVA a cada chamada: cada teste
   trabalha no seu próprio banco, sem herdar a escrita do anterior. */

import type { MapaRecursos, NomeRecurso } from '@/contracts';
import { eventoSemente } from './seed/event';
import {
  conteudosSemente,
  documentosSemente,
  estandesSemente,
  fontesSemente,
  ofertasSemente,
  rotasSemente,
  sessoesDemonstracao,
  usuariosSemente,
} from './seed/operacao';
import { auditoriaSemente, conversasSemente, perguntasSemente } from './seed/atendimento';
import { espacosSemente, palestrantesSemente, sessoesSemente, temasSemente } from './seed/summit';
import { avisosHomeSemente, estadoHomeSemente, trocasHomeSemente } from './seed/home-v3';

export type BancoMock = {
  [K in NomeRecurso]: MapaRecursos[K][];
};

/** Cópia profunda simples — o suficiente para dados JSON puros. */
function clonar<T>(valor: T): T {
  return JSON.parse(JSON.stringify(valor)) as T;
}

export function criarBanco(agora: number = Date.now()): BancoMock {
  return {
    event: clonar([eventoSemente]),
    /* A grade importada mais a sessão de demonstração que existe só
       para a detecção de conflito ter o que mostrar. */
    sessions: clonar([...sessoesSemente, ...sessoesDemonstracao]),
    speakers: clonar(palestrantesSemente),
    spaces: clonar(espacosSemente),
    routes: clonar(rotasSemente),
    booths: clonar(estandesSemente),
    offers: clonar(ofertasSemente),
    content: clonar(conteudosSemente),
    documents: clonar(documentosSemente),
    sources: clonar(fontesSemente),
    conversations: conversasSemente(agora),
    unanswered: perguntasSemente(agora),
    users: clonar(usuariosSemente),
    audit: auditoriaSemente(agora),
    themes: clonar(temasSemente),
    /* Home V3: um estado só, as trocas programadas e os avisos. */
    home_state: clonar([estadoHomeSemente]),
    home_schedule: clonar(trocasHomeSemente),
    home_notices: clonar(avisosHomeSemente),
  };
}

/** Rótulo curto de um registro, para auditoria e listas de pendência. */
export function rotuloDoRegistro(recurso: NomeRecurso, registro: Record<string, unknown>): string {
  const candidatos = ['titulo', 'nome', 'pergunta', 'codigo', 'slug', 'id'];
  for (const chave of candidatos) {
    const valor = registro[chave];
    if (typeof valor === 'string' && valor.trim()) return valor;
  }
  return recurso;
}
