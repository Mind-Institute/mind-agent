# Painel administrativo — Mind Agent

Interface de administração do **Mind Agent**: o lugar onde se edita o que o
chat próprio e o agente do Treble respondem sobre o Mind Summit 2026.

Aplicação **independente**, dentro de `admin/`. O chat da raiz continua sendo
site estático sem build — este painel não toca em nenhum arquivo dele. A única
coisa que atravessa a fronteira é leitura: `../dados/summit.json` como semente e
`../assets/` para a fonte Satoshi, o símbolo e o favicon.

Estado atual: **primeira versão, em modo demonstração.** Todos os quinze módulos
existem, com listagem e estados completos; evento, programação, palestrantes e
espaços têm formulário inteiro. Nenhum dado é persistido — ver
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

O chat da raiz roda em paralelo, sem interferência:

```bash
npx serve .
```

## Stack

Vite · React · TypeScript · Tailwind CSS · shadcn/ui · React Router · React Hook
Form · Zod · TanStack Query. Testes com Vitest e Testing Library.

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
  components/admin/    peças do painel: estados, listagem, drawer, selos, máscara
  layouts/             casca: barra lateral, barra superior, faixa de demonstração
  pages/               uma página por módulo do menu
  features/            o que é específico de um módulo (drawer de edição, prévia)
  services/            AdminDataProvider e as duas implementações
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
É o mesmo princípio que sustenta o agente.

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
| `FaixaDemonstracao` | O aviso de modo demonstração, no topo de toda página. |

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

Duas implementações:

- **`MockAdminDataProvider`** — o que roda hoje. Lê e escreve no banco em
  memória de `src/mocks/db.ts`. Tem controle de concorrência de verdade e
  `configurarFalha(recurso, codigo)`, que injeta erro por recurso: é assim que
  os testes exercitam a tela de erro sem depender de rede caída.
- **`HttpAdminDataProvider`** — preparado, **não ligado**. Mesmos métodos,
  mesmos tipos, mesmos erros. Sem `VITE_ADMIN_API_BASE_URL` o construtor recusa
  a criação em vez de chutar um endereço.

Quem escolhe é `criarProvedorPadrao()`, em `services/provider-context.tsx`: com a
variável preenchida, HTTP; vazia, mock. **Nenhuma página sabe qual dos dois está
ativo — nem precisa.**

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
| `VITE_ADMIN_API_BASE_URL` | Raiz das Edge Functions administrativas. Vazio = modo demonstração. |
| `VITE_SUPABASE_URL` | Projeto Supabase, para o Auth. |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | Chave publicável (anon). Pública por design, depende de RLS. |

**Toda variável `VITE_*` é embutida no bundle e é pública por definição.** Por
isso só cabem aí URL e chave publicável. `service_role`, secret key e chave de
Edge Function **não existem neste código** — nem em variável, nem em header.
Quem guarda segredo é o backend.

A tela de Configurações mostra se cada variável está definida — **nunca o
valor**.

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

### Sobre os papéis: isto não é controle de acesso

`src/lib/permissions.ts` decide o que a tela **mostra**. Ele esconde botão, marca
página como "sem permissão" e evita que alguém tente uma ação que vai ser
recusada. Isso é usabilidade.

**Não é segurança.** Qualquer pessoa com o console aberto muda o papel em memória
e vê tudo — porque o dado já está no navegador.

A autorização de verdade precisa acontecer na Edge Function administrativa: ela
valida o JWT do Supabase Auth, lê o papel de uma **tabela do banco** e recusa a
requisição. **Nunca de `user_metadata`,** que o próprio usuário edita.

O seletor "Ver como" no topo é um simulador de interface, e a tela diz isso.

## Integração futura com Supabase Auth

Hoje `src/hooks/use-sessao.tsx` mantém um usuário de mentira, trocável pelo
seletor do topo. Quando o Auth entrar:

1. o contexto passa a ler `supabase.auth.getUser()`;
2. o papel vem de uma tabela do banco, não de `user_metadata`;
3. `HttpAdminDataProvider` recebe `obterToken: () => session.access_token`.

A assinatura de `useSessao()` não muda, e nenhuma página é reescrita.

## Integração futura com Edge Functions

Preencher `VITE_ADMIN_API_BASE_URL` — e é só isso do lado do frontend. Os oito
endpoints que o `HttpAdminDataProvider` já espera estão na tabela do
`AdminDataProvider`, acima.

O que fica para essa etapa, do lado do backend: a forma exata das respostas
(hoje o contrato é uma proposta razoável, não um acordo), a validação de papel
contra o banco, o `409` de concorrência (o painel já manda
`If-Unmodified-Since-Version` e já sabe tratar) e o pipeline real de indexação.

## Limites desta versão

- **Nada é persistido.** Salvar, publicar, arquivar e reindexar mexem só na
  memória desta aba. Recarregar a página desfaz tudo, e a faixa no topo avisa.
- **Nenhuma tabela foi criada, nenhuma migration foi aplicada, nenhum dado real
  foi alterado.** O painel nunca falou com o Supabase.
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
- **Usuários é leitura.** Convidar pessoa e trocar papel dependem do Auth.
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

92 testes, oito arquivos. Cobrem:

| Arquivo | O que garante |
|---|---|
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
