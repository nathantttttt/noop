//  NathanWorkoutView.swift
//  Nathan's Workout tab: Lift (the Lift Log), Cardio (start a recorded activity or log a past one) and
//  History (every logged activity, newest first). Tapping any activity opens its detail: what it was,
//  when, its stats, and a heart-rate graph you can drag across.

import SwiftUI
import Charts
import StrandDesign
import WhoopStore
import WhoopProtocol

struct NathanWorkoutView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case lift = "Lift", cardio = "Cardio", history = "History"
        var id: String { rawValue }
    }
    @AppStorage("nathan.workout.pane") private var paneRaw = Pane.lift.rawValue
    private var pane: Binding<Pane> {
        Binding(get: { Pane(rawValue: paneRaw) ?? .lift }, set: { paneRaw = $0.rawValue })
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Workout type", selection: pane) {
                ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, NathanStyle.page)
            .padding(.top, 8)
            .padding(.bottom, 4)

            switch pane.wrappedValue {
            case .lift: LiftLogView()
            case .cardio: NathanCardioPane()
            case .history: NathanHistoryPane()
            }
        }
        .background(NathanStyle.canvas.ignoresSafeArea())
    }
}

// MARK: - Shared helpers

enum NathanActivity {
    static func isLift(_ w: WorkoutRow) -> Bool { w.sport == LiftSessionView.sport }

    static func icon(_ sport: String) -> String {
        let s = sport.lowercased()
        if s.contains("strength") || s.contains("lift") || s.contains("weight") { return "dumbbell.fill" }
        if s.contains("cycl") || s.contains("bike") || s.contains("spin") { return "figure.outdoor.cycle" }
        if s.contains("run") || s.contains("jog") { return "figure.run" }
        if s.contains("walk") || s.contains("hik") { return "figure.walk" }
        if s.contains("pickle") || s.contains("tennis") || s.contains("padel") { return "figure.tennis" }
        if s.contains("golf") { return "figure.golf" }
        if s.contains("swim") { return "figure.pool.swim" }
        if s.contains("row") { return "figure.rower" }
        if s.contains("basket") { return "figure.basketball" }
        if s.contains("yoga") || s.contains("stretch") { return "figure.yoga" }
        return "figure.mixed.cardio"
    }

    static func duration(_ w: WorkoutRow) -> Int { max(0, w.endTs - w.startTs) }

    static func durationText(_ seconds: Int) -> String {
        let m = seconds / 60
        return m >= 60 ? "\(m / 60)h \(String(format: "%02d", m % 60))m" : "\(m) min"
    }

    static func strain21(_ w: WorkoutRow) -> Double? { w.strain.map { UnitFormatter.effortValue($0, scale: .whoop) } }

    static func miles(_ meters: Double) -> Double { meters / 1609.344 }
}

