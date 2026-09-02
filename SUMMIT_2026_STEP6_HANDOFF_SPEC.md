# Mind Summit 2026 — Passo 6 — Handoff Concierge → Atendimento

> **STATUS: ESPECIFICAÇÃO FECHADA PARA IMPLEMENTAÇÃO. NÃO É O ESTADO VIVO.**
>
> Saída do Passo 6 de `SUMMIT_2026_EXECUTION_RUNBOOK.md`, investigada contra o Supabase vivo em 2026-09-02.

## 1. O que existe hoje

### Entrada oficial

A entrada oficial continua:

```text
origem_codigo = mind_summit_app
→ concierge_summit
→ Gate
→ Kit
→ Agent
```

`mindagent-chat` v28 já implementa essa origem autoritativa. O Router não participa dessa entrada.

### Canal

`agentes.canal_competencia` permite no `mindagent-web` exatamente:

- `concierge_summit`
- `cliente_suporte`

`public.mind_canal_rotas('mindagent-web')` devolve essas rotas e é a fonte canônica para o universo permitido.

`public.mind_rota_capacidade('cliente_suporte','mindagent-web')` está aberto (`pode_executar=true`).

O Kit real de `cliente_suporte` está disponível e possui os blocos obrigatórios:

- `evento`
- `inclusoes`
- `programacao`

Portanto **Atendimento já é uma competência executável dentro do mesmo runtime/app**. Não é necessário abrir nova conversa, novo backend ou novo Router.

### Gap atual

No `mindagent-chat` vivo:

- a origem `mind_summit_app` força `concierge_summit` em todos os turnos;
- o schema de saída só contém `answer` + `interests`;
- não existe contrato executável para mudar a competência ativa;
- `mindagent_chat_get_context` devolve `origem_codigo`, mas não competência ativa;
- não existe tabela/função específica de handoff;
- `engagement.conversas.variables` já é a casa existente de estado dinâmico da conversa.

Conclusão: o problema é **estado de rota ativa + contrato Agent→runtime**, não falta de arquitetura de atendimento.

---

## 2. Decisão arquitetural

### 2.1 Origem define a rota inicial, não uma prisão permanente

Para o App oficial:

```text
rota_ativa persistida e válida
→ usar rota_ativa

senão:
origem mind_summit_app
→ concierge_summit
```

Para entradas sem origem autoritativa, continua valendo o Router atual.

Precedência:

```text
ROTA ATIVA DA CONVERSA
> ROTA AUTORITATIVA DA ORIGEM
> ROUTER (somente quando as anteriores não definem a competência)
```

O Gate continua obrigatório depois da escolha, qualquer que seja a origem da rota.

### 2.2 Casa do estado

Persistir a competência corrente em:

```text
engagement.conversas.variables.rota_ativa
```

Não criar:

- tabela de handoff;
- coluna nova;
- nova taxonomia;
- nova conversa;
- segundo Router.

`origem_codigo` permanece imutável como **porta de entrada**. `rota_ativa` representa **quem está atendendo agora**. São conceitos diferentes.

### 2.3 Contrato Agent → runtime

Adicionar ao schema de saída do `mindagent-chat`:

```text
next_route: <rota canônica permitida no canal> | null
```

A lista permitida NÃO deve ser hardcoded separadamente. Montar o enum do schema a partir de:

```text
public.mind_canal_rotas('mindagent-web')
```

Regras:

- `null` = permanece na competência atual;
- rota igual à atual = normalizar para `null` / sem mudança;
- rota diferente = pedido de troca de competência;
- runtime valida novamente a rota pelo Gate antes de persistir;
- nunca aceitar rota fora da política do canal;
- o modelo não altera `origem_codigo`.

### 2.4 Transições necessárias

O fluxo mínimo deve aceitar as duas transições entre as competências já permitidas:

```text
concierge_summit → cliente_suporte
cliente_suporte → concierge_summit
```

