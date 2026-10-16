//  WHealth.swift
//  Nathan's build: the WHOOP-style Health tab. NOOP Age (an estimate of how old your habits make your
//  body, from nine long-term health markers) with pace of aging, then Health Monitor and Stress Monitor.
//  NOOP Age is NOOP's own transparent model, not WHOOP's: each marker's 6-month average maps linearly
//  onto a years impact between published-style "worse" and "better" ends, and the impacts add up.

import SwiftUI
import Charts
import StrandAnalytics

// MARK: - NOOP Age model

struct WAgeFactor: Identifiable {
    enum Section: String { case sleep = "Sleep", strain = "Strain", fitness = "Fitness" }
    let id: String
    let title: String
    let section: Section
    let metric: WMetric
    let weekly: Bool            // summed per week (zones, strength time)
    let worst: Double           // scale end that adds years
    let best: Double            // scale end that takes years off
    let worstYears: Double
    let bestYears: Double
    let leftLabel: String
    let rightLabel: String
    let unit: String

    /// Years added (positive) or taken off (negative) at value `v`.
    func years(_ v: Double) -> Double {
        let t = max(0, min(1, (v - worst) / (best - worst)))
        return worstYears + t * (bestYears - worstYears)
    }

    /// Position 0…1 along the bar as drawn (left label → right label).
    func position(_ v: Double) -> Double {
        let lo = min(worst, best), hi = max(worst, best)
        let t = max(0, min(1, (v - lo) / (hi - lo)))
        return worst < best ? t : 1 - t
    }

    static let all: [WAgeFactor] = [
        .init(id: "consistency", title: "Sleep Consistency", section: .sleep, metric: .sleepConsistency, weekly: false,
              worst: 40, best: 100, worstYears: 1.5, bestYears: -1.0, leftLabel: "40%", rightLabel: "100%", unit: "%"),
        .init(id: "hours", title: "Hours of Sleep", section: .sleep, metric: .hoursVsNeeded, weekly: false,
              worst: 5 * 60, best: 8 * 60, worstYears: 1.0, bestYears: -0.6, leftLabel: "5h", rightLabel: "8h+", unit: "h"),
        .init(id: "z13", title: "Time in HR Zones 1-3 (Weekly)", section: .strain, metric: .zones13, weekly: true,
              worst: 0, best: 180, worstYears: 1.0, bestYears: -0.6, leftLabel: "0h", rightLabel: "3h", unit: "h"),
        .init(id: "z45", title: "Time in HR Zones 4-5 (Weekly)", section: .strain, metric: .zones45, weekly: true,
              worst: 0, best: 60, worstYears: 0.6, bestYears: -0.6, leftLabel: "0h", rightLabel: "1h", unit: "h"),
        .init(id: "strength", title: "Strength Activity Time (Weekly)", section: .strain, metric: .strengthTime, weekly: true,
              worst: 0, best: 120, worstYears: 1.5, bestYears: -0.8, leftLabel: "0h", rightLabel: "2h", unit: "h"),
        .init(id: "steps", title: "Steps", section: .strain, metric: .steps, weekly: false,
              worst: 0, best: 16_000, worstYears: 2.0, bestYears: -1.0, leftLabel: "0K", rightLabel: "16K", unit: "steps"),
        .init(id: "vo2", title: "VO₂ Max", section: .fitness, metric: .vo2max, weekly: false,
              worst: 15, best: 70, worstYears: 3.0, bestYears: -2.0, leftLabel: "15", rightLabel: "70", unit: "ml/kg/min"),
        .init(id: "rhr", title: "RHR", section: .fitness, metric: .rhr, weekly: false,
              worst: 80, best: 40, worstYears: 1.5, bestYears: -1.0, leftLabel: "80bpm", rightLabel: "40bpm", unit: "bpm"),
        .init(id: "lean", title: "Lean Body Mass", section: .fitness, metric: .leanMass, weekly: false,
              worst: 60, best: 90, worstYears: 1.0, bestYears: -0.5, leftLabel: "60%", rightLabel: "90%", unit: "%"),
    ]
}

struct WAgeResult {
    struct Row: Identifiable {
        let factor: WAgeFactor
        let sixMonth: Double?
        let thirtyDay: Double?
        /// What's still missing before this marker counts ("3 of 7 days"); nil once it counts.
        var calibrating: String? = nil
        var id: String { factor.id }
        var years: Double? { sixMonth.map(factor.years) }
    }
    let chronological: Double
    let rows: [Row]
    var age: Double { chronological + rows.compactMap(\.years).reduce(0, +) }
    var delta: Double { age - chronological }
    /// Above 1x the last 30 days are aging you faster than your 6-month habits; below 1x slower.
    var pace: Double {
        let change = rows.compactMap { r -> Double? in
            guard let s = r.sixMonth, let t = r.thirtyDay else { return nil }
            return r.factor.years(t) - r.factor.years(s)
        }.reduce(0, +)
        return max(-1, min(3, 1 + change * 2))
    }
    var ready: Int { rows.filter { $0.sixMonth != nil }.count }
    /// NOOP Age shows once at least three of the nine markers have enough data.
    var hasData: Bool { ready >= 3 }
}

