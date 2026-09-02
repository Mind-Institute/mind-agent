# Prompt para Claude Code — implementar Passos 5 e 6 do Concierge Mind Summit

Você vai implementar **somente** os Passos 5 e 6 já fechados do Concierge Mind Summit 2026.

Não redesenhe arquitetura. Não crie novas frentes. Não altere nada além do necessário para estes dois passos e das regressões diretamente afetadas.

## 0. Antes de qualquer mudança: investigue e reconcilie o estado real

Leia primeiro, nesta ordem:

1. `AGENTS.md`
2. `CHECKPOINT_ATUAL.md`
3. `PROJECT_STATE.md`
4. `docs/CORE_UNIVERSAL.md`
5. `MAPA_DO_SISTEMA.md`
6. `SUMMIT_2026_CANON_AGENTES.md`
7. `SUMMIT_2026_EXECUTION_RUNBOOK.md`
8. `SUMMIT_2026_STEP5_PROMPTS_SPEC.md`
9. `SUMMIT_2026_STEP5_MEMORY_ADDENDUM.md`
10. `SUMMIT_2026_STEP6_HANDOFF_SPEC.md`

O adendo de memória prevalece sobre trechos conflitantes da spec do Passo 5.

### Trava crítica: live ≠ main

Foi verificado em 2026-09-02:

- Supabase produção `mindagent-chat`: **v28 / VERSION 1.8.0**;
- GitHub `main` `supabase/functions/mindagent-chat/index.ts`: **VERSION 1.5.0**.

Não edite/deploy a partir do `main` 1.5.0 como se fosse a produção: isso causaria regressão.

Primeiro:

1. busque o código **vivo** das Edge Functions afetadas;
2. compare com repo/branches;
3. reconcilie o código vivo 1.8.0 para a branch de trabalho sem perder nenhuma mudança posterior a 1.5.0;
4. só depois aplique o delta deste prompt.

Não altere produção durante a investigação.

---

# 1. Constraints fechadas

Preserve estas decisões:

- INTELLIGENCE = verdade atual.
- PLAYBOOK = como pensar/agir.
- DECISIONING = estratégia quando aplicável.
- AGENT = o que diz/faz.
- Não recriar `Executor` comportamental.
- App oficial entra por `mind_summit_app → concierge_summit` sem Router.
- Gate continua obrigatório.
- `mindagent-web` permite somente `concierge_summit` e `cliente_suporte` conforme `agentes.canal_competencia`.
- Concierge não lê nem terá leitura sistêmica de `Minha Agenda`.
- Concierge não reserva, cancela, agenda, favorita, altera perfil/agenda nem faz check-in.
- Agenda pessoal só existe para o Concierge quando a própria pessoa conta.
- Categoria de ingresso virá da Intelligence/credenciamento; não crie sistema paralelo de ingresso.
- Falta de informação sozinha NÃO é critério de handoff.
- Atendimento pode oferecer upgrade/novo ingresso quando isso resolve o problema.
- Menor upgrade suficiente: Mind→workshop = VIP; VIP→Masterclass = Prime; Mind→Masterclass = Prime.
- Upgrade dá elegibilidade, não garante vaga em sessão.
- Percentual vendido oficial pode ser informado; quantidade absoluta restante nunca.
- `Arena Sextante` é o nome correto.
- O item de certificado agora se chama **`Certificado das Masterclasses realizadas`**. Ele nunca foi benefício de Mind/VIP: nessas categorias permanece `—`; em Prime é `Com scan de entrada`.
- Não tocar agora na pendência de Knowledge institucional geral (Mind Institute, Mind Dash, Mind Summit, soluções do Mind). Ela está separada e não bloqueia estes passos.

---

# 2. PASSO 5 — Prompts finais

Use **exatamente como fonte de contrato** os textos de:

- `SUMMIT_2026_STEP5_PROMPTS_SPEC.md`
- `SUMMIT_2026_STEP5_MEMORY_ADDENDUM.md`

