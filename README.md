# feature-factory — Claude Code plugin marketplace

A small marketplace with three plugins that package the multi-agent feature-delivery
workflow so it can be reused across any project and shared with teammates.

- **`feature-factory-core`** — stack-agnostic. The eight specialist agents, the
  `feature-factory` orchestration skill, and a secret-scan pre-commit hook. Its
  end-to-end step is UI-runtime-neutral: a browser for web apps, a simulator/emulator
  for mobile apps.
- **`nextjs-prisma-overlay`** — optional. A `stack-conventions` skill encoding the
  Next.js (App Router) + TypeScript + Prisma/PostgreSQL + BullMQ/Redis + Resend +
  Docker/Playwright conventions. Enable it only on matching repos; it sharpens the
  core agents with that stack's build/test/migration/deploy rules.
- **`react-native-overlay`** — optional. A `stack-conventions` skill encoding the
  React Native (Expo managed/dev-client or bare RN) + TypeScript conventions:
  navigation, client state, the data layer, native config/permissions, on-simulator
  verification, and the e2e harness. It detects the RN flavor and the e2e harness
  (Detox/Maestro), asking only when the repo is ambiguous. Enable it only on matching repos.

The core agents discover each project's stack (from the manifest — `package.json`,
`pyproject.toml`, `go.mod`, … — and the project's `CLAUDE.md`) and, if the
`stack-conventions` skill is installed, consult it. So the core works anywhere;
the overlay makes it stack-aware where it applies.

## What's inside

```
.claude-plugin/marketplace.json          # lists both plugins
plugins/
  feature-factory-core/
    .claude-plugin/plugin.json
    agents/                              # codebase-researcher, story-writer, spec-writer,
                                         # backend-builder, frontend-builder, test-verifier,
                                         # e2e-author, implementation-validator, feature-orchestrator
    skills/feature-factory/SKILL.md      # the 8-step chain + 3 approval gates + validator loop-back
    hooks/hooks.json + pre-commit.sh     # blocks commits containing .env/.key/.pem/secrets/creds
  nextjs-prisma-overlay/
    .claude-plugin/plugin.json
    skills/stack-conventions/SKILL.md
  react-native-overlay/
    .claude-plugin/plugin.json
    skills/stack-conventions/SKILL.md   # Expo/bare RN; detects flavor + e2e harness
```

## The chain

`codebase-researcher → story-writer → (approval) → spec-writer → (approval) →
backend-builder → frontend-builder → test-verifier → e2e-author →
implementation-validator → (approval)`, looping back to the right builder if the
validator finds critical gaps. Run it with the `feature-factory` skill (or the
`feature-orchestrator` agent), or invoke any agent on its own.

## Install (in any project)

```bash
# From a local clone of this repo:
/plugin marketplace add /path/to/feature-factory
# …or from a git remote once you push it:
/plugin marketplace add <git-url>

/plugin install feature-factory-core@feature-factory
# On Next.js + Prisma repos, also:
/plugin install nextjs-prisma-overlay@feature-factory
# On React Native (Expo or bare) repos, instead:
/plugin install react-native-overlay@feature-factory
```

Enable **at most one** stack overlay per repo — each ships a skill named
`stack-conventions`, and the core agents consult whichever one is installed.

Enable per project by committing `enabledPlugins` to the project's `.claude/settings.json`,
or globally in `~/.claude/settings.json`.

## Deliberately NOT included

- **Agent memory** (`.claude/agent-memory/*`) — these are per-project learnings
  (database/container names, this-repo gotchas). They must NOT travel between
  projects; each repo accrues its own. The `memory: project` setting on each agent
  keeps memory scoped to the project it runs in.
- **MCP servers / connectors** (telegram, Context7, Gmail, etc.) and the global
  voice-transcription `CLAUDE.md` — these are already user-scoped (in
  `~/.claude/settings.json` `enabledPlugins` and `~/.claude.json`), so they apply
  to every project automatically. Nothing to package here. Environment-specific
  MCP (e.g. a docker-socket proxy for one dev box) is intentionally left out.

## Provenance

Extracted and genericized from the `notesapp` project's `.claude/` setup. The
core agents/skill had all `notesapp`-specific names (container/DB names, the
tsvector gotcha, exact compose paths) stripped; those repo-specific details belong
in each project's own `CLAUDE.md`.
