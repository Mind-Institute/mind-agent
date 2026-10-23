import { describe, expect, it } from 'vitest';
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { Agent, AgentChannel, AgentPrompt, ChannelEntry } from '@/contracts';
import { criarBanco } from '@/mocks/db';
import { MockAdminDataProvider } from '@/services/mock-admin-data-provider';
import { renderizarPainel } from './utils';

/* ============================================================
   CANAIS E ROTEADOR
   ============================================================
   Pedido da Adriana (22/10/2026): ver, por canal, por onde a pessoa chega,
   quem atende primeiro e para quem o roteador pode passar, com liga/desliga.
   A porta é a `mindagent-knowledge` (`tests/agent_intelligence_painel.test.mjs`)
   e o roteador lê o mesmo banco (`tests/router_politica.test.mjs`). */

const QUANDO = '2026-10-22T13:35:26.000000+00:00';

const AGENTES: Agent[] = [
  { id: 'concierge_summit', rota: 'concierge_summit', nome: 'Concierge Summit', descricao: 'Ajuda quem participa do Summit.', analisaConversas: true, modelo: null, atualizadoEm: QUANDO },
  { id: 'mia_summit_2026', rota: 'mia_summit_2026', nome: 'MIA Summit 2026', descricao: null, analisaConversas: true, modelo: null, atualizadoEm: QUANDO },
  { id: 'cliente_suporte', rota: 'cliente_suporte', nome: 'Suporte ao cliente', descricao: null, analisaConversas: true, modelo: null, atualizadoEm: QUANDO },
];

const CANAIS: AgentChannel[] = [
  { id: 'mindagent-web::concierge_summit', canal: 'mindagent-web', rota: 'concierge_summit', ativo: true, roteavel: true, entradasDiretas: ['mind_summit_app'], observacao: null, atualizadoEm: QUANDO },
  { id: 'mindagent-web::mia_summit_2026', canal: 'mindagent-web', rota: 'mia_summit_2026', ativo: true, roteavel: false, entradasDiretas: [], observacao: null, atualizadoEm: QUANDO },
  { id: 'whatsapp::cliente_suporte', canal: 'whatsapp', rota: 'cliente_suporte', ativo: true, roteavel: true, entradasDiretas: [], observacao: null, atualizadoEm: QUANDO },
  { id: 'whatsapp::mia_summit_2026', canal: 'whatsapp', rota: 'mia_summit_2026', ativo: false, roteavel: false, entradasDiretas: [], observacao: null, atualizadoEm: QUANDO },
];

const ENTRADAS: ChannelEntry[] = [
  { id: 'whatsapp_flutuante', codigo: 'whatsapp_flutuante', canal: 'whatsapp', site: 'mindsummit', rotulo: 'Botão flutuante de WhatsApp', descricao: 'Entrada mais genérica do site.', audienciaSugerida: 'desconhecido', ativo: true, atualizadoEm: QUANDO },
];

const PROMPT_ROTEADOR: AgentPrompt = {
  id: 'router_universal', chave: 'router_universal', titulo: 'Router Universal', conteudo: 'ROUTER UNIVERSAL — MIND',
  ativo: true, versao: 5, produtoCodigo: null, atualizadoEm: QUANDO, rota: null, usadoPor: [], historico: [],
};

function provedor() {
  const banco = criarBanco();
  banco.agents = structuredClone(AGENTES);
  banco.agent_channels = structuredClone(CANAIS);
  banco.channel_entries = structuredClone(ENTRADAS);
  banco.agent_prompts = structuredClone([PROMPT_ROTEADOR]);
  return new MockAdminDataProvider({ banco, latenciaMs: 0 });
}

