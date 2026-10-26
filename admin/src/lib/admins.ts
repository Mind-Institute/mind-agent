import {
  PAPEIS,
  ROTULO_PAPEL,
  type AdminSistema,
  type AdminSistemaForm,
} from '@/contracts';
import type { OpcaoCategoria, Rotulo } from './rotulos';

/* ============================================================
   ADMINS DO SISTEMA — regras que a tela usa
   ============================================================
   Moram aqui, e não na página, para serem testadas sozinhas. */

export const OPCOES_PAPEL: OpcaoCategoria[] = PAPEIS.map((papel) => ({
  valor: papel,
  rotulo: ROTULO_PAPEL[papel],
}));

/** Papel que o painel não conhece aparece com o próprio código (ver `rotulos.ts`). */
export function rotuloDoPapel(papel: string): Rotulo {
  const conhecido = Object.prototype.hasOwnProperty.call(ROTULO_PAPEL, papel);
  return conhecido
    ? { texto: ROTULO_PAPEL[papel as keyof typeof ROTULO_PAPEL], conhecido: true }
    : { texto: papel, conhecido: false };
}

export function paraFormularioAdmin(admin: AdminSistema): AdminSistemaForm {
  return { papel: admin.papel, ativo: admin.ativo };
}

/**
 * O que vai para o banco ao salvar: só papel e situação, e só o que
 * mudou. Mandar o papel sem ter mexido nele faria uma troca de situação
 * esbarrar em regra de papel à toa.
 */
export function payloadDaEdicaoAdmin(
  valores: AdminSistemaForm,
  aberto: AdminSistema | undefined,
): Partial<AdminSistema> {
  const payload: Partial<AdminSistema> = {};
  if (!aberto || valores.papel !== aberto.papel) payload.papel = valores.papel;
  if (!aberto || valores.ativo !== aberto.ativo) payload.ativo = valores.ativo;
  return payload;
}
