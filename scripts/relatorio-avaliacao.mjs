#!/usr/bin/env node
/* ============================================================
   relatorio-avaliacao.mjs — a Avaliação do dia em PDF
   ============================================================
   USO

     1. rode `scripts/relatorio-avaliacao.sql` no SQL Editor do Supabase
     2. salve a coluna `dados` num arquivo
     3. npm run relatorio:avaliacao -- <arquivo.json> [saida.pdf]

   POR QUE DOIS PASSOS, e não um script que busca sozinho: o token do
   operador (`MINDAGENT_ADMIN_TOKEN`) vence em cerca de uma hora, e um
   relatório que falha por token vencido justo na hora em que alguém
   pede é pior que dois passos. A consulta lê; este arquivo só desenha.

   O QUE ELE GARANTE, e que é o motivo de existir em vez de alguém
   montar a tabela na mão:

   - MÉDIA NUNCA SOZINHA. Toda média sai com o tamanho da amostra ao
     lado. 5,0 com uma resposta e 5,0 com duzentas são números
     diferentes na cabeça de quem decide.
   - ATIVIDADE SEM NOTA NÃO É ATIVIDADE RUIM. Ela aparece como "Sem
     avaliações", nunca como zero, e cai para o fim da ordenação em vez
     de liderar a lista das piores.
   - RESPOSTA DE TESTE NÃO ENTRA NA CONTA. Quem tem `"teste": true` no
     JSON aparece marcada e fica fora de todas as médias.

   CONTÉM DADO PESSOAL: nome, e-mail, profissão e o que cada pessoa
   escreveu. O PDF é de uso interno e está no `.gitignore`.
*/

import PDFDocument from 'pdfkit';
import { createWriteStream, readFileSync, existsSync } from 'node:fs';

const [, , entradaArg, saidaArg] = process.argv;

if (!entradaArg) {
  console.error(`
  Falta o arquivo com o resultado da consulta.

    1. rode scripts/relatorio-avaliacao.sql no SQL Editor
    2. salve a coluna "dados" num arquivo
    3. npm run relatorio:avaliacao -- dados.json
`);
  process.exit(1);
}
if (!existsSync(entradaArg)) {
  console.error(`  arquivo não encontrado: ${entradaArg}`);
  process.exit(1);
}

let d;
try {
  d = JSON.parse(readFileSync(entradaArg, 'utf8'));
} catch (e) {
  console.error(`  o arquivo não é JSON válido: ${e.message}`);
  process.exit(1);
}
for (const campo of ['respostas', 'porAtividade']) {
  if (!Array.isArray(d[campo])) {
    console.error(`  falta "${campo}" — o arquivo não veio da consulta certa.`);
    process.exit(1);
  }
}

const SAIDA = saidaArg || `avaliacao-do-dia-${new Date().toISOString().slice(0, 10)}.pdf`;

const TINTA = '#16161d', SUAVE = '#4a4a57', MUDO = '#7a7a88';
const VERDE = '#0f7a45', CORAL = '#b23a22', LINHA = '#e0e1dc', CAIXA = '#f5f6f3';

const M = 52;
const doc = new PDFDocument({
  size: 'A4', bufferPages: true, margins: { top: M, bottom: M, left: M, right: M },
  info: { Title: 'Avaliação do dia · ' + (d.evento || 'Mind Summit'), Author: 'Mind Agent' },
});
doc.pipe(createWriteStream(SAIDA));
const L = doc.page.width - M * 2;

/* Quebra de página que não corta um bloco no meio. */
const espaco = (h) => { if (doc.y + h > doc.page.height - M) doc.addPage(); };
const regua = (y) => doc.moveTo(M, y).lineTo(M + L, y).lineWidth(0.5).strokeColor(LINHA).stroke();
const vg = (n) => (n === null || n === undefined ? '—' : Number(n).toFixed(2).replace('.', ','));

/* TESTE FORA DA CONTA. Ele aparece no documento, marcado, porque sumir
   com uma linha que existe no banco confunde quem for conferir — mas
   não entra em média nenhuma. */
