# Mind Agent — estado do projeto, arquitetura congelada e ordem de execução

> **Documento canônico de arquitetura e decisões congeladas.**
> Para o ponto exato de retomada operacional, leia primeiro **[`CHECKPOINT_ATUAL.md`](CHECKPOINT_ATUAL.md)**.
>
> **Versão do checkpoint arquitetural: v8 — 04/09/2026.**
>
> v8 reconcilia o documento com o sistema vivo: o Core agêntico unificado foi
> integrado e publicado; `mindagent-chat` está na v39, `treble-inbound-agent`
> na v38 e o go-live em lanes B/C/D/E deixou de ser a fila operacional atual.
> Os gates restantes são ativação externa e validação controlada, descritos em
> `CHECKPOINT_ATUAL.md`.
>
> v7 congela a correção de produto pedida pela Adriana: o App continua entrando como Concierge e usando momento do evento + contexto da pessoa, mas também pode vender quando houver intenção explícita de compra ou upgrade. O mesmo contrato de checkout atribuído vale no App e no WhatsApp e já nasce extensível para Institute e pré-venda do Summit seguinte quando essas ofertas oficiais entrarem nos Kits.
>
> v6 substitui duas partes desatualizadas de v5: (1) o modelo operacional vigente volta a refletir o workflow realmente usado — **ChatGPT arquiteto/supervisor + Claude Code executor + GitHub como memória/barramento**; (2) `Passo 12B` deixou de ser “passo atual”: Kit/Gate/Core já estão integrados e o go-live está em lanes B/C/D/E. v6 também explicita a diferença entre merge de migrations/app e publicação manual das Edge Functions neste repo sem `supabase/config.toml`.
>
> As decisões arquiteturais anteriores que não conflitam com v6 continuam vigentes.

---

## 1. Documentação canônica

Cada arquivo tem um papel. Não misturar:

| documento | responde |
|---|---|
| **`CHECKPOINT_ATUAL.md`** | Onde estamos exatamente agora? Quais PRs/HEADs/pendências? |
| **`PROJECT_STATE.md`** | Qual arquitetura, ordem e gates estão congelados? |
| **`GO_LIVE_PARALLEL_20260830.md`** | Quem é dono de cada capacidade durante o paralelo? |
| **`BACKLOG.md`** | O que foi investigado/deferido e não deve ser redescoberto? |
| **`docs/CORE_UNIVERSAL.md`** | O que já existe e funciona no sistema real? |

**Sistema real vence documentação desatualizada.** Uma decisão nova só fica congelada depois de registrada no Git.

`GO_LIVE_VENDEDOR_CONCIERGE_20260830.md` preserva o plano inicial/histórico da entrega; não usar sua checklist final como estado atual depois deste v6.

---

## 2. Ritual obrigatório

```text
INVESTIGAR
→ ENTENDER O QUE JÁ EXISTE
→ DECIDIR A MENOR MUDANÇA
→ IMPLEMENTAR
→ TESTAR SÓ O AFETADO
→ REGISTRAR O ESTADO FINAL/CHECKPOINT
→ CONTINUAR ATÉ E2E OU GATE REAL
```

Antes de alterar banco, função, prompt, integração ou estado:

- verificar infraestrutura real;
- separar vivo × legado × preparado em PR;
- identificar dependências;
- reaproveitar o que já resolve parte;
- escolher a menor mudança suficiente;
- apontar conclusão que contradiga a arquitetura imaginada.

### Proporcionalidade

Mudança pequena não vira revalidação ampla. Testar o que mudou e regressões diretamente afetadas. Não criar hardening, camada ou abstração para risco hipotético distante.

---

## 3. Modo operacional vigente — v6

- **Adriana** = dona de produto/negócio e dos gates sensíveis.
- **ChatGPT arquiteto/supervisor** = mantém o modelo mental, verifica GitHub/Supabase, fecha a menor mudança, coordena lanes, revisa PRs/testes, decide ordem de integração, mergeia quando permitido e registra checkpoints.
- **Claude Code** = investigador/executor escopado em branch `claude/...`; implementa o chunk fechado, testa o afetado, reporta evidência; não amplia escopo e não mergeia sozinho.
- **GitHub** = memória compartilhada e barramento entre lanes. Coordenação deve ir direto às issues/PRs, evitando Adriana como transporte humano.

Workflow:

```text
supervisão investiga/verifica
→ fecha menor mudança
→ Claude executa em branch/PR
→ supervisão revisa
→ corrige se necessário
→ integra/deploya no ponto seguro
→ verifica produção/E2E
→ documenta
→ segue
```

A lane é dona da **capacidade**, não de um único PR. PR verde não encerra lane; E2E ou gate real encerra.

