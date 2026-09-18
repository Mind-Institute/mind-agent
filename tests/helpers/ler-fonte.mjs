/* ============================================================
   LER FONTE — sempre com LF
   ============================================================
   Vários testes daqui afirmam coisas sobre o TEXTO dos arquivos: "esta
   linha termina em `to service_role;`", "não existe linha assim". Essas
   afirmações são sobre o conteúdo, não sobre como o git materializou o
   arquivo no disco.

   No Windows o checkout escreve CRLF; no CI, LF. Um `$` de regex casa
   num caso e não casa no outro, e o teste passa numa máquina e falha na
   outra sem nada ter mudado — foi exatamente o que aconteceu ao trocar
   de branch, e o alarme apontou para a mudança errada.

   Ler sempre com LF tira o sistema operacional da conta.
*/

import { readFileSync } from 'node:fs';

export function lerFonte(url) {
  return readFileSync(url, 'utf8').replace(/\r\n/g, '\n');
}

/* ============================================================
   SEM COMENTÁRIOS
   ============================================================
   Os comentários do código CITAM o que não se deve fazer — é neles que
   está escrito por quê. Um teste que procura `location.hash = ''` ou
   `resposta.atividades` no arquivo inteiro acha a frase que explica a
   regra e acusa exatamente o código que a cumpre.

   Aconteceu três vezes nesta lane antes de virar função. A afirmação é
   sobre o que o código FAZ; então é o código que ela lê. */
export function semComentarios(fonte) {
  return fonte.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
}
