---
name: stack-conventions
description: Stack conventions for building, implementing, or extending a feature in a React Native + TypeScript project — Expo (managed / dev-client) or bare React Native — covering navigation, client state, the data layer, native config/permissions, unit/component tests, and the on-simulator e2e/verify loop. Triggers when the user asks to build, implement, add, create, or extend a feature, screen, navigator, hook, or native-module integration on such a stack. Enforces the read-first / pattern-match / test-alongside / verify-on-a-simulator workflow, including updates to app config, config plugins / native files, and the e2e harness when the change requires it.
---

# Stack conventions: React Native (Expo or bare)

This skill is the **stack overlay** consulted by the feature-factory-core agents (and by humans) when working on a React Native + TypeScript project. It encodes the conventions that generalize across any RN repo. **Repo-specific names, commands, simulator/device targets, API base URLs, and bundle identifiers are NOT hardcoded here — they live in the project's own `CLAUDE.md`.** Wherever this skill says "the project's <thing>", read the concrete value from that repo's `CLAUDE.md` and docs.

Follow this loop end-to-end. Do not skip steps even when the task feels small — these conventions exist because shortcuts on this stack (native/JS drift, missing permissions, platform divergence) ship broken builds that pass the JS test suite.

## 0. Resolve the RN flavor and harness first

Before handing out any build/run/verify command, determine **which RN flavor** this repo is and **which e2e harness** it uses. Detect from the repo; only ask the user when the signals are absent or conflicting.

**Expo (managed / dev-client) vs bare React Native — detect:**

- **Expo** signals: `expo` in `package.json` dependencies; an `app.json` / `app.config.ts` / `app.config.js`; `expo` in the npm scripts; an `eas.json`.
- **Bare RN** signals: committed `ios/` **and** `android/` native directories; a `Podfile`; `react-native` CLI scripts; **no** Expo markers.
- **Dev-client nuance:** Expo deps *and* committed native dirs means **Expo with a custom dev client / prebuilt native projects** — treat it as Expo (config plugins + prebuild), not as bare RN. Do not misclassify it.

If the signals are conclusive, proceed silently. **If they are absent (greenfield) or conflicting, STOP and ask the user: "Expo (managed/dev-client) or bare React Native?"** — give the one-line trade-off (Expo: managed native config via config plugins + prebuild, simplest simulator story; bare: full native control, heavier Xcode/Gradle/CocoaPods toolchain). **Record the answer in the project's `CLAUDE.md`** so this is resolved once per repo, not once per feature.

**E2E harness — detect, same rule:** look for a Detox config (`.detoxrc*`, `detox` in `package.json`) or Maestro flows (`.maestro/`, `*.yaml` flows, `maestro` in scripts). Use whichever the repo already has. If neither exists and the feature needs an on-device flow, default to **Maestro** (lighter to author for a simulator-smoke role) and note the choice. Do not introduce a second harness alongside an existing one.

Everything below that says "Expo:" or "Bare:" selects on the resolved flavor.

## 1. Read before writing

Before touching code:

- Re-read the relevant section of the project's `CLAUDE.md`. It is the source of truth for the resolved RN flavor, the e2e harness, the navigation/state/data conventions, the "Don't do" list, and the concrete simulator/device/command names this skill refers to abstractly.
- Read the technical brief in full. If anything is ambiguous (which platforms are in scope, offline behavior, permission UX, deep-link handling, auth-token storage), ask before coding — don't guess.
- Pull in the right doc from the project's `docs/` for the area you're touching: navigation, data fetching, native modules, push, builds/release.
- For React Native, Expo, React Navigation / Expo Router, your data library (React Query / RTK Query), or your e2e harness specifics, check official docs (Context7) rather than guessing from memory — native APIs and Expo SDK surfaces change fast across versions.

## 2. Match existing patterns

Find 2–3 existing features that are structurally similar to what you're about to build and mirror them:

- A new screen → find 2–3 screens of similar shape (params typing, data fetch, loading/empty/error states, safe-area + keyboard handling).
- A new navigator / route → find how the project registers routes (React Navigation stack/tab config or Expo Router file-based routes). Match param typing and deep-link config.
- A new data hook → find 2–3 existing hooks in the project's data layer. Match the query-key / cache / retry conventions; do not introduce a second data library.
- A new client-state slice → match the project's existing store (Redux/Zustand/Context). Do not add a new state library.
- A new native-module / Expo SDK integration → find 2–3 existing wrappers. Match how the project isolates native calls behind a typed module so screens stay testable.

If you can't find a similar pattern, that's a signal to pause and ask — you may be building something the architecture doesn't yet support.

## 3. Write tests alongside the code

This is not strict TDD. Write production code and its tests together as one unit of work. Goals:

- Component/unit tests via the project's runner — typically **Jest + React Native Testing Library** (query by accessibility role/label/`testID`, not by DOM selectors; RN has no DOM).
- Every feature ships with at least: a **render / happy-path** test, a **loading and error state** test, and at least one **user-interaction** test (press, input, navigation).
- Use the project's **test data builders / fixtures**. Do not write inline setup objects — grep for an existing builder first.
- Mock native modules and the network at the project's existing seam (its mock setup file), the same way neighbouring tests do. Do not invent a new mocking approach.
- Tests live next to the code they cover, following the existing file naming convention.

## 4. Conventions to follow

**Where logic lives**
- Screens render and orchestrate; they do not hold business logic. Push data access into hooks and shared logic into plain TS modules so it stays unit-testable off-device.
- Navigation config is centralized (React Navigation config or Expo Router files). Don't scatter ad-hoc navigation.
- **The app usually consumes a separate/existing API rather than owning a backend.** Match the project's existing API client, auth-header injection, and error envelope. If the feature needs a brand-new backend endpoint, that is backend work in another repo/layer — surface it as a handoff; do not stub a fake endpoint in the app.

**Naming**
- Match the casing and verb conventions of the nearest existing sibling (screens, hooks, navigator entries, store slices). Consistency with neighbors beats personal preference.

**Platform & UX**
- Build for **both iOS and Android** unless the brief scopes one. Handle safe areas, the keyboard (avoiding view / inset behavior), and back-button/gesture behavior the way existing screens do.
- Use the project's existing list/virtualization primitive for long lists. Don't render unbounded `.map()` into a ScrollView.

**Secrets & storage**
- Store auth tokens / secrets in secure storage (**Expo:** `expo-secure-store`; **Bare:** Keychain/Keystore via the project's wrapper). **Never** put tokens or secrets in AsyncStorage, in JS constants, or committed config.
- Public, build-time config goes through the project's config mechanism (Expo: `app.config` `extra` / `EXPO_PUBLIC_*`; Bare: the project's env mechanism). Never hardcode environment-specific URLs in screens.

## 5. Update native config / build files when the feature requires it

A change that crosses the native boundary must update the right files in lockstep so JS and native stay in sync. The exact filenames live in this repo's `CLAUDE.md`.

- **New permission** (camera, location, photos, notifications, microphone, contacts) → declare it on **both** platforms.
  - **Expo:** add it via the config plugin / `app.config` (iOS usage-description strings + Android permissions), then re-run prebuild if native dirs are committed.
  - **Bare:** edit `Info.plist` (usage-description strings) **and** `AndroidManifest.xml` directly.
- **New native dependency or Expo config plugin** → update `package.json`, then sync native:
  - **Expo:** `npx expo install <pkg>` (version-matched to the SDK), add any config plugin, and run `npx expo prebuild` if the repo commits native dirs. A new native dep means a new **dev-client / EAS build** — a JS-only OTA update will crash against the old binary.
  - **Bare:** install, then `npx pod-install` (or `cd ios && pod install`) and confirm Gradle picks up the Android side.