---

## 4. Boundary de deploy

> **MERGE EM `main` É BOUNDARY DE DEPLOY, mas o efeito depende do componente.**

- root/app: integração Cloudflare pode publicar automaticamente no merge;
- migrations Supabase: integração pode aplicá-las no merge;
- Edge Functions em `supabase/functions/`: **não assumir publicação automática neste repo enquanto não houver `supabase/config.toml`**;
- `treble-inbound-agent` e `mindagent-chat`, no go-live atual, exigem deploy manual controlado depois do merge e comparação com a versão viva.

Revisão/teste antes do merge.

Gate explícito da Adriana antes de execução perigosa envolvendo:

- dados destrutivos/irreversíveis;
- identidade, auth, RLS, security, secrets;
- preço/desconto/regra comercial nova;
- source of truth;
- outbound/disparo;
- write-back material em CRM/operação sem contrato já fechado;
- mudança material de produto/comportamento não congelada.

Mudança aditiva/reversível já contratada pode seguir sem novo gate de negócio.

---

## 5. Propósito e arquitetura

Construir um **Core Universal de agentes do Mind** reutilizado por vendas, atendimento, concierge e futuros agentes, independentemente do canal.

Treble, app e web são adapters/superfícies; não são a arquitetura.

Quatro responsabilidades:

| camada | função |
|---|---|
| **INTELLIGENCE** | o que é verdade agora |
| **PLAYBOOK** | como um excelente profissional pensa/atua |
| **DECISIONING** | qual estratégia faz sentido agora |
| **AGENT** | o que efetivamente diz/faz |

> **PLAYBOOK DECIDE COMO PENSAR. INTELLIGENCE INFORMA O QUE É VERDADE AGORA.**

### App Concierge com venda contextual — CONGELADO em v7

- `mind_summit_app` continua abrindo em `concierge_summit`; não vira vendedor por padrão.
- Momento do evento e produtos/ingressos já conhecidos da pessoa orientam a resposta. Durante o Summit, programação, acesso e experiência continuam no Concierge.
- Havendo intenção explícita de compra ou upgrade, o App pode trocar a competência ativa para `summit_b2c` e emitir checkout oficial.
- WhatsApp e App só podem enviar um `checkout_url` que tenha vindo do Kit oficial. O runtime substitui o link por uma versão atribuída e registra canal, Agent, rota, motivo e conversa em `engagement.agente_eventos`.
- Institute e pré-venda do Summit seguinte serão vendáveis pelo Concierge quando suas ofertas, regras e URLs oficiais forem cadastradas nos Kits. Até isso acontecer, o Agent não cria URL, preço ou condição.

Coletor factual não decide, não pontua, não recomenda e não escreve.

---

## 6. Ordem canônica do runtime

```text
CANAL / ENTRADA
→ INGESTÃO
→ IDENTIDADE
→ AGENT_CONTEXT
→ ROUTER                         [somente quando rota não é autoritativamente conhecida]
→ CAPABILITY GATE
→ KIT DA ROTA
    ├── PLAYBOOK
    ├── PRODUCT INTELLIGENCE
    ├── ECOSSISTEMA / Intelligence perene
    ├── KNOWLEDGE relevante
    └── TOOLS / capabilities
→ DECISIONING
→ AGENT
→ AÇÃO / HANDOFF
→ ANÁLISE PÓS-TURNO + MEMÓRIA
→ WRITE-BACK / DISPATCH
→ CONTINUIDADE / SILENCE
```

Regras:

- identidade/contexto antes do Router;
- necessidade atual decide rota;
- rota autoritativa pode pular Router, **nunca o Gate**;
- Gate não muda rota, apenas diz se o runtime pode executá-la;
- `needs_human` = necessidade sem capacidade autônoma, não transporte;
- Kit é recomposto por turno;
- Product Intelligence não entra como blob persistente no `AGENT_CONTEXT`;
- memória da pessoa não vira segunda casa para fatos mutáveis do produto.

---

## 7. Identidade e casas canônicas

### Pessoa

`pessoas.pessoas.id` é a `pessoa_id` canônica. HubSpot/e-mail/WhatsApp/auth são identificadores/evidências, não IDs alternativos.

Conflito de identidade:

```text
detecta → persiste evidência → pendência idempotente → NÃO auto-merge → resolução humana
```

### Intelligence

**Ecossistema/perene**: conhecimento curado e reutilizável. `ecossistema.palestrantes_especialistas` é LOCAL_AUTHORITATIVE.

**Product Intelligence**: verdade atual do produto/evento — sessões, horários, locais, reservas, ingressos, inclusões etc.

