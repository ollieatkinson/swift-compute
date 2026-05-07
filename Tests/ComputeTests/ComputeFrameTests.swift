import Compute
import Testing

@Suite
struct ComputeFrameTests {
    @Test func subscript_appends_route_components_and_preserves_context_and_depth() async throws {
        let item: JSON = ["id": 7]
        let actual = try await value(
            ["{returns}": ["frame_probe": [:]]],
            in: Compute.Context(item: item),
            functions: [FrameProbe.function, RouteProbeFunction()]
        )

        let base: [Compute.Route.Component] = [.key("{returns}"), .key("frame_probe")]

        #expect(actual == [
            "absolute_compute": frameSummary(
                route: [
                    .key("absolute"),
                    .index(3),
                    .key("{returns}"),
                    .key("route_probe"),
                ],
                depth: 0,
                item: item,
                input: "payload"
            ),
            "child_compute": frameSummary(
                route: base + [.key("child"), .key("{returns}"), .key("route_probe")],
                depth: 0,
                item: item,
                input: "payload"
            ),
            "child_frame": frameSummary(route: base + [.key("child")], depth: 0, item: item),
            "current_compute": frameSummary(
                route: base + [.key("{returns}"), .key("route_probe")],
                depth: 0,
                item: item,
                input: "payload"
            ),
            "frame": frameSummary(route: base, depth: 0, item: item),
            "indexed_frame": frameSummary(
                route: base + [.key("array"), .index(2), .key("value")],
                depth: 0,
                item: item
            ),
        ])
    }
}

private struct FrameProbe: Compute.KeywordDefinition {
    static let name = "frame_probe"

    func compute(in frame: Compute.Frame) async throws -> JSON? {
        let probe: JSON = ["{returns}": ["route_probe": "payload"]]
        return [
            "absolute_compute": try await frame.compute(
                probe,
                at: Compute.Route([.key("absolute"), .index(3)])
            ),
            "child_compute": try await frame["child"].compute(probe),
            "child_frame": frameSummary(frame["child"]),
            "current_compute": try await frame.compute(probe),
            "frame": frameSummary(frame),
            "indexed_frame": frameSummary(frame["array", 2, "value"]),
        ]
    }
}
