import { describe, expect, it } from 'vitest';
import { AdminApiError, ehErroAdmin, type ProdutoCatalogo } from '@/contracts';
import { MockAdminDataProvider } from '@/services/mock-admin-data-provider';
import { HttpAdminDataProvider } from '@/services/http-admin-data-provider';

/* Desde 26/09/2026 o único recurso do painel é o Catálogo (`products`):
   o resto não era dado real e saiu. O mock existe para os testes e para o
   preview de cada versão; o contrato dele é o mesmo do provedor HTTP. */

function criar() {
  return new MockAdminDataProvider({ latenciaMs: 0 });
}

/* Um produto como a `mindagent-catalogo` devolve. */
const PRODUTO: ProdutoCatalogo = {
  id: 'prd_1',
  criadoEm: '',
  atualizadoEm: '2026-09-13T15:30:00.123456+00:00',
  atualizadoPor: null,
  codigo: 'produto-1',
  nome: 'Produto 1',
  tipo: 'formacao',
  vertical: 'institute',
  categoria: null,
  descricaoCurta: null,
  descricao: null,
  ativo: true,
  vende: true,
  vendeDe: null,
  vendeAte: null,
  comecaEm: null,
  encerraEm: null,
  periodo: null,
  schemaDados: null,
  pipelinesHubspot: [],
  datasDaTurma: null,
};

describe('MockAdminDataProvider', () => {
  it('lista os produtos da semente', async () => {
    const provedor = criar();
    const { itens, total } = await provedor.list('products');
    expect(total).toBe(6);
    expect(itens[0]).toHaveProperty('codigo');
    expect(itens[0]).toHaveProperty('nome');
  });

  it('filtra por campo simples, booleano e nulo', async () => {
    const provedor = criar();
    const todos = await provedor.list('products');

    const doInstitute = await provedor.list('products', { vertical: 'institute' });
    expect(doInstitute.total).toBe(2);
    expect(doInstitute.itens.every((p) => p.vertical === 'institute')).toBe(true);

    const inativos = await provedor.list('products', { ativo: 'false' });
    expect(inativos.itens.map((p) => p.id)).toEqual(['prd_summit_2025']);

    const semVertical = await provedor.list('products', { vertical: 'null' });
    expect(semVertical.total).toBeGreaterThan(0);
    expect(semVertical.total).toBeLessThan(todos.total);
    expect(semVertical.itens.every((p) => p.vertical === null)).toBe(true);
  });

  it('busca textual ignora acento e caixa', async () => {
    const provedor = criar();
    const resultado = await provedor.list('products', { busca: 'CERTIFICACAO' });
    expect(resultado.itens.map((p) => p.id)).toEqual(['prd_cert_lideranca_2027']);
  });

  it('devolve nao_encontrado para id inexistente', async () => {
    const provedor = criar();
    await expect(provedor.get('products', 'prd_inexistente')).rejects.toSatisfy(
      (erro: unknown) => ehErroAdmin(erro) && erro.codigo === 'nao_encontrado',
    );
  });

  it('arquiva em vez de excluir — o registro continua na base', async () => {
    const provedor = criar();
    const antes = await provedor.list('products');

    const arquivado = await provedor.archive('products', 'prd_dash');
    expect(arquivado.ativo).toBe(false);

    const depois = await provedor.list('products');
    expect(depois.total).toBe(antes.total);
  });

  it('recusa escrita quando o registro mudou (conflito de atualização)', async () => {
    const provedor = criar();
    const produto = await provedor.get('products', 'prd_dash');
    const versaoAntiga = produto.atualizadoEm;

    await provedor.update('products', produto.id, { descricao: 'primeiro salvamento' });

    await expect(
      provedor.update(
        'products',
        produto.id,
        { descricao: 'segundo salvamento' },
        { atualizadoEmEsperado: versaoAntiga },
      ),
    ).rejects.toSatisfy((erro: unknown) => ehErroAdmin(erro) && erro.codigo === 'conflito');
  });

  it('injeta falha por recurso para exercitar a tela de erro', async () => {
    const provedor = criar();
    provedor.configurarFalha('products', 'rede');
    await expect(provedor.list('products')).rejects.toBeInstanceOf(AdminApiError);

    provedor.limparFalhas();
    await expect(provedor.list('products')).resolves.toBeTruthy();
  });

  it('cada instância trabalha em um banco próprio', async () => {
    const a = criar();
    const b = criar();

    await a.update('products', 'prd_dash', { nome: 'Renomeado em A' });

    const emB = await b.get('products', 'prd_dash');
    expect(emB.nome).not.toBe('Renomeado em A');
  });
});

