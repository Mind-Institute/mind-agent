# Mind Agent — Mind Summit 2026

Frontend do **Mind Agent**, o concierge do Mind Summit 2026 (16 e 17 de setembro
de 2026, São Paulo Expo). Site estático **mobile-first**, sem build e sem
dependências: uma página que abre em qualquer navegador ou por QR code.

Veio da pasta `mindagent/` do repositório `Mind-Institute/mindsummit2026`, onde
existia só na branch de preview. Aqui é o projeto — separado do mapa do evento.

Estado atual: **IA conectada.** A programação vem do `mindagent-bootstrap`
(10 temas, 67 sessões, 44 palestrantes) com `dados/summit.json` como fallback, e
o chat responde de verdade pela Edge Function `mindagent-chat`, que fala com a
OpenAI. As respostas simuladas foram removidas. A identidade chega pela Yazo
na URL (ver “Identidade via Yazo”), e o deploy é automático: cada push na
`main` publica em `mind-agent.adriana-3eb.workers.dev` pelo Workers Builds da
Cloudflare.

O painel de administração vive em `admin/` (Vite + React + TypeScript) e é um
projeto à parte, com o próprio `package.json` e o próprio README.

## Como executar localmente

```bash
npx serve .
```

E abrir <http://localhost:3000>. Precisa ser por servidor local, por dois
motivos: a página busca os dados por `fetch` e o `app.js` é um ES module — em
`file://` os dois são bloqueados pelo navegador.

Qualquer servidor estático serve (`python -m http.server`, `php -S`, extensão
Live Server). O chat não tem passo de build: o que está no repositório é o que
roda.

O painel administrativo é um projeto Vite separado, na porta 5174:

```bash
npm run dev:admin
```

## Deploy — dois produtos, um site

```bash
npm run build
```

Constrói o painel e monta `dist/`, que é o que sobe:

```
dist/            → Mind Agent, o chat público (arquivos da raiz)
dist/admin/      → Painel Admin (build do Vite, base /admin/)
dist/_redirects  → /admin sem barra e deep link do painel
```

`/` abre o chat e `/admin` abre o painel. Cada um tem a sua pasta `assets/`,
em níveis diferentes — não colidem. Para conferir o artefato antes de publicar:

```bash
npm run preview:deploy
```

**Nunca publicar a raiz do repositório.** Os dois `assets/` colidiriam, e
README, `admin/node_modules` e `.env.local` iriam para o ar. A configuração do
Worker está em `wrangler.toml`, apontando para `dist/`.

Os contratos que os dois produtos compartilham estão em
[`shared/CONTRATOS.md`](shared/CONTRATOS.md) — leitura obrigatória antes de
mexer no banco ou nas Edge Functions.

## Estrutura dos arquivos

| Arquivo | O que é |
|---|---|
| `index.html` | Só estrutura: o `<head>`, o markup das quatro vistas (splash, home, chat, Seu Summit, tour) e os popups. Nenhum estilo e nenhuma lógica. |
| `styles.css` | Tokens da marca, as quatro vistas, o tour e os componentes de UI generativa. |
| `app.js` | A aplicação: splash, navegação, motor do tour, chat, perfil vivo e o mapa. ES module — entra por `<script type="module">`. |
| `config.js` | Configuração central e a identidade do participante. O único lugar que sabe de onde vêm os dados e quem está usando. |
| `data-service.js` | A camada de dados (conteúdo do evento). Ninguém mais no frontend chama `fetch` de conteúdo. |
| `chat-service.js` | A camada do chat: sessão anônima do Supabase Auth, JWT guardado e renovado, e a chamada à Edge Function. Ninguém mais no frontend fala com o chat. |
| `dados/summit.json` | Cópia congelada da programação (10 temas, 53 sessões, 39 pessoas). Só é lida se a API não responder (ver abaixo). |
| `assets/tour/` | As 12 capturas de tela do app usadas pelo tour. |
| `assets/palestrantes/` | As 39 fotos referenciadas por `pessoas[].foto`. |
| `assets/` | Símbolo Mind, favicon e a fonte Satoshi (`.woff2`). |
| `admin/` | O painel de administração — projeto Vite/React separado. Ver `admin/README.md`. |

O `index.html` monolítico anterior foi separado sem alterar uma linha de CSS
nem de markup: o `<style>` virou `styles.css` e o `<script>` virou `app.js`,
byte por byte.

## Configuração central

Tudo em `config.js`:

