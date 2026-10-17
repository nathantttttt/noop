//  WScoreDetail.swift
//  Nathan's build: the page behind each Home dial (Sleep · Recovery · Strain), laid out like WHOOP's:
//  the big dial, a callout of what drove it (each value against the last 30 days), the night or day in
//  detail, then a stack of weekly trend cards that each open the full Trend View.

import SwiftUI
import Charts
import WhoopStore

enum WScore: String, Hashable { case sleep, recovery, strain }

enum WRoute: Hashable {
    case score(WScore, String)          // score + day key
    case trend(WMetric, WPeriod)
    case activity(Int)                  // workout startTs
    case journal
    case healthMonitor
    case stress
    case healthspan
    case leanFat
}

/// Destinations for the WHOOP-style stack, registered once at the root of each tab that uses them.
struct WRouteDestinations: ViewModifier {
    @EnvironmentObject var data: WhoopData
    func body(content: Content) -> some View {
        content.navigationDestination(for: WRoute.self) { route in
            switch route {
            case .score(let s, let day): WScoreDetail(score: s, day: day)
            case .trend(let m, let p): WTrendView(metric: m, period: p)
            case .activity(let ts):
                if let w = data.workouts.first(where: { $0.startTs == ts }) {
                    NathanActivityDetail(workout: w).wPage(title: "Activity")
                }
            case .journal:
                WJournalImpacts()
            case .healthMonitor:
                WHealthMonitorView()
            case .stress:
                WStressView()
            case .healthspan:
                WHealthspanView()
            case .leanFat:
                WLeanFatView()
            }
        }
    }
}

extension View {
    func wRoutes() -> some View { modifier(WRouteDestinations()) }
}

struct WScoreDetail: View {
    @EnvironmentObject var data: WhoopData
    @EnvironmentObject var repo: Repository
    let score: WScore
    @State private var day: String

    init(score: WScore, day: String) {
        self.score = score
        _day = State(initialValue: day)
    }

    private var isToday: Bool { day == data.todayKey }

