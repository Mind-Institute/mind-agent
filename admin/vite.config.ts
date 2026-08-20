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
  },
});
