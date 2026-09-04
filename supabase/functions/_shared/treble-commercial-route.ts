export type RotaVenda = "summit_b2c" | "summit_b2b";

function normalizar(texto: string): string {
  return texto.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
}

const SUPORTE_OU_OUTRO_PRODUTO = /\b(mind institute|mind dash|ja comprei|meu ingresso nao|reembolso|cancelamento|erro (no|de) pagamento|pagamento (nao|duplicado)|nao consigo acessar)\b/;
const PATROCINIO = /\b(patrocinio|patrocinar|patrocinador)\b/;
const COMPRA_SINGULAR = /\b(compra individual|ingresso individual|(so|apenas|somente) (um|1) ingresso|um unico ingresso|meu unico ingresso|o meu ingresso|meu ingresso|(so|apenas|somente) para mim|(so|apenas|somente) (um|1) para mim)\b/;
const DESTINO_PESSOAL = /\b(para mim|pra mim|para (meu|minha|meus|minhas) (marido|esposa|companheiro|companheira|familia|amigo|amiga|amigos|amigas|filho|filha|filhos|filhas))\b/;
const DESTINO_CORPORATIVO = /\b(compra corporativa|para (a|minha|nossa) empresa|pela empresa|empresa (vai|ira|quer|pretende|precisa) (pagar|comprar|levar|enviar)|levar (a|minha|nossa) equipe|levar (o|meu|nosso) time|enviar (a|minha|nossa) equipe|enviar (o|meu|nosso) time|para (a|minha|nossa) equipe|para (o|meu|nosso) time|delegacao corporativa|delegacao da empresa|colaboradores? da empresa|funcionarios? da empresa|em nome da empresa|no cnpj)\b/;
const QUANTIDADE_MULTIPLA = /\b(([2-9]|[1-9][0-9]+)|dois|duas|tres|quatro|cinco|seis|sete|oito|nove|dez|onze|doze|treze|catorze|quatorze|quinze|dezesseis|dezessete|dezoito|dezenove|vinte)\s*(ingressos?|pessoas?|participantes?|vagas?)\b|\b(varios|varias|multiplos|multiplas|diversos|diversas|mais de um|mais de uma)\s*(ingressos?|pessoas?|participantes?|vagas?)\b/;
const COLETIVO_CORPORATIVO = /\b(levar|enviar|inscrever|convidar)\s+(a |minha |nossa |o |meu |nosso )?(equipe|time|delegacao|colaboradores|funcionarios)\b/;
const EQUIPE_MENCIONADA = /\b(a|minha|nossa|da|nossa) (equipe|delegacao)|\b(o|meu|nosso|do) time\b/;

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

  const multiploAtual = QUANTIDADE_MULTIPLA.test(atual) || COLETIVO_CORPORATIVO.test(atual);
  const corporativoAtual = DESTINO_CORPORATIVO.test(atual) ||
    COLETIVO_CORPORATIVO.test(atual) ||
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
    COLETIVO_CORPORATIVO.test(contexto);
  const multiploNoContexto = QUANTIDADE_MULTIPLA.test(contexto) ||
    COLETIVO_CORPORATIVO.test(contexto);

  if (PATROCINIO.test(contexto)) {
    return { rota: "summit_b2b", motivo: "b2b_patrocinio" };
  }

  if (corporativoNoContexto && multiploNoContexto) {
    return { rota: "summit_b2b", motivo: "b2b_empresa_multiplos" };
  }

  if (corporativoNoContexto) {
    return { rota: null, motivo: "router_quantidade_corporativa" };
  }

  return { rota: "summit_b2c", motivo: "b2c_padrao_comercial" };
}
