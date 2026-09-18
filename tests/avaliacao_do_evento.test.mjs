/* ============================================================
   AVALIAÇÃO DO EVENTO — o que não pode quebrar
   ============================================================
   A segunda pesquisa mora na MESMA Edge da primeira, e é aí que está o
   risco: `rota` é o último segmento da URL, então `/evento/estado` e
   `/estado` terminam com a mesma palavra. Errar esse desvio faria a
   pesquisa do evento responder pela do dia sem erro nenhum na tela —
   o tipo de defeito que só aparece no dado, semanas depois.

   Três camadas, três jeitos de provar:

   1. A Edge, executada de verdade pelo harness.
   2. A migration, lida como texto — o que mora em `constraint` e em
      `unique` não roda aqui sem banco, mas some de um diff sem parecer
      erro.
   3. A pesquisa do dia, que tem de continuar exatamente onde estava.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { chamar, erroRpc, AUTH_USER_ID } from './helpers/avaliacao-harness.mjs';

const migracao = readFileSync(
  new URL('../supabase/migrations/20260918120000_avaliacao_do_evento.sql', import.meta.url), 'utf8');

const ESTADO = '/functions/v1/mindagent-avaliacao/evento/estado';
const ENVIAR = '/functions/v1/mindagent-avaliacao/evento/enviar';

/** Uma resposta completa e válida do evento, para os testes partirem dela. */
function respostaDoEvento(extra = {}) {
  return {
    eventSlug: 'mind-summit-2026',
    experiencia: 'prime',
    profissao: 'Gerente de RH',
    expectativas: 'Sair com um caminho para medir bem-estar.',
    notaRelevancia: 4,
    notaProgramacao: 5,
    maisGostou: null,
    melhorar: null,
    comentario: null,
    ...extra,
  };
}

const rpcsDe = (chamadas) => chamadas.map((c) => c.nome);

/* ============================================================
   O DESVIO — a parte que cala quando quebra
   ============================================================ */

test('/evento/estado pergunta pela pesquisa do evento, não pela do dia', async () => {
  const { resposta, chamadas } = await chamar({ caminho: ESTADO });

  assert.equal(resposta.status, 200);
  assert.ok(rpcsDe(chamadas).includes('mind_avaliacao_do_evento_estado'));
  assert.ok(!rpcsDe(chamadas).includes('mind_avaliacao_do_dia_estado'),
    'a rota do evento não pode cair no estado da pesquisa do dia');
});

test('/estado continua sendo a pesquisa do dia', async () => {
  const { resposta, chamadas } = await chamar({
    caminho: '/functions/v1/mindagent-avaliacao/estado',
  });

  assert.equal(resposta.status, 200);
  assert.ok(rpcsDe(chamadas).includes('mind_avaliacao_do_dia_estado'));
  assert.ok(!rpcsDe(chamadas).includes('mind_avaliacao_do_evento_estado'));
});

test('a palavra "evento" solta no fim do caminho não é rota', async () => {
  const { resposta } = await chamar({ caminho: '/functions/v1/mindagent-avaliacao/evento' });
  assert.equal(resposta.status, 404);
});

/* ============================================================
   O ENVIO
   ============================================================ */

test('o envio do evento não leva dia nem atividades ao banco', async () => {
  const { resposta, chamadas } = await chamar({
    metodo: 'POST', caminho: ENVIAR,
    corpo: respostaDoEvento({ dia: '2026-09-16', atividades: [{ sessaoId: 'x', nota: 5 }] }),
  });

  assert.equal(resposta.status, 201);
  const registro = chamadas.find((c) => c.nome === 'mind_avaliacao_do_evento_registrar');
  assert.ok(registro, 'o envio do evento tem de chamar a função do evento');
  assert.ok(!('p_dia' in registro.args), 'a pesquisa do evento não tem dia');
  assert.ok(!('atividades' in registro.args.p_payload),
    'a pesquisa do evento não tem nota por atividade');
});

test('quem responde é o dono do token — nunca um id mandado pelo cliente', async () => {
  const { chamadas } = await chamar({
    metodo: 'POST', caminho: ENVIAR,
    corpo: respostaDoEvento({
      participanteId: '99999999-9999-4999-8999-999999999999',
      participante_id: '99999999-9999-4999-8999-999999999999',
    }),
  });

  const registro = chamadas.find((c) => c.nome === 'mind_avaliacao_do_evento_registrar');
  assert.equal(registro.args.p_auth_user_id, AUTH_USER_ID);
  const enviado = JSON.stringify(registro.args.p_payload);
  assert.ok(!enviado.includes('99999999'), 'id vindo do cliente não pode atravessar');
});

