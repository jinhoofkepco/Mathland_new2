# Content Number Parity Corrections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make strict JSON number handling and omitted-root checksum canonicalization agree across TypeScript, ECMAScript, and Godot without losing the existing depth and source-size bounds.

**Architecture:** The shared fixtures define the accepted decimal-to-binary64 behavior. TypeScript and Godot strict scanners reject only non-finite results, unsafe integral results, and nonzero decimal lexemes that underflow to zero; Godot records each numeric lexeme during its bounded scan and validates/replaces the decoded value at the same path so `String.to_float()` cannot alter the contract. Canonical preflight receives the root omission set and never descends into an omitted root property.

**Tech Stack:** TypeScript 5, Vitest, Zod 4, Godot 4.7.1 typed GDScript, repository-owned headless content tests.

## Global Constraints

- Work from commit `efc480946d4eab547ffdfce0e03d8ff0de85a9a4` in `.worktrees/content-runtime`.
- Preserve `MAX_JSON_SOURCE_LENGTH = 2_000_000` and `MAX_JSON_NESTING = 64`.
- Keep canonical validation iterative before recursive encoding.
- Treat every finite IEEE-754 binary64 value, including subnormals, as canonicalizable; reject a nonzero source only when it decodes to zero.
- Keep unsafe integral rejection and exact-integer lexeme checks unchanged.
- Run all TypeScript contract tests, TypeScript typecheck, and the complete Godot content suite before committing.

---

### Task 1: Lock the numeric domain and decimal parity

**Files:**

- Modify: `tests/fixtures/contracts/strict_json_number_vectors.json`
- Modify: `packages/contracts/test/content/checksum.test.ts`
- Modify: `packages/contracts/test/content/schema.test.ts`
- Modify: `tests/content/content_contract_parity_test.gd`
- Modify: `packages/contracts/src/content/canonical_json.ts`
- Modify: `src/content/content_validator.gd`

**Interfaces:**

- Consumes: decimal `source` strings and canonical outputs in the shared fixtures.
- Produces: `parseJsonStrict(source)` and `ContentValidator.parse_json(source)` values whose canonical encodings agree with ECMAScript.

- [ ] **Step 1: Add failing numeric regressions**

Change `5e-324` to an accepted vector and add accepted vectors for `0.9999999999999999`, `123456789012345.67`, the largest subnormal, the smallest normal, and huge-exponent zero. Keep `1e-324` rejected as `UNSAFE_INTEGER`. In the Godot parity test, parse every canonical spelling in `ecmascript_number_vectors.json` and assert that re-canonicalization returns the fixture spelling. In the TypeScript schema test, assert that finite subnormal adaptive thresholds pass while `Infinity` fails.

- [ ] **Step 2: Run the focused tests and verify red**

Run: `npm --workspace @mathland/contracts test -- --run test/content/checksum.test.ts test/content/schema.test.ts`

Run: `./tools/test/run_godot_tests.sh content`

Expected: TypeScript fails on the old subnormal rejection and Godot fails on decimal spellings rounded or rejected through `String.to_float()`.

- [ ] **Step 3: Align strict parsing with the finite binary64 domain**

In TypeScript, remove the `Math.abs(number) < MIN_NORMAL_DOUBLE` rejection while retaining `!isZeroDecimalLexeme(lexeme) && number === 0`. Check zero lexemes before adjusted-exponent overflow so `0e999999` is accepted without numeric conversion.

In Godot, remove the decimal literal `MIN_NORMAL_DOUBLE`, record `{ path, lexeme }` entries during the bounded scanner, and validate decoded numeric values against those entries after the built-in structural parse. Replace each path with the contract value before recursive number normalization; do not call `String.to_float()`. Reject a nonzero lexeme decoded as zero, a non-finite result, or an unsafe/inexact integral result with the same stable codes used by TypeScript.

- [ ] **Step 4: Run the focused tests and verify green**

Run the two commands from Step 2.

Expected: all focused TypeScript and Godot content tests pass with no script warnings or errors.

### Task 2: Exclude omitted root content from canonical preflight

**Files:**

- Modify: `packages/contracts/test/content/checksum.test.ts`
- Modify: `tests/content/content_contract_parity_test.gd`
- Modify: `packages/contracts/src/content/canonical_json.ts`
- Modify: `src/content/content_validator.gd`

**Interfaces:**

- Consumes: `canonicalJson(value, { omitTopLevel })` and `ContentValidator.canonical_json(value, true)`.
- Produces: canonical output that validates only serialized content while retaining iterative cycle/depth checks elsewhere.

- [ ] **Step 1: Add failing omitted-content regressions**

Construct a root object whose `checksum` property points back to the root. Assert that omission yields the same canonical object as `{ value: 1 }`, while canonicalization without omission still rejects the cycle.

- [ ] **Step 2: Run focused tests and verify red**

Run the focused TypeScript and Godot commands from Task 1.

Expected: the omission calls fail during iterative preflight before serialization.

- [ ] **Step 3: Filter the root traversal**

Pass the root omission set/flag into `assertCanonicalDomain` and `_validate_canonical_domain_iterative`. When visiting the root dictionary, skip only omitted root keys before pushing child frames; keep key validation and traversal unchanged at every nested depth.

- [ ] **Step 4: Run focused tests and verify green**

Run the focused TypeScript and Godot commands from Task 1.

Expected: omitted cycles pass, non-omitted cycles and over-depth values still fail.

### Task 3: Verify and commit

**Files:** all files modified above.

- [ ] **Step 1: Run full verification**

Run: `npm --workspace @mathland/contracts test`

Run: `npm --workspace @mathland/contracts run typecheck`

Run: `./tools/test/run_godot_tests.sh content`

Expected: 0 TypeScript test failures, typecheck exit 0, and `RESULT PASS tests=2` from Godot.

- [ ] **Step 2: Review generated/unrelated changes**

Run: `git status --short && git diff --check && git diff --stat`

Expected: only the planned contract, fixture, test, validator, and plan files are changed; `git diff --check` exits 0.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/plans/2026-07-22-content-number-parity-corrections.md \
  packages/contracts/src/content/canonical_json.ts \
  packages/contracts/test/content/checksum.test.ts \
  packages/contracts/test/content/schema.test.ts \
  src/content/content_validator.gd \
  tests/content/content_contract_parity_test.gd \
  tests/fixtures/contracts/strict_json_number_vectors.json
git commit -m "fix(content): align decimal parsing boundaries"
```
