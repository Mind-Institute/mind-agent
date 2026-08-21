/* ============================================================
   PERMISSÕES — DA INTERFACE, NÃO DO SISTEMA
   ============================================================
   Este arquivo decide o que a tela MOSTRA. Ele esconde botão, marca
   página como "sem permissão" e evita que alguém tente uma ação que
   vai ser recusada. Isso é usabilidade, não segurança: quem abre o
   console muda o papel em memória e vê a interface inteira.

   A AUTORIZAÇÃO DE VERDADE JÁ EXISTE, e é do backend, em duas camadas:

   1. a Edge Function administrativa valida o JWT do Supabase Auth, lê o
      papel em `mind_admin_users` e confere se aquele papel pode fazer
      aquela ação;
   2. a função SQL `mind_admin_mutate_resource` valida o papel outra vez
      antes de escrever. `anon` e `authenticated` não executam a RPC
      direto.

   Conferido em transação: papel `analista` tentando atualizar foi
   recusado. O papel nunca sai de `user_metadata`, que o próprio usuário
   edita.

   Ou seja: divergência entre esta matriz e o backend produz uma recusa
   visível (403), não um vazamento. O frontend nunca é a última palavra —
   e agora existe uma última palavra. */

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
