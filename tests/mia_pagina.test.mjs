/* ============================================================
   A PÁGINA DA MIA — embed no LearnWorlds
   ============================================================
   Três promessas:
   - só a escola do Mind Institute (e o próprio site) enquadram `/mia`, e
     o resto do site não ganha política nenhuma;
   - a conversa da página abre pela porta `institute_learnworlds` e nunca
     continua a sessão do concierge guardada no mesmo navegador;
   - a resposta da IA não vira HTML por conta própria.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lerFonte } from './helpers/ler-fonte.mjs';
import { ENQUADRAM_A_MIA, politicaDeEnquadramento } from '../cloudflare/roteamento.js';
import { formatarResposta } from '../mia/formato.js';

const worker = lerFonte(new URL('../cloudflare/worker.ts', import.meta.url));
const build = lerFonte(new URL('../scripts/build-cloudflare.mjs', import.meta.url));
const pagina = lerFonte(new URL('../mia.html', import.meta.url));
const tela = lerFonte(new URL('../mia/mia.js', import.meta.url));
const servico = lerFonte(new URL('../chat-service.js', import.meta.url));

/* ============================================================
   QUEM PODE ENQUADRAR
   ============================================================ */

test('/mia só pode ser enquadrada pela escola e pelo próprio site', () => {
  for (const caminho of ['/mia', '/mia/', '/mia.html']) {
    const politica = politicaDeEnquadramento(caminho);
    assert.equal(politica, "frame-ancestors 'self' https://my.mindinstitute.com.br https://*.learnworlds.com");
  }
  assert.ok(!ENQUADRAM_A_MIA.includes('*'), 'curinga solto liberaria qualquer site');
  assert.ok(ENQUADRAM_A_MIA.every((o) => o === "'self'" || o.startsWith('https://')));
});

test('o resto do site não ganha política de enquadramento', () => {
  for (const caminho of ['/', '/index.html', '/avaliacao', '/avaliacao.html', '/admin/',
                         '/mia/mia.js', '/mia/mia.css', '/miax', '/x/mia']) {
    assert.equal(politicaDeEnquadramento(caminho), null, caminho);
  }
});

test('o Worker aplica a política antes de qualquer outra saída do asset', () => {
  const asset = worker.indexOf('const resposta = await env.ASSETS.fetch(request);');
  const politica = worker.indexOf('politicaDeEnquadramento(url.pathname)');
  const fallback = worker.indexOf('if (resposta.status !== 404) return resposta;');
  assert.ok(asset > 0 && politica > asset && fallback > politica);
  assert.match(worker, /headers\.set\('Content-Security-Policy', enquadramento\)/);
});

test('a página e a pasta dela entram no build', () => {
  assert.match(build, /'mia\.html',/);
  assert.match(build, /'mia',/);
  assert.match(pagina, /<script type="module" src="\.\/mia\/mia\.js"><\/script>/);
});

/* ============================================================
   A CONVERSA DA PÁGINA
   ============================================================ */

test('a página abre pela porta própria e não lê identidade da URL', () => {
  assert.match(tela, /conversaPropria\('mia', 'institute_learnworlds'\);/);
  /* E-mail na URL não prova quem é a pessoa (P7). */
  assert.ok(!/capturarIdentidade|definirParticipante/.test(tela));
});

test('o serviço não toca no localStorage fora do armazém', () => {
  const usos = servico.match(/localStorage\.\w+/g) || [];
  /* Só o teste de disponibilidade, dentro de `ARMAZEM`. */
  assert.deepEqual(usos, ['localStorage.setItem', 'localStorage.removeItem']);
});

function armazemFalso(inicial) {
  const dados = new Map(Object.entries(inicial));
  return {
    dados,
    getItem: (k) => (dados.has(k) ? dados.get(k) : null),
    setItem: (k, v) => { dados.set(k, String(v)); },
    removeItem: (k) => { dados.delete(k); },
  };
}

