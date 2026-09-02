# Customer Intelligence do Mind — Passo 4: extração, memória e consumo universal

Status: **IMPLEMENTADO E TESTADO EM PRODUÇÃO**  
Data: 2026-09-02  
Supabase: `ymnmotgglsrxmjmonwjz`  
Migration persistida na PR #54: `supabase/migrations/20260902140000_customer_intelligence_icp_jtbd.sql`  
Commit da branch da PR #54: `739dafa4ef3a4b4aaf40d2491198362a12c285ee`

Este passo implementa o contrato aprovado em:

- `CUSTOMER_INTELLIGENCE_STEP2_TAXONOMY.md`;
- `CUSTOMER_INTELLIGENCE_STEP3_CONTRACT.md`.

Não foi criada tabela nova, Edge Function nova, Router novo, pipeline paralelo de memória ou estado `job_prioritario_atual`.

---

# 1. Resultado arquitetural

Fluxo vivo:

```text
CONVERSA
  ↓
analisar-conversa
  ↓
analise_classificador
  ↓
analise_concierge quando houver Customer Intelligence útil
  ↓
intelligence.analise_conversa
  ↓
analise_projetar_memoria
  ↓
intelligence.participante_memoria
  ↓
mind_customer_intelligence(p_pessoa_id)
  ↓
mind_kit_customer_intelligence
  ↓
Kit da competência
  ↓
Agent / Decisioning
```

Regra preservada:

> Intelligence guarda o que sabemos sobre a pessoa.  
> Decisioning decide o que importa agora.

Portanto `status='ativa'` significa memória confiável/válida, não prioridade atual.

---

# 2. O que o sistema passou a aprender

## ICP

A memória existente passa a suportar:

```text
tipo  = icp
chave = icp_atual
```

Valores válidos são exatamente os seis valores oficiais da propriedade `icp` do HubSpot:

1. `CHRO / VP de Pessoas`
2. `CEO / C-Suite`
3. `Gestor / Middle Manager`
4. `People Leader / Business Partner`
5. `Executivo Sênior / Alto Performer`
6. `Consultor / Coach / Psicólogo`

Não foi criado slug/enumeration paralelo.

`lead_icp` (`ICP1`, `ICP3`, `ICP4`, `ICP6`) continua legado e não participa da classificação.

`icp_confianca` histórico continua sem uso porque os dados existentes misturam escalas 0–1 e 0–10. A escala interna de memória continua 0–1.

Uma classificação de ICP de alta confiança pode substituir a anterior usando o mecanismo já existente de `substituida/substituida_por`. Uma inferência ambígua não derruba um ICP ativo.

## JTBD

A mesma `intelligence.participante_memoria` passa a suportar:

```text
tipo  = jtbd
chave = jtbd:JT01 ... jtbd:JT15
```

O banco valida o código e canonicaliza o label, impedindo uma segunda linguagem para o mesmo job.

Cada JTBD guarda no `valor`:

- `code`;
- `text` canônico;
- `context` específico daquela pessoa;
- `scope`;
- `evidence_kind`;
- `sensitivity`.

Uma pessoa pode ter vários JTBDs ativos.

Não existe `job_prioritario_atual` persistido.

---

# 3. Evidência virou contrato executável

`public.analise_montar_contexto` agora inclui em cada item do transcrito:

- `mensagem_id`;
- `papel`;
- `conteudo`;
- `criado_em`.

O prompt `analise_concierge` exige `evidence_message_id` para cada item de `customer_memory`.

O writer `public.analise_projetar_memoria` valida a evidência no banco:

- o UUID precisa existir;
- precisa pertencer à mesma conversa da análise;
- precisa ser uma mensagem de `papel='lead'`.

Para `analise_concierge`, memória sem evidência válida é descartada **fail-closed**.

Assim, recomendação do Agent, fala do sistema ou UUID inventado não podem virar Customer Intelligence durável.

---

# 4. Sensibilidade

Permanece a regra fechada do projeto:

- somente `sensitivity='none'` pode virar memória durável pelo `analise_concierge`;
- `temporary` não vira memória durável;
- diagnóstico, medicação, afastamento, saúde pessoal do titular ou terceiro identificável e demais categorias sensíveis continuam bloqueados.

JT01 exige cuidado especial: um objetivo profissional de performance sustentável pode ser memória; uma condição/diagnóstico pessoal de saúde não.

---

# 5. Atualização/correção de JTBD

O contrato passou a suportar:

- `observe` — registra ou fortalece o job;
- `reject` — a própria pessoa diz explicitamente que aquele job não a descreve/foi entendido errado;
- `expire` — a própria pessoa diz que era uma necessidade anterior e deixou de valer.