extension WhoopData {
    func ageResult(chronologicalAge: Int) -> WAgeResult {
        let end = Date()
        let worn6 = window(.strain, end: end, days: 182).filter { $0.value != nil }.count
        let worn30 = window(.strain, end: end, days: 30).filter { $0.value != nil }.count
        func count(_ f: WAgeFactor) -> Int { window(f.metric, end: end, days: 182).filter { $0.value != nil }.count }
        func need(_ f: WAgeFactor) -> String? {
            if f.id == "lean" { return latestLeanPct == nil && count(f) == 0 ? "Needs one scan with weight and lean mass" : nil }
            if f.id == "vo2" { return count(f) == 0 ? "Needs 4 of 7 nights of resting HR, plus your age and sex in Settings" : nil }
            if f.weekly { return worn6 < 14 ? "\(worn6) of 14 days of wear" : nil }
            let n = count(f)
            return n < 7 ? "\(n) of 7 days of data" : nil
        }
        func avg(_ f: WAgeFactor, days: Int) -> Double? {
            if need(f) != nil { return nil }
            if f.id == "lean" {
                let w = window(.weight, end: end, days: days), l = window(.leanMass, end: end, days: days)
                let pairs = zip(w, l).compactMap { a, b -> Double? in
                    guard let wv = a.value, let lv = b.value, wv > 0 else { return nil }
                    return lv / wv * 100
                }
                return pairs.isEmpty ? latestLeanPct : pairs.reduce(0, +) / Double(pairs.count)
            }
            if f.weekly {
                // Sum over the days the strap was worn, per worn week (a missing workout is a real zero).
                let worn = days >= 182 ? worn6 : worn30
                guard worn >= 7 else { return nil }
                let total = window(f.metric, end: end, days: days).compactMap(\.value).reduce(0, +)
                return total / (Double(worn) / 7)
            }
            return mean(f.metric, end: end, days: days)
        }
        let rows = WAgeFactor.all.map { f in
            WAgeResult.Row(factor: f, sixMonth: avg(f, days: 182), thirtyDay: avg(f, days: 30), calibrating: need(f))
        }
        return WAgeResult(chronological: Double(chronologicalAge), rows: rows)
    }

    private var latestLeanPct: Double? {
        guard let l = latest(.leanMass), let w = series[.weight]?[l.day] ?? latest(.weight)?.value, w > 0 else { return nil }
        return l.value / w * 100
    }

    /// In range when inside the middle 80% of the prior 30 days (within ±1.8 °F for skin temperature).
    func vitalInRange(_ m: WMetric) -> Bool? {
        guard let l = latest(m) else { return nil }
        if m == .skinTemp { return abs(l.value) <= 1.8 }
        guard let d = WFmt.dayDate(l.day), let end = Calendar.current.date(byAdding: .day, value: -1, to: d) else { return nil }
        let xs = window(m, end: end, days: 30).compactMap(\.value).sorted()
        guard xs.count >= 7 else { return nil }
        let lo = xs[Int(Double(xs.count - 1) * 0.1)], hi = xs[Int(Double(xs.count - 1) * 0.9)]
        return l.value >= lo && l.value <= hi
    }

    static let vitals: [WMetric] = [.respRate, .spo2, .rhr, .hrv, .skinTemp]

    /// Nights of this vital banked in the last 30, for the "calibrating" note (a normal range needs 7).
    func vitalNights(_ m: WMetric) -> Int {
        window(m, end: Date(), days: 30).filter { $0.value != nil }.count
    }
    static let rangeNights = 7
}

// MARK: - Health tab

