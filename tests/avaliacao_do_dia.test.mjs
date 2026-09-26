/* ============================================================
   AVALIAÇÃO DO DIA — o que não pode quebrar
   ============================================================
   Três camadas, três jeitos de provar:

   1. A Edge, executada de verdade pelo harness — identidade, validação,
      permissão e tradução de erro são comportamento, e comportamento se
      prova rodando.
   2. A migration, lida como texto — as garantias que moram em
      `constraint` e em `unique` não têm como rodar aqui sem banco, mas
      somem de um diff sem parecer erro.
   3. O módulo do app e o CSV do painel, lidos como texto pelo mesmo
      motivo.

   O que NÃO está aqui e está no relatório: o que só um banco de verdade
   responde (transação, lock, unicidade sob concorrência).
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lerFonte } from './helpers/ler-fonte.mjs';
import { chamar, respostaValida, erroRpc, AUTH_USER_ID, SESSAO_VALIDA } from './helpers/avaliacao-harness.mjs';

const migracao = lerFonte(
  new URL('../supabase/migrations/20260916210000_avaliacao_do_dia.sql', import.meta.url));
const tela = lerFonte(new URL('../avaliacao/avaliacao.js', import.meta.url));
const servico = lerFonte(new URL('../avaliacao/servico.js', import.meta.url));
const estilo = lerFonte(new URL('../avaliacao/avaliacao.css', import.meta.url));
const build = lerFonte(new URL('../scripts/build-cloudflare.mjs', import.meta.url));
const configApp = lerFonte(new URL('../config.js', import.meta.url));

/* ============================================================
   A EDGE, RODANDO
   ============================================================ */

test('quem responde é o dono do token — nunca um id mandado pelo cliente', async () => {
  const { resposta, chamadas } = await chamar({
    metodo: 'POST',
    caminho: '/functions/v1/mindagent-avaliacao/enviar',
    corpo: respostaValida({ participanteId: '99999999-9999-4999-8999-999999999999' }),
  });

  assert.equal(resposta.status, 201);
  const registrar = chamadas.find((c) => c.nome === 'mind_avaliacao_do_dia_registrar');
  assert.ok(registrar, 'a gravação precisa ter sido chamada');
  assert.equal(registrar.args.p_auth_user_id, AUTH_USER_ID);
  /* O id inventado pelo cliente não chega ao banco por nenhum caminho. */
  assert.ok(!JSON.stringify(registrar.args).includes('99999999-9999-4999-8999-999999999999'));
});

test('sem token não há pesquisa, e a orientação é entrar pelo app do evento', async () => {
  const { resposta, corpo } = await chamar({ autorizacao: null });
  assert.equal(resposta.status, 401);
  assert.equal(corpo.codigo, 'sem_sessao');
  assert.match(corpo.mensagem, /app do evento/i);
});

test('sem identidade canônica, a Edge liga pelo e-mail da Yazo e lê de novo', async () => {
  let ligou = false;
  const { corpo, chamadas } = await chamar({
    cabecalhos: { 'X-Identidade-Email': 'alguem@example.com', 'X-Identidade-Nome': 'Alguém' },
    rpc: {
      mind_identidade_resolver: () => { ligou = true; return { pessoa_id: 'x' }; },
      mind_avaliacao_do_dia_estado: () => (ligou
        ? { ativo: true, identificado: true, dia: '2026-09-16', atividades: [] }
        : { ativo: true, identificado: false, dia: '2026-09-16', atividades: [] }),
    },
  });

  assert.equal(corpo.identificado, true);
  const resolver = chamadas.find((c) => c.nome === 'mind_identidade_resolver');
  assert.ok(resolver, 'a porta canônica de identidade precisa ser a usada');
  /* Os MESMOS argumentos que a `mindagent-chat` usa na primeira mensagem:
     não nasce um segundo jeito de resolver quem é a pessoa. */
  assert.equal(resolver.args.p_canal, 'mindagent-web');
  assert.deepEqual(resolver.args.p_identificadores,
    { email: 'alguem@example.com', auth_user_id: AUTH_USER_ID });
  /* Lido duas vezes: antes e depois de ligar. */
  assert.equal(chamadas.filter((c) => c.nome === 'mind_avaliacao_do_dia_estado').length, 2);
});

