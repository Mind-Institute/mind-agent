/* Tipos de `roteamento.js`.
   Existe porque as regras são consumidas por TypeScript em dois lugares:
   o `worker.ts` e a suíte do painel. */

export declare const PREFIXO_PAINEL: '/admin';
export declare const DIRETORIO_ASSETS: '/admin/assets/';
export declare const INDICE_PAINEL: '/admin/index.html';

export type Decisao =
  | { tipo: 'redirecionar'; para: string }
  | { tipo: 'asset' }
  | { tipo: 'indice' };

export declare const HOST_DO_PAINEL: 'admin.minddash.pro';
export declare const HOST_ANTIGO_DO_PAINEL: 'mind-agent.adriana-3eb.workers.dev';

export declare function ehDoHostDoPainel(hostname: string | null | undefined): boolean;
export declare function decidirNoHostDoPainel(
  pathname: string,
): { tipo: 'painel' } | { tipo: 'redirecionar'; para: string } | { tipo: 'recusado' };
export declare function destinoDoPainelAntigo(
  hostname: string | null | undefined,
  pathname: string,
): string | null;
export declare function pedeArquivo(pathname: string): boolean;
export declare function ehDoPainel(pathname: string): boolean;
export declare function decidirAntes(metodo: string, pathname: string): Decisao;
export declare function decidirApos404(metodo: string, pathname: string): Decisao;