struct WHealthTab: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var data: WhoopData
    @EnvironmentObject var profile: ProfileStore
    @State private var showCoach = false
    @State private var scrollY: CGFloat = 0

    private var morph: CGFloat { min(1, max(0, (scrollY - 60) / 160)) }

    var body: some View {
        let age = data.ageResult(chronologicalAge: profile.age)
        ScrollView {
            VStack(alignment: .leading, spacing: W.rowGap) {
                Text("HEALTH").font(W.caps(15)).tracking(1.6).foregroundStyle(W.text)
                    .frame(maxWidth: .infinity).padding(.top, 8)
                NavigationLink(value: WRoute.healthspan) {
                    VStack(spacing: 6) {
                        WAgeOrb(age: age.hasData ? age.age : nil, delta: age.hasData ? age.delta : nil, size: 290)
                        if !age.hasData {
                            Text("Calibrating · \(age.ready) of 3 markers ready. Tap to see what each needs.")
                                .font(W.body(14)).foregroundStyle(W.text3).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .scaleEffect(1 - 0.45 * morph, anchor: .top)
                    .opacity(Double(1 - morph))
                }
                .buttonStyle(.plain)
                paceCard(age)
                NavigationLink(value: WRoute.healthMonitor) { WHealthMonitorCard() }.buttonStyle(WPressStyle())
                NavigationLink(value: WRoute.stress) { WStressCard() }.buttonStyle(WPressStyle())
                Text("NOOP Age, Health Monitor and Stress Monitor are estimates from your own data. They are not medical devices and cannot diagnose anything.")
                    .font(W.body(14)).foregroundStyle(W.text3).padding(.top, 10)
            }
            .padding(.horizontal, W.margin)
            .padding(.bottom, 80)
        }
        .modifier(WScrollTracker(y: $scrollY))
        .background(WBackground().overlay(
            RadialGradient(colors: [W.hex(0x6A4E1E, 0.55), .clear], center: .top, startRadius: 10, endRadius: 460)
                .ignoresSafeArea()))
        .overlay(alignment: .top) { WAgePinnedHeader(age: age, morph: morph) }
        .refreshable { await repo.refresh() }
        .overlay(alignment: .bottomTrailing) { WCoachButton { showCoach = true }.padding(.trailing, 16).padding(.bottom, 10) }
        .sheet(isPresented: $showCoach) { WCoachSheet() }
        .wRoutes()
    }

    private func paceCard(_ age: WAgeResult) -> some View {
        WCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("PACE OF AGING").font(W.caps(14)).tracking(1.5).foregroundStyle(W.text)
                    Spacer()
                    if age.hasData {
                        let slower = age.pace < 1
                        HStack(spacing: 5) {
                            Image(systemName: slower ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill").font(.system(size: 8))
                            Text(slower ? "slower than 1x" : "faster than 1x").font(W.body(14, .semibold))
                        }
                        .foregroundStyle(slower ? W.mint : W.orange)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(slower ? W.pillGreenBG : W.pillOrangeBG, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                WPaceScale(pace: age.hasData ? age.pace : nil)
                NavigationLink(value: WRoute.healthspan) {
                    Text("GO TO HEALTHSPAN").font(W.caps(14)).tracking(1.5).foregroundStyle(W.text)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(WPressStyle())
            }
        }
    }
}

/// The glowing gold orb: a slowly breathing, slightly irregular disc with a dark core and drifting
/// sparks around the rim, the age in the middle.
struct WAgeOrb: View {
    let age: Double?
    let delta: Double?
    var size: CGFloat = 290
    var compact = false

    private static let sparks: [(a: Double, r: Double, s: Double, p: Double)] = (0..<90).map { i in
        let x = Double(i)
        return (a: (x * 2.399).truncatingRemainder(dividingBy: 6.283),
                r: 0.70 + 0.28 * abs(sin(x * 1.7)),
                s: 1.0 + 2.6 * abs(sin(x * 0.9)),
                p: x * 0.37)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let r = min(sz.width, sz.height) / 2 * 0.92
                var path = Path()
                for i in 0...120 {
                    let th = Double(i) / 120 * 2 * .pi
                    let k = 1 + 0.035 * sin(3 * th + t * 0.6) + 0.025 * sin(5 * th - t * 0.45) + 0.02 * sin(2 * th + 1.3)
                    let pt = CGPoint(x: c.x + cos(th) * r * k, y: c.y + sin(th) * r * k)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                path.closeSubpath()
                ctx.fill(path, with: .radialGradient(
                    Gradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.45),
                                     .init(color: W.hex(0x3A2A10), location: 0.72), .init(color: W.hex(0xA77A33), location: 1)]),
                    center: c, startRadius: 0, endRadius: r * 1.05))
                ctx.stroke(path, with: .color(W.hex(0xE4CC92, 0.9)), lineWidth: compact ? 1.2 : 2)
                for s in Self.sparks {
                    let ang = s.a + t * 0.05
                    let p = CGPoint(x: c.x + cos(ang) * r * s.r, y: c.y + sin(ang) * r * s.r)
                    let alpha = 0.35 + 0.65 * abs(sin(t * 0.8 + s.p))
                    let d = s.s * (compact ? 0.5 : 1)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)),
                             with: .color(W.hex(0xF3E3B5, alpha)))
                }
            }
        }
        .frame(width: size, height: size)
        .overlay {
            VStack(spacing: compact ? 0 : 4) {
                Text(age.map(WFmt.one) ?? "--").font(W.num(compact ? 36 : 66, .heavy)).foregroundStyle(W.text)
                Text("NOOP AGE").font(W.caps(compact ? 11 : 16)).tracking(1.6).foregroundStyle(compact ? W.text3 : W.text)
                if !compact, let delta {
                    Text("\(WFmt.one(abs(delta))) years \(delta >= 0 ? "older" : "younger")")
                        .font(W.body(19, .semibold)).foregroundStyle(W.gold)
                }
            }
        }
    }
}

