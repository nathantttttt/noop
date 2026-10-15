//  WCharts.swift
//  Nathan's build: the WHOOP-style trend charts. One view draws every shape the Trend View needs:
//  value-labelled bars (week), bars with a dashed AVG line (month), monthly-average steps over a faint
//  daily line (6 months), a blue line over a hazed typical range (HRV / RHR / breathing), the
//  hours-vs-need pair and stacked deep + REM. Drag a finger across any of them to read a day; each new
//  day under the finger gives a selection tick.

import SwiftUI
import Charts

struct WPoint: Identifiable {
    let id: String          // day key
    let date: Date
    let value: Double?      // plotted units (hours for durations)
    var value2: Double? = nil
}

private struct WSeg: Identifiable {
    let id: Int
    let start: Date
    let end: Date
    let avg: Double
    let delta: Double?
    let color: Color
}

struct WTrendChart: View {
    @EnvironmentObject var data: WhoopData
    let metric: WMetric
    let period: WPeriod
    var end: Date = Date()
    var height: CGFloat = 300

    @State private var selected: Date?
    @State private var lastKey: String?

    // MARK: Data

    private func plot(_ v: Double) -> Double { metric.isDuration ? v / 60 : v }

    private var points: [WPoint] {
        let w = data.window(metric, end: end, days: period.days)
        switch metric {
        case .hoursVsNeeded:
            return w.map { WPoint(id: $0.day, date: $0.date, value: $0.value.map { $0 / 60 },
                                  value2: data.need[$0.day].map { $0 / 60 }) }
        case .restorative:
            return w.map { WPoint(id: $0.day, date: $0.date, value: data.deep[$0.day].map { $0 / 60 },
                                  value2: data.rem[$0.day].map { $0 / 60 }) }
        default:
            return w.map { WPoint(id: $0.day, date: $0.date, value: $0.value.map(plot)) }
        }
    }

    private var isPercent: Bool {
        [.sleepPerformance, .hoursVsNeededPct, .sleepConsistency, .sleepEfficiency, .recovery].contains(metric)
    }

    private func yDomain(_ pts: [WPoint]) -> ClosedRange<Double> {
        if isPercent { return 0...100 }
        let vals = pts.compactMap(\.value) + pts.compactMap(\.value2)
        let stacked = metric == .restorative ? pts.map { ($0.value ?? 0) + ($0.value2 ?? 0) } : []
        guard let lo = vals.min(), let hi = (vals + stacked).max() else { return 0...1 }
        if metric.chart == .line {
            let pad = max((hi - lo) * 0.35, metric == .respRate ? 0.5 : 2)
            return (lo - pad)...(hi + pad)
        }
        return 0...max(hi * 1.18, 1)
    }

    /// Middle half of the 60 days before this window: the hazed "typical range".
    private var typical: ClosedRange<Double>? {
        guard metric.chart == .line,
              let before = Calendar.current.date(byAdding: .day, value: -period.days, to: end) else { return nil }
        let xs = data.window(metric, end: before, days: 60).compactMap(\.value).sorted()
        guard xs.count >= 8 else { return nil }
        return xs[Int(Double(xs.count - 1) * 0.25)]...xs[Int(Double(xs.count - 1) * 0.75)]
    }

