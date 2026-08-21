#!/usr/bin/env node
/* ============================================================
   alimentar-banco.mjs — escrita assistida no banco do Summit
   ============================================================
   O caminho para levar conteúdo ao banco sem abrir o painel registro
   por registro. Fala com a Edge Function `mindagent-admin`, a mesma que
   o painel usa — logo herda validação, tradução de vocabulário
   (admin → chat), auditoria e RLS.

   REGRAS QUE NÃO PODEM SER QUEBRADAS AQUI
   ---------------------------------------
   - NUNCA falar com o Postgres direto. Só Edge Function.
   - `service_role` e secret key não entram aqui. O script RECUSA token
     cuja `role` não seja `authenticated`: chave administrativa pularia
     justamente as camadas que tornam a escrita segura.
   - O token não é impresso, não é logado, não vai para a URL. Nem
     inteiro, nem em pedaço.
   - Escrita é opt-in explícito (`--aplicar`). Sem a flag, o script
     mostra o diff e não manda nada.
   - Campo com conteúdo não é sobrescrito sem `--sobrescrever`. O banco
     está à frente do repositório; presumir o contrário apaga trabalho.
   - Toda escrita manda `If-Unmodified-Since-Version` com o
     `atualizadoEm` que o plano viu. Registro que mudou desde então dá
     conflito em vez de atropelar quem editou no painel.

   USO
   ---
     node scripts/alimentar-banco.mjs inspecionar
     node scripts/alimentar-banco.mjs lacunas
     node scripts/alimentar-banco.mjs aplicar plano.json             # dry-run
     node scripts/alimentar-banco.mjs aplicar plano.json --aplicar    # escreve

   FLAGS
   -----
     --aplicar        manda de verdade (sem ela, só mostra)
     --sobrescrever   deixa trocar campo que já tem conteúdo
     --limite N       teto de escritas na rodada (padrão 25)
     --continuar      não para no primeiro erro
     --saida DIR      onde gravar snapshot e diário (padrão .banco/)

   CREDENCIAL
   ----------
   O token do operador vem do ambiente, nunca de argumento (argumento
   vaza em histórico de shell e em lista de processo):

     MINDAGENT_ADMIN_TOKEN=<access_token>

   ou em `.env.admin.local` na raiz (coberto pelo .gitignore). Para
   obtê-lo: entre em /admin e, no console do navegador, leia o campo
   `access_token` de `localStorage.getItem('mindagent-admin-auth')`.
   Ele expira em cerca de uma hora; expirado, a API responde 401 e o
   script diz isso em vez de insistir.
*/

import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), '..');

/* ------------------------------------------------------------------ */
/* Ambiente                                                            */
/* ------------------------------------------------------------------ */

