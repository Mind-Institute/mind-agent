# Mind Agent — estado do projeto, arquitetura congelada e ordem de execução

> **Documento obrigatório de entrada no projeto.**
> Este arquivo preserva as decisões congeladas, a ordem de trabalho e o checkpoint atual para que uma nova IA ou desenvolvedor consiga continuar o projeto sem depender de conversa anterior.
>
> **Versão do checkpoint: v5 — 30/08/2026.**
> v2 formaliza a mudança de prioridade feita no Passo 12: completar toda a Intelligence do Summit **não bloqueia** o go-live do vendedor. A investigação já feita fica preservada no `BACKLOG.md`; o caminho crítico passa a ser Kit Loader mínimo → vendas Summit → runtime completo → Treble E2E. **Essa decisão continua vigente — v3 e v4 não a substituem.**
> v3 acrescenta e formaliza o **modo de execução assistida/autônoma** entre Adriana, ChatGPT, Claude Code e GitHub (§2B). É uma decisão sobre como o trabalho é conduzido; não altera arquitetura, runtime nem a ordem do roadmap. **Continua vigente, exceto na premissa corrigida por v4.**
> v4 corrige **apenas uma premissa incorreta de v3**: a frase `Produção continua separada e controlada.` foi contrariada pelo sistema real. As integrações GitHub da Cloudflare e do Supabase estão ativas e **merge em `main` publica produção**. v4 substitui essa premissa pelo contrato canônico **merge em `main` é boundary de deploy** (§2B). Não muda arquitetura, runtime, roadmap nem PASSO ATUAL. **Esse contrato continua vigente — v5 não o altera.**
> v5 substitui **somente o modelo operacional de papéis** de v3/v4 (§2B): o ChatGPT-chat sai do caminho crítico operacional e o **supervisor técnico passa a ser o Codex no repositório**. Não altera arquitetura, runtime, roadmap, PASSO ATUAL nem o boundary de deploy; os gates da Adriana permanecem integralmente.

---

## 1. Como a documentação se divide

Não misturar os três papéis:

| documento | responde |
|---|---|
| **`PROJECT_STATE.md`** | Qual arquitetura/ordem está congelada? Em que passo estamos? O que vem depois? |
| **`docs/CORE_UNIVERSAL.md`** | O que existe e funciona **agora** no sistema real? Quais contratos já estão implementados? |
| **`BACKLOG.md`** | O que foi descoberto/investigado e deliberadamente deixado para depois? Como retomar sem investigar de novo? |

### Regra de congelamento

**Uma decisão só está realmente congelada quando está registrada no Git.**

Quando a Adriana aprovar uma decisão de arquitetura, funcionamento, taxonomia ou ordem de execução:

1. registrar a decisão neste arquivo no mesmo passo;
2. se a decisão também muda o estado/contrato implementado, atualizar somente as seções afetadas de `docs/CORE_UNIVERSAL.md` depois da implementação/teste;
3. se algo já investigado for adiado, registrar o checkpoint detalhado no `BACKLOG.md`;
4. só então considerar o passo fechado.

### Mudança de decisão congelada = nova versão

Não sobrescrever silenciosamente uma decisão congelada.

Se uma mudança material reorganizar o funcionamento do sistema ou a ordem de trabalho:

- incrementar este checkpoint: `v2 → v3 → v4...`;
- registrar **o que a nova versão substitui e por quê**;
- deixar a decisão vigente clara;
- ajustar o Core quando a implementação mudar de fato;
- Git preserva o histórico anterior.

Não é necessário versionar por mudança cosmética. Versão muda quando o modelo mental do sistema ou a sequência material de execução muda.

---

## 2. Ritual obrigatório de execução

```
INVESTIGAR
→ ENTENDER O QUE JÁ EXISTE
→ DECIDIR A MENOR MUDANÇA
→ IMPLEMENTAR
→ TESTAR SÓ O AFETADO
→ ATUALIZAR A DOCUMENTAÇÃO DO ESTADO FINAL
→ FECHAR O PASSO
```

Antes de implementar qualquer passo, investigar o sistema real relacionado ao tema.

Na investigação, responder apenas o necessário para decidir corretamente:

- o que já existe;
- tabelas, funções, Edge Functions e fluxos envolvidos;
- o que está realmente em uso e o que é legado;
- dependências;
- o que já resolve parte do problema;
- menor mudança recomendada;
- qualquer fato que contradiga a arquitetura imaginada.

### Proporcionalidade

Mudança pequena não vira revalidação ampla.

Critério operacional:

> **funciona corretamente + não perde/corrompe dado + é replicável = seguimos.**

Testar o que mudou e regressões diretamente afetadas. Suíte completa só quando a mudança for estrutural ou explicitamente pedida.

Não criar abstrações, hardening ou proteções para riscos hipotéticos distantes.

---

## 2B. Modo operacional de execução — decisão congelada (v3, corrigida em v4, papéis substituídos em v5)

**Papéis vigentes — v5 (30/08/2026).** v5 substitui o modelo de papéis de v3/v4: o ChatGPT-chat sai do caminho crítico operacional e a supervisão técnica passa ao Codex no repositório. Arquitetura, runtime, roadmap e boundary de deploy não mudam.

- **Adriana** = dona das decisões de produto/negócio e dos gates sensíveis/manuais que só ela pode executar ou autorizar.
- **Codex** = supervisor técnico operacional: reconstrói o checkpoint pelos documentos canônicos + estado real, mantém a ordem, enquadra as perguntas de investigação, verifica GitHub/Supabase, decide a menor mudança, delega ao Claude quando uma segunda leitura/execução agregar, revisa PR e testes, mergeia quando permitido, verifica produção, documenta o fechamento e **continua para o próximo passo sem esperar a Adriana**.
- **Claude Code** = investigador + executor complementar, sempre escopado: investigações pequenas e orientadas a uma decisão; implementação em branch `claude/...`; traz leitura independente; **nunca mergeia e não amplia escopo sozinho**.
- **GitHub** = memória compartilhada + barramento de trabalho/estado.

Workflow operacional:

```
Codex formula pergunta específica
→ Claude investiga sem implementar
→ Codex verifica os fatos-chave contra o sistema real
→ Codex fecha a menor mudança
→ Claude implementa a task fechada quando delegado
→ Codex revisa / testa / mergeia / verifica / documenta
→ continua
```

Regras:

- Claude nunca escreve diretamente em `main`; implementação passa por branch/PR e revisão.
- Descoberta lateral fora do escopo: não corrigir; registrar/relatar para backlog.
- Investigação e desenho técnico podem ocorrer autonomamente entre Codex e Claude.
- Código reversível pode seguir Claude → branch/PR → revisão do Codex → testes afetados → documentação → merge.
- Alterações de dados, identidade, segurança/RLS/auth/secrets, preço/desconto/regra comercial, outbound/disparo, source of truth, mudança material de comportamento do produto ou operação irreversível exigem gate explícito da Adriana antes da execução perigosa.
- Se uma implementação depender de decisão de produto/negócio não congelada, parar e devolver a pergunta em vez de escolher.
- O ritual INVESTIGAR → DECIDIR → IMPLEMENTAR → TESTAR → DOCUMENTAR → FECHAR continua valendo; a automação só remove Adriana do papel de mensageira.

Autonomia do supervisor:

- **Espera técnica, fim de run, preview, revisão, merge permitido e verificação não são motivo para parar.** São etapas do próprio trabalho do supervisor.
- O supervisor só para para a Adriana nos **gates já definidos** acima e na §"Boundary de deploy", ou diante de uma **decisão de negócio realmente não congelada**.
- Fora desses casos, relatar o checkpoint de forma objetiva e seguir para o próximo passo.

### Boundary de deploy — correção v4 (29/08/2026)

v3 dizia: `Claude via GitHub não recebe credenciais de produção nem autorização de deploy. Produção continua separada e controlada.`

A primeira frase continua verdadeira. **A segunda estava errada** e foi verificada como falsa contra o sistema real: as integrações GitHub da Cloudflare e do Supabase estão ativas neste repositório, geram preview em PR e agem em produção no merge. Contrato canônico vigente:

> **MERGE EM `main` É BOUNDARY DE DEPLOY.**

