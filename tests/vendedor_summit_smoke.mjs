#!/usr/bin/env node
// Smoke test do Vendedor Summit no runtime real do Treble.
//
// Bate no `treble-inbound-agent` com o MESMO payload que a Treble envia e imprime, por
// caso, o que voltou no contrato público: `resposta_ia`, `needs_human`, `audience`,
// `intent`, `checkout_sent`, o `request_id` e o TEMPO de cada turno.
//
// NÃO é suíte de regressão e não substitui leitura humana. Ele prova o encanamento —
// turno responde, rota executa, handoff acende, guardrail dispara — e deixa a resposta
// na tela para alguém julgar se o fato está certo e o tom está certo. O critério do
// go-live ("factual correto, tom adequado, sem invenção") é de gente, não de assert.
//
// ============================================================================
// HTTP 200 NÃO É O CRITÉRIO. ENTREGA NO WHATSAPP É.
//
// O caminho canônico soma uma ida ao modelo (Router) antes da ida do Agent. Produção
// tem `treble_agent_config.timeout_ms = 20000` e o Router pode gastar até
// `router_timeout_ms` (6000 por padrão) antes disso. Já existe evidência histórica de
// um turno de ~5,96 s que a Treble NÃO emitiu, contra um de ~4,43 s que chegou
// (§8/§10 do Core, Passo 6B).
//
// Portanto: este script mede a latência da Edge e mostra `router_ms` no log, mas isso é
// DIAGNÓSTICO. A Definition of Done do ciclo E2E é a mensagem chegar no WhatsApp de um
// número real. Um caso com `ok:true`, resposta bonita e 9 s de latência que não aparece
// no aparelho é uma FALHA, e o desfecho correto é devolver
// `treble.config.core_rota_kit` para off — não seguir para o próximo passo.
//
// O script não consegue provar entrega sozinho: quem confirma é quem está com o
// telefone. Por isso ele imprime, no fim, a checagem que precisa ser feita por fora.
// ============================================================================
//
// ELE ESCREVE DADO REAL. Cada caso abre uma conversa de verdade em `engagement` e gasta
// chamada de modelo. As sessões nascem com o prefixo `smoke-laneb-<carimbo>` justamente
// para serem reconhecíveis depois — o rodapé imprime o SQL que lista o que este run
// criou, com a rota que cada turno realmente executou.
//
// ============================================================================
// O TELEFONE É OBRIGATÓRIO, E TEM DE SER UM WHATSAPP CONTROLADO PARA TESTE.
//
// Não há número padrão aqui, de propósito. Até esta versão o script mandava
// `+5511999990000` fixo — um número que PARECE de teste e não é: em produção, os dez
// últimos dígitos dele (que é exatamente como `mind_crm_vincular_pessoa` casa telefone)
// já correspondem a 1 contato em `crm.contato_espelho`, 1 identidade `whatsapp` e
// 1 pessoa reais.
//
// O caminho `treble_agent_start → mind_inbound → mind_identidade_resolver` cria e
// vincula pessoa e identidade, e o vínculo com o CRM vem junto. Rodar o smoke com um
// número de outra pessoa gruda conversa de teste na ficha dela.
//
// IDENTIDADE É PERSISTENTE E NÃO É LIMPA AUTOMATICAMENTE. A limpeza no rodapé apaga
// somente mensagens e conversas. Pessoa, identidade e vínculo de CRM NÃO são apagados —
// e isso é deliberado: quando o número já existir de propósito (o WhatsApp de teste de
// alguém do time), apagar a pessoa seria destruir dado legítimo, não faxina.
//
// Use um número que você controla e sobre o qual pode responder. Se ele já tiver pessoa
// no Mind, ela vai ganhar as conversas do smoke — e isso é aceitável justamente porque
// a pessoa é sua.
// ============================================================================
//
//   TREBLE_WEBHOOK_TOKEN=...  \
//   TREBLE_AGENT_URL=https://<ref>.supabase.co/functions/v1/treble-inbound-agent \
//   TREBLE_SMOKE_CELLPHONE=+55DDDNNNNNNNN  \
//   TREBLE_SMOKE_NAME="Smoke Lane B"        # opcional
//   node tests/vendedor_summit_smoke.mjs
//
//   --caso <n>   roda só um caso (1..N)
//   --listar     imprime os casos e sai, sem tocar em nada

const URL_AGENTE = process.env.TREBLE_AGENT_URL ??
  (process.env.SUPABASE_URL ? `${process.env.SUPABASE_URL}/functions/v1/treble-inbound-agent` : "");
const TOKEN = process.env.TREBLE_WEBHOOK_TOKEN ?? "";
const CELULAR = (process.env.TREBLE_SMOKE_CELLPHONE ?? "").trim();
const NOME = (process.env.TREBLE_SMOKE_NAME ?? "Smoke Lane B").trim();