/// Tick ruler from −1.0x to 3.0x with a bright marker at the current pace.
struct WPaceScale: View {
    let pace: Double?
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) { Circle().fill(W.text3).frame(width: 14, height: 14); Text("Slow") }
                Spacer()
                HStack(spacing: 6) { Text("Fast"); Image(systemName: "flame") }
            }
            .font(W.body(16)).foregroundStyle(W.text2)
            GeometryReader { g in
                let n = 64
                let w = g.size.width
                let mx = pace.map { (($0 + 1) / 4) * w }
                ZStack(alignment: .topLeading) {
                    ForEach(0..<n, id: \.self) { i in
                        let x = w * Double(i) / Double(n - 1)
                        let near = mx.map { abs($0 - x) < w * 0.12 } ?? false
                        Rectangle().fill(Color.white.opacity(near ? 0.75 : 0.28))
                            .frame(width: 1.6, height: 30).offset(x: x)
                    }
                    if let mx {
                        Rectangle().fill(W.text).frame(width: 3.5, height: 42).offset(x: mx - 1.75, y: -6)
                        Text(String(format: "%.1fx", pace ?? 1)).font(W.num(24)).foregroundStyle(W.text)
                            .fixedSize().offset(x: min(max(0, mx - 22), w - 50), y: -40)
                    }
                }
            }
            .frame(height: 30)
            .padding(.top, 34)
            HStack {
                Text("-1.0x"); Spacer(); Text("1.0x"); Spacer(); Text("3.0x")
            }
            .font(W.caps(13, .semibold)).foregroundStyle(W.text3)
        }
    }
}

// MARK: - Healthspan

struct WHealthspanView: View {
    @EnvironmentObject var data: WhoopData
    @EnvironmentObject var profile: ProfileStore
    @State private var open: Set<String> = []
    @State private var scrollY: CGFloat = 0

    private var morph: CGFloat { min(1, max(0, (scrollY - 40) / 160)) }

