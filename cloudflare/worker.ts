/* ============================================================
   WORKER — fallback de SPA para o painel
   ============================================================
   Um Worker, três produtos, separados por caminho e por HOST:

     /        → Mind Agent, o chat público (estático, sem rota de cliente)
     /admin/  → Painel Admin (SPA com BrowserRouter)
     avaliacao.mindsummit.com.br → só a pesquisa, e nada mais
     admin.minddash.pro          → só o painel; o endereço antigo leva para lá

   O Worker atende TODOS os caminhos (`run_worker_first` no
   `wrangler.jsonc`). Era só `/admin` antes; ampliou porque a decisão do
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
  INDICE_PAINEL, PAGINA_DA_PESQUISA,
  decidirAntes, decidirApos404, decidirNaPesquisa, decidirNoHostDoPainel,
  destinoDoPainelAntigo, ehDaPesquisa, ehDoHostDoPainel, ehDoPainel,
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
       O DOMÍNIO DA PESQUISA
       ============================================================
       Vem ANTES de tudo, inclusive do painel: em
       `avaliacao.mindsummit.com.br` não existe app do evento, agente nem
       /admin. O que não está na lista de permissão é 404 — e é lista de
       permissão justamente para o arquivo que alguém acrescentar amanhã
       não vazar sozinho para cá. */
    if (ehDaPesquisa(url.hostname)) {
      const decisao = decidirNaPesquisa(url.pathname);

      if (decisao.tipo === 'recusado') {
        return new Response('Não encontrado.', {
          status: 404,
          headers: { 'Content-Type': 'text/plain; charset=utf-8' },
        });
      }

      if (decisao.tipo === 'pesquisa') {
        /* A URL do navegador NÃO muda: a pessoa continua vendo o
           endereço que recebeu, e não um `/avaliacao.html` que ela não
           pediu. Por isso busca-se a página e devolve-se o conteúdo, em
           vez de redirecionar.

           E É PRECISO SEGUIR UM REDIRECIONAMENTO AQUI DENTRO. O pipeline
           de assets serve `avaliacao.html` em `/avaliacao` e responde
           307 para o caminho com extensão (`html_handling`). Repassar
           esse 307 mandava o navegador para `/avaliacao`, que voltava
           por este mesmo caminho e recebia outro 307 — laço, e a página
           nunca aparecia. Foi o que aconteceu no primeiro deploy. */
        const pagina = new URL(PAGINA_DA_PESQUISA, url.origin);
        let resposta = await env.ASSETS.fetch(new Request(pagina, request));

        const destino = resposta.headers.get('Location');
        if (resposta.status >= 300 && resposta.status < 400 && destino) {
          /* Uma vez só, e sempre na nossa origem: seguir cegamente o que
             vier no cabeçalho seria deixar o destino ser escolhido por
             outro. */
          const seguinte = new URL(destino, url.origin);
          seguinte.protocol = url.protocol;
          seguinte.host = url.host;
          resposta = await env.ASSETS.fetch(new Request(seguinte, request));
        }

        return new Response(resposta.body, {
          status: resposta.status,
          headers: resposta.headers,
        });
      }

      return env.ASSETS.fetch(request);
    }

    /* ============================================================
       O DOMÍNIO DO PAINEL
       ============================================================
       Em `admin.minddash.pro` só existe o painel: a raiz e qualquer
       navegação fora de `/admin` levam para `/admin/`, e arquivo que não
       é do painel é 404. O que é do painel segue o fluxo de sempre, logo
       abaixo. No endereço antigo do worker, o painel manda para cá; o chat
       fica onde está. Redirecionamento temporário (302) enquanto o domínio
       novo se firma — trocar para 301 é uma linha. */
    if (ehDoHostDoPainel(url.hostname)) {
      const decisao = decidirNoHostDoPainel(url.pathname);
      if (decisao.tipo === 'recusado') {
        return new Response('Não encontrado.', {
          status: 404,
          headers: { 'Content-Type': 'text/plain; charset=utf-8' },
        });
      }
      if (decisao.tipo === 'redirecionar') {
        url.pathname = decisao.para;
        return Response.redirect(url.toString(), 302);
      }
    } else {
      const destino = destinoDoPainelAntigo(url.hostname, url.pathname);
      if (destino) {
        const alvo = new URL(destino);
        alvo.search = url.search;
        return Response.redirect(alvo.toString(), 302);
      }
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
       chamava o Worker em `/admin`; para o domínio da pesquisa existir,
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
