/* ============================================================
   FOTOS DOS PALESTRANTES
   ============================================================
   O campo `foto` do summit.json guarda um caminho relativo
   (`palestrantes/amy.webp`) que o chat resolve contra `assets/`. O
   painel precisa do mesmo arquivo, mas com o caminho que o bundler
   gerou — daí o mapa montado em build por `import.meta.glob`.

   Os arquivos continuam pertencendo ao chat: aqui só são lidos. */

const ARQUIVOS = import.meta.glob('../../../assets/palestrantes/*.webp', {
  eager: true,
  query: '?url',
  import: 'default',
}) as Record<string, string>;

const POR_NOME = new Map<string, string>();
for (const [caminho, url] of Object.entries(ARQUIVOS)) {
  const nome = caminho.split('/').pop();
  if (nome) POR_NOME.set(nome, url);
}

/** `palestrantes/amy.webp` → URL empacotada, ou `null` se não existir. */
export function urlDaFoto(caminho: string | null | undefined): string | null {
  if (!caminho) return null;
  const nome = caminho.split('/').pop();
  if (!nome) return null;
  return POR_NOME.get(nome) ?? null;
}
