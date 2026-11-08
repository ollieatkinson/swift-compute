import Foundation
import _JSON
import Testing

@Suite
struct JSONDecodingTests {
    @Test
    func numeric_decoding_rejects_coercions_and_checks_conversion_bounds() throws {
        #expect(try JSON.int(8).decode(Double.self) == 8)
        #expect(try JSON.double(8).decode(Int.self) == 8)
        #expect(try JSON.int(127).decode(Int8.self) == 127)
        #expect(try JSON.int(9_007_199_254_740_993).decode(UInt64.self) == 9_007_199_254_740_993)
        #expect(try JSON(UInt64.max).decode(UInt64.self) == UInt64.max)
        #expect(try JSON.double(0.25).decode(Float.self) == 0.25)
        for input: JSON in [true, false, "1", .null] {
            #expect(throws: (any Error).self) { try input.decode(Double.self) }
            #expect(throws: (any Error).self) { try input.decode(Int.self) }
        }
        #expect(try JSON.int(1).decode(String.self) == "1")
        for input: JSON in [
            .null,
            [],
            [:],
            [1, true, "1"],
            ["value": [1, true]],
            JSON(UInt64.max),
            JSON([UInt64.max])
        ] {
            #expect(try input.decode(String.self) == String(describing: input.any))
        }
        #expect(throws: (any Error).self) { try JSON.double(1.5).decode(Int.self) }
        #expect(throws: (any Error).self) { try JSON.int(-1).decode(UInt.self) }
        #expect(throws: (any Error).self) { try JSON.int(128).decode(Int8.self) }
        #expect(throws: (any Error).self) { try JSON.double(1.0e100).decode(Int.self) }
        #expect(throws: (any Error).self) { try JSON.double(1.0e100).decode(Float.self) }
    }

    @Test
    func literal_checks_reach_arrays_and_synthesized_fields_without_losing_native_values() throws {
        struct Reading: Decodable {
            let count: Int
            let ratio: Double
            let enabled: Bool
            let title: String
            let date: Date
            let url: URL
            let payload: JSON
        }
        let date = Date(timeIntervalSince1970: 1_704_067_200.25)
        let payload: JSON = ["date": JSON(date), "error": JSON(JSONError("Opaque"))]
        let input: JSON = ["count": 2,
                           "ratio": 1,
                           "enabled": true,
                           "title": "1",
                           "date": JSON(date),
                           "url": "https://example.com",
                           "payload": payload]
        let result = try input.decode(Reading.self)
        #expect(result.count == 2 && result.ratio == 1 && result.enabled && result.title == "1")
        #expect(result.date == date && result.url.absoluteString == "https://example.com")
        #expect(result.payload == payload)
        let opaque = JSONError("Opaque")
        #expect(try JSON(opaque).decode(JSONError.self) == opaque)
        for (key, value): (String, JSON) in [
            ("count", 1.5),
            ("ratio", true),
            ("count", "1"),
            ("ratio", "1")
        ] {
            var invalid = input
            invalid[key] = value
            #expect(throws: (any Error).self) { try invalid.decode(Reading.self) }
        }
        #expect(try JSON.array([1, 2.5]).decode([Double].self) == [1, 2.5])
        #expect(throws: (any Error).self) { try JSON.array([1, true]).decode([Double].self) }
    }
}