const reais = d.respostas.filter((r) => !r.teste);
const n = reais.length;
const media = (f) => (n ? reais.reduce((s, r) => s + r[f], 0) / n : null);
const quantos = (e) => reais.filter((r) => r.experiencia === e).length;
const p45 = (f) => (n ? Math.round(100 * reais.filter((r) => r[f] >= 4).length / n) : null);

/* ---------------- capa ---------------- */
doc.font('Helvetica').fontSize(8.5).fillColor(MUDO)
  .text((d.evento || 'MIND SUMMIT').toUpperCase(), M, M, { characterSpacing: 1.1 });
doc.moveDown(1.2);
doc.font('Helvetica-Bold').fontSize(26).fillColor(TINTA).text('Avaliação do dia', { lineGap: 2 });
doc.font('Helvetica').fontSize(11).fillColor(SUAVE).text(d.recorte || '');
doc.moveDown(0.8);
doc.fontSize(9.5).fillColor(MUDO).text(
  `Gerado em ${d.geradoEm || '—'}. ${n} ${n === 1 ? 'resposta' : 'respostas'} de participantes` +
  (d.respostas.length > n
    ? ` (${d.respostas.length - n} de teste, fora das médias).`
    : '.'),
  { width: L * 0.9 });
doc.moveDown(0.6);
doc.fontSize(8.5).fillColor(CORAL).text(
  'CONTÉM DADO PESSOAL: e-mail, profissão e o que cada pessoa escreveu. Uso interno.',
  { width: L * 0.9 });

/* RESSALVA DE LEITURA, quando existe. Um relatório que não consegue dizer
   "estes números têm um problema conhecido" mente por omissão — e quem
   recebe age sobre a média sem saber o que ela esconde. */
if (d.ressalva) {
  doc.moveDown(0.8);
  const y = doc.y;
  doc.font('Helvetica').fontSize(9).fillColor(TINTA)
    .text(d.ressalva, M + 12, y, { width: L - 24, lineGap: 2.5 });
  doc.moveTo(M + 2, y - 2).lineTo(M + 2, doc.y).lineWidth(2).strokeColor(CORAL).stroke();
  doc.x = M;
}

doc.moveDown(1.2);
regua(doc.y);
doc.moveDown(1.2);

/* ---------------- os números ---------------- */
function cartao(x, y, w, titulo, valor, apoio) {
  doc.roundedRect(x, y, w, 70, 10).fillColor(CAIXA).fill();
  doc.font('Helvetica-Bold').fontSize(8).fillColor(MUDO)
    .text(titulo.toUpperCase(), x + 12, y + 12, { width: w - 24, characterSpacing: 0.6 });
  doc.font('Helvetica-Bold').fontSize(21).fillColor(TINTA)
    .text(valor, x + 12, y + 26, { width: w - 24 });
  doc.font('Helvetica').fontSize(8).fillColor(SUAVE)
    .text(apoio, x + 12, y + 52, { width: w - 24 });
}

const larg = (L - 16) / 3;
const yCartoes = doc.y;
cartao(M, yCartoes, larg, 'Respondentes', String(n),
  `Mind ${quantos('mind')} · VIP ${quantos('vip')} · Prime ${quantos('prime')}`);
/* A amostra vai grudada na média, e não numa legenda longe dela. */
cartao(M + larg + 8, yCartoes, larg, 'Relevância', vg(media('relevancia')) + ' / 5',
  n ? `${n} respostas · ${p45('relevancia')}% deram 4 ou 5` : 'sem respostas');
cartao(M + (larg + 8) * 2, yCartoes, larg, 'Programação', vg(media('programacao')) + ' / 5',
  n ? `${n} respostas · ${p45('programacao')}% deram 4 ou 5` : 'sem respostas');
doc.y = yCartoes + 86;
doc.x = M;

