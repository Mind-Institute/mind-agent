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

/* ---------------- por atividade ---------------- */
doc.font('Helvetica-Bold').fontSize(13).fillColor(TINTA).text('Por atividade');
doc.font('Helvetica').fontSize(8.5).fillColor(MUDO)
  .text('A média vem sempre com o número de avaliações ao lado. Atividade que ninguém avaliou aparece como "Sem avaliações", nunca como zero.');
doc.moveDown(0.7);

/* Num relatório de mais de um dia, "11:30" aparece duas vezes e não quer
   dizer a mesma coisa. O dia entra como cabeçalho de grupo quando a
   consulta o traz; num relatório de um dia só, nada muda. */
let diaCorrente = null;

for (const a of d.porAtividade) {
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