**Commercial current reality**: preço, lote, checkout, volume e regras comerciais vigentes.

**Knowledge**: explicação/long-tail, FAQs, materiais e conteúdo recuperável.

> **Uma casa por conceito.**

Não criar tabela conceitual sem necessidade/consumidor real.

---

## 8. Source → mirror

```text
SOURCE EXTERNA
→ SYNC / MIRROR LOCAL
→ KIT LOADER
→ AGENTE
```

Se o fato nasce fora, a source externa continua source of truth. O mirror local não vira segunda fonte autoral.

Proveniência canônica:

- `SOURCE`;
- `MIRROR`;
- `LOCAL_AUTHORITATIVE`;
- `DERIVED`;
- `LEGACY_DUPLICATE`;
- `UNKNOWN`.

Antes de declarar lacuna, procurar fontes acessíveis relevantes. “Não está no mind-agent” não significa “não existe no ecossistema Mind”.

---

## 9. Retrieval / Kit / RAG

> **ESTRUTURADO AUTORITATIVO PRIMEIRO. RAG SOMENTE PARA LONG-TAIL.**

Preço, desconto, checkout, inclusão, horário e disponibilidade nunca dependem de vector/RAG como fonte da verdade.

A LLM pode decidir **o que buscar**; não decide **qual é a verdade**.

Kit Loader esconde topologia física. O Agent consome playbook + structured + knowledge + tools, não tabelas específicas.

Provider obrigatório:

- SQL `NULL` = não consegue entregar verdade mínima prometida;
- JSON não nulo = bloco disponível.

---

## 10. Router e Capability Gate

Rotas canônicas, exatamente seis:

- `summit_b2c`;
- `summit_b2b`;
- `institute`;
- `dash`;
- `cliente_suporte`;
- `concierge_summit`.

`ja_comprou` e `desconhecido` não são rotas.

O Gate `public.mind_rota_capacidade(rota, canal)` lê o playbook e `mind_kit_meta`.

Precedência de motivo:

```text
missing_playbook > missing_kit > canal_incompativel
```

O Gate não inventa rota nem estratégia.

---

## 11. Handoff

Transferir é último recurso, não primeira resposta.

`needs_human=true` por necessidade real, como:

- pedido explícito de humano;
- erro de pagamento;
- reclamação séria;
- situação fora da política;
- dúvida que os dados não resolvem e trava a decisão.

Antes de transferir: entregar valor e recolher o útil. Horário só calibra expectativa; não recusa handoff necessário.

### Troca de competência no App ≠ handoff humano — congelado em 02/09

São dois conceitos diferentes e não devem ser confundidos:

- **troca de competência** (`concierge_summit` ↔ `cliente_suporte`) acontece dentro do mesmo
  runtime, canal, pessoa, sessão e conversa. É o que o Passo 6 implementa;
- **handoff humano** é ação operacional posterior. O App **não tem** actuator de handoff
  humano confirmado equivalente ao `needs_human` do Treble; enquanto não houver transporte
  confirmado, o Agent não pode afirmar que transferiu para uma pessoa. `needs_human` do Treble
  não produz handoff no App e não deve ser reutilizado como se produzisse.

Estado da competência corrente mora em `engagement.conversas.variables.rota_ativa`. Não existe
tabela, coluna, conversa ou Router novo para handoff. `origem_codigo` permanece imutável como
**porta de entrada**; `rota_ativa` diz **quem está atendendo agora**.

Precedência da rota no turno, com Gate obrigatório depois de qualquer uma das três:

```text
ROTA ATIVA DA CONVERSA
> ROTA AUTORITATIVA DA ORIGEM
> ROUTER (só quando as anteriores não definem a competência)
```

O contrato Agent→runtime é `next_route`, cujo enum é montado em runtime a partir de
`mind_canal_rotas(<canal>)` — não existe segunda lista hardcoded de rotas permitidas. A troca
vale para o **próximo turno**: não se roda uma segunda LLM no mesmo turno só para trocar de
playbook. A persistência acontece dentro de `mindagent_chat_save_message`, na mesma transação
da gravação da mensagem, depois de revalidar a rota pelo Gate.

---

## 12. Memória / sensibilidade — decisões congeladas

- memória não pode ser exposta ao Agent sem validação de sensibilidade;
- taxonomia de sensibilidade reutiliza `intelligence.memoria_bloqueios.chave`; não criar segunda linguagem;
- `sensitivity='none'` marca item aprovado;
- item sensível, sem rótulo ou inválido é fail-closed nos writers sob contrato;
- legado v1 sem marcador permanece preservado e invisível ao coletor;
- `ativa` e `proposta` permanecem separadas;
- não aplicar regex de conteúdo como policy gate em domínio de saúde mental;
- C pode começar a emitir `sensitivity` antes de D entrar; RPC antiga ignora a chave JSON extra.