/* ---------------- os mesmos números, por dia ----------------
   O total esconde o que separa os dois dias, e é justamente aí que a
   leitura muda: a média geral sobe ou desce conforme o dia de maior
   volume, e quem decide precisa ver os dois lado a lado.

   Cada linha carrega a própria amostra. Um dia com 24 respostas e outro
   com 15 não são comparáveis sem isso — e a diferença entre 4,50 e 4,33
   cabe inteira dentro dessa distância. */
/* A MESMA TABELA SERVE AOS DOIS RECORTES. "Dia a dia" na pesquisa do dia
   e "Por ingresso" na do evento são a mesma pergunta — os três números
   separados por um corte, cada linha com a própria amostra. Duas cópias
   divergiriam na primeira vez que alguém mexesse em uma só. */
function tabelaKpi(titulo, subtitulo, primeira, linhas) {
  if (!linhas || !linhas.length) return;
  espaco(70);
  doc.font('Helvetica-Bold').fontSize(13).fillColor(TINTA).text(titulo);
  doc.font('Helvetica').fontSize(8.5).fillColor(MUDO).text(subtitulo, { width: L * 0.95 });
  doc.moveDown(0.8);

  /* Cabeçalho da tabelinha. Colunas fixas: número alinhado embaixo de
     número é o que deixa comparar sem contar casas. */
  const col = [0, 132, 208, 268, 344, 404, 470];
  const cabeca = (t, i, alinha) =>
    doc.font('Helvetica-Bold').fontSize(7.5).fillColor(MUDO)
      .text(t.toUpperCase(), M + col[i], doc.y, {
        width: col[i + 1] - col[i] - 8, align: alinha || 'left', characterSpacing: 0.5,
        lineBreak: false,
      });

  const yCab = doc.y;
  [primeira, 'Respostas', 'Relevância', '4 ou 5', 'Programação', '4 ou 5']
    .forEach((t, i) => { doc.y = yCab; cabeca(t, i, i >= 2 ? 'right' : (i === 1 ? 'right' : 'left')); });
  doc.x = M;
  doc.y = yCab + 12;
  regua(doc.y);
  doc.moveDown(0.5);

  for (const l of linhas) {
    espaco(26);
    const y = doc.y;
    const cel = (t, i, forte) => {
      doc.y = y;
      doc.font(forte ? 'Helvetica-Bold' : 'Helvetica').fontSize(forte ? 11 : 9.5)
        .fillColor(forte ? TINTA : SUAVE)
        .text(t, M + col[i], y, {
          width: col[i + 1] - col[i] - 8, align: i >= 1 ? 'right' : 'left', lineBreak: false,
        });
    };
    doc.font('Helvetica-Bold').fontSize(9.5).fillColor(TINTA)
      .text(l.rotulo, M + col[0], y, { width: col[1] - col[0] - 8, lineBreak: false });
    cel(String(l.n), 1, false);
    cel(vg(l.relevancia), 2, true);
    cel(l.p45relevancia + '%', 3, false);
    cel(vg(l.programacao), 4, true);
    cel(l.p45programacao + '%', 5, false);

    doc.x = M;
    doc.y = y + 15;
    if (l.apoio) {
      doc.font('Helvetica').fontSize(8).fillColor(MUDO)
        .text(l.apoio, M + col[0], doc.y, { width: L, lineBreak: false });
      doc.y += 11;
    }
    doc.x = M;
    regua(doc.y);
    doc.moveDown(0.5);
  }
  doc.moveDown(0.8);
}

tabelaKpi('Dia a dia',
  'Os mesmos três números, separados. A amostra vem em cada linha porque é ela que diz o quanto a diferença entre os dias significa.',
  'Dia', d.porDia);

/* ---------------- por atividade ----------------
   Também compartilhada pelas duas pesquisas: cada uma traz a própria
   lista, e a regra de leitura — média com amostra ao lado, atividade sem
   nota escrita por extenso e nunca como zero — vale igual nas duas. */
