# Design session continuity contract

A new session must resume the design relationship, not merely receive a summary. The project owns the durable state; conversation history, a terminal buffer, and a worker transcript are supporting evidence only.

Use this contract when a design workstream pauses, changes conductor, moves to another session or machine, or separates into an independently owned design session.

This contract is the design-domain extension of the generic [restart-safe handoff](../../restart-safe-handoff/SKILL.md). The generic skill owns durable bundle, writer ownership, takeover, and content-versus-delivery receipt semantics; this document adds design approval, taste, artifact visibility, and production-boundary semantics. If the generic skill is not installed, this contract still defines the complete design continuation behavior required here.

## Project-owned continuation bundle

Use the owner's existing versioned documentation convention. Do not create a parallel source of truth. A complete bundle resolves these fields, either in one handoff file or through stable pointers:

- owner project, workstream, branch or source version, and current commit or artifact revision;
- current design state and the difference between technical validation, direction selection, final visual acceptance, and production authorization;
- confirmed taste rules, calibrated forbidden patterns, adopted and rejected references, and still-open axes;
- the director's working vocabulary, preferred language, and confirmed interaction rules that affect the design dialogue;
- selected, rejected, and deferred directions with stable artifact identifiers and reasons;
- visible evidence for the current candidate, including target medium, viewport or scale, state, data, and verification status;
- unresolved contradictions, residual risks, and freshness triggers;
- the exact next human decision and the first useful artifact or question to present;
- allowed writes, prohibited work, and the production boundary;
- skills, tools, providers, and exposed model labels needed to resume, with substitutions or uncertainty;
- transfer receipt and recipient acknowledgement state.

Point to the current DesignContext, decision log, specification, verification receipt, and artifacts instead of copying them. A handoff is an index and continuation contract, not a second archive.

## Approval semantics

Keep these states separate:

| State | Meaning | What it authorizes |
| --- | --- | --- |
| continue | proceed with the immediately described next design action | only that action |
| direction selected | use the named candidate or combination for further refinement | specification and further design validation, not production |
| final design accepted | the named artifact, revision, medium, and state are accepted | handoff may be prepared |
| production authorized | implementation, fabrication, publishing, or operational change may begin within the named scope | only the approved production scope |

A short acknowledgement such as “yes”, “continue”, or its local-language equivalent confirms the immediately stated next action. It does not create a taste rule, select an unnamed artifact, grant final acceptance, or authorize production unless the preceding gate explicitly names that consequence and artifact.

Record final acceptance with the artifact identifier or revision, scope, date, and decider. When the wording is ambiguous, preserve the lower state and ask at the next material gate rather than silently promoting it.

## Visual delivery receipt

Generation or capture success does not prove that the director saw the artifact. Before asking for a visual choice:

1. save the artifact in the owner project or its approved asset store;
2. identify the exact revision, medium, viewport or scale, state, and realistic content used;
3. render or attach it through the current conversation surface;
4. provide a stable project-owned path or link as a fallback;
5. confirm the surface returned the artifact rather than only a text placeholder or tool receipt.

If the director reports that an image is missing, stop the selection gate. Re-deliver the same revision or a stable fallback before discussing preference. Never generate a new option merely to work around a delivery failure, because that changes the comparison.

Record delivery as `prepared`, `rendered`, `director-visible`, or `failed`, with evidence. Do not infer `director-visible` from a successful image tool call.

## Closing the current session

1. Reconcile the DesignContext, decision log, taste record, verification receipt, and artifact paths.
2. Separate observed facts, confirmed decisions, inferences, proposals, and stale claims.
3. Name the approval state and production boundary explicitly.
4. Record the exact continuation point: one next human decision, not a backlog dump.
5. Write a launch prompt that contains stable pointers and the first task, not copied private context.
6. Preserve changes in the owner project's normal versioning flow when authorized.
7. Deliver the prompt or report through the approved session channel and obtain a recipient acknowledgement when transfer is requested.

Transfer states are distinct:

- **prepared** — the bundle exists at stable identifiers;
- **sent** — a named channel accepted the payload;
- **acknowledged** — the target session identified the project, source ref, current gate, and next action;
- **failed** — the target or channel could not be verified.

Writing or committing a report is not evidence that another session received it. A send command is not an acknowledgement. Report the highest state supported by evidence.

## Starting the next session

Before producing new design work, the receiving conductor:

1. reads the nearest project instructions and stop files;
2. resolves the continuation bundle and every stable pointer needed for the next gate;
3. checks the branch, source ref, dirty state, freshness triggers, and production boundary;
4. separates inherited confirmed decisions from open or stale questions;
5. checks that the artifacts named for the next decision are actually visible or reachable;
6. replies with a compact acknowledgement: project and workstream, current approval state, inherited taste constraints, exact next gate, and any contradiction that prevents safe continuation.

Do not repeat resolved taste questions or ask the director to restate the project. Begin with the recorded next artifact or one unresolved decision. If the bundle conflicts with live evidence, show the contradiction instead of blending the two.

The receiving session owns the conversation after acknowledgement. Prior workers may supply evidence but must not separately interview the director.

## Failure recovery

- Missing bundle: remain in Discover mode and rebuild from project evidence; do not claim continuity.
- Stale source ref: re-resolve affected claims and mark what changed before visual work.
- Missing artifact: pause the choice and restore the exact referenced revision.
- Missing acknowledgement: report `prepared` or `sent`, never `transferred` or `received`.
- Wrong target session: do not resend blindly; re-resolve the target and preserve the failed receipt.
- Unknown provider or model: record the exposed tool label and uncertainty, not an inferred backend.

Project facts, private dialogue, and taste values stay in the owner project. The shared skill stores only this method.
