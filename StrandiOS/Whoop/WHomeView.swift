//  WHomeView.swift
//  Nathan's build: the WHOOP-style Home tab. A date stepper and strap pill, the three dials (Sleep ·
//  Recovery · Strain) that shrink into a pinned mini row as you scroll, then My Dashboard (customisable
//  metric rows that open their Trend View), Strain & Recovery for the week, calories in vs. out with
//  protein from MacroFactor, the day's activities and the journal.

import SwiftUI
import Charts
import WhoopStore

private struct DialsOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct WHomeView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var data: WhoopData
    @AppStorage(WDashboard.key) private var dashboardCSV = WDashboard.defaultCSV
    @State private var dayOffset = 0
    @State private var scrollY: CGFloat = 0
    @State private var showCustomize = false
    @State private var showJournal = false
    @State private var showCoach = false

    private var day: Date { Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date() }
    private var dayKey: String { Repository.localDayKey(day) }
    /// 0 at the top of the page, 1 once the big dials have scrolled under the bar.
    private var morph: CGFloat { min(1, max(0, (scrollY - 50) / 120)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.top, 4)
                dials
                    .padding(.top, 22)
                    .scaleEffect(1 - 0.3 * morph, anchor: .top)
                    .opacity(Double(1 - morph))
                    .background(GeometryReader { g in
                        Color.clear.preference(key: DialsOffsetKey.self, value: g.frame(in: .named("home")).minY)
                    })
                VStack(alignment: .leading, spacing: W.rowGap) {
                    staleBanner
                    activities
                    monitors
                    NathanSignalsCard()
                    dashboard
                    strainRecovery
                    nutrition
                    journalCard
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, W.margin)
            .padding(.bottom, 40)
        }
        .coordinateSpace(name: "home")
        .modifier(WScrollTracker(y: $scrollY))
        .onPreferenceChange(DialsOffsetKey.self) { v in
            // iOS 17 fallback; iOS 18+ reads the scroll position directly (WScrollTracker).
            if #unavailable(iOS 18) { scrollY = 26 - v }
        }
        .background(WBackground())
        .overlay(alignment: .top) { compactHeader }
        .overlay(alignment: .bottomTrailing) { WCoachButton { showCoach = true }.padding(.trailing, 16).padding(.bottom, 10) }
        .sheet(isPresented: $showCoach) { WCoachSheet() }
        .refreshable { await repo.refresh() }
        .wRoutes()
        .sheet(isPresented: $showCustomize) { WDashboardCustomize(csv: $dashboardCSV) }
        .fullScreenCover(isPresented: $showJournal) { NathanMorningJournal() }
        .task(id: repo.refreshSeq) {
            if NathanMorningJournalGate.shouldShow(today: repo.today) {
                NathanMorningJournalGate.markShown()
                showJournal = true
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            WAvatar()
            Spacer()
            HStack(spacing: 18) {
                Button { WHaptics.select(); dayOffset += 1 } label: { Image(systemName: "chevron.left") }
                Text(dayOffset == 0 ? "TODAY" : day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased())
                    .font(W.caps(15)).tracking(1.6).frame(minWidth: 110)
                Button { WHaptics.select(); dayOffset = max(0, dayOffset - 1) } label: {
                    Image(systemName: "chevron.right").foregroundStyle(dayOffset == 0 ? W.text3.opacity(0.5) : W.text)
                }
                .disabled(dayOffset == 0)
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(W.text)
            .buttonStyle(.plain)
            Spacer()
            WStrapPill()
        }
    }

    // MARK: Dials

    /// Today's value, or (on today only) the last one recorded, so the dials don't blank at midnight.
    private func carriedScore(_ s: WScore) -> (value: Double, day: String)? {
        let back = dayOffset == 0 ? 2 : 0
        switch s {
        case .sleep:
            return data.carried(.sleepPerformance, dayKey, maxBack: back)
                ?? data.carried(.hoursVsNeededPct, dayKey, maxBack: back).map { (value: min(100, $0.value), day: $0.day) }
        case .recovery: return data.carried(.recovery, dayKey, maxBack: back)
        case .strain: return data.carried(.strain, dayKey, maxBack: back)
        }
    }

    private func value(_ s: WScore) -> Double? { carriedScore(s)?.value }

    private func color(_ s: WScore) -> Color {
        switch s {
        case .sleep: W.sleep
        case .recovery: W.recoveryColor(value(.recovery))
        case .strain: W.strain
        }
    }

    private func fraction(_ s: WScore) -> Double? { value(s).map { s == .strain ? $0 / 21 : $0 / 100 } }

    private func text(_ s: WScore) -> String {
        guard let v = value(s) else { return "--" }
        return s == .strain ? WFmt.one(v) : WFmt.int(v) + "%"
    }

    private var dials: some View {
        HStack(spacing: 0) {
            ForEach([WScore.sleep, .recovery, .strain], id: \.self) { s in
                // Open on the day the ring is showing (yesterday's, if today has no score yet).
                NavigationLink(value: WRoute.score(s, carriedScore(s)?.day ?? dayKey)) {
                    VStack(spacing: 12) {
                        WDial(fraction: fraction(s), color: color(s), size: 104, lineWidth: 9,
                              target: s == .strain ? data.strainTarget(dayKey) : nil) {
                            VStack(spacing: 2) {
                                Text(text(s)).font(W.num(28, .heavy)).foregroundStyle(W.text)
                                    .minimumScaleFactor(0.6).lineLimit(1).padding(.horizontal, 12)
                                if s == .recovery, value(.recovery) == nil, dayOffset == 0,
                                   let n = WhoopData.recoveryCalibration(repo) {
                                    Text("\(n) OF \(WhoopData.recoverySeedNights)\nNIGHTS").font(W.caps(9)).tracking(0.8)
                                        .multilineTextAlignment(.center).foregroundStyle(W.text3)
                                }
                            }
                        }
                        VStack(spacing: 2) {
                            Text(s.rawValue.uppercased()).font(W.caps(14)).tracking(1.6).foregroundStyle(W.text)
                            Text(carriedScore(s).flatMap { WhoopData.asOf($0.day, relativeTo: dayKey) } ?? " ")
                                .font(W.caps(10)).tracking(1).foregroundStyle(W.text3)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(WPressStyle())
            }
        }
    }

    /// The pinned mini row that takes over once the big dials scroll away.
    private var compactHeader: some View {
        HStack(spacing: 0) {
            ForEach([WScore.sleep, .recovery, .strain], id: \.self) { s in
                NavigationLink(value: WRoute.score(s, carriedScore(s)?.day ?? dayKey)) {
                    HStack(spacing: 10) {
                        WDial(fraction: fraction(s), color: color(s), size: 30, lineWidth: 3.5,
                              target: s == .strain ? data.strainTarget(dayKey) : nil) { EmptyView() }
                        Text(s.rawValue.uppercased()).font(W.caps(14)).tracking(1.5).foregroundStyle(W.text)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .padding(.top, 4)
        .background(
            LinearGradient(colors: [W.bgTop, W.bgTop.opacity(0.94)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
        .opacity(Double(max(0, morph * 2 - 1)))
        .offset(y: (1 - morph) * -14)
        .allowsHitTesting(morph > 0.9)
    }

    // MARK: My Dashboard

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: W.rowGap) {
            WSectionTitle(title: "My Dashboard", trailing: AnyView(
                Button { showCustomize = true } label: {
                    HStack(spacing: 8) {
                        Text("CUSTOMIZE").font(W.caps(14)).tracking(1.5)
                        Image(systemName: "pencil").font(.system(size: 17, weight: .regular))
                    }
                    .foregroundStyle(W.text)
                }
                .buttonStyle(.plain)
            ))
            .padding(.bottom, 4)
            ForEach(WDashboard.decode(dashboardCSV)) { m in
                NavigationLink(value: WRoute.trend(m, .month)) { dashboardRow(m) }
                    .buttonStyle(WPressStyle())
            }
        }
    }

    private func rowValue(_ m: WMetric) -> (String, Bool?)? {
        let weekly = m == .zones13 || m == .zones45 || m == .strengthTime
        let v: Double?
        var asOfDay: String?
        if weekly {
            let xs = data.window(m, end: day, days: 7).compactMap(\.value)
            v = xs.isEmpty ? nil : xs.reduce(0, +)
        } else {
            let c = data.carried(m, dayKey, maxBack: m.group == .body ? 365 : 7)
            v = c?.value
            asOfDay = c?.day
        }
        guard let v else { return nil }
        var good: Bool?
        let ref = asOfDay ?? dayKey
        if !weekly, let b = data.baseline(m, before: ref), m.better != .neither, abs(v - b) > max(abs(b) * 0.03, 0.0001) {
            good = m.better == .up ? v > b : v < b
        }
        let unit = m.unit == "%" ? "%" : ""
        return ((m.isDuration ? WFmt.hm(v) : m.format(v)) + unit, good)
    }

    /// Small "YESTERDAY" / weekday tag on a carried value; "STALE" when it is older than 30 hours.
    private func rowAsOf(_ m: WMetric) -> String? {
        guard m != .zones13, m != .zones45, m != .strengthTime, m.group != .body,
              let c = data.carried(m, dayKey), c.day != dayKey else { return nil }
        if let d = WFmt.dayDate(c.day), let b = WFmt.dayDate(dayKey),
           (Calendar.current.dateComponents([.day], from: d, to: b).day ?? 0) >= 2 { return "STALE" }
        return WhoopData.asOf(c.day, relativeTo: dayKey)
    }

    private func dashboardRow(_ m: WMetric) -> some View {
        let rv = rowValue(m)
        let weekly = m == .zones13 || m == .zones45 || m == .strengthTime
        return HStack(spacing: 14) {
            Image(systemName: m.icon).font(.system(size: 19, weight: .light)).foregroundStyle(W.text2).frame(width: 28)
            Text((m.title + (weekly ? " (Weekly)" : "")).uppercased()).font(W.caps(14)).tracking(1.5)
                .foregroundStyle(W.text).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 6)
            if let rv {
                if let tag = rowAsOf(m) {
                    Text(tag).font(W.caps(10)).tracking(0.8).foregroundStyle(tag == "STALE" ? W.orange : W.text3)
                }
                if let g = rv.1 {
                    Image(systemName: g ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 8)).foregroundStyle(g ? W.mint : W.orange)
                }
                Text(rv.0).font(W.num(19)).foregroundStyle(W.text)
            }
            Image(systemName: "chevron.right").font(.system(size: 17, weight: .semibold)).foregroundStyle(W.text)
        }
        .padding(.horizontal, 18)
        .frame(height: 59)
        .background(W.row, in: RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous))
    }

    // MARK: Strain & Recovery

    private struct SRDay: Identifiable {
        let id: String
        let date: Date
        let recovery: Double?
        let strain: Double?
    }

    private var srDays: [SRDay] {
        let r = data.window(.recovery, end: day, days: 7)
        return r.map { SRDay(id: $0.day, date: $0.date, recovery: $0.value, strain: data.value(.strain, $0.day)) }
    }

    private var strainRecovery: some View {
        let days = srDays
        return WCard {
            VStack(alignment: .leading, spacing: 16) {
                WCardHeader(title: "Strain & Recovery", info: true)
                if days.allSatisfy({ $0.recovery == nil && $0.strain == nil }) {
                    WNoData(height: 220)
                } else {
                    Chart {
                        ForEach(days.filter { $0.recovery != nil }) { d in
                            BarMark(x: .value("Day", d.date, unit: .day), y: .value("Recovery", d.recovery ?? 0), width: .ratio(0.42))
                                .foregroundStyle(W.recoveryColor(d.recovery).opacity(0.9))
                        }
                        ForEach(days.filter { $0.strain != nil }) { d in
                            LineMark(x: .value("Day", d.date, unit: .day), y: .value("Strain", (d.strain ?? 0) / 21 * 100))
                                .foregroundStyle(W.strain).lineStyle(StrokeStyle(lineWidth: 2.5))
                            PointMark(x: .value("Day", d.date, unit: .day), y: .value("Strain", (d.strain ?? 0) / 21 * 100))
                                .foregroundStyle(W.strain).symbolSize(40)
                                .annotation(position: .top, spacing: 6) {
                                    // Backed so the line passing under a low point can't hide its label.
                                    Text(WFmt.one(d.strain ?? 0)).font(W.num(13)).foregroundStyle(W.strain)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(W.cardBottom.opacity(0.92), in: RoundedRectangle(cornerRadius: 4))
                                }
                        }
                    }
                    .chartYScale(domain: -6...112)
                    .chartXScale(domain: (days.first?.date ?? day)...(days.last?.date.addingTimeInterval(86_400) ?? day))
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [0, 33.33, 66.67, 100]) { v in
                            AxisGridLine().foregroundStyle(W.grid)
                            AxisValueLabel {
                                if let d = v.as(Double.self) { Text("\(Int((d / 100 * 21).rounded()))") }
                            }
                            .font(W.caps(13)).foregroundStyle(W.strain)
                        }
                        AxisMarks(position: .trailing, values: [0, 33.33, 66.67, 100]) { v in
                            AxisValueLabel {
                                if let d = v.as(Double.self) {
                                    Text("\(Int(d.rounded()))%").foregroundStyle(d >= 66 ? W.green : d >= 33 ? W.yellow : W.red)
                                }
                            }
                            .font(W.caps(13))
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { v in
                            AxisValueLabel(centered: true) {
                                if let d = v.as(Date.self) {
                                    VStack(spacing: 2) {
                                        Text(d, format: .dateTime.weekday(.abbreviated))
                                        Text(d, format: .dateTime.day()).foregroundStyle(W.text3)
                                    }
                                }
                            }
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(W.text2)
                        }
                    }
                    .frame(height: 250)
                }
            }
        }
        .padding(.top, 10)
    }

    // MARK: Nutrition

    private var nutrition: some View {
        let eatenC = data.carried(.caloriesIn, dayKey, maxBack: 2)
        let eaten = eatenC?.value
        let burned = eatenC.flatMap { data.value(.calories, $0.day) } ?? data.carried(.calories, dayKey, maxBack: 2)?.value
        let protein = data.carried(.protein, dayKey, maxBack: 2)?.value
        return NavigationLink(value: WRoute.trend(.energyBalance, .week)) {
            WCard {
                VStack(alignment: .leading, spacing: 16) {
                    WCardHeader(title: eatenC.flatMap { WhoopData.asOf($0.day, relativeTo: dayKey) }.map { "Calories · " + $0.capitalized } ?? "Calories",
                                chevron: true)
                    HStack(alignment: .top) {
                        kcalCol("EATEN", eaten, W.orange)
                        Spacer()
                        kcalCol("BURNED", burned, W.strain)
                        Spacer()
                        if let eaten, let burned {
                            let bal = eaten - burned
                            kcalCol(bal < 0 ? "DEFICIT" : "SURPLUS", abs(bal), bal < 0 ? W.mint : W.text2)
                        } else {
                            kcalCol("BALANCE", nil, W.text2)
                        }
                    }
                    if let protein {
                        HStack(spacing: 10) {
                            Text("PROTEIN").font(W.caps(12)).tracking(1.2).foregroundStyle(W.text3)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.08))
                                    Capsule().fill(W.mint).frame(width: g.size.width * min(1, protein / max(1, WDashboard.proteinGoal)))
                                }
                            }
                            .frame(height: 8)
                            Text("\(Int(protein.rounded())) g").font(W.num(17)).foregroundStyle(W.text)
                        }
                    } else if eaten == nil {
                        Text("Add your MacroFactor calories and protein to the Health Shortcut to see what you ate here.")
                            .font(W.body(14)).foregroundStyle(W.text3)
                    }
                }
            }
        }
        .buttonStyle(WPressStyle())
    }

    private func kcalCol(_ label: String, _ v: Double?, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(v.map(WFmt.grouped) ?? "--").font(W.num(30)).foregroundStyle(v == nil ? W.text3 : c)
            Text(label).font(W.caps(12)).tracking(1.2).foregroundStyle(W.text3)
        }
    }

    // MARK: Activities

    @ViewBuilder private var activities: some View {
        let todays = data.workouts.filter { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.startTs))) == dayKey }
        if !todays.isEmpty {
            ForEach(todays, id: \.startTs) { w in
                NavigationLink(value: WRoute.activity(w.startTs)) { WActivityRow(workout: w) }
                    .buttonStyle(WPressStyle())
            }
        }
    }

    // MARK: Stale data

    /// Speaks up when no sleep has been recorded for more than 30 hours.
    @ViewBuilder private var staleBanner: some View {
        if dayOffset == 0, let last = repo.sleeps.map(\.endTs).max() {
            let hours = (Date().timeIntervalSince1970 - Double(last)) / 3600
            if hours > 30 {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "moon.zzz").font(.system(size: 18)).foregroundStyle(W.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NO NEW SLEEP IN \(Int(hours)) HOURS").font(W.caps(13)).tracking(1.2).foregroundStyle(W.text)
                        Text("Last recorded night ended \(Date(timeIntervalSince1970: TimeInterval(last)).formatted(.dateTime.weekday(.wide).hour().minute())). Wear the strap overnight and open NOOP in the morning to sync. Your other numbers show their last recorded values.")
                            .font(W.body(14)).foregroundStyle(W.text2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(W.row, in: RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous).stroke(W.orange.opacity(0.5), lineWidth: 1))
            }
        }
    }

    // MARK: Health + Stress monitor tiles

    private var monitors: some View {
        HStack(spacing: W.rowGap) {
            NavigationLink(value: WRoute.healthMonitor) { WHealthMonitorTile() }.buttonStyle(WPressStyle())
            NavigationLink(value: WRoute.stress) { WStressTile() }.buttonStyle(WPressStyle())
        }
    }

    // MARK: Journal

    private var journalCard: some View {
        Button { showJournal = true } label: {
            WCard(padding: 22) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Daily Journal").font(W.body(20, .semibold)).foregroundStyle(W.text)
                        Text("Log yesterday's habits so NOOP can learn what moves your recovery.")
                            .font(W.body(16)).foregroundStyle(W.text2).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Text("OPEN JOURNAL").font(W.caps(14)).tracking(1.5)
                            Image(systemName: "arrow.right").font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(W.lineBlue)
                        .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "book.closed").font(.system(size: 46, weight: .ultraLight)).foregroundStyle(W.text3)
                }
            }
        }
        .buttonStyle(WPressStyle())
        .padding(.top, 10)
    }
}