function tabelaDeAtividades(titulo, subtitulo, lista) {
  if (!lista || !lista.length) return;
  espaco(70);
  doc.font('Helvetica-Bold').fontSize(13).fillColor(TINTA).text(titulo);
  doc.font('Helvetica').fontSize(8.5).fillColor(MUDO).text(subtitulo, { width: L * 0.95 });
  doc.moveDown(0.7);

  /* Num relatório de mais de um dia, "11:30" aparece duas vezes e não quer
     dizer a mesma coisa. O dia entra como cabeçalho de grupo quando a
     consulta o traz; num relatório de um dia só, nada muda. */
  let diaCorrente = null;

  for (const a of lista) {
    if (a.dia && a.dia !== diaCorrente) {
      diaCorrente = a.dia;
      espaco(34);
      doc.moveDown(0.6);
      doc.font('Helvetica-Bold').fontSize(9).fillColor(SUAVE)
        .text(a.dia, M, doc.y, { characterSpacing: 0.8 });
      doc.moveDown(0.3);
    }
    espaco(28);
    const y = doc.y;
    doc.font('Helvetica-Bold').fontSize(8.5).fillColor(VERDE).text(a.inicio || '', M, y, { width: 34 });
    doc.font('Helvetica').fontSize(9).fillColor(TINTA)
      .text(a.titulo, M + 38, y, { width: L - 160, lineGap: 1 });
    doc.fontSize(8).fillColor(MUDO).text(a.espaco || '', M + 38, doc.y, { width: L - 160 });
    const yFim = Math.max(doc.y, y + 12);

    if (!a.n) {
      doc.font('Helvetica-Oblique').fontSize(8.5).fillColor(MUDO)
        .text('Sem avaliações', M + L - 118, y, { width: 118, align: 'right' });
    } else {
      doc.font('Helvetica-Bold').fontSize(11).fillColor(TINTA)
        .text(vg(a.media), M + L - 118, y - 1, { width: 60, align: 'right' });
      doc.font('Helvetica').fontSize(8).fillColor(MUDO)
        .text(`${a.n} ${a.n === 1 ? 'avaliação' : 'avaliações'}`,
          M + L - 56, y + 1, { width: 56, align: 'right' });
    }
    doc.x = M;
    doc.y = yFim + 5;
    regua(doc.y - 2);
  }
  doc.moveDown(0.5);
}

tabelaDeAtividades('Por atividade',
  'A média vem sempre com o número de avaliações ao lado. Atividade que ninguém avaliou aparece como "Sem avaliações", nunca como zero.',
  d.porAtividade);

/* ---------------- as respostas ---------------- */
doc.addPage();
doc.font('Helvetica-Bold').fontSize(13).fillColor(TINTA).text('As respostas, uma a uma');
doc.font('Helvetica').fontSize(8.5).fillColor(MUDO)
  .text('Texto exatamente como foi escrito, sem correção de digitação.');
doc.moveDown(1);

function aberta(rotulo, texto) {
  if (!texto) return;
  espaco(44);
  doc.font('Helvetica-Bold').fontSize(7.5).fillColor(MUDO)
    .text(rotulo.toUpperCase(), M + 12, doc.y, { width: L - 24, characterSpacing: 0.5 });
  doc.font('Helvetica').fontSize(9.5).fillColor(TINTA)
    .text(texto, M + 12, doc.y + 1, { width: L - 24, lineGap: 2 });
  doc.moveDown(0.45);
}

