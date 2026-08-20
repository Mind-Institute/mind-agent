import { z } from 'zod';
import { papelSchema, type Papel } from './user';

/* ============================================================
   AUTENTICAÇÃO
   ============================================================
   Duas coisas separadas, de propósito:

   - a SESSÃO diz *quem* está logado. Vem do Supabase Auth.
   - o PERFIL diz *o que essa pessoa pode fazer*. Vem exclusivamente
     de `GET /admin/me`, validado contra o JWT no backend.

   O painel nunca lê papel de `user_metadata`: aquilo é editável pelo
   próprio usuário e não serve para autorizar nada. */

/** O mínimo que o painel precisa de uma sessão do Supabase. */
export interface SessaoAuth {
  accessToken: string;
  usuarioId: string;
  email: string | null;
  /** Epoch em segundos. `null` quando o provedor não informa. */
  expiraEm: number | null;
}

/**
 * Resposta de `GET /admin/me`.
 *
 * `permissoes` é opcional porque o backend pode devolver só o papel.
 * Quando ela vem, é ela que manda — a matriz local de
 * `src/lib/permissions.ts` só entra como leitura padrão do papel que o
 * servidor informou, e continua sendo decisão de interface.
 */
export const perfilAdminSchema = z.object({
  id: z.string().optional(),
  email: z.string().nullable().optional(),
  nome: z.string().nullable().optional(),
  papel: papelSchema,
  permissoes: z.array(z.string()).optional(),
});

export type PerfilAdminBruto = z.infer<typeof perfilAdminSchema>;

export interface PerfilAdmin {
  id: string | null;
  email: string | null;
  nome: string;
  papel: Papel;
  /** `null` = o backend não enviou lista; a interface usa a do papel. */
  permissoes: string[] | null;
}

/* ============================================================
   ESTADOS DA SESSÃO
   ============================================================
   Cada um tem uma tela. Nenhum deles é "meia tela": ou o painel sabe
   quem você é e o que você pode, ou ele diz o que está faltando. */
export type EstadoSessao =
  /** Restaurando a sessão guardada — antes de decidir qualquer coisa. */
  | 'carregando'
  /** Sem sessão: mostra a tela de login. */
  | 'anonimo'
  /** Tem sessão, buscando papel e permissões em /admin/me. */
  | 'carregando_perfil'
  /** Sessão e perfil resolvidos: o painel abre. */
  | 'autenticado'
  /** Autenticado no Supabase, mas /admin/me recusou ou não respondeu. */
  | 'erro_perfil';
