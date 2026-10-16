//  WData.swift
//  Nathan's build: one per-day table behind every WHOOP-style screen. Each metric is a
//  [dayKey: value] dictionary read from the same Repository data the rest of NOOP shows; the only
//  values derived here are the WHOOP-shaped views of that data (hours vs. need %, time in bed, a
//  4-night bed/wake consistency, weekly HR-zone minutes, strength time).

import SwiftUI
import WhoopStore
import StrandAnalytics

enum WPeriod: String, CaseIterable, Hashable {
    case week, month, sixMonths
    var days: Int { switch self { case .week: 7; case .month: 30; case .sixMonths: 182 } }
    var label: String { switch self { case .week: "W"; case .month: "M"; case .sixMonths: "6M" } }
    var noun: String { switch self { case .week: "week"; case .month: "month"; case .sixMonths: "6-month period" } }
    var priorNoun: String { switch self { case .week: "prior week"; case .month: "prior month"; case .sixMonths: "prior 6 months" } }
}

enum WBetter { case up, down, neither }

enum WGroup: String { case sleep, recovery, strain, nutrition, health, body }

enum WChart { case bars, recoveryBars, line, dualNeed, restorative, sleepStress }

enum WMetric: String, CaseIterable, Hashable, Identifiable {
    // Sleep
    case sleepPerformance, hoursVsNeeded, hoursVsNeededPct, restorative, sleepConsistency, timeInBed,
         sleepEfficiency, sleepDebt, matSleep
    // Recovery
    case recovery, hrv, rhr, respRate, spo2, skinTemp
    // Strain
    case strain, zones13, zones45, strengthTime, steps, calories
    // Nutrition
    case caloriesIn, protein, energyBalance
    // Body (InBody scale through Apple Health) and fitness
    case weight, bodyFat, leanMass, fatMass, vo2max

    var id: String { rawValue }

    /// Mass metrics are stored in the user's unit (lb for imperial) so every chart and label agrees.
    static var imperial: Bool {
        (UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "imperial") == UnitSystem.imperial.rawValue
    }
    static var massUnit: String { imperial ? "lb" : "kg" }

    var group: WGroup {
        switch self {
        case .sleepPerformance, .hoursVsNeeded, .hoursVsNeededPct, .restorative, .sleepConsistency,
             .timeInBed, .sleepEfficiency, .sleepDebt, .matSleep: .sleep
        case .recovery, .hrv, .rhr, .respRate: .recovery
        case .spo2, .skinTemp: .health
        case .strain, .zones13, .zones45, .strengthTime, .steps, .calories: .strain
        case .caloriesIn, .protein, .energyBalance: .nutrition
        case .weight, .bodyFat, .leanMass, .fatMass, .vo2max: .body
        }
    }

    var title: String {
        switch self {
        case .sleepPerformance: "Sleep Performance"
        case .hoursVsNeeded: "Hours vs. Needed (Hours)"
        case .hoursVsNeededPct: "Hours vs. Needed (%)"
        case .restorative: "Restorative Sleep (Hours)"
        case .sleepConsistency: "Sleep Consistency"
        case .timeInBed: "Time in Bed"
        case .sleepEfficiency: "Sleep Efficiency"
        case .sleepDebt: "Sleep Debt"
        case .matSleep: "Sleep Mat (Hours)"
        case .recovery: "Recovery"
        case .hrv: "Heart Rate Variability"
        case .rhr: "Resting Heart Rate"
        case .respRate: "Respiratory Rate"
        case .spo2: "Blood Oxygen"
        case .skinTemp: "Skin Temp (From Baseline)"
        case .strain: "Strain"
        case .zones13: "HR Zones 1-3"
        case .zones45: "HR Zones 4-5"
        case .strengthTime: "Strength Activity Time"
        case .steps: "Steps"
        case .calories: "Calories"
        case .caloriesIn: "Calories Eaten"
        case .protein: "Protein"
        case .energyBalance: "Calories In vs. Out"
        case .weight: "Weight"
        case .bodyFat: "Body Fat"
        case .leanMass: "Lean Body Mass"
        case .fatMass: "Body Fat Mass"
        case .vo2max: "VO₂ Max"
        }
    }

