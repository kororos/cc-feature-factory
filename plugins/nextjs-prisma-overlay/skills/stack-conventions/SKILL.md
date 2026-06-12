---
name: stack-conventions
description: Stack conventions for building, implementing, or extending a feature in a Next.js (App Router) + TypeScript + Prisma/PostgreSQL project (also covering BullMQ/Redis, Resend, and Docker/Playwright). Triggers when the user asks to build, implement, add, create, or extend a feature, endpoint, service, job, or email flow on such a stack. Enforces the read-first / pattern-match / test-alongside / verify-in-a-container workflow, including updates to the project's Dockerfile, compose, and stack files when the change requires it.
---

# Stack conventions: Next.js + Prisma

This skill is the **stack overlay** consulted by the feature-factory-core agents (and by humans) when working on a Next.js (App Router) + TypeScript + Prisma/PostgreSQL + BullMQ/Redis + Resend + Docker/Playwright project. It encodes the conventions that generalize across any repo on this stack. **Repo-specific names, commands, container names, network names, and database names are NOT hardcoded here — they live in the project's own `CLAUDE.md`.** Wherever this skill says "the project's <thing>", read the concrete value from that repo's `CLAUDE.md` and docs.

Follow this loop end-to-end. Do not skip steps even when the task feels small — these conventions exist because shortcuts have caused production incidents on this stack.

## 1. Read before writing

Before touching code:

- Re-read the relevant section of the project's `CLAUDE.md`. It is the source of truth for the stack, architecture rules, the "Don't do" list, and the concrete container/DB/command names this skill refers to abstractly.
- Read the technical brief in full. If anything is ambiguous (tenant scoping, retry behavior, email template choice, billing edge cases), ask before coding — don't guess.
- Pull in the right doc from the project's `docs/` for the area you're touching: API/service work, billing, email, background jobs, schema/queries. If an ADR covers the area, read it before contradicting it.
- For Next.js, Prisma, Auth.js, BullMQ, or Resend specifics, check official docs (Context7) rather than guessing from memory.

## 2. Match existing patterns

Find 2–3 existing features that are structurally similar to what you're about to build and mirror them:

- A new API route → find 2–3 routes of similar shape (auth + tenant scope + service call + response shape).
- A new service method → find 2–3 methods in the same or sibling services. Match function signatures, error types, and how they receive the tenant context.
- A new background job → find 2–3 existing BullMQ jobs. Match queue naming, payload shape, and retry/backoff config from the project's job docs.
- A new email → find 2–3 templates in the existing email template system. Do not introduce a new template system.
- A new Prisma model or migration → find 2–3 recent migrations. Match naming, indexing, soft-delete, and tenant-id conventions from the project's DB docs.

If you can't find a similar pattern, that's a signal to pause and ask — you may be building something the architecture doesn't yet support.

## 3. Write tests alongside the code

This is not strict TDD. Write production code and its tests together as one unit of work — typically in the same edit pass or back-to-back. Goals:

- Every feature ships with at least: a **success** test, a **validation failure** test, and a **not-found / unauthorized** test. Add more for genuine branches; don't pad.
- Use the project's **test data builders**. Do not write inline setup objects — grep for an existing builder for the model first.
- Do **not** mock the database unless the surrounding tests in that file already do. Integration-style tests against the real DB are the default here.
- Tests live next to the code they cover, following the existing file naming convention in that directory.
- For services, test the service directly. For API routes, test the route only if it has logic beyond delegation; otherwise the service tests cover it.

## 4. Conventions to follow

**Where logic lives**
- Business logic → services or domain modules. Never in API routes.
- API routes → auth check, parse input, call service, shape response. Thin.
- Scheduled work → BullMQ worker only. Never add cron.
- Tenant isolation → enforced in the service layer. Routes pass the tenant context in; services apply the filter.

**Naming**
- Match the casing and verb conventions of the nearest existing sibling (service methods, route handlers, job names, Prisma models). Consistency with neighbors beats personal preference.

**Error handling**
- Throw typed domain errors from services; let the route layer translate them to HTTP responses.
- Never return raw database errors to the client.
- Never log raw payment payloads or other secrets (see the project's billing docs).

**Migrations**
- Additive migrations only. Never edit a migration that has been merged.
- Apply migrations with the project's **safe migration command** (as defined in this repo's `CLAUDE.md`). Never run a destructive dev/reset migration — it can drop generated/derived columns and other DB state that is not reconstructible from the schema alone.

## 5. Update Docker infra when the feature requires it

This stack ships through Docker: an image definition (Dockerfile), a local dev compose file (app + Postgres + Redis, with the project directory bind-mounted for hot reload), and a production stack/orchestration file. The exact filenames and locations are defined in this repo's `CLAUDE.md`.

If your change crosses the container boundary, update all relevant files together so dev and prod stay in lockstep:

- **New runtime dependency** (system package, native build tool, new binary) → update the Dockerfile. Rebuild the image locally and confirm it still starts.
- **New env var or secret** → add to the dev compose file (dev defaults / `.env` reference) **and** the production stack file (prod secret reference). Never hardcode secrets; use Docker secrets or env files in prod.
- **New service** (e.g., a second worker, a new Redis instance, an additional queue consumer) → add to both the dev compose and production stack files. Match the network, volume, and healthcheck patterns of existing services.
- **New port, volume, or healthcheck** → mirror it in both files.
- **Changed Node version, build step, or entrypoint** → update the Dockerfile and verify the dev container hot-reload still works.

If the change is pure application code with no new deps / env / services, leave the Docker files alone. Don't churn them for no reason.

## 6. Verify inside a container

All verification runs **inside the dockerized dev environment**, not on the host. The local Docker stack (Next.js app + Postgres + Redis) is the source of truth for "does it work." Use the concrete compose file path, app service name, and commands defined in this repo's `CLAUDE.md`.

Bring the stack up if it isn't already, then run the project's typecheck, lint, and test commands inside the app container. For DB-touching work, also apply migrations against the containerized Postgres using the project's **safe migration command** (never a destructive reset).

All checks must pass. If a pre-existing failure is unrelated to your change, say so explicitly rather than glossing over it.

For UI changes, exercise the feature in a **browser smoke** against the running dev container (the project's Playwright/e2e harness, or a manual pass). Typecheck and tests verify code correctness, not feature correctness — a browser smoke is required before a feature is considered done.

If you touched the Dockerfile, rebuild the image before re-running checks.

## End-of-task summary

Report in 1–2 sentences: what was built, which files changed (including any deploy/infra files), and confirmation that typecheck / lint / tests are green inside the container and a browser smoke passed. Nothing more.
