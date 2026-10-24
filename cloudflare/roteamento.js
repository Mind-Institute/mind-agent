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

/* ============================================================
   O DOMÍNIO DA PESQUISA, DESLIGADO
   ============================================================
   `avaliacao.mindsummit.com.br` servia uma pesquisa avulsa, que a
   Adriana mandou apagar (24/09/2026). O domínio ainda pode estar
   apontado para ESTE Worker na Cloudflare; enquanto estiver, tudo nele
   é 404. Sem esta trava, a raiz daquele domínio entregaria o app
   inteiro, inclusive /admin/. Quando o domínio sair da Cloudflare,
   esta trava pode sair junto. */
export const HOST_DA_PESQUISA = 'avaliacao.mindsummit.com.br';

/**
 * O pedido chegou pelo domínio da pesquisa, que não serve mais nada?
 *
 * @param {string | null | undefined} hostname
 * @returns {boolean}
 */
export function ehDaPesquisa(hostname) {
  return String(hostname || '').toLowerCase() === HOST_DA_PESQUISA;
}

/**
/* ============================================================
   O DOMÍNIO DO PAINEL
   ============================================================
   Pedido da Adriana (26/09/2026): o painel abre em `admin.minddash.pro`, e
   app e painel são duas coisas em dois endereços. Ali só existe o painel.
   A raiz, e qualquer navegação fora de `/admin`, levam para `/admin/`;
   arquivo que não é do painel (o chat público, a pesquisa) é 404.

   E o contrário vale em QUALQUER outro endereço deste worker — o
   `workers.dev`, o domínio do app, o domínio que alguém ligar amanhã pelo
   painel da Cloudflare: `/admin` leva para `admin.minddash.pro`. Lista de
   permissão pelo mesmo motivo da pesquisa: domínio novo não traz o painel
   junto sem ninguém perceber. Assim o app nunca roda na mesma origem do
   painel, e o navegador guarda a sessão de cada um separada.

   Exceção, só para teste: os previews de cada versão
   (`<rótulo>-mind-agent.adriana-3eb.workers.dev`) e a máquina local
   continuam servindo o painel no próprio endereço. Sem as variáveis de
   build do Supabase, ali ele abre em demonstração. */
export const HOST_DO_PAINEL = 'admin.minddash.pro';
export const HOST_DO_WORKER = 'mind-agent.adriana-3eb.workers.dev';

const SUFIXO_DOS_PREVIEWS = '-' + HOST_DO_WORKER;
const HOSTS_LOCAIS = ['localhost', '127.0.0.1'];

/**
 * O pedido chegou pelo domínio do painel?
 *
 * @param {string | null | undefined} hostname
 * @returns {boolean}
 */
export function ehDoHostDoPainel(hostname) {
  return String(hostname || '').toLowerCase() === HOST_DO_PAINEL;
}

/**
 * Decide o que o domínio do painel entrega.
 *
 * @param {string} pathname
 * @returns {{ tipo: 'painel' } | { tipo: 'redirecionar', para: string } | { tipo: 'recusado' }}
 */
export function decidirNoHostDoPainel(pathname) {
  if (ehDoPainel(pathname)) return { tipo: 'painel' };
  if (pedeArquivo(pathname)) return { tipo: 'recusado' };
  return { tipo: 'redirecionar', para: PREFIXO_PAINEL + '/' };
}

/**
 * Endereço de teste: o preview de uma versão do worker, ou a máquina local.
 *
 * @param {string | null | undefined} hostname
 * @returns {boolean}
 */
export function ehEnderecoDeTeste(hostname) {
  const host = String(hostname || '').toLowerCase();
  if (HOSTS_LOCAIS.includes(host)) return true;
  return host.endsWith(SUFIXO_DOS_PREVIEWS) && host.length > SUFIXO_DOS_PREVIEWS.length;
}

/**
 * Painel pedido fora do domínio dele → o mesmo caminho em
 * `admin.minddash.pro`. `null` quando não há o que desviar: o pedido não é
 * do painel (o app continua onde está), já é o domínio do painel, ou é
 * endereço de teste.
 *
 * @param {string | null | undefined} hostname
 * @param {string} pathname
 * @returns {string | null}
 */
export function destinoDoPainelForaDoDominio(hostname, pathname) {
  if (!ehDoPainel(pathname)) return null;
  if (ehDoHostDoPainel(hostname) || ehEnderecoDeTeste(hostname)) return null;
  return `https://${HOST_DO_PAINEL}${pathname}`;
}

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
