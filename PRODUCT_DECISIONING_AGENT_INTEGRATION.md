# Product Decisioning → Agents — integração viva

Status: **IMPLEMENTADO / TESTADO NO CONTRATO / FROZEN**  
Data: 2026-09-02

## Objetivo

Reutilizar o mesmo `product_decisioning` v2 nos Agents que realmente precisam escolher entre Summit, Institute e Dash, sem copiar sua lógica para playbooks de competência.

## Arquitetura final

```text
Customer Intelligence ─┐
Product Intelligence  ──┼→ Product Decisioning → Agent
Commercial Intelligence ┘                       → próximo passo permitido
```

As responsabilidades permanecem separadas:

- `agentes.prompts['playbook_<rota>']` = como a competência pensa e conversa;
- `agentes.prompts['product_decisioning']` = qual solução faz sentido para a transformação atual;
- `structured.customer_intelligence` = o que sabemos sobre a pessoa;
- `structured.product_intelligence` = o que cada solução realmente entrega;
- Commercial Intelligence = sellability atual, separada do fit.

## O que mudou

### 1. O Kit ganhou uma seção canônica `decisioning`

`agentes.kit_blocos.secao` passa a aceitar:

- `structured`;
- `knowledge`;
- `tools`;
- `decisioning`.

Registro vivo:

```text
rota: concierge_summit
bloco: product_decisioning
provider: agentes.prompts
secao: decisioning
obrigatorio: false
ativo: true
```

Nenhuma tabela nova.

### 2. `mind_agent_kit` devolve Decisioning separadamente

O Kit agora contém:

```text
playbook
 decisioning
structured
knowledge
tools
meta
```

`decisioning` é montado a partir dos prompts ativos registrados na seção `decisioning` do Kit.

### 3. Compatibilidade com o runtime atual do App

Na baseline desta implementação, a `mindagent-chat` v30 / `1.9.1` já usava
`kit.playbook` como o bundle de `instructions` enviado à OpenAI. A versão
operacional atual está em `CHECKPOINT_ATUAL.md`.

Para não fazer deploy de Edge apenas para renomear/compor campos, `mind_agent_kit` faz a composição por turno:

```text
base + playbook da competência + decisioning registrado
→ kit.playbook  [bundle de runtime]
```

Ao mesmo tempo:

```text
kit.decisioning
```

continua expondo a camada separadamente para auditoria e futuros runtimes.

**Isso não duplica o conteúdo no playbook-fonte.** `agentes.prompts['playbook_concierge_summit']` continua sem qualquer cópia de `product_decisioning`.

## Quem recebe Product Decisioning hoje

### `summit_b2c` / `summit_b2b`

Já recebiam `product_decisioning` pela composição `treble_agent_prompt(..., 'decisioning')`. Nenhuma mudança funcional nesta entrega.

### `concierge_summit`

Passa a receber `product_decisioning` v2 pelo Kit.

No mesmo turno, o Concierge dispõe de:

- `structured.customer_intelligence`;
- `structured.product_intelligence`;
- `decisioning` v2;
- playbook da competência;
- Intelligence e tools do Summit.

### `cliente_suporte`

**Não recebe Product Decisioning.** Atendimento resolve necessidade operacional; não é superfície de cross-sell/recomendação entre soluções.

### `institute` / `dash`

Não foram ligados nesta entrega. As rotas existem no registry, mas ainda não são Agents operacionais em canal real. Não antecipar wiring sem consumidor.

## Invariantes preservadas

- ICP não determina produto.
- JTBD não determina sozinho produto.
- Interesse temático não prova intenção de compra.
- `nenhuma` é recomendação válida.
- Fit vem antes de sellability.
- Produto vendável não substitui produto de melhor fit.
- Certificação Avançada não é upsell automático.
- Product Decisioning não roteia competência.
- Product Decisioning não foi copiado para playbook de Concierge.

## Migrations

- `20260902230159_kit_decisioning_section_concierge.sql`
- `20260902230319_kit_decisioning_runtime_compat.sql`

Ambas estão aplicadas em produção e versionadas na `main`.

## Testes

Contrato executado contra produção:

1. Kit do Concierge disponível.
2. `customer_intelligence` presente.
3. `product_intelligence` presente.
4. `kit.decisioning` contém Product Decisioning v2.
5. bundle consumido pelo runtime contém Product Decisioning v2.
6. `playbook_concierge_summit` fonte não contém o Decisioning.
7. Atendimento não recebe Decisioning.
8. Treble B2C continua recebendo Product Decisioning v2.

Teste versionado:

`tests/product_decisioning_agent_integration.sql`

## Estado final

Para os Agents vivos relevantes, a cadeia agora é:

```text
Customer Intelligence
+ Product Intelligence
+ necessidade/fala atual
+ Product Decisioning v2
→ Agent
```

Sem lookup rígido `ICP/JTBD → produto` e sem duplicação do Decisioning no playbook.

## Próximo passo

E2E de recomendação entre soluções com os cenários canônicos:

1. repertório/mobilização → Summit;
2. formação/aplicação de método → Institute;
3. diagnóstico/implementação organizacional → Dash;
4. múltiplos eixos integrados → Institute / Certificação quando houver evidência;
5. necessidade fora das capacidades → nenhuma recomendação;
6. tema ambíguo → uma pergunta discriminante.

Depois disso, fechar o E2E do vendedor Summit no WhatsApp e seguir para pós-conversa/write-back.
