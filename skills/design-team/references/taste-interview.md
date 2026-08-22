# Taste elicitation contract

People cannot state their own taste accurately in words. "Modern", "clean", "premium" produce generic work because they carry no decision. Elicit taste by structured comparison against real candidates, then read the choices back as explicit statements the design director confirms.

Never skip this and substitute the team's own aesthetic. A design team without a recorded taste model restarts from zero every session and produces work the director keeps rejecting without being able to say why.

## When to run

Run a taste pass when:

- no confirmed taste record exists for this project and medium;
- the existing record is stale, contradicted by a recent decision, or was inherited from a different medium;
- a new surface, medium, or audience enters scope;
- the director rejects two consecutive direction sets — that signals a wrong taste model, not weak execution.

Skip when the director supplied an already approved target to match, or when an active confirmed record already covers every axis this work touches.

## Step 1 — choose the axes before showing anything

1. List the decisions that will visibly change this outcome in this medium.
2. Remove every decision already fixed by an existing design system, brand standard, regulation, platform convention, or accessibility requirement. Those are constraints, and asking about them invites an answer that cannot be honored.
3. Keep only axes where both ends are genuinely defensible for this project.
4. Order by how much downstream work each axis controls.
5. Cap the first session at four to seven axes. Remaining axes wait for a later session.
6. Name each axis in the director's own vocabulary, not design jargon.

An axis is a real choice with two defensible ends, not a quality scale. "Dense or airy" is an axis. "Good or bad hierarchy" is not.

| Medium | Example axes |
| --- | --- |
| Screen product | information density, role of color, grouping unit, navigation placement, emphasis unit, state expression |
| Print | text-to-white ratio, image dominance, grid strictness, stock and finish weight, typographic contrast |
| Spatial | openness, path directness, material warmth, lighting temperature, signage prominence |
| Brand system | wordmark weight, palette breadth, voice formality, motif abstraction |
| Service | staff visibility, self-service depth, recovery formality, communication frequency |

Do not reuse a list from another project without re-deriving it here.

## Step 2 — source candidates, never invent them

Every candidate shown must come from one of three sources:

1. **Director-approved existing work** — their current product, previously approved artifacts, brand assets, published output. Strongest evidence, because it is already accepted.
2. **Real shipped artifacts** — first-party product sources or captured references collected under [reference-intake.md](reference-intake.md).
3. **A controlled pair built from the project's own content** — the same real data or copy rendered twice, varying exactly one axis.

Forbidden as candidates: imagined descriptions, prose boxes, mood words with no artifact, ASCII or placeholder rectangles, and galleries of famous products that answer no project question.

Prefer source 3 for axes where the project's own content changes the answer, such as density with real record counts or truncation with real names. Prefer sources 1 and 2 where the axis depends on craft the team cannot fabricate quickly.

Match the candidate's fidelity to the axis. Do not ask about color from a grayscale sketch, or about density from a screenshot holding a different amount of content.

## Step 3 — present pairs

- Two candidates per axis, shown together, never sequentially from memory.
- Hold everything else constant: same content, medium, scale or viewport, and state.
- Vary exactly one axis. If two move at once, the choice cannot be interpreted.
- Two options at a time during elicitation. The three-option rule in the report contract governs direction boards, not axis pairs.
- Accept four answers: A, B, neither, or conditional. Record a conditional as a rule with its condition, not as a failure.
- Do not lead, do not disclose which candidate the team prefers, and do not explain a candidate's virtues before the choice.
- When the director volunteers a reason, capture the exact wording. Do not paraphrase it into design vocabulary.

## Step 4 — read back and confirm

Elicitation is not finished at the last choice. Convert the choices into explicit statements and have the director confirm each one.

Each statement carries:

- the rule, in plain language;
- its scope — which surfaces, media, or contexts it governs;
- the reason, quoted when the director gave one and labeled `Inferred` when the team derived it;
- confidence and what would change it.

The director confirms, edits, or rejects each statement. Only confirmed statements become taste records. Inferred statements that go unconfirmed stay open questions and must not be used as if approved. Never present a read-back that adds a rule the choices do not support.

## Step 5 — collect what the director rejects

Run a forbidden-pattern pass with the same discipline. Ask for concrete artifacts the director dislikes rather than abstract dislikes, then convert each into an anti-pattern with an observable test that a reviewer can apply without the director present.

A usable anti-pattern names the observable symptom, the reason it fails here, and its scope. "Looks AI-generated" is not usable until it names what is observable: uniform card grids, centered hero with three equal features, gradient-on-gradient, decorative icons carrying no information, or whatever the director actually points at.

Rejections are as valuable as preferences and are frequently more stable. Record them with equal care.

## Session budget

- First session: four to seven axis pairs plus one forbidden pass, then stop.
- Later sessions: only new, contradicted, or previously deferred axes.
- Never re-ask a confirmed axis without new evidence, and say what the new evidence is when you do.
- Watch for fatigue — one-word answers, "whatever", "you pick", or reversals within a session. Stop, record the remaining axes as open, and continue another time. A tired director's answers pollute the record.

## Output

- confirmed taste records;
- anti-pattern records with observable tests;
- conditional rules with their conditions;
- open axes and unconfirmed inferences.

Store them under the project's context contract, in the taste section defined by [context-contract.md](context-contract.md). The shared skill repository holds this method only; the values belong to the owner project or the owner's designated knowledge store.

## Freshness

Taste drifts and context changes it. Re-verify when the medium changes, when the director rejects two consecutive direction sets, when the product's audience or purpose shifts, or when the project's stated recheck interval elapses. Mark superseded records rather than deleting them — a reversal is itself evidence.
