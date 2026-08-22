# Reference intake contract

A reference is evidence for a project decision, not decoration and not a gallery entry. Collect references to answer a stated question, evaluate them against the project, and record what was adopted and what was rejected with the reason.

A project that owns one reference produces work anchored to one accident. Widen the evidence base before blaming the output.

## Step 1 — state the question first

Write the question before collecting. Each question names the decision it will settle, for example: how do operations dashboards show a stalled item without alarming the operator, or how do menu cards handle nine items without a wall of text.

Collect against questions. Discard anything that answers none of them, however good it looks.

## Step 2 — collect from ranked sources

| Rank | Source | Use it for | Caution |
| --- | --- | --- | --- |
| 1 | Owner-supplied artifacts and links | the director's actual attraction, which is often unstated | ask what specifically drew them; the whole artifact is rarely the point |
| 2 | Owner's own shipped work | continuity and accumulated constraints | may encode an old compromise rather than a preference |
| 3 | First-party sources of real shipped products | how a pattern behaves in production | marketing pages flatter the product; prefer the real artifact |
| 4 | Curated capture libraries and design archives | breadth and fast coverage of a pattern space | freshness and attribution vary; verify the origin before recording |
| 5 | Secondary commentary, listicles, generated showcases | vocabulary and orientation only | never sufficient evidence on its own |

Use whichever tools the runtime actually provides for ranks 3 and 4 — a screenshot library, a research skill, a capture tool, direct retrieval. Record the tool used. Do not claim a source you did not open.

Cover both ends of every open axis from [taste-interview.md](taste-interview.md). A set that only shows one end cannot support a comparison.

## Step 3 — record each item

Each reference carries:

- stable identifier and where the artifact lives;
- source, owner, and retrieval date;
- which project question it answers;
- what specifically transfers — the pattern, not the whole artifact;
- what blocks transfer in this project;
- status: candidate, adopted, rejected, or deferred, with the reason;
- access and rights class.

Record what transfers at the level of a mechanism, not an adjective. "Groups by status with a persistent count so an operator sees pressure without opening anything" transfers. "Clean and modern" does not.

Rejected references stay in the record with their reason. A rejection prevents the same candidate returning next session and is direct evidence of taste.

## Take the structure, not only the rules

Extracting a list of rules from a reference and then arranging the result yourself throws away the part that took the original team longest to get right. Rules describe what a design avoids; the skeleton is what makes it read.

For an adopted reference, capture both:

- **the rule** — what it does and why it transfers;
- **the skeleton** — the actual arrangement: what occupies the most space, what the size ratio between the largest and smallest element is, where the eye is meant to land first, what is deliberately left empty, and what sits below the fold.

Reproduce the skeleton with the project's own content before adjusting anything. If the result looks wrong with real data, that is a finding about the project's content, not a license to redesign the arrangement from scratch.

A design that satisfies every extracted rule and still reads as flat is the signature of rules taken without structure.

## Step 4 — human adoption gate

Candidates become adopted taste evidence only by the design director's explicit selection. The team may recommend and must show the reasoning, but never promotes its own recommendation.

Present candidates for adoption in comparable groups tied to the question they answer. Do not present an undifferentiated pile and ask which ones are liked.

## Forbidden patterns

Collect rejected work with the same rigor as admired work, from the same ranked sources. For each, record the observable symptom, why it fails for this project, and its scope. An anti-pattern that cannot be tested by a reviewer without the director present is not finished.

Anti-patterns are the cheapest quality gate the project will ever own, because they are checkable before anything is produced.

**An empty forbidden list makes the scan a no-op.** A project with no recorded anti-patterns will pass every forbidden-pattern check while producing exactly the work the director keeps rejecting. Populate the list in the first session — the fastest source is the director's own rejections during taste elicitation, which cost nothing extra to collect. Until it holds at least the patterns the director has already rejected out loud, treat the scan as unrun and say so rather than reporting a pass.

## Volume and stopping

- Collect enough to cover both ends of every open axis; below that the comparison is decorative.
- Stop when new items stop changing the picture. Repetition is the signal that the pattern space is covered.
- Prefer a small set with sharp reasons over a large set with none. Every item must survive the question "which decision does this settle".

## Storage and rights

Artifacts and binaries stay in the owner project or the owner's designated asset store, following its existing conventions. Shared knowledge stores receive pointers, provenance, and approval metadata unless their own contract says otherwise. Never duplicate a binary into the shared skill repository.

Respect the source's rights and the project's privacy rules. Record attribution. Do not transmit private or confidential material to an external provider without authorization. Store the minimum needed to re-resolve the reference later.

## Freshness

References age as products ship redesigns. Record the retrieval date, mark an item stale when its source materially changes, and re-check before reusing an old set for a new decision. Superseded items are marked, not deleted.
