import { describe, expect, it } from 'vitest';
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ehErroAdmin } from '@/contracts';
import { HttpAdminDataProvider } from '@/services/http-admin-data-provider';
import {
  API_FALSA,
  CHAVE_FALSA,
  SESSAO_DE_TESTE,
  criarFetchFalso,
  lista,
  renderizarHibrido,
} from './utils';

/* ============================================================
   API REAL — verbos, cabeçalhos e códigos de erro
   ============================================================
   Tudo hermético: um `fetch` falso registra método, URL e cabeçalhos.
   Nenhuma requisição sai da máquina e o Supabase real nunca é tocado. */

const EVENTO_DA_API = {
  id: 'evt_real',
  nome: 'Mind Summit 2026',
  slug: 'mind-summit-2026',
  dataInicio: '2026-09-16',
  dataFim: '2026-09-17',
  /* O cadastro oficial diz Transamérica; a cópia congelada em
     dados/summit.json diz São Paulo Expo. A divergência é real. */
  local: 'Pavilhão 3 · Transamérica Expo Center',
  cidade: 'São Paulo',
  fusoHorario: 'America/Sao_Paulo',
  descricao: 'Evento real.',
  regraReserva: 'Reservas caem 5 minutos antes.',
  regraVagas: 'Workshops têm vagas limitadas.',
  ativo: true,
  criadoEm: '2026-08-01T00:00:00.000Z',
  atualizadoEm: '2026-08-10T00:00:00.000Z',
  atualizadoPor: 'API',
};

const SESSAO_DA_API = {
  id: 'ses_real_1',
  titulo: 'Sessão real',
  descricao: 'Descrição real.',
  dia: '2026-09-16',
  inicio: '10:00',
  fim: '11:00',
  espacoId: 'esp_real_1',
  tipo: 'palestra',
  formato: 'presencial',
  trilhas: ['mind'],
  temas: ['cultura'],
  palestranteIds: [],
  quemTexto: 'Alguém',
  necessitaReserva: false,
  vagasTotais: null,
  vagasDisponiveis: null,
  nivel: null,
  resultadosEsperados: [],
  status: 'em_revisao',
  publicadoEm: null,
  publicadoPor: null,
  criadoEm: '2026-08-01T00:00:00.000Z',
  atualizadoEm: '2026-08-12T09:00:00.000Z',
  atualizadoPor: 'API',
};

const ROTAS = {
  '/admin/dashboard': {
    corpo: { metricas: [], pendencias: [], alertas: [], geradoEm: '2026-08-20T00:00:00Z' },
  },
  '/admin/event': { corpo: lista([EVENTO_DA_API]) },
  '/admin/sessions': { corpo: lista([SESSAO_DA_API], { total: 67, porPagina: 50 }) },
  '/admin/speakers': { corpo: lista([]) },
  '/admin/spaces': { corpo: lista([]) },
  '/admin/themes': { corpo: lista([{ id: 'cultura', codigo: 'cultura', rotulo: 'Cultura' }]) },
};

/** Provedor HTTP puro, para afirmar verbo, caminho e cabeçalho. */
function criarProvedorHttp(
  rotas: Record<string, { status?: number; corpo?: unknown; erroDeRede?: boolean }> = {},
) {
  const falso = criarFetchFalso({ '/admin/': { corpo: {} }, ...rotas });
  const http = new HttpAdminDataProvider({
    baseUrl: API_FALSA,
    fetchImpl: falso.fetch,
    chavePublicavel: CHAVE_FALSA,
    obterToken: async () => SESSAO_DE_TESTE.accessToken,
  });
  return { http, falso };
}

