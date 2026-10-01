/* ============================================================================
 * BANCO DE PROVAS DO AGENTE DO APP — contra o agente NO AR
 *
 * Conversa com a Edge `mindagent-chat` exatamente como o app: usuário anônimo
 * (signup do Supabase Auth), mesma sessão entre as falas de um cenário, sem
 * e-mail (nenhuma pessoa real é casada). Cada cenário usa um usuário novo.
 *
 * Custa chamadas reais à OpenAI e grava conversas de teste em
 * engagement.conversas (canal mindagent-web, sem mind_id de pessoa real).
 * O relatório lista os ids para limpeza.
 *
 * Como rodar:  node scripts/testar-agente-app.mjs [saida.md] [filtro]
 * ==========================================================================*/

import { writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';

const URL_BASE = 'https://ymnmotgglsrxmjmonwjz.supabase.co';
const CHAVE = 'sb_publishable__wYRbYyBgK_MBfqmLpiZNg_Z8iJNxvc';
const EVENTO = 'mind-summit-2026';

/* Cenários tirados de conversas reais do app (17 a 24/09) e dos leads do Institute.
   `espera` é o que um bom profissional faria — é para a leitura humana, não é asserção. */
export const CENARIOS = [
  { id: 'institute-nr1', area: 'Institute', falas: [
    'Sou gerente de RH e preciso aprender a implementar a NR-1 e os riscos psicossociais na minha empresa. Vocês têm algum curso?',
    'Quanto custa e quando começa?',
  ], espera: 'Indica a formação certa do Institute (saúde mental/NR-1), diz o que sabe de preço/turma sem inventar e oferece falar com o time.' },
  { id: 'institute-carreira', area: 'Institute', falas: [
    'Quero fazer uma transição de carreira para a área de saúde emocional nas organizações. O que o Mind Institute oferece para mim?',
  ], espera: 'Entende a transição de carreira e recomenda formação com motivo, sem empurrar Summit.' },
  { id: 'institute-lideres', area: 'Institute', falas: [
    'Meu desafio tem sido engajar mais as equipes e cuidar dos líderes.',
    'O que você me recomenda?',
  ], espera: 'Faz uma pergunta boa ou recomenda Engajamento/Liderança; lembra da fala anterior.' },
  { id: 'dash-160', area: 'Dash', falas: [
    'Tenho 160 funcionários que parecem não se importar com o emprego nem ter orgulho da empresa. Como vocês podem ajudar a minha empresa?',
    'Como funciona e quanto custa?',
  ], espera: 'Reconhece caso de empresa (Dash), explica diagnóstico/intervenção e encaminha para o time; não inventa preço.' },
  { id: 'dash-nr1', area: 'Dash', falas: [
    'Preciso de um diagnóstico de riscos psicossociais na empresa por causa da NR-1. Vocês fazem isso?',
  ], espera: 'Explica o que o Dash faz para NR-1 e oferece contato do time.' },
  { id: 'suporte-certificado', area: 'Suporte', falas: [
    'Como obtenho o certificado?',
  ], espera: 'Regra oficial do certificado (a partir de 30 dias, e-mail do ingresso) de forma direta.' },
  { id: 'suporte-fone', area: 'Suporte', falas: [
    'Esqueci de entregar o fone de tradução e meu documento ficou retido. Como resolvo?',
  ], espera: 'Acolhe e dá um caminho concreto de contato; não repete regra de retirada do fone.' },
  { id: 'suporte-gravacoes', area: 'Suporte', falas: [
    'Sou VIP. Onde assisto as gravações?',
    'E quando liberam?',
  ], espera: 'Plataforma do Mind Institute, 45 dias, 90 dias de acesso; segunda fala sem repetir tudo.' },
  { id: 'concierge-mala', area: 'Concierge', falas: [
    'Há algum lugar onde eu possa guardar minha mala??',
  ], espera: 'Chapelaria, com localização.' },
  { id: 'venda-encerrada', area: 'Venda encerrada', falas: [
    'Quero comprar um ingresso VIP para o Summit.',
  ], espera: 'Diz que o Summit 2026 já aconteceu e não está à venda; não oferece checkout; pode falar de Institute.' },
];

async function signup() {
  const r = await fetch(`${URL_BASE}/auth/v1/signup`, {
    method: 'POST', headers: { apikey: CHAVE, 'Content-Type': 'application/json' }, body: '{}',
  });
  const j = await r.json();
  if (!j.access_token) throw new Error('signup falhou: ' + JSON.stringify(j).slice(0, 200));
  return j.access_token;
}

async function falar(token, dispositivo, sessao, mensagem) {
  const inicio = Date.now();
  const r = await fetch(`${URL_BASE}/functions/v1/mindagent-chat`, {
    method: 'POST',
    headers: { apikey: CHAVE, Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message: mensagem, event_slug: EVENTO, device_id: dispositivo,
      client_message_id: randomUUID(), session: sessao || undefined,
    }),
  });
  const j = await r.json().catch(() => ({}));
  return { status: r.status, ms: Date.now() - inicio, corpo: j };
}

async function rodarCenario(c) {
  const token = await signup();
  const dispositivo = randomUUID();
  let sessao = null;
  const turnos = [];
  for (const fala of c.falas) {
    const r = await falar(token, dispositivo, sessao, fala);
    if (r.corpo.session) sessao = r.corpo.session;
    turnos.push({
      fala, status: r.status, ms: r.ms,
      resposta: r.corpo.answer ?? r.corpo.error?.message ?? '(sem resposta)',
      rota: r.corpo.rota ?? null, conversa: r.corpo.session?.conversation_id ?? null,
    });
  }
  return { ...c, turnos };
}

async function main() {
  const saida = process.argv[2] || 'relatorio-agente.md';
  const filtro = process.argv[3];
  const escolhidos = CENARIOS.filter((c) => !filtro || c.id.includes(filtro) || c.area.toLowerCase().includes(filtro));
  const resultados = [];
  for (const c of escolhidos) {
    process.stderr.write(`→ ${c.id}\n`);
    try { resultados.push(await rodarCenario(c)); }
    catch (e) { resultados.push({ ...c, erro: String(e) }); }
  }
  let md = `# Banco de provas do agente do app — ${new Date().toISOString()}\n\n`;
  for (const r of resultados) {
    md += `## ${r.area} · ${r.id}\n\n_Esperado:_ ${r.espera}\n\n`;
    if (r.erro) { md += `**ERRO:** ${r.erro}\n\n`; continue; }
    for (const t of r.turnos) {
      md += `**Pessoa:** ${t.fala}\n\n**App** _(rota ${t.rota ?? '—'}, ${(t.ms / 1000).toFixed(1)} s, HTTP ${t.status})_: ${String(t.resposta).replace(/\n/g, '  \n')}\n\n`;
    }
  }
  const conversas = resultados.flatMap((r) => (r.turnos || []).map((t) => t.conversa)).filter(Boolean);
  md += `---\nConversas de teste (para limpeza): ${[...new Set(conversas)].join(', ')}\n`;
  writeFileSync(saida, md);
  process.stderr.write(`ok: ${saida}\n`);
}

if (import.meta.url === `file://${process.argv[1]}`) main();
