import Foundation
import _JSON
import Testing

@Suite struct JSONIdentityTests {
    private struct Atom: Codable, Hashable, Sendable { let name: String }
    private static let samples: [JSON] = [
        .null, false, 1, .double(1), "1", [], [:],
        JSON(Date(timeIntervalSince1970: 1_704_067_200.25)),
        JSON(JSONError("Opaque", path: ["source"])), JSON(Atom(name: "Native")),
        ["nested": [true, 1, .double(1), "1", .null, [], [:]],
         "date": JSON(Date(timeIntervalSince1970: 1_704_067_200.25)),
         "error": JSON(JSONError("Opaque")), "atom": JSON(Atom(name: "Native"))],
    ]

    @Test(arguments: samples)
    func generic_json_decoding_matches_concrete_identity_without_changing_native_atoms(input: JSON) throws {
        func generic<Value: Decodable>(_ input: JSON, as type: Value.Type) throws -> (Value, Value) {
            (try input.decode(type), try JSON.decoded(type, from: input))
        }
        let (instance, staticValue) = try generic(input, as: JSON.self)
        #expect(instance == input.decode(JSON.self) && staticValue == JSON.decoded(JSON.self, from: input))
        #expect(Swift.type(of: instance.rawValue) == Swift.type(of: input.rawValue))
        #expect(Swift.type(of: staticValue.rawValue) == Swift.type(of: input.rawValue))
    }
}
