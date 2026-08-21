import { describe, expect, it, vi } from 'vitest';
import { screen, waitFor, within } from '@testing-library/react';
import type { ResumoPainel } from '@/contracts';
import { ehErroAdmin } from '@/contracts';
import { HybridAdminDataProvider, RECURSOS_REAIS } from '@/services/hybrid-admin-data-provider';
import { MockAdminDataProvider } from '@/services/mock-admin-data-provider';
import type { AdminDataProvider } from '@/services/admin-data-provider';
import { NOMES_RECURSOS } from '@/contracts';
import { SESSAO_DE_TESTE, lista, renderizarHibrido } from './utils';

/* Números propositalmente diferentes dos do mock: se a tela mostrar
   777, veio da API. */
const RESUMO_DA_API: ResumoPainel = {
  geradoEm: '2026-08-20T15:00:00.000Z',
  metricas: [
    { chave: 'sessoes', rotulo: 'Sessões', valor: 777, destino: '/programacao' },
    { chave: 'palestrantes', rotulo: 'Palestrantes', valor: 888, destino: '/palestrantes' },
  ],
  pendencias: [
    {
      categoria: 'sessoes_sem_espaco',
      titulo: 'Sessões sem espaço',
      descricao: 'Vindo da API administrativa.',
      total: 3,
      itens: [{ id: 's1', rotulo: 'Sessão da API', destino: '/programacao/s1' }],
      destino: '/programacao',
    },
  ],
  alertas: [
    {
      id: 'alerta_api',
      nivel: 'atencao',
      titulo: 'Alerta vindo do backend',
      descricao: 'Este texto não existe no mock.',
    },
  ],
};

const SESSAO_DA_API = {
  id: 'ses_api_1',
  titulo: 'Sessão vinda da API',
  descricao: 'Registro real.',
  dia: '2026-09-16',
  inicio: '10:00',
  fim: '11:00',
  espacoId: 'esp_api_1',
  tipo: 'credenciamento',
  formato: 'remoto',
  trilhas: ['mind'],
  temas: [],
  palestranteIds: [],
  quemTexto: 'Equipe',
  necessitaReserva: false,
  vagasTotais: null,
  vagasDisponiveis: null,
  nivel: null,
  resultadosEsperados: [],
  status: 'publicado',
  publicadoEm: '2026-08-01T00:00:00.000Z',
  publicadoPor: 'API',
  criadoEm: '2026-08-01T00:00:00.000Z',
  atualizadoEm: '2026-08-10T00:00:00.000Z',
  atualizadoPor: 'API',
};

const ESPACO_DA_API = {
  id: 'esp_api_1',
  nome: 'Portaria Norte',
  slug: 'portaria-norte',
  tipo: 'acesso',
  aliases: ['entrada norte'],
  descricao: '',
  comoChegar: 'Pela lateral do pavilhão.',
  localPrincipal: 'Pavilhão 3',
  espacoPaiId: null,
  andar: 'Térreo',
  coordenadaX: 10,
  coordenadaY: 20,
  acessivel: true,
  observacaoAcessibilidade: '',
  ativo: true,
  criadoEm: '2026-08-01T00:00:00.000Z',
  atualizadoEm: '2026-08-01T00:00:00.000Z',
  atualizadoPor: 'API',
};

const ROTAS_BASICAS = {
  '/admin/dashboard': { corpo: RESUMO_DA_API },
  '/admin/sessions': { corpo: lista([SESSAO_DA_API]) },
  '/admin/speakers': { corpo: lista([]) },
  '/admin/spaces': { corpo: lista([ESPACO_DA_API]) },
  '/admin/themes': { corpo: lista([{ id: 'cultura', codigo: 'cultura', rotulo: 'Cultura' }]) },
  '/admin/event': { corpo: lista([]) },
};

