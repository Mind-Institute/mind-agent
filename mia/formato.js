/* ============================================================
   O TEXTO DA RESPOSTA DA MIA
   ============================================================
   A resposta chega como texto. O modelo às vezes escreve no formato de
   Markdown (`**negrito**`, `- item`, `## título`), e asterisco cru na
   tela é ruído. Primeiro TUDO é escapado; depois só dois elementos
   voltam: `<strong>` e link https. Nada que venha da resposta vira HTML
   por conta própria.

   Separado da tela para ser testado sem navegador.
*/

function escapar(texto) {
  return texto
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function formatarResposta(texto) {
  return escapar(String(texto ?? ''))
    .split('\n')
    .map((linha) => {
      const titulo = linha.match(/^\s{0,3}#{1,4}\s+(.+)$/);
      if (titulo) return '<strong>' + titulo[1].replace(/\*\*/g, '') + '</strong>';
      return linha.replace(/^(\s*)[-*]\s+/, '$1• ');
    })
    .join('\n')
    .replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>')
    .replace(/https:\/\/[^\s<]+[^\s<.,;:!?)\]]/g,
      (url) => '<a href="' + url + '" target="_blank" rel="noopener noreferrer">' + url + '</a>');
}
