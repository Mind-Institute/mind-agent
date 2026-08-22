# MIND INTELLIGENCE — KNOWLEDGE INGESTION & RETRIEVAL

Status: NORMATIVE for how knowledge enters, is validated, indexed and retrieved.

## 1. Purpose

Mind Intelligence must not become a folder of embeddings or a collection of copied website pages. It needs a reproducible knowledge pipeline that converts changing sources into structured, traceable, retrievable knowledge for multiple agents.

The system must support content coming from:
- Mind website / WordPress;
- product pages;
- program/event schedules;
- spreadsheets;
- Google Docs / internal docs;
- uploaded PDFs/files;
- scientific papers/books/reports;
- operational systems/APIs;
- manually curated content;
- future CMS or partner sources.

## 2. Core distinction: operational truth vs semantic knowledge

Use the right retrieval mechanism for the question.

### Deterministic structured data
Use structured tables/functions for exact and volatile facts.

Examples:
- current VIP price;
- active lot;
- checkout URL;
- speaker/session time;
- reservation availability;
- ticket access right;
- purchase/payment state.

These should not be answered from vector search if an authoritative structured source exists.

### Global entities
Use canonical entity tables for identity/profile information.

Examples:
- who Amy Edmondson is;
- affiliations;
- books/works;
- product role;
- organization.

### Scientific/semantic knowledge
Use `knowledge` concepts/claims/sources/documents and hybrid retrieval where language understanding is required.

Examples:
- why psychological safety matters;
- evidence behind wellbeing and performance;
- what science says about burnout;
- caveats in a research finding.

### Product/editorial knowledge
Use `catalog.product_content` and product-specific documents for:
- positioning;
- audience;
- FAQ;
- value proposition;
- differentiators;
- cases;
- approved explanations.

## 3. Ingestion pipeline

```text
SOURCE
  ↓
SOURCE REGISTRATION
  ↓
RAW SNAPSHOT / VERSION
  ↓
PARSING / NORMALIZATION
  ↓
CLASSIFICATION
  ├─ canonical entity
  ├─ product content
  ├─ structured operational data
  ├─ scientific claim/source
  └─ document/chunks
  ↓
VALIDATION / APPROVAL / PROVENANCE
  ↓
INDEXING
  ├─ relational
  ├─ full-text
  └─ embeddings when useful
  ↓
RETRIEVAL POLICY
  ↓
AGENT API
```

## 4. Source registration

Every recurring source should have a stable identity and ownership metadata.

Conceptual fields:
- source_id;
- source_type;
- provider;
- canonical_url / locator;
- owner;
- refresh strategy;
- expected freshness;
- authority class;
- active/status;
- last_seen_at;
- last_successful_sync_at;
- content hash/version;
- locale;
- sensitivity/classification.

A URL is not enough. We need to know whether it is authoritative, how often it changes and what downstream objects it may update.

## 5. Raw snapshots and versioning

For mutable sources, preserve enough raw/version metadata to answer:
- what did the source say when this record was produced?
- when did it change?
- can we re-process it with a better parser later?

Do not overwrite provenance with only the latest parsed text.

Raw snapshots may live in Storage or a dedicated integration/document representation depending on size and sensitivity.

## 6. Classification before chunking

Do not chunk everything first.

Example website page about VIP may contain:
- product description → `catalog.product_content`;
- current price → `commercial` (only if authoritative and synchronized appropriately);
- speaker names → canonical `people` references;
- scientific statement → `knowledge.claims` + source;
- long explanatory text → document/chunks.

The ingestion pipeline should route information to the correct owner domain before relying on generic RAG.

## 7. Knowledge model

### Concepts
Semantic anchors such as:
- psychological safety;
- burnout;
- wellbeing at work;
- meaning;
- job design;
- leadership;
- resilience;
- psychosocial risks.

Concepts allow relationships between user needs, sessions, people, products and evidence.

### Claims
Structured assertions that matter enough to retrieve reliably.

Conceptual fields:
- statement;
- claim_type;
- concept_ids;
- evidence_strength;
- caveats;
- validity/status;
- locale;
- reviewed_at;
- reviewer/approval if needed.

### Sources
Original evidence artifacts: paper, book, report, institutional page, etc.

### Documents / chunks
Long-form content for semantic retrieval. Chunking is an implementation technique, not the ontology itself.

## 8. Provenance and authority envelope

Every context item passed to agents should be able to carry a common metadata envelope when relevant:

```json
{
  "value": "...",
  "source": "...",
  "authority": "authoritative | observed | inferred | generated",
  "observed_at": "...",
  "effective_at": "...",
  "valid_until": "...",
  "confidence": 0.93,
  "sensitivity": "normal"
}
```