// Um caso é uma conversa. `turnos` são as falas do lead, na ordem — B2B só vira B2B
// depois que a pessoa diz que é para o time, e essa é a parte que interessa testar.
const CASOS = [
  {
    nome: "preço — pergunta seca de valor",
    rota_esperada: "summit_b2c",
    turnos: ["Quanto custa?"],
    espera: { needs_human: false },
    olhar: "Preço do lote vigente, com a moeda e o parcelamento como estão na oferta. Nenhum valor fora do Kit.",
  },
  {
    nome: "diferença de ingresso — Mind × VIP × Prime",
    rota_esperada: "summit_b2c",
    turnos: ["Qual a diferença entre Mind, VIP e Prime?"],
    espera: { needs_human: false },
    olhar: "Diferenças vindas do bloco `inclusoes`. Workshops VIP, masterclasses e lounge no Prime, credenciamento — sem inventar benefício.",
  },
  {
    nome: "objeção de valor — 'o Prime vale a pena?'",
    rota_esperada: "summit_b2c",
    turnos: ["O Prime vale a pena? É bem mais caro que o Mind."],
    espera: { needs_human: false },
    olhar: "Trabalha a objeção com inclusão real e preço real. Não promete o que não está no Kit.",
  },
  {
    nome: "regra comercial — pedido de desconto",
    rota_esperada: "summit_b2c",
    turnos: ["Tem desconto?"],
    espera: { needs_human: false },
    olhar: "GATE SENSÍVEL: com `regras_comerciais` no Kit o agente passa a poder conduzir desconto individual. Conferir se respeitou `desconto_espontaneo`/`mencionar_cupom_nao_solicitado` e se NÃO revelou a escada D1–D4.",
  },
  {
    nome: "volume B2B — 5 ingressos",
    rota_esperada: "summit_b2b",
    turnos: ["Quero 5 ingressos para a minha equipe"],
    espera: { needs_human: false },
    olhar: "Tier de 5–9 (10% off) com o valor por ingresso do bloco `precos_por_volume`. Não pode transferir só por ser grupo.",
  },
  {
    nome: "volume B2B — 15 ingressos e valor por pessoa",
    rota_esperada: "summit_b2b",
    turnos: ["Quero levar meu time", "Somos 15 pessoas. Quanto fica por pessoa?"],
    espera: { needs_human: false },
    olhar: "Tier de +15 (30% off). O valor por pessoa tem de bater com `valor_por_ingresso_com_desconto`. Conta total, se aparecer, é múltiplo exato do unitário.",
  },
  {
    nome: "programação como apoio à decisão",
    rota_esperada: "summit_b2c",
    turnos: ["Vale a pena? Quem vai palestrar sobre burnout?"],
    espera: { needs_human: false },
    olhar: "Usa AGENDA_E_PALESTRANTES para sustentar a decisão de compra. Palestrante/sessão que não existir na base não pode aparecer.",
  },
  {
    nome: "handoff — pedido explícito de humano",
    rota_esperada: "summit_b2c | cliente_suporte",
    turnos: ["Quero falar com uma pessoa de verdade, por favor"],
    espera: { needs_human: true },
    olhar: "needs_human=true. Antes de transferir, recolhe o que falta — sem prender a pessoa numa pergunta.",
  },
  {
    nome: "dado ausente — pergunta que o Kit não resolve",
    rota_esperada: "summit_b2c | concierge_summit",
    turnos: ["Tem estacionamento coberto e quanto custa a diária no dia do evento?"],
    espera: {},
    olhar: "Admite a lacuna ou confirma com o time. NÃO pode inventar valor de estacionamento. Se inventar preço, o guardrail devolve `guarded:true`.",
  },
  {
    nome: "desinteresse — encerrar sem insistir",
    rota_esperada: "summit_b2c",
    turnos: ["Não quero mais, obrigado"],
    espera: {},
    olhar: "Encerra com respeito. `insistencia_apos_desinteresse` permite no máximo uma retomada — não pode virar insistência.",
  },
];

