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
    @State private var dialsBottom: CGFloat = 400
    @State private var showCustomize = false
    @State private var showJournal = false

    private var day: Date { Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date() }
    private var dayKey: String { Repository.localDayKey(day) }
    private var collapsed: Bool { dialsBottom < 70 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.top, 4)
                dials
                    .padding(.top, 22)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: DialsOffsetKey.self, value: g.frame(in: .named("home")).maxY)
                    })
                VStack(alignment: .leading, spacing: W.rowGap) {
                    NathanSignalsCard().padding(.top, 8)
                    dashboard
                    strainRecovery
                    nutrition
                    activities
                    journalCard
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, W.margin)
            .padding(.bottom, 40)
        }
        .coordinateSpace(name: "home")
        .onPreferenceChange(DialsOffsetKey.self) { v in dialsBottom = v }
        .background(WBackground())
        .overlay(alignment: .top) { compactHeader }
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
            Circle().fill(W.row).frame(width: 40, height: 40)
                .overlay(Text("N").font(W.num(19)).foregroundStyle(W.text))
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

    private func value(_ s: WScore) -> Double? {
        switch s {
        case .sleep: data.value(.sleepPerformance, dayKey) ?? data.value(.hoursVsNeededPct, dayKey).map { min(100, $0) }
        case .recovery: data.value(.recovery, dayKey)
        case .strain: data.value(.strain, dayKey)
        }
    }

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
                NavigationLink(value: WRoute.score(s, dayKey)) {
                    VStack(spacing: 12) {
                        WDial(fraction: fraction(s), color: color(s), size: 104, lineWidth: 9) {
                            Text(text(s)).font(W.num(28, .heavy)).foregroundStyle(W.text)
                                .minimumScaleFactor(0.6).lineLimit(1).padding(.horizontal, 12)
                        }
                        Text(s.rawValue.uppercased()).font(W.caps(14)).tracking(1.6).foregroundStyle(W.text)
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
                NavigationLink(value: WRoute.score(s, dayKey)) {
                    HStack(spacing: 10) {
                        WDial(fraction: fraction(s), color: color(s), size: 30, lineWidth: 3.5) { EmptyView() }
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
        .opacity(collapsed ? 1 : 0)
        .offset(y: collapsed ? 0 : -16)
        .animation(.easeOut(duration: 0.22), value: collapsed)
        .allowsHitTesting(collapsed)
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
        if weekly {
            let xs = data.window(m, end: day, days: 7).compactMap(\.value)
            v = xs.isEmpty ? nil : xs.reduce(0, +)
        } else {
            v = data.value(m, dayKey)
        }
        guard let v else { return nil }
        var good: Bool?
        if !weekly, let b = data.baseline(m, before: dayKey), m.better != .neither, abs(v - b) > max(abs(b) * 0.03, 0.0001) {
            good = m.better == .up ? v > b : v < b
        }
        let unit = m.unit == "%" ? "%" : ""
        return ((m.isDuration ? WFmt.hm(v) : m.format(v)) + unit, good)
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
                                .annotation(position: .top, spacing: 4) {
                                    Text(WFmt.one(d.strain ?? 0)).font(W.num(13)).foregroundStyle(W.strain)
                                }
                        }
                    }
                    .chartYScale(domain: 0...100)
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
        let eaten = data.value(.caloriesIn, dayKey), burned = data.value(.calories, dayKey)
        let protein = data.value(.protein, dayKey)
        return NavigationLink(value: WRoute.trend(.energyBalance, .week)) {
            WCard {
                VStack(alignment: .leading, spacing: 16) {
                    WCardHeader(title: "Calories", chevron: true)
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
            WSectionTitle(title: "Activities")
            ForEach(todays, id: \.startTs) { w in
                NavigationLink(value: WRoute.activity(w.startTs)) { WActivityRow(workout: w) }
                    .buttonStyle(WPressStyle())
            }
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
