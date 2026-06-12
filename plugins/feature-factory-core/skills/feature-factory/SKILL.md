---
name: feature-factory
description: Run a full feature build by chaining eight specialist subagents — codebase-researcher, story-writer, spec-writer, backend-builder, frontend-builder, test-verifier, e2e-author, implementation-validator — with three human approval gates and a validator loop-back on critical findings. Triggers when the user asks to "build a feature", "ship a feature", "implement a feature", "run the full chain", or invokes the "feature factory". Use for end-to-end feature work, not single-agent tasks or one-off questions.
---

# Feature factory

This skill is the canonical step order for the eight-agent chain. The `feature-orchestrator` agent loads this skill as its source of truth; you can also invoke the skill directly when a user asks to run the chain.

Do not skip steps. Do not reorder. The approval gates and the loop-back rule exist because shortcuts at any of them have produced rework in past runs.

This chain is stack-agnostic. The builder, verifier, and validator agents discover the project's stack, test/e2e harness, and conventions themselves — by reading the repo, its `CLAUDE.md`, and its docs — and consult a `stack-conventions` skill if one is installed as an overlay for that stack.

## Inputs

- A rough feature idea from the user (one sentence to a few paragraphs).
- The user's responses at each of the three approval gates.

## Rules that apply to every step

- **Always invoke specialists through subagent invocation.** Never inline a specialist's work into your own context. Each agent has its own context window — that is the point.
- **Pass each agent only what it needs.** See "How to invoke each agent" below.
- **Never edit code directly from this skill.** All code changes go through a builder agent.
- **If any agent fails** (errors, returns unparseable output, or reports it cannot complete the work without violating a rule), stop the chain, name the agent, show its output, and wait for the user. Do not silently retry. Do not route around the failure.

## How to invoke each agent

| Agent | Input |
|---|---|
| `codebase-researcher` | the user's rough idea framed as "how does X work today?" |
| `story-writer` | the rough idea + researcher findings + any user-added rules |
| `spec-writer` | the approved user story + researcher findings |
| `backend-builder` | the approved brief + researcher findings |
| `frontend-builder` | the approved brief + researcher findings + backend-builder's summary (the API contract) |
| `test-verifier` | the approved story + the approved brief + both builder summaries |
| `e2e-author` | the approved story + the approved brief + both builder summaries + the test-verifier's coverage map (so it sees which ACs still need browser coverage). e2e-author reads the actual code on disk to ground its selectors and HTTP calls. |
| `implementation-validator` | the approved story + the approved brief + the test-verifier's report + the e2e-author's report (spec list + flagged divergences) |

If a hand-off requires fabricating something a prior agent didn't produce, stop and report the gap.

## The chain

### 1. codebase-researcher
Invoke `codebase-researcher` to map the area of code involved. Capture its findings; pass them forward to every later step that needs them.

### 2. story-writer
Invoke `story-writer` with the user's idea + researcher findings. Capture the user story, acceptance criteria, edge cases, and out-of-scope items.

### 3. ASK HUMAN — approve the story
Present the story to the user. Ask explicitly: approve, request changes, or reject?

