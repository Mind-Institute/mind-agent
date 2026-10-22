import { afterEach, describe, expect, it, vi } from 'vitest';
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { AgentChannel, AgentKitBlock, AgentPrompt } from '@/contracts';
import { criarBanco } from '@/mocks/db';
import { MockAdminDataProvider } from '@/services/mock-admin-data-provider';
import { SESSAO_DE_TESTE, criarPortaFalsa, renderizarPainel } from './utils';

/* ============================================================
   AGENT INTELLIGENCE — cada agente num lugar só
   ============================================================
   Pedido da Adriana (22/10/2026): operar, por agente, o conhecimento, o
   kit, os canais e os prompts, com histórico; só administrador edita. A
   porta é a `mindagent-knowledge` (`tests/agent_intelligence_painel.test.mjs`)
   e quem decide é o banco. Aqui se confere a tela. */

const QUANDO = '2026-10-22T12:05:12.019284+00:00';

const CANAIS: AgentChannel[] = [
  { id: 'mindagent-web::mia_summit_2026', canal: 'mindagent-web', rota: 'mia_summit_2026', ativo: false, observacao: 'Nasce desligado.', atualizadoEm: QUANDO },
  { id: 'whatsapp::mia_summit_2026', canal: 'whatsapp', rota: 'mia_summit_2026', ativo: false, observacao: null, atualizadoEm: QUANDO },
  { id: 'mindagent-web::concierge_summit', canal: 'mindagent-web', rota: 'concierge_summit', ativo: true, observacao: null, atualizadoEm: QUANDO },
];

const KIT: AgentKitBlock[] = [
  { id: 'mia_summit_2026::evento', rota: 'mia_summit_2026', bloco: 'evento', provider: 'public.mind_kit_evento', secao: 'structured', obrigatorio: true, ativo: true, atualizadoEm: QUANDO },
  { id: 'concierge_summit::evento', rota: 'concierge_summit', bloco: 'evento', provider: 'public.mind_kit_evento', secao: 'structured', obrigatorio: true, ativo: true, atualizadoEm: QUANDO },
  { id: 'concierge_summit::product_decisioning', rota: 'concierge_summit', bloco: 'product_decisioning', provider: 'agentes.prompts', secao: 'decisioning', obrigatorio: false, ativo: true, atualizadoEm: QUANDO },
];

const PROMPT_MIA: AgentPrompt = {
  id: 'playbook_mia_summit_2026',
  chave: 'playbook_mia_summit_2026',
  titulo: 'Playbook — MIA Summit 2026 (RASCUNHO)',
  conteudo: 'VOCÊ É A MIA SUMMIT 2026',
  ativo: false,
  versao: 1,
  produtoCodigo: 'mind-summit-2026',
  atualizadoEm: QUANDO,
  rota: 'mia_summit_2026',
  usadoPor: [],
  historico: [],
};

const PROMPT_CONCIERGE: AgentPrompt = {
  ...PROMPT_MIA,
  id: 'playbook_concierge_summit',
  chave: 'playbook_concierge_summit',
  titulo: 'Playbook — Concierge',
  conteudo: 'CONCIERGE',
  ativo: true,
  rota: 'concierge_summit',
};

function provedorComAgentes() {
  const banco = criarBanco();
  banco.agent_channels = structuredClone(CANAIS);
  banco.agent_kit_blocks = structuredClone(KIT);
  banco.agent_prompts = structuredClone([PROMPT_MIA, PROMPT_CONCIERGE]);
  return new MockAdminDataProvider({ banco, latenciaMs: 0 });
}