    var icon: String {
        switch self {
        case .sleepPerformance, .sleepDebt: "moon"
        case .hoursVsNeeded, .hoursVsNeededPct: "moon.circle"
        case .restorative: "moon.stars"
        case .sleepConsistency: "clock.arrow.circlepath"
        case .timeInBed, .matSleep: "bed.double"
        case .sleepEfficiency: "chart.bar"
        case .recovery: "figure.mind.and.body"
        case .hrv: "waveform.path.ecg"
        case .rhr: "heart"
        case .respRate: "lungs"
        case .spo2: "drop"
        case .skinTemp: "thermometer.medium"
        case .strain: "flame"
        case .zones13: "heart.text.square"
        case .zones45: "bolt.heart"
        case .strengthTime: "dumbbell"
        case .steps: "shoeprints.fill"
        case .calories: "flame"
        case .caloriesIn: "fork.knife"
        case .protein: "fish"
        case .energyBalance: "plusminus"
        case .weight: "scalemass"
        case .bodyFat: "percent"
        case .leanMass: "figure.strengthtraining.traditional"
        case .fatMass: "drop.halffull"
        case .vo2max: "lungs"
        }
    }

    /// Unit shown after the average.
    var unit: String {
        switch self {
        case .sleepPerformance, .hoursVsNeededPct, .sleepConsistency, .sleepEfficiency, .recovery, .spo2: "%"
        case .hoursVsNeeded, .restorative, .timeInBed, .sleepDebt, .matSleep, .zones13, .zones45, .strengthTime: "hr"
        case .hrv: "ms"
        case .rhr: "bpm"
        case .respRate: "rpm"
        case .skinTemp: "°"
        case .strain: ""
        case .steps: "Steps"
        case .calories, .caloriesIn, .energyBalance: "Cals"
        case .protein: "g"
        case .weight, .leanMass, .fatMass: WMetric.massUnit
        case .bodyFat: "%"
        case .vo2max: "ml/kg/min"
        }
    }

    var better: WBetter {
        switch self {
        case .rhr, .sleepDebt, .respRate, .skinTemp, .bodyFat, .fatMass: .down
        case .weight: .neither
        case .strain, .energyBalance: .neither
        default: .up
        }
    }

    var chart: WChart {
        switch self {
        case .recovery: .recoveryBars
        case .hrv, .rhr, .respRate, .spo2, .skinTemp, .weight, .bodyFat, .leanMass, .fatMass, .vo2max: .line
        case .hoursVsNeeded: .dualNeed
        case .restorative: .restorative
        default: .bars
        }
    }

    var barColor: Color {
        switch group {
        case .sleep: W.sleep
        case .nutrition: self == .protein ? W.mint : W.orange
        default: W.strain
        }
    }

    /// Hours-shaped metrics store minutes and print as h:mm.
    var isDuration: Bool {
        switch self {
        case .hoursVsNeeded, .restorative, .timeInBed, .sleepDebt, .matSleep, .zones13, .zones45, .strengthTime: true
        default: false
        }
    }

    func format(_ v: Double) -> String {
        if isDuration { return WFmt.hm(v) }
        switch self {
        case .strain, .respRate, .weight, .bodyFat, .leanMass, .fatMass: return WFmt.one(v)
        case .skinTemp: return (v >= 0 ? "+" : "") + WFmt.one(v)
        case .steps, .calories, .caloriesIn, .energyBalance: return WFmt.grouped(v)
        default: return WFmt.int(v)
        }
    }

