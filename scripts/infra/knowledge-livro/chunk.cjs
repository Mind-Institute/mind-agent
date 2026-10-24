// Structure rows + chunks for the pilot book, from out/canon.json.
// Usage: node chunk.cjs out/canon.json files.json out/
//   files.json: {master:{id,path,url,size,pages}, parts:[{part,id,path,url,size,pages,masterStart,masterEnd}], duplicates:[...]}
// Rules:
//   * a chunk never crosses its leaf structural unit (chapter intro, section intro, subsection, notes group);
//   * chunks are packed from whole blocks (paragraphs, lists, captions, tables); target 1800 chars, max 2600, min 600;
//   * a block longer than the max is split at sentence boundaries, with one sentence of overlap between its pieces;
//   * every chunk is an exact slice of the canonical text: texto === text.slice(char_start, char_end).
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const [canonFile, filesFile, outDir] = process.argv.slice(2);
const J = JSON.parse(fs.readFileSync(canonFile, 'utf8'));
const F = JSON.parse(fs.readFileSync(filesFile, 'utf8'));
const T = J.text;
const S = J.structure;
const TARGET = 1800, MAX = 2600, MIN = 600;
const uuid = () => crypto.randomUUID();
const OFFSET = 18;
const bookLabel = (pdf) => (pdf >= 19 ? String(pdf - OFFSET) : ['i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii', 'ix', 'x', 'xi', 'xii', 'xiii', 'xiv', 'xv', 'xvi', 'xvii', 'xviii'][pdf - 1]);
const bookInt = (pdf) => (pdf >= 19 ? pdf - OFFSET : null);

// ---------- page lookup for any character range (uses exact in-block page breaks) ----------
const blocks = J.blocks;
function pagesOf(a, b) {
  const pages = new Set();
  for (const bl of blocks) {
    if (bl.charEnd <= a || bl.charStart >= b) continue;
    const ps = bl.pages || [{ pdf: bl.pageStart, at: bl.charStart }];
    for (let i = 0; i < ps.length; i++) {
      const s = ps[i].at, e = i + 1 < ps.length ? ps[i + 1].at : bl.charEnd;
      if (e > a && s < b) pages.add(ps[i].pdf);
    }
  }
  const arr = [...pages].sort((x, y) => x - y);
  return arr.length ? [arr[0], arr[arr.length - 1]] : [null, null];
}
function partFor(pdf) { return F.parts.find((p) => pdf >= p.masterStart && pdf <= p.masterEnd) || null; }
function locationOf(p0, p1) {
  const a = partFor(p0), b = partFor(p1);
  const loc = { master_drive_file_id: F.master.id, master_pdf_pages: [p0, p1] };
  if (a) {
    loc.chapter_file = { drive_file_id: a.id, part: a.part, file_pages: [p0 - a.masterStart + 1, (b && b.part === a.part ? p1 : a.masterEnd) - a.masterStart + 1] };
    if (b && b.part !== a.part) loc.chapter_file_next = { drive_file_id: b.id, part: b.part, file_pages: [1, p1 - b.masterStart + 1] };
  }
  return loc;
}

// ---------- chapter titles in their printed case (from the Contents page) ----------
const contents = T.slice(...(() => { const b = blocks.find((x) => x.type === 'front' && /^CONTENTS/.test(T.slice(x.charStart, x.charEnd))); return [b.charStart, b.charEnd]; })());
function printedTitle(upper) {
  const i = contents.toLowerCase().indexOf(upper.toLowerCase());
  return i >= 0 ? contents.slice(i, i + upper.length) : upper;
}

