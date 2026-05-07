import Algorithms
import Brain
import Testing

@Suite(.serialized)
struct BrainTests {
    @Test func commitsBoundedThoughtsUntilSettled() async throws {
        let brain = Brain<String, Int>(
            [
                .init("adult", inputs: ["age"]),
            ],
            state: ["age": 17],
            change: ["age": 21],
            remainingThoughts: { state in
                state["adult"] == 1 ? 0 : 1
            }
        )

        let commit = try await brain.commit(thoughts: 1) { lemma, state in
            #expect(lemma == "adult")
            #expect(state["age"] == 21)
            return 1
        }

        #expect(commit.change == ["age": 21])
        #expect(commit.thoughts == ["adult": 1])
        #expect(commit.state["adult"] == 1)
        #expect(commit.remainingThoughts == 0)
        #expect(commit.isThinking == false)
        #expect(await brain.value["adult"] == 1)
        await brain.cancelStreams()
    }

    @Test func propagatesThroughDependentConceptsAcrossWaves() async throws {
        let graph = arithmeticGraph(
            [
                "a + b + c": .sum("a", "b", "c"),
                "x * (a + b + c)": .product("x", "a + b + c"),
            ],
            change: [
                "a": 1,
                "b": 2,
                "c": 3,
                "x": 10,
            ],
            remainingThoughts: { state in
                state["x * (a + b + c)"] == 60 ? 0 : 1
            }
        )

        let commit = try await graph.commit(thoughts: 2)

        #expect(commit.state["a + b + c"] == 6)
        #expect(commit.state["x * (a + b + c)"] == 60)
        #expect(commit.thoughts == [
            "a + b + c": 6,
            "x * (a + b + c)": 60,
        ])
        #expect(commit.remainingThoughts == 0)
        await graph.cancelStreams()
    }

    @Test func selfDependentConceptAdvancesOneWaveAtATime() async throws {
        let graph = arithmeticGraph(
            [
                "x": .sum("x", "increment"),
            ],
            change: [
                "increment": 1,
                "x": 0,
            ],
            remainingThoughts: { _ in 1 }
        )

        var commit = try await graph.commit()
        #expect(commit.state["x"] == 1)

        commit = try await graph.commit()
        #expect(commit.state["x"] == 2)

        commit = try await graph.commit()
        #expect(commit.state["x"] == 3)

        commit = try await graph.commit(thoughts: 100)
        #expect(commit.state["x"] == 103)
        #expect(commit.remainingThoughts == 1)
        await graph.cancelStreams()
    }

    @Test func blankBrainCommitsStagedValuesWithoutConcepts() async throws {
        let brain = Brain<String, Int>(
            [],
            remainingThoughts: { _ in 0 }
        )

        await brain.stage(["?": 42])
        let commit = try await brain.commit { _, _ in nil }

        #expect(commit.change == ["?": 42])
        #expect(commit.thoughts == [:])
        #expect(commit.state == ["?": 42])
        #expect(commit.remainingThoughts == 0)
        await brain.cancelStreams()
    }

    @Test func gameOfLifeBlinkerOscillatesOneGenerationPerCommit() async throws {
        let cells = Cell.board(width: 5, height: 5)
        let vertical: Set<Cell> = [
            Cell(2, 1),
            Cell(2, 2),
            Cell(2, 3),
        ]
        let horizontal: Set<Cell> = [
            Cell(1, 2),
            Cell(2, 2),
            Cell(3, 2),
        ]
        let brain = Brain<Cell, Bool>(
            cells.map { cell in
                Brain<Cell, Bool>.Concept(cell, inputs: Set([cell] + cell.neighbors(in: cells)))
            },
            state: Dictionary(uniqueKeysWithValues: cells.map { ($0, false) }),
            change: Dictionary(uniqueKeysWithValues: vertical.map { ($0, true) }),
            remainingThoughts: { _ in 1 }
        )

        var commit = try await brain.commit { cell, state in
            cell.nextGenerationValue(in: state, board: cells)
        }
        #expect(livingCells(in: commit.state) == horizontal)

        commit = try await brain.commit { cell, state in
            cell.nextGenerationValue(in: state, board: cells)
        }
        #expect(livingCells(in: commit.state) == vertical)

        commit = try await brain.commit { cell, state in
            cell.nextGenerationValue(in: state, board: cells)
        }
        #expect(livingCells(in: commit.state) == horizontal)
        await brain.cancelStreams()
    }
}

private struct ArithmeticGraph: Sendable {
    let brain: Brain<String, Int>
    let rules: [String: ArithmeticRule]

    func commit(thoughts count: Int = 1) async throws -> BrainCommit<String, Int> {
        try await brain.commit(thoughts: count) { lemma, state in
            rules[lemma]?.value(in: state)
        }
    }

    func cancelStreams() async {
        await brain.cancelStreams()
    }
}

private struct ArithmeticRule: Sendable {
    let inputs: [String]
    let operation: @Sendable ([Int]) -> Int

    static func sum(_ inputs: String...) -> Self {
        Self(inputs: inputs) { values in
            values.reduce(0, +)
        }
    }

    static func product(_ inputs: String...) -> Self {
        Self(inputs: inputs) { values in
            values.reduce(1, *)
        }
    }

    func value(in state: [String: Int]) -> Int? {
        var values: [Int] = []
        for input in inputs {
            guard let value = state[input] else { return nil }
            values.append(value)
        }
        return operation(values)
    }
}

private func arithmeticGraph(
    _ rules: [String: ArithmeticRule],
    change: [String: Int] = [:],
    remainingThoughts: @escaping Brain<String, Int>.ThoughtCounter = { _ in 0 }
) -> ArithmeticGraph {
    let concepts = rules.keys.sorted().map { name in
        Brain<String, Int>.Concept(name, inputs: Set(rules[name]?.inputs ?? []))
    }
    return ArithmeticGraph(
        brain: Brain<String, Int>(
            concepts,
            change: change,
            remainingThoughts: remainingThoughts
        ),
        rules: rules
    )
}

private struct Cell: Hashable, Sendable {
    let x: Int
    let y: Int

    init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    static func board(width: Int, height: Int) -> Set<Cell> {
        Set(product(0..<width, 0..<height).map { x, y in
            Cell(x, y)
        })
    }

    func neighbors(in board: Set<Cell>) -> [Cell] {
        product(-1...1, -1...1).compactMap { dx, dy in
            guard (dx, dy) != (0, 0) else { return nil }
            let candidate = Cell(x + dx, y + dy)
            return board.contains(candidate) ? candidate : nil
        }
    }

    func nextGenerationValue(in state: [Cell: Bool], board: Set<Cell>) -> Bool {
        let liveNeighbors = neighbors(in: board).count { state[$0] == true }
        if state[self] == true {
            return liveNeighbors == 2 || liveNeighbors == 3
        }
        return liveNeighbors == 3
    }
}

private func livingCells(in state: [Cell: Bool]) -> Set<Cell> {
    Set(state.compactMap { cell, isAlive in isAlive ? cell : nil })
}
