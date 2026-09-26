# Mind Intelligence Admin — o painel do Mind

Interface de administração do Mind. Desde 26/09/2026, nas palavras da Adriana,
é **o painel de controle da inteligência do Mind** — não mais o admin do app do
Summit, que foi como ele nasceu.

**O que saiu (26/09/2026, decisões dela):** a visão geral, o grupo Evento
(evento, programação, palestrantes, espaços, rotas e estandes) e a Home V3
(visualização e avisos), que eram do app; e depois **tudo o que não era dado
real** — ofertas, conteúdo, documentos, conversas, perguntas, usuários e
auditoria, que mostravam demonstração; e por fim as avaliações do dia e do
evento, a tela de configurações e o rodapé com a data do Summit. O menu tem um
título por vertical — **Summit, Institute, Dash** —, por ora vazios: as tabelas
de cada uma entram quando ela as mapear. A raiz do painel abre no Catálogo até ela
definir a tela inicial, e **o que entra no painel é ela quem define** — nada de
estrutura presumida. O backend dessas telas (Edge Functions `mindagent-admin` e
`mindagent-home`, e as tabelas) continua como estava: o app ainda depende dele.

Aplicação **independente**, dentro de `admin/`. O chat da raiz continua sendo
site estático sem build — este painel não toca em nenhum arquivo dele. A única
coisa que atravessa a fronteira é leitura: `../assets/` para a fonte Satoshi, o
símbolo e o favicon.

Estado atual: **o painel mostra só dado real.**

- O acesso passa por **Supabase Auth**. Papel e permissões vêm exclusivamente de
  `GET /admin/me`, validado no backend.
