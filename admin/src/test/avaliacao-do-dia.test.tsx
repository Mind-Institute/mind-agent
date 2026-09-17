import { afterEach, describe, expect, it, vi } from 'vitest';
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { renderizarPainel } from './utils';
import { montarCsv } from '@/features/avaliacao-do-dia/csv';

/* ============================================================
   AVALIAÇÃO DO DIA — o relatório
   ============================================================
   O que se prova aqui é o que uma média mal desenhada estraga sem dar
   erro: amostra escondida, atividade sem nota virando zero e respondente
   contado uma vez por atividade avaliada. Os três passam despercebidos
   numa revisão e mudam a decisão de quem lê. */

const BASE = 'https://exemplo.supabase.co/functions/v1/mindagent-avaliacao';

const RELATORIO = {
  evento: { slug: 'mind-summit-2026', nome: 'Mind Summit 2026',
            dias: ['2026-09-16', '2026-09-17'], fuso: 'America/Sao_Paulo' },
  filtro: { dia: null, experiencia: null },
  kpis: {
    respondentes: 3,
    porExperiencia: { mind: 1, vip: 1, prime: 1 },
    relevancia: {
      amostra: 3, media: 3, percentual45: 66.7,
      distribuicao: { '0': 1, '1': 0, '2': 0, '3': 0, '4': 1, '5': 1 },
    },
    programacao: {
      amostra: 3, media: 4, percentual45: 66.7,
      distribuicao: { '0': 0, '1': 0, '2': 0, '3': 1, '4': 1, '5': 1 },
    },
  },
  avaliacoesDeAtividades: 3,
  porAtividade: [
    {
      id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
      titulo: 'Do benefício à transformação', dia: '2026-09-16', inicio: '09:15',
      espaco: 'Arena Mind', tipo: 'palestra', ingressos: ['mind', 'vip', 'prime'],
      avaliacoes: 2, media: 2.5,
      distribuicao: { '0': 1, '1': 0, '2': 0, '3': 0, '4': 0, '5': 1 },
    },
    {
      id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
      titulo: 'Ninguém avaliou esta', dia: '2026-09-16', inicio: '10:00',
      espaco: 'Arena Sextante', tipo: 'palestra', ingressos: ['mind'],
      avaliacoes: 0, media: null,
      distribuicao: { '0': 0, '1': 0, '2': 0, '3': 0, '4': 0, '5': 0 },
    },
  ],
};

const RESPOSTAS = {
  total: 1, pagina: 1, porPagina: 25,
  itens: [{
    id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    dia: '2026-09-16', enviadoEm: '2026-09-16T21:10:00-03:00',
    experiencia: 'prime', profissao: 'Gerente de RH',
    expectativas: 'Entender como medir bem-estar.',
    notaRelevancia: 0, notaProgramacao: 5,
    maisGostou: 'A masterclass.', melhorar: 'Mais lugares para sentar.',
    comentario: null, atividadesAvaliadas: 2,
  }],
};