describe('encaminhamento seletivo', () => {
  function montar() {
    const mock = new MockAdminDataProvider({ latenciaMs: 0 });
    const chamadas: string[] = [];
    const http = new Proxy({} as AdminDataProvider, {
      get(_alvo, prop: string) {
        if (prop === 'modo') return 'http';
        if (prop === 'origemDoRecurso') return () => 'http';
        return (...args: unknown[]) => {
          chamadas.push(`${prop}:${String(args[0] ?? '')}`);
          if (prop === 'getDashboard') return Promise.resolve(RESUMO_DA_API);
          return Promise.resolve(prop === 'list' ? lista([]) : {});
        };
      },
    });
    return { hibrido: new HybridAdminDataProvider(http, mock), chamadas, mock };
  }

  it('os cinco recursos reais desta etapa são exatamente os combinados', () => {
    expect([...RECURSOS_REAIS]).toEqual(['event', 'sessions', 'speakers', 'spaces', 'themes']);
  });

  it('origemDoRecurso separa real de demonstração recurso por recurso', () => {
    const { hibrido } = montar();

    for (const recurso of RECURSOS_REAIS) {
      expect(hibrido.origemDoRecurso(recurso), recurso).toBe('http');
    }
    for (const recurso of NOMES_RECURSOS.filter((r) => !RECURSOS_REAIS.includes(r as never))) {
      expect(hibrido.origemDoRecurso(recurso), recurso).toBe('mock');
    }
  });

  it('anuncia o modo como hybrid — nem mock, nem http', () => {
    expect(montar().hibrido.modo).toBe('hybrid');
  });

  it('leitura e escrita dos recursos reais vão para o HTTP', async () => {
    const { hibrido, chamadas } = montar();

    await hibrido.list('sessions');
    await hibrido.get('sessions', 'x');
    await hibrido.create('sessions', {});
    await hibrido.update('sessions', 'x', {});
    await hibrido.publish('sessions', 'x');
    await hibrido.archive('sessions', 'x');
    await hibrido.list('speakers');
    await hibrido.update('speakers', 'x', {});
    await hibrido.list('spaces');
    await hibrido.archive('spaces', 'x');
    await hibrido.list('event');
    await hibrido.update('event', 'x', {});
    await hibrido.list('themes');
    await hibrido.getDashboard();

    expect(chamadas).toEqual([
      'list:sessions',
      'get:sessions',
      'create:sessions',
      'update:sessions',
      'publish:sessions',
      'archive:sessions',
      'list:speakers',
      'update:speakers',
      'list:spaces',
      'archive:spaces',
      'list:event',
      'update:event',
      'list:themes',
      'getDashboard:',
    ]);
  });

  it('os outros recursos não passam pelo HTTP nem na escrita', async () => {
    const { hibrido, chamadas, mock } = montar();

    const oferta = await hibrido.update('offers', 'ofe_mind', { nome: 'Editado' });
    expect(oferta.nome).toBe('Editado');
    await hibrido.list('booths');
    await hibrido.archive('content', 'con_produtos');
    await hibrido.requestReindex('doc_mapa_pdf');

    expect(chamadas).toEqual([]);
    expect((await mock.get('offers', 'ofe_mind')).nome).toBe('Editado');
  });

  it('temas são somente leitura: escrita é recusada com o motivo', async () => {
    const { hibrido, chamadas } = montar();

    await expect(hibrido.update('themes', 'cultura', {})).rejects.toSatisfy(
      (e: unknown) => ehErroAdmin(e) && /somente leitura/i.test(e.message),
    );
    await expect(hibrido.create('themes', {})).rejects.toSatisfy(
      (e: unknown) => ehErroAdmin(e) && /GET \/admin\/themes/.test(e.message),
    );
    expect(chamadas).toEqual([]);
  });

  it('operação sem endpoint publicado é recusada antes de sair', async () => {
    const { hibrido, chamadas } = montar();

    /* A API não expõe publish para espaços, nem create para o evento. */
    await expect(hibrido.publish('spaces', 'esp_1')).rejects.toSatisfy(
      (e: unknown) => ehErroAdmin(e) && /não expõe publicar para spaces/.test(e.message),
    );
    await expect(hibrido.create('event', {})).rejects.toSatisfy(
      (e: unknown) => ehErroAdmin(e) && /não expõe criar para event/.test(e.message),
    );
    expect(chamadas).toEqual([]);
  });
});

