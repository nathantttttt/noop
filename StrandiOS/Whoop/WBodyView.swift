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
        return NavigationLink(value: WRoute.leanFat) {
            WCard {
                VStack(alignment: .leading, spacing: 14) {
                    WCardHeader(title: "Lean vs. Fat Mass", chevron: true)
                    HStack(spacing: 16) {
                        Spacer()
                        WLegend(color: W.mint, label: "Lean mass")
                        WLegend(color: W.orange, label: "Fat mass")
                    }
                    if !all.isEmpty {
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

/// Lean mass against fat mass over time on one chart, with the change in each and every scan listed.
struct WLeanFatView: View {
    @EnvironmentObject var data: WhoopData
    @State private var days = 90
    @State private var selected: Date?

    private struct C: Identifiable { let id: String; let date: Date; let value: Double; let lean: Bool }

    private var lean: [WPoint] {
        data.window(.leanMass, end: Date(), days: days).compactMap { d in d.value.map { WPoint(id: d.day, date: d.date, value: $0) } }
    }
    private var fat: [WPoint] {
        data.window(.fatMass, end: Date(), days: days).compactMap { d in d.value.map { WPoint(id: d.day, date: d.date, value: $0) } }
    }

    var body: some View {
        let l = lean, f = fat
        let all = l.map { C(id: "l" + $0.id, date: $0.date, value: $0.value ?? 0, lean: true) }
            + f.map { C(id: "f" + $0.id, date: $0.date, value: $0.value ?? 0, lean: false) }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WSegmented(options: [(30, "1M"), (90, "3M"), (182, "6M"), (365, "1Y")], selection: $days)
                HStack(alignment: .top) {
                    summary("LEAN MASS", l, W.mint, betterUp: true)
                    Spacer()
                    summary("FAT MASS", f, W.orange, betterUp: false)
                }
                Text(verdict(l, f)).font(W.body(17)).foregroundStyle(W.text).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    Spacer()
                    WLegend(color: W.mint, label: "Lean mass")
                    WLegend(color: W.orange, label: "Fat mass")
                }
                if all.isEmpty {
                    WNoData(height: 260)
                } else {
                    Chart {
                        ForEach(all) { p in
                            LineMark(x: .value("Day", p.date, unit: .day), y: .value(WMetric.massUnit, p.value),
                                     series: .value("S", p.lean ? "Lean" : "Fat"))
                                .foregroundStyle(p.lean ? W.mint : W.orange)
                                .lineStyle(StrokeStyle(lineWidth: 2.5))
                            PointMark(x: .value("Day", p.date, unit: .day), y: .value(WMetric.massUnit, p.value))
                                .foregroundStyle(p.lean ? W.mint : W.orange).symbolSize(36)
                        }
                        if let sel = selected, let near = all.min(by: { abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel)) }) {
                            let k = Repository.localDayKey(near.date)
                            RuleMark(x: .value("Sel", near.date, unit: .day))
                                .foregroundStyle(Color.white.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                    VStack(spacing: 2) {
                                        Text(near.date.formatted(.dateTime.month(.abbreviated).day()).uppercased()).font(W.caps(11)).foregroundStyle(W.text2)
                                        HStack(spacing: 8) {
                                            Text(data.value(.leanMass, k).map(WFmt.one) ?? "--").foregroundStyle(W.mint)
                                            Text(data.value(.fatMass, k).map(WFmt.one) ?? "--").foregroundStyle(W.orange)
                                        }
                                        .font(W.num(18))
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(W.callout, in: RoundedRectangle(cornerRadius: 8))
                                }
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXSelection(value: $selected)
                    .onChange(of: selected) { _, _ in WHaptics.tick() }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { _ in
                            AxisGridLine().foregroundStyle(W.grid)
                            AxisValueLabel().font(W.caps(12, .semibold)).foregroundStyle(W.text3)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(W.caps(12, .semibold)).foregroundStyle(W.text3)
                        }
                    }
                    .frame(height: 300)
                }
                scans
            }
            .padding(.horizontal, W.margin)
            .padding(.bottom, 40)
        }
        .wPage(title: "Lean vs. Fat")
    }

    private func summary(_ label: String, _ pts: [WPoint], _ c: Color, betterUp: Bool) -> some View {
        let last = pts.last?.value, first = pts.first?.value
        let d = (last != nil && first != nil && pts.count >= 2) ? last! - first! : nil
        let good = d.map { betterUp ? $0 > 0 : $0 < 0 }
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).font(W.caps(13)).tracking(1.3).foregroundStyle(W.text2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(last.map(WFmt.one) ?? "--").font(W.num(36)).foregroundStyle(c)
                Text(WMetric.massUnit).font(W.body(16)).foregroundStyle(W.text3)
            }
            if let d, let good {
                WDeltaPill(text: "\(WFmt.one(abs(d))) \(WMetric.massUnit)", up: d >= 0, good: abs(d) < 0.05 ? nil : good)
            } else {
                Text(pts.count == 1 ? "One scan so far" : " ").font(W.body(13)).foregroundStyle(W.text3)
            }
        }
    }

    private func verdict(_ l: [WPoint], _ f: [WPoint]) -> String {
        guard l.count >= 2, f.count >= 2, let l0 = l.first?.value, let l1 = l.last?.value,
              let f0 = f.first?.value, let f1 = f.last?.value else {
            return "Each InBody scan adds a point. With two or more you'll see whether lean mass is climbing while fat comes down."
        }
        let dl = l1 - l0, df = f1 - f0, u = WMetric.massUnit
        if dl > 0.2 && df < -0.2 { return "Recomposing: \(WFmt.one(dl)) \(u) of lean mass gained and \(WFmt.one(-df)) \(u) of fat lost over this range." }
        if dl > 0.2 && df > 0.2 { return "Gaining both: lean mass up \(WFmt.one(dl)) \(u), fat up \(WFmt.one(df)) \(u). A slightly smaller surplus would tilt it toward muscle." }
        if dl < -0.2 && df < -0.2 { return "Losing both: fat down \(WFmt.one(-df)) \(u), lean mass down \(WFmt.one(-dl)) \(u). Keep protein high and keep lifting heavy to protect muscle." }
        return "Lean mass \(dl >= 0 ? "+" : "")\(WFmt.one(dl)) \(u), fat mass \(df >= 0 ? "+" : "")\(WFmt.one(df)) \(u) over this range."
    }

    private var scans: some View {
        let keys = Set((data.series[.weight] ?? [:]).keys).union((data.series[.leanMass] ?? [:]).keys).sorted(by: >).prefix(20)
        return VStack(alignment: .leading, spacing: 10) {
            Text("SCANS").font(W.caps(13)).tracking(1.4).foregroundStyle(W.text3).padding(.top, 6)
            VStack(spacing: 0) {
                HStack {
                    Text("DATE").frame(maxWidth: .infinity, alignment: .leading)
                    Text("WEIGHT").frame(width: 66, alignment: .trailing)
                    Text("FAT %").frame(width: 54, alignment: .trailing)
                    Text("LEAN").frame(width: 58, alignment: .trailing)
                    Text("FAT").frame(width: 52, alignment: .trailing)
                }
                .font(W.caps(11)).tracking(1).foregroundStyle(W.text3)
                .padding(.horizontal, 16).padding(.vertical, 10)
                ForEach(Array(keys), id: \.self) { k in
                    Rectangle().fill(W.hairline).frame(height: 1)
                    HStack {
                        Text(WFmt.dayDate(k)?.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits)) ?? k)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(data.value(.weight, k).map(WFmt.one) ?? "--").frame(width: 66, alignment: .trailing)
                        Text(data.value(.bodyFat, k).map(WFmt.one) ?? "--").frame(width: 54, alignment: .trailing)
                        Text(data.value(.leanMass, k).map(WFmt.one) ?? "--").frame(width: 58, alignment: .trailing).foregroundStyle(W.mint)
                        Text(data.value(.fatMass, k).map(WFmt.one) ?? "--").frame(width: 52, alignment: .trailing).foregroundStyle(W.orange)
                    }
                    .font(W.num(15)).foregroundStyle(W.text)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .background(W.row, in: RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous))
        }
    }
}
