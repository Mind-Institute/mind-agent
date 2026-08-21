import { describe, expect, it } from 'vitest';
import { screen, within } from '@testing-library/react';
import {
  DIRETORIO_ASSETS,
  INDICE_PAINEL,
  decidirAntes,
  decidirApos404,
  ehDoPainel,
  pedeArquivo,
} from '../../../cloudflare/roteamento.js';
import { renderizarPainel } from './utils';

/* ============================================================
   PUBLICAÇÃO — o painel sob /admin/
   ============================================================
   Duas coisas que só quebram em produção, e que por isso precisam de
   teste: o prefixo das rotas e a decisão do Worker entre 404 e fallback
   de SPA.

   As regras do Worker moram na raiz do repositório (`cloudflare/`), não
   em `admin/`. Elas são testadas aqui porque este é o único runner do
   projeto — a alternativa seria não testá-las. */

describe('rotas sob /admin (basename)', () => {
  it('monta a página no deep link, com o prefixo de produção', async () => {
    renderizarPainel({ rota: '/admin/programacao', basename: '/admin' });

    expect(await screen.findByRole('heading', { name: 'Programação', level: 1 })).toBeVisible();
  });

  it('os links do menu levam o prefixo UMA vez, sem /admin/admin', async () => {
    renderizarPainel({ rota: '/admin/', basename: '/admin' });

    const menu = await screen.findByRole('navigation', { name: /navegação principal/i });

    const evento = within(menu).getByRole('link', { name: /^Evento/ });
    expect(evento).toHaveAttribute('href', '/admin/evento');

    /* A raiz do painel: o React Router normaliza `to="/"` para o próprio
       basename, com ou sem barra final. As duas formas servem. */
    const visaoGeral = within(menu).getByRole('link', { name: /visão geral/i });
    expect(visaoGeral.getAttribute('href')).toMatch(/^\/admin\/?$/);

    /* O que este teste existe para pegar: prefixo duplicado. */
    for (const link of within(menu).getAllByRole('link')) {
      expect(link.getAttribute('href'), link.textContent ?? '').not.toMatch(/\/admin\/admin/);
      expect(link.getAttribute('href')).toMatch(/^\/admin(\/|$)/);
    }
  });

  it('sem basename as rotas seguem na raiz — é o que as outras suítes usam', async () => {
    renderizarPainel({ rota: '/programacao' });

    expect(await screen.findByRole('heading', { name: 'Programação', level: 1 })).toBeVisible();
    const menu = screen.getByRole('navigation', { name: /navegação principal/i });
    expect(within(menu).getByRole('link', { name: /^Evento/ })).toHaveAttribute('href', '/evento');
  });
});

describe('regras de roteamento do Worker', () => {
  it('só entra em /admin e /admin/*', () => {
    expect(ehDoPainel('/admin')).toBe(true);
    expect(ehDoPainel('/admin/')).toBe(true);
    expect(ehDoPainel('/admin/programacao')).toBe(true);
    expect(ehDoPainel('/admin/assets/index.js')).toBe(true);

    /* O chat não passa pelo Worker: 404 dele continua 404. */
    expect(ehDoPainel('/')).toBe(false);
    expect(ehDoPainel('/app.js')).toBe(false);
    expect(ehDoPainel('/dados/summit.json')).toBe(false);
    expect(ehDoPainel('/administrativo')).toBe(false);
  });

  it('/admin sem barra redireciona para /admin/', () => {
    expect(decidirAntes('GET', '/admin')).toEqual({ tipo: 'redirecionar', para: '/admin/' });
    expect(decidirAntes('GET', '/admin/')).toEqual({ tipo: 'asset' });
    expect(decidirAntes('GET', '/admin/evento')).toEqual({ tipo: 'asset' });
  });

  it('distingue pedido de ARQUIVO de navegação', () => {
    /* Arquivo: tem extensão, ou está sob o diretório de build. */
    expect(pedeArquivo('/admin/assets/index-abc123.js')).toBe(true);
    expect(pedeArquivo('/admin/assets/index-abc123.css')).toBe(true);
    expect(pedeArquivo('/admin/assets/inexistente.js')).toBe(true);
    expect(pedeArquivo('/admin/favicon.svg')).toBe(true);
    expect(pedeArquivo('/admin/qualquer.json')).toBe(true);

    /* Navegação: sem extensão. */
    expect(pedeArquivo('/admin/')).toBe(false);
    expect(pedeArquivo('/admin/programacao')).toBe(false);
    expect(pedeArquivo('/admin/programacao/ses_123')).toBe(false);
    expect(pedeArquivo('/admin/configuracoes')).toBe(false);

    expect(DIRETORIO_ASSETS).toBe('/admin/assets/');
  });

  it('404 de navegação cai no index do painel', () => {
    for (const caminho of ['/admin/', '/admin/programacao', '/admin/evento', '/admin/palestrantes/pal_1']) {
      expect(decidirApos404('GET', caminho), caminho).toEqual({ tipo: 'indice' });
    }
    expect(INDICE_PAINEL).toBe('/admin/index.html');
  });

  it('404 de arquivo continua 404 — nunca HTML no lugar de JS ou CSS', () => {
    for (const caminho of [
      '/admin/assets/inexistente.js',
      '/admin/assets/inexistente.css',
      '/admin/assets/index-abc.js.map',
      '/admin/sumiu.svg',
    ]) {
      expect(decidirApos404('GET', caminho), caminho).toEqual({ tipo: 'asset' });
    }
  });

  it('método que não é navegação não recebe fallback', () => {
    expect(decidirApos404('POST', '/admin/programacao')).toEqual({ tipo: 'asset' });
    expect(decidirApos404('DELETE', '/admin/evento')).toEqual({ tipo: 'asset' });
    expect(decidirApos404('HEAD', '/admin/evento')).toEqual({ tipo: 'indice' });
  });
});