A segunda transição é necessária para o participante não ficar preso permanentemente em Atendimento depois que a necessidade operacional termina ou a conversa volta a ser sobre curadoria/aprendizagem do Summit.

Não é Router. É a competência atual explicitamente entregando a conversa para a outra competência permitida no mesmo canal.

---

## 3. Critério de troca

### Concierge → Atendimento

Só quando surgir **necessidade operacional real**, por exemplo:

- ingresso/acesso com problema;
- pagamento;
- titularidade/atribuição de ingresso;
- reembolso;
- erro técnico;
- inconsistência cadastral;
- reclamação séria;
- exceção de política;
- pedido explícito de atendimento/humano.

Não trocar por:

- simples falta de informação;
- dúvida sobre conteúdo/programação que o Concierge pode investigar;
- ação que a própria pessoa deve executar no app, como reserva/cancelamento;
- pergunta comercial que o próprio Concierge consegue resolver com Intelligence.

### Atendimento → Concierge

Quando a necessidade corrente deixar de ser operacional e a pessoa voltar a pedir curadoria, aprendizagem, recomendação de conteúdo ou orientação típica de Concierge.

Atendimento não deve permanecer dono por inércia.

---

## 4. Semântica do turno de handoff

A troca é **para o próximo turno**.

No turno em que pede a troca, a competência atual deve:

1. entregar tudo que ainda consegue resolver/explicar;
2. não fazer a pessoa repetir contexto;
3. sinalizar a troca pelo `next_route`;
4. não afirmar uma ação humana que não aconteceu.

O próximo turno já carrega o Kit/Playbook da `rota_ativa` persistida.

Não fazer uma segunda chamada de LLM no mesmo turno apenas para trocar playbook. Isso aumentaria latência e complexidade sem necessidade atual.

---

## 5. Persistência sem novo writer conceitual

### Leitura

Estender `mindagent_chat_get_context` para devolver `rota_ativa` a partir de `engagement.conversas.variables` quando houver objeto válido.

### Escrita

Preservar `mindagent_chat_save_message` como writer do App e sua validação de sessão/idempotência.

Menor mudança recomendada: usar o `p_blocks` já persistido pelo turno para carregar um subobjeto de estado controlado pelo runtime, por exemplo:

```json
{
  "state": {
    "rota_ativa": "cliente_suporte"
  }
}
```

Quando `p_role='assistant'` e `state.rota_ativa` estiver presente, `mindagent_chat_save_message` deve, **na mesma transação da gravação da mensagem**:

1. validar a sessão/conversa como já faz;
2. validar a rota via `mind_rota_capacidade(rota,'mindagent-web')`;
3. exigir `pode_executar=true`;
4. persistir `variables.rota_ativa`;
5. gravar a mensagem.

Assim evitamos o estado impossível “a resposta disse que encaminhou, mas a rota não mudou” e não criamos RPC/tabela nova.

O runtime pode também registrar em `p_blocks`:

- `rota` = competência que respondeu este turno;
- `next_route` = pedido bruto do Agent;
- `rota_ativa` = competência efetivamente persistida depois da validação;

Isso mantém auditabilidade sem nova casa de histórico: cada mensagem já guarda metadados do turno.

---

## 6. Seleção da rota no `mindagent-chat`

Ao montar o turno:

```text
1. ler sessionContext.rota_ativa
2. se existir e Gate permitir no canal → rotaDecidida = rota_ativa
3. senão, verificar ROTA_POR_ORIGEM
4. se origem autoritativa existir → rotaDecidida = rota da origem
5. senão → Router atual
6. sempre → Gate
7. Kit da rota escolhida
```

Se `rota_ativa` estiver inválida ou deixar de ser permitida pelo canal, ignorar o override e seguir a precedência normal. Não inventar fallback para uma rota proibida.

---

## 7. Handoff entre competências ≠ handoff humano

