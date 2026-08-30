/* ============================================================================
   CONTRATO DA SUPERFÍCIE DO PLAY NO APP
   ----------------------------------------------------------------------------
   Este arquivo é TESTE. Ele sobe o app estático e dirige o navegador de
   verdade: nenhum mock de DOM, nenhuma reimplementação do fluxo.

   O que ele trava é o que a Lane E prometeu na tela:
     1. a intenção "Registrar meus insights" existe na home;
     2. a coleta abre com sessões, a pergunta da nota e 11 alvos (0..10);
     3. a nota é destocável — um toque errado não vira avaliação;
     4. só a nota, sem texto, já é coleta válida (preenchimento parcial);
     5. sem endpoint de ação, a tela NÃO diz que gravou;
     6. o `play-service.js` recusa id de sessão não canônico antes de gastar
        uma chamada de ferramenta, e os nomes batem com `concierge.ferramentas`.

   O contrato 5 é o que mais importa: antes desta lane a tela dizia "Guardei."
   sem que nada saísse do navegador.

   COMO RODAR
     npx -y serve . -l 4173 &
     npm i --no-save playwright
     node tests/play_superficie_app.spec.mjs

   `playwright` NÃO é dependência do projeto de propósito: este teste é de
   superfície e roda sob demanda, não no caminho de build do app.
   ============================================================================ */


import { chromium } from 'playwright';

const erros = [];
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
const pg = await b.newPage();
pg.on('pageerror', (e) => erros.push('pageerror: ' + e.message));
// Erro de REDE aqui é o sandbox, não o app: este ambiente bloqueia a saída
// para supabase.co, e o `data-service.js` cai no fallback local de propósito.
// O que não pode passar é erro de JavaScript.
pg.on('console', (m) => {
  const t = m.text();
  if (m.type() !== 'error') return;
  if (/ERR_TUNNEL_CONNECTION_FAILED|Failed to load resource|net::ERR_/.test(t)) return;
  erros.push('console: ' + t);
});

// O guia da barra abre sozinho na primeira visita e cobre a home. Marcar como
// visto ANTES de carregar é o mesmo caminho do usuário que já viu o guia.
await pg.addInitScript(() => {
  try { localStorage.setItem('mindagent:v1:mind-summit-2026:guia-visto', '1'); } catch (e) {}
});
await pg.goto('http://localhost:4173/', { waitUntil: 'networkidle' });
await pg.evaluate(() => document.getElementById('pular')?.click());
await pg.waitForTimeout(500);
await pg.evaluate(() => document.getElementById('guia-pular')?.click());
await pg.waitForTimeout(400);

// Contrato 1: a intenção "Registrar meus insights" existe na home.
const btn = pg.locator('[data-intencao="insight"]');
if (await btn.count() !== 1) throw new Error('FALHA 1: intenção insight não está na home');

// Caminho real do usuário: `insight` pendura o registro numa sessão, e as
// sessões candidatas saem da afinidade por tema. Quem nunca marcou tema não
// tem onde pendurar — então o percurso passa por escolher tema primeiro,
// exatamente como no app.
await pg.locator('[data-intencao="palestras"]').click();
await pg.waitForTimeout(1500);
await pg.locator('.chips button[data-tema]').first().click();
await pg.locator('button.avancar', { hasText: 'Pronto, continuar' }).click();
await pg.waitForTimeout(1200);

await pg.locator('#vista-chat .c-voltar[data-volta]').click();
await pg.waitForTimeout(700);
await pg.locator('[data-intencao="insight"]').click();
await pg.waitForTimeout(1400);

// Contrato 2: a coleta abre com sessões, a pergunta da nota e 11 alvos 0..10.
const sessoes = pg.locator('.ins .chips.sessoes button');
const notas   = pg.locator('.ins .chips.nota button');
const perg    = pg.locator('.ins-pergunta');
if (await sessoes.count() < 1) throw new Error('FALHA 2: sem chips de sessão');
if (await notas.count() !== 11) throw new Error('FALHA 2: nota tem ' + await notas.count() + ' alvos, esperado 11');
const textoPergunta = (await perg.first().textContent()).trim();
if (textoPergunta !== 'De 0 a 10, quanto essa sessão foi útil para você?')
  throw new Error('FALHA 2: pergunta da nota divergiu do template ciclo.nota: ' + textoPergunta);

// Contrato 3: a nota é destocável — toque errado não vira avaliação.
await notas.nth(9).click();
if (await notas.nth(9).getAttribute('aria-pressed') !== 'true') throw new Error('FALHA 3: nota não marcou');
await notas.nth(9).click();
if (await notas.nth(9).getAttribute('aria-pressed') !== 'false') throw new Error('FALHA 3: nota não desmarcou');

// Contrato 4: só nota, sem texto, já é coleta válida (preenchimento parcial).
await notas.nth(10).click();
await pg.locator('button.avancar', { hasText: 'Guardar no meu Summit' }).click();
await pg.waitForTimeout(1200);

// Contrato 5: sem endpoint e sem id canônico, a tela NÃO pode dizer que gravou.
const balao = (await pg.locator('#mensagens .bolha.mind').last().textContent() || '').trim();
if (/Guardei\./.test(balao))
  throw new Error('FALHA 5: disse que guardou sem ter gravado. Balão: ' + balao);
if (!/Ainda não consigo registrar isso no sistema do evento/.test(balao))
  throw new Error('FALHA 5: não avisou que não gravou. Balão: ' + balao);

// Contrato 6: o guard client-side recusa id slug antes de gastar chamada.
const r = await pg.evaluate(async () => {
  const m = await import('/play-service.js');
  return {
    slug:   await m.registrarFeedbackSessao({ sessao_id: 'd1-09_00-abertura', nota: 10 }),
    uuid:   await m.registrarFeedbackSessao({ sessao_id: '11111111-1111-4111-8111-111111111111', nota: 10 }),
    nps:    await m.registrarNps({ nota: 9 }),
    tools:  m.FERRAMENTAS,
  };
});
if (r.slug.motivo !== 'sessao_sem_id_canonico') throw new Error('FALHA 6: slug devia dar sessao_sem_id_canonico, veio ' + JSON.stringify(r.slug));
if (r.uuid.motivo !== 'sem_endpoint')          throw new Error('FALHA 6: uuid devia parar em sem_endpoint, veio ' + JSON.stringify(r.uuid));
if (r.nps.motivo  !== 'sem_endpoint')          throw new Error('FALHA 6: nps devia parar em sem_endpoint, veio ' + JSON.stringify(r.nps));
if (r.tools.feedbackSessao !== 'registrar_feedback_sessao' || r.tools.nps !== 'registrar_nps')
  throw new Error('FALHA 6: nomes de ferramenta divergem do registro: ' + JSON.stringify(r.tools));

if (erros.length) throw new Error('ERROS DE RUNTIME NO APP:\n' + erros.join('\n'));

console.log('OK — 6 contratos de superfície do Play passaram');
console.log('   balão exibido:', balao.slice(0, 90) + '…');
await b.close();
