import { describe, expect, it } from 'vitest';
import { AdminApiError, ehErroAdmin } from '@/contracts';
import { MockAdminDataProvider } from '@/services/mock-admin-data-provider';
import { HttpAdminDataProvider } from '@/services/http-admin-data-provider';

function criar() {
  return new MockAdminDataProvider({ latenciaMs: 0 });
}

describe('MockAdminDataProvider', () => {
  it('lista sessões vindas do summit.json', async () => {
    const provedor = criar();
    const { itens, total } = await provedor.list('sessions');
    expect(total).toBeGreaterThan(0);
    expect(itens[0]).toHaveProperty('titulo');
    expect(itens[0]).toHaveProperty('dia');
  });

  it('filtra por campo simples e por campo de lista', async () => {
    const provedor = criar();
    const todas = await provedor.list('sessions');
    const doPrimeiroDia = await provedor.list('sessions', { dia: '2026-09-16' });

    expect(doPrimeiroDia.total).toBeGreaterThan(0);
    expect(doPrimeiroDia.total).toBeLessThan(todas.total);
    expect(doPrimeiroDia.itens.every((s) => s.dia === '2026-09-16')).toBe(true);

    const porTema = await provedor.list('sessions', { tema: 'performance' });
    expect(porTema.itens.every((s) => s.temas.includes('performance'))).toBe(true);
  });

  it('filtra sessões sem espaço com espacoId=null — o link da visão geral', async () => {
    const provedor = criar();
    const semEspaco = await provedor.list('sessions', { espacoId: 'null' });
    expect(semEspaco.total).toBeGreaterThan(0);
    expect(semEspaco.itens.every((s) => s.espacoId === null)).toBe(true);
  });

  it('busca textual ignora acento e caixa', async () => {
    const provedor = criar();
    const resultado = await provedor.list('speakers', { busca: 'EDMONDSON' });
    expect(resultado.total).toBeGreaterThan(0);
    expect(resultado.itens[0].nome).toContain('Edmondson');
  });

  it('devolve nao_encontrado para id inexistente', async () => {
    const provedor = criar();
    await expect(provedor.get('sessions', 'ses_inexistente')).rejects.toSatisfy(
      (erro: unknown) => ehErroAdmin(erro) && erro.codigo === 'nao_encontrado',
    );
  });

  it('publica mudando status, data e responsável', async () => {
    const provedor = criar();
    const { itens } = await provedor.list('content', { status: 'rascunho' });
    const alvo = itens[0];
    expect(alvo.status).toBe('rascunho');

    const publicado = await provedor.publish('content', alvo.id);
    expect(publicado.status).toBe('publicado');
    expect(publicado.publicadoEm).toBeTruthy();
    expect(publicado.publicadoPor).toBeTruthy();
  });

  it('arquiva em vez de excluir — o registro continua na base', async () => {
    const provedor = criar();
    const antes = await provedor.list('booths');
    const alvo = antes.itens[0];

    const arquivado = await provedor.archive('booths', alvo.id);
    expect(arquivado.ativo).toBe(false);

    const depois = await provedor.list('booths');
    expect(depois.total).toBe(antes.total);
  });

  it('recusa escrita quando o registro mudou (conflito de atualização)', async () => {
    const provedor = criar();
    const { itens } = await provedor.list('spaces');
    const espaco = itens[0];
    const versaoAntiga = espaco.atualizadoEm;

    await provedor.update('spaces', espaco.id, { descricao: 'primeiro salvamento' });

    await expect(
      provedor.update(
        'spaces',
        espaco.id,
        { descricao: 'segundo salvamento' },
        { atualizadoEmEsperado: versaoAntiga },
      ),
    ).rejects.toSatisfy((erro: unknown) => ehErroAdmin(erro) && erro.codigo === 'conflito');
  });

  it('registra auditoria de toda escrita, com antes e depois', async () => {
    const provedor = criar();
    const { itens } = await provedor.list('spaces');
    const espaco = itens[0];

    await provedor.update('spaces', espaco.id, { andar: 'Subsolo' });

    const auditoria = await provedor.list('audit', { ordenar: '-ocorridoEm' });
    const registro = auditoria.itens[0];
    expect(registro.acao).toBe('atualizar');
    expect(registro.recurso).toBe('spaces');
    expect(registro.depois).toMatchObject({ andar: 'Subsolo' });
    expect(registro.requestId).toMatch(/^req_/);
  });

  it('reindexação enfileira e marca o recibo como simulado', async () => {
    const provedor = criar();
    const recibo = await provedor.requestReindex('doc_mapa_pdf');

    expect(recibo.simulado).toBe(true);
    expect(recibo.statusAtual).toBe('na_fila');
    expect(recibo.mensagem).toMatch(/nada foi indexado/i);

    const documento = await provedor.get('documents', 'doc_mapa_pdf');
    expect(documento.statusIndexacao).toBe('na_fila');
  });

  it('monta o resumo do painel com métricas e pendências', async () => {
    const provedor = criar();
    const resumo = await provedor.getDashboard();

    const chaves = resumo.metricas.map((m) => m.chave);
    expect(chaves).toEqual(
      expect.arrayContaining([
        'sessoes',
        'palestrantes',
        'espacos',
        'estandes',
        'ofertas',
        'documentos_publicados',
        'documentos_aguardando',
        'perguntas',
        'conversas_24h',
        'dados_incompletos',
      ]),
    );

    const categorias = resumo.pendencias.map((p) => p.categoria);
    expect(categorias).toEqual([
      'sessoes_sem_espaco',
      'sessoes_sem_palestrante',
      'espacos_sem_localizacao',
      'palcos_sem_alias',
      'ofertas_sem_checkout',
      'documentos_sem_indexacao',
      'conteudo_em_rascunho',
    ]);

    /* A divergência de local do evento é alerta, não decisão. */
    expect(resumo.alertas.some((a) => a.id === 'alerta_local_evento')).toBe(true);
  });

  it('injeta falha por recurso para exercitar a tela de erro', async () => {
    const provedor = criar();
    provedor.configurarFalha('offers', 'rede');
    await expect(provedor.list('offers')).rejects.toBeInstanceOf(AdminApiError);

    provedor.limparFalhas();
    await expect(provedor.list('offers')).resolves.toBeTruthy();
  });

  it('cada instância trabalha em um banco próprio', async () => {
    const a = criar();
    const b = criar();
    const { itens } = await a.list('spaces');

    await a.update('spaces', itens[0].id, { nome: 'Renomeado em A' });

    const emB = await b.get('spaces', itens[0].id);
    expect(emB.nome).not.toBe('Renomeado em A');
  });
});

