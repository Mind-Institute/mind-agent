// Checks that every 60-char window of every chunk is found in the raw text of the pages the chunk declares.
// Raw page text is split into a reading stream (body, headings, bullets; notes text on notes pages)
// and a float stream (captions, tables, small text), because figures interrupt paragraphs in the raw stream.
const fs = require('fs');
const arr = fs.readFileSync('master2.jsonl', 'utf8').split('\n').filter(Boolean).map(JSON.parse);
const key = (s) => s.normalize('NFC').toLowerCase().replace(/\[\d+\]/g, '').replace(/[^a-z0-9]+/g, '');
const txt = (l) => l.r.map((x) => x[0]).join('');
const sz = (l) => { for (const [t, s] of l.r) if (t.trim()) return s; return 0; };
const bodyKey = new Map(), floatKey = new Map();
for (const p of arr) {
  let L = p.lines.filter((l) => txt(l).trim());
  if (L.length && sz(L[0]) === 9 && !/^\s*•/.test(txt(L[0])) && txt(L[0]).trim().length < 60) L = L.slice(1);
  if (L.length && sz(L[L.length - 1]) === 9 && /^\s*([0-9]+|[ivxlc]+)\s*$/i.test(txt(L[L.length - 1]))) L = L.slice(0, -1);
  const strip = (l) => l.r.map(([t, s]) => (s <= 7 && /^\s*\d+\s*$/.test(t) ? '' : t)).join('');
  const notesPage = p.page >= 351 && p.page <= 390;
  const isBody = (l) => { const s = sz(l); return s >= 10 || /^\s*•/.test(txt(l)) || (notesPage && s >= 9); };
  bodyKey.set(p.page, key(L.filter(isBody).map(strip).join(' ')));
  floatKey.set(p.page, key(L.filter((l) => !isBody(l)).map(strip).join(' ')));
}
const C = JSON.parse(fs.readFileSync('out/chunks.json', 'utf8'));
let ok = 0; const miss = [];
for (const c of C) {
  const [p0, p1] = c.metadata.pdf_pages; let body = '', fl = '';
  for (let p = p0; p <= p1; p++) { body += bodyKey.get(p) || ''; fl += ' ' + (floatKey.get(p) || ''); }
  let good = true;
  for (const k of c.texto.split(/\n\n+/).map(key).filter(Boolean)) {
    for (let i = 0; i < k.length; i += 60) { const w = k.slice(i, i + 60); if (w.length < 12) continue; if (!body.includes(w) && !fl.includes(w)) { good = false; miss.push({ ordem: c.ordem, pages: [p0, p1], win: w }); break; } }
    if (!good) break;
  }
  if (good) ok++;
}
fs.writeFileSync('out/page-validation.json', JSON.stringify({ total: C.length, fullyInside: ok, misses: miss }, null, 1));
console.log('chunks fully inside declared page range:', ok, '/', C.length); for (const m of miss) console.log(JSON.stringify(m));