    /// WHOOP's one-liner under the selector, in NOOP's own words.
    var blurb: String {
        switch self {
        case .sleepPerformance: "Sleep Performance compares the sleep you got with the sleep your body needed."
        case .hoursVsNeeded: "Aim to match your Hours of Sleep with your Sleep Need to avoid Sleep Debt."
        case .hoursVsNeededPct: "Good sleep speeds up recovery, supports your immune system and boosts fitness gains."
        case .restorative: "Restorative sleep (deep plus REM) is when your body repairs itself. Get enough of it to maximize Recovery."
        case .sleepConsistency: "Sleep Consistency measures how similar your bed and wake times are over a 4-day period."
        case .timeInBed: "Total time from getting into bed to getting up, awake time included."
        case .sleepEfficiency: "Sleep efficiency is the share of your time in bed that you actually spend asleep."
        case .sleepDebt: "Sleep Debt is the sleep you still owe from recent nights. Paying it back raises tomorrow's need less."
        case .matSleep: "Time asleep as measured by your Withings sleep mat, next to your strap."
        case .recovery: "Recovery reflects how ready your body is to take on strain, from HRV, resting heart rate, breathing rate and sleep."
        case .hrv: "Heart rate variability is the variation in time between heartbeats. Higher is generally better and shows readiness."
        case .rhr: "Resting heart rate measured during your deepest sleep. Lower generally means better fitness and recovery."
        case .respRate: "Breaths per minute during sleep. It is very stable night to night, so a jump can be an early sign of illness."
        case .spo2: "Blood oxygen saturation during sleep."
        case .skinTemp: "Skin temperature compared with your baseline. A rise can be an early sign of illness."
        case .strain: "Strain measures the cardiovascular load you took on across the day, from 0 to 21."
        case .zones13: "Time spent in heart rate zones 1 to 3 builds your aerobic base."
        case .zones45: "Time spent in heart rate zones 4 and 5 builds speed and top-end fitness."
        case .strengthTime: "Time spent in logged strength sessions."
        case .steps: "Steps counted through the day."
        case .calories: "Calories burned across the whole day."
        case .caloriesIn: "Calories eaten, imported from MacroFactor through Apple Health."
        case .protein: "Protein eaten, imported from MacroFactor through Apple Health."
        case .energyBalance: "Calories eaten minus calories burned. Below zero is a deficit."
        case .weight: "Body weight from your smart scale, through Apple Health."
        case .bodyFat: "Body fat percentage from your InBody scale. Measure at the same time of day for the cleanest trend."
        case .leanMass: "Lean body mass: everything that isn't fat, mostly muscle and water. Rising lean mass with falling fat is a recomposition."
        case .fatMass: "Pounds of fat, from weight times body fat percentage."
        case .vo2max: "VO₂ Max is the most oxygen your body can use during hard exercise, one of the strongest predictors of long-term health."
        }
    }
}

/// The table every WHOOP-style screen reads. Loaded once per Repository refresh.
@MainActor
final class WhoopData: ObservableObject {
    @Published private(set) var series: [WMetric: [String: Double]] = [:]
    /// Sleep need (minutes), keyed by wake day. Paired with `.hoursVsNeeded`.
    @Published private(set) var need: [String: Double] = [:]
    @Published private(set) var deep: [String: Double] = [:]
    @Published private(set) var rem: [String: Double] = [:]
    @Published private(set) var workouts: [WorkoutRow] = []
    @Published private(set) var loadedSeq = -1
    @Published private(set) var loaded = false

    /// Today's daytime stress (0–3 per hour), the same DaytimeStress read the Stress screen uses.
    @Published private(set) var stress: DaytimeStress.Result?
    @Published private(set) var stressLoadedAt: Date?

    var todayKey: String { Repository.localDayKey(Date()) }

    /// Latest scored hour's stress level, 0…3.
    var currentStress: Double? {
        let pts = (stress?.timeline.isEmpty == false ? stress?.timeline : stress?.hours) ?? []
        return pts.last(where: { $0.level != nil })?.level
    }

    func loadStress(_ repo: Repository) async {
        let cal = Calendar.current
        let from = Int(cal.startOfDay(for: Date()).timeIntervalSince1970)
        let to = Int(Date().timeIntervalSince1970)
        let tz = TimeZone.current.secondsFromGMT(for: Date())
        let hr = await repo.hrSamples(from: from, to: to, limit: 200_000)
        guard hr.count >= DaytimeStress.minHourHRSamples else { stress = .empty; stressLoadedAt = Date(); return }
        let rr = await repo.rrIntervals(from: from, to: to, limit: 200_000)
        let gravity = await repo.gravitySamplesUnion(from: from, to: to, limit: 200_000)
        stress = await runUnescalated(priority: .userInitiated) {
            DaytimeStress.analyze(hr: hr, rr: rr, gravity: gravity, tzOffsetSeconds: tz, mode: .dayRelative,
                                  includeTimeline: true)
        }
        stressLoadedAt = Date()
    }

