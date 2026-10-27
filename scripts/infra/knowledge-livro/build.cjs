// Builds the canonical text of the pilot book from the master PDF dump (pagedump2 output).
// Usage: node build.cjs master2.jsonl outline.json out/
// Output: out/canon.txt, out/canon.json ({text, pageMap, blocks, structure, stats, decisions})
//
// Rules (all derived from the book's own typography, never invented):
//   running head = first line at 9pt that matches a known running head; folio = last line at 9pt (arabic/roman)
//   13pt "CHAPTER N" + 18pt title = chapter; 11pt = section; 10pt = subsection (only inside chapters)
//   10.5pt = body; 11pt "Table N.N."/"Box N.N:" = table/box title; 8pt "Figure N.N." = caption (+9pt continuation)
//   9pt bullets = lists; other small text inside chapters = chart labels (dropped, counted)
//   note markers = digit runs <= 7pt inside text lines, rendered as [n]
//   line-end hyphens: kept when the hyphenated form exists elsewhere in the book, joined when the joined
//   word exists in the dictionary or the book, joined by default otherwise; "x- y" mid-line = "x-y".
const fs = require('fs');
const path = require('path');

const [dumpFile, outlineFile, outDir] = process.argv.slice(2);
const pages = new Map(fs.readFileSync(dumpFile, 'utf8').split('\n').filter(Boolean).map((l) => { const p = JSON.parse(l); return [p.page, p]; }));
const outline = JSON.parse(fs.readFileSync(outlineFile, 'utf8'));
const NPAGES = Math.max(...pages.keys());

// NFC everywhere; the one private-use glyph in the book (U+F04A, a Wingdings smiley on p. 262) becomes U+263A
for (const pg of pages.values()) for (const l of pg.lines) for (const r of l.r) r[0] = r[0].normalize('NFC').replace(/\uF04A/g, '\u263A');
const lineText = (l) => l.r.map((x) => x[0]).join('');
const lineSize = (l) => { for (const [t, s] of l.r) if (t.trim()) return s; return 0; };
const squash = (s) => s.replace(/\s+/g, '').toUpperCase();

// ---------- regions from the outline (1-based PDF pages) ----------
const ch = outline.chapters; // [{n, title, pdf}]
const after = outline.backmatter; // {notes, references, credits, index}
const OFFSET = outline.bookPageOffset; // book page = pdf - OFFSET for arabic pages
function regionOf(p) {
  if (p < outline.preface.pdf) return { kind: 'front' };
  if (p < ch[0].pdf) return p <= outline.preface.end ? { kind: 'preface' } : { kind: 'front' };
  for (let i = ch.length - 1; i >= 0; i--) if (p >= ch[i].pdf && p < (ch[i + 1] ? ch[i + 1].pdf : after.notes)) return { kind: 'chapter', n: ch[i].n };
  if (p < after.references) return { kind: 'notes' };
  if (p < after.credits) return { kind: 'references' };
  if (p < after.index) return { kind: 'credits' };
  return { kind: 'index' };
}
const runningHeads = new Set(['PREFACE', 'NOTES', 'REFERENCES', 'ILLUSTRATIONCREDITS', 'INDEX', squash(outline.bookTitle)]);
for (const c of ch) { runningHeads.add('CHAPTER' + c.n); if (c.runningHead || c.title) runningHeads.add(squash(c.runningHead || c.title)); }
for (let n = 1; n <= ch.length; n++) runningHeads.add('NOTESTOCHAPTER' + n);
// Running heads observed in the book itself: a 9pt first line repeated on 2+ pages.
{
  const seen = new Map();
  for (const pg of pages.values()) { const l = pg.lines.find((x) => lineText(x).trim()); if (l && lineSize(l) === 9) { const k = squash(lineText(l)); seen.set(k, (seen.get(k) || 0) + 1); } }
  for (const [k, n] of seen) if (n >= 2 && !/^\d+$/.test(k)) runningHeads.add(k);
}
const romanLabel = (p) => { const r = ['i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii', 'ix', 'x', 'xi', 'xii', 'xiii', 'xiv', 'xv', 'xvi', 'xvii', 'xviii']; return r[p - 1] || null; };
function pageLabel(p) { if (p >= ch[0].pdf) return String(p - OFFSET); return romanLabel(p); }

