//  WTrendView.swift
//  Nathan's build: the WHOOP-style "Trend View". Metric picker, the period average with a change pill
//  against the period before, W / M / 6M, a date range you can step back through, one plain sentence
//  about the period, the chart (drag to read a day), a day-count breakdown where WHOOP shows one, and a
//  short explainer card.

import SwiftUI

struct WTrendView: View {
    @EnvironmentObject var data: WhoopData
    @State var metric: WMetric
    @State var period: WPeriod
    @State private var back = 0      // how many periods before the current one

    init(metric: WMetric, period: WPeriod = .month) {
        _metric = State(initialValue: metric)
        _period = State(initialValue: period)
    }

    private var end: Date {
        Calendar.current.date(byAdding: .day, value: -back * period.days, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }
    private var start: Date { Calendar.current.date(byAdding: .day, value: -(period.days - 1), to: end) ?? end }
    private var priorEnd: Date { Calendar.current.date(byAdding: .day, value: -period.days, to: end) ?? end }

    private var avg: Double? { data.mean(metric, end: end, days: period.days) }
    private var priorAvg: Double? { data.mean(metric, end: priorEnd, days: period.days) }

    /// Metrics offered in the picker: the same family as the one opened.
    private var family: [WMetric] {
        let g = metric.group
        return WMetric.allCases.filter { $0.group == g || (g == .health && $0.group == .recovery) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                selector
                HStack(alignment: .top, spacing: 12) {
                    averageBlock.layoutPriority(1)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 14) {
                        WSegmented(options: WPeriod.allCases.map { ($0, $0.label) }, selection: $period)
                            .frame(width: 196)
                        rangeNav
                    }
                }
                Text(insight).font(W.body(18)).foregroundStyle(W.text).fixedSize(horizontal: false, vertical: true)
                legend
                WTrendChart(metric: metric, period: period, end: end, height: 330)
                    .id("\(metric.rawValue)-\(period.rawValue)-\(back)")
                    .transition(.opacity)
                breakdown
                about
            }
            .padding(.horizontal, W.margin)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .wPage(title: "Trend View")
        .onChange(of: period) { _, _ in back = 0 }
        .animation(.easeInOut(duration: 0.25), value: period)
        .animation(.easeInOut(duration: 0.25), value: back)
    }

    // MARK: Pieces

    private var selector: some View {
        Menu {
            ForEach(family) { m in
                Button { WHaptics.select(); metric = m } label: { Label(m.title, systemImage: m.icon) }
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: metric.icon).font(.system(size: 22, weight: .light)).foregroundStyle(W.text3)
                    .frame(width: 30)
                Text(metric.title.uppercased()).font(W.caps(16)).tracking(1.6).foregroundStyle(W.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 17, weight: .bold)).foregroundStyle(W.text)
            }
            .padding(.horizontal, 22)
            .frame(height: 76)
            .background(W.selector, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    @ViewBuilder private var averageBlock: some View {
        if metric == .hoursVsNeeded {
            let needAvg = needMean(end: end), needPrior = needMean(end: priorEnd)
            VStack(alignment: .leading, spacing: 14) {
                twoLineAvg(value: needAvg, prior: needPrior, color: W.mint, label: "AVG. NEED")
                twoLineAvg(value: avg, prior: priorAvg, color: W.hours, label: "AVG. HOURS")
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("AVERAGE").font(W.caps(14, .semibold)).tracking(1.4).foregroundStyle(W.text2)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(avg.map(display) ?? "---").font(W.num(46)).foregroundStyle(W.text)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(metric.unit).font(W.body(metric.unit.count > 3 ? 17 : 22, .medium)).foregroundStyle(W.text)
                        .lineLimit(1).fixedSize()
                }
                pill(current: avg, prior: priorAvg)
            }
        }
    }