    var body: some View {
        let age = data.ageResult(chronologicalAge: profile.age)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 14) {
                    WAgeOrb(age: age.hasData ? age.age : nil, delta: age.hasData ? age.delta : nil, size: 260)
                    if age.hasData {
                        Text("PACE OF AGING  \(String(format: "%.1fx", age.pace))").font(W.caps(14)).tracking(1.4).foregroundStyle(W.text2)
                    } else {
                        Text("Calibrating · \(age.ready) of 3 markers ready. Each marker below says what it still needs.")
                            .font(W.body(14)).foregroundStyle(W.text3).multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .scaleEffect(1 - 0.45 * morph, anchor: .top)
                .opacity(Double(1 - morph))
                ForEach([WAgeFactor.Section.sleep, .strain, .fitness], id: \.self) { sec in
                    HStack(alignment: .lastTextBaseline) {
                        Text(sec.rawValue).font(W.title(26)).foregroundStyle(W.text)
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 10))
                            Text("6 Month avg.")
                            Text("|").foregroundStyle(W.text3)
                            Image(systemName: "arrowtriangle.up.fill").font(.system(size: 10)).foregroundStyle(W.text3)
                            Text("30 Day avg.")
                        }
                        .font(W.body(14)).foregroundStyle(W.text2)
                    }
                    .padding(.top, 10)
                    VStack(spacing: 0) {
                        let rows = age.rows.filter { $0.factor.section == sec }
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                            factorRow(r)
                            if i < rows.count - 1 { Rectangle().fill(W.hairline).frame(height: 1) }
                        }
                    }
                    .padding(.horizontal, 20)
                    .background(LinearGradient(colors: [W.cardTop, W.cardBottom], startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous))
                }
                Text("How NOOP Age works: each marker's 6-month average is placed between a level that adds years and a level that takes years off, and the years add to your age. Pace of aging compares your last 30 days with your 6-month habits. It is an estimate for motivation, not a medical measurement.")
                    .font(W.body(14)).foregroundStyle(W.text3).padding(.top, 8)
            }
            .padding(.horizontal, W.margin)
            .padding(.bottom, 40)
        }
        .modifier(WScrollTracker(y: $scrollY))
        .overlay(alignment: .top) { WAgePinnedHeader(age: age, morph: morph) }
        .wPage(title: "Healthspan")
    }

    private func display(_ f: WAgeFactor, _ v: Double) -> String {
        switch f.unit {
        case "h": return WFmt.hm(v)
        case "%": return "\(Int(v.rounded()))%"
        case "steps": return WFmt.grouped(v)
        default: return "\(Int(v.rounded()))"
        }
    }

    private func factorRow(_ r: WAgeResult.Row) -> some View {
        let f = r.factor
        let isOpen = open.contains(f.id)
        return VStack(alignment: .leading, spacing: 14) {
            Button {
                WHaptics.select()
                withAnimation(.easeInOut(duration: 0.22)) {
                    if isOpen { open.remove(f.id) } else { open.insert(f.id) }
                }
            } label: {
                HStack {
                    Text(f.title.uppercased()).font(W.caps(14)).tracking(1.3).foregroundStyle(W.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer()
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.system(size: 15, weight: .medium)).foregroundStyle(W.text2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(alignment: .center, spacing: 14) {
                WImpactBar(factor: f, sixMonth: r.sixMonth, thirtyDay: r.thirtyDay, expanded: isOpen, display: { display(f, $0) })
                VStack(alignment: .trailing, spacing: 0) {
                    if let y = r.years {
                        Text((y >= 0 ? "+" : "−") + WFmt.one(abs(y))).font(W.num(24))
                            .foregroundStyle(abs(y) < 0.05 ? W.text : (y > 0 ? W.orange : W.mint))
                    } else {
                        Text("--").font(W.num(24)).foregroundStyle(W.text3)
                    }
                    Text("years").font(W.body(15)).foregroundStyle(W.text3)
                }
                .frame(width: 64, alignment: .trailing)
            }
            if let c = r.calibrating {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass").font(.system(size: 12))
                    Text("Calibrating · \(c)").font(W.body(14))
                }
                .foregroundStyle(W.text3)
            }
            if isOpen {
                Text(advice(r)).font(W.body(16)).foregroundStyle(W.text2).fixedSize(horizontal: false, vertical: true)
                NavigationLink(value: WRoute.trend(f.metric, .month)) {
                    HStack(spacing: 8) {
                        Text("VIEW TREND").font(W.caps(14)).tracking(1.5)
                        Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(W.lineBlue)
                }
            }
        }
        .padding(.vertical, 20)
    }

    private func advice(_ r: WAgeResult.Row) -> String {
        guard let s = r.sixMonth else { return "No data yet for this marker. Once NOOP has some, it starts counting toward your NOOP Age." }
        guard let t = r.thirtyDay else { return "Your 6-month average is \(display(r.factor, s))." }
        let better = r.factor.years(t) < r.factor.years(s) - 0.02
        let worse = r.factor.years(t) > r.factor.years(s) + 0.02
        if better { return "Keep pushing. Your last 30 days (\(display(r.factor, t))) beat your 6-month average (\(display(r.factor, s))), which lowers your NOOP Age over time." }
        if worse { return "Slipping a little. Your last 30 days (\(display(r.factor, t))) trail your 6-month average (\(display(r.factor, s)))." }
        return "Steady. Your last 30 days match your 6-month average (\(display(r.factor, s)))."
    }
}

/// Ten-segment bar from the years-adding end (orange) to the years-saving end (green), with the
/// 6-month average marked above and the 30-day average below.
struct WImpactBar: View {
    let factor: WAgeFactor
    let sixMonth: Double?
    let thirtyDay: Double?
    let expanded: Bool
    let display: (Double) -> String

    private func segColor(_ i: Int) -> Color {
        // Left→right runs from the label on the left to the one on the right; colour by years impact.
        let t = (Double(i) + 0.5) / 10
        let goodSide = factor.worst < factor.best ? t : 1 - t
        if goodSide < 0.35 { return W.orange }
        if goodSide < 0.55 { return W.hex(0x8A6A32) }
        if goodSide < 0.65 { return W.breakdownGray }
        return goodSide < 0.85 ? W.hex(0x3E9A6C) : W.mint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 2) {
                        ForEach(0..<10, id: \.self) { i in
                            Rectangle().fill(segColor(i).opacity(expanded ? 0.35 : 0.9))
                                .overlay(alignment: .top) { Rectangle().fill(segColor(i)).frame(height: 3) }
                        }
                    }
                    .frame(height: expanded ? 26 : 5)
                    .offset(y: 30)
                    if let s = sixMonth {
                        let x = w * factor.position(s)
                        VStack(spacing: 1) {
                            if expanded { Text("6 Month avg.").font(W.body(13)).foregroundStyle(W.text) }
                            Text(display(s)).font(W.num(17)).foregroundStyle(W.text)
                            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 11)).foregroundStyle(W.text)
                        }
                        .fixedSize()
                        .position(x: min(max(30, x), w - 30), y: expanded ? 8 : 14)
                    }
                    if let t = thirtyDay {
                        let x = w * factor.position(t)
                        VStack(spacing: 1) {
                            Image(systemName: "arrowtriangle.up.fill").font(.system(size: 9)).foregroundStyle(W.text3)
                            if expanded {
                                Text(display(t)).font(W.num(15)).foregroundStyle(W.text)
                                Text("30 Day avg.").font(W.body(13)).foregroundStyle(W.text2)
                            }
                        }
                        .fixedSize()
                        .position(x: min(max(30, x), w - 30), y: (expanded ? 56 : 37) + (expanded ? 18 : 6))
                    }
                }
            }
            .frame(height: expanded ? 104 : 46)
            HStack {
                Text(factor.leftLabel).foregroundStyle(factor.worst < factor.best ? W.orange : W.mint)
                Spacer()
                Text(factor.rightLabel).foregroundStyle(factor.worst < factor.best ? W.mint : W.orange)
            }
            .font(W.caps(12, .semibold))
        }
    }
}

// MARK: - Health Monitor