- **Catálogo, real em leitura e edição:** os produtos de `catalogo.produtos`,
  pela Edge Function `mindagent-catalogo` — a origem de tudo. Salvar manda
  para o banco só o que mudou; `codigo` e `schema_dados` não se editam; criar
  e arquivar produto ainda não existem. Ver [Catálogo](#catálogo).
- **Admins do sistema, real em leitura e escrita:** quem entra no painel
  (`mind_admin_users`, por Mind ID), pela `mindagent-acesso`. Só administrador vê
  e mexe. Ver [Admins do sistema](#admins-do-sistema).

A faixa do topo diz de onde vem o que está na tela — **dados reais** em
produção, **dados simulados** no preview e nos testes, que não têm banco ligado —
e cada listagem carrega o seu selo, para não haver dúvida sobre qual tabela você
está editando. Ver
[Limites desta versão](#limites-desta-versão).

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

O projeto é fixado em **Node 22** (`.nvmrc` e `engines`). Em outra versão o
`npm install` avisa `EBADENGINE` — o build e os testes continuam passando, mas
a versão de referência é a 22:

```bash
nvm use
```

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

**2. Regra de negócio mora em `lib/`, não na tela.** A conversão entre o banco e
o formulário do Catálogo mora em `lib/catalogo.ts`, uma cópia só.

**3. O painel não inventa dado.** Quando a fonte é ambígua, ele mostra a
divergência e pede revisão humana, em vez de escolher.
Quando a API responde fora do contrato, aparece erro de contrato, não campo
preenchido por conta própria nem queda silenciosa para o mock. É o mesmo
princípio que sustenta o agente.

**4. Autenticação e autorização são coisas separadas.** O Supabase Auth diz
*quem* entrou. `GET /admin/me` diz *o que essa pessoa pode*. O painel não deduz a
segunda a partir da primeira, e nunca lê `user_metadata`.

## Rotas

| Rota | Módulo |
|---|---|
| `/` | leva ao Catálogo |
| `/catalogo` · `/catalogo/:id` | Catálogo de produtos |
| `/summit/2026/programacao` · `/summit/2026/programacao/:id` | SUMMIT → Mind Summit 2026 → Programação (só leitura) |
| `/admins` · `/admins/:id` | Admins do sistema (só administrador) |

Os módulos com edição em drawer têm **duas entradas para a mesma página**: a
listagem continua montada atrás e o endereço é compartilhável.

**Login não é rota.** `GuardaAutenticacao` fica fora do roteador: sem sessão e
sem perfil não existe painel — nem barra lateral, nem endereço. É mais honesto
que renderizar a casca e ir escondendo pedaço, e evita todo o vaivém de
`redirectTo` na URL. Quem entra volta para o mesmo endereço que estava tentando
abrir, porque a rota nunca chegou a mudar.

Filtro também mora na URL (`/catalogo?vertical=institute`). Só
metadado — vertical, tipo, situação. **Nunca dado pessoal:** URL vaza em histórico,
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
| `SeloCategoria` | Categoria da API. Conhecida aparece traduzida; desconhecida aparece com o código cru, em âmbar. |
| `AvisoErroEscrita` | 422, 403 e rede na hora de salvar — com a mensagem do backend, os detalhes e o `requestId`. |

E `useEdicaoRecurso`, em `features/comum/`: carregar, preencher, salvar com
controle de concorrência, publicar, arquivar. Escrito uma vez para que "conflito
de atualização" e "alterações não salvas" funcionem igual em todos os módulos —
e não só naquele que alguém lembrou.

## Contratos

`src/contracts/` guarda, por recurso, o schema Zod do **formulário** (o que o
React Hook Form valida) e o do **registro** (o que o provedor devolve). Os dois
são separados de propósito: campo de horário vazio no formulário vira `null` no
registro, não string vazia.

### Categorias, e por que elas não são convertidas

Os enums acompanham o vocabulário da API real:

| Campo | Valores |
|---|---|
| `sessions.tipo` | abertura, palestra, painel, workshop, masterclass, experiencia, lancamento, autografos, **credenciamento**, **almoco**, **intervalo**, **em_curadoria** |
| `sessions.formato` | presencial, online, hibrido, **remoto** |
| `spaces.tipo` | palco, sala, arena, lounge, area_expositiva, apoio, externo, **acessibilidade**, **acesso**, **alimentacao**, **ativacao**, **estandes**, **servico** |

Nos **registros** esses campos são `string`, não enum. É deliberado: valor novo
no backend precisa chegar à tela, não travar a listagem. `src/lib/rotulos.ts`
resolve o rótulo e diz se ele é conhecido; `SeloCategoria` mostra o código cru,
marcado, quando não é.

### Validação das respostas reais

`src/services/validacao-api.ts` confere toda resposta dos cinco recursos reais
contra o schema Zod do recurso, e o envelope `ListResult` contra
`{ itens, total, pagina, porPagina }`.

A regra que organiza os schemas é o que o painel faz com o campo:

| | Campos | Por quê |
|---|---|---|
| **Obrigatório** | `id`, `atualizadoEm`, `status`, e a identidade do recurso (`titulo`, `nome`, `codigo`, `dia`, `inicio`, `tipo`, datas e local do evento) | Sem `id` o registro não abre; sem `atualizadoEm` a escrita perde o `If-Unmodified-Since-Version` e passa a sobrescrever o trabalho de outra pessoa. Preencher isso por conta própria seria esconder uma quebra de contrato. |
| **Default explícito** | descrições, arrays, coordenadas, flags | Vazio é estado legítimo, e o painel já mostra "falta biografia" como pendência. Cada default está anotado no schema com o motivo. |
| **Passa intacto** | `tipo`, `formato` | Categoria desconhecida aparece com o código cru. |

Resposta fora do formato levanta `AdminApiError` com a mensagem **"Contrato
incompatível em GET /admin/…"** e uma lista de `caminho: problema` —
`itens.3.id: esperado string, veio undefined`.

**O erro nunca carrega o corpo da resposta.** Só o caminho do campo e o tipo do
problema; nem o valor recebido em enum, nem nada no console. O índice diz *qual*
registro quebrou sem revelar *o que* ele continha.

Recurso sem schema (os módulos que ainda não têm contrato fechado) passa sem
conferência — não faz sentido barrá-lo por um schema que não existe.

Se o backend passar a usar `mesa_redonda` ou `em-curadoria` com hífen, a
divergência salta aos olhos na primeira listagem. Um painel que "arredondasse"
para `palestra` faria alguém editar uma coisa acreditando ser outra — e ninguém
descobriria.

O mesmo vale nos formulários: o `Select` inclui o valor atual mesmo fora da
lista conhecida, e salvar preserva o que veio.

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
  readonly modo: 'mock' | 'http' | 'hybrid';

  list(resource, filters?)                    // GET    /admin/:resource
  get(resource, id)                           // GET    /admin/:resource/:id
  create(resource, payload)                   // POST   /admin/:resource
  update(resource, id, payload, opcoes?)      // PATCH  /admin/:resource/:id
  publish(resource, id, opcoes?)              // POST   /admin/:resource/:id/publish
  archive(resource, id, opcoes?)              // POST   /admin/:resource/:id/archive
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
- **`HybridAdminDataProvider`** — o de produção. O único recurso é o Catálogo:

  | Recurso | Destino | Operações que a API expõe |
  |---|---|---|
  | `products` | HTTP, na `mindagent-catalogo` (mock se ela não estiver configurada) | list, get, update |

  Duas garantias que valem mais que o roteamento em si:

  **Não existe queda para o mock.** Se um recurso real falha, aparece a tela de
  erro. Cair no mock em silêncio faria o painel apresentar dado inventado como se
  fosse do banco.

  **Operação sem endpoint é recusada antes de sair.** Criar, publicar ou
  arquivar produto devolve uma frase dizendo que o painel não faz aquilo — em vez
  de mandar a requisição e traduzir o 404 do gateway em "Registro não
  encontrado", que mandaria o operador procurar problema de dado onde o problema
  é de contrato.

Quem escolhe é `criarProvedorPadrao()`, em `services/provider-context.tsx`, a
partir de `VITE_ADMIN_API_BASE_URL` e `VITE_ADMIN_DATA_MODE`. **Nenhuma página
sabe qual dos três está ativo — nem precisa.**

`ProvedorDeDados` também aceita uma *fábrica* no lugar de uma instância. É o que
permite montar, no teste, o provedor HTTP ligado à sessão real — e assim
verificar que o token chega ao header e que o 401 volta para o login.

O nome do recurso (`products`) é o mesmo na URL da Edge Function e na chave do
TanStack Query. Um nome, escrito num lugar só.

## Catálogo

`/catalogo` espelha `catalogo.produtos` — um registro por produto do Mind, o
vocabulário que CRM, conhecimento e agentes referenciam — e edita o que já
existe.

| Camada | Onde |
|---|---|
| Tela | `src/pages/catalogo.tsx` (listagem + drawer de edição) |
| Regras da tela | `src/lib/catalogo.ts` — fuso de Brasília na janela de venda, e o recorte do que mudou |
| Contrato | `src/contracts/product.ts` |
| API | `supabase/functions/mindagent-catalogo` — `GET /admin/products`, `GET`/`PATCH /admin/products/:id` |
| Banco | `mind_admin_read_catalogo` e `mind_admin_mutate_catalogo` (migration `20260925183716`); contrato em `tests/catalogo_painel_contract.sql` |

Três regras seguram a edição:

- **Só vai para o banco o que mudou.** A janela de venda guarda segundos
  (`02:59:59`); regravar o formulário inteiro arredondaria o que ninguém tocou e
  sujaria a auditoria.
- **`codigo` e `schema_dados` não se editam.** O código é a chave de 13 tabelas
  de outros schemas. A tela mostra os dois travados, e o banco recusa de novo.
- **Mesmas garantias das outras escritas:** papel conferido na função e no banco
  (administrador, editor e aprovador editam), versão obrigatória — `409` abre o
  diálogo de conflito — e antes/depois em `public.mind_admin_audit`.

**No Institute, as datas são as da turma** (pedido da Adriana, 26/09/2026): os dois
sites e o agente leem `api.programas`, que usa a data de `institute.programas` e,
quando ela está vazia, o primeiro e o último encontro da turma. Produto com turma
mostra essas mesmas datas, travadas, com a turma indicada; salvar nunca as manda, e
o banco recusa (`datas_da_turma`) se alguém tentar por fora da tela. O contrato
`CATALOGO_OK` confere, produto a produto, que o painel mostra as datas do site.

**Ordenar pelas colunas** (pedido da Adriana, 26/09/2026): todo cabeçalho do
Catálogo ordena. Um clique é crescente, o segundo decrescente, o terceiro volta à
ordem do banco (por vertical e nome). A ordem mora na URL (`?ordenar=-comecaEm`),
volta à página 1 e é feita pela `mindagent-catalogo` na lista inteira, antes de
paginar. Vazio fica no fim nos dois sentidos; em Situação e Venda, "não" vem
antes de "sim"; a Janela de venda ordena pela data em que o produto sai de venda.

## Summit → Mind Summit 2026 → Programação

Pedido da Adriana (26/09/2026): no menu SUMMIT, um submenu por produto — hoje
"Mind Summit 2026" — com a tabela de programação "conforme está no backend".
É `summit_2026.sessions`, **só leitura**, pela `mindagent-summit`
(`mind_admin_read_summit_2026_sessoes`, só `service_role`; contrato
`tests/summit_programacao_contract.sql` → `SUMMIT_PROGRAMACAO_OK`).

- A lista mostra dia, horário (fuso de São Paulo), sessão, tipo (o código do
  banco), espaço, palestrantes e reserva; busca, filtros por dia, tipo e
  reserva, e ordem por coluna.
- Abrir uma sessão mostra **todas as colunas, com os nomes do banco** — coluna
  nova aparece sem versão nova do painel.
- Qualquer papel do painel vê. Escrever é recusado antes de sair.

## Admins do sistema

Pedido da Adriana (26/09/2026): ver e cadastrar quem entra no painel. A casa é a
que já existia, `public.mind_admin_users`, por Mind ID — nenhuma tabela nova. A
porta é a `mindagent-acesso`, e quem decide é o banco (`mind_admin_read_admins`,
`mind_admin_mutate_admins`, só `service_role` executa; contrato
`tests/admins_no_painel_contract.sql` → `ADMINS_PAINEL_OK`).

- **Dar acesso:** e-mail @joinmind.com.br e papel (escolhido, sem valor pronto).
  O banco acha a pessoa no Mind ID pelo e-mail: tem que existir, ser uma só, não
  fundida e **marcada como equipe**. A lista nunca cria pessoa. Quem tinha acesso
  desligado volta na mesma linha.
- **Na linha:** papel e situação ("Pode entrar no painel"). Tirar o acesso é
  desligar a situação — a linha fica, para a auditoria e para religar depois.
  Salvar manda só o que mudou, com a versão (409 abre o conflito).
- **Travas do banco:** só administrador ativo lê e escreve; ninguém tira o próprio
  acesso nem o próprio papel de administrador; o painel nunca fica sem
  administrador ativo. Toda escrita vai para `mind_admin_audit`.
- A conta antiga, de senha, aparece com o selo **sem Mind ID**.

## Dados simulados

Só existe para os testes e para o preview de cada versão, que é montado sem as
variáveis do Supabase: **em produção o painel mostra só dado real.** A semente é
`src/mocks/seed/catalogo.ts` — seis produtos escritos à mão no formato de
`catalogo.produtos`, que vende e que não vende, ativo e inativo, com e sem
vertical —, e o selo da listagem diz *demonstração* sempre que ela aparece.

## Estados obrigatórios

Toda página prevê: carregando, vazio, erro (com "tentar novamente"), sucesso,
sem permissão, alterações não salvas e conflito de atualização.

## Variáveis de ambiente

Modelo em `.env.example`; copie para `.env.local` e preencha localmente.

| Variável | Para quê |
|---|---|
| `VITE_ADMIN_API_BASE_URL` | Raiz da Edge Function `mindagent-admin`. Vazio = tudo em demonstração. |
| `VITE_ADMIN_DATA_MODE` | `mock`, `hybrid` (padrão quando há URL) ou `http`. |
| `VITE_SUPABASE_URL` | Projeto Supabase, para o Auth. Vazio = painel abre sem login. |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | Chave publicável (`sb_publishable_…`/anon). Pública por design, depende de RLS. |
| `VITE_CATALOGO_API_BASE_URL` | Opcional. Raiz da `mindagent-catalogo`; vazia, sai de `VITE_SUPABASE_URL` + `/functions/v1/mindagent-catalogo`. |
| `VITE_ACESSO_API_BASE_URL` | Opcional. Raiz da `mindagent-acesso` (primeiro login com Google); vazia, sai de `VITE_SUPABASE_URL` + `/functions/v1/mindagent-acesso`. |

**Toda variável `VITE_*` é embutida no bundle e é pública por definição.** Por
isso só cabem aí URL e chave publicável. `service_role`, secret key e chave de
Edge Function **não existem neste código** — nem em variável, nem em header.
Quem guarda segredo é o backend.

Nenhuma tela mostra o valor de variável — **nunca o
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

**A recusa de escrita por papel já existe, e é do backend, em duas camadas:**

1. a Edge Function administrativa lê o papel em `mind_admin_users` e confere se
   aquele papel pode fazer aquela ação;
2. a função SQL `mind_admin_mutate_resource` valida o papel outra vez antes de
   escrever. `anon` e `authenticated` não executam a RPC direto.

Conferido em transação: papel `analista` tentando atualizar foi recusado.

Ou seja: divergência entre a matriz da interface e o backend produz um **403
visível**, não um vazamento. Esta matriz existe para poupar o clique inútil, não
para autorizar.

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

### Admins do sistema: entrar com o Google da Mind

Decisão da Adriana (25/09/2026): o painel é dos **admins deste sistema**. A lista
é `mind_admin_users` **por Mind ID** — a pessoa tem que existir antes e estar
marcada como equipe (`staff` em `pessoas.relacionamento_mind`); a lista nunca
cria pessoa (migration `20260925232508`, contrato
`tests/admins_do_sistema_contract.sql` → `ADMINS_OK`).

1. **"Entrar com o Google da Mind"** — `signInWithOAuth` com PKCE e
   `hd=joinmind.com.br`. O app de login no Google é "Interno" do Workspace: conta
   de fora nem passa pelo Google.
2. **A volta** — o `?code=` vira sessão só com o verificador guardado neste
   navegador na ida, e sai do endereço logo depois.
3. **Primeiro login** — `/admin/me` ainda não conhece a conta (403). O painel
   chama uma vez `POST /admin/vincular` na `mindagent-acesso`, e o banco
   (`mind_admin_vincular_login`) liga a conta à pessoa: Google, e-mail verificado
   @joinmind.com.br, uma pessoa só com esse e-mail, acesso ativo e marca de
   equipe. Aí `/admin/me` é chamado de novo. Recusa do banco aparece com a frase
   dele, sem nova tentativa.

E-mail e senha continuam na tela durante a transição; saem quando todos
entrarem pelo Google.

Para o Google devolver a pessoa ao painel, o endereço precisa estar em
**Authentication → URL Configuration → Redirect URLs** do Supabase — produção
(`…/admin/`) e previews (`https://*-mind-agent.adriana-3eb.workers.dev/admin/**`).

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

As funções respondem no formato do contrato — inclusive o corpo de erro
(`{ "codigo": "sem_permissao", "mensagem": "…" }`), o `ListResult`
(`{ itens, total, pagina, porPagina }`) e o header
`If-Unmodified-Since-Version` para concorrência otimista.

Endpoints em uso:

```text
mindagent-admin      GET   /admin/me                  (quem é você e o que pode)
mindagent-acesso     POST  /admin/vincular            (primeiro login com Google)
mindagent-acesso     GET   /admin/admins · /:id · POST /admin/admins · PATCH /:id
mindagent-catalogo   GET   /admin/products · /:id · PATCH /:id
mindagent-summit     GET   /admin/summit_2026_sessions · /:id   (só leitura)
```

Toda escrita manda `If-Unmodified-Since-Version: <atualizadoEm>`, e `409` abre o
diálogo de conflito em vez de sobrescrever o trabalho de outra pessoa.

**Paginação.** A listagem pede `porPagina=50` e usa o `total` da resposta para
montar o rodapé; `pagina` fica na URL.

A `mindagent-admin` ainda serve as rotas do evento e o dashboard para quem
quiser usá-los, mas o painel não chama mais nenhuma delas: só `/admin/me`.

## Limites desta versão

- **Só o Catálogo escreve, e só edição.** Criar, publicar e arquivar produto
  ainda não existem. Pedir o que não existe devolve uma frase explicando, não um
  404 disfarçado.
- **As avaliações são somente leitura,** de propósito: resposta enviada não se
  edita, nem pelo painel.
- **Nenhuma tabela foi criada para o painel.** Ele só consome os endpoints já
  publicados.
- **A tela de login não tem "esqueci minha senha" nem cadastro.** O acesso é
  pelo Google da Mind; quem entra é quem está na lista de admins do sistema, por
  Mind ID.
- **Não há tela de criação.** `create` existe no provedor e é testado, mas a
  tela do Catálogo edita o que já está lá.
- **Paginação simples.** `porPagina=50` com "anterior/próxima". Sem salto para
  uma página específica e sem escolha de tamanho.

## Testes

```bash
npm test --prefix admin
```

141 testes, treze arquivos. Cobrem, entre outros:

| Arquivo | O que garante |
|---|---|
| `api-real.test.tsx` | Contrato das respostas da `mindagent-catalogo` (registro sem `id`, sem `atualizadoEm`, sem `nome`/`ativo`, envelope incompleto, erro apontando o índice sem revelar conteúdo, nada no console); verbos e caminhos; `If-Unmodified-Since-Version`; token e `apikey` nos headers e fora da URL; e, na tela, 401, 403, 404, 409, 422, 503 e o `requestId`. |
| `modo-hibrido.test.tsx` | O Catálogo como único recurso, real com a função e demonstração sem ela, operação inexistente recusada antes de sair, sem queda para o mock em erro, token fora da URL e do console, e o selo do topo. |
| `catalogo.test.tsx` | Conversão entre banco e formulário (fuso de Brasília, só o que mudou), endereço da função, contrato, roteamento e a tela do Catálogo. |
| `autenticacao.test.tsx` | Restauração da sessão, `onAuthStateChange`, login, validação, credencial inválida, serviço de auth fora, logout, 401, 403, papel irreconhecível, papel e permissões vindos de `/admin/me`, login com o Google da Mind, token no `Authorization` e fora da URL e do console. |
| `provedor-dados.test.ts` | Listagem, filtros, busca sem acento, arquivamento, conflito de atualização, injeção de falha e isolamento no mock — e, no `HttpAdminDataProvider`, os caminhos, a tradução de status HTTP e o token fora da URL. |
| `dominio.test.ts` | Máscaras de dado pessoal, formatação em BRL e pt-BR e a matriz de permissões. |
| `navegacao.test.tsx` | Os quatro módulos no menu, cada um abrindo sem quebrar, a raiz no Catálogo, o 404 — e que nada do que saiu volta ao menu. |
| `filtros-e-estados.test.tsx` | Filtro na URL, limpar filtros, vazio, erro com "tentar novamente" e esqueleto de carregamento. |
| `formularios.test.tsx` | O drawer não fecha por cima de alteração não salva. |
| `fluxo-editorial.test.tsx` | Conflito de atualização: a alteração de outra pessoa não é sobrescrita em silêncio. |
| `listagens.test.tsx` | Busca textual. |
| `publicacao.test.tsx` | O painel sob `/admin` e as regras de roteamento do Worker. |
| `admins.test.tsx` | A lista vem da `mindagent-acesso`; dar acesso manda só e-mail e papel; e-mail de fora da Mind e papel vazio não saem da tela; recusas do banco aparecem; mudar papel ou situação manda só o que mudou, com a versão; conflito; quem não é administrador não vê. |

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