```js
export const CONFIG = {
  eventSlug: 'mind-summit-2026',
  apiBaseUrl: 'https://…/functions/v1/mindagent-bootstrap',  // programação
  useLocalFallback: true,          // cai no dados/summit.json se a API não responder
  supabaseUrl: 'https://ymnmotgglsrxmjmonwjz.supabase.co',
  supabasePublishableKey: 'sb_publishable_…',                 // pública por definição
  chatFunction: 'mindagent-chat',                             // a IA
};
```

Só entra aqui o que é público: a URL do bootstrap (abre sem autenticação) e a
publishable key, feita para viver no cliente. **`service_role`, secret key e
`OPENAI_API_KEY` nunca entram no frontend** — moram nas Edge Functions. Quem
fala com a OpenAI é a `mindagent-chat`, nunca o navegador.

## Chat e privacidade

O chat responde de verdade. O caminho de uma pergunta:

1. O navegador abre uma **sessão anônima** do Supabase Auth e guarda o JWT, o
   refresh token, um `device_id` e a sessão do chat no `localStorage` — assim a
   conversa sobrevive ao recarregar a página. O JWT é renovado quando vence.
2. `chat-service.js` chama `POST /functions/v1/mindagent-chat` com `apikey`,
   `Authorization: Bearer <JWT anônimo>` e um corpo enxuto: `message`,
   `event_slug`, `device_id`, `client_message_id` e `session`. **Nada mais.**
3. A Edge Function busca o contexto oficial, **mascara e-mail e telefone**, e
   manda para a OpenAI apenas a pergunta mascarada e o contexto público, com
   `store: false`.
4. Mensagens e interesses detectados são gravados no Supabase — é o que
   alimenta a experiência do agente e o painel `/admin`.

**Perfil, nome, e-mail identificado, cargo, empresa e histórico da conversa não
são enviados ao modelo.** O frontend não tem como contornar isso: ele não manda
esses campos, e o mascaramento acontece do lado do servidor.

Em caso de JWT inválido ou sessão expirada, o serviço tenta **uma única vez**
com credencial nova. Há timeout de 32s, e a interface diz o que aconteceu em vez
de travar.

## Contrato da camada de dados

`data-service.js` expõe uma função pública:

```js
carregarDadosSummit() → Promise<Dados>
```

```js
Dados = {
  evento:  { nome, dias: [ISO, ISO], local, regra_reserva, regra_vagas },
  temas:   [ { codigo, rotulo } ],
  sessoes: [ { id, dia, inicio, fim, titulo, descricao, quem, espaco,
               formato, etiqueta, trilhas[], vaga_limitada, online, temas[] } ],
  pessoas: [ { nome, credencial, resumo, foto, destaque, na_grade, temas[] } ]
}
```

Regras do contrato:

- **Resolve com a forma acima, já conferida.** Se vier faltando `evento.dias`,
  `temas`, `sessoes` ou `pessoas`, é erro — não meia tela.
- **Rejeita com um `Error` que nomeia a origem e o motivo**
  (`local ./dados/summit.json: HTTP 503`). A página mostra isso e **não inventa
  conteúdo no lugar** — é o princípio que sustenta a confiança no agente.
- **Não guarda estado nem cache.** Quem chama decide quando recarregar.
- **Nenhuma outra parte do frontend chama `fetch` de conteúdo.** Fora do
  `data-service.js`, `summit.json` só aparece em comentário.

A ordem das origens sai do config: com `apiBaseUrl` preenchida a API vem
primeiro e o arquivo local vira rede de segurança; com ela nula, só o arquivo.
Desligar as duas deixa a página sem fonte — e ela diz isso na tela.

## Integração com o `mindagent-bootstrap`

A API é a origem oficial. O `data-service.js` pede
`GET {apiBaseUrl}/eventos/{eventSlug}/summit` e recebe a forma do contrato, com
`_meta.generated_at` e `_meta.schema_version` por cima (campos extra são
ignorados). Validado em 20/08/2026: **10 temas, 67 sessões, 44 palestrantes**,
`Access-Control-Allow-Origin: *`, sem autenticação, `Cache-Control: max-age=60`.

Uma observação para quem for mexer no bootstrap: hoje a função **ignora o
caminho** — responde a mesma coisa na raiz e em
`/eventos/mind-summit-2026/summit`. O frontend já manda o caminho completo, então
o dia em que a função passar a rotear por evento, nada muda aqui.

Nenhuma outra linha do frontend sabe de onde vêm os dados: `app.js` só chama
`carregarDadosSummit()`.

O que fica para as próximas etapas: levar a identidade ao backend do agente
(hoje ela para no navegador — ver “Identidade via Yazo”), e mover as respostas
dos fluxos locais de `app.js` para o RAG do agente.

## `summit.json` como fallback

