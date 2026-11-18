// SPDX-License-Identifier: Apache-2.0
import MartyGraphics

struct MLAgent: Equatable, Sendable {
    enum State: String, CaseIterable, Sendable {
        case plan, toolCall, toolResult, review, act, revise, stop
    }

    struct Edge: Equatable, Sendable {
        let from: State
        let to: State
        var decision: String? {
            guard from == .review else { return nil }
            return to == .act ? "approve" : "reject"
        }
    }

    let states: [State]
    let requiresReview: Bool
    let budget: Int
    let edges: [Edge]
    let minimumSteps: Int

    init(_ input: MLObject) throws {
        guard case .bool(let requiresReview)? = input.values["requiresReview"] else {
            throw input.issue(.review, "requiresReview")
        }
        self.requiresReview = requiresReview
        guard case .array(let raw)? = input.values["states"], raw.count <= State.allCases.count else {
            throw input.issue(.states, "states")
        }
        var present = Set<State>()
        for value in raw {
            guard case .string(let text) = value, let state = State(rawValue: text), present.insert(state).inserted else {
                throw input.issue(.states, "states")
            }
        }
        guard present.contains(.stop) else { throw input.issue(.stop, "states") }
        let hasReview = present.contains(.review)
        guard !requiresReview || hasReview else { throw input.issue(.review, "states") }
        guard present.isSuperset(of: [.plan, .toolCall, .toolResult, .act]),
              hasReview || !present.contains(.revise) else { throw input.issue(.states, "states") }
        states = State.allCases.filter { present.contains($0) }

        var edges = [Edge(from: .plan, to: .toolCall), Edge(from: .toolCall, to: .toolResult)]
        if hasReview {
            edges += [Edge(from: .toolResult, to: .review), Edge(from: .review, to: .act),
                      Edge(from: .review, to: .stop)]
            if present.contains(.revise) {
                edges += [Edge(from: .review, to: .revise), Edge(from: .revise, to: .plan)]
            }
        } else {
            edges.append(Edge(from: .toolResult, to: .act))
        }
        edges.append(Edge(from: .act, to: .stop))
        self.edges = edges

        let budget = try input.integer("stepBudget", in: 1...32, reason: .budget)
        // Walk the approval path, so the budget permits a full successful pass even with a review gate.
        var current: State = .plan
        var steps = 0
        while current != .stop, steps < budget,
              let next = edges.first(where: { $0.from == current && $0.decision != "reject" }) {
            current = next.to
            steps += 1
        }
        guard current == .stop else { throw input.issue(.budget, "stepBudget") }
        self.budget = budget
        minimumSteps = steps
    }

    var facts: [String: MGJSON] {
        [
            "states": .array(states.map { .string($0.rawValue) }),
            "requiresReview": .bool(requiresReview),
            "stepBudget": .number(Double(budget)),
            "minimumApprovalSteps": .number(Double(minimumSteps)),
            "onBudgetExhausted": .string(State.stop.rawValue),
            "edges": .array(edges.map { edge in
                .object(["from": .string(edge.from.rawValue), "to": .string(edge.to.rawValue),
                         "decision": edge.decision.map(MGJSON.string) ?? .null])
            })
        ]
    }
}
