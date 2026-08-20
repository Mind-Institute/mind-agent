import { render, type RenderResult } from '@testing-library/react';
import { RouterProvider, createMemoryRouter } from 'react-router-dom';
import type { Papel } from '@/contracts';
import { FUTURO_PROVEDOR, FUTURO_ROTEADOR, Provedores, criarClienteDeConsulta } from '@/App';
import { rotasAdmin } from '@/routes';
import { MockAdminDataProvider } from '@/services/mock-admin-data-provider';

/* ============================================================
   AJUDANTES DE TESTE
   ============================================================
   Cada teste monta o painel inteiro — rotas, provedores e um banco
   novo em memória. É o mais próximo do uso real que dá para chegar sem
   navegador, e garante que a troca de página passa pelo roteador de
   verdade.

   `latenciaMs: 0` porque a espera artificial só serve para a demo. */

export interface OpcoesRender {
  rota?: string;
  papel?: Papel;
  provedor?: MockAdminDataProvider;
  agora?: number;
}

export interface ResultadoRender extends RenderResult {
  provedor: MockAdminDataProvider;
}

export function renderizarPainel({
  rota = '/',
  papel = 'administrador',
  provedor,
  agora,
}: OpcoesRender = {}): ResultadoRender {
  const usado = provedor ?? new MockAdminDataProvider({ latenciaMs: 0, agora });
  const roteador = createMemoryRouter(rotasAdmin, {
    initialEntries: [rota],
    future: FUTURO_ROTEADOR,
  });

  const resultado = render(
    <Provedores provider={usado} papelInicial={papel} queryClient={criarClienteDeConsulta()}>
      <RouterProvider router={roteador} future={FUTURO_PROVEDOR} />
    </Provedores>,
  );

  return Object.assign(resultado, { provedor: usado });
}

/** Conta as linhas de dados da tabela atual. */
export function contarLinhas(container: HTMLElement): number {
  return container.querySelectorAll('tbody tr').length;
}