`dados/summit.json` deixou de ser a fonte e virou rede de segurança: só é lido
se a API não responder. Ele é gerado por `scripts/gerar-dados-mindagent.mjs` no
repositório do site, a partir de `src/data/programacao.json` e
`src/data/speakers.json` — **não editar à mão**, a edição se perde na próxima
geração.

É uma cópia congelada e já está atrás da API (53 sessões e 39 pessoas, contra 67
e 44). Serve para a página não morrer numa queda do bootstrap; vale regerar de
vez em quando para a diferença não crescer.

## Identidade via Yazo

**Implementada.** A Yazo (o app do evento) embeda a página passando quem está
logado no dispositivo:

```
https://mind-agent.adriana-3eb.workers.dev/?email=fulana@empresa.com&nome=Fulana
```

`config.js` é o dono da identidade — `capturarIdentidade()`, chamada pelo
`app.js` antes da primeira saudação. A ordem de prioridade: query string da
Yazo → `sessionStorage` (mesma aba, até 12 horas) → anônimo. Escolhas que
valem registro:

- **`sessionStorage`, não `localStorage`**: a identidade morre com a aba. Um
  notebook emprestado no credenciamento não entrega o e-mail de quem usou
  antes.
- **Só `email` e `nome`**, sem aliases: alias aceito é porta que ninguém fecha
  depois.
- **A URL é limpa antes de validar** (`history.replaceState()`): o e-mail some
  da barra de endereço, do histórico e de link copiado — e não aparece em
  console nem em mensagem de erro, nem quando é inválido.
- **E-mail fora do formato descarta a identidade inteira**; nome sozinho só
  cumprimenta. O agente nunca chuta um nome nem transforma o antes-do-@ em
  apelido.
- Para conferir de dentro do app (onde não há DevTools): o painel de ajuda
  (?) mostra *“Identificado pela Yazo: Fulana — fulana@empresa.com”* ou que o
  dispositivo ainda não foi identificado.

Duas fronteiras de pé: isso é **identificação, não autenticação** (qualquer um
abre a página com `?email=` alheio — serve para personalizar, nunca para
liberar dado sensível), e **nada disso vai para a OpenAI** — o payload do
`chat-service.js` segue a lista fechada de `shared/CONTRATOS.md`. Levar a
identidade ao backend do agente (`identity_verified` hoje é sempre `false`) é
mudança de contrato e de política de privacidade, para a Edge Function.

## Princípio preservado: o agente não agenda por você

Vale registrar porque é fácil de quebrar sem perceber. Toda resposta com passo
abre o cartão “onde fica”: o recorte da tela real com o anel sobre o botão, e o
selo **“Quem faz é você. Eu ainda não consigo agendar no seu lugar.”** O agente
mostra o caminho; a ação é sempre da pessoa. Espelha o template
`agente.nao_agendo` e a tabela `tutorial_passos` que o backend vai servir.

## Integrações

A página aceita ser embedada e responde a dois gatilhos, os dois abrindo o tour
direto numa tela:

- `?tutorial=agenda` na URL (`agenda`, `detalhe`, `confirmada`, `minha-agenda`,
  `minha-agenda-17`, `qrcode`, `scanner`, `menu`, `mapa`, `rede`,
  `palestrantes`, `chat`);
- `postMessage({ tipo: 'mindagent:tutorial', tela: 'agenda' })`.

Ao concluir o tour ela emite `postMessage({ tipo: 'mindagent:tour-concluido' })`
para a página que a embeda.

## Pontos em aberto

- **Os seis fluxos de intenção continuam locais.** Agenda, palestras, pessoas,
  desafio, insight e plano são montados no navegador a partir dos dados do
  bootstrap — só a pergunta em texto livre vai para a IA. No fluxo do desafio, a
  leitura vem da IA e os cards continuam saindo daqui.
- **`<meta name="robots" content="noindex">` continua no `<head>`**, de
  propósito, enquanto a aplicação está em desenvolvimento.
- **Sem Open Graph.** Fica para o go-live, junto com a decisão sobre o
  `noindex`.
- **O fallback do chat é silencioso.** Se o `mindagent-bootstrap` cair, a
  página passa a ler `dados/summit.json` — que hoje está 14 sessões e 5 pessoas
  atrás — sem avisar ninguém. Não sobrescreve nada oficial, mas durante o evento
  um dado velho na tela é pior que um aviso de indisponibilidade.
- **`wrangler publish` ainda não foi rodado.** O `wrangler.toml` está pronto e o
  `dist/` foi validado localmente (`/` e `/admin`), mas a publicação depende da
  conta Cloudflare.
- **`assets/simbolo-mind-branco.png` e
  `assets/mind-summit-2026-branco-horizontal-transp.png`** vieram no pacote
  original mas não são referenciados pela página.
