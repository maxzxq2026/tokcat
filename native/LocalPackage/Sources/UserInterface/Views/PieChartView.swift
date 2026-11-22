import DataSource
import Model
import SwiftUI

// Port of PieChart.tsx + the pieSegments builder in UsageBarGraph2D.tsx:
// the model-share pie inside the usage card. Wedges are drawn as short line
// segments rather than Path.addArc so the sweep direction cannot disagree
// with the trig that places the endpoints (SwiftUI's flipped coordinate
// system makes arc angles easy to get backwards).

/// One wedge of the pie: a label, a token count, and the color both the
/// wedge and its legend row use.
struct PieSlice: Identifiable, Equatable {
    let id: String
    let label: String
    let value: Int64
    let color: Color
}

/// Port of the COLOR_PALETTE + MODEL_FIXED_COLORS tables in the React pie
/// and ModelBarChart: brand colors for the models this fork routes through
/// (mimo, deepseek, qwen, …), falling back to a rotating accent palette.
/// Keyword matching tries the longest key first, so "claude-sonnet-4"
/// matches "sonnet" and "qwen-2.5" beats "qwen".
enum ModelChartPalette {
    static let palette: [Color] = [
        Color(hex: "#8b5cf6"),  // 紫
        Color(hex: "#10b981"),  // 绿
        Color(hex: "#3b82f6"),  // 蓝
        Color(hex: "#f59e0b"),  // 黄
        Color(hex: "#ef4444"),  // 红
        Color(hex: "#ec4899"),  // 粉
        Color(hex: "#06b6d4"),  // 青
        Color(hex: "#f97316"),  // 橙
        Color(hex: "#84cc16"),  // 青绿
        Color(hex: "#a855f7"),  // 亮紫
    ]

    private static let fixedColors: [String: Color] = [
        "deepseek": Color(hex: "#0066ff"),
        "mimo": Color(hex: "#ff6b35"),
        "qwen": Color(hex: "#7c3aed"),
        "claude": Color(hex: "#8b5cf6"),
        "sonnet": Color(hex: "#8b5cf6"),
        "opus": Color(hex: "#7c3aed"),
        "haiku": Color(hex: "#a78bfa"),
        "gpt": Color(hex: "#10b981"),
        "gpt-4o": Color(hex: "#059669"),
        "o3": Color(hex: "#059669"),
        "o4": Color(hex: "#047857"),
        "gemini": Color(hex: "#3b82f6"),
        "hermes": Color(hex: "#fbbf24"),
        "llama": Color(hex: "#ef4444"),
    ]

    /// The brand color whose key appears in the model id (longest key wins),
    /// or nil when the model should take a palette color instead.
    static func fixedColor(for model: String) -> Color? {
        let lower = model.lowercased()
        let key = fixedColors.keys
            .filter { lower.contains($0) }
            .max { $0.count < $1.count }
        return key.map { fixedColors[$0]! }
    }

    /// Assigns colors to a list of models: brand color where one matches,
    /// palette rotation otherwise.
    static func colors(for models: [String]) -> [Color] {
        var paletteIndex = 0
        return models.map { model in
            if let fixed = fixedColor(for: model) { return fixed }
            let color = palette[paletteIndex % palette.count]
            paletteIndex += 1
            return color
        }
    }
}

enum PieSliceBuilder {
    /// Slices for the usage card's pie (UsageBarGraph2D.tsx pieSegments):
    /// a single-agent card shows that agent's model share, the overview
    /// shows the per-agent share. Month 0 = the whole year.
    static func slices(clientIds: [String], payload: UsagePayload,
                       month: Int) -> [PieSlice] {
        if clientIds.count == 1 {
            let models = StatsBuilder.aggregateByModel(
                payload.contributions, clients: Set(clientIds), month: month)
            // More than 8 legend rows stretch the card absurdly long: keep
            // the top 7 and fold the tail into one "其他" slice.
            var shown = models
            var tailTokens: Int64 = 0
            if models.count > 8 {
                tailTokens = models.dropFirst(7).reduce(Int64(0)) { $0 + $1.tokens }
                shown = Array(models.prefix(7))
            }
            var labels = shown.map { $0.model == "unknown" ? "未知模型" : $0.model }
            var colors = ModelChartPalette.colors(for: shown.map(\.model))
            if tailTokens > 0 {
                shown.append(ModelAggregate(
                    model: "其他", tokens: tailTokens, messages: 0,
                    breakdown: TokenBreakdown()))
                labels.append("其他")
                colors.append(Color(hex: "#6b7280"))
            }
            return zip(shown, zip(labels, colors)).map { model, labelAndColor in
                PieSlice(id: model.model, label: labelAndColor.0,
                         value: model.tokens, color: labelAndColor.1)
            }
        }

        var totals: [String: Int64] = [:]
        for contribution in payload.contributions {
            if month > 0,
               StatsBuilder.monthValue(of: contribution.date) != month {
                continue
            }
            for cc in contribution.clients where clientIds.contains(cc.client) {
                totals[cc.client, default: 0] += cc.tokens.total
            }
        }
        return totals
            .sorted { $0.value > $1.value }
            .map { clientId, value in
                let style = ClientRegistry.style(for: clientId)
                return PieSlice(id: clientId, label: style.displayName,
                                value: value, color: style.color)
            }
    }
}

/// Port of PieChart.tsx: wedge pie (SVG arcs in React) with the legend
/// stacked under it. Zero-total input renders nothing, like the React
/// `if (total === 0) return null`.
struct PieChartView: View {
    let slices: [PieSlice]
    var size: CGFloat = 200

    var body: some View {
        let total = slices.reduce(Int64(0)) { $0 + $1.value }
        if total > 0 {
            VStack(spacing: 10) {
                Canvas { context, canvasSize in
                    drawWedges(into: &context, canvasSize: canvasSize, total: total)
                }
                .frame(width: size, height: size)
                legend(total: total)
            }
        }
    }

    private func drawWedges(into context: inout GraphicsContext,
                            canvasSize: CGSize, total: Int64) {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let radius = min(canvasSize.width, canvasSize.height) / 2 - 10
        // One polyline segment per 5.625° of arc: smooth enough at 180-200pt
        // to be indistinguishable from a true arc.
        let maxSteps = 64

        var startAngle = -Double.pi / 2  // 12 o'clock, sweeping clockwise
        for slice in slices {
            let fraction = Double(slice.value) / Double(total)
            let endAngle = startAngle + fraction * 2 * .pi
            let steps = max(2, Int(Double(maxSteps) * fraction))

            var path = Path()
            path.move(to: center)
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let angle = CGFloat(startAngle + (endAngle - startAngle) * t)
                path.addLine(to: CGPoint(
                    x: center.x + radius * Foundation.cos(angle),
                    y: center.y + radius * Foundation.sin(angle)))
            }
            path.closeSubpath()
            context.fill(path, with: .color(slice.color))
            context.stroke(path, with: .color(.white), lineWidth: 2)
            startAngle = endAngle
        }
    }

    private func legend(total: Int64) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(slices) { slice in
                HStack(spacing: 6) {
                    Circle()
                        .fill(slice.color)
                        .frame(width: 8, height: 8)
                    Text(slice.label)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(String(format: "%.1f%%",
                                Double(slice.value) / Double(total) * 100))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                // Column width tracks the card, not the pie: a fixed
                // pie-relative width clipped long model ids at both ends.
                .frame(maxWidth: 360, alignment: .leading)
                .help("\(slice.label): \(Formatters.humanizeTokens(slice.value))")
            }
        }
        .frame(maxWidth: .infinity)
    }
}
