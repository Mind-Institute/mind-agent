/* ============================================================
   O CONVITE POR LINK — o que não pode quebrar
   ============================================================
   Esta é a única porta da pesquisa que abre sem login: um token no link
   vale como identidade. Por isso o que se prova aqui é quase todo
   RECUSA — o caminho feliz é uma linha, e o resto é o que não pode
   acontecer.

   O que está atrás de gate é a APLICAÇÃO da migration, não o teste: o
   handler roda inteiro contra o harness, e é bom que ele rode antes de
   alguém decidir ligar.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lerFonte } from './helpers/ler-fonte.mjs';
import { chamar } from './helpers/avaliacao-harness.mjs';

const migracao = lerFonte(
  new URL('../supabase/migrations/20260918140000_avaliacao_do_evento_convite.sql', import.meta.url));
const edge = lerFonte(
  new URL('../supabase/functions/mindagent-avaliacao/index.ts', import.meta.url));

const ESTADO = '/functions/v1/mindagent-avaliacao/convite/estado';
const ENVIAR = '/functions/v1/mindagent-avaliacao/convite/enviar';

/* 64 hex, que é o formato que a Edge sorteia. */
const TOKEN = 'a'.repeat(64);

const rpcsDe = (chamadas) => chamadas.map((c) => c.nome);

function resposta(extra = {}) {
  return {
    experiencia: 'vip',
    profissao: 'Gerente de RH',
    expectativas: 'Aprender e aplicar.',
    notaRelevancia: 5,
    notaProgramacao: 4,
    ...extra,
  };
}

const CENARIO = {
  mind_avaliacao_do_evento_estado_por_convite: {
    ativo: true, motivo: null, identificado: true, porConvite: true,
    primeiroNome: 'Florence', enviado: false,
  },
  mind_avaliacao_do_evento_registrar_por_convite: {
    id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', jaRegistrado: false,
  },
};

/* ============================================================
   SEM LOGIN, MAS NÃO SEM PROVA
   ============================================================ */

test('o convite abre sem sessão — é o ponto dele', async () => {
  const { resposta: r, chamadas } = await chamar({
    caminho: ESTADO, autorizacao: null,
    cabecalhos: { 'X-Convite': TOKEN },
    rpc: CENARIO,
  });

  assert.equal(r.status, 200);
  assert.ok(rpcsDe(chamadas).includes('mind_avaliacao_do_evento_estado_por_convite'));
});

test('sem token não abre, e o erro não conta o que existe', async () => {
  for (const cabecalhos of [{}, { 'X-Convite': '' }, { 'X-Convite': 'curto' },
                            { 'X-Convite': 'Z'.repeat(64) }, { 'X-Convite': 'a'.repeat(63) }]) {
    const { resposta: r, corpo, chamadas } = await chamar({
      caminho: ESTADO, autorizacao: null, cabecalhos, rpc: CENARIO,
    });

    assert.equal(r.status, 401, `${JSON.stringify(cabecalhos)} devia ser recusado`);
    assert.equal(corpo.codigo, 'convite_invalido');
    assert.ok(!rpcsDe(chamadas).length, 'token malformado não pode chegar ao banco');
  }
});

test('o banco recebe o HASH, e nunca o token', async () => {
  const { chamadas } = await chamar({
    caminho: ESTADO, autorizacao: null,
    cabecalhos: { 'X-Convite': TOKEN }, rpc: CENARIO,
  });

  const chamada = chamadas.find((c) => c.nome === 'mind_avaliacao_do_evento_estado_por_convite');
  assert.ok(chamada);
  assert.notEqual(chamada.args.p_token_hash, TOKEN, 'o token cru não pode atravessar');
  assert.match(chamada.args.p_token_hash, /^[0-9a-f]{64}$/);
  /* SHA-256 de 64 letras "a", à unha. Fixo de propósito: trocar a função
     de hash invalidaria todos os convites vivos de uma vez, e isso tem
     de doer aqui antes de doer numa lista de mil pessoas. */
  assert.equal(
    chamada.args.p_token_hash,
    'ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb',
  );
});

test('o token vai por cabeçalho, nunca por query string', async () => {
  const { resposta: r, chamadas } = await chamar({
    caminho: ESTADO, autorizacao: null, busca: '?c=' + TOKEN, rpc: CENARIO,
  });

  assert.equal(r.status, 401, 'token na URL não pode valer');
  assert.ok(!rpcsDe(chamadas).length);
});