    private func step(_ by: Int) {
        guard let d = WFmt.dayDate(day), let n = Calendar.current.date(byAdding: .day, value: by, to: d) else { return }
        let k = Repository.localDayKey(n)
        guard k <= data.todayKey else { return }
        WHaptics.select()
        withAnimation(.easeInOut(duration: 0.2)) { day = k }
    }
    private var title: String {
        guard !isToday, let d = WFmt.dayDate(day) else { return "Today" }
        return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dial.frame(maxWidth: .infinity).padding(.top, 6)
                callout
                switch score {
                case .sleep: sleepSection
                case .recovery: recoverySection
                case .strain: strainSection
                }
                WSectionTitle(title: "Weekly Trends")
                ForEach(trendMetrics) { m in
                    NavigationLink(value: WRoute.trend(m, .week)) {
                        WCard {
                            VStack(alignment: .leading, spacing: 14) {
                                WCardHeader(title: m.title, chevron: true)
                                if m.chart == .dualNeed {
                                    HStack(spacing: 16) { Spacer(); WLegend(color: W.hours, label: "Hours of sleep", ring: true); WLegend(color: W.mint, label: "Sleep needed", ring: true) }
                                } else if m.chart == .restorative {
                                    HStack(spacing: 16) { Spacer(); WLegend(color: W.deep, label: "Deep sleep"); WLegend(color: W.rem, label: "REM sleep") }
                                }
                                WTrendChart(metric: m, period: .week, height: 230)
                            }
                        }
                    }
                    .buttonStyle(WPressStyle())
                }
            }
            .padding(.horizontal, W.margin)
            .padding(.bottom, 40)
        }
        .wPage()
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 16) {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    Text(title.uppercased()).font(W.caps(15)).tracking(1.6).frame(minWidth: 110)
                    Button { step(1) } label: {
                        Image(systemName: "chevron.right").foregroundStyle(isToday ? W.text3.opacity(0.5) : W.text)
                    }
                    .disabled(isToday)
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(W.text)
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Dial

    private var dialValue: Double? {
        switch score {
        case .sleep: data.value(.sleepPerformance, day) ?? data.value(.hoursVsNeededPct, day).map { min(100, $0) }
        case .recovery: data.value(.recovery, day)
        case .strain: data.value(.strain, day)
        }
    }

    private var dialColor: Color {
        switch score {
        case .sleep: W.sleep
        case .recovery: W.recoveryColor(dialValue)
        case .strain: W.strain
        }
    }

    private var dial: some View {
        let v = dialValue
        let fraction = v.map { score == .strain ? $0 / 21 : $0 / 100 }
        return WDial(fraction: fraction, color: dialColor, size: 258, lineWidth: 16,
                     target: score == .strain ? data.strainTarget(day) : nil) {
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(v.map { score == .strain ? WFmt.one($0) : WFmt.int($0) } ?? "--")
                        .font(W.num(68, .heavy)).foregroundStyle(W.text)
                    if score != .strain {
                        Text("%").font(W.num(40, .heavy)).foregroundStyle(W.text)
                    }
                }
                Text(score == .sleep ? "SLEEP\nPERFORMANCE" : score.rawValue.uppercased())
                    .font(W.caps(16)).tracking(1.8).multilineTextAlignment(.center).foregroundStyle(W.text)
                if score == .recovery, v == nil, isToday, let n = WhoopData.recoveryCalibration(repo) {
                    Text("CALIBRATING · \(n) OF \(WhoopData.recoverySeedNights) NIGHTS")
                        .font(W.caps(12)).tracking(1).foregroundStyle(W.text3)
                }
            }
        }
    }

    // MARK: Callout

    private struct Row: Identifiable {
        let id: String
        let icon: String
        let title: String
        let value: String?
        let good: Bool?
        var up: Bool? = nil        // which way it moved vs. the 30-day baseline
    }

    private func compare(_ m: WMetric) -> (String?, Bool?, Bool?) {
        guard let v = data.value(m, day) else { return (nil, nil, nil) }
        var good: Bool?, up: Bool?
        if let b = data.baseline(m, before: day) {
            let diff = v - b
            if abs(diff) > max(abs(b) * 0.03, 0.0001) {
                up = diff > 0
                if m.better != .neither { good = m.better == .up ? diff > 0 : diff < 0 }
            }
        }
        let unit = m.unit == "%" ? "%" : (m.isDuration || m.unit.isEmpty || m.unit == "Steps" ? "" : " " + m.unit)
        return ((m.isDuration ? WFmt.hm(v) : m.format(v)) + unit, good, up)
    }

    private var rows: [Row] {
        func row(_ m: WMetric, _ title: String? = nil, icon: String? = nil) -> Row {
            let (v, g, u) = compare(m)
            return Row(id: m.rawValue, icon: icon ?? m.icon, title: title ?? m.title, value: v, good: g, up: u)
        }
        switch score {
        case .sleep:
            return [row(.hoursVsNeededPct, "Hours vs. Needed"), row(.restorative, "Restorative Sleep"),
                    row(.sleepEfficiency), row(.sleepConsistency), row(.hrv), row(.rhr)]
        case .recovery:
            return [row(.hrv), row(.rhr), row(.respRate), row(.sleepPerformance)]
        case .strain:
            return [row(.zones13, "Heart Rate Zones 1-3"), row(.zones45, "Heart Rate Zones 4-5"),
                    row(.strengthTime), row(.steps)]
        }
    }

    private var callout: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                NavigationLink(value: WRoute.trend(WMetric(rawValue: r.id) ?? .recovery, .month)) {
                    HStack(spacing: 14) {
                        Image(systemName: r.icon).font(.system(size: 18, weight: .light)).foregroundStyle(W.text2)
                            .frame(width: 26)
                        Text(r.title.uppercased()).font(W.caps(14)).tracking(1.3).foregroundStyle(W.text)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Spacer(minLength: 6)
                        if let u = r.up {
                            // Direction is the actual move; colour is whether that move is good for this
                            // metric (resting HR rising is an orange UP arrow, HRV falling an orange DOWN).
                            Image(systemName: u ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(.system(size: 9)).foregroundStyle(r.good == nil ? W.text3 : (r.good! ? W.mint : W.orange))
                        }
                        Text(r.value ?? "--").font(W.num(20)).foregroundStyle(r.value == nil ? W.text3 : W.text)
                    }
                    .padding(.vertical, 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < rows.count - 1 { Rectangle().fill(W.hairline).frame(height: 1) }
            }
            Group {
                HStack(spacing: 8) {
                    HStack(spacing: 1) {
                        Image(systemName: "arrowtriangle.up.fill").foregroundStyle(W.mint)
                        Image(systemName: "arrowtriangle.down.fill").foregroundStyle(W.orange)
                    }
                    .font(.system(size: 8))
                    Text(isToday ? "Today" : "This day").font(W.body(16, .semibold)).foregroundColor(W.text)
                    + Text(" vs. last 30 days").font(W.body(16)).foregroundColor(W.text2)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(W.segTrack.opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.bottom, 14)
            }
        }
        .padding(.horizontal, 20)
        .background(
            LinearGradient(colors: [W.hex(0x30353A), W.hex(0x1D2124)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous))
        .overlay(alignment: .top) {
            Triangle().fill(W.hex(0x30353A)).frame(width: 26, height: 12).offset(y: -11)
        }
        .padding(.top, 6)
    }

    // MARK: Sleep

    private var night: CachedSleepSession? {
        repo.sleeps.filter { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.endTs))) == day }
            .max { $0.endTs < $1.endTs }
    }

    @ViewBuilder private var sleepSection: some View {
        WSectionTitle(title: "Last Night's Sleep", subtitle: nil)
        Text(isToday ? "Today" : "This night").font(W.body(16, .semibold)).foregroundColor(W.text)
            + Text(" vs. prior 30 days").font(W.body(16)).foregroundColor(W.text3)
        statCard(.hoursVsNeeded, title: "Hours of Sleep")
        needCard
        statCard(.sleepConsistency)
        statCard(.sleepEfficiency)
        statCard(.timeInBed)
        if let night { WSleepNightCard(night: night, day: day) }
        WMatCompareCard(day: day)
    }

    private var needCard: some View {
        let asleep = data.value(.hoursVsNeeded, day), need = data.need[day]
        return WCard {
            VStack(alignment: .leading, spacing: 12) {
                WCardHeader(title: "Hours vs. Needed", info: true)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(asleep.map(WFmt.hm) ?? "-:--").font(W.num(34)).foregroundStyle(W.hours)
                    Text("/").font(W.num(26)).foregroundStyle(W.text3)
                    Text(need.map(WFmt.hm) ?? "-:--").font(W.num(34)).foregroundStyle(W.mint)
                }
                if let asleep, let need, need > 0 {
                    WCompareBar(value: asleep, reference: need, color: W.hours, refColor: W.mint,
                                valueLabel: "SLEPT", refLabel: "NEEDED")
                }
            }
        }
    }

    private func statCard(_ m: WMetric, title: String? = nil) -> some View {
        let v = data.value(m, day)
        let base = data.baseline(m, before: day)
        return WCard {
            VStack(alignment: .leading, spacing: 12) {
                WCardHeader(title: title ?? m.title, info: true)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(v.map { m.isDuration ? WFmt.hm($0) : m.format($0) } ?? (m.unit == "%" ? "--%" : "-:--"))
                        .font(W.num(34)).foregroundStyle(W.text)
                    if v != nil && m.unit == "%" { Text("%").font(W.num(24)).foregroundStyle(W.text) }
                }
                if let v, let base {
                    WCompareBar(value: v, reference: base, color: W.text, refColor: W.text3,
                                valueLabel: isToday ? "TODAY" : "THIS NIGHT", refLabel: "30-DAY AVG",
                                format: { m.isDuration ? WFmt.hm($0) : m.format($0) + (m.unit == "%" ? "%" : "") },
                                better: m.better)
                }
            }
        }
    }

    // MARK: Recovery

    @ViewBuilder private var recoverySection: some View {
        NavigationLink(value: WRoute.journal) {
            WCard(padding: 22) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your behavior insights").font(W.body(20, .semibold)).foregroundStyle(W.text)
                        Text("See which journal habits raise or lower your recovery, HRV and resting heart rate.")
                            .font(W.body(16)).foregroundStyle(W.text2).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Text("SEE YOUR IMPACTS").font(W.caps(14)).tracking(1.5)
                            Image(systemName: "arrow.right").font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(W.lineBlue)
                        .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.seal").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(W.purple.opacity(0.9))
                }
            }
        }
        .buttonStyle(WPressStyle())
    }

    // MARK: Strain

    @ViewBuilder private var strainSection: some View {
        let recovery = data.value(.recovery, day)
        if let range = CoupledView.optimalStrainRange(recovery: recovery) {
            let s = data.value(.strain, day) ?? 0
            let low = Double(range.lowerBound), high = Double(range.upperBound)
            WCard {
                VStack(alignment: .leading, spacing: 12) {
                    WCardHeader(title: "Optimal Strain")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(range.lowerBound) – \(range.upperBound)").font(W.num(34)).foregroundStyle(W.strain)
                        Text("for today's recovery").font(W.body(15)).foregroundStyle(W.text3)
                    }
                    GeometryReader { g in
                        let w = g.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule().fill(W.strain.opacity(0.30))
                                .frame(width: w * (high - low) / 21).offset(x: w * low / 21)
                            Capsule().fill(W.strain).frame(width: max(6, w * min(1, s / 21)))
                        }
                    }
                    .frame(height: 10)
                    Text(s < low ? "\(WFmt.one(low - s)) more strain reaches your target."
                         : s > high ? "You're above the optimal range. Recovery comes first now." : "You're in your optimal range.")
                        .font(W.body(15)).foregroundStyle(W.text2)
                }
            }
        }
        let todays = data.workouts.filter { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.startTs))) == day }
        if !todays.isEmpty {
            WSectionTitle(title: "Activities")
            ForEach(todays, id: \.startTs) { w in
                NavigationLink(value: WRoute.activity(w.startTs)) { WActivityRow(workout: w) }
                    .buttonStyle(WPressStyle())
            }
        }
    }

    private var trendMetrics: [WMetric] {
        switch score {
        case .sleep: [.sleepPerformance, .hoursVsNeeded, .hoursVsNeededPct, .restorative, .sleepConsistency,
                      .timeInBed, .sleepEfficiency, .sleepDebt]
        case .recovery: [.recovery, .hrv, .rhr, .respRate, .sleepPerformance]
        case .strain: [.strain, .zones13, .zones45, .steps, .calories, .strengthTime]
        }
    }
}