describe('verbos e caminhos dos recursos reais', () => {
  it('listagem, item, criação, atualização, publicação e arquivamento', async () => {
    const { http, falso } = criarProvedorHttp({
      '/admin/sessions': { corpo: lista([SESSAO_DA_API]) },
    });

    await http.list('sessions');
    await http.get('sessions', 'ses_real_1');
    await http.create('sessions', { titulo: 'Nova' });
    await http.update('sessions', 'ses_real_1', { titulo: 'Editada' });
    await http.publish('sessions', 'ses_real_1');
    await http.archive('sessions', 'ses_real_1');
    await http.list('speakers');
    await http.get('speakers', 'pal_1');
    await http.create('speakers', { nome: 'Nova pessoa' });
    await http.update('speakers', 'pal_1', { nome: 'Editada' });
    await http.publish('speakers', 'pal_1');
    await http.archive('speakers', 'pal_1');
    await http.list('spaces');
    await http.create('spaces', { nome: 'Novo espaço' });
    await http.archive('spaces', 'esp_1');
    await http.list('event');
    await http.get('event', 'evt_real');
    await http.update('event', 'evt_real', { cidade: 'São Paulo' });
    await http.list('themes');

    expect(falso.chamadas.map((c) => `${c.metodo} ${c.url.replace(API_FALSA, '')}`)).toEqual([
      'GET /admin/sessions',
      'GET /admin/sessions/ses_real_1',
      'POST /admin/sessions',
      'PATCH /admin/sessions/ses_real_1',
      'POST /admin/sessions/ses_real_1/publish',
      'POST /admin/sessions/ses_real_1/archive',
      'GET /admin/speakers',
      'GET /admin/speakers/pal_1',
      'POST /admin/speakers',
      'PATCH /admin/speakers/pal_1',
      'POST /admin/speakers/pal_1/publish',
      'POST /admin/speakers/pal_1/archive',
      'GET /admin/spaces',
      'POST /admin/spaces',
      'POST /admin/spaces/esp_1/archive',
      'GET /admin/event',
      'GET /admin/event/evt_real',
      'PATCH /admin/event/evt_real',
      'GET /admin/themes',
    ]);
  });

  it('toda escrita manda If-Unmodified-Since-Version com o atualizadoEm visto', async () => {
    const { http, falso } = criarProvedorHttp();
    const versao = '2026-08-12T09:00:00.000Z';

    await http.update('sessions', 'x', { titulo: 'a' }, { atualizadoEmEsperado: versao });
    await http.publish('sessions', 'x', { atualizadoEmEsperado: versao });
    await http.archive('spaces', 'y', { atualizadoEmEsperado: versao });

    for (const chamada of falso.chamadas) {
      expect(chamada.cabecalhos['If-Unmodified-Since-Version'], chamada.url).toBe(versao);
    }
  });

  it('sem versão conhecida, o header não é inventado', async () => {
    const { http, falso } = criarProvedorHttp();
    await http.update('sessions', 'x', { titulo: 'a' });
    expect(falso.chamadas[0].cabecalhos['If-Unmodified-Since-Version']).toBeUndefined();
  });

  it('token no Authorization e publicável no apikey, em toda chamada', async () => {
    const { http, falso } = criarProvedorHttp();

    await http.list('sessions');
    await http.update('sessions', 'x', {});

    for (const chamada of falso.chamadas) {
      expect(chamada.cabecalhos.Authorization).toBe(`Bearer ${SESSAO_DE_TESTE.accessToken}`);
      expect(chamada.cabecalhos.apikey).toBe(CHAVE_FALSA);
      expect(chamada.url).not.toContain(SESSAO_DE_TESTE.accessToken);
      expect(chamada.url).not.toContain(CHAVE_FALSA);
    }
  });

  it('preenche campo ausente sem inventar valor', async () => {
    /* A API devolve uma sessão sem `temas` nem `trilhas`: a listagem não
       pode quebrar num `.map` de undefined, e o que veio fica intacto. */
    const { http } = criarProvedorHttp({
      '/admin/sessions': {
        corpo: lista([{ id: 'ses_x', titulo: 'Só o essencial', tipo: 'mesa_redonda' }]),
      },
    });

    const { itens } = await http.list('sessions');
    expect(itens[0].temas).toEqual([]);
    expect(itens[0].trilhas).toEqual([]);
    expect(itens[0].titulo).toBe('Só o essencial');
    /* Categoria fora do vocabulário do painel NÃO é convertida. */
    expect(itens[0].tipo).toBe('mesa_redonda');
  });
});