Mudança simples de assunto não rejeita nem expira memória.

O leitor universal só devolve memórias `ativa` e não expiradas.

---

# 6. ICP do CRM entra no contexto correto

`public.analise_montar_contexto` agora entrega `crm.icp` ao pós-conversa além do antigo `lead_icp`.

O prompt foi instruído a:

- reconhecer `crm.icp` como a linguagem canônica;
- ignorar `lead_icp` para ICP/JTBD;
- não criar uma memória duplicada apenas para copiar o CRM;
- usar a conversa atual quando ela trouxer evidência mais nova/forte.

---

# 7. Leitor universal de Customer Intelligence

Criado:

`public.mind_customer_intelligence(p_pessoa_id uuid)`

É uma **projeção**, não uma nova fonte da verdade.

Lê casas existentes e devolve:

```text
professional_context
  role
  company
  icp

jobs_observed

goals
interests
preferences
constraints

decision_context
  stakeholders
  delegations
  relevant_constraints
```

Precedência do ICP:

```text
memória ativa atual
> CRM `icp`
> desconhecido
```

A confiança histórica inconsistente do HubSpot não é convertida por palpite.

A função não decide:

- prioridade atual;
- produto;
- próxima ação;
- estágio comercial.

---

# 8. Customer Intelligence entra pelo Kit, não por integrações separadas

Criado provider:

`public.mind_kit_customer_intelligence(p_conversa_id, p_necessidade)`

Bloco opcional `customer_intelligence` adicionado a:

- `concierge_summit`;
- `cliente_suporte`;
- `summit_b2c`;
- `summit_b2b`.

Isto foi deliberado:

```text
ROTA JÁ DECIDIDA
  ↓
KIT
  ↓
CUSTOMER INTELLIGENCE
```

O Router não recebe jobs antigos. Portanto memória histórica não passa a escolher a rota.

O bloco é opcional: conversa sem pessoa identificada não derruba o Kit.

Institute/Dash ainda não receberam bloco porque essas competências não têm o mesmo runtime/Kit executável fechado hoje. A função compartilhada já existe para ser reutilizada quando essas rotas entrarem.

---

# 9. Correção do perfil rápido do App

Antes deste passo, `mindagent-chat` lia toda memória ativa e a função `buildPersonalizationProfile` achatava tudo na lista `interesses`.

Isso passaria a transformar, por exemplo:

- objetivo → interesse;
- JTBD → interesse;
- ICP → interesse.

Para não criar uma segunda linguagem, `public.mindagent_chat_get_context` agora entrega em `memories` apenas `tipo='interesse'`.

ICP, JTBD, objetivos, preferências e restrições chegam preservando seu tipo no bloco estruturado `customer_intelligence` do Kit.

---

# 10. Prompt do analisador

`agentes.prompts['analise_concierge']` está em **versão 3**.

A versão 2 introduziu:

- ICP/JTBD;
- os 15 jobs canônicos;
- evidência por `mensagem_id`;
- `memory_action`;
- distinção interesse × JTBD;
- regras de sensibilidade.

No primeiro E2E real, a frase sintética `Sou HRBP...` gerou corretamente JT04 e JT05, mas o modelo guardou apenas `role=HRBP` e não emitiu ICP.

A versão 3 tornou explícitos apenas casos profissionalmente inequívocos, por exemplo:

- HRBP / HR Business Partner → `People Leader / Business Partner`;
- CHRO / Chief Human Resources Officer / VP de Pessoas / VP de RH → `CHRO / VP de Pessoas`;
- CEO → `CEO / C-Suite`;
- consultor corporativo/organizacional, coach executivo ou psicólogo corporativo explicitamente declarado → `Consultor / Coach / Psicólogo`.

Títulos genéricos (`gerente`, `diretor`, `head`, `líder`, `executivo`) continuam sem classificação forçada.

Cargo inequívoco pode gerar `role` **e** `icp`; um não substitui o outro.

---

# 11. Regra transversal dos Agents

`agentes.prompts['base']` recebeu a seção `CUSTOMER INTELLIGENCE`.

Todo Agent que receber o bloco deve:

- usar memória para evitar perguntas já respondidas;
- deixar a fala atual vencer memória antiga;
- não tratar memória ativa como prioridade atual;
- não inferir dor pelo ICP;
- não tratar `jobs_observed` como intenção de compra;
- nunca expor códigos internos `JTxx` nem apresentar a classificação ICP como rótulo técnico ao cliente.

---

# 12. Segurança diretamente afetada

O Security Advisor revelou que funções antigas do pós-conversa, embora `SECURITY DEFINER`, ainda eram executáveis por `anon/authenticated`.