/// Small up-pointing triangle for the callout's pointer.
struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Two stacked bars: this value against a reference (30-day average, or sleep need).
struct WCompareBar: View {
    let value: Double
    let reference: Double
    let color: Color
    let refColor: Color
    var valueLabel = "TODAY"
    var refLabel = "30-DAY AVG"
    var format: (Double) -> String = { WFmt.hm($0) }
    var better: WBetter = .neither

    var body: some View {
        let top = max(value, reference, 0.0001) * 1.08
        let diffGood: Bool? = better == .neither ? nil : (better == .up ? value >= reference : value <= reference)
        VStack(spacing: 8) {
            bar(valueLabel, value, top, diffGood == nil ? color : (diffGood! ? W.mint : W.orange))
            bar(refLabel, reference, top, refColor)
        }
    }

    private func bar(_ label: String, _ v: Double, _ top: Double, _ c: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(W.caps(11)).tracking(1.1).foregroundStyle(W.text3).frame(width: 84, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.07))
                    RoundedRectangle(cornerRadius: 2).fill(c).frame(width: max(3, g.size.width * v / top))
                }
            }
            .frame(height: 8)
            Text(format(v)).font(W.num(15)).foregroundStyle(W.text2).frame(width: 52, alignment: .trailing)
        }
    }
}

