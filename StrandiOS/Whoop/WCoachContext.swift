//  WCoachContext.swift
//  Nathan's build: the extra data summary the Coach gets on top of NOOP's own context, so it can answer
//  about everything the app shows: a 14-day daily table, body composition trend, nutrition, sleep mat,
//  NOOP Age with its biggest factors, this week's sets per muscle and the last few lift sessions.
//  Text summaries only; no raw sensor streams leave the phone.

import Foundation
import WhoopStore

@MainActor
enum WCoachContext {
    static func build(data: WhoopData, repo: Repository, age: Int) async -> String {
        var out: [String] = ["## Nathan's app data (NOOP, on-device summary)"]
        let cal = Calendar.current
        let today = Date()
        let unit = WMetric.massUnit

        // Daily table
        out.append("### Last 14 days (date | recovery % | HRV ms | RHR | sleep h (need h, perf %) | strain 0-21 | steps | kcal burned | kcal eaten | protein g)")
        for back in (0..<14).reversed() {
            guard let d = cal.date(byAdding: .day, value: -back, to: today) else { continue }
            let k = Repository.localDayKey(d)
            func f(_ m: WMetric, _ fmt: (Double) -> String = { WFmt.int($0) }) -> String { data.value(m, k).map(fmt) ?? "-" }
            let sleep = data.value(.hoursVsNeeded, k).map { WFmt.hm($0) } ?? "-"
            let need = data.need[k].map { WFmt.hm($0) } ?? "-"
            out.append("\(k) | \(f(.recovery)) | \(f(.hrv)) | \(f(.rhr)) | \(sleep) (\(need), \(f(.sleepPerformance))) | \(f(.strain, WFmt.one)) | \(f(.steps)) | \(f(.calories)) | \(f(.caloriesIn)) | \(f(.protein))")
        }

        // 30-day averages vs prior 30
        out.append("### 30-day averages (vs. the 30 days before)")
        let prev = cal.date(byAdding: .day, value: -30, to: today) ?? today
        for m in [WMetric.recovery, .hrv, .rhr, .respRate, .sleepPerformance, .hoursVsNeeded, .sleepConsistency, .strain, .steps, .caloriesIn, .protein] {
            guard let a = data.mean(m, end: today, days: 30) else { continue }
            let b = data.mean(m, end: prev, days: 30)
            let fa = m.isDuration ? WFmt.hm(a) : m.format(a)
            let fb = b.map { m.isDuration ? WFmt.hm($0) : m.format($0) } ?? "n/a"
            out.append("- \(m.title): \(fa) \(m.unit) (prior \(fb))")
        }

        // Body composition
        var body: [String] = []
        for m in [WMetric.weight, .bodyFat, .leanMass, .fatMass, .vo2max] {
            guard let l = data.latest(m) else { continue }
            let old = data.window(m, end: today, days: 90).first { $0.value != nil }?.value
            let change = old.map { " (90-day change \(String(format: "%+.1f", l.value - $0)))" } ?? ""
            body.append("- \(m.title): \(m.format(l.value)) \(m.unit) on \(l.day)\(change)")
        }
        if !body.isEmpty { out.append("### Body composition (InBody scale via Apple Health, mass in \(unit))"); out += body }

        // Sleep mat
        let mat = data.window(.matSleep, end: today, days: 7).compactMap { d in d.value.map { "\(d.day): \(WFmt.hm($0))" } }
        if !mat.isEmpty { out.append("### Withings sleep mat, time asleep (last 7 nights)"); out.append(mat.joined(separator: ", ")) }

        // NOOP Age
        let ageR = data.ageResult(chronologicalAge: age)
        if ageR.hasData {
            out.append("### NOOP Age (estimate): \(WFmt.one(ageR.age)) vs chronological \(age), pace of aging \(String(format: "%.1fx", ageR.pace))")
            for r in ageR.rows {
                guard let y = r.years else { continue }
                out.append("- \(r.factor.title): 6-mo avg \(r.sixMonth.map { WFmt.one($0) } ?? "-"), 30-day \(r.thirtyDay.map { WFmt.one($0) } ?? "-"), impact \(String(format: "%+.1f", y)) years")
            }
        }

        // Stress today
        if let s = data.stress, let v = data.currentStress {
            out.append("### Stress today: current \(WFmt.one(v))/3, high-stress time \(WFmt.hm(Double(s.highStressMinutes)))")
        }

        // Lifting
        if let store = await repo.storeHandle() {
            let now = Int(today.timeIntervalSince1970)
            let weekAgo = now - 7 * 86_400
            if let counts = try? await store.liftSetCounts(deviceId: repo.deviceId, fromTs: weekAgo, toTs: now).fractional, !counts.isEmpty {
                out.append("### Working sets per muscle, last 7 days (secondary muscles count half)")
                out.append(counts.sorted { $0.value > $1.value }.map { "\($0.key.rawValue) \(WFmt.one($0.value))" }.joined(separator: ", "))
            }
            let sessions = ((try? await store.liftSessions(deviceId: repo.deviceId, fromTs: now - 45 * 86_400, toTs: now)) ?? [])
                .filter { $0.endTs != nil }.sorted { $0.startTs > $1.startTs }.prefix(6)
            if !sessions.isEmpty {
                out.append("### Recent lift sessions (exercise: sets as weight×reps, \(unit))")
                for s in sessions {
                    let rows = (try? await store.liftSets(sessionId: s.id)) ?? []
                    var byEx: [(String, [String])] = []
                    for r in rows.sorted(by: { ($0.ord, $0.setIndex) < ($1.ord, $1.setIndex) }) where !r.isWarmup {
                        let w = r.weightKg.map { WMetric.imperial ? $0 * 2.2046226218 : $0 }.map { WFmt.int($0) } ?? "bw"
                        let set = "\(w)×\(r.reps ?? 0)"
                        if let i = byEx.firstIndex(where: { $0.0 == r.exercise }) { byEx[i].1.append(set) } else { byEx.append((r.exercise, [set])) }
                    }
                    let day = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(s.startTs)))
                    out.append("- \(day) \(s.programName ?? s.sport): " + byEx.map { "\($0.0) \($0.1.joined(separator: ", "))" }.joined(separator: "; "))
                }
            }
        }
        out.append("Training plan: lifts Tue/Thu/Sat (Workout A/B alternating). Goals: lower resting HR, raise HRV, lower body fat, raise lean mass. Calories are tracked in MacroFactor.")
        return out.joined(separator: "\n")
    }
}
