//  WBodyView.swift
//  Nathan's build: the Body tab in the WHOOP style. The four goals (resting HR down, HRV up, body fat
//  down, lean mass up), lean vs. fat mass, the latest InBody scan and progress photos. Every number
//  opens its Trend View, the same page the Home dials lead to.

import SwiftUI
import Charts

struct WBodyView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var data: WhoopData

    enum Range: String, CaseIterable, Hashable {
        case m1 = "1M", m3 = "3M", m6 = "6M"
        var days: Int { self == .m1 ? 30 : self == .m3 ? 91 : 182 }
        var trend: WPeriod { self == .m1 ? .month : .sixMonths }
    }
    @State private var range: Range = .m1
    @State private var showCoach = false

    private struct P: Identifiable { let id: String; let date: Date; let value: Double }

    private func points(_ m: WMetric) -> [P] {
        data.window(m, end: Date(), days: range.days).compactMap { d in d.value.map { P(id: d.day, date: d.date, value: $0) } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: W.rowGap) {
                Text("BODY").font(W.caps(15)).tracking(1.6).foregroundStyle(W.text)
                    .frame(maxWidth: .infinity).padding(.top, 8)
                WSegmented(options: Range.allCases.map { ($0, $0.rawValue) }, selection: $range)
                WSectionTitle(title: "My Goals")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    goal(.rhr)
                    goal(.hrv)
                    goal(.bodyFat)
                    goal(.leanMass)
                }
                leanVsFat
                WSectionTitle(title: "Latest Scan", subtitle: latestScanDay.map { "InBody · " + $0 })
                VStack(spacing: 0) {
                    let rows: [WMetric] = [.weight, .bodyFat, .leanMass, .fatMass, .vo2max]
                    ForEach(Array(rows.enumerated()), id: \.element) { i, m in
                        NavigationLink(value: WRoute.trend(m, range.trend)) { scanRow(m) }.buttonStyle(.plain)
                        if i < rows.count - 1 { Rectangle().fill(W.hairline).frame(height: 1).padding(.leading, 58) }
                    }
                }
                .background(W.row, in: RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous))
                NathanProgressPhotos(bodyFatByDay: data.series[.bodyFat] ?? [:])
                    .padding(.top, 14)
            }
            .padding(.horizontal, W.margin)
            .padding(.bottom, 40)
        }
        .background(WBackground())
        .refreshable { await repo.refresh() }
        .overlay(alignment: .bottomTrailing) { WCoachButton { showCoach = true }.padding(.trailing, 16).padding(.bottom, 10) }
        .sheet(isPresented: $showCoach) { WCoachSheet() }
        .wRoutes()
    }

    private var latestScanDay: String? {
        [WMetric.weight, .bodyFat, .leanMass].compactMap { data.latest($0)?.day }.max()
            .flatMap(WFmt.dayDate)?.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Change across the range: 7-day means at each end for daily vitals, first vs. last scan otherwise.
    private func change(_ m: WMetric, _ pts: [P]) -> (Double, Bool?)? {
        guard pts.count >= 2 else { return nil }
        let daily = m == .rhr || m == .hrv
        let a = daily ? pts.prefix(7).map(\.value).reduce(0, +) / Double(min(7, pts.count)) : pts.first!.value
        let b = daily ? pts.suffix(7).map(\.value).reduce(0, +) / Double(min(7, pts.count)) : pts.last!.value
        let d = b - a
        guard abs(d) > (daily ? 0.5 : 0.05) else { return (d, nil) }
        let good: Bool? = m.better == .neither ? nil : (m.better == .up ? d > 0 : d < 0)
        return (d, good)
    }

    private func goal(_ m: WMetric) -> some View {
        let pts = points(m)
        let ch = change(m, pts)
        let color: Color = ch?.1 == nil ? W.lineBlue : (ch!.1! ? W.mint : W.orange)
        return NavigationLink(value: WRoute.trend(m, range.trend)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: m.icon).font(.system(size: 15, weight: .light)).foregroundStyle(W.text2)
                    Text(m == .leanMass ? "LEAN MASS" : m.title.uppercased()).font(W.caps(12)).tracking(1.1)
                        .foregroundStyle(W.text).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Image(systemName: m.better == .down ? "arrow.down.right" : "arrow.up.right")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(W.text3)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(pts.last.map { m.format($0.value) } ?? "--").font(W.num(32)).foregroundStyle(W.text)
                    if !pts.isEmpty { Text(m.unit).font(W.body(14)).foregroundStyle(W.text3) }
                }
                if pts.count >= 2 {
                    Chart(pts) { p in
                        LineMark(x: .value("Day", p.date), y: .value("V", p.value))
                            .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.monotone)
                    }
                    .chartXAxis(.hidden).chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 34)
                } else {
                    Text(pts.isEmpty ? "No data yet" : "One reading so far").font(W.body(13)).foregroundStyle(W.text3)
                        .frame(height: 34, alignment: .leading)
                }
                if let ch {
                    HStack(spacing: 4) {
                        Image(systemName: ch.0 >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 8))
                        Text("\(m.format(abs(ch.0)))\(m.unit == "%" ? " pts" : " " + m.unit) · \(range.rawValue)")
                            .font(W.body(13, .semibold))
                    }
                    .foregroundStyle(ch.1 == nil ? W.text2 : color)
                } else {
                    Text(" ").font(W.body(13))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [W.cardTop, W.cardBottom], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous))
        }
        .buttonStyle(WPressStyle())
    }

    private struct C: Identifiable { let id: String; let date: Date; let value: Double; let series: String }

    private var leanVsFat: some View {
        let lean = points(.leanMass).map { C(id: "l" + $0.id, date: $0.date, value: $0.value, series: "Lean mass") }
        let fat = points(.fatMass).map { C(id: "f" + $0.id, date: $0.date, value: $0.value, series: "Fat mass") }
        let all = lean + fat
        return NavigationLink(value: WRoute.trend(.leanMass, range.trend)) {
            WCard {
                VStack(alignment: .leading, spacing: 14) {
                    WCardHeader(title: "Lean vs. Fat Mass", chevron: true)
                    HStack(spacing: 16) {
                        Spacer()
                        WLegend(color: W.mint, label: "Lean mass")
                        WLegend(color: W.orange, label: "Fat mass")
                    }
                    if Set(all.map(\.date)).count >= 2 {
                        Chart(all) { p in
                            LineMark(x: .value("Day", p.date), y: .value(WMetric.massUnit, p.value), series: .value("S", p.series))
                                .foregroundStyle(p.series == "Lean mass" ? W.mint : W.orange)
                                .lineStyle(StrokeStyle(lineWidth: 2.5))
                            PointMark(x: .value("Day", p.date), y: .value(WMetric.massUnit, p.value))
                                .foregroundStyle(p.series == "Lean mass" ? W.mint : W.orange).symbolSize(24)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                                AxisGridLine().foregroundStyle(W.grid)
                                AxisValueLabel().font(W.caps(12, .semibold)).foregroundStyle(W.text3)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                                AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(W.caps(12, .semibold)).foregroundStyle(W.text3)
                            }
                        }
                        .frame(height: 210)
                    } else {
                        WNoData(height: 160)
                    }
                }
            }
        }
        .buttonStyle(WPressStyle())
        .padding(.top, 6)
    }

    private func scanRow(_ m: WMetric) -> some View {
        let l = data.latest(m)
        let start = points(m).first
        let d = (l != nil && start != nil && start!.id != l!.day) ? l!.value - start!.value : nil
        let good: Bool? = d.flatMap { dd in abs(dd) < 0.05 || m.better == .neither ? nil : (m.better == .up ? dd > 0 : dd < 0) }
        return HStack(spacing: 14) {
            Image(systemName: m.icon).font(.system(size: 18, weight: .light)).foregroundStyle(W.text2).frame(width: 26)
            Text(m.title.uppercased()).font(W.caps(14)).tracking(1.3).foregroundStyle(W.text).lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 6)
            if let d {
                Text((d >= 0 ? "+" : "−") + m.format(abs(d))).font(W.body(14, .semibold))
                    .foregroundStyle(good == nil ? W.text3 : (good! ? W.mint : W.orange))
            }
            Text(l.map { m.format($0.value) + (m.unit == "%" ? "%" : " " + m.unit) } ?? "--")
                .font(W.num(19)).foregroundStyle(W.text)
            Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(W.text3)
        }
        .padding(.horizontal, 18)
        .frame(height: 59)
        .contentShape(Rectangle())
    }
}
