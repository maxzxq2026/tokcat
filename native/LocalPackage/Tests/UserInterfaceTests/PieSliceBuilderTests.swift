import DataSource
import Testing

@testable import UserInterface

// The pie legend grows a row per model and stretches the usage card, so
// PieSliceBuilder folds a single-agent tail beyond 8 models into one gray
// "其他" slice. These tests pin the fold and the overview branch's ordering.
@Suite struct PieSliceBuilderTests {
    private func contribution(
        _ date: String, _ clients: [(String, String, Int64)]
    ) -> Contribution {
        Contribution(
            date: date,
            totals: ContributionTotals(
                tokens: clients.reduce(Int64(0)) { $0 + $1.2 },
                cost: 0, messages: 0),
            intensity: 0,
            tokenBreakdown: TokenBreakdown(),
            clients: clients.map { client, modelId, tokens in
                ContributionClient(
                    client: client, modelId: modelId, providerId: "p",
                    tokens: TokenBreakdown(input: tokens), cost: 0, messages: 0)
            })
    }

    private func payload(_ contributions: [Contribution]) -> UsagePayload {
        UsagePayload(
            meta: UsageMeta(
                generatedAt: "2026-11-22T00:00:00Z", version: "test",
                dateRange: DateRange(start: "2026-11-01", end: "2026-11-22")),
            summary: UsageSummary(
                totalTokens: 0, totalCost: 0, totalDays: 0, activeDays: 0,
                averagePerDay: 0, maxCostInSingleDay: 0, clients: [], models: []),
            years: [],
            contributions: contributions)
    }

    @Test func atMostEightModelsStayUnfolded() {
        let models = (0..<8).map { ("claude", "m\($0)", Int64(100 - $0)) }
        let slices = PieSliceBuilder.slices(
            clientIds: ["claude"],
            payload: payload([contribution("2026-11-01", models)]),
            month: 11)
        #expect(slices.count == 8)
        #expect(!slices.contains { $0.label == "其他" })
        #expect(slices[0].label == "m0")
        #expect(slices[0].value == 100)
    }

    @Test func nineModelsFoldTheTailIntoOther() {
        // m0..m8 with 100..92 tokens: the top 7 stay, m7+m8 (93+92=185)
        // fold into "其他".
        let models = (0..<9).map { ("claude", "m\($0)", Int64(100 - $0)) }
        let slices = PieSliceBuilder.slices(
            clientIds: ["claude"],
            payload: payload([contribution("2026-11-01", models)]),
            month: 11)
        #expect(slices.count == 8)
        #expect(slices.prefix(7).map(\.label) == (0..<7).map { "m\($0)" })
        let other = slices[7]
        #expect(other.label == "其他")
        #expect(other.value == 185)
    }

    @Test func unknownModelKeepsItsLabel() {
        let slices = PieSliceBuilder.slices(
            clientIds: ["claude"],
            payload: payload([contribution("2026-11-01", [("claude", "", 50)])]),
            month: 11)
        #expect(slices.count == 1)
        #expect(slices[0].label == "未知模型")
    }

    @Test func overviewSlicesArePerAgentSortedByValue() {
        let slices = PieSliceBuilder.slices(
            clientIds: ["claude", "codex"],
            payload: payload([
                contribution("2026-11-01", [
                    ("claude", "m", 300),
                    ("codex", "m", 100),
                ]),
            ]),
            month: 11)
        #expect(slices.map(\.label) == ["Claude Code", "Codex CLI"])
        #expect(slices[0].value == 300)
        #expect(slices[1].value == 100)
    }
}
