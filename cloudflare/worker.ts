/* ============================================================
   WORKER — fallback de SPA para o painel
   ============================================================
   Um site, dois produtos:

     /        → Mind Agent, o chat público (estático, sem rota de cliente)
     /admin/  → Painel Admin (SPA com BrowserRouter)

   O `wrangler.jsonc` limita este Worker a `/admin` e `/admin/*` por
   `run_worker_first`. Todo o resto — o chat — é servido direto pelo
   pipeline de assets, sem passar por aqui. É de propósito: o chat não
   tem rota de cliente, e o 404 dele deve continuar 404.

   As regras de decisão moram em `roteamento.js`, importado também pelo
   simulador local. Uma cópia só, para o que se valida ser o que sobe.

   Nenhum segredo aqui. As chaves de verdade (`service_role`,
   `OPENAI_API_KEY`) ficam nas Edge Functions do Supabase. */

import { INDICE_PAINEL, decidirAntes, decidirApos404 } from './roteamento.js';

export interface Env {
  /** Binding declarado em `wrangler.jsonc` → `assets.binding`. */
  ASSETS: { fetch(request: Request): Promise<Response> };
  CHECKOUT_REDIRECT_ORIGIN?: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'GET' && /^\/c\/[0-9a-f-]{36}$/i.test(url.pathname)) {
      const eventId = url.pathname.slice(3);
      const origin = (env.CHECKOUT_REDIRECT_ORIGIN ||
        'https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/mindagent-checkout').replace(/\/+$/, '');
      return Response.redirect(origin + '/' + eventId, 307);
    }

    const antes = decidirAntes(request.method, url.pathname);
    if (antes.tipo === 'redirecionar') {
      /* Só o caminho muda: `?tutorial=agenda` e afins sobrevivem. */
      url.pathname = antes.para;
      return Response.redirect(url.toString(), 301);
    }

    const resposta = await env.ASSETS.fetch(request);
    if (resposta.status !== 404) return resposta;

    const depois = decidirApos404(request.method, url.pathname);
    if (depois.tipo !== 'indice') return resposta;

    /* Navegação do painel: devolve o index dele com 200. A URL do
       navegador não muda, então a SPA continua vendo o caminho e a
       query originais. */
    const indice = new URL(INDICE_PAINEL, url.origin);
    return env.ASSETS.fetch(new Request(indice.toString(), { headers: request.headers }));
  },
};