/** Leitor de `.env` deliberadamente burro: `CHAVE=valor`, sem interpolação. */
function lerEnv(caminho) {
  if (!existsSync(caminho)) return {};
  const fora = {};
  for (const linha of readFileSync(caminho, 'utf8').split(/\r?\n/)) {
    const corte = linha.indexOf('=');
    if (!linha.trim() || linha.trim().startsWith('#') || corte < 1) continue;
    fora[linha.slice(0, corte).trim()] = linha
      .slice(corte + 1)
      .trim()
      .replace(/^["']|["']$/g, '');
  }
  return fora;
}

/** Sinal de "já expliquei o problema, encerre" — não é falha inesperada. */
class Saida extends Error {}

/* Sai por `exitCode` + throw, nunca por `process.exit()`. Com requisições
   em voo, matar o processo no meio dispara asserção do libuv no Windows e
   enterra a mensagem de erro debaixo de um stack trace de C. */
function morrer(mensagem) {
  console.error('\n[x] ' + mensagem + '\n');
  process.exitCode = 1;
  throw new Saida(mensagem);
}

/** Payload de JWT sem verificar assinatura — só para ler `role` e `exp`. */
function corpoDoToken(token) {
  try {
    const meio = token.split('.')[1];
    const base = meio.replace(/-/g, '+').replace(/_/g, '/');
    return JSON.parse(Buffer.from(base, 'base64').toString('utf8'));
  } catch {
    return null;
  }
}

function ambiente() {
  const doAdmin = lerEnv(join(RAIZ, 'admin', '.env.local'));
  const daRaiz = lerEnv(join(RAIZ, '.env.admin.local'));

  const baseUrl = (
    process.env.VITE_ADMIN_API_BASE_URL ||
    daRaiz.VITE_ADMIN_API_BASE_URL ||
    doAdmin.VITE_ADMIN_API_BASE_URL ||
    ''
  )
    .trim()
    .replace(/\/+$/, '');
  const apikey = (
    process.env.VITE_SUPABASE_PUBLISHABLE_KEY ||
    daRaiz.VITE_SUPABASE_PUBLISHABLE_KEY ||
    doAdmin.VITE_SUPABASE_PUBLISHABLE_KEY ||
    ''
  ).trim();
  const token = (process.env.MINDAGENT_ADMIN_TOKEN || daRaiz.MINDAGENT_ADMIN_TOKEN || '').trim();

  if (!baseUrl) {
    morrer('VITE_ADMIN_API_BASE_URL nao encontrada (nem no ambiente, nem em admin/.env.local).');
  }
  if (!apikey) {
    morrer('VITE_SUPABASE_PUBLISHABLE_KEY nao encontrada. Ela e publica por design — sem ela o gateway recusa.');
  }
  if (!token) {
    morrer(
      'MINDAGENT_ADMIN_TOKEN ausente.\n\n' +
        '  Entre em /admin e no console do navegador rode:\n' +
        "    JSON.parse(localStorage.getItem('mindagent-admin-auth')).access_token\n\n" +
        '  Guarde em `.env.admin.local` na raiz (ja ignorado pelo git):\n' +
        '    MINDAGENT_ADMIN_TOKEN=<cole aqui>\n\n' +
        '  Nao passe o token por argumento: ele vai para o historico do shell.',
    );
  }

  /* A guarda que importa: chave administrativa pularia a Edge Function
     inteira. Melhor recusar aqui do que descobrir depois que a escrita
     entrou sem validacao nem auditoria. */
  if (/^sb_secret/.test(token) || !/^eyJ/.test(token)) {
    morrer(
      'Esse token nao parece um JWT de sessao de operador. `service_role` e secret key nao ' +
        'sao aceitos aqui — a escrita tem de passar pela Edge Function.',
    );
  }
  const corpo = corpoDoToken(token);
  if (corpo && corpo.role && corpo.role !== 'authenticated') {
    morrer('Token com role `' + corpo.role + '`. So sessao de operador (`authenticated`) e aceita.');
  }
  if (corpo && corpo.exp && corpo.exp * 1000 < Date.now()) {
    morrer(
      'Token expirado em ' + new Date(corpo.exp * 1000).toISOString() +
        '. Entre no painel de novo e pegue outro.',
    );
  }

  return {
    baseUrl,
    apikey,
    token,
    expiraEm: corpo && corpo.exp ? new Date(corpo.exp * 1000) : null,
    operador: (corpo && (corpo.email || corpo.sub)) || '-',
  };
}

/* ------------------------------------------------------------------ */
/* Cliente HTTP                                                        */
/* ------------------------------------------------------------------ */

class ErroApi extends Error {
  constructor(status, codigo, mensagem, detalhes) {
    super(mensagem);
    this.status = status;
    this.codigo = codigo;
    this.detalhes = detalhes;
  }
}

function criarCliente(env) {
  return async function pedir(caminho, opcoes = {}) {
    const { metodo = 'GET', corpo, versao, filtros } = opcoes;
    const url = new URL(env.baseUrl + '/admin/' + caminho.map(encodeURIComponent).join('/'));
    for (const [chave, valor] of Object.entries(filtros || {})) {
      if (valor === undefined || valor === null || valor === '') continue;
      url.searchParams.set(chave, String(valor));
    }

    const cabecalhos = {
      Accept: 'application/json',
      apikey: env.apikey,
      /* Vive so nesta chamada. Nao e guardado nem impresso. */
      Authorization: 'Bearer ' + env.token,
    };
    if (corpo !== undefined) cabecalhos['Content-Type'] = 'application/json';
    if (versao) cabecalhos['If-Unmodified-Since-Version'] = versao;

    let resposta;
    try {
      resposta = await fetch(url, {
        method: metodo,
        headers: cabecalhos,
        body: corpo !== undefined ? JSON.stringify(corpo) : undefined,
      });
    } catch (erro) {
      throw new ErroApi(0, 'rede', 'Falha de rede em ' + metodo + ' ' + url.pathname + ': ' + erro.message);
    }

    if (resposta.status === 204) return undefined;
    const texto = await resposta.text();
    let json;
    try {
      json = texto ? JSON.parse(texto) : undefined;
    } catch {
      json = undefined;
    }

    if (!resposta.ok) {
      const codigo = (json && json.codigo) || String(resposta.status);
      const msg = (json && json.mensagem) || texto.slice(0, 300) || resposta.statusText;
      if (resposta.status === 401) {
        throw new ErroApi(
          401,
          codigo,
          'Sessao recusada (401): ' + msg + '\n  -> o token expirou ou nao e de operador. Pegue outro no painel.',
        );
      }
      throw new ErroApi(
        resposta.status,
        codigo,
        metodo + ' /admin/' + caminho.join('/') + ' -> ' + resposta.status + ' ' + codigo + ': ' + msg,
        json,
      );
    }
    return json;
  };
}

/** Lista paginada até o fim, sem confiar num número mágico de página. */
async function listarTudo(pedir, recurso, filtros = {}) {
  const itens = [];
  let pagina = 1;
  for (;;) {
    const r = await pedir([recurso], { filtros: { ...filtros, pagina, porPagina: 100 } });
    const lote = (r && r.itens) || [];
    itens.push(...lote);
    const total = Number((r && r.total) != null ? r.total : lote.length);
    if (!lote.length || itens.length >= total || pagina > 50) break;
    pagina += 1;
  }
  return itens;
}

/* ------------------------------------------------------------------ */
/* Relatório de lacunas                                                */
/* ------------------------------------------------------------------ */

const vazio = (v) => v === null || v === undefined || v === '' || (Array.isArray(v) && v.length === 0);

/* Campo cuja ausência é legítima em bloco operacional: intervalo não
   tem palestrante, credenciamento não tem tema. Cobrar isso encheria o
   relatório de ruído e esconderia a lacuna que importa.
   As duas grafias de `em curadoria` estão aqui de propósito: o
   bootstrap devolve com hífen, o painel conhece com underscore. */
const TIPOS_OPERACIONAIS = new Set([
  'credenciamento',
  'almoco',
  'intervalo',
  'em_curadoria',
  'em-curadoria',
]);

function contarFaltas(linhas, lista, campos, rotuloTotal) {
  linhas.push(rotuloTotal);
  for (const campo of campos) {
    const faltando = lista.filter((r) => vazio(r[campo])).length;
    if (faltando) {
      linhas.push('  ' + campo.padEnd(20) + String(faltando).padStart(3) + '/' + lista.length);
    }
  }
}

function relatorioLacunas(dados) {
  const linhas = [];
  const conteudo = dados.sessions.filter((s) => !TIPOS_OPERACIONAIS.has(s.tipo));

  contarFaltas(
    linhas,
    conteudo,
    ['descricao', 'temas', 'palestranteIds', 'espacoId', 'nivel', 'resultadosEsperados', 'fim'],
    'SESSOES: ' + dados.sessions.length + ' (' + conteudo.length + ' de conteudo, ' +
      (dados.sessions.length - conteudo.length) + ' operacionais)',
  );
  const porStatus = dados.sessions.reduce((a, s) => ((a[s.status] = (a[s.status] || 0) + 1), a), {});
  linhas.push('  status: ' + JSON.stringify(porStatus));

  linhas.push('');
  contarFaltas(
    linhas,
    dados.speakers,
    ['biografia', 'foto', 'temas', 'cargo', 'organizacao'],
    'PALESTRANTES: ' + dados.speakers.length,
  );

  linhas.push('');
  contarFaltas(
    linhas,
    dados.spaces,
    ['aliases', 'comoChegar', 'descricao', 'andar'],
    'ESPACOS: ' + dados.spaces.length,
  );

  linhas.push('');
  linhas.push('DETALHE — sessoes de conteudo incompletas:');
  for (const s of conteudo) {
    const faltam = ['descricao', 'temas', 'palestranteIds', 'espacoId'].filter((c) => vazio(s[c]));
    if (!faltam.length) continue;
    linhas.push(
      '  ' + (s.dia || '?') + ' ' + (s.inicio || '?') + ' [' + s.tipo + '] ' +
        String(s.titulo).slice(0, 52).padEnd(52) + ' falta: ' + faltam.join(', ') + '  #' + s.id,
    );
  }

  linhas.push('');
  linhas.push('DETALHE — palestrantes incompletos:');
  for (const p of dados.speakers) {
    const faltam = ['biografia', 'foto', 'temas', 'cargo', 'organizacao'].filter((c) => vazio(p[c]));
    if (!faltam.length) continue;
    linhas.push('  ' + String(p.nome).padEnd(32) + ' falta: ' + faltam.join(', ') + '  #' + p.id);
  }

  return linhas.join('\n');
}

/* ------------------------------------------------------------------ */
/* Comandos                                                            */
/* ------------------------------------------------------------------ */

async function baixarTudo(pedir) {
  const [event, themes, spaces, speakers, sessions] = await Promise.all([
    listarTudo(pedir, 'event'),
    listarTudo(pedir, 'themes'),
    listarTudo(pedir, 'spaces'),
    listarTudo(pedir, 'speakers'),
    listarTudo(pedir, 'sessions'),
  ]);
  return { event, themes, spaces, speakers, sessions };
}

async function cmdInspecionar(env, pedir, opcoes) {
  const dados = await baixarTudo(pedir);
  mkdirSync(opcoes.saida, { recursive: true });
  const alvo = join(opcoes.saida, 'snapshot.json');
  writeFileSync(alvo, JSON.stringify({ _gerado_em: new Date().toISOString(), ...dados }, null, 2), 'utf8');

  console.log(
    'Operador: ' + env.operador + (env.expiraEm ? '  · token expira ' + env.expiraEm.toISOString() : ''),
  );
  console.log('Snapshot: ' + alvo + '\n');
  for (const [chave, lista] of Object.entries(dados)) {
    console.log('  ' + chave.padEnd(10) + String(lista.length).padStart(4) + ' registros');
  }
  console.log('\n' + relatorioLacunas(dados));
  return dados;
}

async function cmdLacunas(env, pedir, opcoes) {
  const alvo = join(opcoes.saida, 'snapshot.json');
  const dados = existsSync(alvo) ? JSON.parse(readFileSync(alvo, 'utf8')) : await baixarTudo(pedir);
  console.log(relatorioLacunas(dados));
}

/* Um plano é uma lista de intenções declaradas, não código:
     { recurso, acao: 'atualizar' | 'criar' | 'publicar', id?,
       campos?, motivo? }
   Manter os dados fora do script é o que permite revisar o diff antes
   de escrever — e reler depois o que exatamente foi mandado. */
async function cmdAplicar(env, pedir, opcoes) {
  if (!opcoes.plano) morrer('Falta o arquivo de plano: `aplicar <plano.json>`.');
  const caminho = resolve(opcoes.plano);
  if (!existsSync(caminho)) morrer('Plano nao encontrado: ' + caminho);
  const plano = JSON.parse(readFileSync(caminho, 'utf8'));
  const itens = Array.isArray(plano) ? plano : plano.itens || [];
  if (!itens.length) morrer('Plano vazio.');

  const atual = await baixarTudo(pedir);
  const porId = {};
  for (const [recurso, lista] of Object.entries(atual)) {
    porId[recurso] = new Map(lista.map((r) => [r.id, r]));
  }

  mkdirSync(opcoes.saida, { recursive: true });
  const diario = join(opcoes.saida, 'escritas.jsonl');
  const registrar = (linha) =>
    appendFileSync(diario, JSON.stringify({ em: new Date().toISOString(), ...linha }) + '\n', 'utf8');

  let feitos = 0;
  let pulados = 0;
  let erros = 0;
  console.log(
    (opcoes.aplicar ? '### APLICANDO' : '### DRY-RUN (nada e enviado; use --aplicar)') +
      ' — ' + itens.length + ' itens\n',
  );

  for (const item of itens) {
    const { recurso, acao = 'atualizar', id, campos = {}, motivo = '' } = item;
    if (!recurso) {
      console.log('  ? item sem recurso, ignorado');
      pulados += 1;
      continue;
    }

    const registro = id && porId[recurso] ? porId[recurso].get(id) : null;
    const rotulo = registro
      ? registro.titulo || registro.nome || id
      : campos.titulo || campos.nome || '(novo)';
    const sufixo = motivo ? '   (' + motivo + ')' : '';

    if (opcoes.aplicar && feitos >= opcoes.limite) {
      console.log('  || limite de ' + opcoes.limite + ' escritas atingido; o resto ficou de fora.');
      break;
    }

    if (acao === 'atualizar') {
      if (!registro) {
        console.log('  [x] ' + recurso + ' #' + id + ' nao existe no banco');
        erros += 1;
        continue;
      }

      /* O coração da idempotência: só entra o que está vazio, a menos
         que alguém peça explicitamente para sobrescrever. */
      const mudar = {};
      const preservados = [];
      for (const [campo, valor] of Object.entries(campos)) {
        if (JSON.stringify(registro[campo]) === JSON.stringify(valor)) continue;
        if (!vazio(registro[campo]) && !opcoes.sobrescrever) {
          preservados.push(campo);
          continue;
        }
        mudar[campo] = valor;
      }
      if (preservados.length) {
        console.log('  · ' + rotulo + ' — ja preenchido, preservado: ' + preservados.join(', '));
      }
      if (!Object.keys(mudar).length) {
        pulados += 1;
        continue;
      }

      console.log(
        '  -> PATCH ' + recurso + ' "' + String(rotulo).slice(0, 48) + '"  campos: ' +
          Object.keys(mudar).join(', ') + sufixo,
      );
      for (const [campo, valor] of Object.entries(mudar)) {
        const texto = typeof valor === 'string' ? valor : JSON.stringify(valor);
        console.log('      ' + campo + ': ' + (texto.length > 160 ? texto.slice(0, 157) + '...' : texto));
      }

      if (!opcoes.aplicar) {
        feitos += 1;
        continue;
      }
      try {
        const r = await pedir([recurso, id], {
          metodo: 'PATCH',
          corpo: mudar,
          versao: registro.atualizadoEm,
        });
        registrar({ recurso, id, campos: Object.keys(mudar), ok: true });
        porId[recurso].set(id, r || registro);
        feitos += 1;
      } catch (erro) {
        console.log('    [x] ' + erro.message);
        registrar({ recurso, id, ok: false, erro: erro.message });
        erros += 1;
        if (!opcoes.continuar) morrer('Parei no primeiro erro. Use --continuar para seguir mesmo assim.');
      }
      continue;
    }

    if (acao === 'criar') {
      console.log('  -> POST ' + recurso + ' "' + String(rotulo).slice(0, 48) + '"' + sufixo);
      console.log('      ' + JSON.stringify(campos).slice(0, 400));
      if (!opcoes.aplicar) {
        feitos += 1;
        continue;
      }
      try {
        const r = await pedir([recurso], { metodo: 'POST', corpo: campos });
        console.log('      criado #' + ((r && r.id) || '?'));
        registrar({ recurso, acao: 'criar', id: r && r.id, ok: true });
        feitos += 1;
      } catch (erro) {
        console.log('    [x] ' + erro.message);
        registrar({ recurso, acao: 'criar', ok: false, erro: erro.message });
        erros += 1;
        if (!opcoes.continuar) morrer('Parei no primeiro erro. Use --continuar para seguir mesmo assim.');
      }
      continue;
    }

    if (acao === 'publicar') {
      if (!registro) {
        console.log('  [x] ' + recurso + ' #' + id + ' nao existe no banco');
        erros += 1;
        continue;
      }
      console.log(
        '  -> PUBLISH ' + recurso + ' "' + String(rotulo).slice(0, 48) +
          '" (status atual: ' + registro.status + ')' + sufixo,
      );
      if (!opcoes.aplicar) {
        feitos += 1;
        continue;
      }
      try {
        await pedir([recurso, id, 'publish'], {
          metodo: 'POST',
          corpo: { atualizadoEmEsperado: registro.atualizadoEm },
          versao: registro.atualizadoEm,
        });
        registrar({ recurso, id, acao: 'publicar', ok: true });
        feitos += 1;
      } catch (erro) {
        console.log('    [x] ' + erro.message);
        registrar({ recurso, id, acao: 'publicar', ok: false, erro: erro.message });
        erros += 1;
        if (!opcoes.continuar) morrer('Parei no primeiro erro. Use --continuar para seguir mesmo assim.');
      }
      continue;
    }

    console.log('  ? acao desconhecida: ' + acao);
    pulados += 1;
  }

  console.log(
    '\n' + (opcoes.aplicar ? 'Escritas: ' : 'Escreveria: ') + feitos +
      ' · sem mudanca: ' + pulados + ' · erros: ' + erros,
  );
  if (opcoes.aplicar && feitos) console.log('Diario: ' + diario);
  if (!opcoes.aplicar && feitos) console.log('\nPara valer: repita com --aplicar');
}

/* ------------------------------------------------------------------ */
/* Entrada                                                             */
/* ------------------------------------------------------------------ */

const argv = process.argv.slice(2);
const posicionais = argv.filter((a) => !a.startsWith('-'));
const comando = posicionais[0] || 'inspecionar';
const pegar = (nome, padrao) => {
  const i = argv.indexOf('--' + nome);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : padrao;
};
const opcoes = {
  aplicar: argv.includes('--aplicar'),
  sobrescrever: argv.includes('--sobrescrever'),
  continuar: argv.includes('--continuar'),
  limite: Number(pegar('limite', 25)),
  saida: resolve(pegar('saida', join(RAIZ, '.banco'))),
  plano: posicionais[1],
};

try {
  const env = ambiente();
  const pedir = criarCliente(env);
  if (comando === 'inspecionar') await cmdInspecionar(env, pedir, opcoes);
  else if (comando === 'lacunas') await cmdLacunas(env, pedir, opcoes);
  else if (comando === 'aplicar') await cmdAplicar(env, pedir, opcoes);
  else morrer('Comando desconhecido: ' + comando + '. Use inspecionar | lacunas | aplicar.');
} catch (erro) {
  /* `Saida` já foi explicada por `morrer`. Repetir viraria erro em dobro. */
  if (!(erro instanceof Saida)) {
    console.error('\n[x] ' + (erro instanceof ErroApi ? erro.message : (erro && erro.stack) || String(erro)) + '\n');
    process.exitCode = 1;
  }
}