struct NathanActivityRow: View {
    let workout: WorkoutRow
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: NathanActivity.icon(workout.sport))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NathanActivity.isLift(workout) ? NathanStyle.accent : NathanStyle.strainColor)
                .frame(width: 42, height: 42)
                .background(NathanStyle.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(NathanActivity.isLift(workout) ? (workout.notes?.isEmpty == false ? workout.notes! : "Lift")
                     : WorkoutSource.displaySport(workout.sport))
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(NathanStyle.text)
                    .lineLimit(1)
                Text(Date(timeIntervalSince1970: TimeInterval(workout.startTs))
                        .formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                     + " · " + NathanActivity.durationText(NathanActivity.duration(workout)))
                    .font(.system(size: 12)).foregroundStyle(NathanStyle.text3)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let s = NathanActivity.strain21(workout) {
                    Text(NathanFormat.one(s)).font(NathanStyle.number(18)).foregroundStyle(NathanStyle.strainColor)
                }
                if let hr = workout.avgHr {
                    Text("\(hr) avg").font(.system(size: 11)).foregroundStyle(NathanStyle.text3)
                }
            }
            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(NathanStyle.text3)
        }
        .padding(12)
        .background(NathanStyle.card, in: RoundedRectangle(cornerRadius: NathanStyle.tileRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NathanStyle.tileRadius, style: .continuous).stroke(NathanStyle.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Cardio

struct NathanCardioPane: View {
    @EnvironmentObject var repo: Repository
    @State private var recent: [WorkoutRow] = []
    @State private var logging = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NathanStyle.sectionGap) {
                VStack(alignment: .leading, spacing: NathanStyle.gap) {
                    Text("Cardio").font(.system(size: 28, weight: .heavy)).foregroundStyle(NathanStyle.text)
                    Text("Bike, run, walk, pickleball, golf — anything. Start one to record your heart rate live, or log one you already did.")
                        .font(.system(size: 14)).foregroundStyle(NathanStyle.text2)
                    WorkoutStartControl()
                    Button { logging = true } label: {
                        Label("Log a past activity", systemImage: "square.and.pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .foregroundStyle(NathanStyle.text)
                            .background(NathanStyle.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NathanStyle.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                zone2Week
                VStack(alignment: .leading, spacing: NathanStyle.gap) {
                    NathanSectionHeader(title: "Recent cardio")
                    if recent.isEmpty {
                        Text("Nothing yet.").font(.system(size: 14)).foregroundStyle(NathanStyle.text3)
                    }
                    ForEach(recent.prefix(12), id: \.startTs) { w in
                        NavigationLink { NathanActivityDetail(workout: w) } label: { NathanActivityRow(workout: w) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, NathanStyle.page)
            .padding(.vertical, 12)
        }
        .refreshable { await load() }
        .task(id: repo.refreshSeq) { await load() }
        .sheet(isPresented: $logging) {
            ManualWorkoutSheet { row, old in
                Task { await repo.saveManualWorkout(row, replacing: old); await load() }
            }
        }
    }

    /// Minutes of cardio this week vs last week (Mon-start weeks).
    private var zone2Week: some View {
        let cal = Calendar(identifier: .iso8601)
        let now = Date()
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let lastStart = cal.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let thisMin = recent.filter { Date(timeIntervalSince1970: TimeInterval($0.startTs)) >= weekStart }
            .reduce(0) { $0 + NathanActivity.duration($1) } / 60
        let lastMin = recent.filter {
            let d = Date(timeIntervalSince1970: TimeInterval($0.startTs)); return d >= lastStart && d < weekStart
        }.reduce(0) { $0 + NathanActivity.duration($1) } / 60
        let delta = NathanDelta.make(current: Double(thisMin), baseline: Double(lastMin), better: .up,
                                     format: NathanFormat.int, suffix: " min vs last week", deadband: 0)
        return NathanCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("This week").font(.system(size: 15, weight: .bold)).foregroundStyle(NathanStyle.text)
                    Spacer()
                    Text(delta?.text ?? "").font(.system(size: 12, weight: .medium)).foregroundStyle(delta?.color ?? NathanStyle.text3)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(thisMin)").font(NathanStyle.number(34)).foregroundStyle(NathanStyle.text)
                    Text("/ 150 min cardio").font(.system(size: 14)).foregroundStyle(NathanStyle.text3)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NathanStyle.inset)
                        Capsule().fill(NathanStyle.strainColor).frame(width: g.size.width * min(1, Double(thisMin) / 150))
                    }
                }
                .frame(height: 8)
            }
        }
    }

    private func load() async {
        let rows = await repo.workoutRows(days: 30)
        recent = rows.filter { !NathanActivity.isLift($0) && NathanActivity.duration($0) >= 5 * 60 }
            .sorted { $0.startTs > $1.startTs }
    }
}

// MARK: - History

struct NathanHistoryPane: View {
    @EnvironmentObject var repo: Repository
    @State private var rows: [WorkoutRow] = []
    @State private var filter = 0   // 0 all, 1 lift, 2 cardio

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NathanStyle.gap) {
                Text("History").font(.system(size: 28, weight: .heavy)).foregroundStyle(NathanStyle.text)
                Picker("Show", selection: $filter) {
                    Text("All").tag(0); Text("Lifts").tag(1); Text("Cardio").tag(2)
                }
                .pickerStyle(.segmented)
                let shown = rows.filter { filter == 0 || (filter == 1) == NathanActivity.isLift($0) }
                if shown.isEmpty {
                    Text("No activities yet.").font(.system(size: 14)).foregroundStyle(NathanStyle.text3)
                        .padding(.top, 8)
                }
                ForEach(shown, id: \.startTs) { w in
                    NavigationLink { NathanActivityDetail(workout: w) } label: { NathanActivityRow(workout: w) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, NathanStyle.page)
            .padding(.vertical, 12)
        }
        .refreshable { await load() }
        .task(id: repo.refreshSeq) { await load() }
    }

    private func load() async {
        rows = await repo.workoutRows(days: 365)
            .filter { NathanActivity.duration($0) >= 3 * 60 }
            .sorted { $0.startTs > $1.startTs }
    }
}