describe('Agent Intelligence por agente', () => {
  it('lista os agentes e diz por que a MIA Summit 2026 não atende', async () => {
    renderizarPainel({ rota: '/agent-intelligence', provedor: provedorComAgentes() });

    const grupo = await screen.findByRole('group', { name: 'Agentes' });
    const botoes = within(grupo).getAllByRole('button').map((b) => b.textContent);
    expect(botoes).toEqual(['Concierge Summit', 'MIA Summit 2026']);

    await userEvent.click(within(grupo).getByRole('button', { name: 'MIA Summit 2026' }));
    expect(await screen.findByText('Não atende')).toBeInTheDocument();
    expect(screen.getByText(/o playbook está desligado/)).toBeInTheDocument();
    expect(screen.getByText(/nenhum canal está ligado/)).toBeInTheDocument();
  });

  it('o administrador edita o playbook e salva uma nova versão', async () => {
    const provedor = provedorComAgentes();
    renderizarPainel({ rota: '/agent-intelligence', provedor });

    const grupo = await screen.findByRole('group', { name: 'Agentes' });
    await userEvent.click(within(grupo).getByRole('button', { name: 'MIA Summit 2026' }));
    await userEvent.click(screen.getByRole('tab', { name: 'Prompts' }));

    const texto = await screen.findByLabelText('Texto');
    await userEvent.type(texto, ' — revisado');
    await userEvent.click(screen.getByRole('button', { name: 'Salvar nova versão' }));

    await waitFor(() => {
      const salvo = provedor.banco.agent_prompts.find((p) => p.chave === 'playbook_mia_summit_2026');
      expect(salvo?.conteudo).toBe('VOCÊ É A MIA SUMMIT 2026 — revisado');
    });
  });

  it('ligar um canal pede confirmação antes de salvar', async () => {
    const provedor = provedorComAgentes();
    renderizarPainel({ rota: '/agent-intelligence', provedor });

    const grupo = await screen.findByRole('group', { name: 'Agentes' });
    await userEvent.click(within(grupo).getByRole('button', { name: 'MIA Summit 2026' }));
    await userEvent.click(screen.getByRole('tab', { name: 'Canais' }));
    await userEvent.click(await screen.findByRole('switch', { name: 'MIA Summit 2026 no App (web)' }));

    expect(await screen.findByText('Ligar este canal?')).toBeInTheDocument();
    expect(provedor.banco.agent_channels.find((c) => c.id === 'mindagent-web::mia_summit_2026')?.ativo).toBe(false);

    await userEvent.click(screen.getByRole('button', { name: 'Ligar' }));
    await waitFor(() =>
      expect(provedor.banco.agent_channels.find((c) => c.id === 'mindagent-web::mia_summit_2026')?.ativo).toBe(true),
    );
  });

  it('quem não é administrador vê, mas não edita canais, kit nem prompts', async () => {
    renderizarPainel({ rota: '/agent-intelligence', papel: 'editor', provedor: provedorComAgentes() });

    const grupo = await screen.findByRole('group', { name: 'Agentes' });
    await userEvent.click(within(grupo).getByRole('button', { name: 'MIA Summit 2026' }));

    await userEvent.click(screen.getByRole('tab', { name: 'Canais' }));
    expect(await screen.findByRole('switch', { name: 'MIA Summit 2026 no App (web)' })).toBeDisabled();

    await userEvent.click(screen.getByRole('tab', { name: 'Kit' }));
    expect(await screen.findByRole('switch', { name: 'evento: ligado' })).toBeDisabled();

    await userEvent.click(screen.getByRole('tab', { name: 'Prompts' }));
    expect(await screen.findByLabelText('Texto')).toBeDisabled();
    expect(screen.queryByRole('button', { name: 'Salvar nova versão' })).not.toBeInTheDocument();
  });
});

/* Logado de verdade (o botão manda o token): o perfil vem de `/admin/me`, e o
   resto da tela segue no banco em memória. */
function logadoComIndexador(rodadas: Response[]) {
  vi.stubEnv('VITE_KNOWLEDGE_API_BASE_URL', 'https://knowledge.teste');
  const chamadas: { url: string; corpo: unknown; token: string | null }[] = [];
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    if (String(url).endsWith('/admin/me')) {
      return new Response(JSON.stringify({ papel: 'administrador', nome: 'Teste' }), { status: 200 });
    }
    chamadas.push({
      url: String(url),
      corpo: JSON.parse(String(init?.body)),
      token: new Headers(init?.headers).get('Authorization'),
    });
    return rodadas.shift() ?? new Response('{}', { status: 500 });
  });
  vi.stubGlobal('fetch', fetchImpl);
  renderizarPainel({
    rota: '/agent-intelligence',
    porta: criarPortaFalsa({ sessaoInicial: SESSAO_DE_TESTE }),
    baseUrlApi: 'https://test.supabase.co/functions/v1/admin',
    fetchImpl,
    provedor: provedorComAgentes(),
  });
  return chamadas;
}

const rodada = (processados: number, restantes: boolean) =>
  new Response(JSON.stringify({ schema: 'summit_2026', processados, restantes }), { status: 200 });

describe('gerar embeddings do Summit', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
  });

  it('repete as rodadas até não sobrar trecho e diz quantos processou', async () => {
    const chamadas = logadoComIndexador([rodada(100, true), rodada(100, true), rodada(40, false)]);

    await userEvent.click(await screen.findByRole('button', { name: 'Gerar embeddings do Summit' }));

    expect(await screen.findByText('Pronto: 240 trechos ganharam embedding.')).toBeInTheDocument();
    expect(chamadas).toHaveLength(3);
    expect(chamadas[0]).toEqual({
      url: 'https://knowledge.teste/admin/knowledge_embeddings',
      corpo: { schema: 'summit_2026' },
      token: `Bearer ${SESSAO_DE_TESTE.accessToken}`,
    });
  });

  it('para na falha e conta o que já foi feito', async () => {
    logadoComIndexador([
      rodada(100, true),
      new Response(JSON.stringify({ codigo: 'indisponivel', mensagem: 'Não foi possível gerar embeddings.' }), { status: 503 }),
    ]);

    await userEvent.click(await screen.findByRole('button', { name: 'Gerar embeddings do Summit' }));

    expect(await screen.findByText('Não foi possível gerar embeddings. (100 trechos já foram processados.)')).toBeInTheDocument();
  });

  it('analista não gera embeddings', async () => {
    renderizarPainel({ rota: '/agent-intelligence', papel: 'analista', provedor: provedorComAgentes() });
    expect(await screen.findByRole('button', { name: 'Gerar embeddings do Summit' })).toBeDisabled();
  });
});
