# Mind Agent — Mind Summit 2026

Frontend do **Mind Agent**, o concierge do Mind Summit 2026 (16 e 17 de setembro
de 2026, São Paulo Expo). Site estático **mobile-first**, sem build e sem
dependências: uma página que abre em qualquer navegador ou por QR code.

Veio da pasta `mindagent/` do repositório `Mind-Institute/mindsummit2026`, onde
existia só na branch de preview. Aqui é o projeto — separado do mapa do evento.

Estado atual: **frontend consolidado, pronto para receber backend.** A camada de
dados já está isolada e a identidade do participante já é opcional; falta ligar
o `mindagent-bootstrap` e a Yazo. Sem deploy configurado e sem Supabase.

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
| `dados/summit.json` | A programação — evento, 10 temas, 53 sessões, 39 pessoas. Fonte temporária (ver abaixo). |
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
  apiBaseUrl: null,        // raiz do mindagent-bootstrap; null = usa o arquivo local
  useLocalFallback: true,  // permite cair no dados/summit.json do repositório
};
```

Nenhuma chave de Supabase, URL de Edge Function ou credencial mora aqui — nem
vai morar. Quem guarda segredo é o `mindagent-bootstrap`; o frontend só fala
com ele.

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

## Uso temporário de `summit.json`

`dados/summit.json` é **fonte de transição**, não o destino. Ele é gerado por
`scripts/gerar-dados-mindagent.mjs` no repositório do site, a partir de
`src/data/programacao.json` e `src/data/speakers.json` — **não editar à mão**,
a edição se perde na próxima geração.

Ele existe para o frontend poder ser construído e testado antes do backend. É
uma cópia congelada: horário que muda na Yazo não chega aqui até alguém rodar o
gerador de novo.

## Integração futura com o `mindagent-bootstrap`

Quando o `mindagent-bootstrap` entrar no ar, a troca é de uma linha:

```js
apiBaseUrl: 'https://…',   // em vez de null
```

O `data-service.js` passa a pedir
`GET {apiBaseUrl}/eventos/{eventSlug}/summit` e mantém o arquivo local como
fallback enquanto `useLocalFallback` estiver ligado. Se a resposta da API vier
na forma do contrato, **nenhuma outra linha do frontend muda** — `app.js` não
sabe nem precisa saber de onde vem.

O que fica para essa etapa: a forma exata da resposta (hoje o caminho da URL é
uma suposição razoável, não um acordo), autenticação, e mover as respostas do
chat — hoje simuladas por palavras-chave em `app.js` — para o RAG do agente.

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
