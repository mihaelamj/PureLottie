# Reference Engine Divergences

Status: issue #66 divergence ledger for curated Lottie oracle fixtures.

Reference engine divergences are measured facts. They are not guesses, visual
impressions, or excuses to accept mismatched output. A divergence record says:

- which reference behavior was observed;
- which fixture proves it;
- which Lottie fields or source-intent facts are affected;
- which committed trace, source file, test, or oracle tool lets the claim be
  checked again.

The machine-readable ledger is
`Tools/LottieOracle/reference-divergences.json`. Every curated fixture with the
`engine-divergence` evidence role in `Tools/LottieOracle/oracle-fixtures.json`
must name one or more ledger IDs in `divergenceIDs`.

## Reversibility Rule

A divergence claim must be reversible through this path:

```text
fixture id -> divergenceIDs -> ledger record -> source pointers -> committed
lottie-web intent / local evaluator / local test -> regenerated evidence
```

If any link is missing, the fixture is not allowed to use `engine-divergence` as
evidence.

## Current Families

The current ledger records measured divergence families for:

- layer position matrices;
- split position rejoining;
- anchor, scale, rotation, and position transform order;
- shape group transform scope;
- group opacity as atomic compositing;
- parent world matrices;
- ellipse direction and contour order;
- rounded rectangle radius and cubic constants;
- polygon/star source geometry;
- fill-rule style facts;
- stroke dash arrays and animated stroke width;
- trim length ranges and selected segments;
- half-open layer frame windows;
- mask source graph facts;
- track matte source-target binding;
- precomposition local source frames;
- time-remap as an explicit diagnosed boundary.

## Validation

The Swift tests validate the typed ledger through
`LottieReferenceDivergenceLedgerValidator`, then prove:

- divergence IDs are unique;
- source pointers and comparison evidence resolve to repository files;
- every `engine-divergence` fixture links to at least one known ledger ID;
- every ledger fixture back-reference exists in the curated manifest;
- invalid records fail with exact JSON paths.

The Node oracle tests validate the same links from the external harness side.