test('o e-mail vai por cabeçalho e nunca por query string', async () => {
  const { chamadas } = await chamar({
    cabecalhos: { 'X-Identidade-Email': 'alguem@example.com' },
    rpc: { mind_avaliacao_do_dia_estado: { ativo: true, identificado: true, dia: '2026-09-16', atividades: [] } },
  });
  const tudo = JSON.stringify(chamadas);
  assert.ok(!tudo.includes('email=alguem'), 'e-mail não pode virar parâmetro de URL');
});

test('nota zero atravessa; nota fora da faixa e nota quebrada não', async () => {
  const zero = await chamar({
    metodo: 'POST',
    caminho: '/functions/v1/mindagent-avaliacao/enviar',
    corpo: respostaValida({ notaRelevancia: 0, notaProgramacao: 0 }),
  });
  assert.equal(zero.resposta.status, 201);
  const args = zero.chamadas.find((c) => c.nome === 'mind_avaliacao_do_dia_registrar').args;
  assert.equal(args.p_payload.notaRelevancia, 0);
  assert.equal(args.p_payload.notaProgramacao, 0);
  /* Zero chega como número, não como ausência. */
  assert.equal(args.p_payload.atividades[0].nota, 0);

  const quebrada = await chamar({
    metodo: 'POST',
    caminho: '/functions/v1/mindagent-avaliacao/enviar',
    corpo: respostaValida({ notaRelevancia: 3.5 }),
  });
  assert.equal(quebrada.resposta.status, 422);
  assert.equal(quebrada.corpo.campo, 'nota_obrigatoria');

  const ausente = await chamar({
    metodo: 'POST',
    caminho: '/functions/v1/mindagent-avaliacao/enviar',
    corpo: respostaValida({ notaProgramacao: null }),
  });
  assert.equal(ausente.resposta.status, 422);
});

test('ausência de nota nunca vira zero', async () => {
  /* `Number(null)`, `Number("")`, `Number(false)` e `Number([])` são todos
     0 em JavaScript. Um `Number()` solto aqui transformaria "não avaliei"
     na pior nota possível — e a pesquisa mediria errado exatamente onde
     dói mais. Cada um destes tem de ser recusado, não convertido. */
  for (const vazio of [null, '', false, [], undefined]) {
    const geral = await chamar({
      metodo: 'POST',
      caminho: '/functions/v1/mindagent-avaliacao/enviar',
      corpo: respostaValida({ notaProgramacao: vazio }),
    });
    assert.equal(geral.resposta.status, 422, `nota geral ${JSON.stringify(vazio)} virou aceita`);
  }

  const { chamadas } = await chamar({
    metodo: 'POST',
    caminho: '/functions/v1/mindagent-avaliacao/enviar',
    corpo: respostaValida({
      atividades: [{ sessaoId: SESSAO_VALIDA, nota: null }],
    }),
  });
  const enviadas = chamadas.find((c) => c.nome === 'mind_avaliacao_do_dia_registrar')
    .args.p_payload.atividades;
  assert.deepEqual(enviadas, [], 'atividade sem nota não pode chegar ao banco como zero');
});

test('atividade com id que não é uuid é descartada antes de chegar ao banco', async () => {
  const { chamadas } = await chamar({
    metodo: 'POST',
    caminho: '/functions/v1/mindagent-avaliacao/enviar',
    corpo: respostaValida({
      atividades: [
        { sessaoId: SESSAO_VALIDA, nota: 5 },
        { sessaoId: 'nao-e-uuid', nota: 5 },
        { sessaoId: SESSAO_VALIDA, nota: 2.5 },
      ],
    }),
  });
  const enviadas = chamadas.find((c) => c.nome === 'mind_avaliacao_do_dia_registrar')
    .args.p_payload.atividades;
  assert.equal(enviadas.length, 1);
  assert.equal(enviadas[0].sessaoId, SESSAO_VALIDA);
});

test('dia fora do formato não vira chamada ao banco', async () => {
  const { resposta, chamadas } = await chamar({
    metodo: 'POST',
    caminho: '/functions/v1/mindagent-avaliacao/enviar',
    corpo: respostaValida({ dia: '16/09/2026' }),
  });
  assert.equal(resposta.status, 422);
  assert.equal(resposta.status === 422 && chamadas.some((c) => c.nome === 'mind_avaliacao_do_dia_registrar'), false);
});

