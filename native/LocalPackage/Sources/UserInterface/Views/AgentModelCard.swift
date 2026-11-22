import Model
import SwiftUI

// Port of AgentModelCard.tsx (+ the ModelBarChart it embeds): what model
// each agent actually spent its tokens on. The overview shows one compact
// row per agent; a single-agent tab shows summary stats plus per-model
// bars with the cache-rate split. Scoped by the header's month picker
// (0 = the whole year).

struct AgentModelCard: View {
    let clients: [String]
    var title: String? = nil
    /// Client tab: stack each bar with its cached share and show the
    /// overall cache-rate summary, like the React fork's showCache.
    var showCache = false

    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var liveTrace: LiveTraceStore

    private var monthLabel: String {
        store.selectedMonth == 0 ? "全年" : "\(store.selectedMonth)月"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                CardHeading(text: title ?? heading)
                Spacer()
                Text(monthLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var heading: String {
        clients.count == 1
            ? "\(ClientRegistry.style(for: clients[0]).shortName) 模型用量"
            : "Agent 模型用量"
    }

    @ViewBuilder
    private var content: some View {
        if clients.count == 1 {
            singleAgent(clients[0])
        } else {
            overview
        }
    }

    // MARK: - Single agent

    private func singleAgent(_ clientId: String) -> some View {
        let models = models(for: clientId)
        let totalTokens = models.reduce(Int64(0)) { $0 + $1.tokens }
        let totalMessages = models.reduce(Int64(0)) { $0 + $1.messages }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 20) {
                summaryCell(label: "模型", value: topModel(for: clientId) ?? "—")
                summaryCell(label: "Token",
                            value: Formatters.humanizeTokens(totalTokens))
                summaryCell(label: "调用",
                            value: totalMessages > 0 ? "\(totalMessages) 次" : "—")
            }
            if !models.isEmpty {
                ModelBarChartView(models: models, showCache: showCache)
            }
        }
    }

    private func summaryCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(clients, id: \.self) { clientId in
                let style = ClientRegistry.style(for: clientId)
                let models = models(for: clientId)
                let tokens = models.reduce(Int64(0)) { $0 + $1.tokens }
                let messages = models.reduce(Int64(0)) { $0 + $1.messages }
                HStack(spacing: 8) {
                    Circle()
                        .fill(style.color)
                        .frame(width: 7, height: 7)
                    Text(style.shortName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .frame(width: 64, alignment: .leading)
                    Text(topModel(for: clientId) ?? "—")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Formatters.humanizeTokens(tokens))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                    Text(messages > 0 ? "\(messages)次" : "—")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Data

    private func models(for clientId: String) -> [ModelAggregate] {
        guard let payload = store.payload else { return [] }
        return StatsBuilder.aggregateByModel(
            payload.contributions, clients: [clientId], month: store.selectedMonth)
    }

    /// The agent's currently-live model (its top-token trace row), falling
    /// back to the biggest slice of the month's history. Trace rows carry
    /// tail client ids ("claude-code"); normalize them to the payload's ids
    /// so the match works.
    private func topModel(for clientId: String) -> String? {
        let live = liveTrace.trace
            .filter {
                $0.model != "unknown" && Self.normalizedClient($0.client) == clientId
            }
            .max { $0.tokens < $1.tokens }?
            .model
        return live ?? models(for: clientId).first?.model
    }

    private static func normalizedClient(_ raw: String) -> String {
        if raw == "claude-code" { return "claude" }
        if raw == "codex-cli" { return "codex" }
        return raw
    }
}

// Port of ModelBarChart.tsx: one horizontal bar per model, brand-colored,
// optionally stacked with the model's cached share and summed up in a
// cache-rate footer. Colocated with its only caller, like
// TooltipSegmentRows.
struct ModelBarChartView: View {
    let models: [ModelAggregate]
    var showCache = false

    private var maxTokens: Int64 {
        max(1, models.map(\.tokens).max() ?? 1)
    }

    var body: some View {
        let colors = ModelChartPalette.colors(for: models.map(\.model))
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(models.enumerated()), id: \.element.model) { index, model in
                row(model, color: colors[index])
            }
            if showCache {
                summary
            }
        }
    }

    private func row(_ model: ModelAggregate, color: Color) -> some View {
        let pct = Double(model.tokens) / Double(maxTokens)
        let cacheRate = model.tokens > 0
            ? Double(model.breakdown.cacheRead) / Double(model.tokens)
            : 0
        return HStack(spacing: 8) {
            Text(model.model == "unknown" ? "未知模型" : model.model)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 110, alignment: .leading)
                .help(model.model)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.05))
                    HStack(spacing: 1) {
                        if showCache, cacheRate > 0 {
                            Capsule()
                                .fill(color.opacity(0.3))
                                .frame(width: max(0, geo.size.width * pct * cacheRate))
                        }
                        Capsule()
                            .fill(color)
                            .frame(width: max(
                                2, geo.size.width * pct * (showCache ? 1 - cacheRate : 1)))
                    }
                }
            }
            .frame(height: 10)
            Text(valueText(model, cacheRate: cacheRate))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                // "357.9M · 缓存92% · 3539次" needs ~150pt at this size; the
                // old 92pt cell truncated the cache rate into "缓存 9…".
                .frame(width: 170, alignment: .trailing)
        }
    }

    private func valueText(_ model: ModelAggregate, cacheRate: Double) -> String {
        let tokens = Formatters.humanizeTokens(model.tokens)
        guard showCache else { return tokens }
        var text = "\(tokens) · 缓存\(Int((cacheRate * 100).rounded()))%"
        if model.messages > 0 {
            text += " · \(model.messages)次"
        }
        return text
    }

    private var summary: some View {
        let totalTokens = models.reduce(Int64(0)) { $0 + $1.tokens }
        let totalCache = models.reduce(Int64(0)) { $0 + $1.breakdown.cacheRead }
        let rate = totalTokens > 0 ? Double(totalCache) / Double(totalTokens) : 0
        return Text(
            "整体缓存率 \(Int((rate * 100).rounded()))%"
            + " · 节省 \(Formatters.humanizeTokens(totalCache))")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
    }
}
