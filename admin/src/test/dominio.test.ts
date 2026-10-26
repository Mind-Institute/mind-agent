import { describe, expect, it } from 'vitest';
import {
  mascararEmail,
  mascararIdentificador,
  mascararNome,
  mascararTelefone,
  mascararTextoLivre,
} from '@/lib/mask';
import { formatarMoeda, formatarData, gerarSlug, horaParaMinutos } from '@/lib/format';
import { pode } from '@/lib/permissions';

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