test('ausência de nota nunca vira zero', async () => {
  for (const vazio of [null, '', false, [], undefined]) {
    const corpo = respostaDoEvento();
    corpo.notaRelevancia = vazio;

    const { resposta, corpo: lido, chamadas } = await chamar({
      metodo: 'POST', caminho: ENVIAR, corpo,
    });

    assert.equal(resposta.status, 422, `nota ${JSON.stringify(vazio)} devia ser recusada`);
    assert.equal(lido.campo, 'nota_obrigatoria');
    assert.ok(!rpcsDe(chamadas).includes('mind_avaliacao_do_evento_registrar'),
      'nota ausente não pode virar zero no banco');
  }
});

test('nota zero atravessa — zero é resposta', async () => {
  const { resposta, chamadas } = await chamar({
    metodo: 'POST', caminho: ENVIAR,
    corpo: respostaDoEvento({ notaRelevancia: 0, notaProgramacao: 0 }),
  });

  assert.equal(resposta.status, 201);
  const registro = chamadas.find((c) => c.nome === 'mind_avaliacao_do_evento_registrar');
  assert.equal(registro.args.p_payload.notaRelevancia, 0);
  assert.equal(registro.args.p_payload.notaProgramacao, 0);
});

test('nota quebrada e fora da faixa não viram chamada ao banco', async () => {
  for (const nota of [4.5, -1, 6, '5']) {
    const { resposta, chamadas } = await chamar({
      metodo: 'POST', caminho: ENVIAR, corpo: respostaDoEvento({ notaProgramacao: nota }),
    });
    assert.equal(resposta.status, 422, `nota ${JSON.stringify(nota)} devia ser recusada`);
    assert.ok(!rpcsDe(chamadas).includes('mind_avaliacao_do_evento_registrar'));
  }
});

test('resposta já enviada vira 409, não um segundo registro', async () => {
  const { resposta } = await chamar({
    metodo: 'POST', caminho: ENVIAR, corpo: respostaDoEvento(),
    rpc: { mind_avaliacao_do_evento_registrar: erroRpc('avaliacao_ja_enviada', '23505') },
  });
  assert.equal(resposta.status, 409);
});

test('fora da janela o envio é recusado, e a tela sabe por quê', async () => {
  for (const motivo of ['ainda_nao_abriu', 'ja_fechou', 'pesquisa_desligada']) {
    const { resposta, corpo } = await chamar({
      metodo: 'POST', caminho: ENVIAR, corpo: respostaDoEvento(),
      rpc: {
        mind_avaliacao_do_evento_registrar: erroRpc(`avaliacao_validacao:${motivo}`, '22023'),
      },
    });
    assert.ok(resposta.status >= 400 && resposta.status < 500,
      `${motivo} devia ser erro de cliente, e veio ${resposta.status}`);
    assert.ok(corpo.codigo);
  }
});

test('sem identidade canônica não grava, mesmo com a pesquisa aberta', async () => {
  const { resposta, chamadas } = await chamar({
    metodo: 'POST', caminho: ENVIAR, corpo: respostaDoEvento(),
    rpc: { mind_avaliacao_do_evento_registrar: erroRpc('avaliacao_sem_identidade', '28000') },
  });

  assert.ok(resposta.status >= 400);
  assert.ok(rpcsDe(chamadas).includes('mind_avaliacao_do_evento_registrar'));
});

test('sem token não há pesquisa do evento', async () => {
  const { resposta, corpo } = await chamar({ caminho: ESTADO, autorizacao: null });
  assert.equal(resposta.status, 401);
  assert.equal(corpo.codigo, 'sem_sessao');
});

/* ============================================================
   IDENTIDADE
   ============================================================ */

test('sem vínculo, a Edge liga pelo e-mail do cabeçalho e lê de novo', async () => {
  let vezes = 0;
  const { chamadas } = await chamar({
    caminho: ESTADO,
    cabecalhos: { 'X-Identidade-Email': 'pessoa@exemplo.com', 'X-Identidade-Nome': 'Pessoa' },
    rpc: {
      mind_avaliacao_do_evento_estado: () => {
        vezes += 1;
        return { ativo: true, motivo: null, identificado: vezes > 1, enviado: false };
      },
    },
  });

  assert.equal(vezes, 2, 'tinha de ler, ligar e ler de novo');
  assert.ok(rpcsDe(chamadas).includes('mind_identidade_resolver'));
  const ligacao = chamadas.find((c) => c.nome === 'mind_identidade_resolver');
  assert.equal(ligacao.args.p_identificadores.auth_user_id, AUTH_USER_ID);
});