/// Compact status card on the Health tab; opens the full monitor.
struct WHealthMonitorCard: View {
    @EnvironmentObject var data: WhoopData
    var body: some View {
        let flags = WhoopData.vitals.map { data.vitalInRange($0) }
        let known = flags.compactMap { $0 }
        let out = known.filter { !$0 }.count
        return WCard {
            VStack(alignment: .leading, spacing: 18) {
                WCardHeader(title: "Health Monitor", chevron: true)
                HStack(spacing: 0) {
                    ForEach(Array(WhoopData.vitals.enumerated()), id: \.offset) { i, m in
                        VStack(spacing: 10) {
                            Image(systemName: m.icon).font(.system(size: 20, weight: .light)).foregroundStyle(W.text2)
                            Text(WHealthMonitorView.short(m)).font(W.caps(13)).tracking(1.1).foregroundStyle(W.text)
                            WStatusSquare(ok: flags[i])
                        }
                        .frame(maxWidth: .infinity)
                        if i < WhoopData.vitals.count - 1 { Rectangle().fill(W.hairline).frame(width: 1, height: 80) }
                    }
                }
                HStack(spacing: 10) {
                    WStatusSquare(ok: known.isEmpty ? nil : out == 0)
                    Text(known.isEmpty
                         ? (data.vitalNights(.rhr) == 0 ? "No data" : "Calibrating your normal ranges · \(min(data.vitalNights(.rhr), 6)) of 7 nights")
                         : out == 0 ? "All metrics within range" : "\(out) metric\(out == 1 ? "" : "s") out of range")
                        .font(W.body(16)).foregroundStyle(W.text)
                    Spacer()
                }
                .padding(12)
                .background(W.segTrack.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

/// The small Home tile.
struct WHealthMonitorTile: View {
    @EnvironmentObject var data: WhoopData
    private var calibratingText: String {
        let n = data.vitalNights(.rhr)
        return n == 0 ? "No data" : "Calibrating · \(min(n, 6))/7"
    }
    var body: some View {
        let known = WhoopData.vitals.compactMap { data.vitalInRange($0) }
        let out = known.filter { !$0 }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("HEALTH MONITOR").font(W.caps(12)).tracking(1.2).foregroundStyle(W.text).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(W.text3)
            }
            HStack(spacing: 8) {
                WStatusSquare(ok: known.isEmpty ? nil : out == 0, size: 22)
                Text(known.isEmpty ? calibratingText : out == 0 ? "Within range" : "\(out) out of range")
                    .font(W.body(15, .semibold)).foregroundStyle(W.text).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .background(W.row, in: RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous))
    }
}

struct WStatusSquare: View {
    let ok: Bool?
    var size: CGFloat = 26
    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(ok == nil ? W.text3.opacity(0.35) : (ok! ? W.mint.opacity(0.25) : W.orange.opacity(0.25)))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: ok == nil ? "minus" : (ok! ? "checkmark" : "exclamationmark"))
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(ok == nil ? W.text3 : (ok! ? W.mint : W.orange)))
    }
}

/// The full Health Monitor page: live heart rate, then each overnight vital against its range.
struct WHealthMonitorView: View {
    @EnvironmentObject var data: WhoopData
    @EnvironmentObject var live: LiveState

