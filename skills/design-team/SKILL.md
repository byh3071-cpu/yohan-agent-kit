---
name: design-team
description: Use when a project needs context discovery, design research, UX or information architecture, visual direction exploration, human selection, design specification, critique, or production handoff. Operates a right-sized design team for digital, print, spatial, service, hardware, brand, and other domains while preserving project-owned context and decisions. Do not use for routine production of an already approved design.
---

# Design Team

Run a context-led design workstream in which the user remains the design director. Adapt the roles, evidence, artifacts, and tools to the project instead of applying a fixed aesthetic or fixed vendor lineup.

## Start with context

1. Find the actual owner workspace or repository and read its nearest instructions, active work state, and stop files before making changes.
2. Find existing product flows, screens, tokens, components, brand assets, research, screenshots, and prior decisions. Prefer project evidence over remembered assumptions.
3. Resolve the two-layer context contract in [context-contract.md](references/context-contract.md). Reconcile stale or contradictory facts; never silently pick one.
4. Resolve the project's taste record, forbidden patterns, and reference set. If none exists, is stale, or covers a different medium, a taste pass precedes visual work — do not substitute the team's own aesthetic.
5. State the design outcome, user, surface, constraints, current evidence, unknowns, and the next human gate.
6. Choose the smallest team that covers the uncertainty using [team-contract.md](references/team-contract.md).

Do not store project facts in this skill. The reusable method belongs here; project facts and decisions belong in the owner's versioned source of truth, using Git where the project uses Git.

## Choose the work mode

- **Discover** — inventory context, identify uncertainty, and produce a design brief. Do not invent a visual direction.
- **Elicit** — establish or refresh the taste model with the design director through structured comparison, using [taste-interview.md](references/taste-interview.md). Produces confirmed taste rules and forbidden patterns, not artifacts.
- **Audit** — critique an existing experience against its goals, system, accessibility, and evidence. Separate observed defects from proposals.
- **Explore** — collect references under [reference-intake.md](references/reference-intake.md), define information architecture and flows, then create visual directions.
- **Specify** — turn a human-selected direction into the visual, content, interaction, material, spatial, accessibility, and production rules relevant to its medium.
- **Handoff** — map an approved design to the actual implementation or production environment and verification plan.

For a faithful reproduction or an already approved source, match that source. For open visual exploration without an approved target, create exactly three materially different visual options with a real visual tool, present them together, and wait for the user's selection before production work.

## Operate the design loop

1. **Frame** — write or refresh the project DesignContext and cite evidence with freshness.
2. **Elicit** — resolve or establish the taste model with the design director. Show real candidates and let the director choose; do not ask for style in words. Read the choices back as explicit rules and get them confirmed.
3. **Gather** — collect references against stated project questions under [reference-intake.md](references/reference-intake.md), and use authoritative primary sources for standards. Collect rejected work with equal rigor. Label facts, inferences, and proposals.
4. **Reduce** — decide what to keep, merge, hide, defer, or remove before adding new design elements.
5. **Structure** — define the core job, hierarchy, flow, state model, and approval boundaries.
6. **Visualize** — create the required artifact at its real viewport, print size, physical scale, or environmental context with realistic content and materials. Check it against the recorded forbidden patterns before showing it.
7. **Select** — record the user's chosen, rejected, or deferred direction and why. The team does not self-approve.
8. **Specify** — define the relevant visual, content, interaction, material, spatial, accessibility, and production rules.
9. **Handoff** — connect the specification to the real implementation or production environment without replacing established systems.
10. **Verify** — measure against [verification-contract.md](references/verification-contract.md) in the real medium and runtime, scan for forbidden patterns, run an adversarial critique, and record readings and residual risks.
11. **Close** — update the project context snapshot, including the taste record, and append the decision event. Nominate reusable learning for shared promotion; never auto-promote project facts.

## Gates and boundaries

- The user decides visual direction, density, layout, interaction, and final acceptance.
- Do not begin production implementation before visual selection unless the user has supplied an already approved target.
- Do not create visual directions against an empty or stale taste record. Run the taste pass first, or say plainly that directions are being produced without a taste model and that rejection is the expected outcome.
- Do not present taste inferences the director has not confirmed as if they were approved rules.
- Do not create a supposedly independent top-level design session as a child worker. Use a separate approved worktree/session and leave a project-owned handoff.
- Follow local concurrency, worktree, write, privacy, cost, deployment, and release rules.
- Do not transmit private assets or source material to an external provider without authorization.
- Do not claim an unexposed backend model name. Record the tool and model labels actually shown by the runtime.
- Never use prose boxes, ASCII, emoji, handcrafted SVGs, or placeholder rectangles as substitutes for requested visual design artifacts.
- Keep generated binaries and approved artifacts in the owner project. Shared knowledge stores receive pointers, provenance, and approval metadata unless their contract explicitly says otherwise.

For regulated or safety-critical work, record the governing jurisdiction or framework and version, intended use, use-related hazards and risk controls, and required traceability. Require the named qualified human approver required by the local quality system. Design critique, visual QA, or design-director approval is not regulatory validation or evidence of compliance. Do not vary safety-critical behavior, alarm semantics, or risk controls in exploration without approved traceability.

For a code-based responsive interactive HTML outcome, hand approved work to an implementation skill such as `design-to-html`. For print, spatial, service, hardware, or other media, hand off to the project-authorized production owner or medium-appropriate implementation method.

Before delivering an artifact or handoff, measure against [verification-contract.md](references/verification-contract.md) and apply [report-contract.md](references/report-contract.md).

For a walkthrough of how a full run proceeds and what the design director is asked to do at each gate, see [operating-manual.md](references/operating-manual.md).
