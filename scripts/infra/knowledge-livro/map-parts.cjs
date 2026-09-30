// Maps each "part" (chapter file) to master PDF pages by comparing page texts.
// Usage: node map-parts.cjs master2.jsonl <dir with part-N.jsonl> > mapping.json
// A part is accepted only when every non-empty page matches a master page and the matches are contiguous.
const fs = require('fs');
const path = require('path');
const [masterFile, partsDir] = process.argv.slice(2);
const load = (f) => fs.readFileSync(f, 'utf8').split('\n').filter(Boolean).map(JSON.parse);
const txt = (p) => p.lines.map((l) => l.r.map((x) => x[0]).join('')).join(' ').normalize('NFC');
const toks = (s) => new Set(s.toLowerCase().replace(/[^a-z0-9à-ÿ ]+/g, ' ').split(/\s+/).filter((w) => w.length > 2));
const sim = (a, b) => { if (!a.size || !b.size) return 0; let n = 0; for (const w of a) if (b.has(w)) n++; return n / Math.max(a.size, b.size); };
const M = load(masterFile).map((p) => ({ page: p.page, t: toks(txt(p)) }));
const parts = fs.readdirSync(partsDir).filter((f) => /^part-\d+\.jsonl$/.test(f)).sort((a, b) => parseInt(a.slice(5), 10) - parseInt(b.slice(5), 10));
const rows = parts.map((f) => {
  const P = load(path.join(partsDir, f));
  const map = P.map((p) => { const t = toks(txt(p)); if (!t.size) return { page: p.page, best: null, score: 0 }; let best = null, bs = 0; for (const m of M) { const s = sim(t, m.t); if (s > bs) { bs = s; best = m.page; } } return { page: p.page, best, score: bs }; });
  const ne = map.filter((x) => x.best);
  const contiguous = ne.every((x, k) => k === 0 || x.best === ne[k - 1].best + (x.page - ne[k - 1].page));
  const off = ne.length ? ne[0].best - ne[0].page : null;
  return { part: parseInt(f.slice(5), 10), pages: P.length, masterStart: off == null ? null : 1 + off, masterEnd: off == null ? null : P.length + off, contiguous, minScore: Math.min(...ne.map((x) => x.score)) };
});
console.log(JSON.stringify(rows, null, 1));
