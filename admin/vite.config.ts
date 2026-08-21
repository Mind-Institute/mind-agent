import path from 'node:path';
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

/**
 * O painel vive em `admin/`, ao lado do chat estático da raiz. Ele nunca
 * importa código do chat: a única coisa que atravessa a fronteira são os
 * dados de demonstração (`../dados/summit.json`) e os assets de marca
 * (`../assets/`) — leitura, nunca escrita.
 */
export default defineConfig({
  /* O painel é servido sob /admin, o chat na raiz. Sem isto o build
     emite `/assets/index-*.js` absoluto, que em produção cai nos assets
     do chat e o painel abre em branco. O `basename` do roteador lê este
     mesmo valor via `import.meta.env.BASE_URL`. */
  base: '/admin/',
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      '@dados': path.resolve(__dirname, '../dados'),
      '@marca': path.resolve(__dirname, '../assets'),
    },
  },
  build: {
    rollupOptions: {
      output: {
        /* Separa as bibliotecas do código do painel: elas mudam pouco e
           ganham cache próprio entre deploys. */
        manualChunks: {
          react: ['react', 'react-dom', 'react-router-dom'],
          dados: ['@tanstack/react-query', 'react-hook-form', 'zod'],
        },
      },
    },
  },
  server: {
    port: 5174,
    // Permite servir a fonte Satoshi e o símbolo da marca, que moram na
    // raiz do repositório (fora do root do Vite).
    fs: { allow: ['..'] },
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    css: false,
    restoreMocks: true,
    /* O Vite carrega `.env.local` também em modo de teste, o que
       deixaria a suíte dependente da máquina — e, pior, capaz de bater
       no backend real. Aqui o ambiente é zerado: sem URL de API e sem
       Supabase, nenhum cliente de verdade é criado e nenhuma requisição
       sai. Quem precisa de rede injeta um `fetch` falso. */
    env: {
      VITE_ADMIN_API_BASE_URL: '',
      VITE_ADMIN_DATA_MODE: 'mock',
      VITE_SUPABASE_URL: '',
      VITE_SUPABASE_PUBLISHABLE_KEY: '',
    },
  },
});
