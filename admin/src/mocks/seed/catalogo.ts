/* ============================================================
   CATÁLOGO — semente do modo demonstração
   ============================================================
   Seis produtos no formato de `catalogo.produtos`, escritos à mão para
   exercitar a tela: produto que vende e que não vende, ativo e inativo,
   com e sem vertical, com janela de venda e sem. O catálogo de verdade
   vem da `mindagent-catalogo`; este só aparece em demonstração, com o
   selo dizendo isso. */

import type { ProdutoCatalogo } from '@/contracts';

const ATUALIZADO_EM = '2026-09-13T12:00:00.000+00:00';

function produto(p: Partial<ProdutoCatalogo> & Pick<ProdutoCatalogo, 'id' | 'codigo' | 'nome' | 'tipo'>): ProdutoCatalogo {
  return {
    criadoEm: '',
    atualizadoEm: ATUALIZADO_EM,
    atualizadoPor: null,
    vertical: null,
    categoria: null,
    descricaoCurta: null,
    descricao: null,
    ativo: true,
    vende: false,
    vendeDe: null,
    vendeAte: null,
    comecaEm: null,
    encerraEm: null,
    periodo: null,
    schemaDados: null,
    pipelinesHubspot: [],
    ...p,
  };
}

export const produtosSemente: ProdutoCatalogo[] = [
  produto({
    id: 'prd_mind',
    codigo: 'mind',
    nome: 'Mind',
    tipo: 'empresa',
    descricaoCurta: 'A empresa em si — não é produto vendável.',
  }),
  produto({
    id: 'prd_summit_2026',
    codigo: 'mind-summit-2026',
    nome: 'Mind Summit 2026',
    tipo: 'evento',
    vertical: 'summit',
    comecaEm: '2026-09-16',
    encerraEm: '2026-09-17',
    vendeAte: '2026-09-18T02:59:59+00:00',
    periodo: 'setembro de 2026',
    schemaDados: 'summit_2026',
  }),
  produto({
    id: 'prd_summit_2025',
    codigo: 'mind-summit-2025',
    nome: 'Mind Summit 2025',
    tipo: 'evento',
    vertical: 'summit',
    ativo: false,
    periodo: 'outubro de 2025',
    schemaDados: 'summit_2025',
  }),
  produto({
    id: 'prd_cert_lideranca_2027',
    codigo: 'mind-institute-certificacao-lideranca-positiva-2027',
    nome: 'Certificação Avançada em Liderança Positiva',
    tipo: 'formacao',
    vertical: 'institute',
    vende: true,
    descricaoCurta: 'Formação executiva do Mind Institute.',
  }),
  produto({
    id: 'prd_journey_2027',
    codigo: 'mind-journey-2027',
    nome: 'Mind Journey',
    tipo: 'assinatura',
    vertical: 'institute',
    vende: true,
  }),
  produto({
    id: 'prd_dash',
    codigo: 'mind-dash',
    nome: 'Mind Dash',
    tipo: 'outro',
    vertical: 'dash',
    schemaDados: 'dash',
    pipelinesHubspot: ['123456789'],
  }),
];
