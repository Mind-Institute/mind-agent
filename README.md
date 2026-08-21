# Mind Agent — Mind Summit 2026

Frontend do **Mind Agent**, o concierge do Mind Summit 2026 (16 e 17 de setembro
de 2026, São Paulo Expo). Site estático **mobile-first**, sem build e sem
dependências: uma página que abre em qualquer navegador ou por QR code.

Veio da pasta `mindagent/` do repositório `Mind-Institute/mindsummit2026`, onde
existia só na branch de preview. Aqui é o projeto — separado do mapa do evento.

Estado atual: **IA conectada.** A programação vem do `mindagent-bootstrap`
(10 temas, 67 sessões, 44 palestrantes) com `dados/summit.json` como fallback, e
o chat responde de verdade pela Edge Function `mindagent-chat`, que fala com a
OpenAI. As respostas simuladas foram removidas. A identidade do participante
entra pela URL ou por `postMessage` quando o app do evento embeda a página
(ver “Identidade do participante”). Falta o deploy.

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

O que fica para as próximas etapas: levar a identidade do participante ao
backend do agente (hoje ela para no navegador — ver “Identidade do
participante”), e mover as respostas dos seis fluxos de intenção — hoje montadas
localmente em `app-classic.js` — para o RAG do agente.

## `summit.json` como fallback

`dados/summit.json` deixou de ser a fonte e virou rede de segurança: só é lido
se a API não responder. Ele é gerado por `scripts/gerar-dados-mindagent.mjs` no
repositório do site, a partir de `src/data/programacao.json` e
`src/data/speakers.json` — **não editar à mão**, a edição se perde na próxima
geração.

É uma cópia congelada e já está atrás da API (53 sessões e 39 pessoas, contra 67
e 44). Serve para a página não morrer numa queda do bootstrap; vale regerar de
vez em quando para a diferença não crescer.

## Identidade do participante (embed pelo app do evento)

Quem usa o que está descrito aqui é o **chat clássico, `/classic.html`**. A
Central do Evento (`/`) tem a sua própria leitura de identidade, em
`agent-dados.js`, com política mais fechada: lá `?nome` e `?email` só valem
sob `?preview=1`, e um e-mail fora disso é marcado como não verificado. As
duas conviverem é **decisão pendente** — unificar significa escolher uma
política de confiança para `?email`, e isso é chamada de produto, não de
refactor.

A identidade é **opcional por definição**, em `config.js`:

```js
export const PARTICIPANTE = { nome: null, email: null };
definirParticipante({ nome: 'Fulana', email: 'fulana@empresa.com' });
```

Com tudo nulo o agente cumprimenta sem nome (“Oi! 💚 Sou o Mind Agent…”) —
**ele nunca chuta quem você é.** Preenchido o `nome`, chama pela pessoa sem que
mais nada mude. Só e-mail, sem nome, mantém a saudação neutra: e-mail não vira
apelido.

O app do evento embeda a página passando quem está logado no dispositivo, por
qualquer um dos dois caminhos:

- **Query string** (o combinado com o fornecedor do app):

  ```
  https://mind-agent.adriana-3eb.workers.dev/classic.html?email=fulana@empresa.com&nome=Fulana
  ```

  `email` (ou `user_email`) identifica; `nome` (ou `name`) é opcional. A página
  lê, guarda no `localStorage` (por evento — a identidade sobrevive ao reload,
  já que a query só vem uma vez) e **remove os parâmetros da barra de
  endereço**, para o e-mail não vazar em print, histórico ou link compartilhado.

- **postMessage**, para o app mandar depois do load:

  ```js
  iframe.contentWindow.postMessage(
    { tipo: 'mindagent:identidade', email: 'fulana@empresa.com', nome: 'Fulana' }, '*');
  ```

Duas fronteiras que continuam de pé:

- **Isso é identificação, não autenticação.** Qualquer um pode abrir a página
  com `?email=` de outra pessoa. Serve para personalizar e registrar com quem o
  agente falou — nunca para liberar dado sensível. Se um dia a página precisar
  mostrar dado pessoal (agenda reservada, contatos), o app terá de passar um
  token assinado, não um e-mail em texto puro.
- **Nada disso vai para a OpenAI.** O payload do `chat-service.js` segue a
  lista fechada de `shared/CONTRATOS.md`, sem nome nem e-mail — enviar a
  identidade ao backend do agente (para o `identity_verified` deixar de ser
  sempre `false`) é mudança de contrato e de política de privacidade, a ser
  feita na Edge Function junto com o banco, não aqui.

## Princípio preservado: o agente não agenda por você

Vale registrar porque é fácil de quebrar sem perceber. Toda resposta com passo
abre o cartão “onde fica”: o recorte da tela real com o anel sobre o botão, e o
selo **“Quem faz é você. Eu ainda não consigo agendar no seu lugar.”** O agente
mostra o caminho; a ação é sempre da pessoa. Espelha o template
`agente.nao_agendo` e a tabela `tutorial_passos` que o backend vai servir.

## Integrações

O chat clássico (`/classic.html`) aceita ser embedado e responde a três
gatilhos:

- `?email=…&nome=…` na URL ou
  `postMessage({ tipo: 'mindagent:identidade', email, nome })` — identifica o
  participante logado no app (ver “Identidade do participante” acima);
- `?tutorial=agenda` na URL (`agenda`, `detalhe`, `confirmada`, `minha-agenda`,
  `minha-agenda-17`, `qrcode`, `scanner`, `menu`, `mapa`, `rede`,
  `palestrantes`, `chat`) — abre o tour direto naquela tela;
- `postMessage({ tipo: 'mindagent:tutorial', tela: 'agenda' })` — idem.

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