- Claude Code continua sem credenciais de produção e **nunca mergeia**.
- Claude trabalha em `claude/...` e entrega branch/PR.
- PR que toca runtime Cloudflare pode gerar preview automaticamente; **merge em `main` pode publicar produção**.
- PR que toca `supabase/` pode gerar preview DB; **merge em `main` pode aplicar migrations/Edge Functions em produção** pela integração Supabase.
- Portanto **revisão e teste devem acontecer ANTES do merge**, não depois.
- Mudança aditiva/reversível, com preview/testes afetados aprovados e sem decisão de negócio pendente, pode seguir Codex → merge → verificação pós-deploy **sem pedir aprovação operacional da Adriana a cada PR**. (v5 troca apenas o ator supervisor; o contrato de boundary é o mesmo de v4.)
- Mudanças de dados destrutivas/irreversíveis, identidade, segurança/RLS/auth/secrets, preço/desconto/regra comercial, outbound/disparo, source of truth, mudança material de comportamento do produto ou qualquer decisão de negócio não congelada continuam exigindo **gate explícito da Adriana ANTES DO MERGE**.
- Se preview/CI relevante não existir ou não puder ser verificado, **não mergear no automático**; relatar a lacuna.
- Depois do merge, verificar **somente o efeito diretamente afetado** em produção.

A evidência que sustenta essa correção está registrada no `BACKLOG.md`, em `Infra de deploy GitHub — descoberta 29/08/2026`. **Não reinvestigar esses fatos do zero.**

---

## 3. Propósito do sistema

Construir um **Core Universal de agentes do Mind**, reutilizado por vendas, atendimento, concierge e futuros agentes, independentemente do canal.

O primeiro sistema operacional completo é:

> **Vendas do Mind Summit via Treble/WhatsApp.**

Mas a arquitetura não pode ser Treble-specific.

**Treble é adapter de canal.** App, web e futuros canais consomem o mesmo Core.

Um agente novo **não reimplementa identidade, contexto, memória ou histórico**. Consome o Core Universal existente.

---

## 4. Arquitetura conceitual congelada

Quatro responsabilidades, sem mistura:

| camada | função |
|---|---|
| **INTELLIGENCE** | o que é verdade agora |
| **PLAYBOOK** | como um excelente profissional pensa e atua |
| **DECISIONING** | qual estratégia faz sentido agora |
| **AGENT** | o que efetivamente diz ou faz |

> **PLAYBOOK DECIDE COMO PENSAR. INTELLIGENCE INFORMA O QUE É VERDADE AGORA.**

Coletor factual não decide, não pontua, não recomenda e não escreve.

---

## 5. Ordem canônica do runtime

```text
CANAL / ENTRADA
→ INGESTÃO
→ IDENTIDADE
→ AGENT_CONTEXT
→ ROUTER                       [somente se a rota não vier determinada]
→ CAPABILITY GATE
→ KIT DA ROTA
    ├── PLAYBOOK
    ├── PRODUCT INTELLIGENCE relevante
    ├── ECOSSISTEMA / Intelligence perene relevante
    ├── KNOWLEDGE relevante para a necessidade atual
    └── TOOLS / capabilities
→ DECISIONING
→ AGENT
→ AÇÃO / HANDOFF
→ ANÁLISE PÓS-TURNO + MEMÓRIA
→ WRITE-BACK / DISPATCH
→ CONTINUIDADE / SILENCE
```

### Regras da ordem

- identidade/contexto sempre antes do Router;
- Router só responde **qual competência assume a necessidade atual**;
- se a rota já está determinada por contexto autoritativo, pula Router, **não** o Gate;
- Gate não muda rota: verifica se o runtime consegue executar a rota;
- `needs_human` significa necessidade sem capacidade autônoma; não é o mecanismo de transferência;
- Kit é recomposto por turno; não persistir um blob gigante de Product Intelligence na conversa;
- história informa; **necessidade atual decide a rota**.

---

## 6. Identidade e contexto — decisões congeladas

### Pessoa canônica

`pessoas.pessoas.id` = **`pessoa_id` canônico interno e permanente**.

`pessoas.pessoas` é eixo de identidade, não perfil completo.

HubSpot, e-mail, WhatsApp e auth são identificadores/evidências, não IDs alternativos.