// ---------- structure rows ----------
const sections = [];
let ordem = 0;
function addSection(row) {
  const [p0, p1] = pagesOf(row.charStart, row.charEnd);
  const id = uuid();
  const r = {
    id, parent_section_id: row.parent || null, tipo_secao: row.tipo, numero: row.numero || null, titulo: row.titulo, ordem: ++ordem,
    pagina_inicio: p0 ? bookInt(p0) : null, pagina_fim: p1 ? bookInt(p1) : null,
    mapa_estruturado: {
      pdf_pages: [p0, p1], book_pages: [p0 ? bookLabel(p0) : null, p1 ? bookLabel(p1) : null], char_range: [row.charStart, row.charEnd],
      location: p0 ? locationOf(p0, p1) : null, heading_source: row.headingSource,
    },
    metadata: row.metadata || {},
    _charStart: row.charStart, _charEnd: row.charEnd,
  };
  sections.push(r);
  return r;
}
const P = S.preface;
const prefaceRow = addSection({ tipo: 'other', titulo: 'Preface', charStart: P.charStart, charEnd: P.charEnd, headingSource: 'typography (13pt) + Contents', metadata: { kind: 'preface' } });
const chapterRows = [];
for (const c of S.chapters) {
  const title = printedTitle(c.title);
  const cr = addSection({ tipo: 'chapter', numero: c.number, titulo: title, charStart: c.charStart, charEnd: c.charEnd, headingSource: 'typography (13pt label + 18pt title) + PDF outline + Contents (title and start page)' });
  cr._c = c; chapterRows.push(cr);
  for (const s of c.sections) {
    const sr = addSection({ tipo: 'section', titulo: s.title, parent: cr.id, charStart: s.charStart, charEnd: s.charEnd, headingSource: 'typography (11pt heading)' });
    s._row = sr;
    for (const u of s.subsections) { const ur = addSection({ tipo: 'subsection', titulo: u.title, parent: sr.id, charStart: u.charStart, charEnd: u.charEnd, headingSource: 'typography (10pt heading)' }); u._row = ur; }
  }
}
const back = {};
for (const x of S.backmatter) {
  const kind = { notes: 'notes', references: 'references', credits: 'illustration_credits', index: 'index' }[x.type];
  const title = { notes: 'Notes', references: 'References', credits: 'Illustration Credits', index: 'Index' }[x.type];
  const r = addSection({ tipo: 'other', titulo: title, charStart: x.charStart, charEnd: x.charEnd, headingSource: 'typography (13pt) + Contents', metadata: { kind } });
  back[x.type] = r;
  for (const g of x.groups || []) {
    const ch = chapterRows.find((cr) => cr.numero === g.annotates);
    g._row = addSection({ tipo: 'section', titulo: g.title, parent: r.id, charStart: g.charStart, charEnd: g.charEnd, headingSource: 'typography (10pt group heading in Notes)', metadata: { kind: 'notes_group', annotates_chapter: g.annotates, annotates_section_id: ch ? ch.id : null } });
  }
}

// ---------- units ----------
const units = []; // {start, end, chapterRow, sectionRow, subRow, tipo, labels}
const label = (cr) => `Chapter ${cr.numero}: ${cr.titulo}`;
units.push({ start: P.charStart, end: P.charEnd, leaf: prefaceRow, capitulo: 'Preface', secao: null, subsecao: null, tipo: 'body', chapterRow: null });
for (const cr of chapterRows) {
  const c = cr._c;
  const firstSec = c.sections[0];
  const introEnd = firstSec ? firstSec.charStart : c.charEnd;
  if (introEnd > c.charStart) units.push({ start: c.charStart, end: introEnd, leaf: cr, capitulo: label(cr), secao: null, subsecao: null, tipo: 'body', chapterRow: cr });
  for (const s of c.sections) {
    const firstSub = s.subsections[0];
    const sEnd = firstSub ? firstSub.charStart : s.charEnd;
    if (sEnd > s.charStart) units.push({ start: s.charStart, end: sEnd, leaf: s._row, capitulo: label(cr), secao: s.title, subsecao: null, tipo: 'body', chapterRow: cr, sectionRow: s._row });
    for (const u of s.subsections) units.push({ start: u.charStart, end: u.charEnd, leaf: u._row, capitulo: label(cr), secao: s.title, subsecao: u.title, tipo: 'body', chapterRow: cr, sectionRow: s._row });
  }
}
const notes = S.backmatter.find((x) => x.type === 'notes');
notes.groups.forEach((g, i) => {
  const ch = chapterRows.find((cr) => cr.numero === g.annotates);
  units.push({ start: i === 0 ? notes.charStart : g.charStart, end: g.charEnd, leaf: g._row, capitulo: 'Notes', secao: g.title, subsecao: null, tipo: 'notes', chapterRow: ch, annotates: g.annotates });
});