describe('filtros reais da programação', () => {
  it('todos os filtros combinados chegam na query string', async () => {
    const { falso } = renderizarHibrido({
      rota:
        '/programacao?busca=clareza&dia=2026-09-16&espacoId=esp_real_1' +
        '&tema=cultura&palestranteId=pal_1&tipo=palestra&status=em_revisao&pagina=2',
      rotas: ROTAS,
    });

    /* Duas consultas saem para `sessions`: a listagem filtrada e a
       grade inteira usada na detecção de conflito. A do teste é a que
       carrega os filtros. */
    await waitFor(() => expect(falso.ultima('busca=clareza')).toBeDefined());
    const url = new URL(falso.ultima('busca=clareza')!.url);
    const p = url.searchParams;

    expect(p.get('busca')).toBe('clareza');
    expect(p.get('dia')).toBe('2026-09-16');
    expect(p.get('espacoId')).toBe('esp_real_1');
    expect(p.get('tema')).toBe('cultura');
    expect(p.get('palestranteId')).toBe('pal_1');
    expect(p.get('tipo')).toBe('palestra');
    expect(p.get('status')).toBe('em_revisao');
    expect(p.get('ordenar')).toBe('dia');
    expect(p.get('pagina')).toBe('2');
    expect(p.get('porPagina')).toBe('50');
  });

  it('a paginação usa o total que a API informou', async () => {
    renderizarHibrido({ rota: '/programacao', rotas: ROTAS });

    await screen.findByTestId('linha-ses_real_1');
    /* total 67, porPagina 50 → duas páginas. */
    expect(screen.getByTestId('contagem-registros')).toHaveTextContent('67 registro(s)');
    expect(screen.getByTestId('contagem-registros')).toHaveTextContent('página 1 de 2');
    expect(screen.getByRole('button', { name: /próxima/i })).toBeEnabled();
    expect(screen.getByRole('button', { name: /anterior/i })).toBeDisabled();
  });

  it('avançar de página refaz a busca com pagina=2', async () => {
    const usuario = userEvent.setup();
    const { falso } = renderizarHibrido({ rota: '/programacao', rotas: ROTAS });

    await screen.findByTestId('linha-ses_real_1');
    await usuario.click(screen.getByRole('button', { name: /próxima/i }));

    await waitFor(() => {
      const url = falso.ultima('/admin/sessions?')?.url ?? '';
      expect(new URL(url).searchParams.get('pagina')).toBe('2');
    });
  });
});