for (const r of d.respostas) {
  espaco(115);
  const yTopo = doc.y;

  doc.font('Helvetica-Bold').fontSize(10.5).fillColor(TINTA)
    .text((r.nome || 'Sem nome no cadastro') + (r.teste ? '  (teste)' : ''),
      M + 12, yTopo, { width: L - 150 });
  doc.font('Helvetica').fontSize(8.5).fillColor(MUDO)
    .text([r.email || 'sem e-mail no cadastro', r.profissao].filter(Boolean).join(' · '),
      M + 12, doc.y, { width: L - 150 });

  /* Ressalva desta resposta em particular — por que ela merece leitura
     diferente das outras. Fica colada nela, e não numa nota de rodapé
     que ninguém liga à linha certa. */
  if (r.alerta) {
    doc.font('Helvetica-Oblique').fontSize(8).fillColor(CORAL)
      .text(r.alerta, M + 12, doc.y + 1, { width: L - 150, lineGap: 1 });
  }

  doc.font('Helvetica-Bold').fontSize(8.5).fillColor(r.teste ? MUDO : VERDE)
    .text(`${String(r.experiencia || '').toUpperCase()} · relevância ${r.relevancia} · programação ${r.programacao}`,
      M + L - 200, yTopo, { width: 200, align: 'right' });
  doc.font('Helvetica').fontSize(8).fillColor(MUDO)
    .text(`${r.quando} · ${r.atividades} ${r.atividades === 1 ? 'atividade' : 'atividades'} avaliadas`,
      M + L - 200, yTopo + 12, { width: 200, align: 'right' });

  doc.x = M;
  doc.y = Math.max(doc.y, yTopo + 28);
  doc.moveDown(0.3);

  aberta('Expectativas', r.expectativas);
  aberta('O que mais gostou', r.maisGostou);
  aberta('O que podemos melhorar', r.melhorar);
  aberta('Comentário', r.comentario);

  doc.moveTo(M + 2, yTopo - 2).lineTo(M + 2, doc.y - 2).lineWidth(2)
    .strokeColor(r.teste ? LINHA : VERDE).stroke();
  doc.x = M;
  doc.moveDown(0.5);
  regua(doc.y);
  doc.moveDown(0.8);
}

/* ---------------- a outra pesquisa ----------------
   A Avaliação do EVENTO, quando o arquivo a traz. Ela entra como seção
   própria, e não misturada: são perguntas diferentes sobre recortes
   diferentes — uma sobre o dia, outra sobre o Summit inteiro — e somar
   as duas médias daria um número que não responde a pergunta nenhuma. */
