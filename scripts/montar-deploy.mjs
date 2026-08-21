/* ============================================================
   MONTAGEM DO DEPLOY — dois produtos, um site
   ============================================================
   Junta em `dist/` o que vai para o ar:

     dist/            → Mind Agent, o chat público (arquivos da raiz)
     dist/admin/      → Painel Admin (build do Vite, base /admin/)
     dist/_redirects  → deep link do painel cai no index dele

   Por que um script e não copiar a raiz inteira: o chat e o painel têm
   cada um a sua pasta `assets/`. Se os dois fossem para a raiz, um
   sobrescreveria o outro. Aqui o painel entra sob `admin/`, e o `base`
   do Vite já emite `/admin/assets/…` — não há como colidir.

   Este script não constrói o painel: quem faz isso é `npm run build`,
   que roda `vite build` em `admin/` antes de chamar aqui.
*/

import { cp, mkdir, rm, writeFile, stat } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
const DIST = join(RAIZ, 'dist');

/* O chat é estático: estes são todos os seus arquivos. Lista explícita
   de propósito — assim nada entra no deploy por acidente (README,
   .env, node_modules, o próprio dist). */
const DO_CHAT = [
  'index.html',
  'styles.css',
  'app.js',
  'config.js',
  'data-service.js',
  'chat-service.js',
  'assets',
  'dados',
];

const existe = (p) => stat(p).then(() => true, () => false);

async function main() {
  await rm(DIST, { recursive: true, force: true });
  await mkdir(DIST, { recursive: true });

  /* 1. O chat, na raiz */
  for (const item of DO_CHAT) {
    const origem = join(RAIZ, item);
    if (!(await existe(origem))) {
      throw new Error('falta ' + item + ' — o chat não está completo');
    }
    await cp(origem, join(DIST, item), { recursive: true });
  }

  /* 2. O painel, sob /admin */
  const buildAdmin = join(RAIZ, 'admin', 'dist');
  if (!(await existe(buildAdmin))) {
    throw new Error('admin/dist não existe — rode `npm run build:admin` antes');
  }
  await cp(buildAdmin, join(DIST, 'admin'), { recursive: true });

  /* 3. Duas regras, nesta ordem (a primeira que casa ganha):

        - `/admin` sem barra vira `/admin/`, senão os caminhos relativos
          do painel resolveriam contra a raiz do chat;
        - `/admin/qualquer-coisa` cai no index do painel, porque ele é
          SPA com BrowserRouter e a rota é resolvida no cliente.

        O chat não tem rota de cliente: 404 dele continua 404. */
  await writeFile(
    join(DIST, '_redirects'),
    ['/admin            /admin/            301',
     '/admin/*          /admin/index.html  200',
     ''].join('\n'),
    'utf8',
  );

  console.log('dist/ montado:');
  console.log('  /        → Mind Agent (chat público)');
  console.log('  /admin/  → Painel Admin');
}

main().catch((e) => {
  console.error('falhou: ' + e.message);
  process.exit(1);
});