    private func average(_ pts: [WPoint], second: Bool = false) -> Double? {
        let xs = pts.compactMap { second ? $0.value2 : $0.value }
        return xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    private func barColor(_ v: Double) -> Color {
        metric == .recovery ? W.recoveryColor(v) : metric.barColor
    }

    private func label(_ plotted: Double) -> String {
        metric.isDuration ? WFmt.hm(plotted * 60) : metric.format(plotted)
    }

    private var monthly: [WSeg] {
        let cal = Calendar.current
        let pts = points.filter { $0.value != nil }
        let groups = Dictionary(grouping: pts) { cal.dateComponents([.year, .month], from: $0.date) }
        let sorted = groups.keys.sorted { ($0.year ?? 0, $0.month ?? 0) < ($1.year ?? 0, $1.month ?? 0) }
        var out: [WSeg] = []
        var prev: Double?
        for (i, k) in sorted.enumerated() {
            let g = groups[k] ?? []
            guard let s = g.map(\.date).min(), let e = g.map(\.date).max() else { continue }
            let avg = g.compactMap(\.value).reduce(0, +) / Double(g.count)
            var delta: Double?
            var color = W.text
            if let p = prev, p != 0 {
                delta = (avg - p) / abs(p) * 100
                let improved: Bool? = metric.better == .neither ? nil : (metric.better == .up ? avg >= p : avg <= p)
                color = improved == nil ? W.text : (improved! ? W.mint : W.orange)
            }
            out.append(WSeg(id: i, start: s, end: e.addingTimeInterval(86_400 * 0.9), avg: avg, delta: delta, color: color))
            prev = avg
        }
        return out
    }

    // MARK: View

    var body: some View {
        let pts = points
        if pts.allSatisfy({ $0.value == nil && $0.value2 == nil }) {
            WNoData(height: height)
        } else {
            chart(pts)
                .frame(height: height)
                .onChange(of: selected) { _, new in
                    guard let new else { lastKey = nil; return }
                    let k = Repository.localDayKey(new)
                    if k != lastKey { lastKey = k; WHaptics.tick() }
                }
        }
    }

    private func selectedPoint(_ pts: [WPoint]) -> WPoint? {
        guard let selected else { return nil }
        let k = Repository.localDayKey(selected)
        return pts.first { $0.id == k }
    }

    private func chart(_ pts: [WPoint]) -> some View {
        Chart {
            if metric.chart == .line {
                lineMarks(pts)
            } else if metric.chart == .dualNeed {
                dualMarks(pts)
            } else if metric.chart == .restorative {
                restorativeMarks(pts)
            } else if period == .sixMonths {
                sixMonthMarks(pts)
            } else {
                barMarks(pts)
            }
            selectionMarks(pts)
        }
        .chartYScale(domain: yDomain(pts))
        .chartXScale(domain: (pts.first?.date ?? Date())...(pts.last?.date.addingTimeInterval(86_400) ?? Date()))
        .chartXSelection(value: $selected)
        .chartLegend(.hidden)
        .chartForegroundStyleScale(domain: ["Deep", "REM"], range: [W.deep, W.rem])
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(W.grid)
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text(isPercent ? "\(Int(d))%" : (abs(d) >= 1000 ? WFmt.grouped(d) : (d == d.rounded() ? "\(Int(d))" : WFmt.one(d))))
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(W.text3)
            }
        }
        .chartXAxis { xAxis }
    }

    private var xValues: AxisMarkValues {
        switch period {
        case .week: return .stride(by: .day)
        case .month: return .stride(by: .day, count: 7)
        case .sixMonths: return .stride(by: .month)
        }
    }

    private var xAxis: some AxisContent {
        AxisMarks(values: xValues) { v in
            AxisValueLabel(centered: true) {
                if let d = v.as(Date.self) {
                    if period == .sixMonths {
                        Text(d, format: .dateTime.month(.abbreviated))
                    } else {
                        VStack(spacing: 2) {
                            if period == .week {
                                Text(d, format: .dateTime.weekday(.abbreviated))
                            } else {
                                Text(d, format: .dateTime.month(.abbreviated))
                            }
                            Text(d, format: .dateTime.day()).foregroundStyle(W.text3)
                        }
                    }
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(W.text2)
        }
    }

    // MARK: Marks

    @ChartContentBuilder private func barMarks(_ pts: [WPoint]) -> some ChartContent {
        ForEach(pts.filter { $0.value != nil }) { p in
            BarMark(x: .value("Day", p.date, unit: .day), y: .value("Value", p.value ?? 0),
                    width: .ratio(period == .week ? 0.42 : 0.72))
                .foregroundStyle(barColor(p.value ?? 0))
                .annotation(position: .top, spacing: 5) {
                    if period == .week {
                        Text(label(p.value ?? 0)).font(W.num(16)).foregroundStyle(barColor(p.value ?? 0))
                    }
                }
        }
        if period == .month, let avg = average(pts) {
            avgRule(avg, color: .white, label: "AVG.")
        }
    }

    @ChartContentBuilder private func avgRule(_ y: Double, color: Color, label: String) -> some ChartContent {
        RuleMark(y: .value("Average", y))
            .foregroundStyle(color.opacity(0.85))
            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            .annotation(position: .overlay, alignment: .leading, spacing: 0) {
                Text(label).font(W.caps(12, .heavy)).tracking(0.8).foregroundStyle(.black)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(color, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .offset(x: -6)
            }
    }

    @ChartContentBuilder private func sixMonthMarks(_ pts: [WPoint]) -> some ChartContent {
        ForEach(pts.filter { $0.value != nil }) { p in
            LineMark(x: .value("Day", p.date, unit: .day), y: .value("Value", p.value ?? 0))
                .foregroundStyle(Color.white.opacity(0.16))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        ForEach(monthly) { m in
            RuleMark(xStart: .value("Start", m.start), xEnd: .value("End", m.end), y: .value("Avg", m.avg))
                .foregroundStyle(m.color)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                .annotation(position: .top, spacing: 4) {
                    Text(label(m.avg) + (isPercent ? "%" : "")).font(W.num(17)).foregroundStyle(W.text)
                }
                .annotation(position: .bottom, spacing: 4) {
                    if let d = m.delta {
                        Text((d >= 0 ? "+" : "") + "\(Int(d.rounded()))%").font(W.num(16)).foregroundStyle(m.color)
                    }
                }
        }
    }

    @ChartContentBuilder private func lineMarks(_ pts: [WPoint]) -> some ChartContent {
        if let band = typical, let first = pts.first, let last = pts.last {
            RectangleMark(xStart: .value("Start", first.date), xEnd: .value("End", last.date.addingTimeInterval(86_400)),
                          yStart: .value("Low", band.lowerBound), yEnd: .value("High", band.upperBound))
                .foregroundStyle(W.hex(0x313A41).opacity(0.9))
        }
        let have = pts.filter { $0.value != nil }
        ForEach(have) { p in
            LineMark(x: .value("Day", p.date, unit: .day), y: .value("Value", p.value ?? 0))
                .foregroundStyle(W.lineBlue)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        }
        if period == .week {
            ForEach(Array(have.dropLast())) { p in
                PointMark(x: .value("Day", p.date, unit: .day), y: .value("Value", p.value ?? 0))
                    .symbolSize(28).foregroundStyle(W.lineBlue)
                    .annotation(position: .top, spacing: 6) {
                        Text(label(p.value ?? 0)).font(W.num(14)).foregroundStyle(W.lineBlue)
                    }
            }
        }
        if let lastP = have.last {
            PointMark(x: .value("Day", lastP.date, unit: .day), y: .value("Value", lastP.value ?? 0))
                .symbol {
                    Circle().fill(W.bgMid).overlay(Circle().stroke(W.lineBlue, lineWidth: 2.5)).frame(width: 13, height: 13)
                }
                .annotation(position: .top, spacing: 6) {
                    Text(label(lastP.value ?? 0)).font(W.num(16)).foregroundStyle(W.lineBlue)
                        .padding(.horizontal, 4).background(W.bgMid.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
                }
        }
    }

    @ChartContentBuilder private func dualMarks(_ pts: [WPoint]) -> some ChartContent {
        ForEach(pts.filter { $0.value2 != nil }) { p in
            LineMark(x: .value("Day", p.date, unit: .day), y: .value("Need", p.value2 ?? 0), series: .value("Series", "Need"))
                .foregroundStyle(W.mint).lineStyle(StrokeStyle(lineWidth: 2.2, lineJoin: .round))
        }
        ForEach(pts.filter { $0.value != nil }) { p in
            LineMark(x: .value("Day", p.date, unit: .day), y: .value("Hours", p.value ?? 0), series: .value("Series", "Hours"))
                .foregroundStyle(W.hours).lineStyle(StrokeStyle(lineWidth: 2.2, lineJoin: .round))
        }
        if let n = average(pts, second: true) { avgRule(n, color: W.mint, label: "AVG.") }
        if let h = average(pts) { avgRule(h, color: W.hours, label: "AVG.") }
    }

    @ChartContentBuilder private func restorativeMarks(_ pts: [WPoint]) -> some ChartContent {
        ForEach(pts.filter { $0.value != nil || $0.value2 != nil }) { p in
            BarMark(x: .value("Day", p.date, unit: .day), y: .value("Hours", p.value ?? 0),
                    width: .ratio(period == .week ? 0.42 : 0.72))
                .foregroundStyle(by: .value("Stage", "Deep"))
            BarMark(x: .value("Day", p.date, unit: .day), y: .value("Hours", p.value2 ?? 0),
                    width: .ratio(period == .week ? 0.42 : 0.72))
                .foregroundStyle(by: .value("Stage", "REM"))
                .annotation(position: .top, spacing: 5) {
                    if period == .week {
                        Text(WFmt.hm(((p.value ?? 0) + (p.value2 ?? 0)) * 60)).font(W.num(14)).foregroundStyle(W.text2)
                    }
                }
        }
    }

    @ChartContentBuilder private func selectionMarks(_ pts: [WPoint]) -> some ChartContent {
        if let p = selectedPoint(pts) {
            RuleMark(x: .value("Selected", p.date, unit: .day))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    bubble(p)
                }
        }
    }

    private func bubble(_ p: WPoint) -> some View {
        VStack(spacing: 2) {
            Text(p.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased())
                .font(W.caps(11)).tracking(1).foregroundStyle(W.text2)
            switch metric.chart {
            case .dualNeed:
                HStack(spacing: 8) {
                    Text(p.value.map { WFmt.hm($0 * 60) } ?? "--").foregroundStyle(W.hours)
                    Text(p.value2.map { WFmt.hm($0 * 60) } ?? "--").foregroundStyle(W.mint)
                }
                .font(W.num(18))
            case .restorative:
                HStack(spacing: 8) {
                    Text(p.value.map { WFmt.hm($0 * 60) } ?? "--").foregroundStyle(W.deep)
                    Text(p.value2.map { WFmt.hm($0 * 60) } ?? "--").foregroundStyle(W.rem)
                }
                .font(W.num(18))
            default:
                Text(p.value.map { label($0) + (isPercent ? "%" : "") } ?? "--")
                    .font(W.num(20)).foregroundStyle(p.value.map(barColor) ?? W.text)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(W.callout, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(W.hairline, lineWidth: 1))
    }
}

/// The day-count breakdown under Sleep Performance / Consistency / Recovery trends.
struct WBreakdown: View {
    let title: String
    let buckets: [(label: String, count: Int, color: Color)]
    var body: some View {
        let total = max(1, buckets.map(\.count).reduce(0, +))
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(title.uppercased()).font(W.caps(13)).tracking(1.4).foregroundStyle(W.text)
                Text("(DAYS)").font(W.caps(13, .semibold)).tracking(1.2).foregroundStyle(W.text3)
            }
            GeometryReader { g in
                HStack(spacing: 3) {
                    ForEach(buckets.indices, id: \.self) { i in
                        let b = buckets[i]
                        if b.count > 0 {
                            Rectangle().fill(b.color)
                                .frame(width: max(4, (g.size.width - 6) * Double(b.count) / Double(total)))
                        }
                    }
                }
            }
            .frame(height: 16)
            ForEach(buckets.indices, id: \.self) { i in
                let b = buckets[i]
                HStack(spacing: 10) {
                    Rectangle().fill(b.color).frame(width: 10, height: 10)
                    Text("\(b.count)x").font(W.num(18)).foregroundStyle(W.text).frame(minWidth: 34, alignment: .leading)
                    Text(b.label).font(W.body(17)).foregroundStyle(W.text2)
                }
            }
        }
    }
}
