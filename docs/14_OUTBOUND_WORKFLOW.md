# MIND INTELLIGENCE — SALES OUTBOUND WORKFLOW

Status: NORMATIVE for future outbound architecture. Outbound reuses Sales intelligence/runtime but adds workflow, eligibility and communication-state controls.

## 1. Principle

Outbound is NOT “the inbound Sales agent starts a conversation on its own”.

It reuses:
- people;
- CRM relationship;
- intelligence;
- product context;
- playbooks;
- decisioning;
- Sales profile/tools.

But it introduces a workflow layer:

```text
TRIGGER
  ↓
ELIGIBILITY
  ↓
CONTACTABILITY / CONSENT / SUPPRESSION
  ↓
WHY NOW?
  ↓
RESEARCH / CONTEXT PREPARATION
  ↓
OUTREACH OBJECTIVE + MESSAGE
  ↓
SEND
  ↓
WAIT / FOLLOW-UP STATE
  ↓
REPLY
  ↓
NORMAL SALES RUNTIME
```

## 2. Trigger types

Possible future triggers:
- abandoned checkout/cart;
- high-fit lead with no response;
- event/product lifecycle milestone;
- corporate account opportunity;
- explicit follow-up due;
- inbound conversation that went quiet;
- relevant product launch/offer change;
- post-event next-step opportunity;
- CRM task/campaign eligibility.

Trigger existence does not automatically authorize sending.

## 3. Eligibility

Eligibility should evaluate:
- product/run relevance;
- relationship state;
- open deal/task;
- prior outcomes;
- recent message/contact history;
- contactability/consent;
- suppression/opt-out;
- channel availability;
- cadence limits;
- current lifecycle/status;
- reason to contact now.

## 4. Why-now requirement

Every outbound attempt should have a concise machine-readable reason.

Examples:
- `checkout_abandoned_vip_24h`;
- `corporate_followup_due`;
- `lot_change_relevant`;
- `requested_followup`;
- `post_summit_institute_fit`.

Avoid generic “engagement campaign” as the only rationale.

## 5. Contactability and suppression

Outbound must query the target privacy/contactability layer before message generation/send.

It should consider:
- consent/legal basis as applicable;
- user opt-out;
- channel suppression;
- global suppression;
- do-not-contact state;
- communication preference;
- recent contact/cadence;
- invalid/unverified contact point.

If blocked, message must not be sent even if the LLM recommends it.

## 6. Research/context preparation

Before generation, prepare only relevant context:
- identity/company/role;
- relationship summary;
- relevant prior messages;
- product interest/fit;
- current authoritative offer/pricing;
- why-now trigger;
- open objection/constraint;
- permitted personalization fields.

Do not use unverified inferred details as if the person stated them.

## 7. Message generation

Message should have:
- a legitimate reason for contact;
- relevance to known context;
- concise value/next step;
- no invented familiarity;
- no hidden use of sensitive traits;
- current authoritative commercial facts;
- opt-out/compliance behavior required by channel/policy.

Outbound should be evaluated for naturalness and specificity, not just personalization token count.

## 8. State machine

Track outbound attempt state separately from normal conversation text.

Conceptual states:
- eligible;
- queued;
- sent;
- delivered;
- failed;
- replied;
- waiting;
- followup_due;
- suppressed;
- completed;
- handed_off.

A reply should enter the normal unified `engagement` conversation/runtime and refresh intent/context.

## 9. Cadence and duplicate prevention

Cadence must be policy-driven, not left to LLM discretion.

Rules should prevent:
- duplicate sends from retry;
- two automations contacting same person at once;
- repeated follow-up after reply;
- contacting after opt-out;
- contacting too soon after human outreach;
- campaign sends that ignore an active deal/task state.

Use idempotency keys and auditable outbound attempt ids.

## 10. Human coordination

If a lead/account has an active human owner, outbound policy should define whether agent:
- may send autonomously;
- drafts for approval;
- creates task only;
- is suppressed while human owns the conversation.

This must align with HubSpot/source-of-truth rules before launch.

## 11. Relationship to Sales behavior

Once the person replies, use `sales_summit` or appropriate Sales profile with normal behavior spec.

Do not maintain a second outbound-specific intelligence store or conversation runtime.

## 12. Observability

Each outbound attempt should record:
- trigger/reason;
- eligibility result;
- policy decisions;
- contact point/channel;
- consent/suppression check result;
- context version/manifest;
- generated message version;
- send provider/external id;
- delivery/result;
- follow-up state;
- reply conversion;
- human feedback if applicable.

## 13. Evals

Outbound cannot launch before passing:
- allowed contact sends;
- opt-out blocks;
- suppression blocks;
- duplicate retry blocked;
- stale pricing refreshed;
- requested follow-up honored;
- no fake familiarity;
- reply transitions to Sales runtime;
- cadence policy enforced;
- owner/human coordination cases.

See `docs/13_EVALS_AND_OBSERVABILITY.md`.

## 14. V1 boundary

Do not implement outbound during the current inbound/Concierge build unless it changes a foundational requirement (notably identity, contact points, privacy/contactability, engagement and observability). Architect for it now; implement the workflow after inbound Sales and Concierge are stable.