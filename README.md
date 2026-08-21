# Mind Agent — Mind Summit 2026

Frontend do **Mind Agent**, o concierge do Mind Summit 2026 (16 e 17 de setembro
de 2026, São Paulo Expo). Site estático **mobile-first**, sem build e sem
dependências: uma página que abre em qualquer navegador ou por QR code.

Veio da pasta `mindagent/` do repositório `Mind-Institute/mindsummit2026`, onde
existia só na branch de preview. Aqui é o projeto — separado do mapa do evento.

Estado atual: **frontend consolidado e lendo do `mindagent-bootstrap`.** A
programação vem da API (10 temas, 67 sessões, 44 palestrantes), com o
`dados/summit.json` do repositório como fallback. Falta a identidade via Yazo e
o deploy.

## Como executar localmente

```bash
npx serve .
```

E abrir <http://localhost:3000>. Precisa ser por servidor local, por dois
motivos: a página busca os dados por `fetch` e o `app.js` é um ES module — em
`file://` os dois são bloqueados pelo navegador.

Qualquer servidor estático serve (`python -m http.server`, `php -S`, extensão
Live Server). Não há passo de build: o que está no repositório é o que roda.

## Estrutura dos arquivos

| Arquivo | O que é |
|---|---|
| `index.html` | Só estrutura: o `<head>`, o markup das quatro vistas (splash, home, chat, Seu Summit, tour) e os popups. Nenhum estilo e nenhuma lógica. |
| `styles.css` | Tokens da marca, as quatro vistas, o tour e os componentes de UI generativa. |
| `app.js` | A aplicação: splash, navegação, motor do tour, chat, perfil vivo e o mapa. ES module — entra por `<script type="module">`. |
| `config.js` | Configuração central e a identidade do participante. O único lugar que sabe de onde vêm os dados e quem está usando. |
| `data-service.js` | A camada de dados. Ninguém mais no frontend chama `fetch` de conteúdo. |
| `dados/summit.json` | Cópia congelada da programação (10 temas, 53 sessões, 39 pessoas). Só é lida se a API não responder (ver abaixo). |
| `assets/tour/` | As 12 capturas de tela do app usadas pelo tour. |
| `assets/palestrantes/` | As 39 fotos referenciadas por `pessoas[].foto`. |
| `assets/` | Símbolo Mind, favicon e a fonte Satoshi (`.woff2`). |

O `index.html` monolítico anterior foi separado sem alterar uma linha de CSS
nem de markup: o `<style>` virou `styles.css` e o `<script>` virou `app.js`,
byte por byte.

## Configuração central

Tudo em `config.js`:

```js
export const CONFIG = {
  eventSlug: 'mind-summit-2026',
  apiBaseUrl: 'https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/mindagent-bootstrap',
  useLocalFallback: true,  // cai no dados/summit.json se a API não responder
};
```

A URL do bootstrap é pública e abre sem autenticação — **nenhuma chave, `anon
key` ou credencial mora no cliente.** Quem guarda segredo é o
`mindagent-bootstrap`, do lado do servidor.

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

O que fica para as próximas etapas: identidade via Yazo, e mover as respostas do
chat — hoje simuladas por palavras-chave em `app.js` — para o RAG do agente.

## `summit.json` como fallback

`dados/summit.json` deixou de ser a fonte e virou rede de segurança: só é lido
se a API não responder. Ele é gerado por `scripts/gerar-dados-mindagent.mjs` no
repositório do site, a partir de `src/data/programacao.json` e
`src/data/speakers.json` — **não editar à mão**, a edição se perde na próxima
geração.

É uma cópia congelada e já está atrás da API (53 sessões e 39 pessoas, contra 67
e 44). Serve para a página não morrer numa queda do bootstrap; vale regerar de
vez em quando para a diferença não crescer.

## Identidade futura via Yazo

A identidade do participante é **opcional por definição**, em `config.js`:

```js
export const PARTICIPANTE = { nome: null };
definirParticipante({ nome: 'Fulana' });
```

Com `nome` nulo o agente cumprimenta sem nome (“Oi! 💚 Sou o Mind Agent…”) —
**ele nunca chuta quem você é.** Preenchido, chama pela pessoa sem que mais nada
mude.

Quem vai preencher é a Yazo, pela plataforma do evento (ou o e-mail, como
segunda via), através do `mindagent-bootstrap`. Enquanto isso não existe, o
valor fica nulo em produção e a saudação é neutra. Nada de nome fixo no código.

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

- **As respostas do chat são simuladas** — palavras-chave em `RESPOSTAS`, mais
  os seis fluxos de intenção. A prévia diz isso na tela (“Prévia de design —
  respostas simuladas”). O agente real (RAG) vem com o backend.
- **`<meta name="robots" content="noindex">` continua no `<head>`**, de
  propósito, enquanto a aplicação está em desenvolvimento.
- **Sem Open Graph.** Fica para o go-live, junto com a decisão sobre o
  `noindex`.
- **Deploy não configurado.** Site estático puro: publica como está por
  Cloudflare Pages ou por um Worker com binding de assets.
- **`assets/simbolo-mind-branco.png` e
  `assets/mind-summit-2026-branco-horizontal-transp.png`** vieram no pacote
  original mas não são referenciados pela página.
