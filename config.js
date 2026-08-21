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
   Opcional por definição. Fica nula até o app do evento dizer quem
   abriu a página; sem identidade o agente cumprimenta sem nome —
   ele nunca chuta um.

   Quem usa isto é o chat clássico, `/classic.html`. A Central do
   Evento (`/`) tem a sua própria leitura de identidade, em
   `agent-dados.js`, com política diferente: lá `?nome` e `?email` só
   valem em `?preview=1`. As duas conviverem é decisão pendente, não
   descuido — está anotada no README.

   Como a identidade chega, em ordem de precedência:

   1. Query string — o app do evento embeda a página com o e-mail de
      quem está logado no dispositivo:
        https://…/?email=fulana@empresa.com&nome=Fulana
      `email` (ou `user_email`) identifica; `nome` (ou `name`) é
      opcional e serve só para a saudação. Os parâmetros são removidos
      da barra de endereço assim que lidos, para o e-mail não vazar em
      print, histórico ou link compartilhado.
   2. postMessage — para o app mandar depois do load:
        postMessage({ tipo: 'mindagent:identidade',
                      email: 'fulana@empresa.com', nome: 'Fulana' })
   3. localStorage — o que a URL trouxe fica guardado por evento, para
      a identidade sobreviver ao recarregar (a query só vem uma vez).

   IMPORTANTE: isso é identificação, não autenticação — qualquer um
   pode abrir a página com um e-mail alheio na URL. Serve para
   personalizar a experiência e registrar com quem o agente falou;
   nunca para liberar dado sensível. E nada daqui vai para a OpenAI:
   o payload do chat (`shared/CONTRATOS.md`) continua sem identidade.

   Para testar: abra `/classic.html?email=teste@mind.com&nome=Fulana`
   ou chame `definirParticipante({ nome: 'Fulana' })` antes do primeiro
   chat.
*/
export const PARTICIPANTE = {
  nome: null,
  email: null,
};

const CHAVE_PARTICIPANTE = 'mindagent:v1:' + CONFIG.eventSlug + ':participante';

function emailValido(valor) {
  return typeof valor === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(valor.trim());
}

export function definirParticipante(dados) {
  PARTICIPANTE.nome = (dados && typeof dados.nome === 'string' && dados.nome.trim())
    ? dados.nome.trim()
    : null;
  PARTICIPANTE.email = (dados && emailValido(dados.email))
    ? dados.email.trim().toLowerCase()
    : null;
  try {
    if (PARTICIPANTE.nome || PARTICIPANTE.email) {
      localStorage.setItem(CHAVE_PARTICIPANTE, JSON.stringify(PARTICIPANTE));
    } else {
      localStorage.removeItem(CHAVE_PARTICIPANTE);
    }
  } catch { /* sem storage (aba privada), a identidade vive só nesta carga */ }
  return PARTICIPANTE;
}

/* Lê a identidade: a URL manda; sem URL, vale o que ficou guardado.

   NÃO roda no import, e isso é deliberado. A Central do Evento
   (`app.js` → `agent-dados.js`) tem a sua própria leitura de `?nome` e
   `?email`, e só confia neles em `?preview=1`. Se a captura fosse efeito
   de import, ela rodaria na home também — pela cadeia `app.js →
   chat-service.js → config.js` — e apagaria os parâmetros da URL antes
   de a home os ler. Quem quer identidade chama. Hoje é só o chat
   clássico (`app-classic.js`). */
export function capturarIdentidade() {
  let daUrl = null;
  try {
    const params = new URLSearchParams(location.search);
    const email = params.get('email') || params.get('user_email');
    const nome = params.get('nome') || params.get('name');
    if (email || nome) {
      daUrl = { email, nome };
      ['email', 'user_email', 'nome', 'name'].forEach((p) => params.delete(p));
      const query = params.toString();
      history.replaceState(history.state, '',
        location.pathname + (query ? '?' + query : '') + location.hash);
    }
  } catch { /* URL ilegível não derruba a página */ }

  if (daUrl) return definirParticipante(daUrl);
  try {
    const guardado = JSON.parse(localStorage.getItem(CHAVE_PARTICIPANTE));
    if (guardado) definirParticipante(guardado);
  } catch { /* storage vazio ou corrompido: segue anônimo */ }
  return PARTICIPANTE;
}
