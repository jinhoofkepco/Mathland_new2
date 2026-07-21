# MathLand 1.0.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Coordinate the four executable subproject plans into one test-first delivery path that ends with a verified signed Android APK, deployed guardian web app, and live duplicate-safe synchronization.

**Architecture:** Godot is the offline source of truth for child play, versioned JSON packages are the source of truth for activities, Supabase is the family-scoped synchronization/publication plane, and the React static app is the authenticated guardian/editor surface. Shared TypeScript contracts and committed JSON fixtures bridge these runtimes; integration work may not silently redefine them.

**Tech Stack:** Godot 4.7.1/GDScript, TypeScript/npm workspaces, React/Vite, Supabase/PostgreSQL/Deno, Kotlin Android plugin, GitHub Actions and Releases.

## Plan Set

1. [Godot Foundation and Game Core](2026-07-21-godot-foundation-game-core.md)
2. [Content and Asset Pipeline](2026-07-21-content-asset-pipeline.md)
3. [Cloud, Dashboard, and Content Studio](2026-07-21-cloud-dashboard-content-studio.md)
4. [Android Integration and Release](2026-07-21-android-integration-release.md)

## Frozen Cross-Project Contracts

- Shared browser/tool/Edge Function types: `packages/contracts/src/` as npm package `@mathland/contracts`.
- Godot runtime mirrors/adapters: `src/content/` and `src/sync/`; committed JSON fixtures under `tests/fixtures/contracts/` prove parity.
- Child learning envelope: `LearningEventV1`, UUIDv4 `event_id`, one device-local monotonic sequence, immutable payload, maximum sync batch 100.
- Content envelope: immutable `ActivityPackageV1`, canonical JSON SHA-256, allowlisted generator/manipulative/resource IDs, one content version per run.
- Godot test command: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite <suite>`.
- TypeScript package manager: npm workspaces with a committed root `package-lock.json`.
- Release identity: `com.jinhoofkepco.mathland`, version `1.0.0`, code `1`, min SDK 24, target SDK 35, ARM64, Compatibility renderer.
- Live credentials are never fixtures. Deterministic fakes remain the default until the documented authorization gate.

## File Ownership

| Area | Primary plan | Shared only through |
|---|---|---|
| `project.godot`, `src/core`, `src/game`, `src/ui`, core Godot tests | A | event/content interfaces and fixtures |
| `packages/contracts`, `content`, `tools/content`, `src/content`, `src/manipulatives`, final media | B | reviewed schema changes |
| `web`, `supabase`, cloud operations docs | C | shared contracts and publication fixtures |
| `android`, build/release scripts, integration tests, release workflows/docs | D | stable outputs from A–C |

No worker edits another plan's primary area without first recording the interface change in this index and updating every affected contract test.

## Delivery Gates

### Gate 1: Repository and contract baseline

- [ ] Create an isolated feature worktree and record the base commit.
- [ ] Land the Godot headless runner, npm workspace, shared contract package, content schema, and CI entry points.
- [ ] Prove one LearningEventV1 and one ActivityPackageV1 fixture parse identically in TypeScript and Godot.
- [ ] Run `git diff --check`, Godot contract tests, TypeScript contract tests, and the web build.

### Gate 2: Offline vertical slice

- [ ] Complete profile selection → island → ten-rod activity → health loss/success → reward → island.
- [ ] Force-stop after an answer and prove journal replay restores it without duplicate rewards.
- [ ] Run at 360×800, 1080×2400, and 800×1280 with no clipped primary control.
- [ ] Install a debug ARM64 APK and complete a run with airplane mode enabled.

### Gate 3: Full local product

- [ ] Ship all five migrated topics and the six foundations activities from validated packages.
- [ ] Pass generator property samples, legacy golden fixtures, manipulative scene tests, adaptive on/off tests, and asset/audio license checks.
- [ ] Complete dashboard, Content Studio, Supabase migrations/functions/RLS tests, and fake-cloud Playwright journeys.
- [ ] Demonstrate manual content editing, preview, validation, publication, and rollback without an AI key.

### Gate 4: Authorized cloud integration

- [ ] Authorize one intended Supabase project through trusted browser/CLI flow without exposing credentials in chat or git.
- [ ] Deploy migrations/functions and run cross-family negative tests on disposable identities.
- [ ] Pair a device, ingest the same real app event twice, prove exactly one stored event, and observe the guardian aggregate.
- [ ] Publish and roll back one disposable content version, then remove all disposable data.

### Gate 5: Production release

- [ ] Pass Godot, contracts, tools, web, Edge Function, SQL, Android, lifecycle, accessibility, privacy, performance, and secret-scan suites from the release commit.
- [ ] Generate/locate the external signing key through macOS Keychain, build the signed ARM64 APK, verify certificate/package/version, and produce SHA-256.
- [ ] Confirm APK ≤200 MB, cold launch <5 seconds, input response <100 ms, and effect-heavy p95 frame <25 ms on the reference profile.
- [ ] Tag `v1.0.0`, publish APK/checksum/screenshots/notes/licenses, download the release artifact again, verify hash/signature, and install it.

## Execution Protocol

- Implement one task at a time with `superpowers:test-driven-development`: first observe the focused test fail for the intended reason, then write the minimum production change, then refactor under green tests.
- Use `superpowers:subagent-driven-development`; each task receives a specification-compliance review followed by a code-quality review before it is accepted.
- Re-run the narrow suite after every edit and the plan-level suite before each commit. Never use a later broad test as evidence that an earlier red step occurred.
- Use deterministic clocks, UUID sources, random seeds, and service fakes in automated tests.
- Keep every intermediate deliverable runnable. Cloud or AI unavailability may not prevent offline play, content editing, or dashboard fake mode.
- Before any completion statement, invoke `superpowers:verification-before-completion` and execute fresh commands from a clean tree.

## Required Final Evidence

- Commit SHA and clean-tree status.
- Per-suite test command, pass count, and timestamp.
- Android device/API/viewport and lifecycle run evidence.
- Performance report with raw samples and thresholds.
- RLS cross-family denial and duplicate-ingestion evidence.
- GitHub Pages URL and live dashboard observation.
- GitHub Release URL, downloaded APK SHA-256, signer certificate fingerprint, package/version inspection, and fresh install/launch evidence.
- Asset/audio provenance record and explicit known limitations.

If the only unavailable item is live Supabase authorization, stop at Gate 4 with every local deliverable verified and state precisely that remote monitoring is not yet complete. Do not label or publish `v1.0.0` as fully complete until all five gates pass.