function ligarApi(respostas: { relatorio?: unknown; respostas?: unknown; status?: number } = {}) {
  vi.stubEnv('VITE_AVALIACAO_API_BASE_URL', BASE);
  const chamadas: string[] = [];
  vi.stubGlobal('fetch', vi.fn(async (url: string) => {
    chamadas.push(String(url));
    const corpo = String(url).includes('/admin/relatorio')
      ? (respostas.relatorio ?? RELATORIO)
      : (respostas.respostas ?? RESPOSTAS);
    return new Response(JSON.stringify(corpo), {
      status: respostas.status ?? 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }));
  return chamadas;
}

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe('Avaliação do dia · relatório', () => {
  it('com a variável zerada, não abre e NÃO chama rede nenhuma', async () => {
    /* `vite.config.ts` zera as variáveis em modo de teste para a suíte
       nunca alcançar o backend real. O endereço da Edge Function mora no
       código como fallback de quando a variável NÃO EXISTE — mas vazia é
       diferente de ausente, e vazia desliga o fallback.

       Sem esta distinção, qualquer teste que montasse esta página — e
       `navegacao.test.tsx` monta todos os módulos — passaria a chamar a
       produção de verdade. */
    const buscar = vi.fn();
    vi.stubGlobal('fetch', buscar);
    renderizarPainel({ rota: '/avaliacao-do-dia' });

    expect(await screen.findByRole('heading', { name: 'Avaliação do dia', level: 1 })).toBeVisible();
    expect(await screen.findByText(/pesquisa ainda não foi ligada/i)).toBeVisible();
    expect(buscar).not.toHaveBeenCalled();
  });

  it('a variável de ambiente manda no endereço', async () => {
    const chamadas = ligarApi();
    renderizarPainel({ rota: '/avaliacao-do-dia' });

    await vi.waitFor(() => {
      expect(chamadas.length).toBeGreaterThan(0);
      expect(chamadas.every((u) => u.startsWith(BASE))).toBe(true);
    });
  });

  it('mostra cada média com o tamanho da amostra ao lado', async () => {
    ligarApi();
    renderizarPainel({ rota: '/avaliacao-do-dia' });

    expect(await screen.findByText('3,00')).toBeVisible();      // média de relevância
    expect(await screen.findByText('4,00')).toBeVisible();      // média da programação
    /* A amostra aparece junto: uma média sem denominador mente por omissão. */
    expect(await screen.findAllByText(/3 respostas/)).not.toHaveLength(0);
    expect(await screen.findAllByText(/66,7% deram 4 ou 5/)).not.toHaveLength(0);
  });

  it('respondentes e avaliações de atividades são números separados', async () => {
    ligarApi();
    renderizarPainel({ rota: '/avaliacao-do-dia' });

    const respondentes = (await screen.findByText('Respondentes')).closest('div')?.parentElement;
    expect(within(respondentes as HTMLElement).getByText('3')).toBeVisible();
    /* 3 respondentes e 3 notas de atividade coexistem sem se somarem nem
       se multiplicarem: se a tela juntasse as duas listas, um deles
       estaria errado. */
    const individuais = (await screen.findByText('Avaliações de atividades')).closest('div')?.parentElement;
    expect(within(individuais as HTMLElement).getByText('3')).toBeVisible();
    expect(await screen.findByText(/Mind 1 · VIP 1 · Prime 1/)).toBeVisible();
  });

  it('atividade sem avaliação aparece como "Sem avaliações", nunca com média zero', async () => {
    ligarApi();
    renderizarPainel({ rota: '/avaliacao-do-dia' });

    const linha = (await screen.findByText('Ninguém avaliou esta')).closest('tr');
    expect(within(linha as HTMLElement).getByText('Sem avaliações')).toBeVisible();
    expect(within(linha as HTMLElement).queryByText('0,00')).toBeNull();

    /* A que tem nota zero E nota cinco mostra a média de verdade. */
    const comNota = (await screen.findByText('Do benefício à transformação')).closest('tr');
    expect(within(comNota as HTMLElement).getByText('2,50')).toBeVisible();
  });

  it('ordenar por maior média joga quem não tem nota para o fim', async () => {
    ligarApi();
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/avaliacao-do-dia' });

    await screen.findByText('Ninguém avaliou esta');
    await usuario.click(screen.getByLabelText('Ordenar atividades'));
    await usuario.click(await screen.findByRole('option', { name: 'Maior média' }));

    const linhas = screen.getAllByRole('row').slice(1).map((l) => l.textContent ?? '');
    /* Sem nota tratada como zero iria para o topo numa ordenação
       decrescente invertida — e pareceria a pior atividade do evento. */
    expect(linhas[0]).toContain('Do benefício');
    expect(linhas[linhas.length - 1]).toContain('Ninguém avaliou esta');
  });

  it('o filtro de dia e de experiência viaja na consulta', async () => {
    const chamadas = ligarApi();
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/avaliacao-do-dia' });

    await screen.findByText('Do benefício à transformação');
    await usuario.click(screen.getByLabelText('Experiência declarada'));
    await usuario.click(await screen.findByRole('option', { name: 'VIP' }));

    await vi.waitFor(() => {
      expect(chamadas.some((u) => u.includes('experiencia=vip'))).toBe(true);
    });
  });

  it('mostra as respostas abertas e não expõe e-mail de ninguém', async () => {
    ligarApi();
    renderizarPainel({ rota: '/avaliacao-do-dia' });

    expect(await screen.findByText('Mais lugares para sentar.')).toBeVisible();
    expect(await screen.findByText('A masterclass.')).toBeVisible();
    /* O contrato do relatório não traz e-mail nem nome: quem responde é
       identificado pelo servidor e a análise não precisa saber quem é. */
    expect(screen.queryByText(/@/)).toBeNull();
  });

  it('erro da API vira aviso na tela, não tela em branco', async () => {
    vi.stubEnv('VITE_AVALIACAO_API_BASE_URL', BASE);
    vi.stubGlobal('fetch', vi.fn(async () => new Response(
      JSON.stringify({ codigo: 'sem_permissao', mensagem: 'Usuário sem acesso ao painel.' }),
      { status: 403, headers: { 'Content-Type': 'application/json' } },
    )));
    renderizarPainel({ rota: '/avaliacao-do-dia' });

    expect(await screen.findByText('Usuário sem acesso ao painel.')).toBeVisible();
    expect(screen.getByRole('heading', { name: 'Avaliação do dia', level: 1 })).toBeVisible();
  });
});

describe('Avaliação do dia · CSV', () => {
  it('abre com BOM, separa por ponto e vírgula e cita todo campo', () => {
    const saida = montarCsv(['Profissão'], [['Gerente de RH']]);
    expect(saida.charCodeAt(0)).toBe(0xfeff);
    expect(saida).toContain('"Profissão"');
    expect(saida.split('\r\n')).toHaveLength(2);
  });

  it('quebra de linha e aspas dentro do texto não quebram a planilha', () => {
    const saida = montarCsv(['Comentário'], [['Primeira linha\nSegunda "com aspas"']]);
    const semBom = saida.slice(1);
    /* Uma linha de cabeçalho + uma de dado: a quebra interna fica DENTRO
       das aspas e não vira registro novo. */
    expect(semBom.split('\r\n')).toHaveLength(2);
    expect(semBom).toContain('""com aspas""');
  });

  it('texto que a planilha executaria como fórmula sai neutralizado', () => {
    const saida = montarCsv(['x'], [['=1+1'], ['+55 11 99999-9999'], ['-3'], ['@aqui']]);
    for (const perigoso of ['"\'=1+1"', '"\'+55 11 99999-9999"', '"\'-3"', '"\'@aqui"']) {
      expect(saida).toContain(perigoso);
    }
  });
});
