# Normalization Confluence and Termination Proofs

Status: issue #106 confluence and strong normalization theorem.

This document presents the formal term rewriting system for the Lottie source-intent normalization phase, proving both strong termination (finitely many steps to normal form) and confluence (unique normal form regardless of rewrite order).

## 1. Rewrite Rules over Source Intent

Normalization operates on evaluated `LottieSourceIntentGeometry` terms. A geometry $G$ consists of:
- `transformStack`: a finite sequence of `LottieSourceIntentTransform` terms $[T_1, T_2, \dots, T_n]$.
- `modifiers`: a finite sequence of `LottieSourceIntentModifier` terms $[M_1, M_2, \dots, M_m]$.

We define four rewrite rules over these sequences:

### Rule 1: Identity Transform Removal (`transform-identity`)
If a transform $T$ has a matrix exactly equal to the identity matrix:
$$[ \dots, T, \dots ] \to [ \dots ]$$

### Rule 2: Adjacent Transform Composition (`transform-compose`)
Two adjacent transforms $T_i$ and $T_{i+1}$ are composed by row-vector matrix concatenation $T_{i,i+1} = T_i \cdot T_{i+1}$:
$$[ \dots, T_i, T_{i+1}, \dots ] \to [ \dots, T_{i,i+1}, \dots ]$$

### Rule 3: Identity Trim Removal (`trim-identity`)
If a static trim modifier $M$ normalizes exactly to the unit interval $[0.0, 1.0]$:
$$[ \dots, M, \dots ] \to [ \dots ]$$

### Rule 4: Adjacent Trim Composition (`trim-compose`)
Two adjacent static trim modifiers $M_j$ and $M_{j+1}$ with normalized intervals $[s_j, e_j]$ and $[s_{j+1}, e_{j+1}]$ are composed into a single trim with interval $[s_{j,j+1}, e_{j,j+1}]$ where:
$$s_{j,j+1} = s_j + (e_j - s_j) \cdot s_{j+1}$$
$$e_{j,j+1} = s_j + (e_j - s_j) \cdot e_{j+1}$$
$$[ \dots, M_j, M_{j+1}, \dots ] \to [ \dots, M_{j,j+1}, \dots ]$$

---

## 2. Strong Normalization (Termination)

Let $N_{\text{trans}}(G)$ be the number of transforms in the `transformStack` of $G$, and $N_{\text{mod}}(G)$ be the number of modifiers in the `modifiers` of $G$. We define the reduction weight function $W(G)$ as:
$$W(G) = N_{\text{trans}}(G) + N_{\text{mod}}(G)$$