test('o envio por convite grava, e não leva participante do cliente', async () => {
  const { resposta: r, chamadas } = await chamar({
    metodo: 'POST', caminho: ENVIAR, autorizacao: null,
    cabecalhos: { 'X-Convite': TOKEN },
    corpo: resposta({ participanteId: '99999999-9999-4999-8999-999999999999' }),
    rpc: CENARIO,
  });

  assert.equal(r.status, 201);
  const chamada = chamadas.find((c) => c.nome === 'mind_avaliacao_do_evento_registrar_por_convite');
  assert.ok(chamada);
  assert.ok(!JSON.stringify(chamada.args.p_payload).includes('99999999'),
    'id vindo do cliente não pode atravessar');
  assert.ok(!('p_auth_user_id' in chamada.args), 'quem responde sai do token');
});

test('ausência de nota continua não virando zero, também por convite', async () => {
  for (const vazio of [null, '', false, [], undefined]) {
    const corpo = resposta();
    corpo.notaProgramacao = vazio;
    const { resposta: r, chamadas } = await chamar({
      metodo: 'POST', caminho: ENVIAR, autorizacao: null,
      cabecalhos: { 'X-Convite': TOKEN }, corpo, rpc: CENARIO,
    });
    assert.equal(r.status, 422);
    assert.ok(!rpcsDe(chamadas).includes('mind_avaliacao_do_evento_registrar_por_convite'));
  }
});

test('o convite não abre a pesquisa do dia nem o painel', async () => {
  for (const caminho of ['/functions/v1/mindagent-avaliacao/estado',
                         '/functions/v1/mindagent-avaliacao/evento/estado',
                         '/functions/v1/mindagent-avaliacao/admin/evento/relatorio']) {
    const { resposta: r } = await chamar({
      caminho, autorizacao: null, cabecalhos: { 'X-Convite': TOKEN }, rpc: CENARIO,
    });
    assert.ok(r.status === 401 || r.status === 403,
      `${caminho} não pode aceitar o token de convite (veio ${r.status})`);
  }
});

test('rota desconhecida sob /convite é 404, mesmo com token bom', async () => {
  const { resposta: r } = await chamar({
    caminho: '/functions/v1/mindagent-avaliacao/convite/respostas',
    autorizacao: null, cabecalhos: { 'X-Convite': TOKEN }, rpc: CENARIO,
  });
  assert.equal(r.status, 404);
});

/* ============================================================
   EMITIR
   ============================================================ */

test('emitir convite exige sessão de operador', async () => {
  const { resposta: r, chamadas } = await chamar({
    metodo: 'POST', caminho: '/functions/v1/mindagent-avaliacao/admin/evento/convites',
    corpo: { participantes: ['11111111-1111-4111-8111-111111111111'] },
    papelAdmin: null,
    env: { MINDAGENT_APP_URL: 'https://app.exemplo.com' },
  });

  assert.equal(r.status, 403);
  assert.ok(!rpcsDe(chamadas).includes('mind_avaliacao_do_evento_convite_criar'));
});

test('sem endereço configurado não se inventa link', async () => {
  const { resposta: r, corpo, chamadas } = await chamar({
    metodo: 'POST', caminho: '/functions/v1/mindagent-avaliacao/admin/evento/convites',
    corpo: { participantes: ['11111111-1111-4111-8111-111111111111'] },
  });

  assert.equal(r.status, 503);
  assert.equal(corpo.codigo, 'indisponivel');
  assert.ok(!rpcsDe(chamadas).includes('mind_avaliacao_do_evento_convite_criar'));
});