test('resposta já enviada vira 409, não um segundo registro', async () => {
  const { resposta, corpo } = await chamar({
    metodo: 'POST',
    caminho: '/functions/v1/mindagent-avaliacao/enviar',
    corpo: respostaValida(),
    rpc: { mind_avaliacao_do_dia_registrar: erroRpc('avaliacao_ja_enviada', '23505') },
  });
  assert.equal(resposta.status, 409);
  assert.equal(corpo.codigo, 'ja_enviada');
  assert.match(corpo.mensagem, /não pode ser alterada/i);
});

test('pesquisa desligada recusa o envio e diz isso', async () => {
  const { resposta, corpo } = await chamar({
    metodo: 'POST',
    caminho: '/functions/v1/mindagent-avaliacao/enviar',
    corpo: respostaValida(),
    rpc: { mind_avaliacao_do_dia_registrar: erroRpc('avaliacao_validacao:pesquisa_desligada', '22023') },
  });
  assert.equal(resposta.status, 409);
  assert.equal(corpo.codigo, 'desligada');
});

test('sessão de outro dia ou de outro evento é recusada como validação', async () => {
  const { resposta, corpo } = await chamar({
    metodo: 'POST',
    caminho: '/functions/v1/mindagent-avaliacao/enviar',
    corpo: respostaValida(),
    rpc: { mind_avaliacao_do_dia_registrar: erroRpc('avaliacao_validacao:sessao_invalida', '22023') },
  });
  assert.equal(resposta.status, 422);
  assert.equal(corpo.campo, 'sessao_invalida');
});

test('erro do banco não vaza mensagem nem valor de campo para o cliente', async () => {
  const { resposta, corpo } = await chamar({
    metodo: 'POST',
    caminho: '/functions/v1/mindagent-avaliacao/enviar',
    corpo: respostaValida({ profissao: 'Gerente de RH na Empresa Secreta' }),
    rpc: { mind_avaliacao_do_dia_registrar: erroRpc('null value in column "x" of relation "y"', 'XX000') },
  });
  assert.equal(resposta.status, 503);
  assert.ok(!JSON.stringify(corpo).includes('Empresa Secreta'));
  assert.ok(!JSON.stringify(corpo).includes('relation'));
});

/* ---------- o painel ---------- */

test('usuário sem acesso ao painel não lê o relatório', async () => {
  const { resposta, corpo } = await chamar({
    caminho: '/functions/v1/mindagent-avaliacao/admin/relatorio',
    papelAdmin: null,
  });
  assert.equal(resposta.status, 403);
  assert.equal(corpo.codigo, 'sem_permissao');
});

test('administrador inativo também não lê', async () => {
  const { resposta } = await chamar({
    caminho: '/functions/v1/mindagent-avaliacao/admin/relatorio',
    papelAdmin: { display_name: 'X', role: 'administrador', active: false },
  });
  assert.equal(resposta.status, 403);
});

test('o painel só aceita origem conhecida; o app aceita qualquer uma', async () => {
  const doPainel = await chamar({
    caminho: '/functions/v1/mindagent-avaliacao/admin/relatorio',
    cabecalhos: { Origin: 'https://site-qualquer.example.com' },
  });
  assert.equal(doPainel.resposta.status, 403);

  const doApp = await chamar({
    caminho: '/functions/v1/mindagent-avaliacao/estado',
    cabecalhos: { Origin: 'https://site-qualquer.example.com' },
  });
  assert.equal(doApp.resposta.status, 200);
});

test('o relatório repassa os filtros e nunca escreve', async () => {
  const { chamadas } = await chamar({
    caminho: '/functions/v1/mindagent-avaliacao/admin/relatorio',
    busca: '?dia=2026-09-17&experiencia=vip',
  });
  const r = chamadas.find((c) => c.nome === 'mind_avaliacao_do_dia_relatorio');
  assert.equal(r.args.p_dia, '2026-09-17');
  assert.equal(r.args.p_experiencia, 'vip');
  assert.ok(!chamadas.some((c) => /registrar|mutate|insert|update/.test(c.nome)));
});

test('POST no caminho administrativo não existe', async () => {
  const { resposta } = await chamar({
    metodo: 'POST',
    caminho: '/functions/v1/mindagent-avaliacao/admin/relatorio',
    corpo: {},
  });
  assert.equal(resposta.status, 405);
});