    static func short(_ m: WMetric) -> String {
        switch m {
        case .respRate: "RESP"
        case .spo2: "SPO₂"
        case .rhr: "RHR"
        case .hrv: "HRV"
        default: "TEMP"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HEART RATE").font(W.caps(15)).tracking(1.5).foregroundStyle(W.text)
                    Image(systemName: live.connected ? "heart.fill" : "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 18)).foregroundStyle(live.connected ? W.red : W.text3)
                    Text(live.connected ? (live.heartRate.map { "\($0)" } ?? "--") : "--").font(W.num(44)).foregroundStyle(W.text)
                    Text("BPM").font(W.caps(13)).tracking(1.2).foregroundStyle(W.text2)
                    Text(live.connected ? "Live from your strap" : "Strap disconnected").font(W.body(16)).foregroundStyle(W.text2)
                }
                .padding(.bottom, 8)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(WhoopData.vitals) { m in
                        NavigationLink(value: WRoute.trend(m, .month)) { vitalTile(m) }.buttonStyle(WPressStyle())
                    }
                }
            }
            .padding(.horizontal, W.margin)
            .padding(.bottom, 40)
        }
        .wPage(title: "Health Monitor")
    }

    private func vitalTile(_ m: WMetric) -> some View {
        let l = data.latest(m)
        let ok = data.vitalInRange(m)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: m.icon).font(.system(size: 17, weight: .light)).foregroundStyle(W.text2)
                Text(m.title.uppercased()).font(W.caps(13)).tracking(1.1).foregroundStyle(W.text)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(l.map { m.format($0.value) } ?? "--").font(W.num(32)).foregroundStyle(W.text)
                if l != nil { Text(m == .skinTemp ? "°F" : m.unit).font(W.body(15)).foregroundStyle(W.text3) }
            }
            HStack(spacing: 6) {
                Circle().fill(ok == nil ? W.text3 : (ok! ? W.mint : W.orange)).frame(width: 7, height: 7)
                Text(ok == nil ? (l == nil ? "No data" : "Calibrating · \(min(data.vitalNights(m), 6))/7 nights") : (ok! ? "Within range" : "Out of range"))
                    .font(W.body(14, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(W.text)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(W.segTrack.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(LinearGradient(colors: [W.cardTop, W.cardBottom], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous))
    }
}

// MARK: - Stress Monitor

enum WStressBand {
    static let low = W.hex(0x67AEE6), medium = W.hex(0x00F19F), high = W.hex(0xFFA722)
    static func color(_ v: Double) -> Color { v < 1 ? low : v < 2 ? medium : high }
    static func word(_ v: Double) -> String { v < 1 ? "Low" : v < 2 ? "Medium" : "High" }
}

private struct WStressPoint: Identifiable {
    let id: Int
    let date: Date
    let level: Double
}

/// Small Home tile.
struct WStressTile: View {
    @EnvironmentObject var data: WhoopData
    var body: some View {
        let v = data.currentStress
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("STRESS MONITOR").font(W.caps(12)).tracking(1.2).foregroundStyle(W.text).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(W.text3)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(v.map(WFmt.one) ?? "--").font(W.num(26)).foregroundStyle(W.text)
                if let v { Text(WStressBand.word(v)).font(W.body(15, .semibold)).foregroundStyle(WStressBand.color(v)) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .background(W.row, in: RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous))
    }
}

/// Health tab card: today's high-stress time over a faint day line.
struct WStressCard: View {
    @EnvironmentObject var data: WhoopData
    var body: some View {
        let mins = data.stress?.highStressMinutes
        return WCard {
            VStack(alignment: .leading, spacing: 14) {
                WCardHeader(title: "Stress Monitor", chevron: true)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(data.stressDayLabel.uppercased())'S HIGH STRESS").font(W.caps(13)).tracking(1.3).foregroundStyle(W.text2)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(mins.map { WFmt.hm(Double($0)) } ?? "--:--").font(W.num(30)).foregroundStyle(W.text)
                            Text("hrs").font(W.body(17)).foregroundStyle(W.text3)
                        }
                    }
                    Spacer()
                    if let v = data.currentStress {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(WFmt.one(v)).font(W.num(30)).foregroundStyle(WStressBand.color(v))
                            Text((data.stressDayLabel == "Today" ? "NOW · " : "LATEST · ") + WStressBand.word(v).uppercased()).font(W.caps(12)).tracking(1.2).foregroundStyle(W.text3)
                        }
                    }
                }
            }
        }
    }
}

struct WStressView: View {
    @EnvironmentObject var data: WhoopData
    @EnvironmentObject var repo: Repository
    @State private var selected: Date?

    private var points: [WStressPoint] {
        let src = (data.stress?.timeline.isEmpty == false ? data.stress?.timeline : data.stress?.hours) ?? []
        return src.compactMap { h in h.level.map { WStressPoint(id: h.startTs, date: Date(timeIntervalSince1970: TimeInterval(h.startTs)), level: $0) } }
    }