function fetchFalso(corpos) {
  return async (url, init) => {
    if (String(url).includes('/auth/v1/')) {
      return new Response(JSON.stringify({
        access_token: 'tok', refresh_token: 'ref', expires_in: 3600,
      }), { status: 200 });
    }
    const corpo = JSON.parse(init.body);
    corpos.push(corpo);
    return new Response(JSON.stringify({
      ok: true,
      answer: 'oi',
      session: {
        id: '33333333-3333-4333-8333-333333333333',
        conversation_id: '44444444-4444-4444-8444-444444444444',
        token: 'b'.repeat(64),
      },
    }), { status: 200 });
  };
}

test('a conversa da MIA não continua a sessão do concierge', async () => {
  const sessaoDoApp = { id: 'app', conversation_id: 'conversa-do-concierge', token: 'a'.repeat(64) };
  const chaveDoApp = 'mindagent:v1:mind-summit-2026:chat-session';
  const armazem = armazemFalso({ [chaveDoApp]: JSON.stringify(sessaoDoApp) });
  const corpos = [];
  Object.defineProperty(globalThis, 'localStorage', { configurable: true, value: armazem });
  globalThis.fetch = fetchFalso(corpos);
  try {
    const servicoVivo = await import('../chat-service.js?mia');
    servicoVivo.conversaPropria('mia', 'institute_learnworlds');

    await servicoVivo.enviarMensagem('o que a Maslach disse sobre burnout?');
    assert.equal(corpos[0].session, undefined, 'abre conversa nova, não a do concierge');
    assert.equal(corpos[0].origem_codigo, 'institute_learnworlds');

    await servicoVivo.enviarMensagem('e na prática?');
    assert.equal(corpos[1].session.conversation_id, '44444444-4444-4444-8444-444444444444');

    assert.deepEqual(JSON.parse(armazem.dados.get(chaveDoApp)), sessaoDoApp,
      'a sessão do app fica intacta');
    assert.ok(armazem.dados.has('mindagent:v1:mind-summit-2026:mia:chat-session'));
    /* O aparelho é o mesmo: é da pessoa, não da conversa. */
    assert.ok(armazem.dados.has('mindagent:v1:mind-summit-2026:device-id'));
  } finally {
    delete globalThis.localStorage;
  }
});

test('com o armazenamento bloqueado no iframe, a conversa ainda sai', async () => {
  const corpos = [];
  Object.defineProperty(globalThis, 'localStorage', {
    configurable: true,
    get() { throw new DOMException('Access is denied for this document.', 'SecurityError'); },
  });
  globalThis.fetch = fetchFalso(corpos);
  try {
    const servicoVivo = await import('../chat-service.js?bloqueado');
    servicoVivo.conversaPropria('mia', 'institute_learnworlds');
    const resposta = await servicoVivo.enviarMensagem('oi');
    assert.equal(resposta.answer, 'oi');
    await servicoVivo.enviarMensagem('de novo');
    /* Na memória da página, a sessão continua entre um turno e outro. */
    assert.equal(corpos[1].session.conversation_id, '44444444-4444-4444-8444-444444444444');
    assert.equal(corpos[0].device_id, corpos[1].device_id);
  } finally {
    delete globalThis.localStorage;
  }
});

/* ============================================================
   O TEXTO DA RESPOSTA
   ============================================================ */

test('nada da resposta vira HTML por conta própria', () => {
  const saida = formatarResposta('<img src=x onerror="alert(1)"> e <script>x</script>');
  assert.ok(!/<img|<script/.test(saida));
  assert.match(saida, /&lt;img src=x onerror=&quot;alert\(1\)&quot;&gt;/);
  assert.ok(!/href="javascript:/.test(formatarResposta('javascript:alert(1)')));
  assert.ok(!/<a /.test(formatarResposta('http://inseguro.com')), 'só https vira link');
});

test('o Markdown que o modelo escreve vira leitura, não asterisco', () => {
  assert.equal(formatarResposta('**Tese central**: cuidar.'), '<strong>Tese central</strong>: cuidar.');
  assert.equal(formatarResposta('## Ideias principais'), '<strong>Ideias principais</strong>');
  assert.equal(formatarResposta('- primeira\n* segunda'), '• primeira\n• segunda');
  assert.equal(formatarResposta('Veja https://cvv.org.br.'),
    'Veja <a href="https://cvv.org.br" target="_blank" rel="noopener noreferrer">https://cvv.org.br</a>.');
  assert.equal(formatarResposta(null), '');
});