/* ============================================================
   A MIGRATION — garantias que moram em constraint
   ============================================================ */

test('a estrutura é nova e não toca em nada existente', () => {
  /* Um `alter table` ou um `drop` numa tabela que já existia é
     exatamente o que este trabalho não pode ter. */
  const perigosas = migracao
    .split('\n')
    .filter((l) => !l.trim().startsWith('--'))
    .filter((l) => /\b(drop|truncate|delete\s+from)\b/i.test(l));
  assert.deepEqual(perigosas, [], 'nenhum drop/truncate/delete fora de comentário');

  const alteracoes = migracao.match(/^alter table .*/gim) || [];
  for (const linha of alteracoes) {
    assert.match(linha, /avaliacao_do_dia/,
      'só as tabelas novas podem ser alteradas: ' + linha);
  }

  /* As tabelas de feedback que já existem continuam de fora. */
  assert.ok(!/engagement\.nps|engagement\.sessao_feedback|engagement\.feedbacks/.test(
    migracao.replace(/--[^\n]*/g, '')), 'nenhuma tabela de feedback existente é reaproveitada');
});

test('uma resposta por participante, por evento, por dia', () => {
  assert.match(migracao, /unique \(participante_id, event_id, dia\)/);
  assert.match(migracao, /unique \(avaliacao_id, sessao_id\)/);
});

test('zero é nota válida e nota fora de 0–5 não entra', () => {
  assert.match(migracao, /nota_relevancia between 0 and 5/);
  assert.match(migracao, /nota_programacao between 0 and 5/);
  assert.match(migracao, /check \(nota between 0 and 5\)/);
  /* `not null` nas duas notas gerais: sem isso, "não respondi" e "dei
     zero" viram a mesma linha. */
  assert.match(migracao, /nota_relevancia smallint not null/);
  assert.match(migracao, /nota_programacao smallint not null/);
});

test('nenhuma cascata apaga dado de fora da estrutura nova', () => {
  const cascatas = migracao.match(/references [^\n]*on delete cascade/gi) || [];
  /* A única cascata permitida é a de dentro: nota → resposta. */
  assert.equal(cascatas.length, 1);
  assert.match(cascatas[0], /engagement\.avaliacao_do_dia\(id\)/);
  assert.match(migracao, /references pessoas\.pessoas\(id\) on delete restrict/);
  assert.match(migracao, /references summit_2026\.sessions\(id\) on delete restrict/);
});

test('RLS ligada nas duas tabelas e execute só para service_role', () => {
  assert.match(migracao, /alter table engagement\.avaliacao_do_dia enable row level security/);
  assert.match(migracao, /alter table engagement\.avaliacao_do_dia_atividade enable row level security/);
  assert.ok(!/create policy/i.test(migracao), 'nenhuma policy abre a tabela para anon/authenticated');
  const grants = migracao.match(/^grant execute[^\n]*/gim) || [];
  assert.equal(grants.length, 4);
  for (const g of grants) assert.match(g, /to service_role;$/);
  assert.equal((migracao.match(/^revoke execute[^\n]*/gim) || []).length, 4);
});

test('quem liga e desliga a pesquisa é o banco, não o código', () => {
  /* A chave nasce `false`, e é ela que manda. O app já aponta para a
     função publicada — foi o que permitiu ligar a pesquisa sem deploy,
     mexendo numa linha do banco.

     `avaliacaoApiUrl` continua sendo um segundo interruptor, mais forte e
     mais lento: nulo, o app não chama nada. Serve para arrancar a
     pesquisa do ar se a função estiver causando dano, não para o
     liga-desliga do dia. */
  assert.match(migracao, /'avaliacao_do_dia',\s*\n\s*jsonb_build_object\('ativo', false\)/,
    'a chave precisa nascer desligada: aplicar a migration não pode abrir a pesquisa sozinha');
  assert.match(configApp, /avaliacaoApiUrl: 'https:\/\/[a-z0-9]+\.supabase\.co\/functions\/v1\/mindagent-avaliacao'/,
    'o app precisa de um endereço para a pesquisa existir');

  /* A porta do banco recusa envio com a chave desligada — é o que torna o
     interruptor real, e não só cosmético na home. */
  assert.match(migracao, /if coalesce\(v_ativo, false\) is false then\s*\n\s*raise exception[^\n]*pesquisa_desligada/,
    'sem esta recusa, desligar a pesquisa só esconderia o card');
});

