//  NathanSleepView.swift
//  Nathan's Sleep: night picker, sleep-performance ring (coloured by threshold), asleep time and window,
//  HRV and resting HR, then a WHOOP-style panel — hours of sleep and restorative sleep against your
//  usual, a one-line read of the night, a heart-rate graph you can drag across, and per-stage bars with
//  your typical range hazed behind them. Sleep debt and bedtime consistency close it out.

import SwiftUI
import Charts
import StrandDesign
import WhoopStore

struct NathanSleepView: View {
    @EnvironmentObject var repo: Repository

    @State private var index = 0                 // 0 = newest night
    @State private var perf: [String: Double] = [:]
    @State private var need: [String: Double] = [:]
    @State private var debt: [String: Double] = [:]
    @State private var hr: [NathanHRPoint] = []
    @State private var extStart: [String: Double] = [:]
    @State private var extEnd: [String: Double] = [:]
    @State private var extAsleep: [String: Double] = [:]

    /// Newest first, one night per wake day (the dashboard's own merge).
    private var nights: [CachedSleepSession] { repo.sleeps.sorted { $0.endTs > $1.endTs } }
    private var night: CachedSleepSession? { nights.indices.contains(index) ? nights[index] : nil }
    private var wakeDay: String? { night.map { Self.wakeDay($0) } }
    private var dayRow: DailyMetric? { wakeDay.flatMap { d in repo.days.last(where: { $0.day == d }) } }

