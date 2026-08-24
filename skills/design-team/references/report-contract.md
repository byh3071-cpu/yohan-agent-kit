# Design Team report contract

Use the smallest set of artifacts that preserves the decision. Use stable project-owned identifiers; file-based projects should use project-relative paths and the owner's existing conventions.

## Artifact sequence

| Stage | Required artifact | Gate |
| --- | --- | --- |
| Discovery | DesignContext snapshot | material unknowns are explicit |
| Taste elicitation | confirmed taste rules, forbidden patterns with observable tests, open axes | the director confirms each read-back statement |
| Research / audit | evidence-backed findings, adopted skeletons, and keep/merge/hide/defer/remove decisions | facts and inferences are separated |
| Reduction (existing surface) | element inventory ranked by the director as used constantly / occasionally / never | removals are the director's ranking, not the team's guess |
| Structure | outcome, IA/flow, state model, approval boundaries | core job is understandable without visual polish |
| Exploration | exactly three real visual options when no visual is approved | human selects, combines, or rejects |
| Selection | decision-log entry with rationale and rejected directions | human approval |
| Specification | medium-appropriate visual, content, interaction, material, spatial, accessibility, and production rules | selected direction is producible |
| Handoff | actual production environment, source/asset/vendor/operational boundaries, verification plan; session continuation bundle when ownership moves | production may begin only after the named human gate |
| Verification | measured readings per the verification contract, forbidden-pattern scan, adversarial review, residual risks | final human acceptance or named quality gate |

## Research report

Lead with the decision implication, then include:

1. target user and job;
2. observed current behavior;
3. authoritative and first-party references;
4. useful patterns and why they transfer;
5. project constraints that block transfer;
6. keep / merge / hide / defer / remove recommendations;
7. confidence and open questions.

Do not make a gallery of famous products. Every reference must answer a project question.

## Direction board

Each of the three options must share the same core task, realistic content, and target medium, scale or context so differences are comparable. For interactive work, also hold the relevant viewport and state constant. Make the options materially distinct in hierarchy, composition, density, navigation, interaction, material, or spatial strategy—not merely color variants.

For each option provide:

- one-line design thesis;
- primary workflow and information hierarchy;
- strengths and failure modes;
- accessibility and medium-specific implications;
- production or implementation complexity;
- what project evidence it uses;
- what still requires validation.

Show all three together and stop for the design director's choice. Do not present a hidden fourth option or silently blend them.

## Design specification

Specify the applicable items; do not force software concepts onto another medium:

- target surfaces, media, dimensions, scale, viewports, and environmental conditions;
- grid, spacing, type, color, form, material, finish, imagery, icon, sound, or motion rules as relevant;
- regions, touchpoints, components, objects, or production pieces;
- empty, loading, error, partial, stale, success, selected, disabled, and destructive states as relevant;
- keyboard, focus, screen-reader, contrast, and target-size behavior;
- content hierarchy, labels, truncation, timestamps, ownership, freshness, and uncertainty;
- data, content, operational, fabrication, or service contracts and human approval boundaries;
- responsive, adaptive, print, fabrication, installation, or delivery transformation rules;
- measurable acceptance checks.

## Technical handoff

Map the selected design to the actual implementation or production environment:

- existing systems, assets, components, patterns, materials, vendors, or processes to reuse;
- proposed source files, assets, modules, production pieces, or vendor packages and why;
- relevant state, content, data, material, spatial, and operational mappings;
- allowed writes, fabrication changes, operational changes, and side effects;
- mock, prototype, proof, sample, fixture, or site-test strategy;
- test and visual QA plan;
- deferred debt and non-goals.

The handoff may recommend a medium-appropriate implementation skill or production owner. It must not mutate or release production work while selection is pending.

## Session transfer receipt

When ownership moves to another session, apply [session-continuity.md](session-continuity.md) and record separately:

- bundle path and source ref;
- launch prompt or message identifier;
- delivery channel and result;
- recipient acknowledgement evidence;
- current approval state and production boundary;
- exact next human decision.

Use `prepared`, `sent`, `acknowledged`, or `failed`. Do not collapse writing, sending, and receiving into one `completed` status.

For regulated or safety-critical work, add the governing framework/version, intended use, hazards and risk controls, requirement traceability, protected safety semantics, and the named qualified approver. Keep design QA distinct from formal validation and compliance evidence.

## Final receipt

End with:

- selected outcome and human gate status;
- artifact paths and source refs;
- team/provider receipt;
- session transfer state and acknowledgement evidence when applicable;
- verification performed and evidence;
- known residual risks;
- exact next action.