describe('módulos reais na tela', () => {
  it('a visão geral mostra os números que vieram da API', async () => {
    renderizarHibrido({ rotas: ROTAS_BASICAS });

    expect(await screen.findByText('777')).toBeVisible();
    expect(screen.getByText('888')).toBeVisible();
    expect(screen.getByText('Alerta vindo do backend')).toBeVisible();
    /* 53 é o total do mock: se aparecesse, o dashboard não seria real. */
    expect(screen.queryByText('53')).not.toBeInTheDocument();
  });

  it('a programação lista o que a API devolveu, não o mock', async () => {
    const { falso } = renderizarHibrido({ rota: '/programacao', rotas: ROTAS_BASICAS });

    const linha = await screen.findByTestId('linha-ses_api_1');
    expect(within(linha).getByText('Sessão vinda da API')).toBeVisible();
    expect(screen.queryByTestId('linha-ses_d1-09_00-abertura')).not.toBeInTheDocument();
    expect(falso.ultima('/admin/sessions')).toBeDefined();
  });

  it('espaços vêm da API, com o tipo real', async () => {
    renderizarHibrido({ rota: '/espacos', rotas: ROTAS_BASICAS });

    const linha = await screen.findByTestId('linha-esp_api_1');
    expect(within(linha).getByText('Portaria Norte')).toBeVisible();
    expect(within(linha).getByText('Acesso')).toBeVisible();
    expect(screen.queryByTestId('linha-esp_arena-mind')).not.toBeInTheDocument();
  });

  it('a listagem real é marcada como real e a simulada como demonstração', async () => {
    const real = renderizarHibrido({ rota: '/palestrantes', rotas: ROTAS_BASICAS });
    expect(await screen.findByTestId('selo-origem-real')).toHaveTextContent('dados reais');
    expect(screen.queryByTestId('selo-origem-mock')).not.toBeInTheDocument();
    real.unmount();

    renderizarHibrido({ rota: '/ofertas', rotas: ROTAS_BASICAS });
    expect(await screen.findByTestId('selo-origem-mock')).toHaveTextContent('demonstração');
    expect(screen.queryByTestId('selo-origem-real')).not.toBeInTheDocument();
  });

  it('temas reais alimentam o filtro de tema da programação', async () => {
    const { falso } = renderizarHibrido({ rota: '/programacao', rotas: ROTAS_BASICAS });

    await screen.findByTestId('linha-ses_api_1');
    await waitFor(() => expect(falso.ultima('/admin/themes')).toBeDefined());
  });
});

describe('módulos que continuam em demonstração', () => {
  it('ofertas, estandes e documentos não tocam a API', async () => {
    const { falso, unmount } = renderizarHibrido({ rota: '/ofertas', rotas: ROTAS_BASICAS });
    const linha = await screen.findByTestId('linha-ofe_mind');
    expect(within(linha).getByText(/R\$\s*890,00/)).toBeVisible();
    unmount();

    const segundo = renderizarHibrido({ rota: '/documentos', rotas: ROTAS_BASICAS });
    await screen.findByTestId('linha-doc_mapa_pdf');

    for (const chamada of [...falso.chamadas, ...segundo.falso.chamadas]) {
      expect(chamada.url).toMatch(/\/admin\/(me|dashboard|sessions|speakers|spaces|themes|event)/);
    }
  });

  it('salvar um estande continua sem sair do navegador', async () => {
    const { falso, mock } = renderizarHibrido({ rota: '/estandes/est_mind', rotas: ROTAS_BASICAS });

    await screen.findByDisplayValue('Mind Institute');
    const antes = falso.chamadas.filter((c) => c.metodo !== 'GET').length;

    await mock.update('booths', 'est_mind', { contato: 'novo@exemplo.com.br' });

    expect(falso.chamadas.filter((c) => c.metodo !== 'GET').length).toBe(antes);
    expect((await mock.get('booths', 'est_mind')).contato).toBe('novo@exemplo.com.br');
  });
});