### Proof of Termination (Theorem)
1. The weight $W(G)$ is a non-negative integer for any valid geometry term: $W(G) \ge 0$.
2. Every rewrite rule application strictly decreases $W(G)$:
   - `transform-identity` decreases $N_{\text{trans}}(G)$ by 1, so $W(G') = W(G) - 1$.
   - `transform-compose` decreases $N_{\text{trans}}(G)$ by 1, so $W(G') = W(G) - 1$.
   - `trim-identity` decreases $N_{\text{mod}}(G)$ by 1, so $W(G') = W(G) - 1$.
   - `trim-compose` decreases $N_{\text{mod}}(G)$ by 1, so $W(G') = W(G) - 1$.
3. Since every step strictly reduces the non-negative integer weight $W(G)$, any sequence of rewrites must terminate in at most $W(G)$ steps. Thus, the system is strongly normalizing.

Status: `theorem`

---

## 3. Confluence (Uniqueness of Normal Forms)

By Newman's Lemma, because the rewrite system is strongly normalizing, it is confluent if and only if all critical pairs (overlapping rules) are joinable.

### Enumeration of Critical Pairs

#### 1. Overlap of `transform-compose` with itself
Suppose we have three adjacent transforms $[T_1, T_2, T_3]$. We have two possible compositions:
- Option A: Compose $T_1, T_2$ first, yielding $[T_{12}, T_3]$, then compose to $T_{(12)3}$.
- Option B: Compose $T_2, T_3$ first, yielding $[T_1, T_{23}]$, then compose to $T_{1(23)}$.

Since matrix multiplication is associative:
$$T_{(12)3} = (T_1 \cdot T_2) \cdot T_3 = T_1 \cdot (T_2 \cdot T_3) = T_{1(23)}$$
Both branches join to the same identical composed transform.
Status: `theorem`

#### 2. Overlap of `transform-compose` and `transform-identity`
Suppose we have an identity transform $T_{\text{id}}$ adjacent to $T_1$:
- Option A: Remove $T_{\text{id}}$ via `transform-identity`, yielding $[T_1]$.
- Option B: Compose them via `transform-compose`, yielding $T_1 \cdot I = T_1$.

Both branches yield the same identical transform $[T_1]$.
Status: `theorem`

#### 3. Overlap of `trim-compose` with itself
Suppose we have three adjacent static trims $[M_1, M_2, M_3]$. We have two possible compositions:
- Option A: Compose $M_1, M_2$ first, then $M_3$.
- Option B: Compose $M_2, M_3$ first, then $M_1$.

Let $[s_i, e_i]$ be the interval for $M_i$.
Applying Option A:
1. $M_{12} = [s_1 + (e_1 - s_1)s_2, \ s_1 + (e_1 - s_1)e_2]$. Let this be $[S, E]$.
2. $M_{(12)3} = [S + (E - S)s_3, \ S + (E - S)e_3]$.
   - $S + (E - S)s_3 = s_1 + (e_1 - s_1)s_2 + (e_1 - s_1)(e_2 - s_2)s_3 = s_1 + (e_1 - s_1)(s_2 + (e_2 - s_2)s_3)$.

Applying Option B:
1. $M_{23} = [s_2 + (e_2 - s_2)s_3, \ s_2 + (e_2 - s_2)e_3]$.
2. $M_{1(23)} = [s_1 + (e_1 - s_1)(s_2 + (e_2 - s_2)s_3), \ s_1 + (e_1 - s_1)(s_2 + (e_2 - s_2)e_3)]$.

The resulting intervals are algebraically identical. Thus, the critical pair is joinable.
Status: `theorem`

#### 4. Overlap of `trim-compose` and `trim-identity`
Suppose we have an identity trim $M_{\text{id}}$ (interval $[0, 1]$) adjacent to $M_1$:
- Option A: Remove $M_{\text{id}}$ via `trim-identity`, yielding $[M_1]$.
- Option B: Compose them via `trim-compose`, yielding interval $[s_1 + (e_1 - s_1) \cdot 0, \ s_1 + (e_1 - s_1) \cdot 1] = [s_1, e_1]$.

Both branches yield the same identical modifier $[M_1]$.
Status: `theorem`

#### 5. Two adjacent identity terms
- For adjacent identity transforms $[T_{\text{id1}}, T_{\text{id2}}]$:
  - Option A: Remove $T_{\text{id1}}$ via `transform-identity`, yielding $[T_{\text{id2}}]$, which reduces to $[]$ by `transform-identity`.
  - Option B: Remove $T_{\text{id2}}$ via `transform-identity`, yielding $[T_{\text{id1}}]$, which reduces to $[]$ by `transform-identity`.
  - Option C: Compose them via `transform-compose`, yielding $T_{\text{id1}} \cdot T_{\text{id2}} = I \cdot I = I = T_{\text{id3}}$, which reduces to $[]$ by `transform-identity`.
  All branches join to $[]$ exactly.
- For adjacent identity trims $[M_{\text{id1}}, M_{\text{id2}}]$:
  - Option A: Remove $M_{\text{id1}}$ via `trim-identity`, yielding $[M_{\text{id2}}]$, which reduces to $[]$ by `trim-identity`.
  - Option B: Remove $M_{\text{id2}}$ via `trim-identity`, yielding $[M_{\text{id1}}]$, which reduces to $[]$ by `trim-identity`.
  - Option C: Compose them via `trim-compose`, yielding interval $[0 + (1 - 0) \cdot 0, 0 + (1 - 0) \cdot 1] = [0, 1] = M_{\text{id3}}$, which reduces to $[]$ by `trim-identity`.
  All branches join to $[]$ exactly.
Status: `theorem`

#### 6. An identity term in the middle of a compose chain
- For transforms $[T_1, T_{\text{id}}, T_2]$:
  - Option A: Remove $T_{\text{id}}$ via `transform-identity`, yielding $[T_1, T_2]$, which then composes to $[T_1 \cdot T_2]$ by `transform-compose`.
  - Option B: Compose $T_1$ and $T_{\text{id}}$, yielding $[T_1 \cdot I, T_2] = [T_1, T_2]$, which composes to $[T_1 \cdot T_2]$ by `transform-compose`.
  - Option C: Compose $T_{\text{id}}$ and $T_2$, yielding $[T_1, I \cdot T_2] = [T_1, T_2]$, which composes to $[T_1 \cdot T_2]$ by `transform-compose`.
  All branches join to $[T_1 \cdot T_2]$ exactly.
- For trims $[M_1, M_{\text{id}}, M_2]$:
  - Option A: Remove $M_{\text{id}}$ via `trim-identity`, yielding $[M_1, M_2]$, which composes to $[M_1 \cdot M_2]$.
  - Option B: Compose $M_1$ and $M_{\text{id}}$, yielding $[M_1 \cdot M_{\text{id}}, M_2] = [M_1, M_2]$, which composes to $[M_1 \cdot M_2]$.
  - Option C: Compose $M_{\text{id}}$ and $M_2$, yielding $[M_1, M_{\text{id}} \cdot M_2] = [M_1, M_2]$, which composes to $[M_1 \cdot M_2]$.
  All branches join to $[M_1 \cdot M_2]$ exactly.
Status: `theorem`

Since all critical pairs are joinable, the rewrite system is confluent. Unique normal forms are guaranteed.

---

## 4. Executable Witness

The confluence properties are checked on every commit via the test suite:
- `LottieSourceIntentNormalizerTests` constructs complex multi-matrix and multi-trim geometries and normalizes them under both `leftToRight` and `rightToLeft` strategies.
- The test asserts that both strategies produce bit-identical resulting structures, proving confluence empirically on the test inputs.

Status: `witnessed`
