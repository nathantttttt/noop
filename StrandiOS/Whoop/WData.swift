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
        case .sleepPerformance: "NOOP's sleep score: how much of the sleep you needed you got (45%), how restorative (15%), efficient (10%) and regular (10%) it was, and how your overnight HRV and resting heart rate compare with your normal (10% each)."
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
    /// Each night's sleep-score components (0…1), for the Sleep page breakdown.
    @Published private(set) var sleepParts: [String: [String: Double]] = [:]
    /// Per-workout zone minutes computed from strap HR, kept across reloads (a finished session's HR
    /// does not change).
    private var zoneCache: [String: [Double]] = [:]
    @Published private(set) var loaded = false

    /// Today's optimal strain range for the day's recovery, as fractions of the 0–21 dial.
    func strainTarget(_ day: String) -> ClosedRange<Double>? {
        guard let r = CoupledView.optimalStrainRange(recovery: value(.recovery, day)) else { return nil }
        return Double(r.lowerBound) / 21 ... Double(r.upperBound) / 21
    }

    /// Nights banked toward the first recovery score (NOOP needs 4), nil once recovery exists.
    static func recoveryCalibration(_ repo: Repository) -> Int? {
        RecoveryScorer.calibrationNights(nightlyHrv: repo.chargeBaselines?.hrvHistory.values ?? [],
                                         dayKeys: repo.chargeBaselines?.hrvHistory.dayKeys ?? [],
                                         hasRecovery: repo.today?.recovery != nil)
    }
    static let recoverySeedNights = Baselines.minNightsSeed

    /// Today's daytime stress (0–3 per hour), the same DaytimeStress read the Stress screen uses.
    @Published private(set) var stress: DaytimeStress.Result?
    @Published private(set) var stressLoadedAt: Date?

    var todayKey: String { Repository.localDayKey(Date()) }

    /// Latest scored hour's stress level, 0…3.
    var currentStress: Double? {
        let pts = (stress?.timeline.isEmpty == false ? stress?.timeline : stress?.hours) ?? []
        return pts.last(where: { $0.level != nil })?.level
    }

    /// "Today" or "Yesterday": which day `stress` describes. Early in the day there is too little heart
    /// rate to score, so the monitor keeps showing yesterday until today has some.
    @Published private(set) var stressDayLabel = "Today"

    func loadStress(_ repo: Repository) async {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: Date())
        let tz = TimeZone.current.secondsFromGMT(for: Date())
        func analyze(from: Date, to: Date) async -> DaytimeStress.Result? {
            let f = Int(from.timeIntervalSince1970), t = Int(to.timeIntervalSince1970)
            let hr = await repo.hrSamples(from: f, to: t, limit: 200_000)
            guard hr.count >= DaytimeStress.minHourHRSamples else { return nil }
            let rr = await repo.rrIntervals(from: f, to: t, limit: 200_000)
            let gravity = await repo.gravitySamplesUnion(from: f, to: t, limit: 200_000)
            let r = await runUnescalated(priority: .userInitiated) {
                DaytimeStress.analyze(hr: hr, rr: rr, gravity: gravity, tzOffsetSeconds: tz, mode: .dayRelative,
                                      includeTimeline: true)
            }
            let scored = (r.timeline.isEmpty ? r.hours : r.timeline).contains { $0.level != nil }
            return scored ? r : nil
        }
        if let today = await analyze(from: startToday, to: Date()) {
            stress = today
            stressDayLabel = "Today"
        } else if let y = cal.date(byAdding: .day, value: -1, to: startToday),
                  let yesterday = await analyze(from: y, to: startToday) {
            stress = yesterday
            stressDayLabel = "Yesterday"
        } else {
            stress = .empty
            stressDayLabel = "Today"
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

    /// The value for `day`, or else the most recent earlier one within `maxBack` days, so numbers stay
    /// on screen past midnight until a new reading replaces them.
    func carried(_ m: WMetric, _ day: String, maxBack: Int = 7) -> (value: Double, day: String)? {
        if let v = series[m]?[day] { return (v, day) }
        guard let d = WFmt.dayDate(day),
              let floor = Calendar.current.date(byAdding: .day, value: -maxBack, to: d).map(Repository.localDayKey),
              let s = series[m] else { return nil }
        guard let k = s.keys.filter({ $0 < day && $0 >= floor }).max(), let v = s[k] else { return nil }
        return (v, k)
    }

    /// "Yesterday" / "Tue" label for a carried value's day relative to `day`.
    static func asOf(_ valueDay: String, relativeTo day: String) -> String? {
        guard valueDay != day, let a = WFmt.dayDate(valueDay), let b = WFmt.dayDate(day) else { return nil }
        let n = Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
        if n == 1 { return "YESTERDAY" }
        return a.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    /// Latest day that has a value, with the value.
    func latest(_ m: WMetric) -> (day: String, value: Double)? {
        guard let s = series[m], let k = s.keys.max(), let v = s[k] else { return nil }
        return (k, v)
    }

    func load(_ repo: Repository, zoneSet: HRZoneSet? = nil) async {
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
        var vo2S = dict(await repo.exploreSeries(key: "vo2max_est", source: "my-whoop", days: 800))
        for (k, v) in dict(await repo.series(key: "vo2max", source: "apple-health", days: 800)) { vo2S[k] = v }
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
            if let bfRaw = bodyFatS[k] {
                let bf = bfRaw <= 1 ? bfRaw * 100 : bfRaw
                put(.fatMass, k, toUnit(w * bf / 100))
                if leanS[k] == nil { put(.leanMass, k, toUnit(w * (1 - bf / 100))) }
            } else if let lean = leanS[k], w > 0, lean < w {
                // No body-fat reading that day but weight and lean mass are there: fat = weight − lean.
                put(.bodyFat, k, (w - lean) / w * 100)
                put(.fatMass, k, toUnit(w - lean))
            }
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
            } else if let zoneSet, r.startTs > Int(Date().timeIntervalSince1970) - 120 * 86_400 {
                // No imported split: bin the strap's own heart rate for the session into the profile's zones.
                let key = "\(r.startTs)-\(r.endTs)"
                var z = zoneCache[key]
                if z == nil {
                    z = await repo.workoutZoneMinutes(from: r.startTs, to: r.endTs, zoneSet: zoneSet, source: r.source)
                    if let z { zoneCache[key] = z }
                }
                if let z, z.count >= 5 {
                    out[.zones13, default: [:]][day, default: 0] += z[0] + z[1] + z[2]
                    out[.zones45, default: [:]][day, default: 0] += z[3] + z[4]
                }
            }
        }

        // NOOP sleep score (Nathan's build): how much of the sleep you needed you got, how restorative and
        // efficient it was, how regular, and what your overnight HRV and resting HR say about it, each
        // against your own last 30 nights. Missing parts drop out and the rest re-weight.
        var parts: [String: [String: Double]] = [:]
        func baseline(_ m: WMetric, _ k: String) -> Double? {
            guard let d = WFmt.dayDate(k) else { return nil }
            let xs = (1...30).compactMap { b in
                Calendar.current.date(byAdding: .day, value: -b, to: d).flatMap { out[m]?[Repository.localDayKey($0)] }
            }
            return xs.count >= 5 ? xs.reduce(0, +) / Double(xs.count) : nil
        }
        for (k, asleep) in out[.hoursVsNeeded] ?? [:] where asleep >= 60 {
            var p: [String: Double] = [:]
            let needMin = needS[k] ?? 8 * 60
            p["sufficiency"] = min(1, asleep / max(needMin, 1))
            if let dp = deepD[k], let rm = remD[k] { p["restorative"] = min(1, (dp + rm) / asleep / 0.45) }
            if let e = out[.sleepEfficiency]?[k] { p["efficiency"] = max(0, min(1, (e - 70) / 25)) }
            if let c = out[.sleepConsistency]?[k] { p["consistency"] = max(0, min(1, c / 100)) }
            if let h = out[.hrv]?[k], let b = baseline(.hrv, k), b > 0 {
                p["hrv"] = max(0, min(1, 1 + (h - b) / b / 0.25))       // full at or above baseline, 0 at 25% below
            }
            if let r = out[.rhr]?[k], let b = baseline(.rhr, k), b > 0 {
                p["rhr"] = max(0, min(1, 1 - (r - b) / b / 0.10))       // full at or below baseline, 0 at 10% above
            }
            let weights: [String: Double] = ["sufficiency": 0.45, "restorative": 0.15, "efficiency": 0.10,
                                             "consistency": 0.10, "hrv": 0.10, "rhr": 0.10]
            let wsum = p.keys.compactMap { weights[$0] }.reduce(0, +)
            guard wsum > 0 else { continue }
            let score = p.reduce(0) { $0 + (weights[$1.key] ?? 0) * $1.value } / wsum * 100
            out[.sleepPerformance, default: [:]][k] = score
            parts[k] = p
        }
        sleepParts = parts

        series = out
        need = needS
        deep = deepD
        rem = remD
        workouts = rows.sorted { $0.startTs > $1.startTs }
        loadedSeq = repo.refreshSeq
        loaded = true
    }
}
