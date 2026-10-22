import { afterEach, describe, expect, it, vi } from 'vitest';
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { AgentChannel, AgentInstructions, AgentKitBlock, AgentPrompt, AgentTool } from '@/contracts';
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
  { id: 'mindagent-web::mia_summit_2026', canal: 'mindagent-web', rota: 'mia_summit_2026', ativo: false, roteavel: false, entradasDiretas: [], observacao: 'Nasce desligado.', atualizadoEm: QUANDO },
  { id: 'whatsapp::mia_summit_2026', canal: 'whatsapp', rota: 'mia_summit_2026', ativo: false, roteavel: false, entradasDiretas: [], observacao: null, atualizadoEm: QUANDO },
  { id: 'mindagent-web::concierge_summit', canal: 'mindagent-web', rota: 'concierge_summit', ativo: true, roteavel: true, entradasDiretas: ['mind_summit_app'], observacao: null, atualizadoEm: QUANDO },
];

const KIT: AgentKitBlock[] = [
  { id: 'mia_summit_2026::evento', rota: 'mia_summit_2026', bloco: 'evento', provider: 'public.mind_kit_evento', secao: 'structured', obrigatorio: true, ativo: true, atualizadoEm: QUANDO },
  { id: 'concierge_summit::evento', rota: 'concierge_summit', bloco: 'evento', provider: 'public.mind_kit_evento', secao: 'structured', obrigatorio: true, ativo: true, atualizadoEm: QUANDO },
  { id: 'concierge_summit::product_decisioning', rota: 'concierge_summit', bloco: 'product_decisioning', provider: 'agentes.prompts', secao: 'decisioning', obrigatorio: false, ativo: true, atualizadoEm: QUANDO },
  { id: 'mia_summit_2026::tom_de_voz', rota: 'mia_summit_2026', bloco: 'tom_de_voz', provider: 'agentes.prompts', secao: 'instrucoes', obrigatorio: false, ativo: false, atualizadoEm: QUANDO },
  { id: 'mia_summit_2026::protocolo_crise_mia_summit_2026', rota: 'mia_summit_2026', bloco: 'protocolo_crise_mia_summit_2026', provider: 'agentes.prompts', secao: 'instrucoes', obrigatorio: true, ativo: true, atualizadoEm: QUANDO },
  { id: 'mia_summit_2026::buscar_intelligence', rota: 'mia_summit_2026', bloco: 'buscar_intelligence', provider: 'concierge.ferramentas', secao: 'tools', obrigatorio: false, ativo: true, atualizadoEm: QUANDO },
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

const PROMPT_VOZ: AgentPrompt = {
  ...PROMPT_MIA,
  id: 'tom_de_voz',
  chave: 'tom_de_voz',
  titulo: 'Como o Mind fala (voz da marca)',
  conteudo: 'TOM DE VOZ DO MIND',
  ativo: true,
  produtoCodigo: null,
  rota: null,
};

const PROMPT_CRISE: AgentPrompt = {
  ...PROMPT_MIA,
  id: 'protocolo_crise_mia_summit_2026',
  chave: 'protocolo_crise_mia_summit_2026',
  titulo: 'Protocolo de crise — MIA Summit 2026',
  conteudo: 'PROTOCOLO DE CRISE',
  ativo: true,
  rota: null,
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

const parte = (p: Partial<AgentInstructions['partes'][number]> & { camada: string; chave: string }) => ({
  titulo: null, promptAtivo: true, blocoAtivo: null, obrigatorio: false, ordem: null,
  chars: 10, atualizadoEm: QUANDO, compartilhadoCom: [], entra: false, ...p,
});

/* Como `mind_agent_instrucoes` devolve a MIA hoje: playbook desligado, voz
   desligada e protocolo de crise ligado. */
const INSTRUCOES_MIA: AgentInstructions = {
  id: 'mia_summit_2026',
  rota: 'mia_summit_2026',
  ok: false,
  chars: 0,
  faltando: ['playbook_mia_summit_2026'],
  texto: null,
  partes: [
    parte({ camada: 'playbook', chave: 'playbook_mia_summit_2026', titulo: PROMPT_MIA.titulo, promptAtivo: false, obrigatorio: true }),
    parte({ camada: 'instrucoes', chave: 'tom_de_voz', titulo: PROMPT_VOZ.titulo, blocoAtivo: false, ordem: 10 }),
    parte({ camada: 'instrucoes', chave: 'protocolo_crise_mia_summit_2026', titulo: PROMPT_CRISE.titulo, blocoAtivo: true, obrigatorio: true, ordem: 90 }),
  ],
};

const INSTRUCOES_CONCIERGE: AgentInstructions = {
  id: 'concierge_summit',
  rota: 'concierge_summit',
  ok: true,
  chars: 30,
  faltando: [],
  texto: 'REGRAS\n\nCONCIERGE\n\nDECISÃO',
  partes: [parte({ camada: 'playbook', chave: 'playbook_concierge_summit', titulo: 'Playbook — Concierge', obrigatorio: true, entra: true })],
};

const FERRAMENTA: AgentTool = {
  id: 'buscar_intelligence',
  nome: 'buscar_intelligence',
  descricao: 'Procura em toda a Intelligence aprovada.',
  parametros: {},
  ativo: true,
  escrita: false,
  versao: 2,
  atualizadoEm: QUANDO,
  usadoPor: ['concierge_summit', 'mia_summit_2026'],
  historico: [],
};

function provedorComAgentes() {
  const banco = criarBanco();
  banco.agent_channels = structuredClone(CANAIS);
  banco.agent_kit_blocks = structuredClone(KIT);
  banco.agent_prompts = structuredClone([PROMPT_MIA, PROMPT_VOZ, PROMPT_CRISE, PROMPT_CONCIERGE]);
  banco.agent_instructions = structuredClone([INSTRUCOES_MIA, INSTRUCOES_CONCIERGE]);
  banco.agent_tools = structuredClone([FERRAMENTA]);
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

    /* A aba Instruções abre no playbook. */
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

  it('quem não é administrador vê, mas não edita canais, dados, instruções nem skills', async () => {
    renderizarPainel({ rota: '/agent-intelligence', papel: 'editor', provedor: provedorComAgentes() });

    const grupo = await screen.findByRole('group', { name: 'Agentes' });
    await userEvent.click(within(grupo).getByRole('button', { name: 'MIA Summit 2026' }));

    await userEvent.click(screen.getByRole('tab', { name: 'Canais' }));
    expect(await screen.findByRole('switch', { name: 'MIA Summit 2026 no App (web)' })).toBeDisabled();

    await userEvent.click(screen.getByRole('tab', { name: 'Dados oficiais' }));
    expect(await screen.findByRole('switch', { name: 'evento: ligado' })).toBeDisabled();

    await userEvent.click(screen.getByRole('tab', { name: 'Skills' }));
    expect(await screen.findByRole('switch', { name: 'buscar_intelligence: ligada em MIA Summit 2026' })).toBeDisabled();

    await userEvent.click(screen.getByRole('tab', { name: 'Instruções' }));
    expect(await screen.findByLabelText('Texto')).toBeDisabled();
    expect(screen.queryByRole('button', { name: 'Salvar nova versão' })).not.toBeInTheDocument();
    expect(screen.getByRole('switch', { name: /Protocolo de crise.*ligado em MIA Summit 2026/ })).toBeDisabled();
    expect(screen.queryByRole('button', { name: 'Criar versão própria de MIA Summit 2026' })).not.toBeInTheDocument();
  });
});

describe('o que o agente recebe (aba Instruções)', () => {
  async function abrirMia() {
    const provedor = provedorComAgentes();
    renderizarPainel({ rota: '/agent-intelligence', provedor });
    const grupo = await screen.findByRole('group', { name: 'Agentes' });
    await userEvent.click(within(grupo).getByRole('button', { name: 'MIA Summit 2026' }));
    return provedor;
  }

  it('mostra as partes na ordem real e diz por que a MIA não recebe nada hoje', async () => {
    await abrirMia();
    const lista = await screen.findByRole('list', { name: 'Partes das instruções' });
    const nomes = within(lista).getAllByRole('listitem').map((li) => li.textContent ?? '');
    expect(nomes[0]).toMatch(/1\. Playbook.*Playbook de MIA Summit 2026/);
    expect(nomes[1]).toMatch(/2\. Instrução.*Como o Mind fala/);
    expect(nomes[2]).toMatch(/3\. Instrução · proteção.*Protocolo de crise/);
    expect(nomes[3]).toMatch(/Formato da resposta e travas de segurança/);
    expect(screen.getByText(/não recebe instrução e por isso não responde: falta playbook_mia_summit_2026/)).toBeInTheDocument();
    expect(screen.getByRole('switch', { name: 'Como o Mind fala (voz da marca): ligado em MIA Summit 2026' })).not.toBeChecked();
  });

  it('ligar a voz do Mind só neste agente', async () => {
    const provedor = await abrirMia();
    await userEvent.click(await screen.findByRole('switch', { name: 'Como o Mind fala (voz da marca): ligado em MIA Summit 2026' }));
    await waitFor(() =>
      expect(provedor.banco.agent_kit_blocks.find((b) => b.id === 'mia_summit_2026::tom_de_voz')?.ativo).toBe(true),
    );
  });

  it('desligar o protocolo de crise pede confirmação', async () => {
    const provedor = await abrirMia();
    await userEvent.click(await screen.findByRole('switch', { name: /Protocolo de crise.*ligado em MIA Summit 2026/ }));

    expect(await screen.findByText(/Este texto é de proteção/)).toBeInTheDocument();
    const crise = () => provedor.banco.agent_kit_blocks.find((b) => b.id === 'mia_summit_2026::protocolo_crise_mia_summit_2026');
    expect(crise()?.ativo).toBe(true);

    await userEvent.click(screen.getByRole('button', { name: 'Desligar' }));
    await waitFor(() => expect(crise()?.ativo).toBe(false));
  });

  it('abre a voz do Mind para ler e cria uma voz própria a partir dela', async () => {
    const provedor = await abrirMia();
    await userEvent.click(await screen.findByRole('button', { name: /Como o Mind fala/ }));
    expect(await screen.findByDisplayValue('TOM DE VOZ DO MIND')).toBeInTheDocument();
    expect(screen.getByText(/o liga\/desliga da lista vale só para este/)).toBeInTheDocument();

    const botoes = screen.getAllByRole('button', { name: 'Criar versão própria de MIA Summit 2026' });
    await userEvent.click(botoes[0]);
    await userEvent.click(await screen.findByRole('button', { name: 'Criar' }));

    await waitFor(() => {
      const criada = provedor.banco.agent_instructions.find((x) => (x as unknown as { chave?: string }).chave === 'tom_de_voz_mia_summit_2026');
      expect(criada).toMatchObject({
        rota: 'mia_summit_2026',
        substitui: 'tom_de_voz',
        conteudo: 'TOM DE VOZ DO MIND',
        titulo: 'Como o Mind fala (voz da marca) — MIA Summit 2026',
      });
    });
  });

  it('o texto completo que o agente recebe abre num clique', async () => {
    renderizarPainel({ rota: '/agent-intelligence', provedor: provedorComAgentes() });
    await screen.findByRole('group', { name: 'Agentes' });
    /* Concierge é o primeiro da lista. */
    await userEvent.click(await screen.findByRole('button', { name: 'Ver o texto completo que ele recebe' }));
    expect(screen.getByLabelText('Texto completo das instruções')).toHaveTextContent('CONCIERGE');
  });
});

describe('skills', () => {
  it('o administrador reescreve a descrição de uma skill', async () => {
    const provedor = provedorComAgentes();
    renderizarPainel({ rota: '/agent-intelligence', provedor });
    const grupo = await screen.findByRole('group', { name: 'Agentes' });
    await userEvent.click(within(grupo).getByRole('button', { name: 'MIA Summit 2026' }));
    await userEvent.click(screen.getByRole('tab', { name: 'Skills' }));
    await userEvent.click(await screen.findByRole('button', { name: 'Ver e editar a descrição' }));

    const campo = await screen.findByLabelText('Descrição');
    expect(screen.getByText(/Mudar a descrição muda todos/)).toBeInTheDocument();
    await userEvent.clear(campo);
    await userEvent.type(campo, 'Nova descrição');
    await userEvent.click(screen.getByRole('button', { name: 'Salvar nova descrição' }));

    await waitFor(() => expect(provedor.banco.agent_tools[0].descricao).toBe('Nova descrição'));
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

    await userEvent.click(await screen.findByRole('tab', { name: 'Conhecimento' }));
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

    await userEvent.click(await screen.findByRole('tab', { name: 'Conhecimento' }));
    await userEvent.click(await screen.findByRole('button', { name: 'Gerar embeddings do Summit' }));

    expect(await screen.findByText('Não foi possível gerar embeddings. (100 trechos já foram processados.)')).toBeInTheDocument();
  });

  it('analista não gera embeddings', async () => {
    renderizarPainel({ rota: '/agent-intelligence', papel: 'analista', provedor: provedorComAgentes() });
    await userEvent.click(await screen.findByRole('tab', { name: 'Conhecimento' }));
    expect(await screen.findByRole('button', { name: 'Gerar embeddings do Summit' })).toBeDisabled();
  });
});

describe('playground', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
  });

  it('abre uma conversa de teste com o agente e mostra o que ele respondeu e usou', async () => {
    vi.stubEnv('VITE_SUPABASE_URL', 'https://test.supabase.co');
    const pedidos: { url: string; corpo: Record<string, unknown>; token: string | null }[] = [];
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      if (String(url).endsWith('/admin/me')) {
        return new Response(JSON.stringify({ papel: 'administrador', nome: 'Teste' }), { status: 200 });
      }
      const corpo = JSON.parse(String(init?.body)) as Record<string, unknown>;
      pedidos.push({ url: String(url), corpo, token: new Headers(init?.headers).get('Authorization') });
      return new Response(JSON.stringify({
        ok: true, answer: 'A palestra disse que liderança começa pelo descanso.',
        session: { id: 's1', conversation_id: 'c1', token: 't1' }, device_id: 'd1',
        rota: 'mia_summit_2026', rota_origem: 'rota_ativa', teste: true,
        ferramentas: [{ nome: 'buscar_intelligence', ok: true }],
      }), { status: 200 });
    });
    vi.stubGlobal('fetch', fetchImpl);
    renderizarPainel({
      rota: '/agent-intelligence',
      porta: criarPortaFalsa({ sessaoInicial: SESSAO_DE_TESTE }),
      baseUrlApi: 'https://test.supabase.co/functions/v1/admin',
      fetchImpl,
      provedor: provedorComAgentes(),
    });

    const grupo = await screen.findByRole('group', { name: 'Agentes' });
    await userEvent.click(within(grupo).getByRole('button', { name: 'MIA Summit 2026' }));
    await userEvent.click(screen.getByRole('tab', { name: 'Playground' }));
    await userEvent.type(await screen.findByLabelText('Sua mensagem'), 'O que disseram sobre burnout?');
    await userEvent.click(screen.getByRole('button', { name: 'Enviar' }));

    expect(await screen.findByText('A palestra disse que liderança começa pelo descanso.')).toBeInTheDocument();
    expect(screen.getByText('respondeu: mia_summit_2026')).toBeInTheDocument();
    expect(screen.getByText('skill: buscar_intelligence')).toBeInTheDocument();
    expect(pedidos).toHaveLength(1);
    expect(pedidos[0].url).toBe('https://test.supabase.co/functions/v1/mindagent-chat');
    expect(pedidos[0].token).toBe(`Bearer ${SESSAO_DE_TESTE.accessToken}`);
    expect(pedidos[0].corpo.playground).toEqual({ rota: 'mia_summit_2026' });
    expect(pedidos[0].corpo.session).toBeUndefined();

    /* A segunda mensagem segue na mesma conversa de teste. */
    await userEvent.type(screen.getByLabelText('Sua mensagem'), 'E sobre liderança?');
    await userEvent.click(screen.getByRole('button', { name: 'Enviar' }));
    await waitFor(() => expect(pedidos).toHaveLength(2));
    expect(pedidos[1].corpo.session).toEqual({ id: 's1', conversation_id: 'c1', token: 't1' });
    expect(pedidos[1].corpo.playground).toBeUndefined();
  });

  it('explica quando o agente não tem o que precisa para responder', async () => {
    vi.stubEnv('VITE_SUPABASE_URL', 'https://test.supabase.co');
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/admin/me')) {
        return new Response(JSON.stringify({ papel: 'administrador', nome: 'Teste' }), { status: 200 });
      }
      return new Response(JSON.stringify({ ok: false, error: { code: 'rota_indisponivel', message: 'x' } }), { status: 503 });
    });
    vi.stubGlobal('fetch', fetchImpl);
    renderizarPainel({
      rota: '/agent-intelligence',
      porta: criarPortaFalsa({ sessaoInicial: SESSAO_DE_TESTE }),
      baseUrlApi: 'https://test.supabase.co/functions/v1/admin',
      fetchImpl,
      provedor: provedorComAgentes(),
    });
    const grupo = await screen.findByRole('group', { name: 'Agentes' });
    await userEvent.click(within(grupo).getByRole('button', { name: 'MIA Summit 2026' }));
    await userEvent.click(screen.getByRole('tab', { name: 'Playground' }));
    await userEvent.type(await screen.findByLabelText('Sua mensagem'), 'oi');
    await userEvent.click(screen.getByRole('button', { name: 'Enviar' }));
    expect(await screen.findByText(/confira na aba Instruções se o playbook está ligado/)).toBeInTheDocument();
  });

  it('quem não é administrador não testa', async () => {
    renderizarPainel({ rota: '/agent-intelligence', papel: 'editor', provedor: provedorComAgentes() });
    const grupo = await screen.findByRole('group', { name: 'Agentes' });
    await userEvent.click(within(grupo).getByRole('button', { name: 'MIA Summit 2026' }));
    await userEvent.click(screen.getByRole('tab', { name: 'Playground' }));
    expect(await screen.findByLabelText('Sua mensagem')).toBeDisabled();
  });
});
