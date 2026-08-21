/* ============================================================
   SIMULADOR LOCAL DO WORKER
   ============================================================
   Serve `dist-cloudflare/` imitando o que o Cloudflare faz em produção:

   - o pipeline de assets responde os arquivos e resolve `/` e `/admin/`
     para o `index.html` do diretório;
   - o Worker só entra em `/admin` e `/admin/*` (`run_worker_first`);
   - as regras vêm de `cloudflare/roteamento.js`, o MESMO arquivo que o
     Worker importa. Sem segunda cópia, sem divergência entre o que se
     valida aqui e o que sobe.

   Não substitui `wrangler dev`, e não tenta: serve para conferir o
   contrato de rotas — deep link, asset ausente, `/admin` sem barra —
   sem depender de rede nem de login.

       node scripts/servir-cloudflare.mjs [porta]
*/

import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { dirname, extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import { decidirAntes, decidirApos404, ehDoPainel, INDICE_PAINEL } from '../cloudflare/roteamento.js';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
const SAIDA = join(RAIZ, 'dist-cloudflare');
const PORTA = Number(process.argv[2] ?? 8788);

const TIPOS = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.woff2': 'font/woff2',
  '.ico': 'image/x-icon',
  '.map': 'application/json; charset=utf-8',
};

/** Impede que `..` no caminho escape de `dist-cloudflare/`. */
function resolverDentro(pathname) {
  const relativo = normalize(decodeURIComponent(pathname)).replace(/^([\\/])+/, '');
  const absoluto = join(SAIDA, relativo);
  return absoluto.startsWith(SAIDA) ? absoluto : null;
}

/** O pipeline de assets: arquivo, ou index.html do diretório, ou 404. */
async function lerAsset(pathname) {
  const alvo = resolverDentro(pathname);
  if (!alvo) return null;

  const info = await stat(alvo).catch(() => null);
  if (info?.isFile()) {
    return { corpo: await readFile(alvo), tipo: TIPOS[extname(alvo)] ?? 'application/octet-stream' };
  }
  if (info?.isDirectory() || pathname.endsWith('/')) {
    const indice = join(alvo, 'index.html');
    const infoIndice = await stat(indice).catch(() => null);
    if (infoIndice?.isFile()) {
      return { corpo: await readFile(indice), tipo: TIPOS['.html'] };
    }
  }
  return null;
}

function responder(res, status, corpo, tipo) {
  res.writeHead(status, {
    'content-type': tipo ?? TIPOS['.html'],
    'content-length': Buffer.byteLength(corpo),
  });
  res.end(corpo);
}

const servidor = createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', 'http://localhost');
  const metodo = req.method ?? 'GET';

  /* Fora de /admin o Worker não roda: asset ou 404, como no chat. */
  if (!ehDoPainel(url.pathname)) {
    const asset = await lerAsset(url.pathname);
    if (asset) return responder(res, 200, asset.corpo, asset.tipo);
    return responder(res, 404, 'Not Found', 'text/plain; charset=utf-8');
  }

  const antes = decidirAntes(metodo, url.pathname);
  if (antes.tipo === 'redirecionar') {
    url.pathname = antes.para;
    res.writeHead(301, { location: url.pathname + url.search });
    return res.end();
  }

  const asset = await lerAsset(url.pathname);
  if (asset) return responder(res, 200, asset.corpo, asset.tipo);

  const depois = decidirApos404(metodo, url.pathname);
  if (depois.tipo !== 'indice') {
    return responder(res, 404, 'Not Found', 'text/plain; charset=utf-8');
  }

  const indice = await lerAsset(INDICE_PAINEL);
  if (!indice) return responder(res, 404, 'Not Found', 'text/plain; charset=utf-8');
  return responder(res, 200, indice.corpo, indice.tipo);
});

servidor.listen(PORTA, () => {
  console.log('simulando o Worker sobre dist-cloudflare/');
  console.log('  http://localhost:' + PORTA + '/        → chat');
  console.log('  http://localhost:' + PORTA + '/admin/  → painel');
});
