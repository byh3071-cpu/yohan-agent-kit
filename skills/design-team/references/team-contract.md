# Adaptive team contract

Compose roles from the problem's uncertainty. Do not hardcode a model, vendor, or headcount into the reusable skill.

## Required ownership

- **Design conductor** — owns the user dialogue including taste elicitation, context integrity, synthesis, gates, session continuity, and final handoff. Only one role holds the director dialogue; parallel workers must not interview the director separately.
- **Design director** — the user or named human who selects direction and approves acceptance.

One agent may cover all other roles when the task is small. Add separation when independent evidence or critique improves the decision.

## Optional roles

| Role | Add when | Primary output |
| --- | --- | --- |
| Context / product researcher | product intent, users, or current state is unclear | evidence-backed DesignContext |
| Taste elicitor | the director's preferences are unrecorded, stale, or repeatedly missed by the work | confirmed taste rules and forbidden patterns per [taste-interview.md](taste-interview.md) |
| UX / service designer | flows, roles, approvals, or failure recovery matter | journey, IA, state and boundary model |
| Reference scout | the design space or pattern choice is uncertain | attributed candidate set answering stated questions, per [reference-intake.md](reference-intake.md) |
| Visual designer | a visual target must be created | real direction boards and selected visual |
| Content / information designer | dense, regulated, multilingual, or action-heavy content | hierarchy, terminology, content rules |
| Domain specialist | safety, legal, medical, finance, hardware, spatial, or other expertise matters | domain constraints and risk review |
| Accessibility reviewer | any user-facing interaction or content is designed | keyboard, contrast, target, semantics review |
| Motion / brand / spatial specialist | that medium materially changes the experience | medium-specific specification |
| Production / technical designer | design must fit an implementation, fabrication, publishing, service, or operational environment | production boundaries and handoff mapping |
| Adversarial critic | the choice is costly, novel, or visually approved | independent attack, failure cases, residual risk |

## Sizing

- **Focused** — one conductor covers the needed roles; use for a local critique or a bounded component.
- **Standard** — separate research/UX, visual, technical, and critique responsibilities where useful.
- **Program** — evaluate whether isolated workstreams or worktrees are needed for cross-surface, cross-repository, regulated, or release-level design; use only the separation required by local controls.

Use local routing rules when they are stricter. Same-repository concurrent editing must follow the project's worktree and branch policy.

## Assignment rules

1. Select roles after context discovery, not from a fixed org chart.
2. Give each worker a concrete question, evidence boundary, expected artifact, and write scope.
3. Prefer read-only workers for research and critique. Give write ownership to one worktree per repository/branch.
4. The conductor reconciles disagreements and preserves dissent; workers do not decide the final direction.
5. If a requested provider or model is unavailable, use an available equivalent and disclose the substitution.
6. Use the director's confirmed language and vocabulary, present one material decision at a time, and distinguish a conversational acknowledgement from direction selection or final acceptance.

## Independent design session

When the user asks for a separately owned top-level design session:

- use a dedicated branch and approved worktree when the owner project uses Git, or the equivalent isolated and versioned workspace for other media;
- give it design research, directions, and medium-appropriate specification scope;
- prohibit production work until the design director selects a target;
- hand over a project-owned context bundle with stable identifiers and a launch prompt;
- require the receiving conductor to acknowledge the source ref, approval state, production boundary, and exact next gate under [session-continuity.md](session-continuity.md);
- do not describe a subordinate worker as an independent top-level session;
- let the independent session own its own conversation while the implementation lineage consumes only approved artifacts.

## Provider receipt

For each material contribution record:

- role;
- runtime/provider and exposed model label, if available;
- tool or skill used;
- read/write scope;
- artifact or decision produced;
- validation status;
- uncertainty or substitution.

If the image tool exposes only `ImageGen`, record `ImageGen`. Do not infer or market an unverified backend model name.