test('o e-mail vai por cabeçalho e nunca por query string', async () => {
  const { chamadas } = await chamar({
    caminho: ESTADO, busca: '?email=pessoa@exemplo.com',
    rpc: { mind_avaliacao_do_evento_estado: { ativo: true, identificado: false, enviado: false } },
  });
  assert.ok(!rpcsDe(chamadas).includes('mind_identidade_resolver'),
    'e-mail em query string não pode ligar identidade');
});

/* ============================================================
   O PAINEL
   ============================================================ */

test('/admin/evento/relatorio lê o relatório do evento, sem filtro de dia', async () => {
  const { resposta, chamadas } = await chamar({
    caminho: '/functions/v1/mindagent-avaliacao/admin/evento/relatorio',
    busca: '?experiencia=vip&dia=2026-09-16',
  });

  assert.equal(resposta.status, 200);
  const chamada = chamadas.find((c) => c.nome === 'mind_avaliacao_do_evento_relatorio');
  assert.ok(chamada, 'tinha de chamar o relatório do evento');
  assert.equal(chamada.args.p_experiencia, 'vip');
  assert.ok(!('p_dia' in chamada.args), 'dia não filtra nada nesta pesquisa');
});

test('/admin/evento/respostas pagina', async () => {
  const { resposta, chamadas } = await chamar({
    caminho: '/functions/v1/mindagent-avaliacao/admin/evento/respostas',
    busca: '?pagina=3&porPagina=25',
  });

  assert.equal(resposta.status, 200);
  const chamada = chamadas.find((c) => c.nome === 'mind_avaliacao_do_evento_respostas');
  assert.equal(chamada.args.p_pagina, 3);
  assert.equal(chamada.args.p_por_pagina, 25);
});

test('usuário sem acesso ao painel não lê o relatório do evento', async () => {
  const { resposta, chamadas } = await chamar({
    caminho: '/functions/v1/mindagent-avaliacao/admin/evento/relatorio',
    papelAdmin: null,
  });

  assert.equal(resposta.status, 403);
  assert.ok(!rpcsDe(chamadas).includes('mind_avaliacao_do_evento_relatorio'));
});

test('o painel do evento só aceita origem conhecida', async () => {
  const { resposta } = await chamar({
    caminho: '/functions/v1/mindagent-avaliacao/admin/evento/relatorio',
    cabecalhos: { Origin: 'https://site-de-terceiro.com' },
  });
  assert.equal(resposta.status, 403);
});

test('POST no caminho administrativo do evento não existe', async () => {
  const { resposta } = await chamar({
    metodo: 'POST', caminho: '/functions/v1/mindagent-avaliacao/admin/evento/relatorio',
    corpo: {},
  });
  assert.equal(resposta.status, 405);
});

test('rota administrativa desconhecida do evento é 404', async () => {
  const { resposta } = await chamar({
    caminho: '/functions/v1/mindagent-avaliacao/admin/evento/inventada',
  });
  assert.equal(resposta.status, 404);
});

/* ============================================================
   A MIGRATION, LIDA COMO TEXTO
   ============================================================ */

test('a estrutura é nova e não altera nada existente', () => {
  assert.match(migracao, /create table if not exists engagement\.avaliacao_do_evento/);

  for (const proibido of [/\balter table (?!engagement\.avaliacao_do_evento\b)/i,
                          /\bdrop table\b/i, /\bdrop function\b(?![^\n]*--)/i,
                          /\bupdate engagement\./i, /\bdelete from engagement\./i]) {
    const achou = migracao
      .split('\n')
      .filter((l) => !l.trim().startsWith('--'))
      .some((l) => proibido.test(l));
    assert.ok(!achou, `a migration não pode conter ${proibido}`);
  }
});

test('uma resposta por participante por evento — e sem dia na chave', () => {
  assert.match(migracao, /unique \(participante_id, event_id\)/);
  assert.ok(!/unique \(participante_id, event_id, dia\)/.test(migracao),
    'dia não entra na chave desta pesquisa');
  assert.ok(!/\bdia date\b/.test(migracao), 'a tabela do evento não tem coluna de dia');
});

