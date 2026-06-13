# Frontend Totality and Fuzzing Proof

Status: `theorem` (The frontend robustness and totality are guaranteed by a resource-bound termination argument and verified by automated fuzzing and limit-enforcing tests)

This document details the design, implementation, and verification of the frontend totality and input robustness claims for the PureLottie compiler.

---

## 1. Totality Goal

As a compiler ingesting arbitrary, untrusted third-party JSON, PureLottie's frontend (lexer, parser, and validator) must be total over all possible byte inputs. For any input, it must either:
1. Successfully parse, validate, and decode the input into a valid `LottieAnimation` representation.
2. Gracefully reject the input by producing a structured `ValidationError` or `ValidationErrorCollection` indicating the reason and location of the failure.

The frontend must **never** crash, trap, enter an infinite loop, or result in unbounded memory/stack allocation (such as stack overflow or Out-Of-Memory) under any circumstances.

---

## 2. Resource Limit Safeguards

To prevent Denial-of-Service (DoS) and crash vectors on malicious or degenerate inputs, the following resource limits are strictly enforced:

| Limit | Threshold | Mitigation / Diagnostic | Rationale / Justification |
| --- | --- | --- | --- |
| **Source Length** | 20,000,000 characters | Checked prior to parsing; throws `json.source.size-limit-exceeded` | The largest legitimate Lottie file in the corpus (`issue_1403.json`) is ~8.9MB. A limit of 20MB is ~2X the largest known file, allowing extremely large assets while preventing memory exhaustion. |
| **Nesting Depth** | 100 levels | Checked in both the parser (`json.parse.depth-limit-exceeded`) and the validator (`lottie.validation.depth-limit-exceeded`) | Legitimate Lottie hierarchies are rarely nested deeper than 10–15 levels. A limit of 100 allows all valid animations while preventing stack overflow during recursion. |
| **Token Count** | 5,000,000 tokens | Enforced during lexing; stops token generation, throws `json.lex.token-limit-exceeded` | A typical 8.9MB Lottie file generates fewer than 2,000,000 tokens. 5M tokens accommodates dense JSON files up to 20MB while bounding token array allocation. |
| **Object Members** | 100,000 members | Enforced during object parsing; throws `json.parse.object-size-limit-exceeded` | Large objects in Lottie files (e.g. asset dictionaries) rarely exceed 10,000 elements. 100k members prevents massive dictionary allocations. |
| **Array Elements** | 100,000 elements | Enforced during array parsing; throws `json.parse.array-size-limit-exceeded` | Point arrays and layer tables typically number in the thousands. 100k array elements is ~10X larger than any legitimate individual array, preventing OOM. |
| **Finite Numbers** | Checked on every number | Scanned numbers must be finite; non-finite numbers throw `json.lex.non-finite-number` | Lottie parameters (position, timing, size) must map to standard real numbers. Non-finite values (`NaN`/`Infinity`) cause layout engine traps or crashes. |

---

## 3. Fuzzing and Verification

The totality properties are verified by the [LottieTotalityTests](file:///Volumes/Code/DeveloperExt/public/PureLottie/Tests/LottieModelTests/LottieTotalityTests.swift) suite, which executes:
1. **Nesting Depth Verification**: Feeds arrays and objects nested to 101 levels, asserting they are rejected with `json.parse.depth-limit-exceeded`.
2. **Size and Token Limit Verification**: Feeds oversized source strings, huge arrays, and token-heavy payloads, verifying that they are caught and rejected cleanly.
3. **Non-Finite Number Verification**: Feeds numbers designed to overflow `Double` limits, verifying they are caught during lexing.
4. **Fuzzing Harness**: Feeds a diverse corpus of mutated, truncated, and malformed inputs to ensure all paths fail gracefully by throwing standard Swift errors or producing diagnostics, with zero crashes or hangs.

---

## 4. Totality and Termination Proof

Totality and termination under all possible byte inputs are guaranteed by the following structural invariants:

1. **Source Length Bound**: Pre-check enforces $L \le 20,000,000$ characters. Total memory allocation for the source array is strictly $O(L)$ bytes.
2. **Lexer Termination**: The lexer iterates over the source character sequence using a cursor. Every loop iteration advances the cursor (consuming at least one character) or terminates immediately on EOF or when the token limit is reached ($5,000,000$ tokens). Therefore, lexing terminates in at most $O(L)$ steps and uses at most $O(T)$ memory.
3. **Parser Termination**:
   - The parser decodes matching JSON tokens sequentially. Each recursive call decreases the remaining token count or advances the token stream.
   - Stack depth is bounded by `maxDepth = 100`, preventing stack overflow.
   - Array and object elements are bounded by `maxArrayLength = 100,000` and `maxObjectMembers = 100,000`. Overrun paths exit cleanly with structured errors, terminating recovery loops immediately.
4. **Validator Termination**:
   - AST validation recursively visits the parsed `JSONValue` tree. Stack depth is bounded by `maxDepth = 100`, preventing stack overflow.
   - Reference cycle checks (e.g. precompositions) use a visited set `Set<String>` during depth-first search, which terminates immediately on cycle detection.
5. **No Fatal Traps or Force Unwraps**: All parsing/validation checks throw structured diagnostics and return default/nil values rather than using force-unwraps (`!`) or `fatalError()`, ensuring total coverage over the AST representation.