A pessoa pode entrar primeiro pelo Mind ou primeiro pelo CRM. Quando os dois lados existirem, convergem para a mesma `pessoa_id`.

### CRM + Engagement

O que sabemos sobre a pessoa é montado continuamente a partir de:

- CRM / HubSpot;
- Engagement: mensagens, agentes de IA, agentes humanos, comportamento e contexto aprendido.

Mensagens humanas são primeira classe.

Conflito relevante de identidade/CRM:

```text
detecta
→ persiste evidência
→ pendência persistente/idempotente
→ NÃO auto-merge
→ resolução humana
```

### AGENT_CONTEXT

`AGENT_CONTEXT` é universal e contém pessoa/conversa/CRM/Engagement/realidade factual necessária ao turno.

**Não colocar conhecimento de Summit, Dash ou Institute dentro do AGENT_CONTEXT.** Product Intelligence entra depois da rota, via Kit da rota.

---

## 7. Casas canônicas da Intelligence

### 7.1 ECOSSISTEMA / PERENE

**Intelligence perene, curada e reutilizável do Mind** entre Summit, Institute, Dash e futuros produtos.

Exemplos conceituais:

- especialistas;
- conceitos;
- construtos;
- fundamentos científicos;
- inteligência estratégica perene.

Hoje a única tabela real do schema `ecossistema` é `palestrantes_especialistas`.

`ecossistema.palestrantes_especialistas` é **LOCAL_AUTHORITATIVE**, deliberadamente curada pelo Mind. Não é mirror de `speakers.json` nem do Summit.

Não criar tabelas de conceitos/construtos só porque a arquitetura prevê a casa. Criar quando houver necessidade real.

### 7.2 PRODUCT INTELLIGENCE

Verdade específica e atual do produto/evento.

No Summit, exemplos:

- evento;
- programação/sessões;
- participação em sessões;
- horários;
- locais;
- reservas;
- ingressos e inclusões;
- patrocinadores;
- regras específicas do evento.

### 7.3 OFFER / COMMERCIAL CURRENT REALITY

Preço, lote, checkout, regras comerciais e descontos correntes.

Para Summit, preço/lote/volume têm fonte operacional própria e mirror local. Fato comercial mutável não deve ser autorado manualmente se existe source operacional.

### 7.4 KNOWLEDGE

Conteúdo explicativo / long-tail: FAQs, explicações, logística em texto, materiais, transcrições e conteúdo contextual recuperado conforme a necessidade.

### Regra única

> **Uma casa por conceito.**

A topologia física é escondida do Agent pelo Kit Loader.

---

## 8. SOURCE → MIRROR — decisão congelada

A verdade pode nascer fora do `mind-agent`.

```text
SOURCE EXTERNA
→ SYNC / MIRROR LOCAL
→ KIT LOADER
→ AGENTE
```

Se nasce fora:

- a fonte externa continua source of truth;
- `mind-agent` mantém mirror local quando necessário;
- agentes consomem o mirror;
- o mirror nunca vira segunda fonte autoral.

Classificação canônica de proveniência:

- `SOURCE`;
- `MIRROR`;
- `LOCAL_AUTHORITATIVE`;
- `DERIVED`;
- `LEGACY_DUPLICATE`;
- `UNKNOWN`.

Classificar por **proveniência**, não por localização física.

> **NÃO ESTÁ NO MIND-AGENT ≠ NÃO EXISTE NO ECOSSISTEMA MIND.**

Antes de declarar lacuna, procurar sources relevantes acessíveis: outros Supabases, GitHub, site, Drive e sistemas operacionais pertinentes.

---

## 9. Retrieval e Kit Loader — decisões congeladas

### Structured authoritative first

> **ESTRUTURADO AUTORITATIVO PRIMEIRO. RAG SOMENTE PARA LONG-TAIL.**

Preço, checkout, desconto, inclusão, horário e disponibilidade nunca dependem de vector/RAG como fonte da verdade.

### Cadência por turno

```text
nova mensagem
→ AGENT_CONTEXT atualizado
→ rota
→ Capability Gate
→ Kit Loader
   → fatos autoritativos necessários agora
   → Intelligence perene relevante
   → Knowledge específico da necessidade
→ Decisioning
→ Agent
```

