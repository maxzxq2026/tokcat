import DataSource
import Testing
@testable import Model

// Coverage for StatsBuilder.aggregateByModel: the per-model rollup behind
// the model-share pie and the per-agent model card.
@Suite struct ModelAggregateTests {
    private func contribution(
        _ date: String, _ clients: [(String, String, Int64, Int64)]
    ) -> Contribution {
        Contribution(
            date: date,
            totals: ContributionTotals(
                tokens: clients.reduce(0) { $0 + $1.2 },
                cost: 0,
                messages: clients.reduce(0) { $0 + $1.3 }),
            intensity: 0,
            tokenBreakdown: TokenBreakdown(),
            clients: clients.map { client, modelId, tokens, messages in
                ContributionClient(
                    client: client, modelId: modelId, providerId: "test",
                    tokens: TokenBreakdown(input: tokens), cost: 0,
                    messages: messages)
            })
    }

    @Test func rollsUpTokensAndMessagesPerModelSortedDescending() {
        let models = StatsBuilder.aggregateByModel([
            contribution("2026-07-01", [
                ("claude", "claude-sonnet-4", 100, 3),
                ("codex", "gpt-5.3-codex", 500, 5),
            ]),
            contribution("2026-07-02", [
                ("claude", "claude-sonnet-4", 50, 1),
                ("codex", "gpt-5.3-codex", 200, 2),
                ("codex", "mimo-v2.5-pro", 700, 4),
            ]),
        ])
        #expect(models.map(\.model) == ["gpt-5.3-codex", "mimo-v2.5-pro", "claude-sonnet-4"])
        #expect(models[0].tokens == 700)
        #expect(models[0].messages == 7)
        #expect(models[1].tokens == 700)
        #expect(models[1].messages == 4)
        #expect(models[2].tokens == 150)
        #expect(models[2].messages == 4)
        #expect(models[2].breakdown == TokenBreakdown(input: 150))
    }

    @Test func emptyModelIdCountsAsUnknown() {
        let models = StatsBuilder.aggregateByModel([
            contribution("2026-07-01", [("claude", "", 30, 1)]),
        ])
        #expect(models.count == 1)
        #expect(models[0].model == "unknown")
        #expect(models[0].tokens == 30)
    }

    @Test func clientFilterKeepsOnlyRequestedAgents() {
        let models = StatsBuilder.aggregateByModel(
            [
                contribution("2026-07-01", [
                    ("claude", "claude-sonnet-4", 100, 1),
                    ("codex", "gpt-5.3-codex", 500, 2),
                ]),
            ],
            clients: ["codex"])
        #expect(models.map(\.model) == ["gpt-5.3-codex"])
        #expect(models[0].tokens == 500)
    }

    @Test func monthFilterReadsTheUTCDateString() {
        let models = StatsBuilder.aggregateByModel(
            [
                contribution("2026-06-30", [("claude", "june-model", 100, 1)]),
                contribution("2026-07-01", [("claude", "july-model", 200, 1)]),
                contribution("2026-08-31", [("claude", "august-model", 300, 1)]),
            ],
            month: 7)
        #expect(models.map(\.model) == ["july-model"])
        #expect(models[0].tokens == 200)
    }

    @Test func monthZeroMeansAllMonths() {
        let models = StatsBuilder.aggregateByModel(
            [
                contribution("2026-06-30", [("claude", "june-model", 100, 1)]),
                contribution("2026-07-01", [("claude", "july-model", 200, 1)]),
            ],
            month: 0)
        #expect(models.count == 2)
        #expect(models.map(\.model) == ["july-model", "june-model"])
    }
}