describe('códigos de erro da API real', () => {
  it('401 devolve ao login com aviso de sessão expirada', async () => {
    const { porta } = renderizarHibrido({
      rota: '/programacao',
      rotas: {
        ...ROTAS,
        '/admin/sessions': {
          status: 401,
          corpo: { codigo: 'sem_permissao', mensagem: 'Sessão inválida ou expirada.' },
        },
      },
    });

    expect(await screen.findByText(/sua sessão expirou/i)).toBeVisible();
    /* A programação faz duas consultas (a lista e a grade inteira para
       detectar conflito); as duas levam 401, e as duas mandam sair. O
       que importa é a sessão ter sido descartada. */
    await waitFor(() => expect(porta.chamadas.sair).toBeGreaterThanOrEqual(1));
  });

  it('403 mostra sem permissão, sem cair no mock', async () => {
    renderizarHibrido({
      rota: '/palestrantes',
      rotas: {
        ...ROTAS,
        '/admin/speakers': {
          status: 403,
          corpo: { codigo: 'sem_permissao', mensagem: 'Seu papel não acessa palestrantes.' },
        },
      },
    });

    expect(await screen.findByText('Sem permissão')).toBeVisible();
    expect(screen.getByText('Seu papel não acessa palestrantes.')).toBeVisible();
    expect(screen.queryByText('Amy Edmondson')).not.toBeInTheDocument();
  });

  it('404 no item mostra registro não encontrado', async () => {
    renderizarHibrido({
      rota: '/programacao/ses_inexistente',
      rotas: {
        ...ROTAS,
        '/admin/sessions/ses_inexistente': {
          status: 404,
          corpo: { codigo: 'nao_encontrado', mensagem: 'Sessão não existe.' },
        },
      },
    });

    expect(await screen.findByText('Registro não encontrado')).toBeVisible();
    expect(screen.getByText('Sessão não existe.')).toBeVisible();
  });

  it('409 no salvamento abre o diálogo de conflito', async () => {
    const usuario = userEvent.setup();
    renderizarHibrido({
      rota: '/programacao/ses_real_1',
      rotas: {
        ...ROTAS,
        'GET /admin/sessions/ses_real_1': { corpo: SESSAO_DA_API },
        'PATCH /admin/sessions/ses_real_1': {
          status: 409,
          corpo: {
            codigo: 'conflito',
            mensagem: 'O registro mudou desde que a tela carregou.',
          },
        },
      },
    });

    const titulo = await screen.findByLabelText(/^Título/);
    await waitFor(() => expect(titulo).toHaveValue('Sessão real'));
    await usuario.type(titulo, ' editada');
    await usuario.click(screen.getByRole('button', { name: /^Salvar$/ }));

    expect(await screen.findByRole('heading', { name: /conflito de atualização/i })).toBeVisible();
    expect(screen.getByText(/apagaria a alteração da outra pessoa/i)).toBeVisible();
  });

  it('422 mostra o motivo da recusa e mantém o que foi editado', async () => {
    const usuario = userEvent.setup();
    renderizarHibrido({
      rota: '/espacos/esp_real_1',
      rotas: {
        ...ROTAS,
        'GET /admin/spaces/esp_real_1': {
          corpo: {
            id: 'esp_real_1',
            nome: 'Arena Real',
            slug: 'arena-real',
            tipo: 'arena',
            aliases: ['palco real'],
            comoChegar: 'Ao fundo.',
            coordenadaX: 1,
            coordenadaY: 2,
            ativo: true,
            atualizadoEm: '2026-08-10T00:00:00.000Z',
          },
        },
        'PATCH /admin/spaces/esp_real_1': {
          status: 422,
          corpo: {
            codigo: 'validacao',
            mensagem: 'Slug já usado por outro espaço.',
            detalhes: ['slug: precisa ser único'],
          },
        },
      },
    });

    const slug = await screen.findByLabelText(/^Slug/);
    await waitFor(() => expect(slug).toHaveValue('arena-real'));
    await usuario.clear(slug);
    await usuario.type(slug, 'arena-mind');
    await usuario.click(screen.getByRole('button', { name: /^Salvar$/ }));

    const aviso = await screen.findByTestId('erro-escrita');
    expect(aviso).toHaveTextContent('A API recusou estes dados');
    expect(aviso).toHaveTextContent('Slug já usado por outro espaço.');
    expect(aviso).toHaveTextContent('slug: precisa ser único');
    /* O que a pessoa digitou continua no formulário. */
    expect(screen.getByLabelText(/^Slug/)).toHaveValue('arena-mind');
  });

  it('503 mostra serviço indisponível na listagem real', async () => {
    renderizarHibrido({
      rota: '/espacos',
      rotas: {
        ...ROTAS,
        '/admin/spaces': {
          status: 503,
          corpo: { codigo: 'indisponivel', mensagem: 'Em manutenção programada.' },
        },
      },
    });

    expect(await screen.findByText('Serviço indisponível')).toBeVisible();
    expect(screen.getByText('Em manutenção programada.')).toBeVisible();
  });

  it('o requestId da resposta aparece na tela de erro', async () => {
    renderizarHibrido({
      rota: '/espacos',
      rotas: { ...ROTAS, '/admin/spaces': { status: 503, corpo: { codigo: 'indisponivel' } } },
    });

    expect(await screen.findByText(/requisição req_teste_0001/)).toBeVisible();
  });

  it('o provedor HTTP traduz cada status no código do contrato', async () => {
    const casos: [number, string, string][] = [
      [401, 'sessao_expirada', 'sem_permissao'],
      [403, 'sem_permissao', 'sem_permissao'],
      [404, 'nao_encontrado', 'nao_encontrado'],
      [409, 'conflito', 'conflito'],
      [422, 'validacao', 'validacao'],
      [503, 'indisponivel', 'indisponivel'],
    ];

    for (const [status, esperado, codigoNoCorpo] of casos) {
      const { http } = criarProvedorHttp({
        'GET /admin/sessions': { status, corpo: { codigo: codigoNoCorpo, mensagem: 'x' } },
      });
      await expect(http.list('sessions'), `status ${status}`).rejects.toSatisfy(
        (e: unknown) => ehErroAdmin(e) && e.codigo === esperado,
      );
    }
  });
});

