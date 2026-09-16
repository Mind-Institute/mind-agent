/* ============================================================
   Avaliação do dia — a exportação em CSV
   ============================================================
   Planilha é o destino real deste dado, e planilha é exigente:

   1. ACENTO. Excel no Windows lê CSV como ANSI se não houver BOM. Sem
      ele, "avaliação" vira "avaliaÃ§Ã£o" na abertura por duplo clique.
      O BOM UTF-8 resolve, e o Google Sheets o ignora sem reclamar.

   2. QUEBRA DE LINHA. As respostas abertas têm parágrafos. Um `\n` solto
      dentro de um campo quebra a linha do CSV — a menos que o campo
      esteja entre aspas, e é por isso que TODO campo sai entre aspas.
      As aspas de dentro viram duas, como manda o RFC 4180.

   3. FÓRMULA. Um texto começando com `=`, `+`, `-`, `@`, TAB ou CR é
      executado como fórmula ao abrir — é a injeção de fórmula em CSV, e
      "=1+1" é o caso inocente. Prefixamos com aspa simples, que a
      planilha entende como "isto é texto" e não mostra na célula.

   O separador é `;` porque é o que o Excel em português espera. */

const PERIGOSOS = /^[=+\-@\t\r]/;

/* Escrito como código, não como caractere: colado literalmente no início
   do arquivo ele fica invisível em qualquer editor e some no primeiro
   `trim` distraído — e aí só se descobre quando o acento quebra. */
const BOM = String.fromCharCode(0xfeff);

function celula(valor: unknown): string {
  if (valor === null || valor === undefined) return '""';
  let texto = String(valor);
  if (PERIGOSOS.test(texto)) texto = `'${texto}`;
  return `"${texto.replace(/"/g, '""')}"`;
}

export function montarCsv(cabecalho: string[], linhas: unknown[][]): string {
  const corpo = [cabecalho, ...linhas]
    .map((linha) => linha.map(celula).join(';'))
    .join('\r\n');
  return BOM + corpo;
}

/** Dispara o download no navegador. Nada sai da máquina de quem clicou. */
export function baixarCsv(nome: string, conteudo: string) {
  const blob = new Blob([conteudo], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = nome;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  /* Sem isto o blob fica na memória da aba até ela fechar. */
  setTimeout(() => URL.revokeObjectURL(url), 0);
}