- **New env var / build-time config** → add to the project's config mechanism (Expo `app.config` `extra` / `EXPO_PUBLIC_*`, or the bare project's env files) **and** to the EAS/build profile so dev and release stay aligned. Never hardcode secrets; use the project's secret mechanism (EAS secrets / native secure storage).
- **New deep link / URL scheme / universal link** → register it in app config (Expo) or native files (bare) **and** in the navigation linking config.

If the change is pure JS/TS with no new native deps, permissions, or config, leave the native files alone. Don't churn them for no reason — but remember that a JS-only change can still require a native rebuild if it depends on a binary that isn't in the current build.

## 6. Verify on a simulator / emulator

All verification runs against the app **running on a simulator/emulator** (or a device), not just the JS test runner. "Tests pass" is not "it works on the phone." Use the concrete simulator/device targets and commands defined in this repo's `CLAUDE.md`.

1. Start the bundler and run the app:
   - **Expo:** `npx expo start`, then launch iOS simulator and/or Android emulator. If the feature added a native dep or config plugin, build/run a **dev client** (or an EAS dev build) — Expo Go won't include custom native code.
   - **Bare:** `npx react-native run-ios` / `run-android` (rebuild when native changed).
2. Run the project's typecheck and lint commands.
3. Run the project's unit/component test command (Jest + RNTL or whatever the project uses).
4. For any user-facing flow, run an **on-simulator e2e smoke** using the resolved harness:
   - **Maestro:** run the relevant `.maestro` flow against the running app.
   - **Detox:** `detox build` (matching the configured device/config) then `detox test` scoped to the new spec.

All checks must pass on at least one platform; exercise both iOS and Android when the feature has platform-divergent surface (permissions, native modules, layout/keyboard). If a pre-existing failure is unrelated to your change, say so explicitly rather than glossing over it. If you changed native code/config, **rebuild the app** before re-running the e2e smoke — a stale binary will pass or fail for the wrong reasons.

## Mobile e2e gotchas — verify these against the code every time

These are the *categories* of runtime gotcha that recur in RN e2e/smoke specs. Confirm the specifics against the actual code and the resolved harness for this project:

1. **Selector source.** Assert on `testID` / accessibility label / role taken from the component source, not from the brief wording. Add a `testID` to the component if the flow needs a stable hook — don't assert on rendered copy that designers will change.
2. **Async navigation & data waits.** Screen transitions and first data loads are async; use the harness's wait/visibility assertions with generous timeouts rather than fixed sleeps. A cold Metro bundle or first native launch is slow.
3. **Permission dialogs.** OS permission prompts (camera/location/notifications) are native dialogs the JS layer can't dismiss — drive them through the harness's device/permission API (Detox `device.launchApp({ permissions })`, Maestro permission steps), or the flow hangs.
4. **Platform divergence.** A flow that passes on iOS can fail on Android (back button, keyboard behavior, safe-area, scheme handling). If the feature touches those, run the smoke on both; don't assume parity.
5. **Dev-client vs Expo Go.** A spec that exercises a custom native module must run against a dev client / EAS build, not Expo Go. Flag it if the harness is pointed at the wrong binary.
6. **Deep links / cold start.** Test deep links both from cold start and warm resume — the navigation linking config behaves differently for each.
7. **Stale binary.** If native code/config changed and the e2e run wasn't preceded by a rebuild, results are meaningless. Rebuild first.
8. **Seeded vs live API.** Point e2e at the project's test/staging API or its mock layer, never at production. Use unique-per-run test data to avoid collisions across repeated runs.

## End-of-task summary

Report in 1–2 sentences: what was built, which files changed (including any app-config / config-plugin / native files), the resolved RN flavor and e2e harness, and confirmation that typecheck / lint / unit tests are green and the on-simulator e2e smoke passed (and on which platform[s]). Nothing more.
