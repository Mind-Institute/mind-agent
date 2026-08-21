/* ============================================================
   CONFIGURAÇÃO CENTRAL
   ============================================================
   O único lugar do frontend que sabe de onde vêm os dados e quem
   está usando a página. Só entra aqui o que é público por definição:
   a URL do bootstrap (abre sem autenticação) e a publishable key do
   Supabase, feita para viver no cliente.

   O que NUNCA entra: `service_role`, secret key, `OPENAI_API_KEY`.
   Essas ficam do lado do servidor — nas Edge Functions. Quem fala com
   a OpenAI é a `mindagent-chat`, nunca o navegador.
*/

export const CONFIG = {
  /* Qual evento esta instância atende. Vira parte do caminho da API
     (`/eventos/mind-summit-2026/summit`) quando houver API. */
  eventSlug: 'mind-summit-2026',

  /* Raiz da API do mindagent-bootstrap — a origem oficial dos dados.
     Nula volta a página para o arquivo local. */
  apiBaseUrl: 'https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/mindagent-bootstrap',

  /* O projeto Supabase e a chave pública — usados pelo `chat-service.js`
     para abrir a sessão anônima (Auth) e chamar a função do chat. */
  supabaseUrl: 'https://ymnmotgglsrxmjmonwjz.supabase.co',
  supabasePublishableKey: 'sb_publishable__wYRbYyBgK_MBfqmLpiZNg_Z8iJNxvc',

  /* A Edge Function que conversa com a OpenAI. É ela que mascara e-mail e
     telefone, monta o contexto público e grava mensagens e interesses. */
  chatFunction: 'mindagent-chat',

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
