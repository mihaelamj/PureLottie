# PureLottie — Continuation Guide

This document is the exact procedure for continuing PureLottie. Follow it
literally. When an issue does not spell something out, the standard in §4
governs. Read `AGENTS.md` as well; this guide does not replace it.

PureLottie is a Lottie compiler: it parses Lottie JSON, validates it, evaluates
source intent, lowers to a render IR, lowers that onto the PureLayer backend, and
decompiles back to source intent to prove reversibility. The remaining work
(tracked in issues #102 and its children) raises the project to a provable,
"correct for all inputs" standard.

## 0. Non-negotiable rules

Do exactly these. They are gates, not suggestions.

1. **Run the full gate in §2 before every commit.** Do not commit if any step
   fails.
2. **Never modify PureLayer or PureDraw.** They are private dependencies. The
   proof layer wraps the backend; it does not change it. If a task seems to need
   a backend change, stop and record a blocker in the issue instead.
3. **Zero skipped tests.** Never add `XCTSkip`, `.disabled`, `xfail`, an
   environment gate that skips by default, or any device that makes a test not
   run. Every test runs in the normal `swift test`. The only permitted exception
   is a documented known-invalid input fixture deliberately asserted to fail
   (see `CorpusImportSmokeTests.knownInvalidFixtures`), and it must carry a
   one-line reason in code.
4. **Never swallow errors.** No `try?`, no empty `catch {}`, no `as?`-to-default,
   no force-unwrap (`!`), no `fatalError`/`preconditionFailure` in `Sources`.
   Parse strictly; on malformed input, throw or emit a `ValidationError`. Never
   silently substitute a default. (Reference: the keyframe easing/spatial decode
   was changed from `try?` to strict `try` for exactly this reason. A malformed
   easing handle must surface as an error, not become linear timing.)
5. **No tool or authorship tells anywhere that lands in the repo.** Commit
   messages, code comments, doc text, branch names, and file names must read as
   ordinary human-authored engineering. Do not name any code-generation tool or
   assistant, and do not add "generated"/"co-authored" trailers. Install the
   commit-msg hook before committing: if a tracked `.githooks/` exists,
   `git config core.hooksPath .githooks`.
6. **Push only to the GitHub `origin`.** Never push to any GitLab remote.
7. **One issue per branch.** Branch name `issue-<number>-<short-slug>`. Commit
   subject format `<type>(<scope>): summary` (e.g. `feat(oracle): ...`,
   `fix(model): ...`, `test(import): ...`).

## 1. Environment setup

Run from the repository root. The repo is a sibling of the private `PureLayer`
and `PureDraw` repositories; do not hardcode absolute paths.

- Toolchain: Swift 6.2+, Node 22+, npm.
- Private dependencies resolve over GitHub (`swift package resolve`); revisions
  are pinned in `Package.resolved`. Do not unpin them.
- One-time oracle setup (needed for the Node oracle tests and fixture
  validation):
  ```sh
  npm ci --prefix Tools/LottieOracle
  npx --prefix Tools/LottieOracle playwright install chromium
  ```

## 2. The gate — run before every commit, all must pass

```sh
swiftformat . --config .swiftformat
swiftlint --config .swiftlint.yml --strict
swift build                                   # must finish with 0 warnings
swift test                                    # all pass, ZERO skipped
npm --prefix Tools/LottieOracle test          # 32/32
npm --prefix Tools/LottieOracle run validate-fixtures   # ok: true, 0 errors
```

A change is **done** only when: the full gate passes locally, `swift test`
reports zero skipped tests, the working tree is clean except the intended files,
and the commit is pushed to `origin`.

## 3. Current state and resume point

- `main` is the single integration branch; all completed work is on it. Begin
  from `main`.
- `#103` (classify numeric claims witnessed vs asserted): landed on `main`.
- `#104` (derive numeric tolerance bounds): the tolerance derivations and the
  matrix-translation `< 64` CSS-px domain enforcement are on `main`; the issue is
  still open. Verify every tolerance has a derivation or is explicitly marked
  `assumed`, confirm the domain-enforcement test stays green, then close it.
- `#105, #106, #107, #108, #113, #114, #115, #117, #118` are not started.
- `#102` is the epic; close it only when all children are closed.

## 4. The correctness standard (governs everything, even when an issue is silent)

Grounded in *Compilers: Principles, Techniques, and Tools* (Aho, Lam, Sethi,
Ullman — "Dragon") and *Engineering a Compiler, 2nd ed.* (Cooper, Torczon —
"EaC"):

- **Correctness before everything else.** Dragon §1.4: "It is impossible to
  overemphasize the importance of correctness. It is trivial to write a compiler
  that generates fast code if the generated code need not be correct." Prove an
  effect holds **for all possible inputs**, not just the inputs you tried.
- **Catch errors of type and of agreement in the validator, not at parse.** EaC
  Ch4: a grammatically valid document "may still contain serious errors… of type
  and of agreement"; "the analysis of meaning is the realm of context-sensitive
  analysis." Put semantic checks in `LottieValidator` as composable `Validation`
  values. Never write ad hoc imperative validation loops. Never let the parse
  layer silently drop a malformed value the validator should have reported.
- **Never alter semantics silently.** Dragon §1.5.4: a transformation "cannot
  alter the semantics of the program under any circumstances." Dropping a
  malformed field and continuing with a default is a silent semantic change and
  is forbidden. Either preserve it exactly or report it.
- **The IR is the definitive form.** EaC Ch5: "During translation, the IR form of
  the input program is the definitive form… The compiler does not refer back to
  the source text." Downstream phases must work from source intent / RenderIR,
  which "must be expressive enough to record all of the useful facts" and be
  "examine[d] easily and directly" by a human. When you add a derived fact,
  record it in the IR/trace with its provenance (witnessed vs asserted), and keep
  it inspectable.
- **Tests cover only the inputs you ran; analysis covers all of them.** Dragon
  §1.5.5: program testing finds errors only on "those [inputs] exercised by the
  input data sets," whereas analysis covers "all the possible execution paths."
  A handful of passing tests is not a proof. The bounded-exhaustive (#108),
  fuzzing (#117), and mutation (#113) work is what supplies the "all inputs"
  guarantee — do not substitute green tests for it.

A claim is acceptable only with one explicit status: `witnessed` (a real
reference run backs it), `theorem` / `theorem (bounded to N)`, `sampled`,
`assumed`, or `blocked` (with the named missing piece). Never present `assumed`
or `sampled` as `witnessed`.

## 5. Work queue — process per issue

For each issue, in this order: #104 (finish), then #105, #106, #107, #108, #113,
#114, #115, #117, #118.

Procedure for one issue:
1. `git checkout main && git pull`. Create `git switch -c issue-<n>-<slug>`.
2. Read the full GitHub issue body. Its `Goal`, `Why`, `Scope`, and `Done when`
   sections are the specification. Treat `Done when` as the acceptance test.
3. Implement to the `Done when` bullets and to §4. Verify every external fact
   against the actual source (e.g. the pinned lottie-web 5.13.0 source, the
   committed traces) — never assert a number or behavior from memory.
4. Add tests that fail before your change and pass after, including the negative
   case (malformed/out-of-bound input is rejected or reported, not accepted).
5. Run the full gate (§2). Fix everything until it is green with zero skips.
6. Commit (`<type>(<scope>): summary`, no tool/authorship tells), push the
   branch, open a PR, and resolve every review/critic finding before treating
   the issue as done.
7. Merge to `main` only after the gate is green; tick the box in the #102 epic
   checklist.

Per-issue notes:
- **#106 (confluence and strong normalization)** uses term-rewriting theory
  (Knuth–Bendix completion, Newman's lemma), which is **not** in the two compiler
  books above; use the rewriting-systems literature. Required: a well-founded
  reduction order proven to strictly decrease on every normalization rule;
  every critical pair enumerated and shown joinable (or completed, or recorded as
  a named blocker); and an executable witness that normalizes each committed
  input under two distinct rewrite orders and asserts identical results.
- **#107 (termination and cost)** must explicitly guard the two non-termination
  hazards: cyclic precomposition references and unbounded time-remap recursion.
- **#118 (reproducibility)** must record the Playwright version and resolved
  Chromium revision (not just `lottie-web@5.13.0`) plus a per-trace content hash,
  and add a regenerate-and-compare check.

## 6. Definition of done for the whole effort

Every child of #102 is closed; the full gate (§2) passes from a clean checkout
with zero skipped tests; every numeric and reversibility claim carries an
explicit status (§4); and no source file swallows errors or contains tool or
authorship tells. At that point close #102.
