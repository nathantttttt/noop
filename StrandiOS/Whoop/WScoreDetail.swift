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
    let day: String

    private var isToday: Bool { day == data.todayKey }
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
        .wPage(title: title)
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
        return WDial(fraction: fraction, color: dialColor, size: 258, lineWidth: 16) {
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
    }

    private func compare(_ m: WMetric) -> (String?, Bool?) {
        guard let v = data.value(m, day) else { return (nil, nil) }
        var good: Bool?
        if let b = data.baseline(m, before: day), m.better != .neither {
            let diff = v - b
            if abs(diff) > max(abs(b) * 0.03, 0.0001) { good = m.better == .up ? diff > 0 : diff < 0 }
        }
        let unit = m.unit == "%" ? "%" : (m.isDuration || m.unit.isEmpty || m.unit == "Steps" ? "" : " " + m.unit)
        return ((m.isDuration ? WFmt.hm(v) : m.format(v)) + unit, good)
    }

    private var rows: [Row] {
        func row(_ m: WMetric, _ title: String? = nil, icon: String? = nil) -> Row {
            let (v, g) = compare(m)
            return Row(id: m.rawValue, icon: icon ?? m.icon, title: title ?? m.title, value: v, good: g)
        }
        switch score {
        case .sleep:
            return [row(.hoursVsNeededPct, "Hours vs. Needed"), row(.sleepConsistency), row(.sleepEfficiency),
                    row(.restorative, "Restorative Sleep")]
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
                        if let g = r.good {
                            Image(systemName: g ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(.system(size: 9)).foregroundStyle(g ? W.mint : W.orange)
                        }
                        Text(r.value ?? "--").font(W.num(20)).foregroundStyle(r.value == nil ? W.text3 : W.text)
                    }
                    .padding(.vertical, 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < rows.count - 1 { Rectangle().fill(W.hairline).frame(height: 1) }
            }
            if score != .sleep {
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

/// The Withings mat next to the strap for the same night.
struct WMatCompareCard: View {
    @EnvironmentObject var data: WhoopData
    @EnvironmentObject var repo: Repository
    let day: String
    @State private var matStart: Double?
    @State private var matEnd: Double?

    var body: some View {
        let mat = data.value(.matSleep, day)
        let strap = data.value(.hoursVsNeeded, day)
        VStack(spacing: 0) {
            if mat != nil || matStart != nil {
                WCard {
                    VStack(alignment: .leading, spacing: 14) {
                        WCardHeader(title: "Strap vs. Sleep Mat")
                        HStack(alignment: .top) {
                            col("STRAP", strap.map(WFmt.hm) ?? "-:--", W.hours)
                            Spacer()
                            col("SLEEP MAT", mat.map(WFmt.hm) ?? "-:--", W.mint)
                            Spacer()
                            if let mat, let strap {
                                let d = strap - mat
                                col("DIFFERENCE", (d >= 0 ? "+" : "−") + WFmt.hm(abs(d)), W.text2)
                            }
                        }
                        if let s = matStart, let e = matEnd {
                            Text("Mat: first sleep \(WFmt.clock(Int(s))), up at \(WFmt.clock(Int(e)))")
                                .font(W.body(15)).foregroundStyle(W.text3)
                        }
                    }
                }
            }
        }
        .task(id: data.loadedSeq) {
            matStart = await repo.series(key: "ext_sleep_start", source: "apple-health", days: 30).last { $0.day == day }?.value
            matEnd = await repo.series(key: "ext_sleep_end", source: "apple-health", days: 30).last { $0.day == day }?.value
        }
    }

    private func col(_ label: String, _ value: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(W.num(30)).foregroundStyle(c)
            Text(label).font(W.caps(12)).tracking(1.2).foregroundStyle(W.text3)
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
