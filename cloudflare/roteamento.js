/* ============================================================
   REGRAS DE ROTEAMENTO DO PAINEL
   ============================================================
   Decisão pura: recebe método e caminho, devolve o que fazer. Nenhuma
   API do Cloudflare aqui.

   Isso existe separado do Worker por um motivo prático: o simulador
   local (`scripts/servir-cloudflare.mjs`) importa ESTE arquivo. Se as
   regras estivessem dentro do Worker, o simulador teria uma segunda
   cópia — e a cópia que se valida não seria a que sobe.

   O painel é SPA com BrowserRouter: `/admin/programacao` não existe como
   arquivo, quem resolve a rota é o JavaScript. Então navegação que dá
   404 no disco precisa receber o `index.html` do painel.

   O que NÃO pode acontecer é isso valer para arquivo. Um `.js` ou `.css`
   ausente devolvendo HTML faz o navegador tentar executar `<!doctype` e
   o erro que aparece no console não tem relação com a causa. Arquivo que
   não existe é 404, sempre. */

export const PREFIXO_PAINEL = '/admin';
export const DIRETORIO_ASSETS = '/admin/assets/';
export const INDICE_PAINEL = '/admin/index.html';

/**
 * O caminho pede um ARQUIVO (e não navegação)?
 *
 * Dois sinais, e basta um:
 * - está sob `/admin/assets/`, onde só existe artefato de build;
 * - o último segmento tem ponto, como `main-a1b2c3.js` ou `favicon.svg`.
 *
 * `/admin/programacao` não tem ponto nem está em assets — é navegação.
 *
 * @param {string} pathname
 * @returns {boolean}
 */
export function pedeArquivo(pathname) {
  if (pathname.startsWith(DIRETORIO_ASSETS)) return true;
  const ultimoSegmento = pathname.slice(pathname.lastIndexOf('/') + 1);
  return ultimoSegmento.includes('.');
}

/**
 * O Worker só é chamado para `/admin` e `/admin/*` (`run_worker_first`
 * no wrangler.jsonc). Esta função existe para o simulador local aplicar
 * o mesmo recorte.
 *
 * @param {string} pathname
 * @returns {boolean}
 */
export function ehDoPainel(pathname) {
  return pathname === PREFIXO_PAINEL || pathname.startsWith(PREFIXO_PAINEL + '/');
}

/**
 * @typedef {{ tipo: 'redirecionar', para: string }
 *         | { tipo: 'asset' }
 *         | { tipo: 'indice' }} Decisao
 */

/**
 * Decide ANTES de tocar no disco.
 *
 * @param {string} metodo
 * @param {string} pathname
 * @returns {Decisao}
 */
export function decidirAntes(metodo, pathname) {
  /* `/admin` sem barra: sem o redirecionamento, caminho relativo do
     painel resolveria contra a raiz do chat. A query é preservada por
     quem chama, que só troca o pathname. */
  if (pathname === PREFIXO_PAINEL) {
    return { tipo: 'redirecionar', para: PREFIXO_PAINEL + '/' };
  }
  void metodo;
  return { tipo: 'asset' };
}

/**
 * Decide DEPOIS de o asset ter dado 404.
 *
 * @param {string} metodo
 * @param {string} pathname
 * @returns {Decisao}
 */
export function decidirApos404(metodo, pathname) {
  const verbo = metodo.toUpperCase();
  /* POST/PUT em caminho inexistente não é navegação. */
  if (verbo !== 'GET' && verbo !== 'HEAD') return { tipo: 'asset' };
  if (pedeArquivo(pathname)) return { tipo: 'asset' };
  return { tipo: 'indice' };
}
