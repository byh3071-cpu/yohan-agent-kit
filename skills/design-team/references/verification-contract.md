# Verification contract

Verification is measurement, not impression. "Looks right" is not a result. Every acceptance check names what was measured, in what condition, against what threshold, and what the reading was.

Run verification in the real medium and the real runtime. A preview that parses, scales, or renders differently from the delivery environment produces readings that do not hold.

## What every verification records

| Field | Meaning |
| --- | --- |
| Check | what was measured |
| Condition | medium, size or viewport, state, environment, and data used |
| Threshold | the pass line and where it comes from |
| Reading | the measured value |
| Verdict | pass or fail |
| Evidence | artifact, capture, log, or tool output that can be re-examined |

A check with no reading is not a check. A check that never fails on wrong input is not a check either — validate the gate itself against a deliberately broken sample before trusting it.

## Baseline thresholds

These are defaults. A project may set stricter lines, and a regulated project must use its governing standard instead. A project may not lower a line without recording who approved it and why.

### Any designed artifact

| Check | Baseline |
| --- | --- |
| Anti-pattern scan | zero occurrences of the project's recorded forbidden patterns |
| Taste conformance | every confirmed taste rule in scope is satisfied, or the deviation is listed with a reason |
| Real content | measured with realistic content volume, longest realistic labels, and empty and overflowing cases — never lorem or convenient sample data |
| Comparison basis | the approved direction and the produced artifact compared in the same medium, size, and state |

### Screen and interactive

| Check | Baseline |
| --- | --- |
| Text contrast | 4.5:1 body, 3:1 for large text and meaningful non-text elements |
| Horizontal overflow | none at every declared width |
| Declared widths | verified at the project's stated breakpoints, smallest first |
| Interactive target size | meets the platform's minimum, measured on rendered output |
| Keyboard reachability | every interactive element reachable and visibly focused |
| State coverage | empty, loading, error, partial, stale, success, selected, disabled, and destructive states verified where they exist |
| Rendered dimensions | bars, charts, and meters have non-zero measured size, not merely present markup |
| Spacing and radius scale | values drawn from the declared scale; count distinct values and flag hand-entered ones |
| Text wrapping | verified in every shipping language, including languages where naive wrapping breaks words incorrectly |

### Print and produced media

| Check | Baseline |
| --- | --- |
| Physical proof | verified at final size, not on screen alone |
| Resolution and color space | meets the producer's specification |
| Bleed, trim, and safe area | present and correct |
| Legibility | verified at real reading distance |

### Spatial, hardware, and service

| Check | Baseline |
| --- | --- |
| Scale | verified at real scale or a calibrated mockup, never from a rendering alone |
| Environmental conditions | verified under the lighting, noise, weather, or traffic the artifact will meet |
| Path and reach | verified against the real body, equipment, and accessibility requirements |
| Service rehearsal | walked through with real staff constraints, including the failure and recovery paths |

## Anti-pattern scan

Run the project's recorded forbidden patterns as an explicit checklist before human review. Each anti-pattern carries an observable test from the intake contract, so the scan produces verdicts rather than opinions.

This scan is the main defense against work that satisfies every functional requirement and still reads as generic. Run it on the direction board, not only on the final artifact — a generic direction cannot be rescued in production.

**Everything the team shows the director is in scope**, including comparison sheets, elicitation candidates, mockups, and throwaway examples. The team's own working artifacts are where recorded anti-patterns reappear most easily, because they feel too temporary to check. A rejected pattern that shows up in the next thing the director sees costs more trust than the original mistake.

**Calibrate each observable test against the artifact that was actually rejected.** Write the test, run it on the rejected artifact, and confirm it fails. A test derived from the description of a rejection rather than the rejection itself will usually mis-fire — either flagging acceptable work or missing the real thing. Expect to revise the test more than once; a test that has never produced a failure has not been calibrated at all.

## Adversarial review

After measurement passes, run an independent critique that tries to defeat the work rather than confirm it: the state nobody built, the longest real name, the slowest connection, the smallest supported size, the colorblind reader, the operator under time pressure, the second language.

Give the critic the goals, the taste record, and the artifact, but not the team's rationale. A critic told why a decision was made will rationalize it.

## Failure handling

A failed check is fixed and re-measured, not annotated and shipped. When a fix is out of scope, record the failure as a named residual risk with its impact and the decision to accept it, and route acceptance to the design director. Never mark a stage passed while a check inside it failed.

Report readings even when they pass. A verification section with no numbers is a claim, not evidence.

## Scope limit

Design verification measures whether the artifact matches its intent, its taste record, and its accessibility and production baselines. It is not regulatory validation, safety certification, or compliance evidence. For regulated work, keep the two records separate and route formal validation to the qualified approver named by the governing quality system.
