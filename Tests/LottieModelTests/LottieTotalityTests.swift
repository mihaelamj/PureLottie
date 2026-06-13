import LottieModel
import XCTest

/// Deterministic Linear Congruential Generator for systematic reproducible fuzzing.
struct FuzzPRNG {
    var state: UInt32

    mutating func next() -> UInt32 {
        state = state &* 1_664_525 &+ 1_013_904_223
        return state
    }

    mutating func next(upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt32(upperBound))
    }
}

final class LottieTotalityTests: XCTestCase {
    func testNestingDepthLimit() throws {
        // Create an array nested 101 levels deep
        var deepArray = "0"
        for _ in 0 ..< 101 {
            deepArray = "[\(deepArray)]"
        }

        do {
            _ = try LottieSourceDocument.parse(deepArray)
            XCTFail("Expected nested array exceeding limit to throw.")
        } catch let collection as ValidationErrorCollection {
            XCTAssertTrue(
                collection.values.contains { $0.ruleID == "json.parse.depth-limit-exceeded" },
                "Expected json.parse.depth-limit-exceeded but got \(collection.values)"
            )
        }

        // Create an object nested 101 levels deep
        var deepObject = "0"
        for i in 0 ..< 101 {
            deepObject = "{\"k\(i)\":\(deepObject)}"
        }

        do {
            _ = try LottieSourceDocument.parse(deepObject)
            XCTFail("Expected nested object exceeding limit to throw.")
        } catch let collection as ValidationErrorCollection {
            XCTAssertTrue(
                collection.values.contains { $0.ruleID == "json.parse.depth-limit-exceeded" },
                "Expected json.parse.depth-limit-exceeded but got \(collection.values)"
            )
        }

        // A nested array below the limit should not fail due to depth limit
        var safeArray = "0"
        for _ in 0 ..< 99 {
            safeArray = "[\(safeArray)]"
        }
        do {
            let doc = try LottieSourceDocument.parse(safeArray)
            let errors = LottieValidator().collectErrors(in: doc)
            XCTAssertFalse(errors.contains { $0.ruleID == "json.parse.depth-limit-exceeded" })
        } catch let collection as ValidationErrorCollection {
            XCTAssertFalse(collection.values.contains { $0.ruleID == "json.parse.depth-limit-exceeded" })
        }
    }

    func testSourceSizeLimit() throws {
        // Create a string that exceeds 20MB (20,000,001 characters)
        let largeString = String(repeating: " ", count: 20_000_001)

        do {
            _ = try LottieSourceDocument.parse(largeString)
            XCTFail("Expected source size limit check to throw.")
        } catch let collection as ValidationErrorCollection {
            XCTAssertTrue(
                collection.values.contains { $0.ruleID == "json.source.size-limit-exceeded" },
                "Expected json.source.size-limit-exceeded but got \(collection.values)"
            )
        }
    }

    func testTokenLimit() throws {
        // Generating a string with 5,000,001 comma tokens
        // "[,,,,...]"
        let tokenLimitString = "[" + String(repeating: ",", count: 5_000_001) + "]"

        do {
            _ = try LottieSourceDocument.parse(tokenLimitString)
            XCTFail("Expected token limit check to throw.")
        } catch let collection as ValidationErrorCollection {
            XCTAssertTrue(
                collection.values.contains { $0.ruleID == "json.lex.token-limit-exceeded" },
                "Expected json.lex.token-limit-exceeded but got \(collection.values)"
            )
        }
    }

    func testArrayLengthLimit() throws {
        // Generating an array with 100,001 elements
        // "[0,0,0...]"
        let arrayString = "[" + String(repeating: "0,", count: 100_001) + "0]"

        do {
            _ = try LottieSourceDocument.parse(arrayString)
            XCTFail("Expected array size limit check to throw.")
        } catch let collection as ValidationErrorCollection {
            XCTAssertTrue(
                collection.values.contains { $0.ruleID == "json.parse.array-size-limit-exceeded" },
                "Expected json.parse.array-size-limit-exceeded but got \(collection.values)"
            )
        }
    }

    func testObjectMembersLimit() throws {
        // Generating an object with 100,001 members
        // "{"k0":0,"k1":0,...}"
        var objectString = "{"
        for i in 0 ... 100_001 {
            objectString += "\"k\(i)\":0,"
        }
        objectString += "\"last\":0}"

        do {
            _ = try LottieSourceDocument.parse(objectString)
            XCTFail("Expected object size limit check to throw.")
        } catch let collection as ValidationErrorCollection {
            XCTAssertTrue(
                collection.values.contains { $0.ruleID == "json.parse.object-size-limit-exceeded" },
                "Expected json.parse.object-size-limit-exceeded but got \(collection.values)"
            )
        }
    }

    func testNonFiniteNumbers() throws {
        // Value that overflows Double representing Infinity
        let infinityString = "{\"val\": 1e9999999999}"

        do {
            _ = try LottieSourceDocument.parse(infinityString)
            XCTFail("Expected non-finite number check to throw.")
        } catch let collection as ValidationErrorCollection {
            XCTAssertTrue(
                collection.values.contains { $0.ruleID == "json.lex.non-finite-number" },
                "Expected json.lex.non-finite-number but got \(collection.values)"
            )
        }
    }