function argv(flag) {
  const i = process.argv.indexOf(flag);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

function chave(keys, nome) {
  const hit = (keys ?? []).find((k) => k?.key === nome);
  return hit ? String(hit.value) : null;
}

async function turno(sessionId, texto) {
  const comecou = Date.now();
  const resposta = await fetch(`${URL_AGENTE}?token=${encodeURIComponent(TOKEN)}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      session_external_id: sessionId,
      mensagem: texto,
      cellphone: CELULAR,
      name: NOME,
      message_id: `${sessionId}-${Date.now()}`,
    }),
  });
  const corpo = await resposta.json().catch(() => ({}));
  return { status: resposta.status, corpo, ms: Date.now() - comecou };
}

async function main() {
  if (process.argv.includes("--listar")) {
    CASOS.forEach((c, i) => console.log(`${String(i + 1).padStart(2)}. ${c.nome}  [${c.rota_esperada}]`));
    return 0;
  }
  if (!URL_AGENTE || !TOKEN) {
    console.error("Faltam TREBLE_AGENT_URL (ou SUPABASE_URL) e TREBLE_WEBHOOK_TOKEN.");
    return 2;
  }
  // Antes de qualquer requisição: sem telefone declarado, o script não roda. Um default
  // aqui viraria conversa de teste grudada na pessoa de outra gente.
  if (!/^\+?\d{10,15}$/.test(CELULAR.replace(/[\s()-]/g, ""))) {
    console.error(
      "TREBLE_SMOKE_CELLPHONE é obrigatório e precisa ser um telefone em formato internacional.\n" +
      "\n" +
      "Use um WhatsApp CONTROLADO PARA TESTE. O smoke cria e vincula pessoa e identidade\n" +
      "pelo caminho de ingestão, e o vínculo com o CRM vem junto — a limpeza do rodapé\n" +
      "apaga só mensagens e conversas, nunca pessoa, identidade ou CRM.\n" +
      "\n" +
      "  TREBLE_SMOKE_CELLPHONE=+5511987654321 node tests/vendedor_summit_smoke.mjs\n",
    );
    return 2;
  }

  const so = argv("--caso") ? Number(argv("--caso")) : null;
  const tempos = [];
  const carimbo = new Date().toISOString().replace(/[-:T]/g, "").slice(0, 14);
  const prefixo = `smoke-laneb-${carimbo}`;
  const falhas = [];

  const mascarado = CELULAR.replace(/\d(?=\d{4})/g, "•");
  console.log(`\nVendedor Summit — smoke\nagente:   ${URL_AGENTE}\nsessões:  ${prefixo}-*` +
    `\ntelefone: ${mascarado} (${NOME}) — pessoa e identidade NÃO são apagadas depois\n`);

  for (const [i, caso] of CASOS.entries()) {
    const n = i + 1;
    if (so && so !== n) continue;
    const sessionId = `${prefixo}-${String(n).padStart(2, "0")}`;
    console.log(`\n${"─".repeat(78)}\n${n}. ${caso.nome}   [rota esperada: ${caso.rota_esperada}]`);

    let ultimo = null;
    for (const texto of caso.turnos) {
      console.log(`   lead → ${texto}`);
      ultimo = await turno(sessionId, texto);
      tempos.push(ultimo.ms);
      const keys = ultimo.corpo?.user_session_keys;
      console.log(`   agente (${(ultimo.ms / 1000).toFixed(2)}s) → ${chave(keys, "resposta_ia") ?? "(sem resposta_ia)"}`);
    }

    const keys = ultimo?.corpo?.user_session_keys;
    const needsHuman = chave(keys, "needs_human");
    console.log(`   · http=${ultimo?.status} ok=${ultimo?.corpo?.ok} guarded=${ultimo?.corpo?.guarded ?? false}` +
      ` needs_human=${needsHuman} audience=${chave(keys, "audience")}` +
      ` intent=${chave(keys, "intent")} checkout_sent=${chave(keys, "checkout_sent")}`);
    console.log(`   · request_id=${ultimo?.corpo?.request_id ?? "—"}   sessão=${sessionId}`);
    console.log(`   · olhar: ${caso.olhar}`);

    // Asserções só do que é estrutural. Conteúdo é leitura humana, de propósito.
    const erros = [];
    if (ultimo?.status !== 200) erros.push(`http ${ultimo?.status}`);
    if (ultimo?.corpo?.ok !== true) erros.push(`ok=${ultimo?.corpo?.ok}`);
    if (!chave(keys, "resposta_ia")) erros.push("sem resposta_ia no payload");
    if (needsHuman === null) erros.push("sem needs_human no payload");
    if (caso.espera.needs_human === true && needsHuman !== "true") erros.push("needs_human deveria ser true");
    if (caso.espera.needs_human === false && needsHuman === "true") {
      console.log("   ! needs_human=true onde não se esperava — ver se foi o Gate fechando a rota");
    }
    if (erros.length) {
      falhas.push(`${n}. ${caso.nome}: ${erros.join(" · ")}`);
      console.log(`   ✗ ${erros.join(" · ")}`);
    } else {
      console.log("   ✓ contrato de saída íntegro");
    }
  }

  console.log(`\n${"═".repeat(78)}`);
  if (falhas.length) {
    console.log(`${falhas.length} caso(s) com contrato quebrado:`);
    falhas.forEach((f) => console.log(`  ✗ ${f}`));
  } else {
    console.log("Contrato de saída íntegro em todos os casos rodados.");
  }

  if (tempos.length) {
    const ordenados = [...tempos].sort((a, b) => a - b);
    const p50 = ordenados[Math.floor(ordenados.length * 0.5)];
    const p95 = ordenados[Math.min(ordenados.length - 1, Math.floor(ordenados.length * 0.95))];
    const pior = ordenados[ordenados.length - 1];
    const seg = (ms) => `${(ms / 1000).toFixed(2)}s`;
    console.log(`\nLatência da Edge em ${tempos.length} turnos: ` +
      `p50 ${seg(p50)} · p95 ${seg(p95)} · pior ${seg(pior)}`);
    if (pior >= 5960) {
      console.log("  ⚠️  Pior turno igual ou acima dos ~5,96 s do turno que a Treble NÃO emitiu.");
    }
  }

  console.log(`
${"═".repeat(78)}
DEFINITION OF DONE — o que este script NÃO prova

Tudo acima é HTTP da Edge. O ciclo E2E só fecha quando a mensagem CHEGA no WhatsApp de
um número real. Latência aqui é diagnóstico; entrega é o critério.

  [ ] cada resposta apareceu no aparelho, e não só no \`resposta_ia\` do JSON
  [ ] nenhum turno silencioso — resposta que a Edge devolveu e a Treble não emitiu
  [ ] \`router_ms\` nos logs da function é compatível com a entrega observada
  [ ] leitura humana: fato correto, tom certo, sem invenção, rota certa, handoff certo

Se algum turno não chegar, o caminho canônico NÃO está pronto:

  update treble.config set valor = 'false' where chave = 'core_rota_kit';

Isso volta o runtime ao comportamento da v1.3.0 sem redeploy. Não seguir adiante com
turno que não entrega.
`);

  console.log(`
Rota realmente executada em cada turno (a rota não sai no payload público do Treble —
ela fica no turno, em engagement.mensagens.blocos):

  select c.session_external_id,
         m.criado_em,
         m.blocos->>'rota'               as rota_decidida,
         m.blocos->>'rota_aplicada'      as rota_aplicada,
         m.blocos->>'precisa_esclarecer' as precisa_esclarecer,
         m.blocos->'candidatas'          as candidatas,
         m.blocos->>'gate_reason'        as gate_reason,
         m.blocos->>'rota_falha'         as rota_falha,
         m.blocos->>'router_ms'          as router_ms,
         left(m.conteudo, 80)            as resposta
    from engagement.mensagens m
    join engagement.conversas c on c.id = m.conversa_id
   where c.session_external_id like '${prefixo}-%'
     and m.papel = 'agente'
   order by c.session_external_id, m.criado_em;

REGRESSÃO DA CHAMADA REMOVIDA. A v1.4.0 tirou o \`mind_lead_capturar\`, que nunca
executou (função inexistente, erro engolido). Nada devia se perder: todo campo que ela
carregava já tem casa canônica no mesmo turno. Esta consulta prova campo a campo —
nenhuma coluna pode vir vazia num caso que teve turno de agente:

  select c.session_external_id,
         c.participante_id     is not null as pessoa,
         c.session_external_id is not null as referencia,
         c.agente              is not null as agente,
         c.produto_codigo      is not null as produto,
         c.audience            is not null as audience,
         c.stage               is not null as stage,
         c.variables ? 'intent'            as intent,
         c.variables ? 'needs_human'       as needs_human,
         c.variables ? 'checkout_sent'     as checkout_sent,
         exists (select 1 from engagement.mensagens m
                  where m.conversa_id = c.id and m.papel = 'agente'
                    and m.blocos ? 'rota')                 as rota_no_turno
    from engagement.conversas c
   where c.session_external_id like '${prefixo}-%'
   order by c.session_external_id;

  -- \`ticket_interest\`, \`objection\` e \`desfecho\` são nulos por natureza quando não se
  -- aplicam ao caso; \`origem_codigo\` e \`utm\` vêm vazios do Treble e já vinham antes.

Para apagar as fixtures deste run, depois de conferir:

  delete from engagement.mensagens
   where conversa_id in (select id from engagement.conversas
                          where session_external_id like '${prefixo}-%');
  delete from engagement.conversas where session_external_id like '${prefixo}-%';

O QUE ISSO NÃO APAGA, DE PROPÓSITO: pessoa, identidade e vínculo de CRM. A ingestão cria
e vincula identidade pelo telefone, e esse é dado permanente — apagar automaticamente
seria destruir a ficha de alguém quando o número já existir por um motivo legítimo, que é
justamente o caso do WhatsApp de teste de quem rodou. Se precisar desfazer um vínculo,
faça à mão, olhando o que existia antes.
`);
  return falhas.length ? 1 : 0;
}

main().then((c) => process.exit(c)).catch((e) => {
  console.error(e);
  process.exit(2);
});
