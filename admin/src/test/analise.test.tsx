import { describe, expect, it } from 'vitest';
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { Agent, AgentPrompt, AnalysisRun } from '@/contracts';
import { criarBanco } from '@/mocks/db';
import { MockAdminDataProvider } from '@/services/mock-admin-data-provider';
import { renderizarPainel } from './utils';

/* ============================================================
   ANÁLISE PÓS-CONVERSA (Adriana, 22/10/2026)
   ============================================================ */

const QUANDO = '2026-10-22T14:09:01.000000+00:00';

const AGENTES: Agent[] = [
  { id: 'concierge_summit', rota: 'concierge_summit', nome: 'Concierge Summit', descricao: null, analisaConversas: true, modelo: null, atualizadoEm: QUANDO },
  { id: 'mia_summit_2026', rota: 'mia_summit_2026', nome: 'MIA Summit 2026', descricao: null, analisaConversas: true, modelo: null, atualizadoEm: QUANDO },
];

const prompt = (chave: string, ativo: boolean, conteudo: string): AgentPrompt => ({
  id: chave, chave, titulo: chave, conteudo, ativo, versao: 3, produtoCodigo: null, atualizadoEm: QUANDO, rota: null, usadoPor: [], historico: [],
});

const EXECUCAO: AnalysisRun = {
  id: '88888888-8888-4888-8888-888888888888', conversaId: '66666666-6666-4666-8666-666666666666',
  analisador: 'analise_concierge', funcao: 'concierge', vertical: null, modelo: 'gpt-5.4-mini', promptVersao: 6,
  analisadoEm: QUANDO, canal: 'mindagent-web', agente: 'mindagent-chat', rota: 'concierge_summit', primeiroNome: 'Ana',
  memoriasGravadas: 2, continuidade: null,
  dados: { customer_memory: [{ key: 'tema', value: 'burnout' }] },
  memorias: [{ tipo: 'interesse', chave: 'burnout', status: 'ativa', confianca: 0.9, valor: { text: 'burnout' } }],
};

function provedor() {
  const banco = criarBanco();
  banco.agents = structuredClone(AGENTES);
  banco.agent_prompts = structuredClone([
    prompt('analise_classificador', true, 'CLASSIFICADOR'),
    prompt('analise_concierge', true, 'ANALISE CONCIERGE'),
    prompt('analise_atendimento', false, ''),
  ]);
  banco.analysis_runs = structuredClone([EXECUCAO]);
  return new MockAdminDataProvider({ banco, latenciaMs: 0 });
}

describe('Análise pós-conversa', () => {
  it('mostra os prompts com estado, abre o classificador para editar e lista as execuções', async () => {
    renderizarPainel({ rota: '/analise', provedor: provedor() });

    const grupo = await screen.findByRole('group', { name: 'Prompts da análise' });
    expect(within(grupo).getByRole('button', { name: /analise_classificador/ })).toHaveTextContent('ligado · versão 3');
    expect(within(grupo).getByRole('button', { name: /analise_atendimento/ })).toHaveTextContent('desligado');
    expect(within(grupo).getByRole('button', { name: /analise_vendas_dash/ })).toHaveTextContent('não existe');
    expect(await screen.findByDisplayValue('CLASSIFICADOR')).toBeInTheDocument();

    const linha = await screen.findByTestId(`execucao-${EXECUCAO.id}`);
    expect(linha).toHaveTextContent('analise_concierge');
    expect(linha).toHaveTextContent('Concierge Summit');
    await userEvent.click(within(linha).getByRole('button', { name: 'Abrir' }));
    expect(await screen.findByLabelText('Conclusão da análise')).toHaveTextContent('burnout');
    expect(screen.getByLabelText('Memórias gravadas')).toHaveTextContent('interesse · burnout');
  });

  it('o administrador desliga a análise das conversas de um agente', async () => {
    const p = provedor();
    renderizarPainel({ rota: '/analise', provedor: p });
    await userEvent.click(await screen.findByRole('switch', { name: 'Analisar as conversas de MIA Summit 2026' }));
    await waitFor(() => expect(p.banco.agents.find((a) => a.rota === 'mia_summit_2026')?.analisaConversas).toBe(false));
  });

  it('quem não é administrador vê os prompts, mas não as execuções nem os interruptores', async () => {
    renderizarPainel({ rota: '/analise', papel: 'editor', provedor: provedor() });
    expect(await screen.findByText('Só administrador vê as execuções.')).toBeInTheDocument();
    expect(screen.getByRole('switch', { name: 'Analisar as conversas de MIA Summit 2026' })).toBeDisabled();
    expect(screen.queryByTestId(`execucao-${EXECUCAO.id}`)).not.toBeInTheDocument();
  });
});
