import { describe, expect, it } from 'vitest';
import {
  mascararEmail,
  mascararIdentificador,
  mascararNome,
  mascararTelefone,
  mascararTextoLivre,
} from '@/lib/mask';
import { formatarMoeda, formatarData, gerarSlug, horaParaMinutos } from '@/lib/format';
import {
  alertasDaOferta,
  camposFaltantesDaSessao,
  camposFaltantesDoEspaco,
  detectarConflitos,
} from '@/lib/pendencias';
import { pode } from '@/lib/permissions';
import type { Espaco, Oferta, Sessao } from '@/contracts';

/* ------------------------------------------------------------------ */
/* Mascaramento de dados pessoais                                      */
/* ------------------------------------------------------------------ */
describe('mascaramento de dados pessoais', () => {
  it('esconde o usuário do e-mail e mantém o domínio', () => {
    expect(mascararEmail('ana.ribeiro@exemplo.com.br')).toBe('an•••@exemplo.com.br');
    expect(mascararEmail('ana.ribeiro@exemplo.com.br')).not.toContain('ribeiro');
    expect(mascararEmail(null)).toBe('—');
  });

  it('mantém só os quatro últimos dígitos do telefone', () => {
    const mascarado = mascararTelefone('+55 11 98888-7777');
    expect(mascarado).toContain('7777');
    expect(mascarado).not.toContain('98888');
  });

  it('reduz o sobrenome a inicial', () => {
    expect(mascararNome('Ana Paula Souza')).toBe('Ana P. S.');
    expect(mascararNome('Ana')).toBe('Ana');
  });

  it('mascara identificador genérico', () => {
    expect(mascararIdentificador('5511900000001')).toBe('••••••0001');
  });

  it('varre texto livre e mascara contato digitado no meio da frase', () => {
    const texto = 'meu email é participante@exemplo.com.br e o fone (11) 98888-7777';
    const saida = mascararTextoLivre(texto);
    expect(saida).not.toContain('participante@');
    expect(saida).not.toContain('98888-7777');
    expect(saida).toContain('@exemplo.com.br');
  });
});

/* ------------------------------------------------------------------ */
/* Formatação                                                          */
/* ------------------------------------------------------------------ */
describe('formatação', () => {
  it('formata centavos em BRL', () => {
    /* O separador do Intl é espaço não-quebrável — comparar por partes. */
    const formatado = formatarMoeda(89000);
    expect(formatado).toContain('R$');
    expect(formatado).toContain('890,00');
    expect(formatarMoeda(null)).toBe('—');
  });

  it('formata data sem escorregar de fuso', () => {
    expect(formatarData('2026-09-16')).toBe('16/09/2026');
  });

  it('gera slug sem acento', () => {
    expect(gerarSlug('Arena Sextante — São Paulo')).toBe('arena-sextante-sao-paulo');
  });

  it('converte hora em minutos', () => {
    expect(horaParaMinutos('09:30')).toBe(570);
  });
});

/* ------------------------------------------------------------------ */
/* Qualidade de dado                                                   */
/* ------------------------------------------------------------------ */
function sessaoBase(sobrescrever: Partial<Sessao> = {}): Sessao {
  return {
    id: 'ses_1',
    titulo: 'Sessão',
    descricao: 'Descrição',
    dia: '2026-09-16',
    inicio: '10:00',
    fim: '11:00',
    espacoId: 'esp_arena-mind',
    tipo: 'palestra',
    formato: 'presencial',
    trilhas: ['mind'],
    temas: ['cultura'],
    palestranteIds: ['pal_1'],
    quemTexto: 'Alguém',
    necessitaReserva: false,
    vagasTotais: null,
    vagasDisponiveis: null,
    nivel: null,
    resultadosEsperados: [],
    status: 'publicado',
    publicadoEm: null,
    publicadoPor: null,
    criadoEm: '2026-08-01T12:00:00.000Z',
    atualizadoEm: '2026-08-01T12:00:00.000Z',
    atualizadoPor: null,
    ...sobrescrever,
  };
}