/// Strap connection and battery, in WHOOP's top-right pill.
struct WStrapPill: View {
    @EnvironmentObject var live: LiveState
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: live.connected ? "battery.75percent" : "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 14, weight: .semibold))
            if let b = live.batteryPct { Text("\(Int(b.rounded()))%").font(W.num(15)) }
        }
        .foregroundStyle(live.connected ? W.text : W.text3)
        .padding(.horizontal, 12).frame(height: 40)
        .background(W.row, in: Capsule())
    }
}

// MARK: - Dashboard customisation

enum WDashboard {
    static let key = "w.dashboard.metrics"
    static let all: [WMetric] = [.hrv, .rhr, .respRate, .steps, .zones13, .zones45, .strengthTime, .calories,
                                 .caloriesIn, .protein, .energyBalance, .sleepDebt, .sleepConsistency, .spo2, .skinTemp]
    static let defaultCSV = [WMetric.hrv, .rhr, .steps, .zones13, .zones45, .calories, .caloriesIn, .protein]
        .map(\.rawValue).joined(separator: ",")
    static let proteinGoal: Double = 150

    static func decode(_ csv: String) -> [WMetric] {
        csv.split(separator: ",").compactMap { WMetric(rawValue: String($0)) }
    }
    static func encode(_ ms: [WMetric]) -> String { ms.map(\.rawValue).joined(separator: ",") }
}

struct WDashboardCustomize: View {
    @Binding var csv: String
    @Environment(\.dismiss) private var dismiss
    @State private var shown: [WMetric] = []

    var body: some View {
        NavigationStack {
            List {
                Section("On your dashboard") {
                    ForEach(shown) { m in
                        HStack(spacing: 12) {
                            Image(systemName: m.icon).frame(width: 24).foregroundStyle(W.text2)
                            Text(m.title)
                            Spacer()
                            Button { shown.removeAll { $0 == m } } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(W.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onMove { shown.move(fromOffsets: $0, toOffset: $1) }
                }
                Section("Add") {
                    ForEach(WDashboard.all.filter { !shown.contains($0) }) { m in
                        Button { shown.append(m) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: m.icon).frame(width: 24).foregroundStyle(W.text2)
                                Text(m.title).foregroundStyle(W.text)
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(W.mint)
                            }
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(W.bgMid)
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { csv = WDashboard.encode(shown); dismiss() }.fontWeight(.bold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { shown = WDashboard.decode(csv) }
    }
}