    private func twoLineAvg(value: Double?, prior: Double?, color: Color, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value.map { WFmt.hm($0) } ?? "---").font(W.num(36)).foregroundStyle(color)
                Text("hr").font(W.body(20, .medium)).foregroundStyle(color)
                if let value, let prior, prior > 0 {
                    let pct = (value - prior) / prior * 100
                    WDeltaPill(text: "\(Int(abs(pct).rounded()))%", up: pct >= 0, good: label == "AVG. NEED" ? (pct <= 0) : (pct >= 0))
                }
            }
            Text(label).font(W.caps(13, .semibold)).tracking(1.4).foregroundStyle(W.text2)
        }
    }

    private func needMean(end: Date) -> Double? {
        let cal = Calendar.current
        let xs: [Double] = (0..<period.days).compactMap { back in
            cal.date(byAdding: .day, value: -back, to: end).flatMap { data.need[Repository.localDayKey($0)] }
        }
        return xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    private func display(_ v: Double) -> String {
        metric.isDuration ? WFmt.hm(v) : metric.format(v)
    }

    @ViewBuilder private func pill(current: Double?, prior: Double?) -> some View {
        if let current, let prior, prior != 0 {
            let pct = (current - prior) / abs(prior) * 100
            let r = Int(abs(pct).rounded())
            let good: Bool? = r == 0 || metric.better == .neither ? nil : (metric.better == .up ? pct > 0 : pct < 0)
            WDeltaPill(text: "\(r)% vs. \(period.priorNoun)", up: r == 0 ? nil : pct > 0, good: good)
        }
    }

    private var rangeNav: some View {
        HStack(spacing: 14) {
            Button { WHaptics.select(); back += 1 } label: {
                Image(systemName: "chevron.left").font(.system(size: 19, weight: .bold)).foregroundStyle(W.text)
            }
            Text(rangeText).font(W.caps(13)).tracking(0.8).foregroundStyle(W.text).lineLimit(1).minimumScaleFactor(0.6)
            Button { WHaptics.select(); back = max(0, back - 1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 19, weight: .bold))
                    .foregroundStyle(back == 0 ? W.text3.opacity(0.6) : W.text)
            }
            .disabled(back == 0)
        }
        .buttonStyle(.plain)
    }

    private var rangeText: String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        let y = DateFormatter(); y.dateFormat = ", yy"
        return (f.string(from: start) + " - " + f.string(from: end) + y.string(from: end)).uppercased()
    }

    private var insight: String {
        let name = metric == .hrv ? "HRV" : metric == .rhr ? "resting heart rate" : metric.title.lowercased()
            .replacingOccurrences(of: " (hours)", with: "").replacingOccurrences(of: " (%)", with: "")
        guard let avg else {
            return metric.blurb
        }
        let a = display(avg) + (metric.unit == "%" ? "%" : "")
        guard let prior = priorAvg else {
            return "Your average \(name) this \(period.noun) was \(a). " + metric.blurb
        }
        let p = display(prior) + (metric.unit == "%" ? "%" : "")
        if abs(avg - prior) < max(abs(prior) * 0.01, 0.0001) {
            return "Your \(name) this \(period.noun) (\(a)) was in line with your previous \(period.days)-day average."
        }
        let dir = avg > prior ? "above" : "below"
        return "Your average \(name) this \(period.noun) (\(a)) was \(dir) your previous \(period.days)-day average of \(p)."
    }

    @ViewBuilder private var legend: some View {
        switch metric.chart {
        case .dualNeed:
            HStack(spacing: 18) { Spacer(); WLegend(color: W.hours, label: "Hours of sleep", ring: true); WLegend(color: W.mint, label: "Sleep needed", ring: true) }
        case .restorative:
            HStack(spacing: 18) { Spacer(); WLegend(color: W.deep, label: "SWS (Deep)"); WLegend(color: W.rem, label: "REM") }
        case .line:
            HStack { Spacer(); WLegend(color: W.hex(0x313A41), label: "Typical range") }
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var breakdown: some View {
        let xs = data.window(metric, end: end, days: period.days).compactMap(\.value)
        if !xs.isEmpty {
            switch metric {
            case .sleepPerformance:
                WBreakdown(title: "Sleep breakdown", buckets: [
                    ("Optimal (>85%)", xs.filter { $0 > 85 }.count, W.mint),
                    ("Sufficient (70-85%)", xs.filter { $0 >= 70 && $0 <= 85 }.count, W.breakdownGray),
                    ("Poor (<70%)", xs.filter { $0 < 70 }.count, W.orange)])
            case .sleepConsistency:
                WBreakdown(title: "Sleep consistency breakdown", buckets: [
                    ("Optimal (80%+)", xs.filter { $0 >= 80 }.count, W.mint),
                    ("Sufficient (70-79%)", xs.filter { $0 >= 70 && $0 < 80 }.count, W.breakdownGray),
                    ("Poor (<70%)", xs.filter { $0 < 70 }.count, W.orange)])
            case .recovery:
                WBreakdown(title: "Recovery breakdown", buckets: [
                    ("Green (67-100%)", xs.filter { $0 >= 67 }.count, W.green),
                    ("Yellow (34-66%)", xs.filter { $0 >= 34 && $0 < 67 }.count, W.yellow),
                    ("Red (0-33%)", xs.filter { $0 < 34 }.count, W.red)])
            default:
                EmptyView()
            }
        }
    }

    private var about: some View {
        WCard(padding: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("What is \(metric.title.replacingOccurrences(of: " (Hours)", with: "").replacingOccurrences(of: " (%)", with: ""))?")
                    .font(W.body(22, .semibold)).foregroundStyle(W.text)
                Text(metric.blurb).font(W.body(17)).foregroundStyle(W.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
