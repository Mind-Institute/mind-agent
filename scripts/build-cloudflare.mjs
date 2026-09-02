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
  /* Importado por `app.js` no topo. Sem ele o módulo inteiro não
     executa e a tela fica na abertura — foi o que aconteceu em 02/09. */
  'teclado.js',
  /* Contratos e camada de dados, compartilhados com o painel */
  'config.js',
  'data-service.js',
  'chat-service.js',
  /* Os componentes da home V3 */
  'home',
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

/* Instala as dependências do painel se elas não estiverem lá.
   O painel tem `package.json` próprio e a raiz não declara workspaces,
   então um `install` na raiz NÃO traz o Vite. No Workers Builds da
   Cloudflare só a raiz é instalada — sem isto, o build do painel morre
   em "vite: not found". Na máquina de quem desenvolve é no-op. */
async function instalarDependenciasDoPainel() {
  const ADMIN = join(RAIZ, 'admin');
  if (await existe(join(ADMIN, 'node_modules'))) return;

  const temLock = await existe(join(ADMIN, 'package-lock.json'));
  const comando = temLock ? 'npm ci' : 'npm install';
  console.log('admin/node_modules ausente — rodando `' + comando + '`…');

  /* `cwd` em vez de `--prefix`: o `npm ci` ignora `--prefix` em algumas
     versões e instalaria na raiz. */
  const r = spawnSync(comando, { cwd: ADMIN, stdio: 'inherit', shell: true });
  if (r.status !== 0) {
    throw new Error('a instalação das dependências do painel falhou');
  }
}

/** Constrói o painel. `vite build` já roda o `tsc --noEmit` antes. */
async function construirPainel() {
  await instalarDependenciasDoPainel();

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

/* Só imports relativos: `npm:`, `jsr:` e URL não são arquivo nosso.
   Cobre `from './x.js'` e `import('./x.js')`. */
const IMPORT_RELATIVO = /from\s*['"](\.[^'"]+)['"]|import\s*\(\s*['"](\.[^'"]+)['"]\s*\)/g;

async function jsCopiados(dir) {
  const achados = [];
  for (const item of await readdir(dir, { withFileTypes: true })) {
    /* O painel é bundle do Vite, com nomes com hash e imports que ele
       mesmo resolve — não é lista escrita à mão, não é este risco. */
    if (item.isDirectory()) {
      if (item.name === 'admin') continue;
      achados.push(...(await jsCopiados(join(dir, item.name))));
    } else if (item.name.endsWith('.js')) {
      achados.push(join(dir, item.name));
    }
  }
  return achados;
}

async function conferirImports() {
  const faltando = [];
  for (const arquivo of await jsCopiados(SAIDA)) {
    const fonte = await readFile(arquivo, 'utf8');
    for (const achado of fonte.matchAll(IMPORT_RELATIVO)) {
      const especificador = achado[1] ?? achado[2];
      const alvo = join(dirname(arquivo), especificador);
      if (!(await existe(alvo))) {
        faltando.push(relative(SAIDA, arquivo) + ' importa ' + especificador);
      }
    }
  }
  if (faltando.length) {
    throw new Error(
      'import sem arquivo no build — acrescente à lista DO_CHAT:\n  ' + faltando.join('\n  '),
    );
  }
  console.log('imports relativos conferidos: todos resolvem');
}

async function main() {
  /* 1. Limpa SÓ a saída. `dist/` de outras ferramentas e `admin/dist`
        não são tocados aqui — quem cuida de `admin/dist` é o Vite. */
  await rm(SAIDA, { recursive: true, force: true });

  /* 2. Constrói o painel (gera `admin/dist`), instalando o que faltar. */
  await construirPainel();

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

  /* 7. Todo import relativo do chat tem de existir no que foi copiado.
        A lista acima é escrita à mão, e foi conferida à mão — até o dia
        em que não foi: `teclado.js` entrou no repositório, `app.js`
        passou a importá-lo e a lista não soube. Em desenvolvimento os
        arquivos vêm da raiz e nada quebra; em produção o import 404, o
        módulo não executa e a tela fica na abertura para sempre.

        Conferir custa uma volta de laço e transforma um app fora do ar
        num build que falha. */
  await conferirImports();

  console.log('');
  console.log('dist-cloudflare/ montado — ' + (await contar(SAIDA)) + ' arquivos');
  console.log('  /        → Mind Agent (chat público)');
  console.log('  /admin/  → Painel Admin');
}

main().catch((e) => {
  console.error('falhou: ' + e.message);
  process.exit(1);
});
