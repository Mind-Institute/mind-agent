export type RotaVenda = "summit_b2c" | "summit_b2b";

function normalizar(texto: string): string {
  return texto.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
}

const SUPORTE_OU_OUTRO_PRODUTO = /\b(mind institute|mind dash|ja comprei|meu ingresso nao|reembolso|cancelamento|erro (no|de) pagamento|pagamento (nao|duplicado)|nao consigo acessar)\b/;
const PATROCINIO = /\b(patrocinio|patrocinar|patrocinador)\b/;
const COMPRA_SINGULAR = /\b(compra individual|ingresso individual|(so|apenas|somente) (um|1) ingresso|um unico ingresso|meu unico ingresso|o meu ingresso|meu ingresso|(so|apenas|somente) para mim|(so|apenas|somente) (um|1) para mim)\b/;
const DESTINO_PESSOAL = /\b(para mim|pra mim|para (meu|minha|meus|minhas) (marido|esposa|companheiro|companheira|familia|amigo|amiga|amigos|amigas|filho|filha|filhos|filhas))\b/;
const DESTINO_CORPORATIVO = /\b(compra corporativa|para (a|minha|nossa) empresa|pela empresa|empresa (vai|ira|quer|pretende|precisa) (pagar|comprar|levar|enviar)|levar (a|minha|nossa) equipe|levar (o|meu|nosso) time|enviar (a|minha|nossa) equipe|enviar (o|meu|nosso) time|para (a|minha|nossa) equipe|para (o|meu|nosso) time|delegacao corporativa|delegacao da empresa|(colaboradores?|funcionarios?|gestores?|lideres?|diretores?|executivos?) da empresa|em nome da empresa|no cnpj)\b/;
const QUANTIDADE_MULTIPLA = /\b(([2-9]|[1-9][0-9]+)|dois|duas|tres|quatro|cinco|seis|sete|oito|nove|dez|onze|doze|treze|catorze|quatorze|quinze|dezesseis|dezessete|dezoito|dezenove|vinte)\s*(ingressos?|pessoas?|participantes?|vagas?|colaboradores?|funcionarios?|gestores?|lideres?|diretores?|executivos?)\b|\b(varios|varias|multiplos|multiplas|diversos|diversas|mais de um|mais de uma)\s*(ingressos?|pessoas?|participantes?|vagas?|colaboradores?|funcionarios?|gestores?|lideres?|diretores?|executivos?)\b/;
const COLETIVO_CORPORATIVO = /\b(levar|enviar|inscrever|convidar)\s+(a |minha |nossa |o |meu |nosso )?(equipe|time|delegacao|colaboradores|funcionarios)\b/;
const COLETIVO_COMO_DESTINO = /\b(para|pela)\s+(a |o |minha |nossa |meu |nosso |meus |nossos |as |os )?(equipe|time|delegacao|colaboradores|funcionarios|gestores|lideres|diretores|executivos)\b/;
const EQUIPE_MENCIONADA = /\b(a|minha|nossa|da|nossa) (equipe|delegacao)|\b(o|meu|nosso|do) time\b/;

// O ATALHO SÓ VALE QUANDO O TURNO É DE INGRESSO DO SUMMIT.
//
// Esta função nasceu como otimização de latência em 04/09/2026
// (INCIDENTE_TREBLE_20260904.md), sob uma premissa escrita com todas as letras: "o
// canal é predominantemente comercial B2C". O Router custava mediana de 6,7 s e
// falhava em 5 de 15 turnos, então evitá-lo na maioria dos turnos era ganho real.
//
// A PREMISSA MORREU EM 24/09/2026. O Summit encerrou, saiu de venda, e
// `agentes.canal_competencia` passou a servir `institute`, `dash` e
// `cliente_suporte` no WhatsApp. O que sobrou foi um atalho cujo último `return` era
// incondicional:
//
//     return { rota: "summit_b2c", motivo: "b2c_padrao_comercial" };
//
// Ou seja: toda mensagem que não casasse com a lista de suporte virava `summit_b2c`
// SEM CHAMAR O ROUTER. "Quais ferramentas vocês têm para trabalhar isso?" era
// classificada como compra de ingresso do Summit. Hoje isso termina em
// transferência, porque o Gate fecha a rota — o que esconde o defeito em vez de
// evitá-lo. Com `institute`/`dash` executáveis, esconder deixa de funcionar: o
// atalho sequestraria o turno antes de o Router poder escolher a rota certa, e a
// pessoa receberia Summit ao perguntar de formação.
//
// A REGRA AGORA: o atalho é uma otimização para turnos que JÁ SE DECLARARAM de
// ingresso do Summit. Sem essa declaração, ele não opina — devolve `null` e o Router
// decide, que é o caminho canônico. Dentro dos turnos de ingresso, a discriminação
// B2B/B2C da v1.10.2 continua intacta, palavra por palavra: é contrato de outra
// decisão e não se reabre aqui.
//
// O CUSTO, dito com todas as letras: mais turnos passam pelo Router, e o Router é o
// caminho lento. É o preço de responder a pergunta certa. Latência se melhora no
// Router; rota errada não se melhora depois.
const INGRESSO_OU_SUMMIT =
  /\b(ingressos?|summit|lote \d|credencial|credenciamento|inscricao no summit|(mind|vip|prime)\b.*\bingresso|ingresso.*\b(mind|vip|prime)\b)\b/;

