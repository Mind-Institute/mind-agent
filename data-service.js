/* ============================================================
   CAMADA DE DADOS — a única porta de entrada de conteúdo
   ============================================================
   O resto da aplicação não sabe de onde vem a programação: chama
   `carregarDadosSummit()` e recebe sempre a mesma forma. Trocar o
   arquivo local pela API do `mindagent-bootstrap` é preencher
   `CONFIG.apiBaseUrl` — nenhuma outra linha do frontend muda.

   CONTRATO
   --------
   carregarDadosSummit() → Promise<Dados>

   Dados = {
     evento:  { nome, dias: [ISO, ISO], local, regra_reserva, regra_vagas },
     temas:   [ { codigo, rotulo } ],
     sessoes: [ { id, dia, inicio, fim, titulo, descricao, quem, espaco,
                  formato, etiqueta, trilhas[], vaga_limitada, online,
                  temas[] } ],
     pessoas: [ { nome, credencial, resumo, foto, destaque, na_grade,
                  temas[] } ]
   }

   - Resolve com o objeto acima, já conferido: se vier faltando peça,
     é erro, não meia tela.
   - Rejeita com um Error cuja `message` diz qual origem falhou e por quê
     — a página mostra isso e não inventa conteúdo no lugar.
   - Não guarda estado nem cache: quem chama decide quando recarregar.
*/

import { CONFIG } from './config.js';

const CAMINHO_LOCAL = './dados/summit.json';

/* Onde a API vai responder. Só existe para não espalhar montagem de URL
   pela aplicação — o formato definitivo vem com o mindagent-bootstrap. */
function urlDaApi() {
  const raiz = String(CONFIG.apiBaseUrl).replace(/\/+$/, '');
  return raiz + '/eventos/' + encodeURIComponent(CONFIG.eventSlug) + '/summit';
}

/* A ordem em que as origens são tentadas. Hoje só há a local; com a API
   configurada ela vem primeiro e o arquivo vira rede de segurança. */
function origens() {
  const lista = [];
  if (CONFIG.apiBaseUrl) lista.push({ tipo: 'api', url: urlDaApi() });
  if (CONFIG.useLocalFallback) lista.push({ tipo: 'local', url: CAMINHO_LOCAL });
  return lista;
}

async function buscar(url) {
  const r = await fetch(url, { cache: 'no-store' });
  if (!r.ok) throw new Error('HTTP ' + r.status);
  return r.json();
}

/* Conferência mínima: a página prefere falhar a desenhar pela metade. */
function conferir(dados) {
  if (!dados || typeof dados !== 'object') throw new Error('resposta vazia');
  const listas = ['temas', 'sessoes', 'pessoas'];
  const faltando = listas.filter((k) => !Array.isArray(dados[k]));
  if (!dados.evento || !Array.isArray(dados.evento.dias)) faltando.push('evento.dias');
  if (faltando.length) throw new Error('faltando ' + faltando.join(', '));
  return dados;
}

/* ============================================================
   HOME V3 — avisos e composição no ar
   ============================================================
   Porta separada da programação, e de propósito: quem publica isto é o
   painel administrativo, não a grade do evento. Falha aqui não derruba
   a página — o app tem lista embutida e cai nela.

   carregarHomeDoEvento() → Promise<{ avisos, home } | null>

   `null` quer dizer "a API não respondeu por isso", e é diferente de
   `{ avisos: [] }`, que quer dizer "não há aviso nenhum em circulação".
   O app trata os dois casos de forma diferente, então esta função não
   pode inventar lista vazia quando dá erro. */
export async function carregarHomeDoEvento() {
  if (!CONFIG.homeApiUrl) return null;
  const raiz = String(CONFIG.homeApiUrl).replace(/\/+$/, '');
  const url = raiz + '/publico?event_slug=' + encodeURIComponent(CONFIG.eventSlug);
  try {
    const r = await fetch(url, { cache: 'no-store' });
    if (!r.ok) return null;
    const dados = await r.json();
    return dados && typeof dados === 'object' && Array.isArray(dados.avisos) ? dados : null;
  } catch (e) {
    return null;
  }
}

/* ============================================================
   O TIPO DE INGRESSO DE QUEM ABRIU O APP
   ============================================================
   Só para o cabeçalho: "EXPERIÊNCIA VIP" e a pílula ao lado do `?`.

   O e-mail vai no CORPO, nunca na URL. O app inteiro trabalha para
   manter e-mail fora de barra de endereço e de histórico — mandá-lo em
   query string o devolveria para o log de borda pela porta dos fundos.

   `null` é a resposta para tudo que não é certeza: API desligada, sem
   e-mail, rede caída, e-mail fora do espelho, ingresso sem tipo
   mapeado, ingresso revogado. Quem chama não precisa distinguir — o
   cabeçalho, sem tipo, é o de sempre.

   A FORMA É CONFERIDA AQUI, e não a lista. Começou como lista fechada —
   VIP, Mind, Prime —, e ela se calou sozinha assim que o espelho ganhou
   `Camarote`: 54 pessoas sem pílula, sem erro nenhum na tela. Uma lista
   de nomes num arquivo de front-end é uma promessa de que alguém vai
   lembrar de voltar aqui, e ninguém lembra.

   O que a tela precisa garantir é outra coisa: que o cabeçalho não vire
   campo de texto livre. Uma palavra ou duas, letras e espaço, até 24
   caracteres — cabe qualquer rótulo comercial e não cabe uma frase.
   Quem decide o que é tipo de verdade é a função no banco.

   carregarIngressoDoParticipante(email) → Promise<string|null> */
const FORMATO_INGRESSO = /^\p{L}[\p{L} -]{1,23}$/u;

export async function carregarIngressoDoParticipante(email) {
  if (!CONFIG.homeApiUrl || !email) return null;
  const raiz = String(CONFIG.homeApiUrl).replace(/\/+$/, '');
  try {
    const r = await fetch(raiz + '/participante', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      cache: 'no-store',
      body: JSON.stringify({ email }),
    });
    if (!r.ok) return null;
    const dados = await r.json();
    const tipo = dados && typeof dados.ingresso === 'string' ? dados.ingresso.trim() : null;
    return tipo && FORMATO_INGRESSO.test(tipo) ? tipo : null;
  } catch (e) {
    return null;
  }
}

export async function carregarDadosSummit() {
  const fontes = origens();
  if (!fontes.length) {
    throw new Error('nenhuma origem configurada — apiBaseUrl está nula e useLocalFallback desligado');
  }

  let ultimoErro = null;
  for (const fonte of fontes) {
    try {
      return conferir(await buscar(fonte.url));
    } catch (e) {
      ultimoErro = new Error(fonte.tipo + ' ' + fonte.url + ': ' + e.message);
    }
  }
  throw ultimoErro;
}