Se a verdade da source mudar, o próximo turno lê a verdade nova. Não manter contexto de produto gigante sincronizado dentro da conversa.

### LLM como retrieval planner

Decisão congelada:

- a LLM **pode** atuar como retrieval planner;
- ela decide **O QUE buscar**;
- ela **não decide QUAL É A VERDADE**;
- fatos são buscados deterministicamente em fontes autoritativas.

Modelo:

```text
MENSAGEM
→ interpretar a necessidade de retrieval
→ [LLM planner quando fizer sentido]
→ plano de retrieval
→ buscas determinísticas
→ evidências
→ Decisioning / Agent
```

Não usar uma LLM para mascarar um retriever mecanicamente ruim.

---

## 10. Source Registry / extensibilidade — decisão congelada

Objetivo: enriquecer Intelligence continuamente sem editar código do agente a cada novo conteúdo.

### Novo dado em fonte já registrada

```text
novo conteúdo / nova linha
na casa já registrada
→ zero mudança de código do agente
→ Kit Loader consegue encontrá-lo no próximo turno quando relevante
```

Exemplo: adicionar 20 FAQs à casa de FAQ já conhecida não exige deploy.

### Nova fonte / nova tabela

Nunca autoativar silenciosamente.

Fluxo aprovado:

```text
AUTO-DISCOVERY quando possível
→ pending
→ IA propõe classificação/configuração
→ humano APROVA / AJUSTA / IGNORA
→ Source Registry
→ Kit Loader passa a poder consumir
```

A IA pode interpretar estrutura e sugerir:

- conceito;
- produto/scope;
- natureza (`SOURCE`, `MIRROR`, `LOCAL_AUTHORITATIVE`, `DERIVED`);
- autoridade;
- como pode ser usada.

Mas uma tabela que apareceu não passa a responder clientes sozinha.

### Intelligence Inbox — futuro

Frontend futuro simples, orientado a negócio, para novas fontes/pendências.

Não construir agora. Primeiro o vendedor precisa funcionar.

---

## 11. Router — taxonomia congelada

Exatamente seis rotas:

- `summit_b2c`;
- `summit_b2b`;
- `institute`;
- `dash`;
- `cliente_suporte`;
- `concierge_summit`.

`ja_comprou` e `desconhecido` não são rotas.

Histórico, origem e CRM são evidências. Necessidade atual decide.

---

## 12. Capability Gate — decisões congeladas

`public.mind_rota_capacidade(rota, canal)` verifica se a rota correta é executável no runtime.

Razões canônicas, nesta precedência:

```text
missing_playbook > missing_kit > canal_incompativel
```

`needs_human` é semântica de necessidade, não transporte.

Estado relevante para o caminho crítico: `summit_b2b` permanece `missing_kit` enquanto a Intelligence B2B existir no banco mas não chegar de forma canônica ao runtime.

---

## 13. Handoff — decisão congelada

Transferir é último recurso, não primeira resposta.

`needs_human=true` quando há necessidade real: pedido explícito, erro de pagamento, reclamação séria, situação fora da política, ou dúvida que os dados não resolvem e trava a decisão.

Antes de transferir: entregar valor e recolher o que for útil.

Horário serve apenas para calibrar expectativa; nunca para negar uma transferência necessária.

O mecanismo concreto de handoff/ação é do Passo 14 e pode variar por canal/produto.

---

## 14. Roadmap de execução — checkpoint v2

### Regra da sequência

A numeração preserva a arquitetura original. Um passo pode ficar **aberto/deferido** quando a investigação já foi preservada e sua conclusão não bloqueia o caminho crítico. Não renumerar tudo por causa disso.