export function rotaComercialRapida(
  mensagem: string,
  historicoValue: unknown,
): { rota: RotaVenda | null; motivo: string } {
  const atual = normalizar(mensagem);
  const historico = Array.isArray(historicoValue)
    ? historicoValue
      .filter((m: Record<string, unknown>) => m?.papel === "lead" && typeof m?.conteudo === "string")
      .slice(-8)
      .map((m: Record<string, unknown>) => String(m.conteudo))
      .join(" ")
    : "";
  const contexto = normalizar(`${historico} ${mensagem}`);

  // Suporte e outras soluções têm precedência sobre qualquer sinal comercial.
  if (SUPORTE_OU_OUTRO_PRODUTO.test(atual)) {
    return { rota: null, motivo: "router_necessario" };
  }

  // Sem menção a ingresso/Summit no turno nem no histórico recente, este atalho não
  // tem o que otimizar: quem decide é o Router. `patrocínio` é a exceção, porque é
  // demanda corporativa própria que nomeia o Summit por contexto e já era tratada
  // como rota sem depender da palavra "ingresso".
  if (!INGRESSO_OU_SUMMIT.test(normalizar(`${mensagem}`)) && !PATROCINIO.test(atual)) {
    const historicoBruto = Array.isArray(historicoValue)
      ? historicoValue
        .filter((m: Record<string, unknown>) => m?.papel === "lead" && typeof m?.conteudo === "string")
        .slice(-8)
        .map((m: Record<string, unknown>) => String(m.conteudo))
        .join(" ")
      : "";
    if (!INGRESSO_OU_SUMMIT.test(normalizar(historicoBruto))) {
      return { rota: null, motivo: "router_sem_sinal_de_ingresso" };
    }
  }

  const multiploAtual = QUANTIDADE_MULTIPLA.test(atual) ||
    COLETIVO_CORPORATIVO.test(atual) ||
    COLETIVO_COMO_DESTINO.test(atual);
  const corporativoAtual = DESTINO_CORPORATIVO.test(atual) ||
    COLETIVO_CORPORATIVO.test(atual) ||
    COLETIVO_COMO_DESTINO.test(atual) ||
    (multiploAtual && EQUIPE_MENCIONADA.test(atual));
  const singularAtual = COMPRA_SINGULAR.test(atual) ||
    /\b(nao (e|seria) (uma )?compra corporativa|para eu ir|pra eu ir)\b/.test(atual);
  const pessoalAtual = DESTINO_PESSOAL.test(atual);

  // Patrocínio é uma demanda corporativa própria, não uma compra de ingresso B2C.
  if (PATROCINIO.test(atual)) {
    return { rota: "summit_b2b", motivo: "b2b_patrocinio" };
  }

  // Para ingressos, B2B exige os dois sinais no mesmo objeto comercial:
  // destino empresa/equipe E mais de uma pessoa. Quantidade ou empresa isoladas não bastam.
  if (corporativoAtual && multiploAtual) {
    return { rota: "summit_b2b", motivo: "b2b_empresa_multiplos" };
  }

  // A necessidade explícita deste turno vence sinais corporativos antigos.
  if (singularAtual || (pessoalAtual && !corporativoAtual)) {
    return { rota: "summit_b2c", motivo: "b2c_explicito" };
  }

  const corporativoNoContexto = DESTINO_CORPORATIVO.test(contexto) ||
    COLETIVO_CORPORATIVO.test(contexto) ||
    COLETIVO_COMO_DESTINO.test(contexto);
  const multiploNoContexto = QUANTIDADE_MULTIPLA.test(contexto) ||
    COLETIVO_CORPORATIVO.test(contexto) ||
    COLETIVO_COMO_DESTINO.test(contexto);

  if (PATROCINIO.test(contexto)) {
    return { rota: "summit_b2b", motivo: "b2b_patrocinio" };
  }

  if (corporativoNoContexto && multiploNoContexto) {
    return { rota: "summit_b2b", motivo: "b2b_empresa_multiplos" };
  }

  if (corporativoNoContexto) {
    return { rota: null, motivo: "router_quantidade_corporativa" };
  }

  // Turno de ingresso sem sinal corporativo é B2C — esta é a parte do atalho que
  // continua valendo, e só se chega aqui tendo passado pela porta de ingresso/Summit
  // lá em cima. O antigo `b2c_padrao_comercial` cobria o canal inteiro; este cobre
  // apenas quem falou de ingresso.
  return { rota: "summit_b2c", motivo: "b2c_ingresso_sem_sinal_corporativo" };
}
