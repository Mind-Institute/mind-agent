/* ============================================================
   MASCARAMENTO DE DADOS PESSOAIS
   ============================================================
   Regra do painel: listagem nunca mostra e-mail ou telefone inteiro.
   O mascaramento acontece na exibição E os mocks já nascem sem dado
   real — as duas coisas, porque uma sozinha não é garantia.

   Isto é higiene de interface, não controle de acesso: quem decide
   o que sai do banco é o backend. */

/** `ana.souza@empresa.com.br` → `an•••@empresa.com.br`. */
export function mascararEmail(email: string | null | undefined): string {
  if (!email) return '—';
  const arroba = email.lastIndexOf('@');
  if (arroba < 1) return '•••';
  const usuario = email.slice(0, arroba);
  const dominio = email.slice(arroba + 1);
  const visivel = usuario.slice(0, Math.min(2, usuario.length));
  return `${visivel}${'•'.repeat(3)}@${dominio}`;
}

/** `+55 11 98888-7777` → `+55 11 ••••-7777`. */
export function mascararTelefone(telefone: string | null | undefined): string {
  if (!telefone) return '—';
  const digitos = telefone.replace(/\D/g, '');
  if (digitos.length < 4) return '••••';
  const fim = digitos.slice(-4);
  const prefixo = telefone.trim().startsWith('+') ? `+${digitos.slice(0, 2)} ` : '';
  return `${prefixo}••••-${fim}`;
}

/** `Ana Paula Souza` → `Ana P. S.`. Mantém a pessoa reconhecível sem expor. */
export function mascararNome(nome: string | null | undefined): string {
  if (!nome) return '—';
  const partes = nome.trim().split(/\s+/);
  if (partes.length === 1) return partes[0];
  const [primeiro, ...resto] = partes;
  return [primeiro, ...resto.map((p) => `${p.charAt(0).toUpperCase()}.`)].join(' ');
}

/** Documento/identificador genérico: mantém só os 4 últimos. */
export function mascararIdentificador(valor: string | null | undefined): string {
  if (!valor) return '—';
  if (valor.length <= 4) return '•'.repeat(valor.length);
  return `${'•'.repeat(Math.min(6, valor.length - 4))}${valor.slice(-4)}`;
}

const RE_EMAIL = /[\w.+-]+@[\w-]+\.[\w.-]+/g;
const RE_TELEFONE = /(?:\+?\d{2}\s?)?\(?\d{2}\)?[\s.-]?\d{4,5}[\s.-]?\d{4}/g;

/**
 * Varre texto livre (mensagem de conversa, pergunta sem resposta) e
 * mascara e-mails e telefones encontrados. Rede de segurança para
 * conteúdo que não passou por campo tipado.
 */
export function mascararTextoLivre(texto: string | null | undefined): string {
  if (!texto) return '';
  return texto
    .replace(RE_EMAIL, (m) => mascararEmail(m))
    .replace(RE_TELEFONE, (m) => mascararTelefone(m));
}

