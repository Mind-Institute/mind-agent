# Core agêntico unificado — B2B, B2C e App

Estado deste documento: **implementado em `main` e publicado em produção**.
Snapshot de verificação: 04/09/2026; `mindagent-chat` v39 e
`treble-inbound-agent` v38.

## Decisão

Todos os agentes usam o mesmo pipeline e o mesmo runtime de Intelligence. Rota e canal
mudam o playbook, os fatos oficiais e as capacidades; não criam outra arquitetura.

```text
mensagem → Router → Gate → Kit compacto → LLM → tool loop → guardrails → ação/resposta
```

O Kit monta quatro camadas:

1. `base`: conduta transversal;
2. `playbook_<rota>`: competência e linguagem do produto;
3. `decisioning_vendas_universal`: decisão comercial comum a B2B e B2C;
4. `structured`: fatos oficiais mínimos para o turno.

O App e o WhatsApp consomem `kit.playbook`, `kit.structured` e `kit.tools`. O wrapper
`treble_agent_prompt` permanece apenas para consumidores legados e compõe as mesmas
camadas do registry.

Nas rotas `summit_b2b` e `summit_b2c`, o contato comercial é completado no início:
nome completo, e-mail, WhatsApp, empresa e cargo. O Core usa primeiro o que já existe,
grava cada novo dado em `pessoas.pessoas` e só libera calculadora, proposta ou checkout
depois do conjunto mínimo. O write-back comercial usa essa pessoa canônica para localizar,
criar ou enriquecer o Contact no HubSpot sem sobrescrever campos divergentes; depois liga o
`hubspot_id` por `engagement.identidades` e atualiza o Lead.

## Contexto pequeno e lupa

Preço, desconto, checkout, disponibilidade, categoria e regras comerciais sempre vêm do
`structured`. A lupa não pode substituir esses fatos.

Quando falta profundidade long-tail, o modelo pode chamar:

- `buscar_intelligence`: busca híbrida lexical + vetorial com escopo de rota, canal e produto;
- `ler_intelligence`: abre somente um candidato que continua permitido no mesmo escopo.

O Core permite duas rodadas de ferramentas e 30 segundos para o turno inteiro. Sem
ferramenta, o raciocínio fica em `none`; com lupa, sobe para `low` ou `medium` conforme a
complexidade. O modelo padrão dos dois runtimes é `gpt-5.4`.

## Indexação

`mind_knowledge_preparar_chunks` cria/atualiza chunks de 4.000 caracteres com 500 de
sobreposição. Mudança no hash do documento marca o chunk como `stale` e apaga o embedding.

A Edge interna `mindagent-index-knowledge`:

1. aceita somente `service_role`;
2. lê até 100 chunks pendentes de um schema permitido;
3. gera embeddings `text-embedding-3-small` com 1.536 dimensões;
4. grava por RPC escopada, sem SQL dinâmico vindo da requisição.

Schemas permitidos: `summit_2026`, `institute`, `dash` e `eventos`. A chamada deve ser
repetida enquanto `remaining=true`.

## Segurança

- ferramentas são uma allowlist estática e somente de leitura;
- RPCs de busca, leitura e indexação aceitam apenas `service_role`;
- documentos são filtrados por rota, produto, validade e aprovação do canal;
- `engagement.identidades`, `engagement.pessoa_perfil` e `engagement.treble_eventos`
  recebem RLS defensivo;
- nenhuma UTM ou ferramenta carrega PII.

## Avaliação

A migração registra cinco casos `core_v9_*` na casa já existente
`engagement.avaliacoes`: compra B2C após captura do contato, delegação B2B após captura do contato, argumento de
aprovação com lupa, concierge dentro do Summit e oferta futura sem fonte. As execuções
devem ser gravadas em `engagement.avaliacao_execucoes` no smoke de publicação; arquitetura
aprovada não substitui avaliação da resposta real.

## Ordem de publicação

1. aplicar `20260903110000_core_contexto_agentico_unificado.sql`;
2. publicar `mindagent-chat` com o shared `agent-intelligence.ts`;
3. publicar `treble-inbound-agent` com o mesmo shared;
4. publicar `mindagent-index-knowledge` com JWT obrigatório;
5. indexar os quatro schemas;
6. rodar contratos SQL, smoke App e smoke WhatsApp;
7. liberar tráfego somente depois dos dois canais passarem.

Rollback operacional: republicar as versões anteriores das duas Edges e reativar o bloco
de decisioning anterior do B2C. A migração é aditiva; os prompts e dados antigos não são
apagados.