describe('HttpAdminDataProvider', () => {
  it('recusa ser criado sem endereço — não inventa um', () => {
    expect(() => new HttpAdminDataProvider({ baseUrl: '' })).toThrow(AdminApiError);
  });

  it('monta os caminhos combinados com o backend', async () => {
    const chamadas: { url: string; init?: RequestInit }[] = [];
    /* Corpo válido conforme o contrato: envelope na listagem, registro
       nas demais. Resposta fora do formato é erro — é o que o teste de
       contrato em `api-real.test.tsx` verifica. */
    const envelope = { itens: [], total: 0, pagina: 1, porPagina: 0 };
    const fetchFalso = (async (url: string | URL, init?: RequestInit) => {
      chamadas.push({ url: String(url), init });
      const caminho = new URL(String(url)).pathname;
      /* Só o GET na raiz do recurso é listagem; o POST no mesmo caminho
         é criação e devolve um registro. */
      const metodo = (init?.method ?? 'GET').toUpperCase();
      const eListagem = metodo === 'GET' && /\/admin\/[a-z]+$/.test(caminho);
      return new Response(JSON.stringify(eListagem ? envelope : PRODUTO), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    }) as unknown as typeof fetch;

    const provedor = new HttpAdminDataProvider({
      baseUrl: 'https://exemplo.invalido/api/',
      fetchImpl: fetchFalso,
    });

    await provedor.list('products', { vertical: 'institute' });
    await provedor.get('products', 'prd_1');
    await provedor.create('products', { nome: 'Novo' });
    await provedor.update('products', 'prd_1', { nome: 'Outro' });
    await provedor.publish('products', 'prd_1');
    await provedor.archive('products', 'prd_1');

    expect(chamadas.map((c) => `${c.init?.method ?? 'GET'} ${c.url}`)).toEqual([
      'GET https://exemplo.invalido/api/admin/products?vertical=institute',
      'GET https://exemplo.invalido/api/admin/products/prd_1',
      'POST https://exemplo.invalido/api/admin/products',
      'PATCH https://exemplo.invalido/api/admin/products/prd_1',
      'POST https://exemplo.invalido/api/admin/products/prd_1/publish',
      'POST https://exemplo.invalido/api/admin/products/prd_1/archive',
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

    await expect(provedor.update('products', 'x', {})).rejects.toSatisfy(
      (erro: unknown) => ehErroAdmin(erro) && erro.codigo === 'conflito',
    );
  });

  it('não coloca token na URL — ele vai no header Authorization', async () => {
    const chamadas: { url: string; init?: RequestInit }[] = [];
    const fetchFalso = (async (url: string | URL, init?: RequestInit) => {
      chamadas.push({ url: String(url), init });
      return new Response(JSON.stringify({ itens: [], total: 0, pagina: 1, porPagina: 0 }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    }) as unknown as typeof fetch;

    const provedor = new HttpAdminDataProvider({
      baseUrl: 'https://exemplo.invalido',
      fetchImpl: fetchFalso,
      obterToken: async () => 'token-de-teste',
    });

    await provedor.list('products');

    const cabecalhos = chamadas[0].init?.headers as Record<string, string>;
    expect(cabecalhos.Authorization).toBe('Bearer token-de-teste');
    expect(chamadas[0].url).not.toContain('token');
  });
});
