---
name: runtime-incident-investigator
description: Use when an ambiguous failure spans application, runtime, terminal, provider, or project state and needs read-only evidence, a timeline, competing hypotheses, and disproof. Do not use for live worker supervision, session handoff, or a localized code bug with an established cause.
---

# Runtime incident investigator

Determine what is observed, what is inferred, and what would disprove each explanation before proposing a mutation. Diagnosis does not authorize a fix.

## Start read-only

Read the nearest project rules and stop files, preserve current logs and timestamps, and avoid restart, retry storms, process termination, cache clearing, reset, installation, authentication changes, or shared-state writes. Request authorization immediately before any later mutation that requires it.

Separate the incident into five evidence layers:

| Layer | Read-only questions |
| --- | --- |
| App | What did the user-facing control plane or application actually display or return? |
| Runtime | Was the coordinating service, daemon, scheduler, or session runtime reachable and internally ready? |
| Terminal | Did the expected process exist, produce output, exit, detach, or lose its stream? |
| Provider | What exposed availability, quota, authentication, transport, or provider response was directly observed? |
| Project | What were cwd, source reference, dirty state, stop files, configuration, inputs, and artifact paths? |

Do not let evidence from one layer silently stand in for another. A terminal exit does not prove provider failure; an application error does not prove project corruption.

## Build an evidence timeline

Normalize each event as: reported time, clock source and precision, layer, observation, evidence reference, and confidence in ordering. Preserve missing intervals and clock uncertainty. Use monotonic or sequence evidence when available; wall-clock equality alone does not order events.

Classify every claim:

- **Observed** — directly present in a log, status surface, file, process result, or user-visible response.
- **Inferred** — an explanation connecting observations; state assumptions and confidence.
- **Disconfirmed** — contradicted by named evidence or a discriminating check.
- **Proposed check** — the smallest read-only observation that would separate live hypotheses.

For each hypothesis, record supporting evidence, counterevidence, a plausible alternative, and a disproof condition. Prefer the next check with the highest discrimination and lowest side effect.

## Do not manufacture causality

Events reported at the same time are correlated only. For example, `ENOENT` supports that a referenced path was absent at one operation, while runtime unavailability supports that a runtime surface could not be used. Neither observation proves it caused the other without a shared process, trace, dependency, or ordered mechanism. Investigate both layers and test any proposed common cause.

Absence of a log is not proof that an event did not occur unless the log's coverage and retention are established. A successful retry is not proof of the original cause.

## Use live evidence conditionally

When current structured coordination state is material and the installed `orchestration` skill is available, load its version-matched live guide before any call. For managed terminal, worktree, or application-runtime surfaces, use the installed `orca-cli` skill and its live guide. Do not cache commands or versions. If a live surface is unavailable, record that as an observation and continue with other authorized layers rather than inventing state.

## Report the incident

Return the layer status, bounded timeline, observed facts, ranked hypotheses with confidence, counterevidence, disproof conditions, the smallest next check, and any evidence-preservation risk. State whether the cause is established, narrowed, or unknown. Do not implement remediation unless the user requested it and the required mutation gate is satisfied.
