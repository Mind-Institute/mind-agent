# Painel administrativo — Mind Agent

Interface de administração do **Mind Agent**: o lugar onde se edita o que o
chat próprio e o agente do Treble respondem sobre o Mind Summit 2026.

Aplicação **independente**, dentro de `admin/`. O chat da raiz continua sendo
site estático sem build — este painel não toca em nenhum arquivo dele. A única
coisa que atravessa a fronteira é leitura: `../dados/summit.json` como semente e
`../assets/` para a fonte Satoshi, o símbolo e o favicon.

Estado atual: **autenticação ligada e dashboard real; cadastros ainda em
demonstração.**

- O acesso passa por **Supabase Auth**. Papel e permissões vêm exclusivamente de
  `GET /admin/me`, validado no backend.
- A **visão geral** lê `GET /admin/dashboard` da Edge Function administrativa.
- **Todo o resto** — programação, palestrantes, espaços, rotas, estandes,
  ofertas, conteúdo, documentos, conversas, auditoria — continua no banco em
  memória. Nenhuma escrita chega ao backend nesta etapa.

Essa mistura é a coisa mais perigosa do painel, então ela é dita em voz alta: a
faixa do topo mostra **"Dashboard real · Cadastros em demonstração"** em todas as
páginas. Ver [Limites desta versão](#limites-desta-versão).

## Como executar

```bash
npm install --prefix admin
```

```bash
npm run dev --prefix admin
```

E abrir <http://localhost:5174>.

Da pasta `admin/`, os comandos são os de sempre:

| Comando | O que faz |
|---|---|
| `npm run dev` | Servidor de desenvolvimento (porta 5174). |
| `npm run build` | Confere os tipos (`tsc --noEmit`) e gera `dist/`. |
| `npm run preview` | Serve o `dist/` gerado. |
| `npm test` | Roda a suíte inteira uma vez. |
| `npm run test:watch` | Roda a suíte em modo observador. |
| `npm run typecheck` | Só a conferência de tipos. |

O chat da raiz roda em paralelo, sem interferência:

```bash
npx serve .
```

## Stack

Vite · React · TypeScript · Tailwind CSS · shadcn/ui · React Router 7 · React
Hook Form · Zod · TanStack Query · `@supabase/supabase-js` (versão exata,
`2.112.3`). Testes com Vitest e Testing Library.

`npm audit` reporta **0 vulnerabilidades**.

Desktop-first e responsivo: abaixo de `lg` a barra lateral vira gaveta e as
tabelas rolam dentro do próprio contêiner — a página nunca rola na horizontal.

## Identidade visual

A mesma marca do chat, em fundo claro. Os tokens saem de `styles.css` da raiz:
verde Mind `#68ee95`, coral `#ff7057`, roxo `#9843ff`, tipografia Satoshi (o
`.woff2` de `../assets`).

Sobre superfície branca o verde `#68ee95` não passa em contraste com texto
branco, então o papel de cor primária fica com `verde.600` (`#0f9549`) e o
destrutivo com `coral.600` (`#e53616`). A paleta cheia está em
`tailwind.config.ts`; os papéis semânticos (`--primary`, `--destructive`,
`--muted`…) em `src/index.css`.

Cor é significado, não enfeite: verde = no ar, âmbar = esperando gente, coral =
quebrado.

## Arquitetura

```text
admin/src/
  components/ui/       primitivos shadcn/ui (button, table, sheet, select…)
  components/admin/    peças do painel: estados, listagem, drawer, guarda, máscara
  layouts/             casca: barra lateral, barra superior, faixa de modo
  pages/               uma página por módulo do menu, mais a tela de login
  features/            o que é específico de um módulo (drawer de edição, prévia)
  services/            AdminDataProvider (3 implementações) e a porta de autenticação
  contracts/           tipos e schemas Zod de cada recurso
  mocks/               banco em memória e as sementes
  hooks/               acesso a recurso, filtros na URL, alterações não salvas
  lib/                 formatação, máscara, pendências, permissões
  routes/              definição de rotas e o menu lateral
  test/                suíte e utilitários de teste
```

Três regras sustentam o desenho:

**1. Nenhuma página chama `fetch`.** Todas falam com `AdminDataProvider`, do
mesmo jeito que o chat da raiz fala com `data-service.js`. Trocar mock por HTTP
não reescreve tela nenhuma.

**2. Regra de negócio mora em `lib/`, não na tela.** A listagem de programação e
a visão geral usam as mesmas funções de `lib/pendencias.ts`. Se divergissem, o
painel mentiria em uma das duas.

**3. O painel não inventa dado.** Quando a fonte é ambígua — o local do evento,
por exemplo — ele mostra a divergência e pede revisão humana, em vez de escolher.
Quando o dashboard real não responde no formato do contrato, aparece erro, não
número inventado, e não há queda silenciosa para o mock. É o mesmo princípio que
sustenta o agente.

**4. Autenticação e autorização são coisas separadas.** O Supabase Auth diz
*quem* entrou. `GET /admin/me` diz *o que essa pessoa pode*. O painel não deduz a
segunda a partir da primeira, e nunca lê `user_metadata`.

## Rotas

| Rota | Módulo |
|---|---|
| `/` | Visão geral |
| `/evento` | Evento |
| `/programacao` · `/programacao/:id` | Programação |
| `/palestrantes` · `/palestrantes/:id` | Palestrantes |
| `/espacos` · `/espacos/:id` | Espaços |
| `/rotas` · `/rotas/:id` | Rotas |
| `/estandes` · `/estandes/:id` | Estandes |
| `/ofertas` · `/ofertas/:id` | Ingressos e ofertas |
| `/conteudo` · `/conteudo/:id` | Conteúdo da Mind |
| `/documentos` · `/documentos/:id` | FAQ e documentos |
| `/conversas` · `/conversas/:id` | Conversas (somente leitura) |
| `/perguntas` · `/perguntas/:id` | Perguntas sem resposta |
| `/usuarios` | Usuários e permissões |
| `/auditoria` | Auditoria |
| `/configuracoes` | Configurações |

Os módulos com edição em drawer têm **duas entradas para a mesma página**: a
listagem continua montada atrás, o endereço é compartilhável, e o link de
pendência da visão geral abre direto no registro.

**Login não é rota.** `GuardaAutenticacao` fica fora do roteador: sem sessão e
sem perfil não existe painel — nem barra lateral, nem endereço. É mais honesto
que renderizar a casca e ir escondendo pedaço, e evita todo o vaivém de
`redirectTo` na URL. Quem entra volta para o mesmo endereço que estava tentando
abrir, porque a rota nunca chegou a mudar.

Filtro também mora na URL (`/programacao?dia=2026-09-17&espacoId=null`). Só
metadado — dia, espaço, status. **Nunca dado pessoal:** URL vaza em histórico,
log de proxy e print de tela.

## Componentes

Os que aparecem em quase toda tela:

| Componente | Papel |
|---|---|
| `PaginaListagem` | Listagem padrão: cabeçalho, filtros, tabela e os estados. Cada página só descreve colunas e filtros. |
| `EstadoCarregando` · `EstadoVazio` · `EstadoErro` · `EstadoSemPermissao` | Os estados obrigatórios, escritos uma vez para terem a mesma cara nos quinze módulos. |
| `DrawerEdicao` | Edição sem perder a listagem de vista; fechar passa pela checagem de alterações não salvas. |
| `Campo` · `SecaoFormulario` | Rótulo, dica, erro e `aria-invalid` em um lugar só. |
| `EditorDeLista` · `SelecaoMultipla` | Aliases, resultados esperados, temas, trilhas, agentes. |
| `AcoesEditoriais` · `InfoPublicacao` | Publicar e arquivar conforme o papel; data e responsável do que está publicado. |
| `DialogoArquivamento` · `DialogoAlteracoesNaoSalvas` · `DialogoConflito` | As três confirmações onde alguém perde trabalho. |
| `DadoPessoal` · `ContatoMascarado` | Exibição mascarada — componente, para dar para procurar no código quem mostra dado pessoal. |
| `FaixaDemonstracao` | O aviso de modo (demonstração ou híbrido) no topo de toda página. |
| `GuardaAutenticacao` | Decide entre "restaurando sessão", login, "confirmando permissões", recusa e painel. Transparente no modo simulado. |

E `useEdicaoRecurso`, em `features/comum/`: carregar, preencher, salvar com
controle de concorrência, publicar, arquivar. Escrito uma vez para que "conflito
de atualização" e "alterações não salvas" funcionem igual em todos os módulos —
e não só naquele que alguém lembrou.

## Contratos

`src/contracts/` guarda, por recurso, o schema Zod do **formulário** (o que o
React Hook Form valida) e o do **registro** (o que o provedor devolve). Os dois
são separados de propósito: campo de horário vazio no formulário vira `null` no
registro, não string vazia.

Fora isso, `common.ts` define o que atravessa todos os módulos:

```typescript
// Fluxo editorial
type StatusEditorial = 'rascunho' | 'em_revisao' | 'publicado' | 'arquivado';

// Listagem
interface ListFilters { busca?, pagina?, porPagina?, ordenar?, [filtro]? }
interface ListResult<T> { itens: T[]; total; pagina; porPagina }

// Erro — um tipo só para os dois provedores
class AdminApiError extends Error {
  codigo: 'nao_encontrado' | 'sem_permissao' | 'conflito'
        | 'validacao' | 'rede' | 'indisponivel' | 'desconhecido';
}

// Concorrência otimista
interface OpcoesEscrita { atualizadoEmEsperado?: string | null }
```

A página não pergunta "foi HTTP 409?" — pergunta `erro.codigo === 'conflito'`.

### `AdminDataProvider`

```typescript
interface AdminDataProvider {
  readonly modo: 'mock' | 'http';

  list(resource, filters?)                    // GET    /admin/:resource
  get(resource, id)                           // GET    /admin/:resource/:id
  create(resource, payload)                   // POST   /admin/:resource
  update(resource, id, payload, opcoes?)      // PATCH  /admin/:resource/:id
  publish(resource, id, opcoes?)              // POST   /admin/:resource/:id/publish
  archive(resource, id, opcoes?)              // POST   /admin/:resource/:id/archive
  requestReindex(documentId)                  // POST   /admin/documents/:id/reindex
  getDashboard()                              // GET    /admin/dashboard
}
```

Três implementações:

- **`MockAdminDataProvider`** — banco em memória de `src/mocks/db.ts`. Tem
  controle de concorrência de verdade e `configurarFalha(recurso, codigo)`, que
  injeta erro por recurso: é assim que os testes exercitam a tela de erro sem
  depender de rede caída.
- **`HttpAdminDataProvider`** — fala com a Edge Function. Recebe o token por
  `obterToken`, manda no header `Authorization`, e avisa a camada de sessão por
  `aoNaoAutorizado` quando leva 401. Sem `VITE_ADMIN_API_BASE_URL` o construtor
  recusa a criação em vez de chutar um endereço.
- **`HybridAdminDataProvider`** — o desta etapa. `getDashboard()` vai para o
  HTTP; todo o resto vai para o mock. Ele **não** cai no mock quando o HTTP
  falha: cair em silêncio faria o painel dizer "dashboard real" mostrando número
  inventado.

Quem escolhe é `criarProvedorPadrao()`, em `services/provider-context.tsx`, a
partir de `VITE_ADMIN_API_BASE_URL` e `VITE_ADMIN_DATA_MODE`. **Nenhuma página
sabe qual dos três está ativo — nem precisa.**

`ProvedorDeDados` também aceita uma *fábrica* no lugar de uma instância. É o que
permite montar, no teste, o provedor HTTP ligado à sessão real — e assim
verificar que o token chega ao header e que o 401 volta para o login.

O nome do recurso (`sessions`, `spaces`, `offers`…) é o mesmo na URL da futura
Edge Function e na chave do TanStack Query. Um nome, escrito num lugar só.

## Dados simulados

`../dados/summit.json` é a origem inicial de **evento, temas, sessões e
pessoas** — o mesmo arquivo que o chat usa como fallback. Ele é **lido, nunca
escrito**: continua sendo gerado por `scripts/gerar-dados-mindagent.mjs` no
repositório do site.

A conversão para o formato administrativo (`src/mocks/seed/summit.ts`) é
determinística — nada de `Math.random()`, para o painel abrir igual em toda
sessão e os testes poderem afirmar valores.

Mocks pequenos, escritos à mão, para o resto: espaços (aliases, "como chegar",
coordenadas), rotas, estandes, ofertas, conteúdo institucional, fontes,
documentos, conversas, perguntas sem resposta, usuários e auditoria.

Duas escolhas que valem registrar:

- **Os mocks nascem imperfeitos de propósito.** Sessão sem espaço, palco sem
  alias, oferta sem checkout, documento com erro de indexação, conteúdo em
  rascunho. Sem isso a visão geral abriria vazia e ninguém veria o painel fazer
  o que ele existe para fazer.
- **Há uma sessão de demonstração declarada** (`ses_demo_conflito`). A grade real
  do Summit não tem nenhum choque de horário — ótimo para o evento, péssimo para
  revisar a tela. Esse registro não vem do `summit.json`, o título diz o que ele
  é, e ele nasce em rascunho.

**Nenhum dado pessoal real.** As pessoas das conversas e da lista de usuários são
fictícias, os endereços usam domínios de exemplo, e ainda assim a tela mascara
tudo antes de mostrar. As duas coisas, porque uma sozinha não é garantia.

## Estados obrigatórios

Toda página prevê: carregando, vazio, erro (com "tentar novamente"), sucesso,
sem permissão, alterações não salvas, confirmação de arquivamento e conflito de
atualização.

O fluxo editorial (`rascunho → em_revisao → publicado → arquivado`) aparece
assim: editor salva rascunho e envia para revisão; aprovador publica e arquiva;
o que está publicado mostra data e responsável; sair de formulário sujo pede
confirmação; e **o painel prefere arquivar a excluir** — arquivar tira das
listagens ativas e mantém o rastro na auditoria.

## Variáveis de ambiente

Modelo em `.env.example`; copie para `.env.local` e preencha localmente.

| Variável | Para quê |
|---|---|
| `VITE_ADMIN_API_BASE_URL` | Raiz da Edge Function `mindagent-admin`. Vazio = tudo em demonstração. |
| `VITE_ADMIN_DATA_MODE` | `mock`, `hybrid` (padrão quando há URL) ou `http`. |
| `VITE_SUPABASE_URL` | Projeto Supabase, para o Auth. Vazio = painel abre sem login. |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | Chave publicável (`sb_publishable_…`/anon). Pública por design, depende de RLS. |

**Toda variável `VITE_*` é embutida no bundle e é pública por definição.** Por
isso só cabem aí URL e chave publicável. `service_role`, secret key e chave de
Edge Function **não existem neste código** — nem em variável, nem em header.
Quem guarda segredo é o backend.

A tela de Configurações mostra se cada variável está definida — **nunca o
valor**.

`.env.example` fica sem valores de propósito; os reais vivem em `.env.local`, que
o `.gitignore` cobre. **Em modo de teste o ambiente é zerado** por
`vite.config.ts` (`test.env`): o Vite carrega `.env.local` também nos testes, e
sem isso a suíte dependeria da máquina — e conseguiria bater no backend real.

## Segurança

O que este painel faz, e continuará fazendo:

- Não guarda secret key e não usa `service_role`.
- Não faz consulta administrativa direto do navegador — quem fala com o Postgres
  é a Edge Function.
- Não coloca e-mail nem qualquer dado pessoal na URL.
- Não registra token no console; o token vive no objeto da requisição e vai no
  header `Authorization`, nunca na URL.
- Mascara dado pessoal na exibição: e-mail vira `an•••@dominio`, telefone vira
  `••••-7777`, nome vira `Ana P. S.`. O texto das mensagens de conversa ainda
  passa por `mascararTextoLivre`, porque participante digita contato no meio da
  frase.
- Não oferece botão de "revelar". Ver o dado inteiro é decisão de backend, com
  registro em auditoria.
- Não lê `user_metadata` nem `app_metadata` em lugar nenhum. A busca é
  verificável: `grep -r user_metadata src/` só encontra comentários explicando
  por que não se usa.
- Não guarda papel nem permissão entre sessões. Eles são pedidos a `/admin/me` a
  cada abertura; nada no `localStorage` decide o que você pode fazer.
- O token nunca entra em URL, query string ou console. Isso é testado, não só
  prometido — ver `autenticacao.test.tsx`.

### Sobre os papéis: a tela mostra, o backend decide

`src/lib/permissions.ts` decide o que a tela **mostra**. Ele esconde botão, marca
página como "sem permissão" e evita que alguém tente uma ação que vai ser
recusada. Isso é usabilidade.

**Não é segurança.** Qualquer pessoa com o console aberto muda o estado em
memória e vê a interface inteira — porque o que já chegou ao navegador, chegou.

O que mudou nesta etapa: o **papel** deixou de ser escolhido no cliente. Ele vem
de `/admin/me`, que valida o JWT e lê de uma **tabela do banco** —
nunca de `user_metadata`, que o próprio usuário edita. O seletor "Ver como"
existe só no modo de demonstração, e some quando há login de verdade.

O que ainda falta, e é do backend: recusar as requisições de escrita por papel.
Enquanto os cadastros forem mock, esse risco não existe; quando `VITE_ADMIN_DATA_MODE`
virar `http`, existe — e é lá que precisa estar resolvido.

## Autenticação com Supabase Auth

O painel não conhece o Supabase: conhece `PortaAutenticacao`
(`src/services/auth.ts`), quatro operações. `SupabaseAuthGateway`
(`auth-supabase.ts`) é a implementação real; os testes injetam uma porta falsa.

Isso não é cerimônia de arquitetura — resolve dois problemas concretos. O
primeiro é trocar de provedor de identidade sem reescrever tela. O segundo é
que, sem a porta, o cliente real do Supabase entraria no processo de teste e
abriria o timer de renovação de token: a suíte passaria e **não devolveria o
terminal**.

O ciclo:

1. **Abertura** — `getSession()` restaura a sessão guardada. Enquanto isso a
   tela diz "Restaurando sua sessão…".
2. **Acompanhamento** — `onAuthStateChange()` cobre login, logout e renovação de
   token, inclusive em outra aba. A inscrição é cancelada no desmonte.
3. **Autorização** — com sessão em mãos, `GET /admin/me` com
   `Authorization: Bearer …`. A resposta é validada com Zod.
4. **Abertura do painel** — só depois de 1, 2 e 3.

Papel e permissões vêm **exclusivamente de `/admin/me`**. Quando a resposta traz
`permissoes`, é ela que manda; quando traz só `papel`, a matriz de
`src/lib/permissions.ts` faz a leitura padrão daquele papel — que o **servidor**
informou — e continua valendo só para a interface. `user_metadata` não é lido em
lugar nenhum deste código.

Papel irreconhecível **não abre o painel**. Escolher um papel padrão ali seria o
frontend se autorizando sozinho.

O token é renovado sob demanda: `obterToken()` devolve o token atual e, faltando
menos de 60 segundos para o vencimento, pede um novo ao Supabase — em vez de
mandar um token morto e derrubar a sessão da pessoa no meio de uma edição.

### Estados tratados

| Situação | O que a pessoa vê |
|---|---|
| Restaurando sessão | Tela de espera, sem piscar login |
| Sem sessão | Tela de login |
| Login inválido | "E-mail ou senha incorretos", senha limpa, e-mail preservado |
| Buscando perfil | "Confirmando suas permissões…" |
| 401 em `/admin/me` ou na API | Volta ao login com "Sua sessão expirou"; a sessão morta é descartada |
| 403 em `/admin/me` | "Sua conta não tem acesso ao painel" + sair. Sem "tentar novamente": falta de papel não se resolve repetindo |
| API indisponível | "A API administrativa não respondeu" + tentar novamente |
| Serviço de auth fora | "Sem conexão com o serviço" na tela de login |

## Integração com Edge Functions

Ligado para leitura do dashboard. A Edge Function `mindagent-admin` já responde
no formato do contrato — inclusive o corpo de erro
(`{ "codigo": "sem_permissao", "mensagem": "…" }`) e o header
`If-Unmodified-Since-Version` para concorrência otimista.

O que falta para sair do modo híbrido: as respostas de listagem e item por
recurso, as escritas (`POST`/`PATCH`/`publish`/`archive`) e o pipeline real de
indexação. Do lado do frontend, é trocar `VITE_ADMIN_DATA_MODE` para `http` —
nenhuma página muda.

## Limites desta versão

- **Nenhuma escrita chega ao backend.** Salvar, publicar, arquivar e reindexar
  mexem só na memória desta aba. Recarregar a página desfaz tudo, e a faixa no
  topo avisa. O painel só faz duas requisições à API: `GET /admin/me` e
  `GET /admin/dashboard`.
- **Nenhuma tabela foi criada, nenhuma migration foi aplicada, nenhum dado real
  foi alterado.**
- **Só o dashboard é real.** Os quatorze outros módulos leem do banco em
  memória. Um número da visão geral e uma linha da programação, na mesma sessão,
  vêm de lugares diferentes — é o que a faixa do topo existe para lembrar.
- **A tela de login não tem "esqueci minha senha" nem cadastro.** Recuperação e
  convite de usuário ficam para a etapa em que Usuários deixar de ser leitura.
- **A resposta de `/admin/me` foi validada contra um formato assumido**
  (`{ papel, permissoes?, nome?, email?, id? }`, aceita também embrulhada em
  `usuario`/`perfil`/`data`). Não tive credencial para conferir o retorno real —
  se o formato divergir, o painel recusa a entrada com mensagem explícita em vez
  de adivinhar um papel.
- **O contrato de `/admin/dashboard` também é conferido em runtime.** Faltando
  `metricas`, `pendencias` ou `alertas`, aparece erro — não um dashboard vazio
  que parece ter funcionado.
- **A reindexação não indexa.** Ela enfileira (`nao_indexado` → `na_fila`) e diz,
  em texto, que nada foi indexado. O recibo carrega `simulado: true`. Um painel
  que dissesse "pronto!" sem o pipeline ligado faria o time confiar num índice
  que não existe.
- **Não há criação de registro pela interface.** `create` existe no provedor e é
  testado, mas as telas desta versão editam o que já está lá. Cadastro novo entra
  junto com a persistência.
- **Sem paginação real.** As listas cabem inteiras na tela; a paginação está no
  contrato (`pagina`, `porPagina`) e será usada quando os volumes exigirem.
- **Rotas não têm editor de mapa.** O diagrama de conexões é de conferência —
  serve para ver de relance quem ficou sem caminho.
- **Usuários é leitura, e ainda vem do mock.** Convidar pessoa e trocar papel
  dependem de endpoints que não existem.
- **Conversas é somente leitura,** de propósito: o painel não responde por aqui.
- **O local do evento está em divergência e continua assim.** `summit.json` diz
  "São Paulo Expo", material de divulgação diz "Transamérica Expo Center". O
  painel mostra as duas versões com a origem de cada uma e pede confirmação —
  escolher seria inventar dado.
- **Sem deploy.** Nada foi publicado.

## Testes

```bash
npm test --prefix admin
```

124 testes, dez arquivos. Cobrem:

| Arquivo | O que garante |
|---|---|
| `autenticacao.test.tsx` | Restauração da sessão, `onAuthStateChange`, login, validação do formulário, credencial inválida, serviço de auth fora, logout, 401, 403, papel irreconhecível, papel e permissões vindos de `/admin/me`, ausência do seletor "Ver como", token no `Authorization`, token fora da URL e fora do console, e sessão expirada no meio do uso. |
| `modo-hibrido.test.tsx` | Dashboard com números da API (e não os do mock), o selo e a faixa que dizem isso, formato inesperado virando erro, API fora do ar sem queda silenciosa para o mock, cadastros ainda em memória e nenhuma escrita saindo para o backend. |
| `provedor-dados.test.ts` | Listagem, filtros, busca sem acento, publicação, arquivamento, conflito de atualização, auditoria, reindexação, injeção de falha, isolamento entre instâncias — e, no `HttpAdminDataProvider`, os caminhos combinados, a tradução de status HTTP e o token fora da URL. |
| `dominio.test.ts` | Máscaras, formatação em BRL e pt-BR, campos faltantes, conflito de horário (inclusive os casos que **não** são conflito) e a matriz de permissões. |
| `navegacao.test.tsx` | Os quinze módulos no menu, cada um abrindo sem quebrar, o 404 e a faixa de demonstração. |
| `listagens.test.tsx` | Listagens dos módulos, aliases, alertas de oferta, estados de indexação, auditoria com antes/depois, busca e a marcação visual de conflito. |
| `filtros-e-estados.test.tsx` | Filtro por dia, espaço e status; limpar filtros; vazio; erro com "tentar novamente"; sem permissão por papel; esqueleto de carregamento. |
| `formularios.test.tsx` | Validação (nome vazio, slug inválido, data invertida, fim antes do início, reserva sem vagas), salvamento, editor de aliases, prévia do cartão e os três caminhos de alteração não salva. |
| `fluxo-editorial.test.tsx` | Publicação mock, arquivamento mock com confirmação, botões que somem por papel, conflito de atualização e reindexação mock. |
| `mascaramento-na-tela.test.tsx` | Que as telas realmente usam as máscaras — que é onde o vazamento aconteceria. |

Os testes montam o painel inteiro, com rotas e provedores reais e um banco novo
em memória por teste. `src/test/setup.ts` traz três remendos de ambiente
(ponteiro, `ResizeObserver` e `Request`), todos por limitação do jsdom — nenhum
contorna comportamento do painel.

**A suíte é hermética.** Nenhum teste toca a rede: `vite.config.ts` zera as
variáveis de ambiente em modo de teste, o Supabase entra por uma porta falsa e o
HTTP por um `fetch` falso que registra cada chamada — é assim que dá para
afirmar que o token foi no header e que nenhuma escrita saiu.

**E ela encerra sozinha,** com código 0. Duas coisas garantem isso: os
`QueryClient` de cada teste são cancelados e desmontados no `afterEach` (os
timers de coleta de lixo do TanStack Query seguravam o processo), e nenhum
cliente real do Supabase é criado — o dele renova token em intervalo e manteria
o Vitest vivo depois do último teste.
