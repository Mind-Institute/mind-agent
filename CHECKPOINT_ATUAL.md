# CHECKPOINT ATUAL — go-live Vendedor + Concierge

> **Leia este arquivo primeiro se estiver entrando no projeto sem contexto.**
>
> Data do checkpoint: **30/08/2026 à noite** (eventos do GitHub já aparecem em 31/08 UTC).
> Base de `main` no momento em que este checkpoint foi escrito: **`a226e2888d029b1fd661795b16c18a9dc02a6dac`**.
>
> Este arquivo é o ponto de retomada operacional. `PROJECT_STATE.md` preserva a arquitetura/decisões congeladas; `BACKLOG.md` preserva investigações deferidas; `docs/CORE_UNIVERSAL.md` descreve o sistema que já está vivo. PRs drafts descrevem código ainda não integrado.

---

## 1. O objetivo agora

Fechar dois produtos sobre o mesmo Core:

1. **Vendedor Summit** no Treble/WhatsApp, B2C e B2B, com Router → Gate → Kit → Decisioning/Agent → resposta/handoff e preço/regra comercial sem invenção.
2. **Concierge Summit + Play** no app, com programação/palestrantes/recomendação factual, actions person-bound (NPS/feedback/insight) e o mesmo runtime/identidade — sem backend paralelo.

As lanes continuam donas da capacidade **até o E2E real**, não até o primeiro PR.

---

## 2. O que já está fechado em `main` e produção

### Core / Lane A — concluída

Já estão integrados e verificados:

