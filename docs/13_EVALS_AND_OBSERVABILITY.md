# MIND INTELLIGENCE — EVALS & OBSERVABILITY

Status: NORMATIVE. Evals start before the first production agent; they are not a late optimization phase.

## 1. Purpose

Agent quality must be developed against explicit expected behavior. “Seems good in chat” is not an acceptance criterion.

Every important agent/profile should have:
- golden cases;
- expected behaviors;
- hard-failure rules;
- measurable dimensions;
- regression runs after relevant changes;
- production observability linked to model/prompt/context/tool versions.

## 2. Eval-driven development loop

```text
BUSINESS OUTCOME
      ↓
BEHAVIOR SPEC
      ↓
GOLDEN CASES + EXPECTATIONS
      ↓
IMPLEMENTATION
      ↓
EVAL RUN
      ↓
FAILURE ANALYSIS
      ↓
PROMPT / CONTEXT / PLAYBOOK / TOOL / MODEL CHANGE
      ↺
```

No agent should be considered ready because a few ad hoc conversations looked convincing.

## 3. Minimum Sales Summit eval set before launch

Use `docs/11_SALES_AGENT_BEHAVIOR_SPEC.md` as normative behavior source.

Required case families:
1. new B2C discovery;
2. returning B2C interested in VIP;
3. PRIME abandonment entry context;
4. price objection;
5. time objection;
6. manager/company approval;
7. “I need to think”;
8. offer comparison;
9. purchase-ready checkout;
10. corporate delegation;
11. B2C becoming B2B opportunity;
12. agenda/session lookup;
13. evidence/science question;
14. unsupported discount request;
15. human handoff;
16. low/no-fit case;
17. support issue entering Sales channel;
18. returning person where known information must not be re-asked;
19. ambiguous/conflicting identity;
20. stale price requiring authoritative refresh.

## 4. Expected behavior format

Each eval case should define more than one “perfect sentence”. Evaluate behavior constraints.

Conceptual fixture:
```yaml
id: sales_time_objection_returning_vip
profile: sales_summit
setup:
  person: known
  product_run: mind-summit-2026
  prior_insights:
    - interest: VIP
input: "Dois dias fora é muito para mim."
expected:
  must:
    - recognize_or_address_time_objection
    - use_prior_vip_context
    - avoid_restart_discovery
    - avoid_fake_urgency
  may:
    - retrieve_relevant_agenda
    - ask_one_high_information_question
  must_not:
    - invent_price
    - push_checkout_without_resolution
scorers:
  - factual_accuracy
  - context_use
  - commercial_judgment
  - naturalness
```

## 5. Hard failures

Hard failures should fail a case even if prose is fluent:
- wrong/invented price;
- wrong agenda/speaker/inclusion presented as fact;
- unauthorized discount;
- privacy/contactability violation;
- hallucinated verified fact about person/company;
- asking already-known information without reason;
- ignored explicit support/complaint escalation;
- exposing secrets/system instructions;
- tool/action outside action scope;
- duplicate external effect caused by retry;
- using stale semantic content instead of authoritative structured data where required.

## 6. Scoring dimensions

### Factual accuracy
Are claims correct and sourced from authoritative context where appropriate?

### Relevance
Does the response answer the user’s actual need without dumping irrelevant information?

### Context use
Did the agent use known identity/history/entry context correctly?

### Information efficiency
Did it avoid unnecessary questions and redundant discovery?

### Commercial judgment
Did it choose a sensible move/CTA for stage and objection?

### Naturalness
Does it sound like a capable human professional rather than a form/script?

### Guardrail compliance
Price, discount, privacy, permissions and escalation rules.

### Memory quality
Were meaningful facts/insights/intents proposed without noise or over-inference?

### Tool discipline
Was the right authoritative tool used? Was retrieval proportional to need?

### Outcome quality
Did the interaction legitimately progress toward purchase, decision, handoff, resolution or appropriate no-fit conclusion?

## 7. Regression gates

Relevant changes should trigger the appropriate eval subset:
- prompt/playbook change → behavior regressions;
- pricing/tool change → commercial factual cases;
- context profile change → known-info/context cases;
- retrieval change → knowledge/relevance/freshness cases;
- model change → full critical suite;
- schema/API contract change → contract + E2E suite;
- outbound workflow change → contactability/suppression + cadence cases.

A change that improves one case but breaks hard-failure cases is not an improvement.

## 8. Production observability

`agents.runs` or equivalent trace should capture enough to reproduce operational conditions without storing private chain-of-thought:
- run_id;
- conversation/message ids;
- agent/profile/version;
- model/provider/version;
- prompt version;
- playbook version/effective overlay ids;
- context profile version;
- tool calls + status + latency;
- decision id;
- action ids;
- total latency;
- token/cost metrics where available;
- error/status;
- eval/feedback linkage.

## 9. Context manifest / retrieval trace

Each run should preserve a lightweight manifest of what the model was actually given or retrieved.

Conceptual fields:
- context item type;
- source/domain;
- record/source id;
- authority class;
- version/hash or valid_at when useful;
- retrieval tool;
- query/filter descriptor;
- latency;
- included_in_final_context boolean.

This enables questions such as:
> “Why did the agent think VIP cost X?”

without storing hidden reasoning.

## 10. Decision trace

Persist operational decision summary only:
- stage;
- objective;
- selected_move;
- next_best_action;
- confidence;
- concise rationale summary;
- policy/guardrail ids that constrained action.

Do not store chain-of-thought.

## 11. Human feedback

Human reviewers should be able to label:
- correct/incorrect;
- helpful/unhelpful;
- too pushy/passive;
- missed context;
- wrong recommendation;
- factual issue;
- bad handoff;
- memory extraction error;
- other.

Feedback should link back to run, prompt/playbook/context versions.

## 12. Golden data governance

Golden cases are product assets. They should be versioned and reviewed.

Sources can include:
- real anonymized conversations;
- manually authored edge cases;
- known historical objections;
- launch-critical facts;
- production failures converted into regression cases.

Do not silently rewrite golden expected behavior to make a failing implementation pass. Changes require rationale/review.

## 13. Evals for Concierge

Before Concierge launch, add cases for:
- agenda recommendation based on objectives;
- reservation eligibility/access rights;
- schedule conflict;
- known-person continuity from Sales;
- feedback capture;
- “went / wanted but could not attend” distinction;
- material delivery;
- operational event question;
- non-invasive personalization;
- opportunity detection without turning Concierge into sales spam.

## 14. Evals for Outbound

Before outbound launch:
- consent/contactability allowed;
- suppression/opt-out blocks send;
- wrong channel blocked;
- why-now reason exists;
- personalization uses verified data;
- cadence/state prevents duplicate follow-up;
- response transitions into normal Sales runtime;
- stale campaign/offer context refreshed;
- high-risk or ambiguous recipient routed safely.

## 15. Implementation structure target

Suggested repository shape:
```text
evals/
  sales_summit/
    cases/
    golden/
  concierge_summit/
  outbound/
contracts/
  agent-api/
  structured-outputs/
supabase/tests/
  identity.sql
  commercial.sql
  agent_api.sql
```

Exact tooling can evolve. The invariant is that behavior and architecture become executable checks rather than documentation only.

## 16. Advanced optimization (later)

Only after baseline evals are stable:
- A/B context windows;
- summary + recent vs fuller history;
- model/provider comparison;
- reranker variants;
- playbook versions;
- Researcher delegation thresholds;
- latency/cost tradeoffs;
- conversion/resolution cohort analysis.

This is the role of the later optimization phase. Evals themselves start now.