- **Approved** → continue to step 4.
- **Changes requested** → re-invoke `story-writer` with the user's specific feedback appended to its input. Return to step 3. Repeat until approved or rejected.
- **Rejected** → stop the chain. Produce a short summary of what was explored (researcher findings + the rejected story + the user's reason) so the human can decide what to do next. End the run.

### 4. spec-writer
Invoke `spec-writer` with the approved story + researcher findings. Capture the technical brief (data model, flow, API, frontend, tests required, risks, files that will change).

### 5. ASK HUMAN — approve the brief
Present the brief to the user. Ask explicitly: approve, request changes, or reject?

- **Approved** → continue to step 6.
- **Changes requested** → re-invoke `spec-writer` with the user's specific feedback appended. Return to step 5. Repeat until approved or rejected.
- **Rejected** → stop the chain. Keep the approved story on hand so the user can resume later with a different technical approach. Produce a short summary (approved story + rejected brief + user's reason) and end the run.

### 6. backend-builder
Invoke `backend-builder` with the approved brief + researcher findings. The agent reads `CLAUDE.md`, discovers the project's stack and conventions (consulting a `stack-conventions` skill if one is installed), implements the backend half (services, API routes, jobs, migrations, server-side helpers) with unit tests, runs the project's typecheck/lint/test commands, and returns a summary including the API contract.

If the agent reports a failure or a rule conflict it cannot resolve, stop and surface it.

### 7. frontend-builder
Invoke `frontend-builder` with the approved brief + researcher findings + the backend-builder's summary (so it has the exact API contract). The agent implements the frontend half with component/unit tests, runs the project's typecheck/lint/test commands, and returns a summary.

If it reports a backend mismatch in its handoff section, loop back to `backend-builder` scoped to that mismatch, then re-run `frontend-builder`. Otherwise continue.

### 8. test-verifier
Invoke `test-verifier` with the approved story + approved brief + both builder summaries. It writes acceptance tests in the project's test harness covering every acceptance criterion and the listed edge cases, runs them and the full suite, and returns a coverage map.

If its coverage map reports an uncovered criterion that's blocked on a builder (e.g., missing API field, missing UI affordance), loop back to that builder scoped to the gap, then re-run `test-verifier`.

### 9. e2e-author
Invoke `e2e-author` with the approved story + approved brief + both builder summaries + the test-verifier's coverage map. It reads the actual code on disk (routes, components, API response shapes), then writes specs in the project's e2e harness for every AC that has a user-visible surface. It runs each spec it writes (using the project's e2e command) before handing off, and produces a coverage map + a list of any divergences it found between the spec and the implementation.

If e2e-author flags critical implementation divergences (e.g., a route file is missing on disk, a component renders fundamentally differently from the brief), surface them now and loop back to the appropriate builder before continuing to step 10.

### 10. implementation-validator
Invoke `implementation-validator` with the approved story + approved brief + test-verifier's report + e2e-author's report. It runs the project's static checks (typecheck, lint, unit/acceptance tests) AND the full e2e suite, reads the changed files, and returns findings grouped as Critical / Important / Minor / Opinion, plus a "Recommended next agent" line.

### 11. Loop-back on critical findings
- **Critical findings present** → loop back to the agent named in the validator's "Recommended next agent" line, scoped **only** to the specific critical findings. Routing:
  - Backend/service/migration → `backend-builder`
  - Component/page/hook → `frontend-builder`
  - Unit/acceptance coverage gap → `test-verifier`
  - Wrong selector / wrong method / missing spec → `e2e-author`
  - After any builder loop-back that touched user-facing flows, re-run `e2e-author` BEFORE re-running the validator — its specs may need to be updated to match the new implementation.
- **Important / Minor / Opinion findings only** → continue to step 12. The user will decide on these at the final review.

Guard: if the same critical finding survives **two** loop-back attempts, stop and escalate to the user. Something structural is wrong; another iteration won't fix it.

### 12. ASK HUMAN — final review
Present to the user:
- the validator's full findings (Critical should be empty by now; surface Important, Minor, and Opinion);
- a summary of what was built, files changed, and tests added.

Ask explicitly: ready to open PR, loop back, or waive specific findings?

- **Ready** → produce the final summary (see below) and end the run.
- **Loop back** → route to the agent the user names, scoped to the user's specific request, then re-enter the chain at the appropriate step.
- **Waive specific findings** → record each waived finding with the user's reason in the final summary, then produce it and end the run.

## Final summary

When the chain ends successfully, produce:

- **Feature shipped** — one-sentence restatement.
- **User story** — the approved story, verbatim.
- **Files changed** — bulleted, grouped backend / frontend / tests, pulled from the builders' and verifier's summaries.
- **Tests added** — bulleted, from the test-verifier's coverage map.
- **Validator findings waived** — bulleted, each with the user's reason. Empty if none.
- **Suggested CLAUDE.md additions** — pass through any suggestions the builders surfaced. Do not edit `CLAUDE.md` from this skill.