    var body: some View {
        let v = data.currentStress
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ZStack {
                    WStressGauge(value: v).frame(width: 300, height: 170)
                    VStack(spacing: 4) {
                        Text(v.map(WFmt.one) ?? "--").font(W.num(54, .heavy)).foregroundStyle(W.text)
                        Text(v.map { WStressBand.word($0).uppercased() } ?? "NO DATA").font(W.caps(15)).tracking(1.5).foregroundStyle(W.text)
                        Text(data.stressDayLabel == "Today" ? Date().formatted(date: .omitted, time: .shortened) : "Yesterday")
                            .font(W.body(14)).foregroundStyle(W.text3)
                    }
                    .offset(y: 26)
                }
                .frame(maxWidth: .infinity)
                HStack(spacing: 18) {
                    WLegend(color: WStressBand.high, label: "High")
                    WLegend(color: WStressBand.medium, label: "Medium")
                    WLegend(color: WStressBand.low, label: "Low")
                }
                .frame(maxWidth: .infinity)
                chart
                WCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(data.stressDayLabel.uppercased())'S HIGH STRESS").font(W.caps(13)).tracking(1.3).foregroundStyle(W.text2)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(data.stress.map { WFmt.hm(Double($0.highStressMinutes)) } ?? "--:--").font(W.num(34)).foregroundStyle(W.text)
                            Text("hrs").font(W.body(18)).foregroundStyle(W.text3)
                        }
                        if let m = data.stress?.activityMaskedHours, m > 0 {
                            Text("\(m) hour\(m == 1 ? "" : "s") left out because you were moving.").font(W.body(14)).foregroundStyle(W.text3)
                        }
                    }
                }
                WCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What is Stress?").font(W.body(22, .semibold)).foregroundStyle(W.text)
                        Text("Stress shows how activated your body is from 0 to 3, from your heart rate and HRV through the day compared with your calmer hours. Exercise is left out. Long stretches in the high band are a cue to take a breath or a break.")
                            .font(W.body(17)).foregroundStyle(W.text2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, W.margin)
            .padding(.bottom, 40)
        }
        .wPage(title: "Stress Monitor")
        .task { await data.loadStress(repo) }
    }

    @ViewBuilder private var chart: some View {
        let pts = points
        if pts.isEmpty {
            WNoData(height: 220)
        } else {
            Chart {
                ForEach(pts) { p in
                    LineMark(x: .value("Time", p.date), y: .value("Stress", p.level))
                        .foregroundStyle(WStressBand.color(p.level))
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if let s = selected, let near = pts.min(by: { abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s)) }) {
                    RuleMark(x: .value("Selected", near.date))
                        .foregroundStyle(Color.white.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            VStack(spacing: 2) {
                                Text(near.date.formatted(date: .omitted, time: .shortened)).font(W.caps(11)).foregroundStyle(W.text2)
                                Text(WFmt.one(near.level)).font(W.num(20)).foregroundStyle(WStressBand.color(near.level))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(W.callout, in: RoundedRectangle(cornerRadius: 8))
                        }
                }
            }
            .chartYScale(domain: 0...3)
            .chartXSelection(value: $selected)
            .onChange(of: selected) { _, _ in WHaptics.tick() }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 1, 2, 3]) { v in
                    AxisGridLine().foregroundStyle(W.grid)
                    AxisValueLabel { if let d = v.as(Double.self) { Text(String(format: "%.1f", d)) } }
                        .font(W.caps(12, .semibold)).foregroundStyle(W.text3)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.hour()).font(W.caps(12, .semibold)).foregroundStyle(W.text3)
                }
            }
            .frame(height: 240)
        }
    }
}

/// Half-circle gauge, 0 to 3, banded low / medium / high.
struct WStressGauge: View {
    let value: Double?
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let r = w / 2 - 12
            let c = CGPoint(x: w / 2, y: g.size.height - 6)
            ZStack {
                arc(c, r, 0, 1).stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                arc(c, r, 0, 1.0 / 3).stroke(WStressBand.low.opacity(0.85), style: StrokeStyle(lineWidth: 16, lineCap: .butt))
                arc(c, r, 1.0 / 3, 2.0 / 3).stroke(WStressBand.medium.opacity(0.85), style: StrokeStyle(lineWidth: 16, lineCap: .butt))
                arc(c, r, 2.0 / 3, 1).stroke(WStressBand.high.opacity(0.85), style: StrokeStyle(lineWidth: 16, lineCap: .butt))
                if let value {
                    let a = Double.pi + Double.pi * min(1, max(0, value / 3))
                    Circle().fill(W.text).frame(width: 22, height: 22)
                        .overlay(Circle().stroke(W.bgMid, lineWidth: 4))
                        .position(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                }
                Text("0.0").font(W.caps(13, .semibold)).foregroundStyle(W.text3).position(x: c.x - r, y: c.y + 18)
                Text("3.0").font(W.caps(13, .semibold)).foregroundStyle(W.text3).position(x: c.x + r, y: c.y + 18)
            }
        }
    }

    private func arc(_ c: CGPoint, _ r: CGFloat, _ from: Double, _ to: Double) -> Path {
        var p = Path()
        p.addArc(center: c, radius: r, startAngle: .radians(.pi + .pi * from), endAngle: .radians(.pi + .pi * to), clockwise: false)
        return p
    }
}


/// The pinned header that takes over from the big orb on scroll: years older · small orb · pace.
struct WAgePinnedHeader: View {
    let age: WAgeResult
    let morph: CGFloat

    var body: some View {
        HStack(alignment: .center) {
            VStack(spacing: 2) {
                Text(age.hasData ? WFmt.one(abs(age.delta)) : "--").font(W.num(22)).foregroundStyle(W.gold)
                Text(age.delta >= 0 ? "YEARS OLDER" : "YEARS YOUNGER").font(W.caps(11)).tracking(1.2).foregroundStyle(W.text2)
            }
            .frame(maxWidth: .infinity)
            WAgeOrb(age: age.hasData ? age.age : nil, delta: nil, size: 104, compact: true)
            VStack(spacing: 2) {
                Text(age.hasData ? String(format: "%.1fx", age.pace) : "--").font(W.num(22)).foregroundStyle(W.text)
                Text("PACE OF AGING").font(W.caps(11)).tracking(1.2).foregroundStyle(W.text2)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, W.margin)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [W.bgTop, W.bgTop.opacity(0.96), W.bgTop.opacity(0)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
        .opacity(Double(max(0, morph * 2 - 1)))
        .scaleEffect(0.85 + 0.15 * morph, anchor: .top)
        .allowsHitTesting(false)
    }
}
