/* ============================================================
   CONFIGURAÇÃO CENTRAL
   ============================================================
   O único lugar do frontend que sabe de onde vêm os dados e quem
   está usando a página. Nada aqui é segredo: chave de Supabase,
   URL de Edge Function e credencial não moram no cliente — quando
   o `mindagent-bootstrap` entrar no ar, o frontend fala com ele,
   e é ele que guarda as chaves.
*/

export const CONFIG = {
  /* Qual evento esta instância atende. Vira parte do caminho da API
     (`/eventos/mind-summit-2026/summit`) quando houver API. */
  eventSlug: 'mind-summit-2026',

  /* Raiz da API do mindagent-bootstrap. `null` enquanto não existe:
     é o que mantém a página no arquivo local, sem tentar rede à toa. */
  apiBaseUrl: null,

  /* Permite cair no `dados/summit.json` do repositório. Hoje é a única
     origem; depois vira a rede de segurança de quando a API não responde.
     Desligar os dois deixa a página sem fonte — e ela diz isso na tela,
     em vez de inventar conteúdo. */
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