// MARK: - Activity detail

struct NathanActivityDetail: View {
    @EnvironmentObject var repo: Repository
    let workout: WorkoutRow
    @State private var points: [NathanHRPoint] = []
    @State private var loaded = false

    private var avgHr: Int? {
        workout.avgHr ?? (points.isEmpty ? nil : Int((points.map(\.bpm).reduce(0, +) / Double(points.count)).rounded()))
    }
    private var maxHr: Int? { workout.maxHr ?? points.map(\.bpm).max().map { Int($0.rounded()) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NathanStyle.sectionGap) {
                header
                stats
                NathanCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Heart rate").font(.system(size: 15, weight: .bold)).foregroundStyle(NathanStyle.text)
                            Spacer()
                            Text("Drag to see any moment").font(.system(size: 12)).foregroundStyle(NathanStyle.text3)
                        }
                        if points.count >= 4 {
                            NathanScrubHRChart(points: points, height: 220, color: NathanStyle.bad, restingLine: nil)
                        } else {
                            Text(loaded ? "No heart-rate data was recorded for this activity." : "Loading…")
                                .font(.system(size: 13)).foregroundStyle(NathanStyle.text3)
                        }
                    }
                }
                if let notes = workout.notes, !notes.isEmpty, !NathanActivity.isLift(workout) {
                    NathanCard {
                        Text(notes).font(.system(size: 14)).foregroundStyle(NathanStyle.text2)
                    }
                }
            }
            .padding(.horizontal, NathanStyle.page)
            .padding(.vertical, 12)
        }
        .background(NathanStyle.canvas.ignoresSafeArea())
        .navigationTitle(NathanActivity.isLift(workout) ? "Lift" : WorkoutSource.displaySport(workout.sport))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: NathanActivity.icon(workout.sport))
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(NathanActivity.isLift(workout) ? NathanStyle.accent : NathanStyle.strainColor)
                .frame(width: 56, height: 56)
                .background(NathanStyle.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(NathanActivity.isLift(workout) ? (workout.notes ?? "Lift") : WorkoutSource.displaySport(workout.sport))
                    .font(.system(size: 24, weight: .heavy)).foregroundStyle(NathanStyle.text)
                Text(Date(timeIntervalSince1970: TimeInterval(workout.startTs))
                        .formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                     + " · " + NathanFormat.clock(workout.startTs) + " – " + NathanFormat.clock(workout.endTs))
                    .font(.system(size: 13)).foregroundStyle(NathanStyle.text3)
            }
        }
    }

    private var stats: some View {
        var tiles: [(String, String, String)] = [
            ("Duration", NathanActivity.durationText(NathanActivity.duration(workout)), ""),
            ("Avg HR", avgHr.map(String.init) ?? "—", avgHr == nil ? "" : "bpm"),
            ("Max HR", maxHr.map(String.init) ?? "—", maxHr == nil ? "" : "bpm"),
            ("Strain", NathanActivity.strain21(workout).map(NathanFormat.one) ?? "—", ""),
        ]
        if let kcal = workout.energyKcal { tiles.append(("Calories", NathanFormat.grouped(kcal), "kcal")) }
        if let m = workout.distanceM, m > 0 { tiles.append(("Distance", String(format: "%.2f", NathanActivity.miles(m)), "mi")) }
        if let steps = workout.steps { tiles.append(("Steps", NathanFormat.grouped(Double(steps)), "")) }
        let shown = tiles
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(shown.indices, id: \.self) { i in
                NathanTile(label: shown[i].0, value: shown[i].1, unit: shown[i].2)
            }
        }
    }

    private func load() async {
        let span = workout.endTs - workout.startTs
        if span <= 3 * 3600 {
            let samples = await repo.hrSamples(from: workout.startTs, to: workout.endTs, limit: 20_000)
            points = samples.filter { $0.bpm > 30 }.map { NathanHRPoint(ts: $0.ts, bpm: Double($0.bpm)) }
        } else {
            let b = await repo.hrBuckets(from: workout.startTs, to: workout.endTs, bucketSeconds: 15)
            points = b.filter { $0.bpm > 30 }.map { NathanHRPoint(ts: $0.ts, bpm: $0.bpm) }
        }
        loaded = true
    }
}