    static func wakeDay(_ s: CachedSleepSession) -> String {
        Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(s.endTs)))
    }

    /// One night's stage minutes. Prefers the decoded hypnogram, falls back to the day's totals.
    struct NightStages {
        var awake: Double, light: Double, deep: Double, rem: Double
        var inBed: Double { awake + light + deep + rem }
        var asleep: Double { light + deep + rem }
        var restorative: Double { deep + rem }
        func pct(_ m: Double) -> Double { inBed > 0 ? m / inBed * 100 : 0 }
    }

    private func stages(for s: CachedSleepSession) -> NightStages? {
        if let d = SleepView.decodeSegments(s.stagesJSON, sessionStart: s.effectiveStartTs) {
            return NightStages(awake: d.stages.awake, light: d.stages.light, deep: d.stages.deep, rem: d.stages.rem)
        }
        let day = Self.wakeDay(s)
        guard let row = repo.days.last(where: { $0.day == day }),
              let deep = row.deepMin, let rem = row.remMin, let light = row.lightMin else { return nil }
        let inBed = Double(max(0, s.endTs - s.effectiveStartTs)) / 60
        return NightStages(awake: max(0, inBed - deep - rem - light), light: light, deep: deep, rem: rem)
    }

    /// The 30 nights before the selected one, for "usual" comparisons and typical ranges.
    private var priorStages: [NightStages] {
        guard let night else { return [] }
        return nights.filter { $0.endTs < night.endTs }.prefix(30).compactMap { stages(for: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NathanStyle.sectionGap) {
                nightPicker
                if index == 0 { withingsFallback }
                if let night {
                    let st = stages(for: night)
                    performanceCard(night: night, st: st)
                    vitals
                    whoopPanel(night: night, st: st)
                    debtAndConsistency
                } else {
                    NathanCard {
                        Text("No sleep recorded yet. Wear the strap overnight, then open NOOP in the morning so it can sync.")
                            .font(.system(size: 14, design: .rounded)).foregroundStyle(NathanStyle.text2)
                    }
                }
            }
            .padding(.horizontal, NathanStyle.page)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(NathanStyle.canvas.ignoresSafeArea())
        .refreshable { await repo.refresh() }
        .task(id: repo.refreshSeq) { await loadSeries() }
        .task(id: night?.endTs) { await loadHeartRate() }
    }

    // MARK: Night picker

    private var nightPicker: some View {
        HStack {
            roundButton("chevron.left", label: "Previous night", enabled: index + 1 < nights.count) { index += 1 }
            Spacer()
            VStack(spacing: 2) {
                Text("Sleep").font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(NathanStyle.text)
                Text(nightTitle).font(.system(size: 13, design: .rounded)).foregroundStyle(NathanStyle.text3)
            }
            Spacer()
            roundButton("chevron.right", label: "Next night", enabled: index > 0) { index -= 1 }
        }
    }

    private var nightTitle: String {
        guard let night else { return "—" }
        let start = Date(timeIntervalSince1970: TimeInterval(night.effectiveStartTs))
        return start.formatted(.dateTime.weekday(.abbreviated)) + " night · " + start.formatted(.dateTime.month(.abbreviated).day())
    }

    private func roundButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(enabled ? NathanStyle.text2 : NathanStyle.text3.opacity(0.4))
                .background(NathanStyle.card, in: Circle())
                .overlay(Circle().stroke(NathanStyle.line, lineWidth: 1))
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: Withings fallback

    /// When the strap has no night for the latest mat-recorded window, show the mat's window so the
    /// night is not simply missing. Data arrives through the Shortcuts health import.
    @ViewBuilder private var withingsFallback: some View {
        if let day = extEnd.keys.max(), let s = extStart[day], let e = extEnd[day], e > s,
           !nights.contains(where: { Self.wakeDay($0) == day }) {
            NathanCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "bed.double.fill").foregroundStyle(NathanStyle.sleepColor)
                        Text("Strap missed this night · from your sleep mat")
                            .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(NathanStyle.text)
                    }
                    if let asleep = extAsleep[day], asleep > 0 {
                        Text(NathanFormat.hmLong(asleep) + " asleep")
                            .font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(NathanStyle.text)
                    }
                    Text("\(NathanFormat.clock(Int(s))) → \(NathanFormat.clock(Int(e))) · \(NathanFormat.hmLong((e - s) / 60)) from first to last sleep")
                        .font(.system(size: 14, design: .rounded)).foregroundStyle(NathanStyle.text2)
                    Text("Wear the strap snug overnight so recovery and stages can be scored too.")
                        .font(.system(size: 12, design: .rounded)).foregroundStyle(NathanStyle.text3)
                }
            }
        }
    }

    // MARK: Ring + time

    private func performanceCard(night: CachedSleepSession, st: NightStages?) -> some View {
        let p = wakeDay.flatMap { perf[$0] }
        let n = wakeDay.flatMap { need[$0] }
        let asleep = st?.asleep ?? dayRow?.totalSleepMin
        let color = NathanStyle.sleepPerfColor(p)
        return NathanCard {
            HStack(spacing: 20) {
                NathanRing(fraction: p.map { $0 / 100 }, color: color, size: 112) {
                    VStack(spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(p.map(NathanFormat.int) ?? "—").font(NathanStyle.number(34))
                                .foregroundStyle(p == nil ? NathanStyle.text3 : color)
                            if p != nil { Text("%").font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(NathanStyle.text3) }
                        }
                        Text(NathanStyle.sleepPerfLabel(p).uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(color)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(asleep.map(NathanFormat.hmLong) ?? "—").font(NathanStyle.number(36)).foregroundStyle(NathanStyle.text)
                    if let n, let asleep {
                        let short = asleep - n
                        Text(short < -10 ? "asleep · \(NathanFormat.hmLong(-short)) under need" : "asleep · need met")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(short < -10 ? NathanStyle.bad : NathanStyle.good)
                    } else {
                        Text("asleep").font(.system(size: 13, design: .rounded)).foregroundStyle(NathanStyle.text3)
                    }
                    Text("\(NathanFormat.clock(night.effectiveStartTs)) → \(NathanFormat.clock(night.endTs))")
                        .font(.system(size: 13, design: .rounded)).foregroundStyle(NathanStyle.text2)
                }
            }
        }
    }

    // MARK: HRV + resting HR

    private var vitals: some View {
        let upTo = wakeDay ?? "9999"
        let prior = Array(repo.days.filter { $0.day < upTo }.suffix(30))
        let hrv = dayRow?.avgHrv
        let rhr = (night?.restingHr ?? dayRow?.restingHr).map(Double.init)
        let hrvD = NathanDelta.make(current: hrv, baseline: NathanFormat.mean(prior.compactMap(\.avgHrv)), better: .up,
                                    format: NathanFormat.int, suffix: " vs 30-day avg", deadband: 0.5)
        let rhrD = NathanDelta.make(current: rhr, baseline: NathanFormat.mean(prior.compactMap { $0.restingHr.map(Double.init) }),
                                    better: .down, format: NathanFormat.int, suffix: " vs 30-day avg", deadband: 0.5)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            NathanTile(label: "HRV", value: hrv.map(NathanFormat.int) ?? "—", unit: hrv == nil ? "" : "ms",
                       footer: hrvD?.text ?? "Building baseline", footerColor: hrvD?.color ?? NathanStyle.text3)
            NathanTile(label: "Resting HR", value: rhr.map(NathanFormat.int) ?? "—", unit: rhr == nil ? "" : "bpm",
                       footer: rhrD?.text ?? "Building baseline", footerColor: rhrD?.color ?? NathanStyle.text3)
        }
    }

    // MARK: WHOOP-style panel

    private func whoopPanel(night: CachedSleepSession, st: NightStages?) -> some View {
        let prior = priorStages
        let avgAsleep = NathanFormat.mean(prior.map(\.asleep))
        let avgRest = NathanFormat.mean(prior.map(\.restorative))
        return NathanCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 18) {
                    bigStat(value: st?.asleep, avg: avgAsleep, label: "HOURS OF SLEEP", color: NathanStyle.sleepColor)
                    bigStat(value: st?.restorative, avg: avgRest, label: "RESTORATIVE SLEEP", color: NathanStyle.text)
                }
                if let line = insight(st: st, prior: prior) {
                    Text(line).font(.system(size: 14, design: .rounded)).foregroundStyle(NathanStyle.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if hr.count >= 4 {
                    NathanScrubHRChart(points: hr, height: 170, color: NathanStyle.sleepColor,
                                       restingLine: night.restingHr ?? dayRow?.restingHr, markLow: true)
                    HStack {
                        Text(NathanFormat.clock(night.effectiveStartTs))
                        Spacer()
                        Text(NathanFormat.clock(night.endTs))
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(NathanStyle.text3)
                } else {
                    Text("Not enough heart-rate data for this night yet.")
                        .font(.system(size: 13, design: .rounded)).foregroundStyle(NathanStyle.text3)
                }
                if let st {
                    HStack {
                        HStack(spacing: 6) {
                            NathanTypicalSwatch().frame(width: 16, height: 10)
                            Text("TYPICAL RANGE")
                        }
                        Spacer()
                        Text("DURATION \(NathanFormat.hm(st.inBed))")
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).tracking(0.5)
                    .foregroundStyle(NathanStyle.text3)
                    VStack(spacing: 8) {
                        stageBar("AWAKE", minutes: st.awake, st: st, typical: typical(prior) { $0.pct($0.awake) }, color: StrandPalette.sleepAwake)
                        stageBar("LIGHT", minutes: st.light, st: st, typical: typical(prior) { $0.pct($0.light) }, color: StrandPalette.sleepLight)
                        stageBar("SWS (DEEP)", minutes: st.deep, st: st, typical: typical(prior) { $0.pct($0.deep) }, color: StrandPalette.sleepDeep)
                        stageBar("REM", minutes: st.rem, st: st, typical: typical(prior) { $0.pct($0.rem) }, color: StrandPalette.sleepREM)
                    }
                }
            }
        }
    }

    private func bigStat(value: Double?, avg: Double?, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value.map(NathanFormat.hm) ?? "—").font(NathanStyle.number(34)).foregroundStyle(color)
                if let value, let avg {
                    Text("\(value >= avg ? "▲" : "▼") \(NathanFormat.hm(avg))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(value >= avg ? NathanStyle.good : NathanStyle.bad)
                }
            }
            Text(label).font(.system(size: 11, weight: .bold, design: .rounded)).tracking(0.5).foregroundStyle(NathanStyle.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Middle half of the previous nights (25th to 75th percentile), as percent of time in bed.
    private func typical(_ prior: [NightStages], _ f: (NightStages) -> Double) -> ClosedRange<Double>? {
        let xs = prior.map(f).sorted()
        guard xs.count >= 5 else { return nil }
        let lo = xs[Int(Double(xs.count - 1) * 0.25)], hi = xs[Int(Double(xs.count - 1) * 0.75)]
        return lo...max(lo + 0.5, hi)
    }

    private func stageBar(_ name: String, minutes: Double, st: NightStages, typical: ClosedRange<Double>?, color: Color) -> some View {
        let pct = st.pct(minutes)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.system(size: 12, weight: .bold, design: .rounded)).tracking(0.5).foregroundStyle(NathanStyle.text)
                Text("\(Int(pct.rounded()))%").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(color)
                Spacer()
                Text(NathanFormat.hm(minutes)).font(NathanStyle.number(17)).foregroundStyle(NathanStyle.text)
            }
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    NathanHatch().fill(NathanStyle.line.opacity(0.9))
                        .background(NathanStyle.inset)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    RoundedRectangle(cornerRadius: 3).fill(color)
                        .frame(width: max(4, w * min(1, pct / 100)))
                    if let typical {
                        let x0 = w * typical.lowerBound / 100, x1 = w * typical.upperBound / 100
                        Rectangle().fill(Color.white.opacity(0.22))
                            .frame(width: max(3, x1 - x0))
                            .overlay(
                                HStack {
                                    Rectangle().fill(Color.white.opacity(0.85)).frame(width: 1.5)
                                    Spacer(minLength: 0)
                                    Rectangle().fill(Color.white.opacity(0.85)).frame(width: 1.5)
                                }
                            )
                            .offset(x: x0)
                    }
                }
            }
            .frame(height: 16)
        }
        .padding(12)
        .background(NathanStyle.inset.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(Int(pct.rounded())) percent, \(NathanFormat.hm(minutes))"
                            + (typical.map { ", usually \(Int($0.lowerBound.rounded())) to \(Int($0.upperBound.rounded())) percent" } ?? ""))
    }

    /// One plain sentence about the night, from how its stages sat against the usual ranges.
    private func insight(st: NightStages?, prior: [NightStages]) -> String? {
        guard let st, st.inBed > 0 else { return nil }
        let rem = st.pct(st.rem), deep = st.pct(st.deep)
        let remT = typical(prior) { $0.pct($0.rem) }, deepT = typical(prior) { $0.pct($0.deep) }
        if let remT, rem > remT.upperBound {
            return "\(Int(rem.rounded()))% of your time in bed was REM, more than usual. That often means your body is making up for short or broken sleep recently."
        }
        if let deepT, deep < deepT.lowerBound {
            return "Deep sleep was below your usual range. Late meals, alcohol and hard training late in the day are common causes."
        }
        if let remT, rem < remT.lowerBound {
            return "REM was lower than usual. A short night or an early wake-up trims REM first, since most of it comes late."
        }
        if let n = wakeDay.flatMap({ need[$0] }), st.asleep < n - 30 {
            return "You slept \(NathanFormat.hmLong(n - st.asleep)) less than your body needed."
        }
        if prior.count >= 5 { return "Your sleep stages were within your usual ranges." }
        return nil
    }

    // MARK: Debt + consistency

    private var debtAndConsistency: some View {
        let d = wakeDay.flatMap { debt[$0] }
        let c = consistency
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            NathanTile(label: "Sleep debt", value: d.map(NathanFormat.hm) ?? "—",
                       footer: d.map { $0 <= 30 ? "Little to none" : $0 <= 120 ? "Some catching up to do" : "Prioritise sleep tonight" } ?? " ",
                       footerColor: d.map { $0 <= 30 ? NathanStyle.good : $0 <= 120 ? NathanStyle.warn : NathanStyle.bad } ?? NathanStyle.text3)
            NathanTile(label: "Bedtime consistency", value: c.map { "\($0.score)%" } ?? "—",
                       footer: c.map { "Usually asleep by \($0.typical)" } ?? "Needs a week of nights",
                       footerColor: c.map { $0.score >= 80 ? NathanStyle.good : $0.score >= 60 ? NathanStyle.warn : NathanStyle.bad } ?? NathanStyle.text3)
        }
    }

    /// How steady the time you fall asleep is over the last 14 nights: 100% when every night starts at
    /// the same minute, falling to 0% at a 90-minute spread (standard deviation). Wake times ignored.
    private var consistency: (score: Int, typical: String)? {
        guard let night else { return nil }
        let recent = nights.filter { $0.endTs <= night.endTs }.prefix(14)
        guard recent.count >= 5 else { return nil }
        let cal = Calendar.current
        // Minutes after 18:00, so an 11 PM and a 1 AM onset sit 120 apart, not 22 hours.
        let mins: [Double] = recent.map { s in
            let d = Date(timeIntervalSince1970: TimeInterval(s.effectiveStartTs))
            let m = cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d)
            return Double((m - 18 * 60 + 1440) % 1440)
        }
        let mean = mins.reduce(0, +) / Double(mins.count)
        let sd = (mins.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(mins.count)).squareRoot()
        let score = Int(max(0, min(100, 100 - sd / 90 * 100)).rounded())
        let median = mins.sorted()[mins.count / 2]
        let clockMin = (Int(median) + 18 * 60) % 1440
        var comps = DateComponents(); comps.hour = clockMin / 60; comps.minute = clockMin % 60
        let typical = cal.date(from: comps).map { $0.formatted(.dateTime.hour().minute()) } ?? "—"
        return (score, typical)
    }

    // MARK: Load

    private func loadSeries() async {
        func dict(_ s: [(day: String, value: Double)]) -> [String: Double] {
            Dictionary(s.map { ($0.day, $0.value) }, uniquingKeysWith: { _, b in b })
        }
        perf = dict(await repo.exploreSeries(key: "sleep_performance", source: "my-whoop", days: 120))
        need = dict(await repo.exploreSeries(key: "sleep_need_min", source: "my-whoop", days: 120))
        debt = dict(await repo.exploreSeries(key: "sleep_debt_min", source: "my-whoop", days: 120))
        extStart = dict(await repo.series(key: "ext_sleep_start", source: "apple-health", days: 14))
        extEnd = dict(await repo.series(key: "ext_sleep_end", source: "apple-health", days: 14))
        extAsleep = dict(await repo.series(key: "asleep_min", source: "apple-health", days: 14))
    }

    private func loadHeartRate() async {
        guard let night else { hr = []; return }
        let buckets = await repo.hrBuckets(from: night.effectiveStartTs, to: night.endTs, bucketSeconds: 60)
        hr = buckets.filter { $0.bpm > 25 }.map { NathanHRPoint(ts: $0.ts, bpm: $0.bpm) }
    }
}

/// Diagonal hatching for the empty part of a stage bar.
struct NathanHatch: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let step: CGFloat = 6
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            p.addLine(to: CGPoint(x: x + rect.height + 1.5, y: rect.minY))
            p.addLine(to: CGPoint(x: x + 1.5, y: rect.maxY))
            p.closeSubpath()
            x += step
        }
        return p
    }
}

/// The "typical range" legend swatch.
struct NathanTypicalSwatch: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.22))
            .overlay(HStack { Rectangle().fill(Color.white.opacity(0.85)).frame(width: 1.5); Spacer(minLength: 0); Rectangle().fill(Color.white.opacity(0.85)).frame(width: 1.5) })
    }
}
