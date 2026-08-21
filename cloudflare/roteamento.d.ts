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

export declare function pedeArquivo(pathname: string): boolean;
export declare function ehDoPainel(pathname: string): boolean;
export declare function decidirAntes(metodo: string, pathname: string): Decisao;
export declare function decidirApos404(metodo: string, pathname: string): Decisao;
