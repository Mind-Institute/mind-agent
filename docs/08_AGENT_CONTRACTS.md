# MIND INTELLIGENCE — AGENT API CONTRACTS

Este documento define a interface lógica que agents devem consumir. Implementação física pode mudar sem obrigar agents a conhecer tabelas.

## Principles

1. Contracts semânticos, não SQL livre.
2. Outputs previsíveis e versionáveis.
3. Apenas contexto necessário.
4. Escritas autorizadas por action scope.
5. Dados sensíveis/minimização por profile.
6. Agent não escolhe tabela física.

## Core context functions

### `build_base_context(person_id?, conversation_id?, product_run_id?, profile)`
Returns conceptual shape:
```json
{
  "person": {},
  "relationship": {},
  "conversation": {},
  "recent_messages": [],
  "active_intelligence": [],
  "summary": {},
  "product_scope": {},
  "open_work": []
}
```

### `get_person_context(person_id)`
```json
{
  "person": {},
  "profiles": [],
  "organizations": [],
  "affiliations": [],
  "product_roles": [],
  "external_refs": []
}
```

### `get_relationship_context(person_id)`
```json
{
  "crm_contact": {},
  "companies": [],
  "open_deals": [],
  "orders": [],
  "access_rights": [],
  "support_cases": [],
  "customer_relationship": {}
}
```

### `get_conversation_context(conversation_id)`
```json
{
  "conversation": {},
  "entry_context": {},
  "recent_messages": [],
  "summary": {},
  "current_intents": [],
  "active_insights": []
}
```

## Product context

### `get_product_context(product_run_id, relevance_query?)`
Stable logical shape:
```json
{
  "product": {},
  "run": {},
  "positioning": {},
  "relevant_content": [],
  "relevant_people": [],
  "commercial": {},
  "concepts": []
}
```

Internally:
- Summit → catalog + summit + commercial + knowledge + people
- Institute → catalog + institute + commercial + knowledge + people
- Dash → catalog + dash + commercial + knowledge + people
- Events → catalog + events + commercial + knowledge + people

## Commercial

### `get_commercial_context(product_run_id, person_id?, offer_id?)`
```json
{
  "offers": [],
  "current_pricing_period": {},
  "prices": [],
  "discount_rules": [],
  "eligible_conditions": [],
  "access_context": {},
  "checkout": {}
}
```

### `compare_offers(product_run_id, offer_codes[])`
Return only official, current comparison.

### `get_current_price(offer_id, person_id?, quantity?)`
Must return authoritative calculated price + applied rule provenance.

## Knowledge

### `get_relevant_knowledge(query, concept_ids?, product_run_id?, limit?)`
Return curated relevant claims/documents with sources/caveats when applicable.

### `search_deep_knowledge(query, filters?)`
Broader retrieval for Researcher/deep research.

## Summit-specific

### `find_summit_sessions(product_run_id, query, filters?)`
```json
{
  "sessions": [
    {
      "id": "...",
      "title": "...",
      "starts_at": "...",
      "ends_at": "...",
      "space": {},
      "people": [],
      "concepts": [],
      "reservation": {}
    }
  ]
}
```

### `get_session_details(session_id)`
Full operational details permitted to profile.

### `get_person_profile(person_id, product_run_id?)`
Global person profile plus run-specific role override if relevant.

### `get_person_books(person_id)`
Return works filtered to books.

## Memory write contracts

### `record_fact(...)`
Minimum fields:
- person/org scope
- key
- value_json
- source_type/source_id
- verification status
- valid_from/valid_until when relevant

### `record_insight(...)`
Minimum fields:
- person/org scope
- insight_type
- value_text/value_json
- confidence
- source_type/source_id
- status
- created_by_agent_id
- validity/supersedes when relevant

### `record_intent(...)`
- person/conversation/message
- intent_type
- product/product_run scope
- confidence
- status/time

### `update_summary(...)`
- summary_type
- person/product scope
- content
- valid_through_at
- generated_by

### `record_product_fit(...)`
- person
- product/product_run
- fit_score
- intent_score
- potential_tier
- reason_summary
- evidence_json

## Strategy

### `get_effective_playbook(profile, product_id?, product_run_id?, channel?)`
Must resolve inheritance/overlays and return effective principles/stages/moves/guardrails/examples.

### `get_applicable_policies(profile, context)`
Hard policies only; deterministic whenever possible.

### `record_decision(...)`
Persist operational decision:
- conversation
- agent_run
- stage
- objective
- selected_move
- next_best_action
- confidence
- rationale_summary

No hidden chain-of-thought.

### `get_next_best_actions(person_id?, deal_id?)`
Return actionable queue with reasons/priorities.

## Actions

### `create_followup(...)`
Idempotent; audit required.

### `create_ticket(...)`
Idempotent where possible; link person/conversation/source.

### `create_crm_task(...)`
External write through integration layer/outbox where appropriate.

### `update_crm(...)`
Never arbitrary property write from raw LLM. Use allowlisted fields/action scopes.

### `send_email(...)`
Explicitly authorized only; audit and idempotency.

### `schedule_meeting(...)`
Explicitly authorized; calendar integration rules apply.

## Delegation

### `delegate_task(agent_profile, task, context_refs?)`
Return:
```json
{
  "status": "completed|needs_human|failed",
  "answer": {},
  "sources": [],
  "caveats": [],
  "confidence": null
}
```

### `handoff_to_human(reason, conversation_id, urgency?)`
Return/store handoff package with concise context.

### `request_deep_research(...)`
Convenience wrapper for researcher profile.

## Context Planner contract

Conceptual V1 output:
```json
{
  "needs": ["commercial.current_offer"],
  "needs_deep_research": false,
  "needs_old_history": false
}
```

## Structured Sales turn output — conceptual

```json
{
  "decision": {
    "stage": "...",
    "objective": "...",
    "selected_move": "...",
    "next_best_action": "...",
    "confidence": 0.0
  },
  "response": {
    "answer": "...",
    "needs_human": false
  },
  "memory_candidates": {
    "facts": [],
    "insights": [],
    "intents": []
  },
  "tool_requests": []
}
```

Exact schema may evolve; architectural separation must remain.

## Contract versioning

Breaking changes to agent-facing logical shapes require:
- version bump or compatibility layer;
- consumer inventory;
- migration plan;
- tests.

Physical DB refactors should not force unnecessary prompt/runtime rewrites.