    func value(_ m: WMetric, _ day: String) -> Double? { series[m]?[day] }

    /// Values for the `n` days ending at `end` (inclusive), oldest first; missing days are nil.
    func window(_ m: WMetric, end: Date, days n: Int) -> [(day: String, date: Date, value: Double?)] {
        let cal = Calendar.current
        var out: [(day: String, date: Date, value: Double?)] = []
        for back in (0..<n).reversed() {
            guard let d = cal.date(byAdding: .day, value: -back, to: end) else { continue }
            let k = Repository.localDayKey(d)
            out.append((day: k, date: cal.startOfDay(for: d), value: series[m]?[k]))
        }
        return out
    }

    func mean(_ m: WMetric, end: Date, days n: Int) -> Double? {
        let xs = window(m, end: end, days: n).compactMap(\.value)
        return xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    /// Average of the 30 days before `day`, the "vs. prior 30 days" baseline.
    func baseline(_ m: WMetric, before day: String) -> Double? {
        guard let d = WFmt.dayDate(day), let end = Calendar.current.date(byAdding: .day, value: -1, to: d) else { return nil }
        return mean(m, end: end, days: 30)
    }

    /// Latest day that has a value, with the value.
    func latest(_ m: WMetric) -> (day: String, value: Double)? {
        guard let s = series[m], let k = s.keys.max(), let v = s[k] else { return nil }
        return (k, v)
    }

    func load(_ repo: Repository) async {
        func dict(_ s: [(day: String, value: Double)]) -> [String: Double] {
            Dictionary(s.map { ($0.day, $0.value) }, uniquingKeysWith: { _, b in b })
        }
        var out: [WMetric: [String: Double]] = [:]
        func put(_ m: WMetric, _ day: String, _ v: Double?) {
            guard let v, v.isFinite else { return }
            out[m, default: [:]][day] = v
        }

        let perf = dict(await repo.exploreSeries(key: "sleep_performance", source: "my-whoop", days: 400))
        let needS = dict(await repo.exploreSeries(key: "sleep_need_min", source: "my-whoop", days: 400))
        let debt = dict(await repo.exploreSeries(key: "sleep_debt_min", source: "my-whoop", days: 400))
        let appleSteps = dict(await repo.series(key: "steps", source: "apple-health", days: 400))
        let appleKcal = dict(await repo.series(key: "active_kcal", source: "apple-health", days: 400))
        var eaten = dict(await repo.series(key: "calories_in", source: "nutrition-csv", days: 400))
        for (k, v) in dict(await repo.series(key: "dietary_kcal", source: "apple-health", days: 400)) { eaten[k] = v }
        var protein = dict(await repo.series(key: "protein_g", source: "nutrition-csv", days: 400))
        for (k, v) in dict(await repo.series(key: "protein_g", source: "apple-health", days: 400)) { protein[k] = v }
        let matAsleep = dict(await repo.series(key: "asleep_min", source: "apple-health", days: 400))
        let weightS = dict(await repo.series(key: "weight", source: "apple-health", days: 800))
        let bodyFatS = dict(await repo.series(key: "body_fat", source: "apple-health", days: 800))
        let leanS = dict(await repo.series(key: "lean_mass", source: "apple-health", days: 800))
        let vo2S = dict(await repo.series(key: "vo2max", source: "apple-health", days: 800))
        let rows = await repo.workoutRows(days: 400)

        var deepD: [String: Double] = [:], remD: [String: Double] = [:]
        for d in repo.days {
            put(.recovery, d.day, d.recovery)
            put(.hrv, d.day, d.avgHrv)
            put(.rhr, d.day, d.restingHr.map(Double.init))
            put(.respRate, d.day, d.respRateBpm)
            put(.spo2, d.day, d.spo2Pct.flatMap { $0 > 50 ? $0 : nil })
            put(.skinTemp, d.day, d.skinTempDevC.map { $0 * 1.8 })
            put(.strain, d.day, d.strain.map { UnitFormatter.effortValue($0, scale: .whoop) })
            put(.steps, d.day, d.steps.map(Double.init) ?? appleSteps[d.day])
            put(.calories, d.day, d.activeKcalEst ?? appleKcal[d.day])
            put(.hoursVsNeeded, d.day, d.totalSleepMin)
            put(.sleepEfficiency, d.day, d.efficiency.map { $0 <= 1 ? $0 * 100 : $0 })
            if let a = d.deepMin { deepD[d.day] = a }
            if let r = d.remMin { remD[d.day] = r }
            if let a = d.deepMin, let r = d.remMin { put(.restorative, d.day, a + r) }
        }
        for (k, v) in appleSteps where out[.steps]?[k] == nil { put(.steps, k, v) }
        for (k, v) in appleKcal where out[.calories]?[k] == nil { put(.calories, k, v) }
        for (k, v) in perf { put(.sleepPerformance, k, v) }
        for (k, v) in debt { put(.sleepDebt, k, v) }
        for (k, v) in matAsleep { put(.matSleep, k, v) }
        let toUnit: (Double) -> Double = { WMetric.imperial ? $0 * 2.2046226218 : $0 }
        for (k, v) in weightS { put(.weight, k, toUnit(v)) }
        for (k, v) in bodyFatS { put(.bodyFat, k, v <= 1 ? v * 100 : v) }
        for (k, v) in leanS { put(.leanMass, k, toUnit(v)) }
        for (k, v) in vo2S { put(.vo2max, k, v) }
        for (k, w) in weightS {
            guard let bfRaw = bodyFatS[k] else { continue }
            let bf = bfRaw <= 1 ? bfRaw * 100 : bfRaw
            put(.fatMass, k, toUnit(w * bf / 100))
            if leanS[k] == nil { put(.leanMass, k, toUnit(w * (1 - bf / 100))) }
        }
        for (k, v) in eaten { put(.caloriesIn, k, v) }
        for (k, v) in protein { put(.protein, k, v) }
        for (k, asleep) in out[.hoursVsNeeded] ?? [:] {
            if let n = needS[k], n > 0 { put(.hoursVsNeededPct, k, asleep / n * 100) }
        }
        for (k, inKcal) in eaten {
            if let burned = out[.calories]?[k] { put(.energyBalance, k, inKcal - burned) }
        }

        // Time in bed and 4-night consistency from the sleep sessions, keyed by wake day.
        let sessions = repo.sleeps.sorted { $0.endTs < $1.endTs }
        for s in sessions {
            let day = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(s.endTs)))
            put(.timeInBed, day, Double(max(0, s.endTs - s.effectiveStartTs)) / 60)
        }
        let cal = Calendar.current
        func minutesAfter6pm(_ ts: Int) -> Double {
            let d = Date(timeIntervalSince1970: TimeInterval(ts))
            let m = cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d)
            return Double((m - 18 * 60 + 1440) % 1440)
        }
        func sd(_ xs: [Double]) -> Double {
            let m = xs.reduce(0, +) / Double(xs.count)
            return (xs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(xs.count)).squareRoot()
        }
        for i in sessions.indices where i >= 3 {
            let four = sessions[(i - 3)...i]
            let spread = (sd(four.map { minutesAfter6pm($0.effectiveStartTs) }) + sd(four.map { minutesAfter6pm($0.endTs) })) / 2
            let day = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(sessions[i].endTs)))
            put(.sleepConsistency, day, max(0, min(100, 100 - spread / 120 * 100)))
        }

        // Workout-derived: HR-zone minutes and strength time per day.
        for r in rows {
            let day = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(r.startTs)))
            let minutes = (r.durationS ?? Double(r.endTs - r.startTs)) / 60
            if r.sport == LiftSessionView.sport || r.sport.lowercased().contains("strength") {
                out[.strengthTime, default: [:]][day, default: 0] += minutes
            }
            if let p = WorkoutZones.percents(r.zonesJSON) {
                out[.zones13, default: [:]][day, default: 0] += minutes * (p[0] + p[1] + p[2]) / 100
                out[.zones45, default: [:]][day, default: 0] += minutes * (p[3] + p[4]) / 100
            }
        }

        series = out
        need = needS
        deep = deepD
        rem = remD
        workouts = rows.sorted { $0.startTs > $1.startTs }
        loadedSeq = repo.refreshSeq
        loaded = true
    }
}