/// Last night in detail: heart rate you can drag across, then each stage against its usual range.
struct WSleepNightCard: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var data: WhoopData
    let night: CachedSleepSession
    let day: String
    @State private var hr: [NathanHRPoint] = []

    private struct Stages { var awake = 0.0, light = 0.0, deep = 0.0, rem = 0.0
        var inBed: Double { awake + light + deep + rem } }

    private var stages: Stages? {
        if let d = SleepView.decodeSegments(night.stagesJSON, sessionStart: night.effectiveStartTs) {
            return Stages(awake: d.stages.awake, light: d.stages.light, deep: d.stages.deep, rem: d.stages.rem)
        }
        guard let deep = data.deep[day], let rem = data.rem[day], let asleep = data.value(.hoursVsNeeded, day) else { return nil }
        let inBed = Double(max(0, night.endTs - night.effectiveStartTs)) / 60
        return Stages(awake: max(0, inBed - asleep), light: max(0, asleep - deep - rem), deep: deep, rem: rem)
    }

    var body: some View {
        WCard {
            VStack(alignment: .leading, spacing: 16) {
                WCardHeader(title: "Sleep Stages")
                if hr.count >= 4 {
                    NathanScrubHRChart(points: hr, height: 170, color: W.hours, restingLine: night.restingHr, markLow: true)
                    HStack {
                        Text(WFmt.clock(night.effectiveStartTs)); Spacer(); Text(WFmt.clock(night.endTs))
                    }
                    .font(W.caps(12, .semibold)).foregroundStyle(W.text3)
                }
                if let st = stages, st.inBed > 0 {
                    stageRow("Awake", st.awake, st.inBed, W.hex(0xB9C2C9))
                    stageRow("Light", st.light, st.inBed, W.sleep)
                    stageRow("SWS (Deep)", st.deep, st.inBed, W.deep)
                    stageRow("REM", st.rem, st.inBed, W.rem)
                }
            }
        }
        .task(id: night.endTs) {
            let b = await repo.hrBuckets(from: night.effectiveStartTs, to: night.endTs, bucketSeconds: 60)
            hr = b.filter { $0.bpm > 25 }.map { NathanHRPoint(ts: $0.ts, bpm: $0.bpm) }
        }
    }

    private func stageRow(_ name: String, _ m: Double, _ total: Double, _ c: Color) -> some View {
        let pct = m / total * 100
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(name.uppercased()).font(W.caps(13)).tracking(1.2).foregroundStyle(W.text)
                Text("\(Int(pct.rounded()))%").font(W.caps(13)).foregroundStyle(c)
                Spacer()
                Text(WFmt.hm(m)).font(W.num(18)).foregroundStyle(W.text)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.07))
                    RoundedRectangle(cornerRadius: 2).fill(c).frame(width: max(3, g.size.width * pct / 100))
                }
            }
            .frame(height: 10)
        }
    }
}