describe('HttpAdminDataProvider', () => {
  it('recusa ser criado sem VITE_ADMIN_API_BASE_URL — não inventa endereço', () => {
    expect(() => new HttpAdminDataProvider({ baseUrl: '' })).toThrow(AdminApiError);
  });

  it('monta os caminhos combinados com o backend futuro', async () => {
    const chamadas: { url: string; init?: RequestInit }[] = [];
    const fetchFalso = (async (url: string | URL, init?: RequestInit) => {
      chamadas.push({ url: String(url), init });
      return new Response(JSON.stringify({ itens: [], total: 0, pagina: 1, porPagina: 0 }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    }) as unknown as typeof fetch;

    const provedor = new HttpAdminDataProvider({
      baseUrl: 'https://exemplo.invalido/api/',
      fetchImpl: fetchFalso,
    });

    await provedor.list('sessions', { dia: '2026-09-16' });
    await provedor.get('sessions', 'ses_1');
    await provedor.create('sessions', { titulo: 'Nova' });
    await provedor.update('sessions', 'ses_1', { titulo: 'Outra' });
    await provedor.publish('sessions', 'ses_1');
    await provedor.archive('sessions', 'ses_1');
    await provedor.requestReindex('doc_1');
    await provedor.getDashboard();

    expect(chamadas.map((c) => `${c.init?.method ?? 'GET'} ${c.url}`)).toEqual([
      'GET https://exemplo.invalido/api/admin/sessions?dia=2026-09-16',
      'GET https://exemplo.invalido/api/admin/sessions/ses_1',
      'POST https://exemplo.invalido/api/admin/sessions',
      'PATCH https://exemplo.invalido/api/admin/sessions/ses_1',
      'POST https://exemplo.invalido/api/admin/sessions/ses_1/publish',
      'POST https://exemplo.invalido/api/admin/sessions/ses_1/archive',
      'POST https://exemplo.invalido/api/admin/documents/doc_1/reindex',
      'GET https://exemplo.invalido/api/admin/dashboard',
    ]);
  });

  it('traduz status HTTP para o mesmo código de erro do mock', async () => {
    const fetchFalso = (async () =>
      new Response(JSON.stringify({ mensagem: 'conflito' }), {
        status: 409,
        headers: { 'content-type': 'application/json' },
      })) as unknown as typeof fetch;

    const provedor = new HttpAdminDataProvider({
      baseUrl: 'https://exemplo.invalido',
      fetchImpl: fetchFalso,
    });

    await expect(provedor.update('sessions', 'x', {})).rejects.toSatisfy(
      (erro: unknown) => ehErroAdmin(erro) && erro.codigo === 'conflito',
    );
  });

  it('não coloca token na URL — ele vai no header Authorization', async () => {
    const chamadas: { url: string; init?: RequestInit }[] = [];
    const fetchFalso = (async (url: string | URL, init?: RequestInit) => {
      chamadas.push({ url: String(url), init });
      return new Response('{}', { status: 200, headers: { 'content-type': 'application/json' } });
    }) as unknown as typeof fetch;

    const provedor = new HttpAdminDataProvider({
      baseUrl: 'https://exemplo.invalido',
      fetchImpl: fetchFalso,
      obterToken: async () => 'token-de-teste',
    });

    await provedor.getDashboard();

    const cabecalhos = chamadas[0].init?.headers as Record<string, string>;
    expect(cabecalhos.Authorization).toBe('Bearer token-de-teste');
    expect(chamadas[0].url).not.toContain('token');
  });
});