| # | passo | o que significa | estado |
|---|---|---|---|
| 1 | Ingestão + persistência + identidade universal | qualquer entrada vira conversa/mensagem e resolve identidade sem perder dado | ✅ FECHADO |
| 2 | Ponte Pessoa Mind ↔ CRM/HubSpot | mesma pessoa pode nascer dos dois lados e convergir em `pessoa_id` | ✅ FECHADO |
| 3 | Fila universal de resolução identidade/CRM | conflito persiste, não auto-merge | ✅ FECHADO |
| 4 | Coletor factual CRM | fatos do CRM acessíveis sem Decisioning | ✅ FECHADO |
| 5 | Compras + contexto comercial | histórico e realidade comercial entram no contexto factual | ✅ 5A FECHADO |
| 6 | Coletor factual de Engagement | IA + humano + histórico de interação entram como fatos | ✅ FECHADO |
| 6B | Normalização universal de áudio | áudio normalizado/transcrito na ingestão | ✅ FECHADO; confiabilidade/latência de transporte segue no backlog |
| 7 | Normalização determinística da pessoa | consolida realidade factual sem eleger vencedor arbitrário | ✅ FECHADO |
| 8 | `AGENT_CONTEXT` universal | contrato factual universal por turno | ✅ FECHADO |
| 9 | Testes de contrato do `AGENT_CONTEXT` | garante contrato estável | ✅ FECHADO |
| 10 | Router universal | escolhe competência conforme necessidade atual | ✅ FECHADO |
| 11 | Registry de rotas + Capability Gate | verifica playbook/kit/canal sem alterar rota | ✅ FECHADO |
| 12A | Auditoria/reforma Product Intelligence + Knowledge | provar sources, retrieval, duplicações e qualidade. Retrieval 12A.1 corrigido; investigação ampla preservada | ⏸️ PARCIAL / RESTANTE DEFERIDO para não bloquear vendedor |
| 12B | Source Registry mínimo + Kit Loader universal | rota recebe playbook + Intelligence/Knowledge/tools relevantes, sem conhecer topologia | 🚧 **PASSO ATUAL — investigação enviada ao Claude** |
| 13 | Finalizar cérebro de vendas Summit | Decisioning comercial B2C/B2B usando o Kit correto | ⬜ |
| 14 | Contrato universal de ação + handoff/escalation | transformar decisão em ação segura por canal | ⬜ |
| 15 | Análise pós-turno + memória universal | observar turno e atualizar Intelligence/memória interna | ⬜ |
| 15B | Write-back + dispatch operacional pós-turno | refletir mudanças em HubSpot/operação e despachar quando necessário | ⬜ |
| 16 | Continuidade / Silence | decidir retomada/follow-up sem confundir com turno síncrono | ⬜ |
| 17 | E2E vendas Summit via Treble | provar jornada real completa no primeiro sistema operacional | ⬜ |
| 18 | Hardening + documentação + travas Core Universal | reconciliar documentação, regressões estruturais e pendências que bloqueiem confiança do Core | ⬜ |

### Passo 12A — estado exato

Não considerar “não feito”. O que já foi investigado está preservado no `BACKLOG.md` §12.

12A.1 foi implementado/mergeado na PR #16: retrieval estruturado passou de conjunção rígida para disjunção + ranking; limitações conhecidas documentadas.

O restante do 12A foi conscientemente deferido porque completar palestrantes, conceitos, conteúdo de concierge e auditoria editorial agora impediria o vendedor de sair.

**12A continua aberto** e deve ser retomado sem redescoberta usando o checkpoint do backlog.

### Prioridade operacional atual

```text
SISTEMA EXTENSÍVEL
→ SOURCE REGISTRY + KIT LOADER MÍNIMO
→ INTELLIGENCE COMERCIAL MÍNIMA E CONFIÁVEL DO SUMMIT
→ DECISIONING DE VENDAS
→ AGENT
→ AÇÃO / HANDOFF
→ MEMÓRIA / WRITE-BACK / CONTINUIDADE
→ TREBLE E2E
→ VENDEDOR FUNCIONANDO
```

Não parar o caminho crítico para “completar o banco”. Conteúdo é enriquecido depois, na casa correta.

---

## 15. Conteúdo mínimo para o primeiro go-live de vendas

Não precisamos completar toda a Intelligence do Summit antes do vendedor.

Prioritário porque interfere na compra:

- o que é o Summit;
- diferença Mind × VIP × Prime;
- inclusões;
- preço vigente;
- checkout;
- lote;
- condições B2B/volume;
- programação suficiente para apoiar decisão de compra;
- reserva/agendamento quando interfere na compra;
- FAQs comerciais essenciais;
- políticas/limites necessários para não fazer promessa errada;
- critérios de handoff.

