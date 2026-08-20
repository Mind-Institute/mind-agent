import '@testing-library/jest-dom/vitest';

/* ============================================================
   AJUSTES DO JSDOM
   ============================================================
   O jsdom não implementa a API de ponteiro nem ResizeObserver, e os
   componentes do Radix contam com as duas. Sem estes remendos, abrir
   um Select ou um Sheet estoura no teste — por limitação do ambiente,
   não por defeito do painel. */

if (!Element.prototype.hasPointerCapture) {
  Element.prototype.hasPointerCapture = () => false;
}
if (!Element.prototype.setPointerCapture) {
  Element.prototype.setPointerCapture = () => undefined;
}
if (!Element.prototype.releasePointerCapture) {
  Element.prototype.releasePointerCapture = () => undefined;
}
if (!Element.prototype.scrollIntoView) {
  Element.prototype.scrollIntoView = () => undefined;
}

if (!globalThis.ResizeObserver) {
  globalThis.ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
  } as unknown as typeof ResizeObserver;
}

/* O `Request` do Node (undici) recusa o `AbortSignal` do jsdom: são
   realms diferentes, e a checagem de marca falha. O React Router monta
   um `Request` a cada navegação de data router — o que derruba
   qualquer teste que troque de página.

   Nenhum teste depende do `Request` real (em modo mock não há rede, e
   o teste do HttpAdminDataProvider injeta o próprio `fetch`), então um
   substituto mínimo resolve. É remendo de ambiente, como o
   ResizeObserver acima — não contorna nada do painel. */
class RequestDeTeste {
  readonly url: string;
  readonly method: string;
  readonly signal: unknown;
  readonly headers: Headers;

  constructor(
    entrada: unknown,
    init: { method?: string; signal?: unknown; headers?: HeadersInit } = {},
  ) {
    this.url = String(entrada);
    this.method = init.method ?? 'GET';
    this.signal = init.signal;
    this.headers = new Headers(init.headers);
  }
}
globalThis.Request = RequestDeTeste as unknown as typeof Request;

if (!window.matchMedia) {
  window.matchMedia = ((consulta: string) => ({
    matches: false,
    media: consulta,
    onchange: null,
    addListener: () => undefined,
    removeListener: () => undefined,
    addEventListener: () => undefined,
    removeEventListener: () => undefined,
    dispatchEvent: () => false,
  })) as unknown as typeof window.matchMedia;
}
