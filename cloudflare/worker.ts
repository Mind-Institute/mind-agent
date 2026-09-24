/* ============================================================
   WORKER — fallback de SPA para o painel
   ============================================================
   Um Worker, três produtos, separados por caminho e por HOST:

     /        → Mind Agent, o chat público (estático, sem rota de cliente)
     /admin/  → Painel Admin (SPA com BrowserRouter)
     avaliacao.mindsummit.com.br → 404 em tudo (a pesquisa avulsa foi apagada)

   O Worker atende TODOS os caminhos (`run_worker_first` no
   `wrangler.jsonc`). Era só `/admin` antes; ampliou porque a trava do
   domínio da pesquisa depende de olhar o Host, e o pipeline de assets
   não olha.

   Isso trouxe uma garantia para dentro do código: o fallback de SPA
   continua valendo SÓ para o painel. O chat não tem rota de cliente, e
   o 404 dele deve continuar 404 em vez de virar a home — antes quem
   garantia isso era o recorte da configuração, agora é o
   `ehDoPainel` aqui embaixo.

   As regras de decisão moram em `roteamento.js`, importado também pelo
   simulador local. Uma cópia só, para o que se valida ser o que sobe.

   Nenhum segredo aqui. As chaves de verdade (`service_role`,
   `OPENAI_API_KEY`) ficam nas Edge Functions do Supabase. */

import {
  INDICE_PAINEL,
  decidirAntes, decidirApos404, ehDaPesquisa, ehDoPainel,
} from './roteamento.js';

export interface Env {
  /** Binding declarado em `wrangler.jsonc` → `assets.binding`. */
  ASSETS: { fetch(request: Request): Promise<Response> };
  CHECKOUT_REDIRECT_ORIGIN?: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    /* ============================================================
       O DOMÍNIO DA PESQUISA, DESLIGADO
       ============================================================
       Vem ANTES de tudo, inclusive do painel: a pesquisa avulsa foi
       apagada, e enquanto `avaliacao.mindsummit.com.br` apontar para cá
       nada pode ser servido nele — nem a home, nem /admin/. */
    if (ehDaPesquisa(url.hostname)) {
      return new Response('Não encontrado.', {
        status: 404,
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      });
    }

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

    /* O FALLBACK DE SPA É SÓ DO PAINEL, e agora isso precisa estar
       ESCRITO. Antes quem garantia era o `run_worker_first`, que só
       chamava o Worker em `/admin`; para o domínio da pesquisa ser travado,
       o Worker passou a ser a porta de tudo — e sem esta linha
       `/qualquer-coisa` no chat passaria a devolver o painel em vez de
       404, que é exatamente o que o comentário do wrangler prometia
       que não aconteceria. */
    if (!ehDoPainel(url.pathname)) return resposta;

    const depois = decidirApos404(request.method, url.pathname);
    if (depois.tipo !== 'indice') return resposta;

    /* Navegação do painel: devolve o index dele com 200. A URL do
       navegador não muda, então a SPA continua vendo o caminho e a
       query originais. */
    const indice = new URL(INDICE_PAINEL, url.origin);
    return env.ASSETS.fetch(new Request(indice.toString(), { headers: request.headers }));
  },
};
