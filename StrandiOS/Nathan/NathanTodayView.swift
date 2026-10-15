//  NathanTodayView.swift
//  Nathan's Today: three score rings (Sleep · Recovery · Strain with today's target), last night's
//  vitals, today's activity and the latest body scan. Every value reads the same Repository data the
//  stock Today screen uses; nothing here computes a score of its own.

import SwiftUI
import StrandDesign
import WhoopStore

struct NathanTodayView: View {
    @EnvironmentObject var repo: Repository
    @Environment(\.nathanSelectTab) private var selectTab
    @AppStorage(UnitPrefs.systemKey) private var unitRaw = UnitSystem.imperial.rawValue
    private var units: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    @State private var sleepPerf: [String: Double] = [:]
    @State private var sleepNeed: [String: Double] = [:]
    @State private var weight: [(day: String, value: Double)] = []
    @State private var bodyFat: [(day: String, value: Double)] = []
    @State private var lean: [(day: String, value: Double)] = []
    @State private var appleSteps: [String: Double] = [:]
    @State private var appleKcal: [String: Double] = [:]
    @State private var eaten: [String: Double] = [:]
    @State private var showJournal = false

    private var row: DailyMetric? { repo.today }
    private var dayKey: String { row?.day ?? Repository.localDayKey(Date()) }