// ---------- packing ----------
const SENT = /(?<=[.?!]["”’)\]]*(?:\[\d+\])?)\s+(?=["“‘(\[]?[A-Z0-9])/g;
const ABBR = /\b(?:e\.g|i\.e|et al|cf|vs|Dr|Mr|Mrs|Ms|St|No|Vol|pp|p|ed|eds|Fig|U\.S|U\.K|ca|approx)\.$/i;
function sentencePieces(a, b) {
  // split [a,b) at sentence boundaries into pieces of about TARGET chars; one sentence of overlap between pieces
  const s = T.slice(a, b);
  const cuts = [0];
  for (const m of s.matchAll(SENT)) { const before = s.slice(0, m.index); if (!ABBR.test(before)) cuts.push(m.index + m[0].length); }
  const sentences = cuts.map((c, i) => [a + c, a + (i + 1 < cuts.length ? cuts[i + 1] : s.length)]);
  const pieces = [];
  let i = 0;
  while (i < sentences.length) {
    let j = i, start = sentences[i][0];
    while (j + 1 < sentences.length && sentences[j + 1][1] - start <= TARGET) j++;
    if (j === i && sentences[i][1] - start > MAX) { pieces.push([start, sentences[i][1], 0]); i++; continue; } // one giant sentence
    const endPiece = sentences[j][1];
    const next = j + 1 < sentences.length ? j : j + 1; // next piece starts with the last sentence of this one (overlap)
    pieces.push([start, endPiece]);
    if (j + 1 >= sentences.length) break;
    i = next === i ? i + 1 : next;
  }
  return pieces.map(([x, y]) => [x, T.slice(x, y).replace(/\s+$/, '').length + x]);
}
const chunks = [];
for (const u of units) {
  const ub = blocks.filter((b) => b.charStart >= u.start && b.charStart < u.end);
  const spans = []; // [start,end,types]
  let cur = null;
  const close = () => { if (cur) { spans.push(cur); cur = null; } };
  for (const b of ub) {
    const len = b.charEnd - b.charStart;
    if (len > MAX) {
      close();
      for (const [x, y] of sentencePieces(b.charStart, b.charEnd)) spans.push({ start: x, end: y, types: new Set([b.type]), split: true });
      continue;
    }
    if (!cur) { cur = { start: b.charStart, end: b.charEnd, types: new Set([b.type]) }; continue; }
    const would = b.charEnd - cur.start;
    const curLen = cur.end - cur.start;
    const isHeading = /^(chapter_label|chapter_title|section|subsection|part_title|notes_title|notes_group)$/.test(b.type);
    if (would <= TARGET || curLen < MIN && would <= MAX || isHeading && would <= MAX) { cur.end = b.charEnd; cur.types.add(b.type); }
    else { close(); cur = { start: b.charStart, end: b.charEnd, types: new Set([b.type]) }; }
  }
  close();
  // a span made only of heading blocks joins the next span of the unit
  for (let i = 0; i < spans.length - 1; i++) {
    const onlyHeadings = [...spans[i].types].every((t) => /^(chapter_label|chapter_title|section|subsection|part_title|notes_title|notes_group)$/.test(t));
    if (onlyHeadings) { spans[i + 1].start = spans[i].start; for (const t of spans[i].types) spans[i + 1].types.add(t); spans.splice(i, 1); i--; }
  }
  // any tiny span (e.g. a lone figure caption) joins a neighbour inside the same unit
  for (let i = 0; i < spans.length && spans.length > 1; i++) {
    const sp = spans[i]; if (sp.split || sp.end - sp.start >= 200) continue;
    const prev = spans[i - 1], next = spans[i + 1];
    if (prev && !prev.split && sp.end - prev.start <= MAX + 600) { prev.end = sp.end; for (const t of sp.types) prev.types.add(t); spans.splice(i, 1); i--; }
    else if (next && !next.split && next.end - sp.start <= MAX + 600) { next.start = sp.start; for (const t of sp.types) next.types.add(t); spans.splice(i, 1); i--; }
  }
  // tiny tail merges into the previous span when it stays reasonable
  if (spans.length > 1) { const last = spans[spans.length - 1], prev = spans[spans.length - 2]; const ll = last.end - last.start; if (ll < MIN / 2 && (last.end - prev.start <= MAX + 400 || ll < 200) && !last.split) { prev.end = last.end; for (const t of last.types) prev.types.add(t); spans.pop(); } }
  for (const sp of spans) {
    const [p0, p1] = pagesOf(sp.start, sp.end);
    const texto = T.slice(sp.start, sp.end);
    const prev = chunks[chunks.length - 1];
    const overlap = prev && prev._unit === u && prev.char_end > sp.start ? prev.char_end - sp.start : 0;
    const markers = [...texto.matchAll(/\[(\d+)\]/g)].map((m) => m[1]);
    chunks.push({
      id: uuid(), ordem: chunks.length + 1, char_start: sp.start, char_end: sp.end, texto,
      capitulo: u.capitulo, secao: u.secao, subsecao: u.subsecao,
      pagina_inicio: p0 ? bookInt(p0) : null, pagina_fim: p1 ? bookInt(p1) : null, tipo_trecho: u.tipo,
      metadata: {
        kind: 'source_text', chunker: 'book-pilot-v1', text_version: 1,
        char_start: sp.start, char_end: sp.end, overlap_chars: overlap,
        section_id: u.leaf.id, chapter_section_id: u.chapterRow ? u.chapterRow.id : null,
        section_path: [u.capitulo, u.secao, u.subsecao].filter(Boolean),
        pdf_pages: [p0, p1], book_pages: [p0 ? bookLabel(p0) : null, p1 ? bookLabel(p1) : null],
        location: p0 ? locationOf(p0, p1) : null,
        block_types: [...sp.types], note_markers: markers,
        ...(u.annotates ? { annotates_chapter: u.annotates } : {}),
      },
      _unit: u,
    });
  }
}

// ---------- verification ----------
const problems = [];
for (const c of chunks) {
  if (T.slice(c.char_start, c.char_end) !== c.texto) problems.push(['not_exact_slice', c.ordem]);
  if (c.char_start < c._unit.start || c.char_end > c._unit.end) problems.push(['crosses_unit', c.ordem]);
  if (!c.pagina_inicio && c.capitulo !== 'Preface') problems.push(['no_page', c.ordem]);
}
const bodyChars = units.reduce((n, u) => n + (u.end - u.start), 0);
const covered = new Array(T.length).fill(0);
for (const c of chunks) for (let i = c.char_start; i < c.char_end; i++) covered[i]++;
let uncovered = 0, doubled = 0;
for (const u of units) for (let i = u.start; i < u.end; i++) { if (!covered[i] && !/\s/.test(T[i])) uncovered++; if (covered[i] > 1) doubled++; }
const lens = chunks.map((c) => c.texto.length).sort((a, b) => a - b);
const q = (f) => lens[Math.floor((lens.length - 1) * f)];
const report = {
  chunks: chunks.length, units: units.length, sections: sections.length,
  byTipo: chunks.reduce((m, c) => (m[c.tipo_trecho] = (m[c.tipo_trecho] || 0) + 1, m), {}),
  size: { min: lens[0], p10: q(0.1), p50: q(0.5), p90: q(0.9), max: lens[lens.length - 1] },
  unitChars: bodyChars, uncoveredNonSpaceChars: uncovered, overlapChars: doubled,
  splitParagraphChunks: chunks.filter((c) => c.metadata.overlap_chars > 0).length,
  problems,
};
fs.mkdirSync(outDir, { recursive: true });
const clean = (o) => { const r = {}; for (const k in o) if (!k.startsWith('_')) r[k] = o[k]; return r; };
fs.writeFileSync(path.join(outDir, 'sections.json'), JSON.stringify(sections.map(clean), null, 1));
fs.writeFileSync(path.join(outDir, 'chunks.json'), JSON.stringify(chunks.map(clean), null, 1));
fs.writeFileSync(path.join(outDir, 'chunk-report.json'), JSON.stringify(report, null, 1));
console.log(JSON.stringify(report, null, 1));