test('reenvio idêntico reconhece; divergente é recusado', () => {
  assert.match(migracao, /'jaRegistrado', true/);
  assert.match(migracao, /message = 'avaliacao_ja_enviada'/);
  assert.ok(!/on conflict \(participante_id, event_id, dia\) do update/i.test(migracao),
    'upsert sobrescreveria resposta concluída');
});

test('o dia enviado precisa ser um dia do evento', () => {
  assert.match(migracao, /p_dia = any \(v_evento\.dias\)/);
  assert.match(migracao, /dia_fora_do_evento/);
});

test('só quem é dono do token responde — a função não aceita participante_id', () => {
  assert.match(migracao, /mind_avaliacao_do_dia_registrar\(\s*\n\s*p_auth_user_id uuid/);
  assert.match(migracao, /mind_avaliacao_do_dia_estado\(\s*\n\s*p_auth_user_id uuid/);
  assert.match(migracao, /canal = 'auth_user' and i\.identificador = p_auth_user_id::text/);
});

test('envio concorrente disputa a mesma trava', () => {
  assert.match(migracao, /pg_advisory_xact_lock/);
});

test('o relatório não junta respostas com notas de atividade', () => {
  /* Um join entre as duas multiplicaria cada respondente pelo número de
     notas dele. As duas contagens saem de CTEs separadas. */
  assert.match(migracao, /'avaliacoesDeAtividades', \(select count\(\*\) from notas\)/);
  assert.match(migracao, /'respondentes', count\(\*\)/);
  assert.match(migracao, /avg\(n\.nota\)::numeric\(4,2\) as media/);
  /* Atividade sem nota fica com média nula — `avg` de conjunto vazio é
     null, e nada aqui a transforma em zero. */
  assert.ok(!/coalesce\(avg\([^)]*\), *0\)/i.test(migracao));
});

test('blocos operacionais não recebem nota, nem no envio nem no relatório', () => {
  const ocorrencias = migracao.match(/tipo is distinct from 'credenciamento'/g) || [];
  assert.ok(ocorrencias.length >= 2, 'a regra vale na validação do envio e no relatório');
  assert.match(migracao, /'operacional', s\.tipo in \('credenciamento', 'intervalo', 'almoco'\)/);
});

test('a grade sai da programação oficial, pela categoria de acesso', () => {
  assert.match(migracao, /'ingressos', to_jsonb\(s\.ingressos\)/);
  assert.match(migracao, /from summit_2026\.sessions s/);
  /* `trilhas` está vazia em todas as sessões: filtrar por ela devolveria
     uma grade vazia que parece erro de carregamento. */
  assert.ok(!/s\.trilhas/.test(migracao));
});

/* ============================================================
   O MÓDULO DO APP
   ============================================================ */

test('a data é fixada na abertura e não é recalculada do relógio local', () => {
  /* `new Date()` para decidir o dia avaliado é exatamente o bug da
     virada da meia-noite. O dia vem do servidor e volta para ele. */
  assert.ok(!/new Date\(\)/.test(tela), 'a tela não decide o dia pelo relógio do aparelho');
  assert.match(tela, /estado\.dia/);
  assert.match(tela, /dia: estado\.dia/);
});

test('zero é valor, e a tela nunca o trata como ausência', () => {
  /* `== null` e não `!`: `!0` é verdadeiro, e seria o bug que apaga a
     nota mais negativa da pesquisa. */
  assert.match(tela, /resposta\.notaRelevancia == null/);
  assert.match(tela, /resposta\.notaProgramacao == null/);
  assert.ok(!/if \(!resposta\.notaRelevancia\)/.test(tela));
  assert.match(tela, /hasOwnProperty\.call\(resposta\.atividades, a\.id\)/);
});

test('filtrar esconde linhas e não apaga nota nenhuma', () => {
  const trecho = tela.slice(tela.indexOf('function atividadesVisiveis'),
    tela.indexOf('function quantasAvaliadas'));
  assert.ok(!/delete |resposta\.atividades *=/.test(trecho),
    'o filtro não pode tocar nas respostas');
  assert.match(trecho, /\.filter\(/);
});

test('o rascunho é por pessoa, por dia e por versão — e não guarda e-mail', () => {
  assert.match(servico, /chaveDoRascunho\(dia, versao\)/);
  assert.match(servico, /impressaoDaIdentidade\(\)/);
  const chave = servico.slice(servico.indexOf('function chaveDoRascunho'),
    servico.indexOf('export function lerRascunho'));
  assert.ok(!/obterParticipante\(\)\.email/.test(chave),
    'a chave do rascunho não pode carregar o e-mail em claro');
});

test('o rascunho só some depois da confirmação do servidor', () => {
  const concluir = tela.slice(tela.indexOf('function concluir'), tela.indexOf('function desenharObrigado'));
  assert.match(concluir, /limparRascunho/);
  /* E `confirmarEnvio` só chega em `concluir` pelo caminho de sucesso ou
     pelo de "já enviada", que é sucesso do ponto de vista da pessoa. */
  const envio = tela.slice(tela.indexOf('async function confirmarEnvio'), tela.indexOf('function concluir'));
  assert.match(envio, /await enviar\(corpo\);\s*\n\s*return concluir\(\);/);
  assert.match(envio, /e\.codigo === 'ja_enviada'/);
});

test('timeout consulta o servidor antes de concluir ou deixar reenviar', () => {
  const envio = tela.slice(tela.indexOf('async function confirmarEnvio'), tela.indexOf('function concluir'));
  assert.match(envio, /e\.codigo === 'indeterminado'/);
  assert.match(envio, /await carregarEstado\(estado\.dia\)/);
  assert.match(envio, /conferido && conferido\.enviado/);
  assert.match(servico, /erro\.codigo = 'indeterminado'/);
});

test('clique duplo não vira envio duplo', () => {
  assert.match(tela, /if \(enviando\) return;/);
  assert.match(tela, /enviarBotao\.disabled = enviando;/);
});

test('a confirmação avisa que não dá para alterar depois', () => {
  assert.match(tela, /Confira suas respostas\. Após enviar, você não poderá alterá-las\./);
  assert.match(tela, /'Enviar avaliação'/);
});

test('o card da home só existe quando o servidor confirma', () => {
  const app = lerFonte(new URL('../app.js', import.meta.url));
  assert.match(app, /if \(!e \|\| !e\.ativo \|\| !e\.identificado\) return null;/);
  assert.match(app, /Avaliação de hoje enviada ✓/);
  const homeJs = lerFonte(new URL('../home/home.js', import.meta.url));
  assert.match(homeJs, /ctx\.avaliacao \? \{ \.\.\.b, \.\.\.ctx\.avaliacao \} : \{ \.\.\.b, estado: 'oculto' \}/);
  const estado = lerFonte(new URL('../home/estado.js', import.meta.url));
  assert.match(estado, /daAvaliacao: true, estado: 'oculto'/);
  assert.match(estado, /Como foi seu dia no Mind\?/);
  assert.match(estado, /cta: 'Avaliar meu dia'/);
});

test('o card só aparece depois que o dia aconteceu', () => {
  /* A RESPOSTA É ÚNICA E DEFINITIVA POR DIA. Oferecer a avaliação às 11h
     da manhã faria a pessoa avaliar meia manhã e queimar a resposta do dia
     inteiro, sem poder corrigir. Por isso o card NÃO vive em `no-evento`.

     Vive em `entre-dias` (a noite do dia 1) e em `depois` — que não é
     repetição: depois do dia 2 o momento vai de `no-evento` direto para
     `depois`, e sem esse segundo bloco o dia 17 nunca seria avaliado. Ele
     se apaga sozinho a partir do dia 18, quando o servidor passa a
     responder `fora_do_evento`.

     Recolocar no meio do dia é um diff de uma linha que ninguém percebe
     estar errado — daí este teste. */
  const estado = lerFonte(new URL('../home/estado.js', import.meta.url));
  const composicao = (nome) => {
    const i = estado.indexOf(nome + ': {');
    assert.notEqual(i, -1, 'composição ' + nome + ' sumiu de estado.js');
    /* Até a próxima composição de primeiro nível, que abre na coluna 2. */
    const resto = estado.slice(i);
    const fim = resto.search(/\n  [a-z'][\w'-]*: \{/);
    return fim === -1 ? resto : resto.slice(0, fim);
  };

  assert.ok(composicao("'entre-dias'").includes('daAvaliacao: true'),
    'o fechamento do dia 1 perdeu a avaliação');
  assert.ok(composicao('depois').includes('daAvaliacao: true'),
    'sem o bloco em `depois`, o dia 2 não tem como ser avaliado');
  assert.ok(!composicao("'no-evento'").includes('daAvaliacao'),
    'a avaliação voltou para o meio do dia, onde queima a resposta única da pessoa');
});

test('falha da pesquisa não derruba a home nem o chat', () => {
  const app = lerFonte(new URL('../app.js', import.meta.url));
  const bloco = app.slice(app.indexOf('async function carregarAvaliacaoDoDia'),
    app.indexOf('function cardDaAvaliacao'));
  assert.match(bloco, /try \{/);
  assert.match(bloco, /estadoDaAvaliacao = null;/);
  /* O serviço nunca deixa exceção escapar na leitura. */
  const leitura = servico.slice(servico.indexOf('export async function carregarEstado'),
    servico.indexOf('export async function enviar'));
  assert.match(leitura, /catch \(e\) \{\s*\n\s*return null;/);
});

test('a pesquisa reaproveita a sessão do chat em vez de abrir outra', () => {
  assert.match(servico, /import \{ garantirSessaoDeAcesso \} from '\.\.\/chat-service\.js'/);
  assert.ok(!/auth\/v1\/signup|auth\/v1\/token/.test(servico),
    'nada de segundo fluxo de autenticação');
  const chat = lerFonte(new URL('../chat-service.js', import.meta.url));
  assert.match(chat, /export async function garantirSessaoDeAcesso/);
});

test('o módulo entra no build e o CSS não alcança outra tela', () => {
  assert.match(build, /'avaliacao',/);
  /* Comentários fora antes de olhar seletor: `/* ... *\/` contém `{` e
     entraria na lista como se fosse regra. */
  const semComentario = estilo.replace(/\/\*[\s\S]*?\*\//g, '');
  const seletores = (semComentario.match(/(^|\})\s*([^@{}]+)\{/g) || [])
    .map((s) => s.replace(/^\}/, '').replace('{', '').trim())
    .filter(Boolean);
  assert.ok(seletores.length > 10, 'o arquivo precisa ter regras para o teste valer');
  for (const s of seletores) {
    /* Dentro de `@media` o seletor vem sem prefixo de bloco — vale a
       mesma regra. */
    assert.ok(/^#vista-avaliacao\b|^\.av-|^#home-v3 \.v3-destaque\.av-enviada/.test(s),
      'seletor fora do módulo: ' + s);
  }
});

/* ============================================================
   O CSV DO PAINEL
   ============================================================ */

/* O relatório da pesquisa saiu do painel em 26/09/2026 (a Adriana tirou
   Atendimento do Mind Intelligence Admin). Os testes que liam as telas dele
   — CSV, média sem amostra, taxa de participação — saíram junto; a pesquisa
   do participante e a Edge seguem cobertas aqui. */

test('o rádio invisível rola junto com o formulário', () => {
  /* O DEFEITO QUE ISTO TRAVA, medido em 16/09 num Chrome de desktop:
     rolando o formulário 500px e tocando numa nota, o app inteiro saía da
     tela. O rádio é `position: absolute`; sem ancestral posicionado, o bloco
     contenedor dele virava o `body`, que é `fixed` e fica FORA da área que
     rola. O rádio ficava parado enquanto o rótulo descia — 500px de distância
     entre os dois. O clique no rótulo foca o rádio, o navegador rola o que
     for preciso para alcançá-lo, e rolou o `body` em 614px.

     `overflow: hidden` no body não protege: ele esconde a barra, não proíbe o
     navegador de rolar.

     Depois da correção, a distância caiu para 23px e 18 rótulos visíveis
     foram clicados em 6 profundidades sem mover nada. */
  assert.match(estilo, /\.av-notas,\s*\n\.av-opcoes \{ position: relative; \}/,
    'sem pai posicionado o rádio volta a se ancorar no body e a tela sai voando ao dar uma nota');

  const regra = estilo.slice(estilo.indexOf('.av-radio {'), estilo.indexOf('}', estilo.indexOf('.av-radio {')));
  assert.match(regra, /position: absolute;/);
  assert.match(regra, /top: 50%;/,
    'sem `top` vale a posição estática, que grid e flex resolvem cada um à sua maneira');
  assert.match(regra, /left: 50%;/);
});