Not every field must be physically repeated in every table; the Agent API should make authority/freshness distinguishable in the logical output.

### Authority meanings
- `authoritative`: source-of-truth operational/curated fact.
- `observed`: explicitly seen in user/system evidence but not canonical authority.
- `inferred`: model/algorithm interpretation; confidence required.
- `generated`: derived summary/explanation; must not masquerade as source fact.

## 9. Freshness rules

Different knowledge decays differently.

Examples:
- price/availability: very high freshness requirement;
- event agenda: high freshness requirement before/during event;
- product positioning: moderate, versioned;
- person biography: moderate;
- scientific paper: stable artifact, but synthesis can become outdated.

Retrieval should prefer current valid records and expose stale state where meaningful.

## 10. Retrieval hierarchy

Preferred order:

1. **Authoritative structured tool** when the answer is exact/operational.
2. **Canonical entity context** for people/products/organizations.
3. **Curated product content** for approved commercial/editorial explanation.
4. **Structured knowledge claims** for evidence statements.
5. **Hybrid document retrieval** for nuance/long-form support.
6. **Deep Research / Researcher delegation** for broader synthesis or missing evidence.

Do not jump to generic vector search when step 1–4 can answer more reliably.

## 11. Hybrid retrieval

Where documents are appropriate, retrieval may combine:
- metadata filters;
- product/run scope;
- concept links;
- full-text/BM25-like search;
- embeddings/vector similarity;
- recency/authority weighting;
- reranking if needed.

The exact technique is implementation detail and should be eval-driven.

## 12. Need ↔ concept ↔ content graph

The system should support proactive relevance:

```text
person need / insight
        ↕
      concept
   ↙     ↓      ↘
session product  expert
        ↓
      claim
        ↓
      source
```

This enables an agent to say not merely “here is the agenda”, but “given your concern about X, these are the two sessions/interventions most relevant, and here is the evidence/logic behind that connection.”

## 13. Site as a changing source

The site should be treated as a source with sync/version semantics, not manually pasted prompt content.

For each relevant page:
- register source/url;
- fetch via approved integration/process;
- hash/version;
- parse;
- classify fields/content;
- upsert only the domains the page is authoritative for;
- record provenance;
- mark stale/removed content;
- re-index affected documents/concepts.

If the website is not authoritative for a field such as transactional payment status, it must not overwrite that domain.

## 14. Human curation and approval

Not all content needs manual approval, but high-impact content may.

Examples needing stronger governance:
- scientific claims used in commercial assertions;
- current prices/discount rules;
- regulated/legal statements;
- speaker credentials represented publicly;
- policies/guardrails.

Store approval/review metadata where appropriate.

## 15. Agent-facing retrieval outputs

Agents should receive concise, semantically useful outputs rather than raw chunks whenever possible.

Example scientific result:
```json
{
  "claim": "...",
  "concepts": ["psychological_safety"],
  "evidence_strength": "...",
  "caveat": "...",
  "sources": [{"title":"...","year":2026}],
  "authority": "authoritative",
  "retrieved_from": "knowledge.claims"
}
```

Example product context:
```json
{
  "content_type": "value_proposition",
  "body": "...",
  "product_run_id": "...",
  "valid_until": null,
  "authority": "authoritative"
}
```

## 16. Retrieval trace

Every agent run should be able to record a lightweight trace of what context was actually used/retrieved:
- tool/function name;
- query/filters or safe normalized descriptor;
- returned record/source identifiers;
- versions/hashes where useful;
- freshness/authority;
- latency;
- whether result was included in final context.

This is not chain-of-thought. It is operational observability.

## 17. Evaluation of knowledge quality

Minimum eval dimensions:
- authoritative source chosen correctly;
- current price/agenda not answered from stale semantic text;
- source relevance;
- claim/source linkage correctness;
- stale content detection;
- no unsupported scientific assertion;
- retrieval recall for known answer cases;
- context precision (not flooding model with irrelevant chunks);
- citation/source preservation where required.

## 18. Anti-patterns

- “Upload the whole site into vectors and let the LLM figure it out.”
- copying price/agenda into prompts;
- no source/version metadata;
- embeddings as source of truth;
- duplicating the same page into multiple product silos without canonical source mapping;
- treating every website sentence as a scientific claim;
- allowing ingestion to overwrite a more authoritative domain;
- never deleting/invalidating stale content;
- returning 40 chunks when 3 structured results suffice.

## 19. V1 implementation boundary

For Sales Summit V1 we only need enough ingestion/retrieval to support:
- authoritative product copy/content;
- current Summit agenda/people;
- current commercial data;
- small curated scientific/product knowledge set;
- site source registration/versioning pattern;
- semantic retrieval contracts.

Do not build a universal enterprise ingestion platform before the first vertical passes evals.