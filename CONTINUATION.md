# PureLottie Continuation Guide

**Re-read this entire file at the start of every work cycle: every issue, every PR or critic pass, and after any context reset or compaction. Do exactly what it says. The rules in sections 0 and 4 are binding on every cycle, not just the first.**

This document is the exact procedure for continuing PureLottie. Follow it
literally. When an issue does not spell something out, the codified rules in §4
govern. Read `AGENTS.md` as well; this guide does not replace it.

PureLottie is a Lottie compiler: it parses Lottie JSON, validates it, evaluates
source intent, lowers to a render IR, lowers that onto the PureLayer backend, and
decompiles back to source intent to prove reversibility. The remaining work
(issue #102 and its children) raises the project to a provable, correct-for-all-
inputs standard.

## 0. Non-negotiable rules

Do exactly these. They are gates, not suggestions.

1. **Run the full gate in §2 before every commit.** Do not commit if any step fails.
2. **Never modify PureLayer or PureDraw.** They are private dependencies. The proof layer wraps the backend; it does not change it. If a task seems to need a backend change, stop and record a blocker on the issue instead.
3. **Zero skipped tests.** Never add `XCTSkip`, `.disabled`, `xfail`, or an environment gate that skips by default. Every test runs in the normal `swift test`. The only exception is a documented known-invalid input fixture deliberately asserted to fail, with a one-line reason in code.
4. **Never swallow errors.** No error-discarding `try?`, empty `catch {}`, `as?`-to-default, force-unwrap (`!`), or `fatalError`/`preconditionFailure` in `Sources`. Parse strictly; on malformed input, throw or emit a `ValidationError`. Never silently substitute a default.
5. **No tool or authorship tells in anything that lands in the repo.** Commit messages, comments, docs, branch names, and file names read as ordinary human-authored engineering. Do not name any code-generation tool or assistant, and do not add generated or co-authored trailers. Install the commit-msg hook: if a tracked `.githooks/` exists, run `git config core.hooksPath .githooks`.
6. **Push only to the GitHub `origin`.** Never push to any GitLab remote.
7. **One issue per branch.** Branch `issue-<number>-<slug>`. Commit subject `<type>(<scope>): summary`.

## 1. Environment setup

Run from the repository root (a sibling of the private `PureLayer` and `PureDraw`
repos; do not hardcode absolute paths). Toolchain: Swift 6.2+, Node 22+, npm.
Private dependencies resolve over GitHub and are pinned in `Package.resolved`; do
not unpin them. One-time oracle setup:

```sh
npm ci --prefix Tools/LottieOracle
npx --prefix Tools/LottieOracle playwright install chromium
```

## 2. The gate, run before every commit, all must pass

```sh
swiftformat . --config .swiftformat
swiftlint --config .swiftlint.yml --strict
swift build                                              # 0 warnings
swift test                                               # all pass, ZERO skipped
npm --prefix Tools/LottieOracle test                     # 32/32
npm --prefix Tools/LottieOracle run validate-fixtures    # ok: true, 0 errors
```

Done means: the full gate passes locally, `swift test` reports zero skipped
tests, the tree is clean except the intended files, and the commit is pushed.

## 3. Current state and resume point

- `main` is the single integration branch; begin from it.
- #103, #104, #105, #106, #107, #108, #113, #114, #115 are landed on `main`.
- #117 (totality/fuzzing) is implemented and verified on the issue branch.
- #118 is the next and final open child issue.
- #102 is the epic; close it only when all children are closed.

## 4. Codified rules: compiler-correctness, first principles, Knuth

These are checkable rules, not advice. Apply every one to every change. Each cites
its source. ("Dragon" = Aho, Lam, Sethi, Ullman, *Compilers: Principles,
Techniques, and Tools*; "EaC" = Cooper, Torczon, *Engineering a Compiler, 2nd ed.*)

Compiler-correctness rules:

- **C1. Correctness outranks everything.** (Dragon §1.4: "trivial to write a compiler that generates fast code if the generated code need not be correct.") A change that produces a wrong result on any input is not done. Speed, brevity, or "it builds" never justify incorrectness.
- **C2. Prove for all inputs, not for the examples you ran.** (Dragon §1.5.5: testing covers only "those [inputs] exercised by the input data sets.") "The corpus passed" is a measurement, not a proof. Back a correctness claim with one of: a closed-form argument, bounded-exhaustive enumeration up to a stated N, or an explicit `assumed`/`blocked` status. Never label a claim proved or witnessed on examples alone.
- **C3. Put type and agreement checks in the validator, not the parser.** (EaC Ch4: a valid parse "may still contain serious errors of type and of agreement.") Cross-reference, uniqueness, and consistency checks are composable `Validation` values in `LottieValidator`. No ad hoc imperative validation loops. The parser must not silently absorb an error the validator should report.
- **C4. Never alter semantics silently.** (Dragon §1.5.4: a transformation "cannot alter the semantics under any circumstances.") On malformed or unsupported input, throw or emit a diagnostic; never substitute a default and continue. (The keyframe easing decode was changed from `try?` to strict `try` for exactly this reason.)
- **C5. The IR is the definitive form.** (EaC Ch5: "the IR form is the definitive form; the compiler does not refer back to the source text," and it "must be expressive enough to record all of the useful facts.") Downstream phases read source intent / RenderIR, never re-read JSON. Record every derived fact in the IR with its provenance and status, and keep it human-inspectable.
- **C6. Validation is complete over the input model.** Every field the input can carry is either modeled (it has a typed home and the validations that constrain it) or explicitly reported as unsupported or ignored, with a reason. Unknown keys are detected and reported, never silently dropped. Keep a coverage registry and a meta-test that fails if any field of the model lacks a rule. Passing every shipped test is not enough if a field was never given a rule. (The modeled-or-reported discipline of the OpenAPIKit validation idiom: validate the whole document structure, not a chosen subset.)

First-principles rules:

- **P1. State the invariant before writing code.** Write the one sentence the change must preserve; derive the code from it.
- **P2. Fix the layer that owns the data, not the symptom.** Trace a failure to its root and fix there.
- **P3. Verify every external fact against the source.** Tool versions, constants, spec behavior (e.g. lottie-web 5.13.0 internals, committed traces) are checked against the actual source, never recalled from memory.
- **P4. Make impossible states unrepresentable.** Prefer a type that cannot encode an invalid state over a runtime check that hopes to catch it.
- **P5. Disclose limits; never hide debt.** A known gap is an issue, a failing test, or a `blocked` claim, never a silent skip, stub, or TODO.

Knuth rules:

- **K1. Total correctness by case enumeration.** For every function and compiler edge, handle or explicitly exclude empty, boundary, malformed, maximal, and (where relevant) concurrent inputs. Name what you exclude and why.
- **K2. Analyze, do not guess.** State each edge's termination argument and worst-case asymptotic cost. Never claim a performance or termination property without an analysis or a measurement.
- **K3. Confluence and termination for any rewriting.** A normalization or rewrite system earns the phrase "the normal form" only with a proven well-founded reduction order (termination) and joinable critical pairs (confluence, Knuth-Bendix). Otherwise the normal-form claim is invalid.
- **K4. Write to be read.** Code and prose target a human reader: small single-responsibility units; the trusted core must be readable and believable by a skeptic.
- **K5. The checker is smaller than what it checks.** The independent verifier or oracle that certifies the compiler must be simpler than the compiler and independently inspectable.

Status vocabulary (every numeric, reversibility, and conformance claim carries
exactly one): `theorem`, `theorem (bounded to N)`, `witnessed` (a real reference
run backs it), `sampled`, `assumed`, `blocked` (with the named missing piece).
Never upgrade a status without the evidence its definition requires; never present
`assumed` or `sampled` as `witnessed`.

## 5. Work queue, process per issue

Order: #104 (finish), then #105, #106, #107, #108, #113, #114, #115, #117, #118.

For one issue:
1. `git checkout main && git pull`. Create `git switch -c issue-<n>-<slug>`.
2. Read the full GitHub issue body. `Goal`, `Why`, `Scope`, `Done when` are the specification; treat `Done when` as the acceptance test.
3. Implement to the `Done when` bullets and to every rule in §4.
4. Add tests that fail before the change and pass after, including the negative case (malformed or out-of-bound input is rejected or reported, not accepted).
5. Run the full gate (§2). Make it green with zero skips.
6. Commit, push the branch, open a PR, run the critic loop, resolve every finding before the issue is done.
7. Merge to `main` only after the gate is green; tick the box in the #102 epic checklist.

Per-issue notes:
- **#106 (confluence)** uses term-rewriting theory (Knuth-Bendix completion, Newman's lemma), not the two compiler books; use the rewriting-systems literature. Required by K3: a well-founded reduction order proven to decrease on every rule, every critical pair shown joinable (or completed, or a named blocker), and an executable two-rewrite-order witness.
- **#107 (termination and cost)** must guard the two non-termination hazards explicitly: cyclic precomposition references and unbounded time-remap recursion.
- **#118 (reproducibility)** must record the Playwright version and resolved Chromium revision (not just `lottie-web@5.13.0`) plus a per-trace content hash, and add a regenerate-and-compare check.

## 6. Definition of done for the whole effort

Every child of #102 is closed; the full gate (§2) passes from a clean checkout
with zero skipped tests; every claim carries an explicit status (§4); and no
source file swallows errors or carries tool or authorship tells. Then close #102.