/// The Withings mat next to the strap: each night's sleep onset and wake-up from both, how far apart
/// they were, and how often they agree. Strap nights come from NOOP's own sleep detection; mat nights
/// from the Health Shortcut (first real sleep and last wake, Awake samples filtered out).
struct WMatCompareCard: View {
    @EnvironmentObject var data: WhoopData
    @EnvironmentObject var repo: Repository
    let day: String
    @State private var matStart: [String: Double] = [:]
    @State private var matEnd: [String: Double] = [:]
    @State private var which = 0     // 0 onset, 1 wake

    private struct Night: Identifiable {
        let id: String
        let date: Date
        let strapOn: Double?, strapOff: Double?, matOn: Double?, matOff: Double?   // unix seconds
    }

    private var nights: [Night] {
        var strap: [String: (Double, Double)] = [:]
        for s in repo.sleeps {
            let k = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(s.endTs)))
            if let have = strap[k], have.1 - have.0 > Double(s.endTs - s.effectiveStartTs) { continue }
            strap[k] = (Double(s.effectiveStartTs), Double(s.endTs))
        }
        let keys = Set(strap.keys).union(matStart.keys).filter { $0 <= day }.sorted().suffix(14)
        return keys.compactMap { k in
            guard let d = WFmt.dayDate(k) else { return nil }
            return Night(id: k, date: d, strapOn: strap[k]?.0, strapOff: strap[k]?.1, matOn: matStart[k], matOff: matEnd[k])
        }
    }

    /// Minutes after 6 PM of the night, so 11 PM and 1 AM sit two hours apart on one axis.
    private static func clockMinutes(_ ts: Double) -> Double {
        let d = Date(timeIntervalSince1970: ts)
        let c = Calendar.current
        let m = c.component(.hour, from: d) * 60 + c.component(.minute, from: d)
        return Double((m - 18 * 60 + 1440) % 1440)
    }

    private static func clockLabel(_ minutesAfter6pm: Double) -> String {
        let m = (Int(minutesAfter6pm.rounded()) + 18 * 60) % 1440
        var c = DateComponents(); c.hour = m / 60; c.minute = m % 60
        return Calendar.current.date(from: c)?.formatted(date: .omitted, time: .shortened) ?? ""
    }

    var body: some View {
        let ns = nights
        let both = ns.filter { which == 0 ? ($0.strapOn != nil && $0.matOn != nil) : ($0.strapOff != nil && $0.matOff != nil) }
        let diffs = both.map { n -> Double in
            which == 0 ? abs(n.strapOn! - n.matOn!) / 60 : abs(n.strapOff! - n.matOff!) / 60
        }
        let agree = diffs.filter { $0 <= 30 }.count
        let tonight = ns.last { $0.id == day }
        VStack(spacing: 0) {
            if !matStart.isEmpty {
                WCard {
                    VStack(alignment: .leading, spacing: 14) {
                        WCardHeader(title: "Strap vs. Sleep Mat")
                        if let t = tonight {
                            HStack(alignment: .top) {
                                col("STRAP", t.strapOn, t.strapOff, W.hours)
                                Spacer()
                                col("SLEEP MAT", t.matOn, t.matOff, W.mint)
                                Spacer()
                                if let a = t.strapOn, let b = t.matOn {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(Int((abs(a - b) / 60).rounded())) min").font(W.num(24))
                                            .foregroundStyle(abs(a - b) <= 1800 ? W.mint : W.orange)
                                        Text("ONSET GAP").font(W.caps(11)).tracking(1.2).foregroundStyle(W.text3)
                                    }
                                }
                            }
                        }
                        WSegmented(options: [(0, "FELL ASLEEP"), (1, "WOKE UP")], selection: $which)
                        chart(ns)
                        if !diffs.isEmpty {
                            let avg = diffs.reduce(0, +) / Double(diffs.count)
                            Text("Over \(diffs.count) night\(diffs.count == 1 ? "" : "s") with both, the \(which == 0 ? "sleep onset" : "wake time") differed by \(Int(avg.rounded())) min on average and agreed within 30 min on \(agree) of \(diffs.count).")
                                .font(W.body(15)).foregroundStyle(W.text2).fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Once a night has both a strap sleep and a mat sleep, they line up here.")
                                .font(W.body(15)).foregroundStyle(W.text3)
                        }
                    }
                }
            }
        }
        .task(id: data.loadedSeq) {
            func dict(_ s: [(day: String, value: Double)]) -> [String: Double] {
                Dictionary(s.map { ($0.day, $0.value) }, uniquingKeysWith: { _, b in b })
            }
            matStart = dict(await repo.series(key: "ext_sleep_start", source: "apple-health", days: 60))
            matEnd = dict(await repo.series(key: "ext_sleep_end", source: "apple-health", days: 60))
        }
    }

    private struct Gap: Identifiable { let id: String; let date: Date; let minutes: Double }

    /// Minutes the mat reading sits after (+) or before (−) the strap's, per night with both.
    private func gaps(_ ns: [Night]) -> [Gap] {
        ns.compactMap { n in
            let s = which == 0 ? n.strapOn : n.strapOff
            let m = which == 0 ? n.matOn : n.matOff
            guard let s, let m else { return nil }
            return Gap(id: n.id, date: n.date, minutes: (m - s) / 60)
        }
    }

    @ViewBuilder private func chart(_ ns: [Night]) -> some View {
        let gs = gaps(ns)
        if gs.isEmpty {
            WNoData(height: 140)
        } else {
            let top = max(30, gs.map { abs($0.minutes) }.max() ?? 30) * 1.3
            Chart {
                RectangleMark(xStart: .value("A", gs.first!.date), xEnd: .value("B", gs.last!.date.addingTimeInterval(86_400)),
                              yStart: .value("Lo", -30), yEnd: .value("Hi", 30))
                    .foregroundStyle(W.mint.opacity(0.08))
                RuleMark(y: .value("Zero", 0)).foregroundStyle(Color.white.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(gs) { g in
                    BarMark(x: .value("Night", g.date, unit: .day), yStart: .value("0", 0), yEnd: .value("Gap", g.minutes),
                            width: .ratio(0.5))
                        .foregroundStyle(abs(g.minutes) <= 30 ? W.mint : W.orange)
                        .cornerRadius(3)
                        .annotation(position: g.minutes >= 0 ? .top : .bottom, spacing: 3) {
                            Text("\(g.minutes >= 0 ? "+" : "−")\(Int(abs(g.minutes).rounded()))m")
                                .font(W.num(13)).foregroundStyle(abs(g.minutes) <= 30 ? W.mint : W.orange)
                        }
                }
            }
            .chartYScale(domain: -top...top)
            .chartYAxis {
                AxisMarks(position: .leading, values: [-60.0, -30, 0, 30, 60].filter { abs($0) < top }) { v in
                    AxisGridLine().foregroundStyle(W.grid)
                    AxisValueLabel { if let m = v.as(Double.self) { Text(m == 0 ? "0" : "\(m > 0 ? "+" : "")\(Int(m))m") } }
                        .font(W.caps(11, .semibold)).foregroundStyle(W.text3)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, gs.count / 6))) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated)).font(W.caps(11, .semibold)).foregroundStyle(W.text3)
                }
            }
            .frame(height: 190)
            Text("Bars show how many minutes the mat's \(which == 0 ? "sleep onset" : "wake-up") came after (+) or before (−) the strap's. The green band is within 30 minutes.")
                .font(W.body(13)).foregroundStyle(W.text3).fixedSize(horizontal: false, vertical: true)
            nightTable(ns)
        }
    }

    private func nightTable(_ ns: [Night]) -> some View {
        let rows = Array(ns.reversed().prefix(7))
        return VStack(spacing: 0) {
            HStack {
                Text("NIGHT").frame(maxWidth: .infinity, alignment: .leading)
                Text("STRAP").frame(width: 76, alignment: .trailing)
                Text("MAT").frame(width: 76, alignment: .trailing)
                Text("GAP").frame(width: 52, alignment: .trailing)
            }
            .font(W.caps(11)).tracking(1).foregroundStyle(W.text3).padding(.vertical, 8)
            ForEach(rows) { n in
                let s = which == 0 ? n.strapOn : n.strapOff
                let m = which == 0 ? n.matOn : n.matOff
                Rectangle().fill(W.hairline).frame(height: 1)
                HStack {
                    Text(n.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).frame(maxWidth: .infinity, alignment: .leading)
                    Text(s.map { WFmt.clock(Int($0)) } ?? "--").foregroundStyle(W.hours).frame(width: 76, alignment: .trailing)
                    Text(m.map { WFmt.clock(Int($0)) } ?? "--").foregroundStyle(W.mint).frame(width: 76, alignment: .trailing)
                    if let s, let m {
                        let d = (m - s) / 60
                        Text("\(Int(abs(d).rounded()))m").foregroundStyle(abs(d) <= 30 ? W.mint : W.orange).frame(width: 52, alignment: .trailing)
                    } else {
                        Text("--").foregroundStyle(W.text3).frame(width: 52, alignment: .trailing)
                    }
                }
                .font(W.num(14)).foregroundStyle(W.text).padding(.vertical, 10)
            }
        }
    }

    private func col(_ label: String, _ on: Double?, _ off: Double?, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(on.map { WFmt.clock(Int($0)) } ?? "--").font(W.num(20)).foregroundStyle(c)
            Text(off.map { "→ " + WFmt.clock(Int($0)) } ?? " ").font(W.body(14)).foregroundStyle(W.text2)
            Text(label).font(W.caps(11)).tracking(1.2).foregroundStyle(W.text3)
        }
    }
}

/// One activity in the WHOOP list style: strain badge, sport, time and duration.
struct WActivityRow: View {
    let workout: WorkoutRow
    var body: some View {
        let strain = workout.strain.map { UnitFormatter.effortValue($0, scale: .whoop) }
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(W.strain.opacity(0.18))
                VStack(spacing: 0) {
                    Image(systemName: NathanActivity.icon(workout.sport)).font(.system(size: 15, weight: .semibold))
                    if let strain { Text(WFmt.one(strain)).font(W.num(14)) }
                }
                .foregroundStyle(W.strain)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text((NathanActivity.isLift(workout) ? (workout.notes?.isEmpty == false ? workout.notes! : "Strength Training")
                      : WorkoutSource.displaySport(workout.sport)).uppercased())
                    .font(W.caps(15)).tracking(1.2).foregroundStyle(W.text).lineLimit(1)
                Text(WFmt.clock(workout.startTs) + " – " + WFmt.clock(workout.endTs))
                    .font(W.body(15)).foregroundStyle(W.text3)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 15, weight: .medium)).foregroundStyle(W.text3)
        }
        .padding(14)
        .background(W.row, in: RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous))
    }
}