describe('evento real', () => {
  it('mostra a divergência entre o cadastro oficial e a cópia congelada', async () => {
    renderizarHibrido({ rota: '/evento', rotas: ROTAS });

    expect(await screen.findByText(/local do evento em divergência/i)).toBeVisible();
    expect(screen.getByText('Pavilhão 3 · Transamérica Expo Center')).toBeVisible();
    expect(screen.getByText('São Paulo Expo')).toBeVisible();
    expect(screen.getByText(/o painel não decide qual está correto/i)).toBeVisible();
  });

  it('salvar fala da API, não da base de demonstração', async () => {
    const usuario = userEvent.setup();
    renderizarHibrido({
      rota: '/evento',
      rotas: { ...ROTAS, '/admin/event/evt_real': { corpo: EVENTO_DA_API } },
    });

    const cidade = await screen.findByLabelText(/^Cidade/);
    await waitFor(() => expect(cidade).toHaveValue('São Paulo'));
    await usuario.type(cidade, ' · SP');
    await usuario.click(screen.getByRole('button', { name: /salvar alterações/i }));

    expect(await screen.findByText('Alterações salvas')).toBeVisible();
    expect(screen.getByText(/gravado na api administrativa/i)).toBeVisible();
    expect(screen.queryByText(/base de demonstração/i)).not.toBeInTheDocument();
  });

  it('manda o PATCH com o header de concorrência', async () => {
    const usuario = userEvent.setup();
    const { falso } = renderizarHibrido({
      rota: '/evento',
      rotas: { ...ROTAS, '/admin/event/evt_real': { corpo: EVENTO_DA_API } },
    });

    const cidade = await screen.findByLabelText(/^Cidade/);
    await waitFor(() => expect(cidade).toHaveValue('São Paulo'));
    await usuario.type(cidade, ' · SP');
    await usuario.click(screen.getByRole('button', { name: /salvar alterações/i }));

    await waitFor(() => {
      const patch = falso.chamadas.find((c) => c.metodo === 'PATCH');
      expect(patch?.url).toContain('/admin/event/evt_real');
      expect(patch?.cabecalhos['If-Unmodified-Since-Version']).toBe(EVENTO_DA_API.atualizadoEm);
    });
  });
});

