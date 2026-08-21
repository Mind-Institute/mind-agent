/* ============================================================
   CONFIGURAÇÃO CENTRAL
   ============================================================
   O único lugar do frontend que sabe de onde vêm os dados e quem
   está usando a página. A URL do bootstrap é pública e abre sem
   autenticação — nenhuma chave, `anon key` ou credencial mora aqui.
   Quem guarda segredo é o `mindagent-bootstrap`, do lado do servidor.
*/

export const CONFIG = {
  /* Qual evento esta instância atende. Vira parte do caminho da API
     (`/eventos/mind-summit-2026/summit`) quando houver API. */
  eventSlug: 'mind-summit-2026',

  /* Raiz da API do mindagent-bootstrap — a origem oficial dos dados.
     Nula volta a página para o arquivo local. */
  apiBaseUrl: 'https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/mindagent-bootstrap',

  /* Rede de segurança: se a API não responder, a página cai no
     `dados/summit.json` do repositório — conteúdo mais antigo, mas
     conteúdo real. Desligar as duas origens deixa a página sem fonte, e
     ela diz isso na tela em vez de inventar. */
  useLocalFallback: true,
};

/* ============================================================
   IDENTIDADE DO PARTICIPANTE
   ============================================================
   Opcional por definição. Fica nula até a Yazo (ou o bootstrap)
   dizer quem abriu a página; sem identidade o agente cumprimenta
   sem nome — ele nunca chuta um.

   Para testar com identidade, preencha `nome` aqui ou chame
   `definirParticipante({ nome: 'Fulana' })` antes do primeiro chat.
*/
export const PARTICIPANTE = {
  nome: null,
};

export function definirParticipante(dados) {
  PARTICIPANTE.nome = (dados && typeof dados.nome === 'string' && dados.nome.trim())
    ? dados.nome.trim()
    : null;
  return PARTICIPANTE;
}
