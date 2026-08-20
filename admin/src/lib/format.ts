/* ============================================================
   FORMATAÇÃO — pt-BR em um lugar só
   ============================================================ */

const LOCALE = 'pt-BR';
const FUSO = 'America/Sao_Paulo';

/** Formata centavos em BRL. `null`/`undefined` viram travessão. */
export function formatarMoeda(
  valorEmCentavos: number | null | undefined,
  moeda = 'BRL',
): string {
  if (valorEmCentavos === null || valorEmCentavos === undefined || Number.isNaN(valorEmCentavos)) {
    return '—';
  }
  return new Intl.NumberFormat(LOCALE, {
    style: 'currency',
    currency: moeda,
  }).format(valorEmCentavos / 100);
}

/** `2026-09-16` → `16/09/2026`. Sem `new Date()` para não escorregar de fuso. */
export function formatarData(iso: string | null | undefined): string {
  if (!iso) return '—';
  const soData = iso.slice(0, 10);
  const partes = soData.split('-');
  if (partes.length !== 3) return iso;
  const [ano, mes, dia] = partes;
  return `${dia}/${mes}/${ano}`;
}

/** `2026-09-16` → `16 de setembro de 2026`. */
export function formatarDataExtenso(iso: string | null | undefined): string {
  if (!iso) return '—';
  const data = new Date(`${iso.slice(0, 10)}T12:00:00Z`);
  if (Number.isNaN(data.getTime())) return iso;
  return new Intl.DateTimeFormat(LOCALE, {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(data);
}

/** Timestamp ISO → `16/09/2026 09:30`, no fuso do evento. */
export function formatarDataHora(iso: string | null | undefined): string {
  if (!iso) return '—';
  const data = new Date(iso);
  if (Number.isNaN(data.getTime())) return iso;
  return new Intl.DateTimeFormat(LOCALE, {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: FUSO,
  }).format(data);
}

/** Distância relativa curta: `há 3 min`, `há 2 h`, `há 4 d`. */
export function formatarRelativo(iso: string | null | undefined, agora = Date.now()): string {
  if (!iso) return '—';
  const t = new Date(iso).getTime();
  if (Number.isNaN(t)) return iso;
  const segundos = Math.round((t - agora) / 1000);
  const abs = Math.abs(segundos);
  const rtf = new Intl.RelativeTimeFormat(LOCALE, { numeric: 'auto', style: 'narrow' });
  if (abs < 60) return rtf.format(Math.round(segundos), 'second');
  if (abs < 3600) return rtf.format(Math.round(segundos / 60), 'minute');
  if (abs < 86400) return rtf.format(Math.round(segundos / 3600), 'hour');
  return rtf.format(Math.round(segundos / 86400), 'day');
}

/** Minutos → `1 h 30 min`. */
export function formatarDuracao(minutos: number | null | undefined): string {
  if (minutos === null || minutos === undefined) return '—';
  if (minutos < 60) return `${minutos} min`;
  const h = Math.floor(minutos / 60);
  const m = minutos % 60;
  return m ? `${h} h ${m} min` : `${h} h`;
}

/** Metros → `120 m` ou `1,2 km`. */
export function formatarDistancia(metros: number | null | undefined): string {
  if (metros === null || metros === undefined) return '—';
  if (metros < 1000) return `${metros} m`;
  return `${new Intl.NumberFormat(LOCALE, { maximumFractionDigits: 1 }).format(metros / 1000)} km`;
}

export function formatarNumero(n: number | null | undefined): string {
  if (n === null || n === undefined) return '—';
  return new Intl.NumberFormat(LOCALE).format(n);
}

/** `Arena Mind` → `arena-mind`. Usado na sugestão de slug dos formulários. */
export function gerarSlug(texto: string): string {
  return texto
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
}

/** `09:30` → 570. Base da detecção de conflito de horário.
 *  Hora ausente vira `NaN`: quem chama decide o que fazer com isso. */
export function horaParaMinutos(hora: string | null | undefined): number {
  if (!hora) return Number.NaN;
  const [h, m] = hora.split(':').map((n) => Number.parseInt(n, 10));
  if (Number.isNaN(h) || Number.isNaN(m)) return Number.NaN;
  return h * 60 + m;
}