describe('Canais e Roteador', () => {
  it('mostra, por canal, por onde a pessoa chega e quem atende primeiro', async () => {
    renderizarPainel({ rota: '/canais', provedor: provedor() });

    const app = await screen.findByRole('region', { name: 'Por onde a pessoa chega no App (web)' });
    const porta = within(app).getByRole('list', { name: 'Portas diretas do App (web)' });
    expect(porta).toHaveTextContent('mind_summit_app');
    expect(porta).toHaveTextContent('Concierge Summit');
    expect(porta).toHaveTextContent('atende direto, sem roteador');
    expect(app).toHaveTextContent('Qualquer outra entrada: o roteador decide entre Concierge Summit.');

    const whats = screen.getByRole('region', { name: 'Por onde a pessoa chega no WhatsApp' });
    expect(within(whats).getByText('Botão flutuante de WhatsApp')).toBeInTheDocument();
    expect(whats).toHaveTextContent('Fluxo da Treble; depois, o roteador decide');
    expect(whats).toHaveTextContent('o roteador decide entre Suporte ao cliente.');

    /* O prompt do roteador está aqui, editável. */
    expect(await screen.findByDisplayValue('ROUTER UNIVERSAL — MIND')).toBeInTheDocument();
  });

  it('o administrador deixa o roteador escolher a MIA no app', async () => {
    const p = provedor();
    renderizarPainel({ rota: '/canais', provedor: p });

    await userEvent.click(await screen.findByRole('switch', { name: 'Roteador pode escolher MIA Summit 2026 no App (web)' }));
    await waitFor(() =>
      expect(p.banco.agent_channels.find((c) => c.id === 'mindagent-web::mia_summit_2026')?.roteavel).toBe(true),
    );
  });

  it('entradas diretas se digitam separadas por vírgula e vão ao banco como lista', async () => {
    const p = provedor();
    renderizarPainel({ rota: '/canais', provedor: p });

    const campo = await screen.findByLabelText('Entradas diretas de MIA Summit 2026 no App (web)');
    await userEvent.type(campo, 'institute_learnworlds, outra_entrada');
    await userEvent.click(screen.getByRole('button', { name: 'Salvar entradas' }));

    await waitFor(() =>
      expect(p.banco.agent_channels.find((c) => c.id === 'mindagent-web::mia_summit_2026')?.entradasDiretas)
        .toEqual(['institute_learnworlds', 'outra_entrada']),
    );
  });

  it('desligar um agente no canal pede confirmação; roteável só com atende ligado', async () => {
    const p = provedor();
    renderizarPainel({ rota: '/canais', provedor: p });

    expect(await screen.findByRole('switch', { name: 'Roteador pode escolher MIA Summit 2026 no WhatsApp' })).toBeDisabled();

    await userEvent.click(screen.getByRole('switch', { name: 'Concierge Summit atende no App (web)' }));
    expect(await screen.findByText('Desligar este agente no canal?')).toBeInTheDocument();
    expect(p.banco.agent_channels.find((c) => c.id === 'mindagent-web::concierge_summit')?.ativo).toBe(true);
    await userEvent.click(screen.getByRole('button', { name: 'Desligar' }));
    await waitFor(() =>
      expect(p.banco.agent_channels.find((c) => c.id === 'mindagent-web::concierge_summit')?.ativo).toBe(false),
    );
  });

  it('quem não é administrador só vê', async () => {
    renderizarPainel({ rota: '/canais', papel: 'editor', provedor: provedor() });
    expect(await screen.findByRole('switch', { name: 'Concierge Summit atende no App (web)' })).toBeDisabled();
    expect(screen.getByLabelText('Entradas diretas de MIA Summit 2026 no App (web)')).toBeDisabled();
  });
});

describe('o que cada agente faz', () => {
  it('aparece na ficha do agente e o administrador descreve', async () => {
    const p = provedor();
    renderizarPainel({ rota: '/agent-intelligence', provedor: p });

    const grupo = await screen.findByRole('group', { name: 'Agentes' });
    await userEvent.click(within(grupo).getByRole('button', { name: 'MIA Summit 2026' }));
    expect(await screen.findByText('Ainda sem descrição do que este agente faz.')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Descrever' }));
    await userEvent.type(screen.getByLabelText('O que este agente faz'), 'Orienta a partir das palestras.');
    await userEvent.click(screen.getByRole('button', { name: 'Salvar' }));

    await waitFor(() => expect(p.banco.agents.find((a) => a.rota === 'mia_summit_2026')?.descricao).toBe('Orienta a partir das palestras.'));
    expect(await screen.findByText('Orienta a partir das palestras.')).toBeInTheDocument();
  });
});