describe('campos faltantes', () => {
  it('acusa sessão sem espaço, sem descrição e sem tema', () => {
    const faltando = camposFaltantesDaSessao(
      sessaoBase({ espacoId: null, descricao: '', temas: [] }),
    );
    expect(faltando).toEqual(expect.arrayContaining(['espaço', 'descrição', 'temas']));
  });

  it('não acusa nada quando a sessão está completa', () => {
    expect(camposFaltantesDaSessao(sessaoBase())).toEqual([]);
  });

  it('acusa espaço sem instrução, sem alias e sem coordenada', () => {
    const espaco: Espaco = {
      id: 'esp_1',
      nome: 'Sala',
      slug: 'sala',
      tipo: 'sala',
      aliases: [],
      descricao: '',
      comoChegar: '',
      localPrincipal: '',
      espacoPaiId: null,
      andar: '',
      coordenadaX: null,
      coordenadaY: null,
      acessivel: true,
      observacaoAcessibilidade: '',
      ativo: true,
      criadoEm: '2026-08-01T12:00:00.000Z',
      atualizadoEm: '2026-08-01T12:00:00.000Z',
      atualizadoPor: null,
    };
    expect(camposFaltantesDoEspaco(espaco)).toEqual(['como chegar', 'aliases', 'coordenadas']);
  });
});

describe('conflito de horário', () => {
  it('marca as duas sessões que se sobrepõem no mesmo espaço e dia', () => {
    const conflitos = detectarConflitos([
      sessaoBase({ id: 'a', inicio: '10:00', fim: '11:00' }),
      sessaoBase({ id: 'b', inicio: '10:30', fim: '11:30' }),
    ]);
    expect(conflitos.get('a')).toEqual(['b']);
    expect(conflitos.get('b')).toEqual(['a']);
  });

  it('encostar não é conflito', () => {
    const conflitos = detectarConflitos([
      sessaoBase({ id: 'a', inicio: '10:00', fim: '11:00' }),
      sessaoBase({ id: 'b', inicio: '11:00', fim: '12:00' }),
    ]);
    expect(conflitos.size).toBe(0);
  });

  it('espaços diferentes no mesmo horário convivem', () => {
    const conflitos = detectarConflitos([
      sessaoBase({ id: 'a', espacoId: 'esp_1' }),
      sessaoBase({ id: 'b', espacoId: 'esp_2' }),
    ]);
    expect(conflitos.size).toBe(0);
  });

  it('sessão sem espaço fica fora da detecção', () => {
    const conflitos = detectarConflitos([
      sessaoBase({ id: 'a', espacoId: null }),
      sessaoBase({ id: 'b', espacoId: null }),
    ]);
    expect(conflitos.size).toBe(0);
  });
});

describe('alertas de oferta', () => {
  const base: Oferta = {
    id: 'ofe_1',
    codigo: 'X',
    nome: 'Oferta',
    descricao: '',
    moeda: 'BRL',
    valorCentavos: 10000,
    condicoesPagamento: 'À vista',
    checkoutUrl: 'https://exemplo.invalido/checkout',
    elegibilidade: '',
    publico: 'geral',
    dataInicio: '2026-01-01',
    dataFim: '2026-12-31',
    ativo: true,
    criadoEm: '2026-08-01T12:00:00.000Z',
    atualizadoEm: '2026-08-01T12:00:00.000Z',
    atualizadoPor: null,
  };

  it('não alerta quando a oferta está completa e vigente', () => {
    expect(alertasDaOferta(base, '2026-08-20')).toEqual([]);
  });

  it('alerta sem checkout, sem valor, sem condição e vencida', () => {
    const alertas = alertasDaOferta(
      { ...base, checkoutUrl: '', valorCentavos: null, condicoesPagamento: '', dataFim: '2026-04-30' },
      '2026-08-20',
    );
    expect(alertas).toHaveLength(4);
    expect(alertas.filter((a) => a.nivel === 'erro')).toHaveLength(2);
  });
});

/* ------------------------------------------------------------------ */
/* Permissões (da interface)                                           */
/* ------------------------------------------------------------------ */
describe('matriz de permissões da interface', () => {
  it('editor salva mas não publica', () => {
    expect(pode('editor', 'editar')).toBe(true);
    expect(pode('editor', 'publicar')).toBe(false);
  });

  it('aprovador publica e arquiva', () => {
    expect(pode('aprovador', 'publicar')).toBe(true);
    expect(pode('aprovador', 'arquivar')).toBe(true);
  });

  it('analista é somente leitura', () => {
    expect(pode('analista', 'editar')).toBe(false);
    expect(pode('analista', 'ver_auditoria')).toBe(true);
  });

  it('só administrador gere usuários', () => {
    expect(pode('administrador', 'gerir_usuarios')).toBe(true);
    expect(pode('aprovador', 'gerir_usuarios')).toBe(false);
    expect(pode('atendimento', 'gerir_usuarios')).toBe(false);
  });
});
