/* ============================================================
   BUILD DO CLOUDFLARE — dois produtos, um site
   ============================================================
   Monta `dist-cloudflare/`, que é o que sobe:

     dist-cloudflare/         → Mind Agent, o chat público (arquivos da raiz)
     dist-cloudflare/admin/   → Painel Admin (build do Vite, base /admin/)

   Por que um script e não publicar a raiz do repositório — que é
   exatamente o que estava quebrado: a raiz tem `admin/index.html`, o
   ponto de entrada de DESENVOLVIMENTO do Vite, que aponta para
   `/src/main.tsx`. Em produção esse arquivo não existe, e o painel abre
   em branco com 404 no console. O que precisa subir é o ARTEFATO do
   Vite, onde o `<script>` já aponta para `/admin/assets/…`.

   O segundo motivo: chat e painel têm cada um a sua pasta `assets/`. Na
   mesma raiz, uma sobrescreveria a outra. Aqui o painel entra sob
   `admin/`, e o `base` do Vite já emite `/admin/assets/…`.

   Este script NÃO altera nenhum arquivo-fonte. Ele lê da raiz e de
   `admin/dist`, e escreve só dentro de `dist-cloudflare/`.
*/

import { spawnSync } from 'node:child_process';
import { cp, mkdir, readFile, rm, stat, readdir } from 'node:fs/promises';
import { basename, dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
const SAIDA = join(RAIZ, 'dist-cloudflare');
const BUILD_ADMIN = join(RAIZ, 'admin', 'dist');

/* O chat é estático: estes são todos os seus arquivos, conferidos contra
   as referências de `index.html`, `styles.css` e os imports de `app.js`.
   Lista explícita de propósito — assim README, `.env.local`,
   `node_modules` e a própria saída não entram no deploy por acidente. */
const DO_CHAT = [
  /* Central do Evento — a home */
  'index.html',
  'styles.css',
  'app.js',
  /* Contratos e camada de dados, compartilhados com o painel */
  'config.js',
  'data-service.js',
  'chat-service.js',
  'assets',
  'dados',
];

/* Arquivos que o chat usa quando existem.
   A separação não é preciosismo: o chat ganha peça nova com frequência
   (a home foi reescrita, apareceu a experiência clássica em
   /classic.html), e uma lista única e obrigatória faria o build falhar
   em qualquer checkout onde a peça ainda não chegou. Presente, entra;
   ausente, o build segue e diz que seguiu. */
const DO_CHAT_OPCIONAIS = [
  'agent-dados.js',
  'agent-regras.js',
  'classic.html',
  'styles-classic.css',
  'app-classic.js',
  /* Preserva as quebras de linha das respostas da IA. Carregado pelas
     duas páginas, então some das duas se não vier. */
  'chat-format.css',
];

/* Nada com estes nomes é copiado, em nenhum nível. Rede de segurança
   para o caso de um deles aparecer dentro de `assets/` ou `dados/`. */
const NUNCA_COPIAR = new Set([
  '.env',
  '.env.local',
  '.env.development',
  '.env.production',
  '.git',
  '.gitignore',
  'node_modules',
  '.DS_Store',
  'Thumbs.db',
]);

const existe = (caminho) => stat(caminho).then(() => true, () => false);

function filtro(origem) {
  if (NUNCA_COPIAR.has(basename(origem))) {
    console.log('  ignorado: ' + relative(RAIZ, origem));
    return false;
  }
  return true;
}

/** Constrói o painel. `vite build` já roda o `tsc --noEmit` antes. */
function construirPainel() {
  console.log('construindo o painel…');
  const r = spawnSync('npm run build --prefix admin', {
    cwd: RAIZ,
    stdio: 'inherit',
    shell: true,
  });
  if (r.status !== 0) {
    throw new Error('o build do painel falhou — nada foi montado');
  }
}

/** Conta arquivos, recursivamente, só para o resumo do fim. */
async function contar(dir) {
  let total = 0;
  for (const item of await readdir(dir, { withFileTypes: true })) {
    total += item.isDirectory() ? await contar(join(dir, item.name)) : 1;
  }
  return total;
}

async function main() {
  /* 1. Limpa SÓ a saída. `dist/` de outras ferramentas e `admin/dist`
        não são tocados aqui — quem cuida de `admin/dist` é o Vite. */
  await rm(SAIDA, { recursive: true, force: true });

  /* 2. Constrói o painel (gera `admin/dist`). */
  construirPainel();

  /* 3. Cria a saída. */
  await mkdir(SAIDA, { recursive: true });

  /* 4. O chat, na raiz. */
  for (const item of DO_CHAT) {
    const origem = join(RAIZ, item);
    if (!(await existe(origem))) {
      throw new Error('falta ' + item + ' — o chat não está completo');
    }
    await cp(origem, join(SAIDA, item), { recursive: true, filter: filtro });
  }

  for (const item of DO_CHAT_OPCIONAIS) {
    const origem = join(RAIZ, item);
    if (!(await existe(origem))) {
      console.log('  ausente, seguindo sem: ' + item);
      continue;
    }
    await cp(origem, join(SAIDA, item), { recursive: true, filter: filtro });
  }

  /* 5. O painel, sob /admin. */
  if (!(await existe(BUILD_ADMIN))) {
    throw new Error('admin/dist não existe — o build do painel não produziu nada');
  }
  await cp(BUILD_ADMIN, join(SAIDA, 'admin'), { recursive: true, filter: filtro });

  /* 6. Confere o que mais importa: o index do painel não pode carregar
        o ponto de entrada de desenvolvimento. É a falha que este script
        existe para não repetir, então ela é verificada, não presumida. */
  const indice = await readFile(join(SAIDA, 'admin', 'index.html'), 'utf8');
  if (indice.includes('/src/main.tsx')) {
    throw new Error(
      'admin/index.html do build ainda aponta para /src/main.tsx — o artefato do Vite não foi usado',
    );
  }
  if (!/src="\/admin\/assets\//.test(indice)) {
    throw new Error(
      'admin/index.html do build não referencia /admin/assets/ — confira `base` em admin/vite.config.ts',
    );
  }

  console.log('');
  console.log('dist-cloudflare/ montado — ' + (await contar(SAIDA)) + ' arquivos');
  console.log('  /        → Mind Agent (chat público)');
  console.log('  /admin/  → Painel Admin');
}

main().catch((e) => {
  console.error('falhou: ' + e.message);
  process.exit(1);
});