    /// The 30 scored days before today, for "vs your usual" comparisons.
    private var history: [DailyMetric] {
        let prior = repo.days.filter { $0.day < dayKey }
        return Array(prior.suffix(30))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NathanStyle.sectionGap) {
                header
                NathanSignalsCard()
                scoresCard
                lastNight
                activity
                bodySection
                liftRow
            }
            .padding(.horizontal, NathanStyle.page)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(NathanStyle.canvas.ignoresSafeArea())
        .refreshable { await repo.refresh() }
        .task(id: repo.refreshSeq) {
            await load()
            if NathanMorningJournalGate.shouldShow(today: repo.today) {
                NathanMorningJournalGate.markShown()
                showJournal = true
            }
        }
        .fullScreenCover(isPresented: $showJournal) { NathanMorningJournal() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                    .font(NathanStyle.label).tracking(0.8).foregroundStyle(NathanStyle.text3)
                Text("Today").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(NathanStyle.text)
            }
            Spacer()
            NathanStrapPill()
        }
    }

    // MARK: Scores

    private var recovery: Double? { row?.recovery }
    private var strain21: Double? { row?.strain.map { UnitFormatter.effortValue($0, scale: .whoop) } }
    private var targetRange: ClosedRange<Int>? { CoupledView.optimalStrainRange(recovery: recovery) }

    private var scoresCard: some View {
        NathanCard(padding: 14) {
            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    scoreColumn(title: "SLEEP", color: NathanStyle.sleepPerfColor(sleepPerf[dayKey]),
                                fraction: sleepPerf[dayKey].map { $0 / 100 },
                                center: sleepPerf[dayKey].map { NathanFormat.int($0) },
                                pct: true,
                                caption: row?.totalSleepMin.map { NathanFormat.hmLong($0) } ?? "—")
                        .onTapGesture { selectTab(NathanTab.sleep) }
                    Spacer(minLength: 0)
                    scoreColumn(title: "RECOVERY", color: NathanStyle.recoveryColor(recovery),
                                fraction: recovery.map { $0 / 100 },
                                center: recovery.map { NathanFormat.int($0) },
                                pct: true,
                                caption: NathanStyle.recoveryLabel(recovery))
                    Spacer(minLength: 0)
                    VStack(spacing: 10) {
                        NathanRing(fraction: strain21.map { $0 / 21 }, color: NathanStyle.strainColor,
                                   target: targetRange.map { Double($0.lowerBound) / 21 ... Double($0.upperBound) / 21 }) {
                            Text(strain21.map { NathanFormat.one($0) } ?? "—")
                                .font(NathanStyle.number(30)).foregroundStyle(NathanStyle.text)
                        }
                        VStack(spacing: 2) {
                            Text("STRAIN").font(NathanStyle.label).tracking(1).foregroundStyle(NathanStyle.strainColor)
                            Text(targetRange.map { "Target \($0.lowerBound)–\($0.upperBound)" } ?? "No target yet")
                                .font(.system(size: 12, design: .rounded)).foregroundStyle(NathanStyle.text3)
                        }
                    }
                    .frame(width: 108)
                }
                strainToGo
            }
        }
    }

    private func scoreColumn(title: String, color: Color, fraction: Double?, center: String?,
                             pct: Bool, caption: String) -> some View {
        VStack(spacing: 10) {
            NathanRing(fraction: fraction, color: color) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(center ?? "—").font(NathanStyle.number(30)).foregroundStyle(center == nil ? NathanStyle.text3 : color)
                    if pct && center != nil {
                        Text("%").font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(NathanStyle.text3)
                    }
                }
            }
            VStack(spacing: 2) {
                Text(title).font(NathanStyle.label).tracking(1).foregroundStyle(color)
                Text(caption).font(.system(size: 12, design: .rounded)).foregroundStyle(NathanStyle.text3)
            }
        }
        .frame(width: 108)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var strainToGo: some View {
        if let range = targetRange, let s = strain21 {
            let low = Double(range.lowerBound)
            let left = max(0, low - s)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Group {
                        if left > 0 {
                            Text("\(NathanFormat.one(left)) strain").bold().foregroundColor(NathanStyle.text)
                            + Text(" to hit today's target").foregroundColor(NathanStyle.text2)
                        } else {
                            Text("Target reached").bold().foregroundColor(NathanStyle.good)
                            + Text(s > Double(range.upperBound) ? " · above the range, ease off" : " · nice work")
                                .foregroundColor(NathanStyle.text2)
                        }
                    }
                    .font(.system(size: 13, design: .rounded))
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(NathanStyle.inset)
                            Capsule().fill(NathanStyle.strainColor).frame(width: g.size.width * min(1, s / max(low, 1)))
                        }
                    }
                    .frame(height: 6)
                }
                Text("Based on recovery").font(.system(size: 12, design: .rounded)).foregroundStyle(NathanStyle.text3)
                    .fixedSize()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(NathanStyle.inset.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Last night

    private var lastNight: some View {
        VStack(alignment: .leading, spacing: NathanStyle.gap) {
            NathanSectionHeader(title: "Last night", trailing: "Sleep details") { selectTab(NathanTab.sleep) }
            let hrvBase = NathanFormat.mean(history.compactMap(\.avgHrv))
            let rhrBase = NathanFormat.mean(history.compactMap { $0.restingHr.map(Double.init) })
            let need = sleepNeed[dayKey]
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                deltaTile("HRV", value: row?.avgHrv, unit: "ms", base: hrvBase, better: .up, fmt: NathanFormat.int, vs: " vs 30-day avg")
                deltaTile("Resting HR", value: row?.restingHr.map(Double.init), unit: "bpm", base: rhrBase, better: .down, fmt: NathanFormat.int, vs: " vs 30-day avg")
                asleepTile(need: need)
                deepRemTile
            }
        }
    }

    private func deltaTile(_ label: String, value: Double?, unit: String, base: Double?, better: NathanBetter,
                           fmt: @escaping (Double) -> String, vs: String) -> some View {
        let d = NathanDelta.make(current: value, baseline: base, better: better, format: fmt, suffix: vs, deadband: 0.5)
        return NathanTile(label: label, value: value.map(fmt) ?? "—", unit: value == nil ? "" : unit,
                          footer: d?.text ?? "Building your baseline", footerColor: d?.color ?? NathanStyle.text3)
    }

    private func asleepTile(need: Double?) -> some View {
        let asleep = row?.totalSleepMin
        var footer = need.map { "Need \(NathanFormat.hm($0))" } ?? "—"
        var color = NathanStyle.text3
        if let asleep, let need {
            let diff = asleep - need
            if diff < -10 {
                footer = "▼ \(NathanFormat.hmLong(-diff)) under need"; color = NathanStyle.bad
            } else {
                footer = "Need met"; color = NathanStyle.good
            }
        }
        return NathanTile(label: "Time asleep", value: asleep.map(NathanFormat.hm) ?? "—", footer: footer, footerColor: color)
    }

    private var deepRemTile: some View {
        let deep = row?.deepMin, rem = row?.remMin, total = row?.totalSleepMin
        let value = (deep != nil && rem != nil) ? "\(NathanFormat.hm(deep!)) · \(NathanFormat.hm(rem!))" : "—"
        var footer = "—"
        if let deep, let rem, let total, total > 0 {
            footer = "\(Int((deep / total * 100).rounded()))% · \(Int((rem / total * 100).rounded()))% of sleep"
        }
        return NathanTile(label: "Deep · REM", value: value, footer: footer)
    }

    // MARK: Activity

    private var activity: some View {
        let steps = row?.steps.map(Double.init) ?? appleSteps[dayKey]
        let stepBase = NathanFormat.mean(history.compactMap { $0.steps.map(Double.init) })
        let kcal = appleKcal[dayKey] ?? row?.activeKcalEst
        let stepDelta = NathanDelta.make(current: steps, baseline: stepBase, better: .up,
                                         format: NathanFormat.grouped, suffix: " vs usual", deadband: 250)
        return VStack(alignment: .leading, spacing: NathanStyle.gap) {
            NathanSectionHeader(title: "Activity today")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                NathanTile(label: "Steps", value: steps.map(NathanFormat.grouped) ?? "—",
                           footer: stepDelta?.text ?? " ", footerColor: stepDelta?.color ?? NathanStyle.text3)
                NathanTile(label: "Calories burned", value: kcal.map(NathanFormat.grouped) ?? "—",
                           footer: eaten[dayKey].map { "Eaten \(NathanFormat.grouped($0)) · MacroFactor" } ?? "Active energy",
                           footerColor: NathanStyle.text3)
            }
        }
    }

    // MARK: Body

    private func massText(_ kg: Double) -> String {
        NathanFormat.one(units == .imperial ? UnitFormatter.kgToPounds(kg) : kg)
    }

    /// Latest value and its change versus the reading closest to 30 days earlier.
    private func latestAndDelta(_ s: [(day: String, value: Double)]) -> (latest: (day: String, value: Double)?, change: Double?) {
        guard let last = s.last else { return (nil, nil) }
        let cutoff = Repository.localDayKey(Date().addingTimeInterval(-30 * 86_400))
        let earlier = s.last(where: { $0.day <= cutoff }) ?? s.first
        let change = (earlier.map { $0.day != last.day } ?? false) ? last.value - earlier!.value : nil
        return (last, change)
    }

    private var bodySection: some View {
        let w = latestAndDelta(weight), bf = latestAndDelta(bodyFat), lm = latestAndDelta(lean)
        let unit = UnitFormatter.massUnit(units)
        let scanDay = [w.latest?.day, bf.latest?.day, lm.latest?.day].compactMap { $0 }.max()
        return VStack(alignment: .leading, spacing: NathanStyle.gap) {
            NathanSectionHeader(title: "Body", trailing: scanDay.map { "Latest · \(Self.shortDay($0))" } ?? "Open Body") {
                selectTab(NathanTab.body)
            }
            NathanCard {
                HStack(spacing: 0) {
                    bodyStat("Weight", value: w.latest.map { massText($0.value) }, unit: unit,
                             delta: w.change.map { NathanDelta.make(current: $0, baseline: 0, better: .neither,
                                                                   format: { massText($0) }, deadband: 0.05) } ?? nil)
                    Divider().overlay(NathanStyle.line).padding(.horizontal, 12)
                    bodyStat("Body fat", value: bf.latest.map { NathanFormat.one(Self.pct($0.value)) }, unit: "%",
                             delta: bf.change.map { NathanDelta.make(current: Self.pct($0), baseline: 0, better: .down,
                                                                    format: NathanFormat.one, deadband: 0.05) } ?? nil)
                    Divider().overlay(NathanStyle.line).padding(.horizontal, 12)
                    bodyStat("Lean mass", value: lm.latest.map { massText($0.value) }, unit: unit,
                             delta: lm.change.map { NathanDelta.make(current: $0, baseline: 0, better: .up,
                                                                    format: { massText($0) }, deadband: 0.05) } ?? nil)
                }
            }
        }
    }

    /// Apple Health stores body fat as a fraction on some imports and a percent on others.
    static func pct(_ v: Double) -> Double { v <= 1 ? v * 100 : v }

    private func bodyStat(_ label: String, value: String?, unit: String, delta: NathanDelta?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, design: .rounded)).foregroundStyle(NathanStyle.text3)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value ?? "—").font(NathanStyle.number(26)).foregroundStyle(NathanStyle.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if value != nil { Text(unit).font(.system(size: 12, design: .rounded)).foregroundStyle(NathanStyle.text3) }
            }
            Text(delta?.text ?? " ").font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(delta?.color ?? NathanStyle.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func shortDay(_ key: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: key) else { return key }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: Lift

    private var liftRow: some View {
        Button { selectTab(NathanTab.lift) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEXT LIFT · \(Self.nextTrainDay().uppercased())")
                        .font(NathanStyle.label).tracking(0.6).foregroundStyle(NathanStyle.text3)
                    Text("Open your workouts").font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(NathanStyle.text)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(NathanStyle.text3)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(NathanStyle.card, in: RoundedRectangle(cornerRadius: NathanStyle.tileRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NathanStyle.tileRadius, style: .continuous).stroke(NathanStyle.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Tue · Thu · Sat schedule (Nathan's split).
    static func nextTrainDay(from date: Date = Date()) -> String {
        let cal = Calendar.current
        let train: Set<Int> = [3, 5, 7] // Calendar weekday: 1 = Sunday
        for k in 0..<7 {
            guard let d = cal.date(byAdding: .day, value: k, to: date) else { continue }
            if train.contains(cal.component(.weekday, from: d)) {
                return k == 0 ? "Today" : d.formatted(.dateTime.weekday(.wide))
            }
        }
        return "—"
    }

    // MARK: Load

    private func load() async {
        func dict(_ s: [(day: String, value: Double)]) -> [String: Double] {
            Dictionary(s.map { ($0.day, $0.value) }, uniquingKeysWith: { _, b in b })
        }
        sleepPerf = dict(await repo.exploreSeries(key: "sleep_performance", source: "my-whoop", days: 45))
        sleepNeed = dict(await repo.exploreSeries(key: "sleep_need_min", source: "my-whoop", days: 10))
        weight = await repo.series(key: "weight", source: "apple-health", days: 400)
        bodyFat = await repo.series(key: "body_fat", source: "apple-health", days: 400)
        lean = await repo.series(key: "lean_mass", source: "apple-health", days: 400)
        appleSteps = dict(await repo.series(key: "steps", source: "apple-health", days: 10))
        appleKcal = dict(await repo.series(key: "active_kcal", source: "apple-health", days: 10))
        eaten = dict(await repo.series(key: "calories_in", source: "nutrition-csv", days: 10))
    }
}

/// Strap connection + battery pill. Its own view so the 1 Hz live-state updates never re-render Today.
struct NathanStrapPill: View {
    @EnvironmentObject var live: LiveState
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(live.connected ? NathanStyle.good : NathanStyle.text3).frame(width: 7, height: 7)
            Text(live.batteryPct.map { "WHOOP · \(Int($0.rounded()))%" } ?? (live.connected ? "WHOOP" : "Not connected"))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(NathanStyle.text2)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(NathanStyle.card, in: Capsule())
        .overlay(Capsule().stroke(NathanStyle.line, lineWidth: 1))
    }
}