if (d.pesquisaDoEvento && Array.isArray(d.pesquisaDoEvento.respostas)) {
  const ev = d.pesquisaDoEvento.respostas.filter((r) => !r.teste);
  const ne = ev.length;
  const mediaEv = (f) => (ne ? ev.reduce((s, r) => s + r[f], 0) / ne : null);

  doc.addPage();
  doc.font('Helvetica-Bold').fontSize(13).fillColor(TINTA).text('Avaliação do evento');
  doc.font('Helvetica').fontSize(8.5).fillColor(MUDO).text(
    'Outra pesquisa, sobre o Summit inteiro, aberta depois que ele acabou. ' +
    'As notas abaixo NÃO se somam às de cima: são perguntas diferentes sobre ' +
    'recortes diferentes.', { width: L * 0.95 });
  doc.moveDown(0.9);

  if (!ne) {
    doc.font('Helvetica-Oblique').fontSize(10).fillColor(MUDO)
      .text('Ainda sem respostas de participantes.');
  } else {
    const y = doc.y;
    const larg2 = (L - 16) / 3;
    cartao(M, y, larg2, 'Respondentes', String(ne),
      d.pesquisaDoEvento.apoio || 'desde que a pesquisa abriu');
    cartao(M + larg2 + 8, y, larg2, 'Relevância', vg(mediaEv('relevancia')) + ' / 5',
      `${ne} ${ne === 1 ? 'resposta' : 'respostas'}`);
    cartao(M + (larg2 + 8) * 2, y, larg2, 'Programação', vg(mediaEv('programacao')) + ' / 5',
      `${ne} ${ne === 1 ? 'resposta' : 'respostas'}`);
    doc.y = y + 86;
    doc.x = M;

    /* AMOSTRA PEQUENA SE ANUNCIA. Uma média de duas respostas tem o mesmo
       tamanho de fonte que uma de duzentas, e é isso que engana. */
    if (ne < 10) {
      doc.font('Helvetica-Bold').fontSize(9).fillColor(CORAL).text(
        `Amostra de ${ne}: leia as respostas, não a média.`, M, doc.y);
      doc.moveDown(0.8);
    }

    /* POR INGRESSO, e não por dia: esta pesquisa é sobre o Summit inteiro,
       então o corte que separa experiências diferentes é o ingresso, não
       a data. Mesma tabela, outra pergunta. */
    tabelaKpi('Por ingresso',
      'Mind, VIP e Prime viveram eventos diferentes — lounge, masterclass e fila de almoço não são os mesmos. ' +
      'Com amostras deste tamanho a diferença entre as linhas sugere, não comprova.',
      'Ingresso', d.pesquisaDoEvento.porTicket);

    tabelaDeAtividades('Por atividade, no evento inteiro',
      'Aqui a pessoa avaliou a programação dos dois dias de uma vez, olhando para trás. ' +
      'São notas diferentes das da pesquisa do dia: outro momento, outra memória, outra amostra.',
      d.pesquisaDoEvento.porAtividade);

    doc.addPage();
    doc.font('Helvetica-Bold').fontSize(13).fillColor(TINTA)
      .text('As respostas do evento, uma a uma');
    doc.font('Helvetica').fontSize(8.5).fillColor(MUDO)
      .text('Texto exatamente como foi escrito, sem correção de digitação.');
    doc.moveDown(1);

    for (const r of ev) {
      espaco(115);
      const yTopo = doc.y;
      doc.font('Helvetica-Bold').fontSize(10.5).fillColor(TINTA)
        .text(r.nome || 'Sem nome no cadastro', M + 12, yTopo, { width: L - 150 });
      doc.font('Helvetica').fontSize(8.5).fillColor(MUDO)
        .text([r.email || 'sem e-mail no cadastro', r.profissao].filter(Boolean).join(' · '),
          M + 12, doc.y, { width: L - 150 });
      doc.font('Helvetica-Bold').fontSize(8.5).fillColor(VERDE)
        .text(`${String(r.experiencia || '').toUpperCase()} · relevância ${r.relevancia} · programação ${r.programacao}`,
          M + L - 200, yTopo, { width: 200, align: 'right' });
      doc.font('Helvetica').fontSize(8).fillColor(MUDO)
        .text(r.quando + (r.origem ? ' · ' + r.origem : ''),
          M + L - 200, yTopo + 12, { width: 200, align: 'right' });

      doc.x = M;
      doc.y = Math.max(doc.y, yTopo + 28);
      doc.moveDown(0.3);
      aberta('Expectativas', r.expectativas);
      aberta('O que mais gostou', r.maisGostou);
      aberta('O que podemos melhorar', r.melhorar);
      aberta('Comentário', r.comentario);

      doc.moveTo(M + 2, yTopo - 2).lineTo(M + 2, doc.y - 2).lineWidth(2).strokeColor(VERDE).stroke();
      doc.x = M;
      doc.moveDown(0.5);
      regua(doc.y);
      doc.moveDown(0.8);
    }
  }
}

/* ---------------- rodapé ----------------
   `margins.bottom = 0` ANTES de escrever, e não é firula: o rodapé fica
   abaixo da margem inferior, e o pdfkit responde a isso criando uma
   página nova — uma por rodapé. O documento dobrava de tamanho, metade
   das páginas saía sem rodapé e a numeração dizia "1/5" num PDF de dez.
   Zerar a margem faz a escrita caber onde ela deve estar. */
const total = doc.bufferedPageRange().count;
for (let i = 0; i < total; i++) {
  doc.switchToPage(i);
  doc.page.margins.bottom = 0;
  doc.font('Helvetica').fontSize(7.5).fillColor(MUDO).text(
    `Avaliação do dia · ${d.evento || 'Mind Summit'} · uso interno · ${d.geradoEm || ''}     ${i + 1}/${total}`,
    M, doc.page.height - 34, { width: L, align: 'center', lineBreak: false });
}

doc.end();
console.log(`  ${SAIDA} — ${n} ${n === 1 ? 'resposta' : 'respostas'}, ${total} páginas`);