São dois conceitos diferentes:

### Troca de competência no App

```text
Concierge ↔ Atendimento
```

É o que este Passo 6 implementa.

### Atendimento → humano

É uma ação operacional posterior quando Atendimento também não consegue executar/validar a necessidade.

Hoje o App **não possui actuator de handoff humano confirmado** equivalente ao `needs_human` do Treble. Portanto:

- este Passo 6 não deve fingir que transferiu para humano;
- `playbook_cliente_suporte` pode orientar contato oficial quando necessário;
- um actuator real de humano só pode ser declarado depois de existir transporte confirmado.

Não reutilizar `needs_human` do Treble como se ele automaticamente produzisse handoff no App.

---

## 8. Ajuste dos playbooks da especificação do Passo 5

### Concierge

No bloco de Atendimento, instruir explicitamente:

```text
Quando a necessidade se tornar operacional e exigir Atendimento, responda o que ainda puder e defina next_route=cliente_suporte.
Não use next_route por simples ausência de informação.
```

### Atendimento

Adicionar:

```text
Quando a necessidade operacional terminar ou a nova necessidade for claramente de curadoria/aprendizagem/recomendação do Summit, defina next_route=concierge_summit.
Não permaneça em Atendimento apenas porque a conversa veio de Atendimento.
```

Nenhum dos playbooks escolhe rota fora do conjunto que o runtime expõe no schema.

---

## 9. Testes afetados obrigatórios

### Entrada e persistência

1. nova conversa `mind_summit_app` sem `rota_ativa` → Concierge direto, Router não chamado.
2. Concierge retorna `next_route=cliente_suporte` → Gate do destino aberto → `variables.rota_ativa=cliente_suporte`.
3. turno seguinte da mesma conversa → `cliente_suporte`, Router não chamado.
4. Atendimento retorna `next_route=concierge_summit` → estado muda → próximo turno volta ao Concierge.
5. `next_route` igual à rota atual → nenhuma mudança material.
6. rota fora de `mind_canal_rotas` → não persiste.
7. Gate fechado para destino → não persiste e não afirma handoff concluído.

### Critério comportamental

8. “Meu ingresso não apareceu no app” → Concierge entrega o útil + pede Atendimento.
9. “Qual o cardápio do almoço?” sem dado → Concierge diz que não consegue confirmar; **não** troca para Atendimento.
10. “Como faço para reservar?” → Concierge orienta/tutorial; **não** troca para Atendimento.
11. depois de Atendimento, “agora me ajuda a escolher palestras sobre segurança psicológica” → Atendimento devolve para Concierge.

### Regressões

12. rota não-oficial `mindagent-web` continua usando Router como hoje.
13. Gate continua obrigatório.
14. histórico, identidade, session token, interests e Play continuam funcionando.
15. nenhum novo `pessoa_id`, conversa ou sessão é criado na troca de competência.

---

## 10. Não fazer

- não recolocar Router no App oficial;
- não criar tabela/coluna de handoff;
- não criar segunda conversa para Atendimento;
- não usar `agente` como rota — `agente='mindagent-chat'` identifica o runtime, não a competência;
- não sobrescrever `origem_codigo`;
- não confundir troca Concierge→Atendimento com humano;
- não executar duas LLMs no mesmo turno apenas para fazer a troca;
- não criar segunda lista hardcoded de rotas permitidas; usar `mind_canal_rotas` + Gate.

---

## 11. Definition of Done

Passo 6 está concluído quando, em E2E real do App:

```text
mind_summit_app
→ Concierge
→ necessidade operacional
→ rota_ativa = cliente_suporte
→ próximo turno usa Playbook/Kit de Atendimento
→ nova necessidade de Concierge
→ rota_ativa = concierge_summit
→ próximo turno volta ao Concierge
```

Tudo na mesma pessoa, sessão e conversa, sem Router na entrada oficial e sem alegar handoff humano inexistente.