describe('sem queda para o mock', () => {
  it('erro na listagem real mostra a tela de erro, não dado simulado', async () => {
    renderizarHibrido({
      rota: '/programacao',
      rotas: {
        ...ROTAS_BASICAS,
        '/admin/sessions': {
          status: 503,
          corpo: { codigo: 'indisponivel', mensagem: 'Em manutenção.' },
        },
      },
    });

    expect(await screen.findByText('Serviço indisponível')).toBeVisible();
    expect(screen.getByText('Em manutenção.')).toBeVisible();
    /* Nenhuma linha do mock aparece no lugar. */
    expect(screen.queryByTestId('linha-ses_d1-09_00-abertura')).not.toBeInTheDocument();
    expect(screen.queryByText('Abertura')).not.toBeInTheDocument();
  });

  it('erro de rede em espaços também não cai no mock', async () => {
    renderizarHibrido({
      rota: '/espacos',
      rotas: { ...ROTAS_BASICAS, '/admin/spaces': { erroDeRede: true } },
    });

    expect(await screen.findByText('Não foi possível carregar')).toBeVisible();
    expect(screen.queryByText('Arena Mind')).not.toBeInTheDocument();
  });

  it('dashboard fora do contrato vira erro, não número inventado', async () => {
    renderizarHibrido({
      rotas: { ...ROTAS_BASICAS, '/admin/dashboard': { corpo: { qualquer: 'coisa' } } },
    });

    expect(await screen.findByText('Algo deu errado')).toBeVisible();
    expect(screen.getByText(/não segue o contrato do painel/i)).toBeVisible();
    expect(screen.queryByText('53')).not.toBeInTheDocument();
  });
});

describe('a faixa do topo', () => {
  it('nomeia os módulos reais e os simulados', async () => {
    renderizarHibrido({ rotas: ROTAS_BASICAS });

    const faixa = await screen.findByTestId('faixa-modo');
    expect(faixa).toHaveTextContent(
      'Evento, programação, palestrantes e espaços reais · Demais módulos em demonstração.',
    );
    expect(faixa).toHaveTextContent(/leem e gravam na API administrativa/i);
    expect(faixa).toHaveTextContent(/memória do navegador/i);
  });
});

describe('o token no modo híbrido', () => {
  it('vai no Authorization das chamadas reais e nunca na URL', async () => {
    const { falso } = renderizarHibrido({ rota: '/programacao', rotas: ROTAS_BASICAS });

    await screen.findByTestId('linha-ses_api_1');
    await waitFor(() => expect(falso.ultima('/admin/sessions')).toBeDefined());

    for (const chamada of falso.chamadas) {
      expect(chamada.cabecalhos.Authorization).toBe(`Bearer ${SESSAO_DE_TESTE.accessToken}`);
      expect(chamada.cabecalhos.apikey).toBe('sb_publishable_de_teste');
      expect(chamada.url).not.toContain(SESSAO_DE_TESTE.accessToken);
      expect(chamada.url.toLowerCase()).not.toContain('token');
    }
  });

  it('não aparece em nenhuma saída de console', async () => {
    const escrito: string[] = [];
    const capturar = (...args: unknown[]) => escrito.push(args.map(String).join(' '));
    const espioes = (['log', 'info', 'warn', 'error', 'debug'] as const).map((nivel) =>
      vi.spyOn(console, nivel).mockImplementation(capturar),
    );

    try {
      const { falso } = renderizarHibrido({ rota: '/programacao', rotas: ROTAS_BASICAS });
      await screen.findByTestId('linha-ses_api_1');
      await waitFor(() => expect(falso.ultima('/admin/sessions')).toBeDefined());
    } finally {
      espioes.forEach((e) => e.mockRestore());
    }

    const tudo = escrito.join('\n');
    expect(tudo).not.toContain(SESSAO_DE_TESTE.accessToken);
    expect(tudo).not.toMatch(/bearer/i);
    expect(tudo).not.toMatch(/sb_publishable/i);
  });
});