- speakers canônicos: **81/81 vínculos**, 63 pessoas, 60 sessões; zero `speaker_id` nulo/duplicado;
- Kit Loader universal mínimo (#36): `mind_kit_meta` + `mind_agent_kit`;
- Capability Gate lendo o Kit real (#44);
- correção do provider `mind_kit_evento` (#49), resolvendo produto pela correspondência `evento.produto_codigo = catalogo.produtos.codigo`;
- #49 mergeada em `main` no commit **`a226e288...`** e já refletida no Supabase;
- ledger de produção observado após #49: **285 migrations**;
- `summit_b2c` e `summit_b2b` em `whatsapp`: Gate/Kit disponíveis com os blocos obrigatórios.

A Lane A pode ser considerada encerrada.

---

## 3. Lanes ativas — estado exato e próximo passo

### Lane B — Vendedor Summit / Treble

**Issue:** #40  
**PR:** #47 — draft  
**Branch:** `claude/go-live-vendedor-runtime-hjobov`  
**HEAD atual:** **`0a35d1a5c14d8e79e3a83ccdfe0ae3f9c7b27f0f`**

O que já está feito na branch:

- runtime `treble-inbound-agent` v1.4.0 preparado para Router → Gate → Kit;
- Gate roda para qualquer rota decidida; execução comercial continua só B2C/B2B;
- clarify não cria audience paralela;
- chamada morta `mind_lead_capturar` removida, sem criar writer substituto;
- guardrail comercial evoluiu até validar **papel + faixa + experiência**, incluindo percentual e centavos;
- fixture espelha o Kit comercial vivo: 3 experiências, 3 ofertas vigentes e 12 linhas de preço por volume;
- **71/71 contratos do guardrail** + `tsc --strict` limpo;
- branch sincronizada com #49; dependências Core estão em produção;
- flag `treble.config.core_rota_kit` continua desligado;
- Edge Function ainda não foi publicada.

**Última correção pendente antes do gate de merge:** o smoke ainda hardcodava um telefone que coincide com contato real no CRM. A supervisão mandou:

1. remover telefone hardcoded;
2. exigir `TREBLE_SMOKE_CELLPHONE` para rodar;
3. usar explicitamente um WhatsApp controlado de teste;
4. não tentar limpar pessoa/identidade/CRM automaticamente;
5. atualizar o corpo da PR para 71/71 e fixture real.

Depois disso: `node --check` do smoke + guardrail + `tsc --strict`. Se passar, encerra revisão estática.

**Sequência da Lane B depois disso:** Ready → merge → confirmar migration → comparar function versionada com a viva → deploy manual da `treble-inbound-agent` → ligar `core_rota_kit` → smoke E2E real no WhatsApp. **HTTP 200 não basta: a mensagem precisa chegar no aparelho.** Se a Treble não entregar, flag volta para `false` sem redeploy.

---

### Lane C — Concierge Summit / runtime canônico

**Issue:** #41  
**PR:** #50 — draft  
**Branch:** `claude/go-live-concierge`  
**HEAD atual:** **`06c428c49db9e34558d39012d12126a5af5e5b75`**

O que já está feito na branch:

- `mindagent_chat_search` reformado para Sonja/nome parcial, temas, dia/faixa/hora, múltiplos dias, minuto real e nested speaker sessions;
- provider `mind_kit_programacao(event_slug, pergunta, interesses)`; pergunta seleciona, interesses só reordenam;
- playbook v7 copiado **byte a byte** para `agentes.prompts['playbook_concierge_summit']`;
- Kit `concierge_summit` com blocos `evento` + `programacao`;
- SQL/retrieval/Kit: **17 contratos** em `BEGIN/ROLLBACK` contra produção;
- Edge viva v23 foi versionada no repo em `supabase/functions/mindagent-chat/index.ts` e o wiring novo foi aplicado por cima;
- runtime passa por auth/sessão/bind/contexto → salva fala do usuário → Gate → Kit → OpenAI;
- sem Router no app dedicado;
- fail-closed sem Kit/playbook/blocos;
- `sensitivity` obrigatório no structured output de cada interest, enum `none` + 10 chaves existentes, repassado intacto à RPC;
- modo Play no **mesmo** `mindagent-chat`: sessão/identidade compartilhadas, allowlist explícita de tools, sem OpenAI no modo action;
- pessoa Yazo identificada pode entrar direto no Play sem conversa anterior; sem `pessoa_id`, coleta não executa;
- `npm run test:edge`: **19/19**; `tsc --noEmit` limpo;
- Edge **não publicada**.

Compatibilidade cross-lane já fechada: é correto a Edge C começar a enviar `sensitivity` **antes** do gate SQL da Lane D. A RPC atual recebe JSON e ignora a chave extra; depois #51 passa a exigir/gatear.

**Próximo passo:** revisão final do diff runtime + merge controlado das migrations/código → confirmar DB vivo → publicar `mindagent-chat` manualmente do commit aprovado → E2E real no app. O repo não tem `supabase/config.toml`, então merge **não** publica essa Edge Function automaticamente.

Não insistir em branch paga/preview Supabase para #50; o SQL já foi provado transacionalmente contra produção.

---

### Lane D — pós-turno / memória / write-back / Silence

**Issue:** #42  
**PR #46:** coletor de memória — draft — HEAD **`d6a9fd9e5265989c1147a44b8345c551a4de26e2`**  
**PR #51:** memória sensível + D1/D2 — draft — HEAD **`5712fe027531a42a5f057695b7c8d83deff40c60`**

O que já está feito:

- `mind_memoria_fatos(pessoa_id)` pronto e desligado;
- coletor só expõe linha marcada com `valor.sensitivity='none'`; legado v1 permanece fisicamente preservado e invisível ao Agent;
- `analise_vendas_summit` v2 passa a emitir `sensitivity`;
- `analise_projetar_memoria` fail-closed **somente para o analisador sob contrato**;
- revalidação de mesmo texto adiciona marcador sem duplicar;
- substituição `ativa → ativa` de identidade/cargo/empresa corrigida;
- `mindagent_chat_save_interests` passa pelo mesmo gate **antes** de `session_interests` e também marca memória/perfil seguro;
- Silence D1 corrigido no contrato e D2 no motor (`followup_exhausted` exige `followup_count > 0`);
- #51: **11 contratos** em transação revertida;
- #46: **9 contratos** do coletor em transação revertida;
- produção permanece sem esse gate/coletor; cron 13/outbound continua desligado.

**Correção pendente já ordenada pela supervisão:** a versão da migration da #46 precisa mudar porque C ganhou uma migration posterior.

Renomear, sem mudar conteúdo:

```text
20260830230000_15_mind_memoria_fatos.sql
→ 20260830234000_15_mind_memoria_fatos.sql
```

Depois rodar somente os 9 contratos da #46 em `BEGIN/ROLLBACK` e atualizar os corpos de #46/#51 para o estado real.

Depois da integração C, a Lane D **continua**: wiring seguro de leitura da memória no runtime correto, pós-turno do Concierge, write-back realmente necessário dentro do gate de CRM/source-of-truth e continuidade/Silence até o limite permitido pelo gate de outbound. **Não ligar cron 13 nem outbound sem gate explícito.**

---

### Lane E — Play / experiência do Concierge

**Issue:** #43  
**PR:** #48 — draft  
**Branch:** `claude/go-live-play-labrz9`  
**HEAD atual:** **`2a08e26eb756dc9d33b5aa307710fc15cc3a256d`**

O que já está feito na branch:

- writers person-bound `mind_play_feedback_sessao`, `mind_play_nps`, `mind_play_feedback_evento`, `mind_play_feedback` + agregado;
- casas existentes reutilizadas; zero tabela/coluna nova;
- UI real do app passou a tentar persistir insight/nota/NPS e não dizer “Guardei” quando não gravou;
- Play não exige conversa prévia; reusa auth/sessão/identidade do chat;
- v1 **não aceita feedback/NPS anônimo**;
- slides/materiais deferidos até existir source canônico; não bloqueiam go-live;
- contrato do cliente já é compatível com o executor Play implementado na #50;
- testes SQL 9 contratos; navegador real **8 contratos** no estado reportado da PR.

**Correção pendente já ordenada:** a migration da E precisa ser a última da sequência atual. Renomear, sem mudar conteúdo:

```text
20260830231500_lane_e_play_coleta.sql
→ 20260830235000_lane_e_play_coleta.sql
```

Depois, sincronizar com o contrato final da #50, apontar `CONFIG.playActionUrl` para a mesma Edge `mindagent-chat` quando ela estiver publicada e executar E2E real: pessoa identificada, sem conversa anterior, entra direto no Play e registra uma coleta person-bound nas casas canônicas.

Não consertar `mindagent_bootstrap` pela metade: o fallback local hoje preserva temas que o banco ainda não consegue devolver sem regressão. `mindagent_chat_search` já devolve UUID canônico de sessão no caminho do Concierge; use o menor vínculo que não destrua o que funciona.

---

## 4. Ordem de migrations que deve chegar ao `main`

A ordem precisa refletir a integração e evitar out-of-order:

```text
#47 B   20260830210000
#49 A   20260830220000   [JÁ EM MAIN/PROD]
#50 C   20260830223000
#50 C   20260830233000
#46 D   20260830234000   [rename pendente]
#51 D   20260830234500
#48 E   20260830235000   [rename pendente]
```

Não crie migration duplicada só para corrigir número de uma migration que nunca chegou a produção.

---

## 5. Ordem de integração/deploy a partir daqui

```text
B — fechar correção do smoke → merge → deploy manual Edge → flag → E2E WhatsApp
→ C — review final → migrations → DB live → deploy manual mindagent-chat → E2E Concierge
→ D — migrations seguras → wiring pós-turno/memória/write-back/continuidade dentro dos gates
→ E — migration + UI integrada ao executor C → E2E Play
→ E2E transversal Vendedor + Concierge + Play
→ documentação final do Core/Backlog
```

**Ordem de deploy ≠ ordem de trabalho.** D/E podem corrigir renames/docs enquanto B/C fecham, mas não antecipar dependência material.

---

## 6. Gates que continuam valendo

Exigem Adriana/decisão explícita antes da execução perigosa:

- mudança de preço, desconto ou regra comercial;
- alteração destrutiva/irreversível de dados;
- auth/RLS/security/secrets/identidade;
- source of truth;
- outbound/disparo, inclusive ligar cron 13 do Silence;
- write-back material em CRM quando muda estado operacional sem contrato já fechado;
- mudança de produto/comportamento material não congelada.

Já fechado e **não** precisa voltar para Adriana:

- regra comercial atual do vendedor exatamente como as regras/playbooks ativos;
- Router com seis rotas;
- Gate/Kit semantics;
- person-bound para Play v1;
- slides deferidos;
- `sensitivity` com taxonomia existente e gate fail-closed;
- `concierge.prompts` fica intacta/histórica por enquanto;
- C pode emitir `sensitivity` antes de D estar live;
- `mind_lead_capturar` não deve ser criada.

---

## 7. Coisas que NÃO devem ser reabertas agora

- completar toda a Intelligence do Summit;
- taxonomia conceitual nova;
- RAG/vector sem necessidade real;
- Intelligence Inbox/autodiscovery;
- apagar legado só por estética;
- criar segunda identidade/backend/session lifecycle para Play;
- reintroduzir `schema_dados` como proxy no `mind_kit_evento`;
- criar `mind_lead_capturar`;
- ligar outbound/Silence antes do gate;
- criar fonte falsa para slides/materiais;
- “consertar” bootstrap entregando `temas=[]` e quebrando o fallback que funciona.

---

## 8. Se você for uma IA nova entrando agora

Faça nesta ordem:

1. leia este arquivo;
2. leia `PROJECT_STATE.md` para arquitetura e decisões congeladas;
3. leia `GO_LIVE_PARALLEL_20260830.md` para ownership das lanes;
4. leia `BACKLOG.md` apenas para a frente que você vai tocar;
5. leia `docs/CORE_UNIVERSAL.md` para o que já está vivo;
6. confira no GitHub os HEADs atuais das PRs #47/#50/#46/#51/#48 — **HEAD de PR é mais fresco que este texto**;
7. confira produção antes de qualquer merge/deploy;
8. retome exatamente do primeiro item pendente da lane relevante, sem reinvestigar decisões já fechadas.

### Regra de transporte

GitHub é o barramento compartilhado. Cada lane deve postar checkpoint/coordenação na issue dona (#40–#43). Não use Adriana como mensageira entre lanes quando um comentário direto resolve.

### Regra de parada

A lane só está pronta quando a capacidade funciona E2E ou chegou a um gate real de negócio/segurança. “PR existe”, “checks verdes” ou “primeiro chunk pronto” não encerram a lane.
