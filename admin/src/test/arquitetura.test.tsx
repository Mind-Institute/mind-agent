import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { screen } from '@testing-library/react';
import { renderizarPainel } from './utils';
import { DECISOES } from '@/lib/arquitetura';

describe('arquitetura do sistema', () => {
  it('mostra as decisões numeradas e as regras posteriores', async () => {
    renderizarPainel({ rota: '/arquitetura' });

    expect(await screen.findByRole('heading', { name: 'Arquitetura do sistema', level: 1 })).toBeVisible();
    for (const decisao of DECISOES) {
      expect(screen.getByRole('article', { name: new RegExp(`^${decisao.codigo} — `) })).toBeVisible();
    }
    expect(screen.getByRole('heading', { name: 'Regras posteriores' })).toBeVisible();
  });

  /* A fonte é o PROJECT_STATE.md: decisão numerada lá e não aqui (ou o
     contrário) é resumo desatualizado. */
  it('lista exatamente as decisões numeradas do PROJECT_STATE.md', () => {
    const doc = readFileSync(path.resolve(__dirname, '../../../PROJECT_STATE.md'), 'utf8');
    const noDocumento = [...new Set([...doc.matchAll(/\*\*(D\d+)\s+[—(]/g)].map((m) => m[1]))].sort();

    expect(DECISOES.map((d) => d.codigo).sort()).toEqual(noDocumento);
  });
});