test('não existe tabela de nota por atividade nesta pesquisa', () => {
  assert.ok(!/create table[^;]*avaliacao_do_evento_atividade/i.test(migracao));
});

test('zero é nota válida e nota fora de 0–5 não entra', () => {
  assert.match(migracao, /nota_relevancia smallint not null/);
  assert.match(migracao, /nota_programacao smallint not null/);
  assert.match(migracao, /check \(nota_relevancia between 0 and 5\)/);
  assert.match(migracao, /check \(nota_programacao between 0 and 5\)/);
});

test('nenhuma cascata apaga resposta junto com dado de fora', () => {
  const cascatas = migracao.match(/on delete cascade/gi) || [];
  assert.equal(cascatas.length, 0);
  assert.match(migracao, /references pessoas\.pessoas\(id\) on delete restrict/);
  assert.match(migracao, /references summit_2026\.events\(id\) on delete restrict/);
});

test('RLS ligada e execute só para service_role', () => {
  assert.match(migracao, /alter table engagement\.avaliacao_do_evento enable row level security/);
  assert.ok(!/create policy/i.test(migracao), 'sem policy, a tabela não tem porta de PostgREST');

  for (const f of ['estado', 'registrar', 'relatorio', 'respostas']) {
    const nome = `mind_avaliacao_do_evento_${f}`;
    assert.ok(migracao.includes(`revoke execute on function public.${nome}`), `falta revoke em ${nome}`);
    assert.ok(migracao.includes(`grant execute on function public.${nome}`), `falta grant em ${nome}`);
    assert.ok(new RegExp(`grant execute on function public\\.${nome}[^;]*to service_role`).test(migracao),
      `${nome} tem de ser só do service_role`);
  }
  assert.ok(!/to (anon|authenticated)/.test(migracao));
});

test('a janela é dado, não código, e nasce desligada', () => {
  assert.match(migracao, /insert into concierge\.config \(chave, valor\)/);
  assert.match(migracao, /'avaliacao_do_evento'/);
  assert.match(migracao, /'ativo', false/);
  assert.match(migracao, /'abre', null/);
  assert.match(migracao, /'fecha', null/);
  assert.match(migracao, /on conflict \(chave\) do nothing/);
});

test('a janela é conferida no envio, e não só na abertura da tela', () => {
  const registrar = migracao.slice(migracao.indexOf('mind_avaliacao_do_evento_registrar'));
  assert.match(registrar, /avaliacao_validacao:ainda_nao_abriu/);
  assert.match(registrar, /avaliacao_validacao:ja_fechou/);
  assert.match(registrar, /avaliacao_validacao:pesquisa_desligada/);
});

test('a janela é lida no fuso do evento, não no do servidor', () => {
  const ocorrencias = migracao.match(/now\(\) at time zone v_evento\.fuso/g) || [];
  assert.ok(ocorrencias.length >= 2, 'estado e envio precisam ler a data no fuso do evento');
  assert.ok(!/\bcurrent_date\b/i.test(migracao), 'current_date usaria o fuso do servidor');
});

test('reenvio idêntico reconhece; divergente é recusado', () => {
  assert.match(migracao, /jaRegistrado', true/);
  assert.match(migracao, /avaliacao_ja_enviada/);
  assert.ok(!/on conflict[^;]*do update/i.test(migracao),
    'upsert sobrescreveria resposta concluída');
});

test('envio concorrente disputa a mesma trava', () => {
  assert.match(migracao, /pg_advisory_xact_lock\(\s*hashtext\('avaliacao_do_evento'\)/);
});

test('a função não aceita participante vindo do cliente', () => {
  const assinatura = migracao.match(/create or replace function public\.mind_avaliacao_do_evento_registrar\(([^)]*)\)/);
  assert.ok(assinatura);
  assert.ok(!/participante/i.test(assinatura[1]),
    'quem responde sai do vínculo da sessão, e não de um argumento');
});

/* Citar a pesquisa do dia num `comment on` é documentação e é bem-vindo:
   é ali que fica escrito por que as duas são separadas. O que não pode é
   um comando que a alcance. */
test('nenhum comando desta migration alcança a pesquisa do dia', () => {
  const executavel = migracao
    .split('\n')
    .filter((l) => !l.trim().startsWith('--'))
    .join('\n')
    .replace(/comment on [^;]+;/gi, '');

  assert.ok(!/avaliacao_do_dia/.test(executavel),
    'fora de comentário, a migration do evento não pode citar a tabela do dia');
});
