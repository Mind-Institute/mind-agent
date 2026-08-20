/* ============================================================
   QUALIDADE DE DADO
   ============================================================
   As regras que decidem o que está "faltando" moram aqui, e só aqui.
   A listagem de programação usa as mesmas funções que a visão geral —
   se as duas divergissem, o painel mentiria em uma das telas.

   O critério é sempre o mesmo: falta o que impede o agente de
   responder. Sessão sem espaço quebra "onde fica"; palco sem alias
   quebra "estou indo pro palco principal"; oferta sem checkout quebra
   "como eu compro". */

import type { Alerta, Espaco, Oferta, Palestrante, Sessao } from '@/contracts';
import { horaParaMinutos } from './format';

export function camposFaltantesDaSessao(sessao: Sessao): string[] {
  const faltando: string[] = [];
  if (!sessao.espacoId) faltando.push('espaço');
  if (!sessao.fim) faltando.push('horário final');
  if (sessao.palestranteIds.length === 0 && !sessao.quemTexto.trim()) faltando.push('palestrante');
  if (!sessao.descricao.trim()) faltando.push('descrição');
  if (sessao.temas.length === 0) faltando.push('temas');
  if (sessao.necessitaReserva && !sessao.vagasTotais) faltando.push('vagas totais');
  return faltando;
}

export function camposFaltantesDoEspaco(espaco: Espaco): string[] {
  const faltando: string[] = [];
  if (!espaco.comoChegar.trim()) faltando.push('como chegar');
  if (espaco.aliases.length === 0) faltando.push('aliases');
  if (espaco.coordenadaX === null || espaco.coordenadaY === null) faltando.push('coordenadas');
  return faltando;
}

export function camposFaltantesDoPalestrante(palestrante: Palestrante): string[] {
  const faltando: string[] = [];
  if (!palestrante.biografia.trim()) faltando.push('biografia');
  if (!palestrante.foto.trim()) faltando.push('foto');
  if (!palestrante.organizacao.trim()) faltando.push('organização');
  if (palestrante.temas.length === 0) faltando.push('temas');
  return faltando;
}

/** Espaços onde o participante se orienta por apelido: palco e arena. */
export function ehPalco(espaco: Espaco): boolean {
  return espaco.tipo === 'palco' || espaco.tipo === 'arena';
}

/** Alertas de uma oferta. `hoje` no formato AAAA-MM-DD. */
export function alertasDaOferta(oferta: Oferta, hoje: string): Alerta[] {
  const alertas: Alerta[] = [];
  if (!oferta.checkoutUrl.trim()) {
    alertas.push({ nivel: 'erro', mensagem: 'Sem checkout: ninguém consegue comprar.' });
  }
  if (oferta.valorCentavos === null) {
    alertas.push({ nivel: 'erro', mensagem: 'Sem valor: o agente não responde "quanto custa".' });
  }
  if (!oferta.condicoesPagamento.trim()) {
    alertas.push({ nivel: 'atencao', mensagem: 'Sem condição de pagamento.' });
  }
  if (oferta.dataFim && oferta.dataFim < hoje) {
    alertas.push({ nivel: 'atencao', mensagem: `Vencida em ${oferta.dataFim}.` });
  }
  return alertas;
}

/* ------------------------------------------------------------------ */
/* Conflito de horário                                                 */
/* ------------------------------------------------------------------ */
export interface Conflito {
  sessaoId: string;
  conflitaCom: string[];
}

/**
 * Duas sessões conflitam quando dividem espaço e dia e os horários se
 * sobrepõem. Encostar não é conflito: uma que termina 10:00 e outra que
 * começa 10:00 convivem.
 *
 * Ficam de fora sessão sem espaço e sessão sem hora de término (o
 * `summit.json` tem coquetéis abertos). Nos dois casos o problema é
 * outro e já aparece como campo faltante — inventar um fim para poder
 * comparar produziria conflito falso.
 */
export function detectarConflitos(sessoes: Sessao[]): Map<string, string[]> {
  const conflitos = new Map<string, string[]>();
  const porChave = new Map<string, Sessao[]>();

  for (const sessao of sessoes) {
    if (!sessao.espacoId || !sessao.fim) continue;
    const chave = `${sessao.dia}|${sessao.espacoId}`;
    const lista = porChave.get(chave);
    if (lista) lista.push(sessao);
    else porChave.set(chave, [sessao]);
  }

  for (const lista of porChave.values()) {
    for (let i = 0; i < lista.length; i += 1) {
      for (let j = i + 1; j < lista.length; j += 1) {
        const a = lista[i];
        const b = lista[j];
        const aInicio = horaParaMinutos(a.inicio);
        const aFim = horaParaMinutos(a.fim);
        const bInicio = horaParaMinutos(b.inicio);
        const bFim = horaParaMinutos(b.fim);
        if ([aInicio, aFim, bInicio, bFim].some(Number.isNaN)) continue;
        const sobrepoe = aInicio < bFim && bInicio < aFim;
        if (!sobrepoe) continue;
        conflitos.set(a.id, [...(conflitos.get(a.id) ?? []), b.id]);
        conflitos.set(b.id, [...(conflitos.get(b.id) ?? []), a.id]);
      }
    }
  }

  return conflitos;
}
