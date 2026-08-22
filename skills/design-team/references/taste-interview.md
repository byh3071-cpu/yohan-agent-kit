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

## The candidate itself must clear the bar

A comparison is only as good as the artifacts in it. If the candidates are cruder than what the project already ships, the director is choosing between two failures and the answer is noise.

Before showing any pair, check the candidates against the same standards the final work must meet:

- every recorded forbidden pattern — scan the candidates, not just the finished artifact;
- the project's existing quality floor — if the live product already handles spacing, hierarchy, or state better than your candidate does, the candidate is not ready;
- construction discipline — spacing and sizing drawn from a declared scale, not hand-entered values.

When you cannot build candidates that clear this bar, do not lower the bar. Use real artifacts from source 1 or 2 instead, and say plainly that fabricated candidates were not good enough to ask from.

Borrow proven skeletons rather than inventing layout for each comparison. Extracting rules from a reference and then designing the arrangement yourself discards the part that took the original team the longest.

## Step 3 — present pairs

- Two candidates per axis, shown together, never sequentially from memory.
- Hold everything else constant: same content, medium, scale or viewport, and state.
- Vary exactly one axis. If two move at once, the choice cannot be interpreted.
- Two options at a time during elicitation. The three-option rule in the report contract governs direction boards, not axis pairs.
- Accept four answers: A, B, neither, or conditional. Record a conditional as a rule with its condition, not as a failure.
- Do not lead, do not disclose which candidate the team prefers, and do not explain a candidate's virtues before the choice.
- When the director volunteers a reason, capture the exact wording. Do not paraphrase it into design vocabulary.

## Building the comparison sheet

Whatever carries the comparison — a document, a board, a printed set, a screen — is itself an artifact and follows the same rules as any other deliverable.

- Use the authoring skills, templates, and asset libraries the runtime and the project already provide. Hand-rolling the sheet each time reintroduces every mistake those tools exist to prevent, and it is how house rules get skipped.
- Choose the form by what is being compared. Comparing a screen means the sheet frames real screens at real size; comparing a physical piece means the sheet is physical or shows physical proofs.
- **Give the choices a way back.** A sheet the director can mark but that returns nothing to the team is a dead end — the choices are lost and the same questions get asked again. Whatever the medium, end with a form the director can hand back: a copyable summary, a returned sheet, a recorded decision. Verify the return path works before sending it, not after.
- Keep the sheet's own styling out of the way. It should not compete with the candidates it is presenting.

## When both options are rejected

"Neither" is not a failed question. It means the axis was framed wrong — both candidates shared an assumption the director does not accept, and that shared assumption is the real finding.

Do not re-ask the same axis with new decoration. Instead:

1. Name what the two rejected options had in common. That is the hidden assumption.
2. Build the next pair so one side breaks it.
3. Say out loud which assumption you are testing, so the director can correct the framing itself.

Two rejections on the same axis after reframing means the axis does not belong in this project. Record it as out of scope and move on.

## Deciding what to remove

Contrast comes from killing things, not from arranging them. A team that does not know which elements matter least will weight everything evenly, and evenly weighted screens read as flat no matter how well constructed.

When the outcome is an existing surface being reduced, run a removal pass before any visual work:

1. List every element currently on the surface — every counter, badge, panel, and control, not just the sections.
2. Have the director sort them: **used constantly / used occasionally / never used**.
3. Force one more answer: if only one element could stay, which one.
4. Everything in "never used" leaves the surface. Everything in "occasionally" moves behind a fold, a tab, or a detail view.

This is a sorting task, not a design discussion — it takes minutes and it replaces guesswork about importance with the director's own ranking. Without it, the team is choosing what to emphasize by intuition, which is exactly the thing this skill exists to prevent.

## When the purpose is unclear

If the surface's job cannot be stated in one sentence, visual options will differ only in arrangement and all of them will feel wrong. That is a symptom of an undefined outcome, not of weak visual work.

Stop and settle the purpose first. Offer competing purposes rather than competing styles: build each option around a different answer to "what is this surface for", and make the difference in *what is present*, not in how it is decorated. Choosing an option then settles the product definition, and what to remove follows from it.

Check the project's own stated intent before proposing purposes. A documented purpose that contradicts the live implementation is itself the finding, and the director needs to see that contradiction rather than a synthesis of both.

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
