import Foundation
import _JSON
import Testing

@Suite struct JSONEncodingTests {
    @Test(arguments: [
            ("9007199254740993.0", 9_007_199_254_740_993),
            ("9.007199254740993e15", 9_007_199_254_740_993),
            ("9223372036854775807.0", Int.max),
            ("-9223372036854775808.0", Int.min),
        ])
    func integral_decimal_literals_keep_exact_integer_precision_and_bounds(literal: String, expected: Int) throws {
        #expect(try JSON(jsonObject: NSDecimalNumber(string: literal)) == .int(expected))
        let data = Data(literal.utf8)
        let native = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        // Foundation's Darwin fast path can already round some decimal tokens
        // into Double. When it supplies an exact decimal, the JSON bridge must
        // retain it; the native decimal conversion above is always exercised.
        if native is NSDecimalNumber {
            #expect(try JSON(data: data) == .int(expected))
        }
    }

    @Test func fractional_and_out_of_range_decimals_keep_floating_representation() throws {
        for literal in ["9007199254740993.5", "9223372036854775808.0", "-9223372036854775809.0"] {
            let value = try JSON(jsonObject: NSDecimalNumber(string: literal))
            #expect(value.rawValue is Double)
        }
    }

    private struct Reference: Encodable {
        let id: String
        let data: [String: JSON]
    }

    @Test func encoding_keeps_empty_containers_and_unbound_native_reference_shape() throws {
        #expect(try JSON.encoded([String: String]()) == .object([:]))
        #expect(try JSON.encoded([String]()) == .array([]))
        #expect(try JSON.encoded(Reference(id: "demo.programme", data: [:])) == ["id": "demo.programme", "data": [:]])
        #expect(try JSON.encoded([Reference(id: "demo.programme", data: [:])]) == [["id": "demo.programme", "data": [:]]])
    }

    @Test func optional_encoding_preserves_null_and_propagates_authored_failures() throws {
        enum Failure: Error { case authored }
        struct Broken: Encodable {
            func encode(to encoder: any Encoder) throws { throw Failure.authored }
        }
        #expect(try JSON.encoded(String?.none) == .null)
        #expect(try JSON.encoded(String??.some(.none)) == .null)
        #expect(try JSON(jsonObject: String??.some(.none) as Any) == .null)
        #expect(throws: Failure.authored) { try JSON.encoded(Broken?.some(Broken())) }
    }

    @Test func encoding_uses_codable_containers_once_and_keeps_epoch_dates_urls_and_bytes() throws {
        final class Counter { var calls = 0 }
        struct Value: Encodable {
            let counter: Counter
            let date: Date
            enum CodingKeys: String, CodingKey { case nested, date, atom, url, bytes, empty, omitted }
            func encode(to encoder: any Encoder) throws {
                counter.calls += 1
                var root = encoder.container(keyedBy: CodingKeys.self)
                var nested = root.nestedContainer(keyedBy: CodingKeys.self, forKey: .nested)
                try nested.encode(date, forKey: .date)
                try nested.encode(JSON(date), forKey: .atom)
                try nested.encode(URL(string: "https://example.com/programmes?p=1")!, forKey: .url)
                try nested.encode(Data([0, 1, 255]), forKey: .bytes)
                _ = root.nestedUnkeyedContainer(forKey: .empty)
                try root.encodeIfPresent(String?.none, forKey: .omitted)
            }
        }
        let date = Date(timeIntervalSince1970: 1_704_067_200.25)
        let counter = Counter()
        let json = try JSON.encoded(Value(counter: counter, date: date))
        #expect(counter.calls == 1)
        #expect(json == ["nested": ["date": 1_704_067_200.25, "atom": 1_704_067_200.25,
            "url": "https://example.com/programmes?p=1", "bytes": [0, 1, 255]], "empty": []])
        #expect(try JSON.encoded(date) == JSON.double(date.timeIntervalSince1970))
        #expect(try JSON.encoded(JSON(date)) == JSON.double(date.timeIntervalSince1970))
        #expect(try JSON.encoded(Data()) == .array([]))
        #expect(try JSON.encoded(1.0) == .int(1))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        #expect(try JSON(data: encoder.encode(JSON(date))).string == "2024-01-01T00:00:00Z")
        #expect(throws: EncodingError.self) { try JSON.encoded(Double.infinity) }
    }

    @Test func encoding_and_wire_decoding_keep_large_numbers_without_signed_overflow() throws {
        #expect(try JSON.encoded(Int64.max) == .int(Int.max))
        #expect(try JSON.encoded(9_007_199_254_740_993 as Int64) == .int(9_007_199_254_740_993))
        #expect(try JSON.encoded(UInt64.max) == .double(Double(UInt64.max)))
        for value in [1.0e100, Double(Int64.max), Double(Int64.min).nextDown, -1.25] {
            #expect(try JSON.encoded(value) == .double(value))
        }
        #expect(try JSON(data: Data("{\"large\":1e100,\"unsigned\":18446744073709551615}".utf8)) == [
            "large": .double(1.0e100), "unsigned": .double(Double(UInt64.max)),
        ])
    }
}
