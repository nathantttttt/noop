//  WLiftStats.swift
//  Nathan's build: the top of the Lift pane. A training heat map (every day you lifted, last 18 weeks)
//  with consistency against the Tue / Thu / Sat plan, lifetime pounds lifted, and this week's working
//  sets per muscle group against a 10-set target. Everything is read from the Lift Log store.

import SwiftUI
import WhoopStore

struct WLiftStats: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var session: LiftSessionController
    @AppStorage(UnitPrefs.systemKey) private var unitRaw = UnitSystem.imperial.rawValue
    @AppStorage("nathan.lift.weeklySetTarget") private var setTarget = 10
    @AppStorage("nathan.lift.weeklySessionTarget") private var sessionTarget = 3

    @State private var dayVolume: [String: Double] = [:]      // day → kg lifted
    @State private var lifetimeKg: Double = 0
    @State private var lifetimeSets = 0
    @State private var sessionCount = 0
    @State private var weekKg: Double = 0
    @State private var weekSets: [LiftMuscle: Double] = [:]
    @State private var loaded = false

    private var imperial: Bool { (UnitSystem(rawValue: unitRaw) ?? .imperial) == .imperial }
    private func mass(_ kg: Double) -> Double { imperial ? kg * 2.2046226218 : kg }
    private var unit: String { imperial ? "lb" : "kg" }

    private static let weeks = 18

    var body: some View {
        VStack(alignment: .leading, spacing: W.rowGap) {
            heatmapCard
            volumeCard
            muscleCard
        }
        .task(id: "\(repo.refreshSeq)-\(session.savedSessions)") { await load() }
    }

    // MARK: Heat map

    private var weekStart: Date {
        var cal = Calendar.current
        cal.firstWeekday = 1
        let today = cal.startOfDay(for: Date())
        let wd = cal.component(.weekday, from: today)
        return cal.date(byAdding: .day, value: -(wd - 1), to: today) ?? today
    }

    private func sessionsInWeek(_ start: Date) -> Int {
        (0..<7).filter { i in
            guard let d = Calendar.current.date(byAdding: .day, value: i, to: start) else { return false }
            return dayVolume[Repository.localDayKey(d)] != nil
        }.count
    }

    /// Consecutive weeks (not counting the current one unless it is already met) that hit the target.
    private var streak: Int {
        var n = 0
        let cal = Calendar.current
        if sessionsInWeek(weekStart) >= sessionTarget { n += 1 }
        for back in 1..<52 {
            guard let s = cal.date(byAdding: .day, value: -7 * back, to: weekStart) else { break }
            if sessionsInWeek(s) >= sessionTarget { n += 1 } else { break }
        }
        return n
    }

    private var heatmapCard: some View {
        let cal = Calendar.current
        let maxV = max(1, dayVolume.values.max() ?? 1)
        let first = cal.date(byAdding: .day, value: -7 * (Self.weeks - 1), to: weekStart) ?? weekStart
        let today = cal.startOfDay(for: Date())
        let last30 = (0..<30).filter { i in
            cal.date(byAdding: .day, value: -i, to: today).map { dayVolume[Repository.localDayKey($0)] != nil } ?? false
        }.count
        return WCard {
            VStack(alignment: .leading, spacing: 14) {
                WCardHeader(title: "Training Consistency")
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .trailing, spacing: 3) {
                        ForEach(["S", "M", "T", "W", "T", "F", "S"].indices, id: \.self) { i in
                            Text(["S", "M", "T", "W", "T", "F", "S"][i]).font(W.caps(9, .semibold)).foregroundStyle(W.text3)
                                .frame(height: 14)
                        }
                    }
                    HStack(spacing: 3) {
                        ForEach(0..<Self.weeks, id: \.self) { w in
                            VStack(spacing: 3) {
                                ForEach(0..<7, id: \.self) { d in
                                    let date = cal.date(byAdding: .day, value: w * 7 + d, to: first) ?? first
                                    let v = dayVolume[Repository.localDayKey(date)]
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(date > today ? Color.clear
                                              : v == nil ? Color.white.opacity(0.07)
                                              : W.mint.opacity(0.35 + 0.65 * min(1, (v ?? 0) / maxV)))
                                        .frame(height: 14)
                                }
                            }
                        }
                    }
                }
                HStack(spacing: 0) {
                    stat("\(sessionsInWeek(weekStart))/\(sessionTarget)", "THIS WEEK")
                    Spacer()
                    stat("\(streak)", streak == 1 ? "WEEK STREAK" : "WEEK STREAK")
                    Spacer()
                    stat("\(last30)", "LIFTS · 30 DAYS")
                }
            }
        }
    }

    private func stat(_ v: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(v).font(W.num(26)).foregroundStyle(W.text)
            Text(label).font(W.caps(11)).tracking(1.1).foregroundStyle(W.text3)
        }
    }

    // MARK: Lifetime volume

    private var volumeCard: some View {
        WCard {
            VStack(alignment: .leading, spacing: 10) {
                WCardHeader(title: "Lifetime Volume")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(loaded ? WFmt.grouped(mass(lifetimeKg)) : "--").font(W.num(44, .heavy)).foregroundStyle(W.text)
                        .contentTransition(.numericText())
                    Text(unit + " lifted").font(W.body(18, .medium)).foregroundStyle(W.text2)
                }
                Text("\(WFmt.grouped(Double(lifetimeSets))) working sets across \(sessionCount) session\(sessionCount == 1 ? "" : "s") · \(WFmt.grouped(mass(weekKg))) \(unit) this week")
                    .font(W.body(15)).foregroundStyle(W.text3)
            }
        }
    }

    // MARK: Sets per muscle

    private struct MuscleGroup: Identifiable {
        let id: String
        let muscles: [LiftMuscle]
    }

    private static let groups: [MuscleGroup] = [
        MuscleGroup(id: "Chest", muscles: [.chest]),
        MuscleGroup(id: "Back", muscles: [.lats, .upperBack, .traps]),
        MuscleGroup(id: "Shoulders", muscles: [.frontDelts, .sideDelts, .rearDelts]),
        MuscleGroup(id: "Biceps", muscles: [.biceps]),
        MuscleGroup(id: "Triceps", muscles: [.triceps]),
        MuscleGroup(id: "Quads", muscles: [.quads]),
        MuscleGroup(id: "Hamstrings", muscles: [.hamstrings]),
        MuscleGroup(id: "Glutes", muscles: [.glutes]),
        MuscleGroup(id: "Calves", muscles: [.calves]),
        MuscleGroup(id: "Abs", muscles: [.abs, .obliques]),
    ]

    private var muscleCard: some View {
        let target = Double(max(1, setTarget))
        let hit = Self.groups.filter { g in g.muscles.map { weekSets[$0] ?? 0 }.reduce(0, +) >= target }.count
        return WCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("SETS PER MUSCLE · THIS WEEK").font(W.caps(14)).tracking(1.4).foregroundStyle(W.text)
                    Spacer()
                    Stepper("", value: $setTarget, in: 4...30).labelsHidden().scaleEffect(0.8)
                }
                Text("\(hit) of \(Self.groups.count) muscle groups at \(setTarget)+ sets. Secondary muscles count as half a set.")
                    .font(W.body(14)).foregroundStyle(W.text3)
                ForEach(Self.groups) { g in
                    let v = g.muscles.map { weekSets[$0] ?? 0 }.reduce(0, +)
                    let ok = v >= target
                    HStack(spacing: 10) {
                        Text(g.id.uppercased()).font(W.caps(12)).tracking(1.1).foregroundStyle(W.text).frame(width: 92, alignment: .leading)
                        GeometryReader { geo in
                            let w = geo.size.width
                            let scale = max(target * 1.6, v)
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.07))
                                Capsule().fill(ok ? W.mint : (v > 0 ? W.orange : Color.clear))
                                    .frame(width: max(v > 0 ? 6 : 0, w * v / scale))
                                Rectangle().fill(W.text.opacity(0.8)).frame(width: 2, height: 14).offset(x: w * target / scale - 1)
                            }
                        }
                        .frame(height: 10)
                        Text(v == v.rounded() ? "\(Int(v))" : WFmt.one(v)).font(W.num(16)).foregroundStyle(ok ? W.mint : W.text)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: Load

    private func load() async {
        guard let store = await repo.storeHandle() else { return }
        let now = Int(Date().timeIntervalSince1970)
        let sessions = ((try? await store.liftSessions(deviceId: repo.deviceId, fromTs: 0, toTs: now)) ?? [])
            .filter { $0.endTs != nil }
        var byDay: [String: Double] = [:]
        var total = 0.0, sets = 0, week = 0.0
        let weekFrom = Int(weekStart.timeIntervalSince1970)
        for s in sessions {
            let rows = (try? await store.liftSets(sessionId: s.id)) ?? []
            var kg = 0.0
            for r in rows where !r.isWarmup {
                guard let reps = r.reps, reps > 0 else { continue }
                sets += 1
                kg += (r.weightKg ?? 0) * Double(reps)
            }
            let day = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(s.startTs)))
            byDay[day, default: 0] += max(kg, 1)
            total += kg
            if s.startTs >= weekFrom { week += kg }
        }
        // Strength sessions logged outside the Lift Log (imported or manual) still mark the day.
        for w in await repo.workoutRows(days: 7 * Self.weeks + 7) where w.sport == LiftSessionView.sport || w.sport.lowercased().contains("strength") {
            let day = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(w.startTs)))
            if byDay[day] == nil { byDay[day] = 1 }
        }
        let counts = (try? await store.liftSetCounts(deviceId: repo.deviceId, fromTs: weekFrom, toTs: now).fractional) ?? [:]
        withAnimation(.easeOut(duration: 0.4)) {
            dayVolume = byDay
            lifetimeKg = total
            lifetimeSets = sets
            sessionCount = sessions.count
            weekKg = week
            weekSets = counts
            loaded = true
        }
    }
}