Isto era especialmente material agora porque:

- `analise_montar_contexto` lê transcrito/CRM;
- `analise_gravar` pode escrever análise/memória;
- `analise_projetar_memoria` escreve Customer Intelligence;
- `analise_config` contém configuração interna do pipeline.

O Passo 4 fechou somente a cadeia diretamente afetada:

- `analise_config()`;
- `analise_prompt(text)`;
- `analise_pendentes(integer)`;
- `analise_montar_contexto(uuid)`;
- `analise_gravar(...)`;
- `analise_projetar_memoria(...)`;
- `mind_customer_intelligence(uuid)`;
- `mind_kit_customer_intelligence(uuid,jsonb)`.

Todas ficaram:

```text
anon            EXECUTE = false
authenticated   EXECUTE = false
service_role    EXECUTE = true
```

Outros warnings antigos do Advisor não foram tratados porque estão fora do escopo deste passo.

---

# 13. Testes proporcionais executados

## 13.1 Dry-run estrutural

Todo patch estrutural foi compilado primeiro em `BEGIN ... ROLLBACK`.

Após o patch simulado:

- Concierge Kit = disponível;
- Atendimento Kit = disponível;
- B2C Kit = disponível;
- B2B Kit = disponível.

## 13.2 Writer + leitor + Kit com dados sintéticos

Cenário sintético:

> `Sou HRBP. Preciso desenvolver os gestores que apoio e melhorar conversas difíceis.`

Foram projetados:

- ICP `People Leader / Business Partner`;
- JT04;
- JT05.

Uma tentativa de gravar JT06 usando como “evidência” a mensagem do Agent foi bloqueada.

Validado:

- os dois JTBDs foram canonicalizados pelo banco;
- `evidencia_message_id` ficou ligado à fala do lead;
- `mind_customer_intelligence` devolveu ICP + 2 jobs;
- o Kit Concierge carregou `customer_intelligence` preservando os tipos;
- uma correção explícita rejeitou JT05;
- o leitor então devolveu somente JT04.

Teste: **PASS**.

Dados sintéticos removidos ao final; `cleanup_ok=true`.

## 13.3 E2E real do pós-conversa

A mesma necessidade foi enviada ao Edge `analisar-conversa` vivo.

Primeira rodada:

- HTTP 200;
- ~3,9 s;
- classificador escolheu somente `analise_concierge`;
- JT04 e JT05 gravados com evidência correta;
- `role=HRBP` gravado;
- ICP não emitido.

Após ajuste conservador de cargos inequívocos (prompt v3), nova rodada:

- HTTP 200;
- ~3,8 s;
- classificador novamente `analise_concierge`;
- leitor final retornou `People Leader / Business Partner` + 2 JTBDs.

## 13.4 Quatro Kits

Após implementação definitiva:

- `concierge_summit` = verde;
- `cliente_suporte` = verde;
- `summit_b2c` = verde;
- `summit_b2b` = verde;
- exatamente quatro blocos opcionais `customer_intelligence` ativos.

## 13.5 CRM

Validado que `analise_montar_contexto` consegue expor `crm.icp` canônico quando ele existe no espelho.

## 13.6 Advisors

Security Advisor e Performance Advisor foram executados.

- as funções novas têm ACL restrita a `service_role`;
- os warnings de acesso da cadeia de pós-conversa diretamente afetada foram corrigidos por `REVOKE/GRANT` explícito;
- os demais warnings do projeto são preexistentes e não foram transformados em escopo desta entrega;
- nenhum índice/tabela nova foi criado por este passo.

---

# 14. O que este passo NÃO faz

Não implementado de propósito:

- Product Intelligence de Institute/Dash;
- fit JTBD ↔ produto;
- escolha automática de produto;
- writeback de ICP/JTBD para HubSpot;
- normalização histórica de `icp_confianca`;
- migração de `lead_icp` legado;
- analytics/conversion reporting por JTBD;
- tabela de JTBD;
- `participante_objetivos`/`recomendacoes`/`sinais_comerciais` como novas casas;
- prioridade persistida de job.

Esses temas pertencem aos próximos passos já definidos no plano.

---

# 15. Próximo passo

Com Customer Intelligence agora aprendendo e chegando estruturada aos Agents, o próximo passo do plano é:

**PASSO 5 — completar Product Intelligence do Mind.**

Objetivo: tornar recuperável, em fonte atual e compartilhada, o que Summit, Institute, Dash e demais soluções realmente oferecem — separando capacidades/posicionamento de verdade comercial atual.

Só depois vem o fit JTBD ↔ soluções e o Decisioning de próxima etapa.
