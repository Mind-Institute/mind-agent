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
