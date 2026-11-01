import Compute
import Foundation
import Testing

@Suite(.timeLimit(.minutes(1))) struct ComputedInputTests {
    @Test func required_and_optional_json_slots_preserve_native_data_and_null_semantics() async throws {
        let date = Date(timeIntervalSince1970: 1_704_067_200.25)
        let opaque = JSONError("Source data", path: ["opaque"])
        let payload: JSON = ["date": JSON(date), "error": JSON(opaque),
            "nested": [true, 1, "1", .null, [], [:]],
            "deferred": .returns("unregistered", [:])]
        let item = JSON.returns("item", [])
        for document in [JSON.returns("this", ["value": item]), .returns("map", ["src": item, "dst": item])] {
            let runtime = Compute.Runtime(document: document, context: Compute.Context(item: payload))
            defer { await runtime.cancel() }
            let result = try await runtime.value()
            #expect(result == payload)
            #expect(result["date"].rawValue as? Date == date && result["error"].rawValue as? JSONError == opaque)
        }
        let null = Compute.Runtime(document: .returns("this", ["value": item]), context: Compute.Context(item: .null))
        defer { await null.cancel() }
        #expect(try await null.value() == .null)
        let optional = Compute.Runtime(document: .returns("map", ["src": ["base": true], "dst": .null]))
        defer { await optional.cancel() }
        #expect(try await optional.value() == ["base": true])
    }

    @Test(arguments: ["this", "either"])
    func malformed_present_conditions_fail_at_the_field_instead_of_selecting_a_branch(keyword: String) async throws {
        for condition: JSON in [["unexpected": true], "not-a-boolean"] {
            let branch: JSON = ["condition": condition, "value": "Selected"]
            let expression = JSON.returns(keyword, keyword == "this" ? branch : [branch, ["value": "Fallback"]])
            do {
                _ = try await value(expression)
                Issue.record("Malformed condition selected a branch")
            } catch let error as JSONError {
                #expect(error.message.contains("Bool"))
                #expect(error.path == ["{returns}", keyword] + (keyword == "either" ? ["0"] : []) + ["condition"])
            }
        }
    }

    @Test func unregistered_invocations_fail_when_evaluated_but_not_when_quoted_or_inactive() async throws {
        // `less` is not registered: the ordinary operation is comparison.less.
        let unknown = JSON.returns("less", ["lhs": 460, "rhs": 400])
        for expression in [unknown, .returns("this", ["condition": unknown, "value": "Selected"])] {
            do {
                _ = try await value(expression)
                Issue.record("An unregistered invocation produced a value")
            } catch let error as JSONError {
                #expect(error.message == "Unregistered Compute keyword less")
                #expect(error.path.suffix(2) == ["{returns}", "less"])
            }
        }
        #expect(try await value(.returns("literal", ["value": unknown])) == unknown)
        #expect(try await value(.returns("either", [["condition": false, "value": unknown], ["value": "Fallback"]])) == "Fallback")
        #expect(try await value(.returns("missing", [:], default: "Authored fallback")) == "Authored fallback")
    }

    @Test func absent_null_and_false_conditions_keep_their_existing_meaning() async throws {
        for branch: JSON in [["value": "Selected"], ["condition": .null, "value": "Selected"]] {
            #expect(try await value(.returns("this", branch)) == "Selected")
            #expect(try await value(.returns("either", [branch])) == "Selected")
        }
        #expect(try await value(.returns("either", [
            ["condition": false, "value": .returns("error", ["message": "Inactive branch must remain lazy"])],
            ["value": "Fallback"],
        ])) == "Fallback")
        let malformed = JSON.returns("this", ["condition": ["wrong": true], "value": "Selected"], default: "Authored default")
        #expect(try await value(malformed) == "Authored default")
    }

    @Test func invalid_optional_arrays_and_numbers_do_not_disappear_into_defaults() async throws {
        for field in ["if", "unless"] {
            await expectJSONError(containing: "Bool") {
                _ = try await value(.returns("yes", .object([field: [true, ["wrong": true]]])))
            }
        }
        await expectJSONError(containing: "offset") {
            _ = try await value(.returns("date", ["since": ["epoch": 0], "offset": "not-a-number"]))
        }
    }

    @Test func a_live_condition_reports_bad_data_then_recovers_to_false_and_true() async throws {
        let references = TestReferences()
        await references.set("enabled", to: false)
        let expression = JSON.returns("either", [
            ["condition": JSON.returns("from", ["reference": "enabled"]), "value": "Enabled"],
            ["value": "Disabled"],
        ])
        let runtime = try runtime(expression, references: references)
        defer { await runtime.cancel(); await references.finish() }
        var values = runtime.run().makeAsyncIterator()
        #expect(try await values.next()?.get() == "Disabled")
        await references.set("enabled", to: ["invalid": true])
        if case .failure(let error) = await values.next() {
            #expect(error.path == ["{returns}", "either", "0", "condition"])
        } else { Issue.record("Expected a typed condition diagnostic") }
        await references.set("enabled", to: true)
        #expect(try await values.next()?.get() == "Enabled")
        await references.set("enabled", to: .returns("missing", [:]))
        if case .failure(let error) = await values.next() {
            #expect(error.message == "Unregistered Compute keyword missing")
        } else { Issue.record("Expected an unregistered returned-expression diagnostic") }
        await references.set("enabled", to: false)
        #expect(try await values.next()?.get() == "Disabled")
    }
}