describe('categorias reais na tela', () => {
  const tipos = [
    ['credenciamento', 'Credenciamento'],
    ['almoco', 'Almoço'],
    ['intervalo', 'Intervalo'],
    ['em_curadoria', 'Em curadoria'],
  ] as const;

  it('os novos tipos de sessão aparecem com rótulo em português', async () => {
    renderizarHibrido({
      rota: '/programacao',
      rotas: {
        ...ROTAS,
        '/admin/sessions': {
          corpo: lista(
            tipos.map(([tipo], i) => ({
              ...SESSAO_DA_API,
              id: `ses_${tipo}`,
              titulo: `Bloco ${i}`,
              tipo,
            })),
          ),
        },
      },
    });

    await screen.findByTestId('linha-ses_credenciamento');
    for (const [tipo, esperado] of tipos) {
      const linha = screen.getByTestId(`linha-ses_${tipo}`);
      expect(within(linha).getByText(esperado), tipo).toBeVisible();
    }
  });

  it('o formato remoto aparece traduzido', async () => {
    renderizarHibrido({
      rota: '/programacao',
      rotas: {
        ...ROTAS,
        '/admin/sessions': {
          corpo: lista([{ ...SESSAO_DA_API, id: 'ses_remoto', formato: 'remoto' }]),
        },
      },
    });

    const linha = await screen.findByTestId('linha-ses_remoto');
    expect(within(linha).getByText('Remoto')).toBeVisible();
  });

  it('os novos tipos de espaço aparecem com rótulo em português', async () => {
    const tiposEspaco = [
      ['acessibilidade', 'Acessibilidade'],
      ['acesso', 'Acesso'],
      ['alimentacao', 'Alimentação'],
      ['ativacao', 'Ativação'],
      ['estandes', 'Estandes'],
      ['servico', 'Serviço'],
    ] as const;

    renderizarHibrido({
      rota: '/espacos',
      rotas: {
        ...ROTAS,
        '/admin/spaces': {
          corpo: lista(
            tiposEspaco.map(([tipo]) => ({
              id: `esp_${tipo}`,
              nome: `Espaço ${tipo}`,
              slug: tipo,
              tipo,
              aliases: ['x'],
              comoChegar: 'Ali.',
              coordenadaX: 1,
              coordenadaY: 2,
              ativo: true,
              atualizadoEm: '2026-08-01T00:00:00.000Z',
            })),
          ),
        },
      },
    });

    await screen.findByTestId('linha-esp_acesso');
    for (const [tipo, esperado] of tiposEspaco) {
      const linha = screen.getByTestId(`linha-esp_${tipo}`);
      expect(within(linha).getByText(esperado), tipo).toBeVisible();
    }
  });

  it('categoria desconhecida aparece com o código cru e marcada', async () => {
    renderizarHibrido({
      rota: '/programacao',
      rotas: {
        ...ROTAS,
        '/admin/sessions': {
          corpo: lista([{ ...SESSAO_DA_API, id: 'ses_nova', tipo: 'mesa_redonda' }]),
        },
      },
    });

    const linha = await screen.findByTestId('linha-ses_nova');
    const selo = within(linha).getByText('mesa_redonda');
    expect(selo).toBeVisible();
    /* Marcado como desconhecido, não traduzido para "palestra". */
    expect(selo.closest('[data-categoria-desconhecida="true"]')).not.toBeNull();
    expect(within(linha).queryByText('Palestra')).not.toBeInTheDocument();
  });
});

describe('vínculo que aponta para fora da lista carregada', () => {
  /* Regressão de um bug real: o Radix avisa `onValueChange('')` quando
     o valor controlado não casa com nenhum item montado. Sem o guarda
     em `components/ui/select.tsx`, abrir uma sessão cujo espaço não está
     na lista e salvar qualquer outro campo mandava `espacoId: null`. */
  it('salvar preserva o espaço da sessão mesmo sem ele nas opções', async () => {
    const usuario = userEvent.setup();
    const { falso } = renderizarHibrido({
      rota: '/programacao/ses_real_1',
      rotas: {
        ...ROTAS,
        /* A lista de espaços volta vazia — o espaço da sessão não está lá. */
        '/admin/spaces': { corpo: lista([]) },
        'GET /admin/sessions/ses_real_1': { corpo: SESSAO_DA_API },
        'PATCH /admin/sessions/ses_real_1': { corpo: SESSAO_DA_API },
      },
    });

    const titulo = await screen.findByLabelText(/^Título/);
    await waitFor(() => expect(titulo).toHaveValue('Sessão real'));
    await usuario.type(titulo, ' revisada');
    await usuario.click(screen.getByRole('button', { name: /^Salvar$/ }));

    await waitFor(() => {
      const patch = falso.chamadas.find((c) => c.metodo === 'PATCH');
      expect(patch, 'o PATCH precisa sair — validação não pode barrar').toBeDefined();
    });

    /* Nenhuma mensagem de "escolha o espaço": o vínculo sobreviveu. */
    expect(screen.queryByText('Escolha o espaço.')).not.toBeInTheDocument();
  });
});