Congelado em 02/09, depois do Passo 5:

- **memória tem dois tempos e eles não se misturam.** `engagement.session_interests` é memória
  **rápida**, de sessão, e não promove nada para memória permanente; `intelligence.participante_memoria`
  é memória **durável** e só é escrita pelo analisador de pós-turno;
- o gate de sensibilidade dos writers deixou de ser comentário e passou a existir de fato:
  `mindagent_chat_save_interests` lê `sensitivity` e persiste apenas `none`; um item sensível é
  descartado sozinho, sem derrubar o resto do payload;
- em `analise_projetar_memoria`, o ramo `analise_concierge` exige `sensitivity='none'`, recusa
  `scope='temporary'` e promove `high` + (`stable`|`opportunity`) para `ativa`. A semântica dos
  demais analisadores permanece `stable + high → ativa`;
- não há corte arbitrário de quantidade de interesses no runtime. O volume real hoje é baixo
  (máx. 3 memórias ativas por pessoa); se crescer materialmente, seleção por relevância é outro
  problema, não um teto improvisado;
- memória durável só chega ao Agent por `mindagent_chat_get_context`, e só `status='ativa'` não
  expirada. `proposta` e `substituida` nunca vão para o modelo;
- **`analise_concierge` não é exclusivo do App**: o cron `analise_conversas` também o aplica a
  conversas de WhatsApp. Hoje o único leitor de `participante_memoria` é o App, mas quem mexer
  no analisador precisa contar com os dois canais.

---

## 13. Play — decisões congeladas

- v1 é **person-bound**: sem pessoa identificada, não grava NPS/feedback/insight;
- person-bound não significa “precisa ter conversado antes”; identidade Yazo válida pode entrar direto no Play;
- Play reutiliza o mesmo `mindagent-chat`, auth, sessão, bind de identidade e conversa;
- ações usam allowlist explícita; nome recebido do cliente nunca vira RPC dinâmica arbitrária;
- modo Play não chama OpenAI;
- slides/materiais não bloqueiam go-live até existir source canônico;
- não consertar `mindagent_bootstrap` pela metade se isso eliminar o fallback de temas que hoje funciona.

---

## 14. Estado do roadmap — v6

Core universal necessário ao go-live já passou do antigo Passo 12B.

### Fechado / em produção

- ingestão/identidade/CRM/Engagement;
- normalização factual + `AGENT_CONTEXT`;
- Router;
- Capability Gate;
- speakers/session links canônicos;
- Kit Loader mínimo;
- `mind_kit_evento` por correspondência real (#49).

### Em go-live paralelo agora

- **Lane B / #40 / PR #47** — Vendedor/Treble até E2E WhatsApp;
- **Lane C / #41 / PR #50** — Concierge/runtime até E2E app;
- **Lane D / #42 / PRs #46 + #51** — pós-turno/memória/write-back/Silence;
- **Lane E / #43 / PR #48** — Play/UI até E2E person-bound.

O estado exato, HEADs, renames e próxima ação de cada lane estão em `CHECKPOINT_ATUAL.md`.

### Ordem de integração atual

```text
B
→ C
→ D
→ E
→ E2E transversal
→ documentação final do sistema vivo
```

Trabalho independente pode ocorrer em paralelo. Integração respeita dependências e ordem de migration.

---

## 15. O que não sequestra o caminho crítico

Não abrir agora sem bloqueio real:

- completar toda a Intelligence;
- Intelligence Inbox/autodiscovery completo;
- taxonomia de conceitos sem consumidor;
- RAG/vector por elegância;
- limpeza ampla de legado;
- remoção física de compatibilidade só por estética;
- hardening hipotético;
- backend/identidade/session lifecycle paralelo;
- source falsa para materiais inexistentes.

Descoberta relevante deferida vai ao `BACKLOG.md` com evidência e gatilho de retomada.

---

## 16. Como uma IA nova retoma

1. leia `CHECKPOINT_ATUAL.md`;
2. leia este documento;
3. confira HEADs das PRs ativas citadas no checkpoint;
4. confira comentários mais recentes da issue dona;
5. verifique produção diretamente no trecho que será alterado;
6. execute o primeiro item pendente da lane;
7. não reinvestigue decisões já fechadas;
8. poste coordenação cross-lane diretamente no GitHub;
9. pare apenas em gate real de negócio/segurança.

Se uma decisão material aqui mudar, incremente a versão do `PROJECT_STATE.md` e diga explicitamente o que foi substituído.
