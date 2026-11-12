import Foundation
import _JSON
import Testing

@Suite struct JSONNativeCollectionTests {
    @Test
    func native_foundation_arrays_compare_symmetrically_with_literal_arrays() {
        let values: JSON.Array = [1, "coffee", .null]
        let native = JSON(NativeArray(values))
        let literal = JSON.array(values)
        #expect(native.rawValue is NativeArray)
        #expect(native.rawValue as? JSON.Array == values)
        #expect(native == literal)
        #expect(literal == native)
        #expect(native.hashValue == literal.hashValue)
        #expect(Set([native, literal]).count == 1)
    }

    @Test
    func nested_native_collections_remain_interchangeable_dictionary_keys() {
        let date = JSON(Date(timeIntervalSince1970: 42))
        let inner: JSON.Array = [date, true, 42, .double(-0.0), .null]
        let values: JSON.Array = [
            ["name": "Coffee", "samples": JSON(NativeArray(inner))],
            JSON([Int]()), JSON([String: Int]())
        ]
        let native: JSON = ["records": JSON(NativeArray(values))]
        let literal: JSON = ["records": .array([
            ["name": "Coffee", "samples": .array(inner)], [], [:]
        ])]
        #expect(native == literal && literal == native)
        #expect(native.hashValue == literal.hashValue)
        #expect(Set([native, literal]).count == 1)
        #expect([native: "found"][literal] == "found")
        #expect([literal: "found"][native] == "found")
    }
}

// NSArray's inherited Objective-C storage is unused. The fixture's only storage
// is an immutable array of Sendable JSON values, exposed through read primitives.
private final class NativeArray: NSArray, Codable, @unchecked Sendable {
    private let values: JSON.Array

    init(_ values: JSON.Array) {
        self.values = values
        super.init()
    }

    override init() {
        values = []
        super.init()
    }

    override init(objects: UnsafePointer<AnyObject>?, count: Int) {
        values = (0..<count).map { index in
            let value = objects![index]
            if let value = value as? JSON { return value }
            do { return try JSON(jsonObject: value) }
            catch { preconditionFailure("Unsupported fixture value: \(error)") }
        }
        super.init()
    }

    override var count: Int { values.count }
    override func object(at index: Int) -> Any { values[index] }

    required init(from decoder: any Decoder) throws {
        values = try JSON.Array(from: decoder)
        super.init()
    }

    func encode(to encoder: any Encoder) throws { try values.encode(to: encoder) }

    required init?(coder: NSCoder) { return nil }
}
