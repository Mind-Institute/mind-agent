import type { Evento } from './event';
import type { Sessao } from './session';
import type { Palestrante } from './speaker';
import type { Espaco } from './space';
import type { Rota } from './route';
import type { Estande } from './booth';
import type { Oferta } from './offer';
import type { Conteudo } from './content';
import type { Documento, Fonte } from './document';
import type { Conversa } from './conversation';
import type { PerguntaSemResposta } from './unanswered';
import type { Usuario } from './user';
import type { RegistroAuditoria } from './audit';
import type { Tema } from './theme';

/**
 * O nome do recurso é o mesmo na URL da futura Edge Function
 * (`GET /admin/sessions`) e na chave do TanStack Query. Um nome só,
 * escrito em um lugar só.
 */
export interface MapaRecursos {
  event: Evento;
  sessions: Sessao;
  speakers: Palestrante;
  spaces: Espaco;
  routes: Rota;
  booths: Estande;
  offers: Oferta;
  content: Conteudo;
  documents: Documento;
  sources: Fonte;
  conversations: Conversa;
  unanswered: PerguntaSemResposta;
  users: Usuario;
  audit: RegistroAuditoria;
  themes: Tema;
}

export type NomeRecurso = keyof MapaRecursos;

export const NOMES_RECURSOS: NomeRecurso[] = [
  'event',
  'sessions',
  'speakers',
  'spaces',
  'routes',
  'booths',
  'offers',
  'content',
  'documents',
  'sources',
  'conversations',
  'unanswered',
  'users',
  'audit',
  'themes',
];

export const ROTULO_RECURSO: Record<NomeRecurso, string> = {
  event: 'Evento',
  sessions: 'Sessão',
  speakers: 'Palestrante',
  spaces: 'Espaço',
  routes: 'Rota',
  booths: 'Estande',
  offers: 'Oferta',
  content: 'Conteúdo',
  documents: 'Documento',
  sources: 'Fonte',
  conversations: 'Conversa',
  unanswered: 'Pergunta sem resposta',
  users: 'Usuário',
  audit: 'Auditoria',
  themes: 'Tema',
};

/** Recursos que passam pelo fluxo editorial (rascunho → publicado). */
export const RECURSOS_EDITORIAIS: NomeRecurso[] = ['sessions', 'speakers', 'content'];

/** Recursos somente leitura no painel. */
export const RECURSOS_SOMENTE_LEITURA: NomeRecurso[] = [
  'conversations',
  'audit',
  'themes',
];