Conteúdo profundo de palestrantes, conceitos perenes e concierge não bloqueia o primeiro go-live, salvo se virar necessidade comercial real comprovada.

---

## 16. Como registrar qualquer coisa que decidirmos deixar para depois

**Obrigatório.** Se uma investigação descobrir algo relevante e a decisão for “não mexer agora”, registrar no `BACKLOG.md` antes de seguir.

Template mínimo:

```text
## <item> — DEFERIDO em <data>, descoberto no Passo <X>

POR QUE APARECEU
<qual problema/pergunta levou à descoberta>

O QUE JÁ FOI PROVADO
<tabelas/funções/números/evidências já levantadas>

ESTADO ATUAL
<o que funciona, o que está quebrado, o que não está concluído>

DECISÕES JÁ FECHADAS
<o que não precisa ser rediscutido>

POR QUE FOI DEFERIDO
<por que não é caminho crítico agora>

COMO RETOMAR
<a primeira verificação/mudança recomendada; sem reinvestigar tudo>

DEPENDÊNCIAS / GATILHO
<quando isso volta a ser necessário>
```

Exemplo real: confiabilidade/latência de áudio/transport Treble pode ser descoberta num passo e não ser a mudança atual. Registra-se o que já foi medido e o gatilho para retornar; não se abre uma frente lateral.

---

## 17. Checkpoint atual para uma IA sem contexto

Data: **29/08/2026**.

Último marco de código confirmado antes da documentação operacional:

- PR #16 mergeada;
- merge commit/main naquele marco: `cd551c802570e5358e6bcb55d702c539ba0fe28b`;
- depois disso houve commits apenas de documentação/checkpoint.

### Trabalho em andamento

Foi enviado ao Claude um prompt de **investigação apenas** do Passo 12B:

> investigar o menor `Source Registry + Kit Loader` que destrava `summit_b2c` e `summit_b2b`, mapear o runtime Router → Gate → LLM, explicar `missing_kit`, inventariar somente as fontes comerciais mínimas, avaliar estruturas existentes antes de criar registry, definir contrato mínimo do Kit Loader e decidir se LLM retrieval planner entra já ou depois.

**Não implementar enquanto essa investigação não voltar e for revisada.**

### Não fazer agora

- completar os palestrantes do Ecossistema;
- reparar `session_speakers`;
- reconstruir taxonomy/conceitos;
- construir frontend Intelligence Inbox;
- construir autodiscovery/cron completo;
- completar conteúdo do concierge;
- fazer auditoria editorial completa;
- criar RAG/vector sem necessidade real;
- abrir limpeza ampla de legado.

Tudo que já foi descoberto nessas frentes está no `BACKLOG.md` e deve ser reutilizado.

---

## 18. Decisões congeladas que devem continuar sendo registradas aqui

Este índice é deliberadamente curto. Quando uma nova decisão for aprovada como “congelada”, acrescentar ou ajustar apenas o bloco afetado:

- arquitetura Intelligence / Playbook / Decisioning / Agent;
- ordem do runtime;
- identidade canônica e resolução de conflitos;
- taxonomia de rotas;
- semântica do Capability Gate e `needs_human`;
- fronteira AGENT_CONTEXT × Product Intelligence;
- casas canônicas da Intelligence;
- SOURCE → MIRROR;
- Ecossistema como Intelligence perene/LOCAL_AUTHORITATIVE quando o Mind é autor;
- structured authoritative first / RAG long-tail;
- cadência de Kit por turno;
- LLM retrieval planner decide o que buscar, não a verdade;
- Source Registry: conteúdo novo automático na fonte registrada; fonte nova pending + aprovação;
- handoff por necessidade, não por horário;
- roadmap e ordem operacional;
- modo operacional de execução Adriana / ChatGPT / Claude Code / GitHub (§2B);
- merge em `main` é boundary de deploy: revisão/teste antes do merge, gate da Adriana antes do merge nos casos sensíveis (§2B, correção v4).

Se alguma dessas decisões mudar, **nova versão deste documento**.