// MARK: - Scrubbable heart-rate chart

struct NathanHRPoint: Identifiable, Equatable {
    let ts: Int
    let bpm: Double
    var id: Int { ts }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(ts)) }
}

/// Line chart of heart rate. Press and drag to read the exact bpm and time at any point.
struct NathanScrubHRChart: View {
    let points: [NathanHRPoint]
    var height: CGFloat = 180
    var color: Color = NathanStyle.text
    var restingLine: Int? = nil
    var markLow: Bool = false
    @State private var selected: Date?

    private var nearest: NathanHRPoint? {
        guard let selected, !points.isEmpty else { return nil }
        let t = Int(selected.timeIntervalSince1970)
        var lo = 0, hi = points.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].ts < t { lo = mid + 1 } else { hi = mid }
        }
        if lo > 0, abs(points[lo - 1].ts - t) < abs(points[lo].ts - t) { return points[lo - 1] }
        return points[lo]
    }

    private var low: NathanHRPoint? { markLow ? points.min(by: { $0.bpm < $1.bpm }) : nil }

    var body: some View {
        Chart {
            ForEach(points) { p in
                LineMark(x: .value("Time", p.date), y: .value("BPM", p.bpm))
                    .interpolationMethod(.linear)
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
            }
            if let restingLine {
                RuleMark(y: .value("Resting", restingLine))
                    .foregroundStyle(NathanStyle.sleepColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
            }
            if let low {
                PointMark(x: .value("Time", low.date), y: .value("BPM", low.bpm))
                    .foregroundStyle(NathanStyle.good).symbolSize(60)
            }
            if let p = nearest {
                RuleMark(x: .value("Selected", p.date))
                    .foregroundStyle(NathanStyle.text3)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 1) {
                            Text("\(Int(p.bpm.rounded())) bpm").font(.system(size: 13, weight: .bold))
                                .foregroundStyle(NathanStyle.text)
                            Text(p.date.formatted(.dateTime.hour().minute()))
                                .font(.system(size: 11)).foregroundStyle(NathanStyle.text3)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(NathanStyle.inset, in: RoundedRectangle(cornerRadius: 8))
                    }
                PointMark(x: .value("Selected", p.date), y: .value("BPM", p.bpm))
                    .foregroundStyle(NathanStyle.text).symbolSize(40)
            }
        }
        .chartXSelection(value: $selected)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(NathanStyle.line)
                AxisValueLabel(format: .dateTime.hour().minute()).foregroundStyle(NathanStyle.text3)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(NathanStyle.line)
                AxisValueLabel().foregroundStyle(NathanStyle.text3)
            }
        }
        .frame(height: height)
        .padding(.top, 26)
        .accessibilityLabel("Heart rate chart")
    }
}