test('emite um link por pessoa, e o token nasce diferente a cada vez', async () => {
  const pessoas = [
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
  ];
  const { resposta: r, corpo, chamadas } = await chamar({
    metodo: 'POST', caminho: '/functions/v1/mindagent-avaliacao/admin/evento/convites',
    corpo: { participantes: pessoas, dias: 10 },
    env: { MINDAGENT_APP_URL: 'https://app.exemplo.com/' },
    rpc: { mind_avaliacao_do_evento_convite_criar: { id: 'x', expiraEm: null } },
  });

  assert.equal(r.status, 201);
  assert.equal(corpo.itens.length, 2);

  const tokens = corpo.itens.map((i) => i.url.split('#c=')[1]);
  assert.equal(new Set(tokens).size, 2, 'dois convites não podem sair com o mesmo token');
  for (const t of tokens) assert.match(t, /^[0-9a-f]{64}$/);

  /* O link fecha com uma barra só, venha a base com ela ou sem. */
  for (const i of corpo.itens) assert.match(i.url, /^https:\/\/app\.exemplo\.com\/#c=[0-9a-f]{64}$/);

  /* O que foi ao banco é o hash, e ele é diferente do token do link. */
  const criacoes = chamadas.filter((c) => c.nome === 'mind_avaliacao_do_evento_convite_criar');
  assert.equal(criacoes.length, 2);
  for (const c of criacoes) {
    assert.match(c.args.p_token_hash, /^[0-9a-f]{64}$/);
    assert.ok(!tokens.includes(c.args.p_token_hash), 'foi gravado o token cru');
  }
});

test('id que não é uuid não vira convite', async () => {
  const { resposta: r, corpo } = await chamar({
    metodo: 'POST', caminho: '/functions/v1/mindagent-avaliacao/admin/evento/convites',
    corpo: { participantes: ['nao-e-uuid', '', null, 42] },
    env: { MINDAGENT_APP_URL: 'https://app.exemplo.com' },
  });

  assert.equal(r.status, 422);
  assert.equal(corpo.campo, 'participantes');
});

test('um que falha não derruba a leva, e a mensagem do banco não vaza', async () => {
  let vez = 0;
  const { corpo } = await chamar({
    metodo: 'POST', caminho: '/functions/v1/mindagent-avaliacao/admin/evento/convites',
    corpo: {
      participantes: ['11111111-1111-4111-8111-111111111111',
                      '22222222-2222-4222-8222-222222222222'],
    },
    env: { MINDAGENT_APP_URL: 'https://app.exemplo.com' },
    rpc: {
      mind_avaliacao_do_evento_convite_criar: () => {
        vez += 1;
        return vez === 1
          ? { __erro: 'avaliacao_ja_enviada', __code: '23505' }
          : { id: 'x', expiraEm: null };
      },
    },
  });

  assert.equal(corpo.itens.length, 2);
  assert.equal(corpo.itens[0].emitido, false);
  assert.equal(corpo.itens[0].codigo, '23505');
  assert.ok(!('url' in corpo.itens[0]), 'quem falhou não recebe link');
  assert.equal(corpo.itens[1].emitido, true);
  assert.ok(!JSON.stringify(corpo).includes('avaliacao_ja_enviada'),
    'a mensagem do banco não é para o operador ler');
});

/* ============================================================
   A MIGRATION, LIDA COMO TEXTO
   ============================================================ */

test('o token nunca é gravado — só o hash', () => {
  assert.match(migracao, /token_hash text not null/);
  assert.match(migracao, /check \(token_hash ~ '\^\[0-9a-f\]\{64\}\$'\)/);
  assert.ok(!/\btoken text\b/.test(migracao), 'não pode existir coluna de token cru');
});

test('desconhecido e revogado devolvem o mesmo motivo', () => {
  const resolver = migracao.slice(
    migracao.indexOf('mind_avaliacao_do_evento_convite_resolver('),
    migracao.indexOf('-- 5 · As duas portas'));
  assert.match(resolver, /if not found or v_convite\.revogado_em is not null then/);
  const invalidos = resolver.match(/'motivo', 'invalido'/g) || [];
  assert.ok(invalidos.length >= 2, 'os dois caminhos têm de dizer a mesma coisa');
});

test('o convite sempre tem fim', () => {
  assert.match(migracao, /expira_em timestamptz not null/);
  assert.match(migracao, /avaliacao_validacao:expira_em/);
});

test('reemitir troca o token do mesmo convite, e não cria um segundo', () => {
  assert.match(migracao, /unique \(participante_id, event_id\)/);
  assert.match(migracao, /on conflict \(participante_id, event_id\) do update/);
  assert.match(migracao, /revogado_em = null/);
});

test('o convite se queima na mesma transação da resposta', () => {
  const registrar = migracao.slice(migracao.indexOf('mind_avaliacao_do_evento_registrar_por_convite('));
  assert.match(registrar, /avaliacao_do_evento_gravar\(/);
  assert.match(registrar, /set usado_em = now\(\)/);
  assert.ok(registrar.indexOf('avaliacao_do_evento_gravar(') < registrar.indexOf('set usado_em = now()'),
    'o convite só se queima depois de a resposta passar');
});

test('as duas portas disputam a mesma trava', () => {
  const gravar = migracao.slice(migracao.indexOf('engagement.avaliacao_do_evento_gravar('));
  assert.match(gravar, /pg_advisory_xact_lock/);
  /* A trava é sobre a pessoa e o evento, e não sobre por onde ela
     entrou: senão app e convite gravariam duas respostas. */
  assert.match(gravar, /hashtext\(p_participante_id::text \|\| p_event_id::text\)/);
});

test('o corpo da gravação não é porta: sem grant para ninguém', () => {
  assert.match(migracao, /revoke execute on function engagement\.avaliacao_do_evento_gravar/);
  assert.ok(!/grant execute on function engagement\.avaliacao_do_evento_gravar/.test(migracao));
});

test('as funções do convite são só do service_role', () => {
  for (const f of ['convite_resolver', 'convite_criar',
                   'estado_por_convite', 'registrar_por_convite']) {
    const nome = `mind_avaliacao_do_evento_${f}`;
    assert.ok(migracao.includes(`revoke execute on function public.${nome}`), `falta revoke em ${nome}`);
    assert.ok(new RegExp(`grant execute on function public\\.${nome}[^;]*to service_role`).test(migracao),
      `${nome} tem de ser só do service_role`);
  }
  assert.ok(!/to (anon|authenticated)/.test(migracao));
});

test('a migration está marcada como gate', () => {
  assert.match(migracao, /GATE/);
  assert.match(migracao, /NÃO aplicada/);
});

test('a Edge sorteia 32 bytes do sistema, e não algo derivado da pessoa', () => {
  assert.match(edge, /crypto\.getRandomValues\(new Uint8Array\(32\)\)/);
  assert.match(edge, /crypto\.subtle\.digest\("SHA-256"/);
});

/* ============================================================
   A ENTRADA NO APP, LIDA COMO TEXTO
   ============================================================ */

const app = lerFonte(new URL('../app.js', import.meta.url));
const servico = lerFonte(new URL('../avaliacao/servico.js', import.meta.url));
const tela = lerFonte(new URL('../avaliacao/evento.js', import.meta.url));
const estilo = lerFonte(new URL('../styles.css', import.meta.url));

/* Os comentários do app CITAM o que não se deve fazer — é lá que está
   escrito por quê. A conferência é sobre o código. */
const semComentarios = (fonte) =>
  fonte.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

test('o token é lido do fragmento e apagado da barra de endereço', () => {
  const codigo = semComentarios(app);
  assert.match(codigo, /location\.hash/);
  assert.match(codigo, /history\.replaceState\(null, '', location\.pathname \+ location\.search\)/);
  /* `location.hash = ''` deixaria o `#` na barra e empilharia histórico. */
  assert.ok(!/location\.hash\s*=[^=]/.test(codigo));
});

test('o token nunca vai para o armazenamento local', () => {
  const bloco = servico.slice(servico.indexOf('let convite = null'),
    servico.indexOf('export async function carregarEstadoDoEvento'));
  assert.ok(!/localStorage|sessionStorage/.test(bloco));
  assert.match(servico, /^let convite = null;$/m);
});

test('por convite não se abre sessão nenhuma', () => {
  const chamar = servico.slice(servico.indexOf('async function chamar('),
    servico.indexOf('export async function carregarEstado('));
  assert.match(chamar, /const porConvite = caminho\.startsWith\('\/convite\/'\)/);
  assert.match(chamar, /porConvite \? null : await token\(\)/);
});

test('o e-mail da Yazo não vai junto do convite', () => {
  const chamar = servico.slice(servico.indexOf('async function chamar('),
    servico.indexOf('export async function carregarEstado('));
  assert.match(chamar, /porConvite \? \{\} : cabecalhosDaIdentidade\(\)/);
});

test('o token viaja em cabeçalho, e não na URL montada aqui', () => {
  assert.match(servico, /'X-Convite': convite/);
  assert.ok(!/[?&]c=/.test(servico), 'nada nesta camada põe o token numa URL');
});

test('quem chega por convite não vê home nem chat', () => {
  const entrada = app.slice(app.indexOf('if (conviteDaUrl())'), app.indexOf('/* ---------- Partida'));
  assert.match(entrada, /abrirVista\('avaliacao'\)/);
  assert.ok(!/montarHomeV3|iniciarChat/.test(entrada));
});

test('o voltar some quando não há para onde voltar', () => {
  assert.match(app, /getElementById\('avaliacao-voltar'\)\.hidden = true/);
  /* `hidden` sozinho não esconde: `.c-voltar` define `display`, e a
     regra do navegador tem especificidade zero. */
  assert.match(estilo, /\.c-voltar\[hidden\] \{ display: none; \}/);
  assert.match(tela, /if \(aoVoltar\) \{/);
});

test('a instrução de erro muda quando não existe home atrás', () => {
  assert.match(tela, /Recarregue esta página em instantes/);
  assert.match(tela, /Este link não é mais válido/);
  assert.match(tela, /Peça um novo link para a organização/);
});

test('colar o link numa aba já aberta não falha em silêncio', () => {
  assert.match(app, /addEventListener\('hashchange'/);
  assert.match(app, /location\.reload\(\)/);
});