// ---------- pass 1: classify lines ----------
const G_LINE = (() => { const a = []; for (const pg of pages.values()) for (const l of pg.lines) if (lineSize(l) === 10.5) a.push(lineText(l).trim().length); a.sort((x, y) => x - y); return a[Math.floor(a.length * 0.75)] || 70; })();
const itemEnds = (t) => t.trim().length < 0.85 * G_LINE && /[.?!:;”’")\]]$/.test(t.trim());
const hyEx = { kept: [], def: [] };
const stats = { droppedRunningHeads: 0, droppedFolios: 0, droppedChartLabels: 0, noteMarkers: 0, hyphenJoined: 0, hyphenKept: 0, hyphenDefault: 0, compoundSpaceFixed: 0, folioMismatch: [] };
const items = []; // {page, type, text, size}
for (let p = 1; p <= NPAGES; p++) {
  const pg = pages.get(p);
  const lines = (pg ? pg.lines : []).filter((l) => lineText(l).trim());
  if (!lines.length) continue;
  const reg = regionOf(p);
  let a = 0, z = lines.length;
  if (lineSize(lines[0]) === 9 && runningHeads.has(squash(lineText(lines[0])))) { a = 1; stats.droppedRunningHeads++; }
  const last = lines[z - 1];
  if (z > a && lineSize(last) === 9 && /^\s*([0-9]+|[ivxlc]+)\s*$/i.test(lineText(last))) {
    z--; stats.droppedFolios++;
    const expected = pageLabel(p);
    if (expected && lineText(last).trim().toLowerCase() !== expected) stats.folioMismatch.push({ pdf: p, printed: lineText(last).trim(), expected });
  }
  let mode = null; // 'caption' | 'table' | 'box' | 'list'
  let itemOpen = null; // type of a bulleted item still running on 10.5pt continuation lines
  for (let i = a; i < z; i++) {
    const l = lines[i];
    const s = lineSize(l);
    const t = lineText(l);
    const push = (type, extra) => items.push(Object.assign({ page: p, type, line: l, size: s }, extra || {}));
    if (reg.kind === 'front') { push('front'); continue; }
    if (reg.kind === 'index' || reg.kind === 'credits' || reg.kind === 'references') { push(reg.kind); continue; }
    if (reg.kind === 'notes') {
      if (s === 13) push('notes_title');
      else if (s === 10 && /^Chapter \d+\./.test(t)) push('notes_group');
      else push('note');
      continue;
    }
    // preface / chapters
    if (s === 13 && /^CHAPTER \d+$/.test(t.trim())) { push('chapter_label'); mode = null; continue; }
    if (s === 13) { push('part_title'); mode = null; continue; } // PREFACE heading
    if (s === 18) { push('chapter_title'); mode = null; continue; }
    if (s === 11 && (/^(Table \d+\.\d+)/.test(t) || (items.length && items[items.length - 1].type === 'table_title' && items[items.length - 1].page === p && !/\(cont\.\)\s*$/.test(lineText(items[items.length - 1].line))))) { push('table_title'); mode = 'table'; continue; }
    if (s === 11 && /^Box \d+\.\d+/.test(t)) { push('box_title'); mode = 'box'; continue; }
    if (s === 11) { push('section'); mode = null; continue; }
    if (s === 10 && reg.kind === 'chapter') { push('subsection'); mode = null; continue; }
    if (s === 10.5 && itemOpen) { push(itemOpen, { cont: true }); if (itemEnds(t)) itemOpen = null; continue; }
    if (s === 10.5) { push('body'); mode = null; continue; }
    if (s === 8 && /^Figure \d+\.\d+/.test(t)) { push('caption'); mode = 'caption'; continue; }
    if (mode === 'table') { push('table_cell'); continue; }
    if (s === 9 && /^\s*•/.test(t)) { const ty = mode === 'box' ? 'box_item' : 'list_item'; push(ty); if (mode !== 'box') mode = 'list'; itemOpen = itemEnds(t) ? null : ty; continue; }
    if ((s === 9 || s === 8) && mode === 'caption') { push('caption'); continue; }
    if (s === 9 && (mode === 'list' || mode === 'box')) { push(mode === 'box' ? 'box_item' : 'list_item', { cont: true }); continue; }
    if (s === 9 && t.trim().length >= 60) { push('caption', { orphan: true }); continue; }
    stats.droppedChartLabels++;
  }
}

// ---------- text of a line with note markers ----------
function renderLine(l, allowMarkers) {
  let out = '';
  for (const [t, s] of l.r) {
    if (allowMarkers && s <= 7 && /^\s*\d+\s*$/.test(t)) { out = out.replace(/\s+$/, '') + '[' + t.trim() + ']' + (/\s$/.test(t) ? ' ' : ''); stats.noteMarkers++; }
    else out += t;
  }
  return out;
}

// ---------- vocabulary for hyphenation ----------
const dict = new Set(fs.readFileSync('/usr/share/dict/words', 'utf8').split('\n').map((w) => w.toLowerCase()));
const vocab = new Map();
const hyphenForms = new Set();
for (const it of items) {
  const t = lineText(it.line);
  const toks = t.split(/[^A-Za-zÀ-ÿ'’-]+/).filter(Boolean);
  toks.forEach((w, i) => {
    const m = w.match(/^([A-Za-zÀ-ÿ]+)-([A-Za-zÀ-ÿ]+)$/);
    if (m) hyphenForms.add((m[1] + '-' + m[2]).toLowerCase());
    // whole words only: the first token of a line and a token ending in "-" can be fragments of a split word
    if (i === 0 || /-$/.test(w)) return;
    const k = w.toLowerCase();
    vocab.set(k, (vocab.get(k) || 0) + 1);
  });
  for (const m of t.matchAll(/([A-Za-zÀ-ÿ]+)- ([a-zà-ÿ][A-Za-zÀ-ÿ]*)/g)) hyphenForms.add((m[1] + '-' + m[2]).toLowerCase());
}
function knownDict(word) { return known(word, true); }
function known(word, dictOnly) {
  const w = word.toLowerCase();
  if (dict.has(w) || (!dictOnly && (vocab.get(w) || 0) > 0)) return true;
  for (const [suf, rep] of [['ies', 'y'], ['ied', 'y'], ['es', ''], ['s', ''], ['ed', ''], ['ed', 'e'], ['d', ''], ['ing', ''], ['ing', 'e'], ['ly', ''], ['er', ''], ['ers', ''], ['est', ''], ['ness', ''], ['al', ''], ['ally', ''], ['ity', ''], ['ation', 'e'], ['ations', 'e']]) {
    if (w.endsWith(suf) && w.length > suf.length + 1 && dict.has(w.slice(0, -suf.length) + rep)) return true;
  }
  return false;
}
function joinHyphen(left, right) {
  const l = left.match(/([A-Za-zÀ-ÿ]+)-$/);
  const r = right.match(/^([A-Za-zÀ-ÿ]+)/);
  if (!l || !r) return left + right; // not a word hyphen: glue as is
  const a = l[1], b = r[1];
  const tok = (left.match(/(\S+)$/) || ['', ''])[1];
  if (/[A-Za-zÀ-ÿ]-[A-Za-zÀ-ÿ]+-$/.test(tok)) { stats.hyphenKept++; hyEx.kept.push(tok + b); return left + right; } // "vis-à-" + "vis"
  if (/^(and|or|nor|to)$/.test(b) && !/^[A-Za-zÀ-ÿ]+-/.test(right)) { stats.hyphenKept++; hyEx.kept.push(a + '- ' + b); return left + ' ' + right; } // suspended hyphen
  if (hyphenForms.has((a + '-' + b).toLowerCase())) { stats.hyphenKept++; hyEx.kept.push(a + '-' + b); return left + right; }
  if (known(a + b)) { stats.hyphenJoined++; return left.slice(0, -1) + right; }
  if (/^[A-Z]/.test(b)) { stats.hyphenKept++; hyEx.kept.push(a + '-' + b); return left + right; } // e.g. "anti-Semitic"
  if ((knownDict(a) || (vocab.get(a.toLowerCase()) || 0) >= 3) && knownDict(b) && a.length > 1) { stats.hyphenKept++; hyEx.kept.push(a + '-' + b + ' (compound)'); return left + right; }
  stats.hyphenDefault++; hyEx.def.push(tok + ' + ' + b);
  return left.slice(0, -1) + right;
}
// suspended hyphens ("prestige- and dominance-based") keep their space
const fixCompounds = (s) => s.replace(/([A-Za-zÀ-ÿ0-9])- (?!(?:and|or|nor|to|versus) )(?=[A-Za-zÀ-ÿ0-9])/g, (m, a) => { stats.compoundSpaceFixed++; return a + '-'; });

// ---------- pass 2: blocks (paragraph-level) ----------
// Paragraph end heuristic: a body line is "short" (< 85% of the page's typical line) and ends a sentence.
const typical = new Map();
for (const it of items) if (it.type === 'body' || it.type === 'note') { const arr = typical.get(it.page) || []; arr.push(lineText(it.line).trim().length); typical.set(it.page, arr); }
for (const [p, arr] of typical) { arr.sort((x, y) => x - y); typical.set(p, arr[Math.floor(arr.length * 0.75)] || 70); }
const endsSentence = (s) => /[.?!:;”’")\]]$/.test(s.trim());

const blocks = []; // {type, text, pageStart, pageEnd, level?}
let cur = null;
function flush() { if (cur) { const lead = cur.text.length - cur.text.replace(/^\s+/, '').length; cur.text = cur.text.trim(); if (cur.breaks) cur.breaks.forEach((b) => { b.at = Math.max(0, b.at - lead); }); if (cur.text) blocks.push(cur); cur = null; } }
function appendLine(type, it, text, opts) {
  opts = opts || {};
  text = fixCompounds(text).replace(/[ \t]+/g, ' ');
  if (cur && cur.type === type && !opts.forceNew) {
    const leading = text.match(/^\[\d+\]/); // marker at line start belongs to the previous sentence
    if (leading) { cur.text = cur.text.replace(/\s+$/, '') + leading[0]; text = text.slice(leading[0].length); }
    const before = cur.text.length;
    let at = before + 1;
    if (/[A-Za-zÀ-ÿ]-$/.test(cur.text) && /^[A-Za-zÀ-ÿ]/.test(text.trim())) { cur.text = joinHyphen(cur.text, text.trim()); at = cur.text.length >= before ? before - 1 : before; }
    else if (/(https?:\/\/\S*|\/)$/.test(cur.text) || /^\./.test(text.trim())) { cur.text += text.trim(); at = before; }
    else cur.text += ' ' + text.trim();
    if (it.page !== cur.pageEnd) { cur.breaks = cur.breaks || []; cur.breaks.push({ page: it.page, at }); }
    cur.pageEnd = it.page;
  } else {
    flush();
    cur = { type, text: text.trim(), pageStart: it.page, pageEnd: it.page };
  }
}
// Reading order: a figure or table that interrupts a paragraph is emitted after that paragraph ends.
{
  const FLOAT = new Set(['caption', 'table_title', 'table_cell']);
  const ordered = []; let buf = []; let open = false;
  for (const it of items) {
    if (FLOAT.has(it.type)) { if (open) { buf.push(it); continue; } ordered.push(it); continue; }
    if (it.type === 'body') {
      ordered.push(it);
      const raw = lineText(it.line);
      const ends = raw.trim().length < 0.85 * (typical.get(it.page) || 70) && endsSentence(raw);
      open = !ends;
      if (!open && buf.length) { ordered.push(...buf); buf = []; }
      continue;
    }
    if (buf.length) { ordered.push(...buf); buf = []; }
    open = false; ordered.push(it);
  }
  ordered.push(...buf);
  stats.floatsMoved = items.length === ordered.length ? items.reduce((n, it, i) => n + (it !== ordered[i] ? 1 : 0), 0) : -1;
  items.length = 0; items.push(...ordered);
}
let prevBodyEnded = true;
for (let i = 0; i < items.length; i++) {
  const it = items[i];
  const raw = lineText(it.line);
  switch (it.type) {
    case 'front': case 'index': case 'credits': case 'references': {
      const t = renderLine(it.line, false);
      const startsEntry = it.type === 'references' ? (/^———|^[A-ZÀ-Ý][^\s,]+(?:[ -][A-ZÀ-Ý][^\s,]*)*,\s/.test(t.trim()) && cur && endsSentence(cur.text)) : false;
      appendLine(it.type, it, t, { forceNew: startsEntry || it.type === 'front' && /^(CONTENTS|PREFACE|For Jessica)/.test(t.trim()) });
      break;
    }
    case 'chapter_label': flush(); cur = { type: 'chapter_label', text: raw.trim(), pageStart: it.page, pageEnd: it.page }; flush(); break;
    case 'chapter_title': case 'part_title': case 'section': case 'subsection': case 'table_title': case 'box_title': case 'notes_title': case 'notes_group': {
      const t = fixCompounds(renderLine(it.line, false)).replace(/[ \t]+/g, ' ').trim();
      const prev = items[i - 1];
      // multi-line heading: adjacent lines of the same heading style on the same page form one heading
      // (verified on the page image of p.66: "Why Care What Others Think? / Conformist Transmission" is one centered heading)
      const continues = cur && cur.type === it.type && prev && prev.type === it.type && prev.page === it.page;
      if (continues) { cur.text = /-$/.test(cur.text) ? joinHyphen(cur.text, t) : cur.text + ' ' + t; cur.pageEnd = it.page; }
      else { flush(); cur = { type: it.type, text: t, pageStart: it.page, pageEnd: it.page }; }
      if (!items[i + 1] || items[i + 1].type !== it.type) flush();
      prevBodyEnded = true;
      break;
    }
    case 'body': case 'note': {
      const t = renderLine(it.line, true);
      const isNoteStart = it.type === 'note' && /^\d+\.\s/.test(t.trim());
      appendLine(it.type, it, t, { forceNew: prevBodyEnded || isNoteStart });
      const len = raw.trim().length;
      prevBodyEnded = len < 0.85 * (typical.get(it.page) || 70) && endsSentence(raw);
      break;
    }
    case 'caption': {
      const t = renderLine(it.line, true);
      appendLine('caption', it, t, { forceNew: /^Figure \d/.test(t.trim()) && !(cur && cur.type === 'caption' && !/[.)]$/.test(cur.text)) });
      prevBodyEnded = true; break;
    }
    case 'list_item': case 'box_item': {
      const t = renderLine(it.line, true);
      appendLine(it.type, it, t, { forceNew: /^\s*•/.test(t) });
      prevBodyEnded = true; break;
    }
    case 'table_cell': appendLine('table_cell', it, renderLine(it.line, false)); prevBodyEnded = true; break;
  }
}
flush();

// ---------- pass 3: canonical text with offsets, page map, structure ----------
let text = '';
const pageStarts = [];
const pageMap = new Map(); // pdf page -> {start,end}
const touch = (p, a, b) => { const e = pageMap.get(p); if (!e) pageMap.set(p, { start: a, end: b }); else { e.start = Math.min(e.start, a); e.end = Math.max(e.end, b); } };
const structure = { preface: null, chapters: [], backmatter: [] };
let chapter = null, section = null, notesGroup = null, notes = null;
const open = [];
function startNode(node) { node.charStart = text.length; node.pdfStart = node.pdfStart || null; return node; }
function closeNode(node) { if (node && node.charEnd == null) node.charEnd = text.length; }
for (const b of blocks) {
  // structure bookkeeping before writing the block
  if (b.type === 'part_title' && /^PREFACE$/.test(b.text)) { structure.preface = startNode({ type: 'preface', title: 'Preface', pdfStart: b.pageStart }); }
  if (b.type === 'chapter_label') {
    closeNode(section); closeNode(chapter); if (structure.preface) closeNode(structure.preface);
    const n = Number(b.text.replace(/\D+/g, ''));
    chapter = startNode({ type: 'chapter', number: String(n), title: null, pdfStart: b.pageStart, sections: [] });
    structure.chapters.push(chapter); section = null;
  }
  if (b.type === 'chapter_title' && chapter && !chapter.title) chapter.title = b.text;
  if (b.type === 'section' && chapter) { closeNode(section); section = startNode({ type: 'section', title: b.text, pdfStart: b.pageStart, subsections: [] }); chapter.sections.push(section); }
  if (b.type === 'subsection' && chapter) {
    if (!section) { section = startNode({ type: 'section', title: null, implicit: true, pdfStart: b.pageStart, subsections: [] }); chapter.sections.push(section); }
    const prevSub = section.subsections[section.subsections.length - 1]; if (prevSub) closeNode(prevSub);
    section.subsections.push(startNode({ type: 'subsection', title: b.text, pdfStart: b.pageStart }));
  }
  if (b.type === 'section' || b.type === 'chapter_label') { /* subsections closed with their section */ }
  if (b.type === 'notes_title') { closeNode(section); closeNode(chapter); chapter = null; section = null; notes = startNode({ type: 'notes', title: 'Notes', pdfStart: b.pageStart, groups: [] }); structure.backmatter.push(notes); }
  if (b.type === 'notes_group' && notes) { closeNode(notesGroup); const m = b.text.match(/^Chapter (\d+)\.\s*(.*)$/); notesGroup = startNode({ type: 'notes_group', title: b.text, annotates: m ? m[1] : null, pdfStart: b.pageStart }); notes.groups.push(notesGroup); }
  if (b.type === 'references' && !structure.backmatter.find((x) => x.type === 'references')) { closeNode(notesGroup); closeNode(notes); structure.backmatter.push(startNode({ type: 'references', title: 'References', pdfStart: b.pageStart })); }
  if (b.type === 'credits' && !structure.backmatter.find((x) => x.type === 'credits')) { for (const x of structure.backmatter) closeNode(x); structure.backmatter.push(startNode({ type: 'credits', title: 'Illustration Credits', pdfStart: b.pageStart })); }
  if (b.type === 'index' && !structure.backmatter.find((x) => x.type === 'index')) { for (const x of structure.backmatter) closeNode(x); structure.backmatter.push(startNode({ type: 'index', title: 'Index', pdfStart: b.pageStart })); }
  if (structure.preface && structure.preface.charEnd == null && b.type === 'front' && b.pageStart > outline.preface.end) structure.preface.charEnd = text.length;
  // write block
  const sep = text ? (b.type === 'chapter_label' ? '\n\n\n' : '\n\n') : '';
  const start = text.length + sep.length;
  let body = b.text;
  if (b.type === 'list_item' || b.type === 'box_item') body = body.replace(/^•\s*/, '• ');
  text += sep + body;
  b.charStart = start; b.charEnd = text.length;
  b.pages = [{ pdf: b.pageStart, at: start }];
  for (const br of b.breaks || []) b.pages.push({ pdf: br.page, at: start + br.at + (body.length - b.text.length) });
  for (const x of b.pages) pageStarts.push(x);
  for (let p = b.pageStart; p <= b.pageEnd; p++) touch(p, start, text.length);
  // close subsections/sections lazily: record end at the last written block
  const lastSub = section && section.subsections[section.subsections.length - 1];
  for (const node of [lastSub, section, chapter, notesGroup, notes, structure.preface].filter(Boolean)) if (node.charEnd == null) node.lastEnd = text.length;
}
function finalize(node) { if (!node) return; if (node.charEnd == null) node.charEnd = node.lastEnd != null ? node.lastEnd : text.length; delete node.lastEnd; }
finalize(structure.preface);
for (const c of structure.chapters) { finalize(c); for (const s of c.sections) { finalize(s); for (const u of s.subsections) finalize(u); } }
for (const x of structure.backmatter) { finalize(x); for (const g of x.groups || []) finalize(g); }
// section ends: a section ends where the next sibling starts; a subsection ends where the next subsection or section starts
for (const c of structure.chapters) {
  const all = c.sections;
  for (let i = 0; i < all.length; i++) {
    const s = all[i]; const next = all[i + 1];
    s.charEnd = next ? next.charStart : c.charEnd;
    for (let j = 0; j < s.subsections.length; j++) { const u = s.subsections[j]; const nu = s.subsections[j + 1]; u.charEnd = nu ? nu.charStart : s.charEnd; }
  }
}
// page ranges from char offsets
const pm = [...pageMap.entries()].sort((x, y) => x[0] - y[0]).map(([pdf, r]) => ({ pdf, label: pageLabel(pdf), start: r.start, end: r.end }));
function pagesFor(a, b) { const hit = pm.filter((e) => e.end > a && e.start < b); return hit.length ? [hit[0].pdf, hit[hit.length - 1].pdf] : [null, null]; }
function annotate(node) { const [p0, p1] = pagesFor(node.charStart, node.charEnd); node.pdfStart = p0; node.pdfEnd = p1; node.bookStart = p0 ? pageLabel(p0) : null; node.bookEnd = p1 ? pageLabel(p1) : null; }
if (structure.preface) annotate(structure.preface);
for (const c of structure.chapters) { annotate(c); for (const s of c.sections) { annotate(s); for (const u of s.subsections) annotate(u); } }
for (const x of structure.backmatter) { annotate(x); for (const g of x.groups || []) annotate(g); }

fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'canon.txt'), text);
fs.writeFileSync(path.join(outDir, 'hyphen-review.json'), JSON.stringify(hyEx, null, 1));
const firstAt = new Map(); for (const ps of pageStarts) if (!firstAt.has(ps.pdf) || ps.at < firstAt.get(ps.pdf)) firstAt.set(ps.pdf, ps.at);
const pageStartList = [...firstAt.entries()].sort((x, y) => x[1] - y[1] || x[0] - y[0]).map(([pdf, at]) => ({ pdf, label: pageLabel(pdf), at }));
fs.writeFileSync(path.join(outDir, 'canon.json'), JSON.stringify({ text, pageStarts: pageStartList, pageMap: pm, blocks: blocks.map((b) => ({ type: b.type, pageStart: b.pageStart, pageEnd: b.pageEnd, charStart: b.charStart, charEnd: b.charEnd, pages: b.pages })), structure, stats }, null, 1));
const nSec = structure.chapters.reduce((a, c) => a + c.sections.length, 0);
const nSub = structure.chapters.reduce((a, c) => a + c.sections.reduce((x, s) => x + s.subsections.length, 0), 0);
console.log(JSON.stringify({ chars: text.length, blocks: blocks.length, byType: blocks.reduce((m, b) => (m[b.type] = (m[b.type] || 0) + 1, m), {}), chapters: structure.chapters.length, sections: nSec, subsections: nSub, notesGroups: (structure.backmatter.find((x) => x.type === 'notes') || { groups: [] }).groups.length, stats }, null, 1));