    func testFuzzedInputs() throws {
        let seed = "{\"v\":\"5.5.7\",\"fr\":60,\"ip\":0,\"op\":60,\"w\":100,\"h\":100,\"layers\":[]}"
        var inputs: [String] = []

        // 1. Systematic Truncations
        for i in 0 ... seed.count {
            let index = seed.index(seed.startIndex, offsetBy: i)
            inputs.append(String(seed[..<index]))
        }

        // 2. Systematic Bad Character Injection at all positions
        let badChars = ["{", "}", "[", "]", ":", ",", "\"", "\\", "\0", "\\u0000", "\\u12", "1e9999999", "NaN", "Infinity", "-Infinity", "1.2.3"]
        for char in badChars {
            for i in 0 ... seed.count {
                let index = seed.index(seed.startIndex, offsetBy: i)
                var mutated = seed
                mutated.insert(contentsOf: char, at: index)
                inputs.append(mutated)
            }
        }

        // 3. Systematic Duplicate Keys
        inputs.append("{\"v\":\"5.5.7\",\"v\":\"5.5.8\",\"fr\":60,\"ip\":0,\"op\":60,\"w\":100,\"h\":100,\"layers\":[]}")
        inputs.append("{\"fr\":60,\"fr\":120,\"v\":\"5.5.7\",\"ip\":0,\"op\":60,\"w\":100,\"h\":100,\"layers\":[]}")

        // 4. Systematic Cyclic Precompositions
        let cyclicLottie = """
        {
          "v": "5.5.7",
          "fr": 60,
          "ip": 0,
          "op": 60,
          "w": 100,
          "h": 100,
          "assets": [
            {
              "id": "pre1",
              "layers": [
                { "ty": 0, "refId": "pre2" }
              ]
            },
            {
              "id": "pre2",
              "layers": [
                { "ty": 0, "refId": "pre1" }
              ]
            }
          ],
          "layers": [
            { "ty": 0, "refId": "pre1" }
          ]
        }
        """
        inputs.append(cyclicLottie)

        let selfReferentialLottie = """
        {
          "v": "5.5.7",
          "fr": 60,
          "ip": 0,
          "op": 60,
          "w": 100,
          "h": 100,
          "assets": [
            {
              "id": "pre1",
              "layers": [
                { "ty": 0, "refId": "pre1" }
              ]
            }
          ],
          "layers": []
        }
        """
        inputs.append(selfReferentialLottie)

        // 5. Deterministic Randomized Fuzzing (mutations and random text)
        var prng = FuzzPRNG(state: 42)
        let alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789{}[]:\",.-\0\\u1234 \n\t"

        for _ in 0 ..< 500 {
            var mutated = seed
            let mutationCount = prng.next(upperBound: 4) + 1
            for _ in 0 ..< mutationCount {
                if mutated.isEmpty { break }
                let op = prng.next(upperBound: 3)
                let pos = prng.next(upperBound: mutated.count)
                let idx = mutated.index(mutated.startIndex, offsetBy: pos)
                if op == 0 {
                    // Delete
                    mutated.remove(at: idx)
                } else if op == 1 {
                    // Insert random char from alphabet
                    let randCharIdx = prng.next(upperBound: alphabet.count)
                    let char = alphabet[alphabet.index(alphabet.startIndex, offsetBy: randCharIdx)]
                    mutated.insert(char, at: idx)
                } else {
                    // Replace
                    let randCharIdx = prng.next(upperBound: alphabet.count)
                    let char = alphabet[alphabet.index(alphabet.startIndex, offsetBy: randCharIdx)]
                    mutated.replaceSubrange(idx ... idx, with: String(char))
                }
            }
            inputs.append(mutated)
        }

        // 6. Type-confused structures: replace keys or values with wrong JSON types
        let typeConfusions = [
            "{\"v\": [], \"fr\": 60}",
            "{\"v\": {}, \"fr\": 60}",
            "{\"v\": true, \"fr\": 60}",
            "{\"v\": null, \"fr\": 60}",
            "{\"v\": \"5.5.7\", \"fr\": []}",
            "{\"v\": \"5.5.7\", \"fr\": {}}",
            "{\"v\": \"5.5.7\", \"fr\": \"sixty\"}",
            "{\"v\": \"5.5.7\", \"layers\": {}}",
            "{\"v\": \"5.5.7\", \"layers\": \"not-an-array\"}",
            "{\"v\": \"5.5.7\", \"layers\": [1, 2, 3]}",
        ]
        inputs.append(contentsOf: typeConfusions)

        // Verify that all inputs yield either a successful parse/validation or a structured diagnostic, never a crash
        for input in inputs {
            do {
                let doc = try LottieSourceDocument.parse(input)
                let errors = LottieValidator().collectErrors(in: doc)
                // If it parses and validates, fine. Otherwise, validation errors are produced.
                _ = errors
            } catch let collection as ValidationErrorCollection {
                XCTAssertFalse(collection.values.isEmpty, "Expected non-empty validation errors in collection.")
            } catch {
                XCTFail("Unexpected error type thrown: \(error)")
            }
        }
    }
}
