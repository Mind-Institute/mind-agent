# Mind Summit 2026 — Passo 5 — Adendo de memória após verificação viva

> **Este adendo prevalece sobre trechos conflitantes de `SUMMIT_2026_STEP5_PROMPTS_SPEC.md` relativos à memória.**
>
> Investigado no Supabase vivo em 2026-09-02. Não é implementação.

## 1. Descobertas vivas

### 1.1 Memória durável é gravada, mas o App não a lê

`public.analise_projetar_memoria` grava em `intelligence.participante_memoria`.

`public.mindagent_chat_get_context` hoje devolve:
- histórico;
- `engagement.session_interests`;
- `participant_profile` com nome/cargo/empresa e `intelligence.participante_contexto.temas_relevantes`.

Ele **não lê `intelligence.participante_memoria`**.

Portanto, sem mudança de read path, `analise_concierge` gravaria cargo/objetivo/interesse/preferência que o Concierge não reutilizaria.

### 1.2 Há mais cortes artificiais no runtime

Além de `interests.maxItems = 2` e `.slice(0,2)`, o live faz:
- `buildPersonalizationProfile(...).interesses.slice(0,8)`;
- envia para o Kit `personalizationProfile.interesses.slice(0,3)`.

`public.mind_kit_programacao` **não impõe outro corte**: concatena todos os interesses recebidos e só os usa para reordenar sessões já selecionadas pela pergunta.

Volume real atual de `participante_memoria` ativa e não expirada:
- máximo por pessoa: 3;
- p95: 3;
- média: 1,45.

Decisão: **não criar ranking agora**. Remover os cortes arbitrários do runtime e usar todos os fatos ativos permitidos. Se o volume crescer materialmente no futuro, seleção por relevância será outro problema.

### 1.3 Status atual impediria reutilizar interesses do Summit

Hoje `analise_projetar_memoria` usa:

```text
stable + high → ativa
qualquer outro caso → proposta
```

Isso faria um fato explícito de escopo `opportunity`, por exemplo “quero focar segurança psicológica neste Summit”, ficar em `proposta` e nunca voltar ao Agent.

Para `p_analisador = 'analise_concierge'`:
- `high + stable` → `ativa`;
- `high + opportunity` → `ativa`;
- `temporary` → não projetar como memória durável;
- `medium/low` → `proposta`, não enviar ao Agent como fato ativo.

Não mudar a semântica dos outros analisadores neste passo.

### 1.4 Gate de sensibilidade descrito no runtime não existe no banco

O live de `mindagent-chat` afirma em comentários que `mindagent_chat_save_interests` aplica política/fail-closed de sensibilidade. A função viva, porém:
- recebe objetos com `sensitivity`;
- **não lê nem valida esse campo**;
- não consulta `intelligence.memoria_bloqueios`;
- não há trigger de sensibilidade em `session_interests` ou `participante_memoria`.

Isso é bug real diretamente afetado pelo Passo 5.

## 2. Correção mínima da memória rápida

`mindagent-chat`:
- remover `maxItems: 2`;
- remover `confirmed` do contrato rápido;
- remover `.slice(0,2)`;
- extrair todos os interesses profissionais/de conteúdo úteis revelados no turno;
- manter `sensitivity` obrigatório.

`mindagent_chat_save_interests`:
- remover rejeição de payload >5;
- remover teto de 12 interesses por sessão;
- remover toda promoção para `intelligence.participante_memoria`;
- manter somente `engagement.session_interests`;
- deduplicar por chave;
- ignorar/bloquear deterministicamente qualquer item cujo `sensitivity` seja ausente, desconhecido ou diferente de `none`;
- não falhar o payload inteiro por um item sensível: salva os itens permitidos e descarta os bloqueados.

Memória rápida é sessão, não memória permanente.

## 3. Correção mínima da memória durável

### `analise_concierge`

Além do contrato já especificado, cada item de `customer_memory` deve carregar:

```text
sensitivity:
- none
- afastamento_titular
- diagnostico_titular
- filiacao_sindical
- medicacao_titular
- opiniao_politica
- orientacao_sexual
- origem_racial
- religiao
- saude_de_pessoa_citada
- saude_do_titular
```

Regra:
- somente `sensitivity=none` pode ser projetado como memória durável;
- na dúvida sobre sensibilidade, classificar para o lado bloqueado, nunca `none`.

### `analise_projetar_memoria`

Para `p_analisador='analise_concierge'`:
- exigir `sensitivity='none'`; qualquer outro valor/ausência → não persistir;
- não persistir `scope='temporary'` como memória durável;
- `confidence=high` + scope `stable|opportunity` → `status='ativa'`;
- medium/low → `proposta`;
- manter deduplicação/substituição atual.

Outros analisadores permanecem com a semântica atual neste passo.

## 4. Read path canônico

Estender **a função existente** `public.mindagent_chat_get_context`; não criar outro reader.

Quando `v_session.participante_id` existir, devolver também todas as memórias:

```text
intelligence.participante_memoria
where participante_id = pessoa da sessão
  and status = 'ativa'
  and (valido_ate is null or valido_ate > now())
```

Normalizar cada item para algo como:

```json
{
  "type": "interesse",
  "key": "interesse:seguranca_psicologica",
  "value": "segurança psicológica",
  "scope": "opportunity",
  "confidence": 0.9
}
```

Valor textual deve aceitar as duas formas históricas existentes:
- `valor.text`;
- `valor.label`.

Não devolver `proposta` nem `substituida` para o Agent.

## 5. Contexto enviado ao modelo

O runtime deve montar `personalization_profile` usando:
- nome/cargo/empresa já canônicos;
- session interests;
- memória durável ativa;
- temas existentes em `participante_contexto`, enquanto ainda forem necessários para compatibilidade.

Sem `.slice(0,8)` e sem `.slice(0,3)`.

Deduplicar conceitos equivalentes/chaves iguais antes de enviar.

O Kit pode receber todos os interesses permitidos; `mind_kit_programacao` já suporta isso sem alterar o conjunto de sessões, apenas a ordenação.

Não despejar informação sensível nem memória `proposta` no contexto do modelo.

## 6. Testes adicionais obrigatórios

1. turno com 6 interesses permitidos → todos os 6 persistem em `session_interests`;
2. um payload contém 4 permitidos + 1 `saude_do_titular` → 4 salvos, sensível descartado;
3. interesse `opportunity + high` extraído por `analise_concierge` → fica `ativa`;
4. memória `temporary` do Concierge → não vira durável;
5. memória `proposta` não entra em `mindagent_chat_get_context`;
6. memória ativa `interest/goal/preference` volta no turno seguinte e chega ao modelo;
7. todos os interesses ativos chegam ao Kit sem corte em 3;
8. não há regressão de identidade, histórico ou sessão.
