/* ============================================================
   PERMISSÕES — DA INTERFACE, NÃO DO SISTEMA
   ============================================================
   ⚠️  LEIA ANTES DE USAR ISTO COMO SEGURANÇA.

   Este arquivo decide o que a tela MOSTRA. Ele esconde botão, marca
   página como "sem permissão" e evita que alguém tente uma ação que
   vai ser recusada. Isso é usabilidade.

   Não é controle de acesso. Qualquer pessoa com o console aberto muda
   o papel em memória e vê tudo — porque o dado já está no navegador.

   A autorização de verdade acontece na Edge Function administrativa:
   ela valida o JWT do Supabase Auth, lê o papel de uma TABELA do banco
   (nunca de `user_metadata`, que o próprio usuário edita) e recusa a
   requisição. O frontend nunca é a última palavra.

   Enquanto a Edge Function não existe, o seletor de papel do topo é um
   simulador de interface — e a tela diz isso. */

import type { Papel } from '@/contracts';

export type Acao =
  | 'ver'
  | 'editar'
  | 'criar'
  | 'publicar'
  | 'arquivar'
  | 'reindexar'
  | 'gerir_usuarios'
  | 'ver_auditoria'
  | 'ver_conversas'
  | 'configurar';

const MATRIZ: Record<Papel, Acao[]> = {
  administrador: [
    'ver',
    'editar',
    'criar',
    'publicar',
    'arquivar',
    'reindexar',
    'gerir_usuarios',
    'ver_auditoria',
    'ver_conversas',
    'configurar',
  ],
  editor: ['ver', 'editar', 'criar', 'reindexar', 'ver_conversas'],
  aprovador: ['ver', 'editar', 'publicar', 'arquivar', 'ver_auditoria', 'ver_conversas'],
  atendimento: ['ver', 'ver_conversas'],
  analista: ['ver', 'ver_auditoria'],
};

export function pode(papel: Papel, acao: Acao): boolean {
  return MATRIZ[papel].includes(acao);
}

/** Explicação exibida na tela de "sem permissão". */
export function motivoDaRecusa(papel: Papel, acao: Acao): string {
  const nomes: Record<Acao, string> = {
    ver: 'visualizar este módulo',
    editar: 'editar registros',
    criar: 'criar registros',
    publicar: 'publicar conteúdo',
    arquivar: 'arquivar registros',
    reindexar: 'solicitar reindexação',
    gerir_usuarios: 'gerir usuários e permissões',
    ver_auditoria: 'consultar a auditoria',
    ver_conversas: 'ler conversas',
    configurar: 'alterar configurações',
  };
  return `O papel ${papel} não pode ${nomes[acao]}.`;
}