Implementar em `agentes.prompts`:

1. atualizar `base`;
2. atualizar `playbook_concierge_summit`;
3. atualizar `playbook_cliente_suporte`;
4. criar/ativar `analise_concierge`.

Não copie fatos estáticos do Summit para os playbooks. Eles já pertencem à Intelligence.

Não mexa em `analise_classificador`: foi verificado que a versão viva já conhece `analise_concierge` e pode combiná-lo com vendas/atendimento.

---

# 3. PASSO 5 — Memória rápida

## 3.1 `mindagent-chat` RESPONSE_SCHEMA

No código vivo 1.8.0, hoje ainda existem:

- `interests.maxItems = 2`;
- descrição “no máximo dois”;
- campo `confirmed`;
- `.slice(0,2)` após a resposta.

Mudar para:

- remover `maxItems: 2`;
- remover qualquer limite comportamental artificial de quantidade;
- remover `confirmed` do tipo/schema/required e do pipeline rápido;
- manter `key`, `label`, `confidence`, `sensitivity`;
- `interests` = todos os interesses profissionais/de conteúdo úteis realmente revelados no turno;
- não inventar interesse a partir de conteúdo apenas citado pelo Agent/Intelligence.

Remover `.slice(0,2)`.

## 3.2 `mindagent_chat_save_interests`

Hoje a função viva:

- rejeita payload >5;
- limita a sessão a 12;
- limita permanentes a 8;
- promove permanente via `confirmed=true`;
- apesar do comentário no runtime, **não valida `sensitivity`**.

Mudar para:

- remover limite >5;
- remover teto 12 por sessão;
- writer fica apenas com `engagement.session_interests`;
- remover toda promoção para `intelligence.participante_memoria` e toda escrita em `participante_contexto` deste writer;
- deduplicação por chave permanece;
- confidence mínima razoável permanece;
- ler `sensitivity` de cada item;
- somente `sensitivity='none'` pode ser salvo;
- qualquer valor ausente/desconhecido/diferente de `none` deve ser descartado deterministicamente;
- um item bloqueado não deve impedir os demais itens permitidos de serem gravados.

Não criar tabela nova.

---

# 4. PASSO 5 — Memória durável

## 4.1 `analise_concierge`

Criar o prompt exatamente conforme `SUMMIT_2026_STEP5_PROMPTS_SPEC.md`, com a extensão obrigatória de `SUMMIT_2026_STEP5_MEMORY_ADDENDUM.md`:

cada `customer_memory` deve incluir também `sensitivity` usando a mesma taxonomia do runtime.

Somente memória permitida deve sair com `sensitivity=none`; na dúvida, classificar para o lado bloqueado.

## 4.2 `analise_projetar_memoria`

Não mudar a semântica dos outros analisadores neste passo.

Quando `p_analisador = 'analise_concierge'`:

- exigir `sensitivity='none'`; ausente/outro → não persistir;
- `scope='temporary'` → não projetar como memória durável;
- `confidence='high'` + `scope in ('stable','opportunity')` → `status='ativa'`;
- medium/low → `status='proposta'`;
- manter deduplicação e substituição atual.

Isso é necessário porque um interesse explícito do Summit normalmente é `opportunity`, e não pode ficar inutilizado como `proposta` apenas por não ser “stable”.

---

# 5. PASSO 5 — Read path da memória

Foi verificado ao vivo:

- `analise_projetar_memoria` grava `intelligence.participante_memoria`;
- `mindagent_chat_get_context` não lê essa tabela;
- não existe outro reader canônico de `participante_memoria`;
- volume real atual ativo/não expirado: máximo 3 memórias por pessoa, p95=3.

Portanto, sem criar nova função:

## 5.1 Estender `mindagent_chat_get_context`

Quando houver participante, devolver todas as memórias:

```sql
status = 'ativa'
and (valido_ate is null or valido_ate > now())
```

Não devolver `proposta` nem `substituida` para o Agent.

Normalizar valor textual aceitando histórico:

- `valor->>'text'`
- fallback `valor->>'label'`

Retornar pelo menos:

- `type/tipo`;
- `key/chave`;
- `value` textual;
- `scope` quando existir;
- `confidence`.

## 5.2 Runtime

Montar o `personalization_profile` usando:

- nome/cargo/empresa;
- session interests;
- memória durável ativa;
- `participante_contexto.temas_relevantes` somente enquanto necessário por compatibilidade.

Remover cortes arbitrários:

- `.slice(0,8)` no perfil;
- `.slice(0,3)` antes de enviar interesses ao Kit.

Deduplicar conceitos/chaves equivalentes.

Enviar todos os interesses permitidos ao Kit. **Não alterar `mind_kit_programacao`**: foi verificado que ele já aceita todo o array e só usa interesses para reordenar sessões já selecionadas pela pergunta.

Não despejar memória `proposta` nem sensível no modelo.

---

# 6. PASSO 6 — Handoff Concierge ↔ Atendimento

Implementar exatamente a arquitetura de `SUMMIT_2026_STEP6_HANDOFF_SPEC.md`.

## 6.1 Não recolocar Router no App oficial

Precedência do turno:

```text
rota_ativa persistida e válida
> rota autoritativa da origem (`mind_summit_app → concierge_summit`)
> Router somente quando nenhuma das anteriores define a competência
```

Sempre passar pelo Gate.

## 6.2 Estado

Usar:

```text
engagement.conversas.variables.rota_ativa
```

Não criar:

- tabela;
- coluna;
- nova conversa;
- nova sessão;
- nova taxonomia.

`origem_codigo` continua imutável como porta de entrada.

## 6.3 Output do Agent

Adicionar ao RESPONSE_SCHEMA:

```text
next_route: <rota canônica permitida no mindagent-web> | null
```

Não hardcode uma segunda lista de rotas. Monte o enum a partir de:

```text
public.mind_canal_rotas('mindagent-web')
```

Regras:

- null = permanece;
- mesma rota atual = normalizar para sem mudança;
- rota diferente = pedido de troca;
- validar destino novamente em `mind_rota_capacidade` antes de persistir.

## 6.4 Persistência

Preservar `mindagent_chat_save_message` como writer do App.

Usar `p_blocks.state.rota_ativa` como estado controlado pelo runtime e, na mesma transação de gravação da resposta do assistant:

1. validar sessão/conversa como hoje;
2. se houver `state.rota_ativa`, validar Gate para `mindagent-web`;
3. persistir em `engagement.conversas.variables.rota_ativa` apenas se `pode_executar=true`;
4. gravar mensagem.

Registrar em `blocks` para auditoria:

- rota que respondeu;
- `next_route` pedido;
- `rota_ativa` efetivamente persistida.

Não sobrescrever `origem_codigo`.

## 6.5 Troca vale para o próximo turno

Não chamar duas LLMs no mesmo turno.

Turno atual entrega o que puder + pede troca. Próximo turno usa Kit/Playbook da competência nova.

## 6.6 Duas direções

Permitir:

```text
concierge_summit → cliente_suporte
cliente_suporte → concierge_summit
```

Concierge usa `next_route=cliente_suporte` somente para necessidade operacional real.

Atendimento usa `next_route=concierge_summit` quando o problema operacional acabou e a nova necessidade voltou a ser curadoria/aprendizagem/recomendação.

## 6.7 Não confundir com humano

Concierge→Atendimento é troca de competência dentro do App.

Atendimento→humano é outra ação. O App hoje não tem actuator confirmado equivalente ao `needs_human` do Treble.

Não diga que transferiu para humano sem transporte real.

---

# 7. Não mexer agora

Não implementar neste trabalho:

- Knowledge institucional geral do Mind;
- agenda pessoal sistêmica;
- reservas pelo Concierge;
- novo Router;
- nova identidade;
- novo banco de conhecimento;
- recuperação sofisticada de conta;
- novo sistema de handoff humano;
- fallback de programação 24h do frontend (é passo posterior do runbook, a menos que uma regressão direta desta mudança obrigue tocar nele — não deve obrigar).

---

# 8. Testes — só o afetado

## Prompts/Concierge

- VIP quer Masterclass → verifica Prime vendável; explica upgrade/eligibilidade/vaga; não reserva.
- Mind quer workshop → VIP como menor upgrade.
- informação não encontrada → não inventa e não troca para Atendimento só por isso.
- agenda pessoal → não finge leitura.
- reserva → orienta a pessoa; não executa.
- lista completa de workshops → não corta artificialmente.

## Memória rápida

- 6 interesses permitidos no turno → todos persistem.
- 4 permitidos + 1 `saude_do_titular` → 4 persistem, sensível não.
- nenhum `confirmed` necessário.

## Memória durável

- `analise_concierge` extrai múltiplos fatos da conversa inteira.
- `opportunity + high` → ativa.
- temporary → não vira durável.
- medium/low → proposta.
- sensível → não persiste.
- proposta não volta para o Agent.
- memória ativa volta no turno seguinte.
- todos os interesses ativos chegam ao Kit sem corte em 3.

## Handoff

- nova conversa `mind_summit_app`, sem rota ativa → Concierge direto e Router não chamado.
- “meu ingresso não apareceu” → Concierge entrega útil + `next_route=cliente_suporte`.
- próximo turno → Atendimento sem Router.
- “qual o cardápio?” sem dado → continua Concierge, sem handoff automático.
- “como reservar?” → continua Concierge.
- depois de Atendimento: “me ajuda a escolher palestras sobre segurança psicológica” → `next_route=concierge_summit`; próximo turno volta ao Concierge.
- rota não permitida → não persiste.
- Gate fechado → não persiste e não afirma handoff.

## Regressões diretamente afetadas

- identidade continua igual;
- mesma pessoa/sessão/conversa durante troca de competência;
- origem oficial continua persistida e imutável;
- histórico continua funcionando;
- tools Intelligence continuam funcionando;
- Play continua funcionando;
- Router continua sendo usado nas entradas `mindagent-web` sem origem/rota autoritativa;
- Gate continua obrigatório.

Não rode suíte completa salvo se a implementação revelar mudança estrutural imprevista. Rode os testes diretamente afetados acima.

---

# 9. Git / deploy / documentação

- Trabalhe em branch, não direto na `main` desatualizada.
- Primeiro reconcilie o live 1.8.0 para a branch.
- Faça migrations idempotentes para alterações de funções/prompts quando apropriado.
- Não apague histórico de versões úteis sem necessidade.
- Antes de deploy, mostre diff resumido por arquivo/função e confirme que nenhum comportamento do live 1.8.0 foi perdido.
- Depois, deploy somente das Edge Functions afetadas.
- Teste E2E real do App.
- Atualize `CHECKPOINT_ATUAL.md`, `PROJECT_STATE.md` e o checkpoint #55 com:
  - o que mudou;
  - o que foi testado;
  - versões/deploys;
  - pendências que continuam abertas.

## Saída que quero de você ao terminar

Responda com:

1. **Investigação** — estado encontrado, especialmente live vs Git.
2. **Mudanças aplicadas** — arquivos, migrations, prompts e funções.
3. **Testes executados** — resultado de cada cenário afetado.
4. **Produção** — versões finais e confirmação de deploy.
5. **Pendências** — somente as que realmente continuam abertas.
6. **Commits/PR** — links ou SHAs.

Não proponha redesign ao final. Se algo impedir a implementação exata, pare naquele ponto e explique a incompatibilidade concreta antes de improvisar outra arquitetura.
