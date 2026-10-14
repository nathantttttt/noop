//  NathanSleepView.swift
//  Nathan's Sleep: night picker, sleep-performance ring, stage timeline + totals, overnight heart-rate
//  graph (low point and resting line marked), and 7-night HRV / RHR trends. The stock Sleep screen
//  stays one tap away for the deep detail.

import SwiftUI
import Charts
import StrandDesign
import WhoopStore
import WhoopProtocol

struct NathanSleepView: View {
    @EnvironmentObject var repo: Repository

    @State private var index = 0                 // 0 = newest night
    @State private var perf: [String: Double] = [:]
    @State private var need: [String: Double] = [:]
    @State private var hr: [HRBucket] = []
    @State private var hrNightId: Int?

    /// Newest first, one night per wake day (the dashboard's own merge).
    private var nights: [CachedSleepSession] {
        repo.sleeps.sorted { $0.endTs > $1.endTs }
    }
    private var night: CachedSleepSession? { nights.indices.contains(index) ? nights[index] : nil }
    private var wakeDay: String? { night.map { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.endTs))) } }
    private var dayRow: DailyMetric? { wakeDay.flatMap { d in repo.days.last(where: { $0.day == d }) } }

    private var decoded: (stages: Stages, intervals: [SleepInterval])? {
        guard let night else { return nil }
        return SleepView.decodeSegments(night.stagesJSON, sessionStart: night.effectiveStartTs)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NathanStyle.sectionGap) {
                nightPicker
                if night == nil {
                    NathanCard {
                        Text("No sleep recorded yet. Wear the strap overnight, then open NOOP in the morning so it can sync.")
                            .font(.system(size: 14, design: .rounded)).foregroundStyle(NathanStyle.text2)
                    }
                } else {
                    performanceCard
                    stagesCard
                    heartRateCard
                    vitalsTrends
                    NavigationLink { SleepView() } label: {
                        HStack {
                            Text("Full sleep details").font(.system(size: 15, weight: .semibold, design: .rounded))
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(NathanStyle.text2)
                        .padding(16)
                        .background(NathanStyle.card, in: RoundedRectangle(cornerRadius: NathanStyle.tileRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: NathanStyle.tileRadius, style: .continuous).stroke(NathanStyle.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
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

    // MARK: Performance

    private var asleepMin: Double? { decoded?.stages.asleep ?? dayRow?.totalSleepMin }

    private var performanceCard: some View {
        let p = wakeDay.flatMap { perf[$0] }
        let n = wakeDay.flatMap { need[$0] }
        return NathanCard {
            HStack(spacing: 20) {
                NathanRing(fraction: p.map { $0 / 100 }, color: NathanStyle.sleepColor, size: 112) {
                    VStack(spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(p.map(NathanFormat.int) ?? "—").font(NathanStyle.number(34)).foregroundStyle(NathanStyle.text)
                            if p != nil { Text("%").font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(NathanStyle.text3) }
                        }
                        Text("OF NEED").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(NathanStyle.sleepColor)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(asleepMin.map(NathanFormat.hmLong) ?? "—").font(NathanStyle.number(36)).foregroundStyle(NathanStyle.text)
                    if let n {
                        let short = (asleepMin ?? n) - n
                        Text(short < -10 ? "asleep · \(NathanFormat.hmLong(-short)) under need" : "asleep · need met")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(short < -10 ? NathanStyle.bad : NathanStyle.good)
                    } else {
                        Text("asleep").font(.system(size: 13, design: .rounded)).foregroundStyle(NathanStyle.text3)
                    }
                    if let night {
                        Text("\(NathanFormat.clock(night.effectiveStartTs)) → \(NathanFormat.clock(night.endTs))")
                            .font(.system(size: 13, design: .rounded)).foregroundStyle(NathanStyle.text2)
                    }
                }
            }
        }
    }

    // MARK: Stages

    private var stagesCard: some View {
        let s = decoded?.stages
        let deep = s?.deep ?? dayRow?.deepMin
        let rem = s?.rem ?? dayRow?.remMin
        let light = s?.light ?? dayRow?.lightMin
        let awake = s?.awake
        let asleep = [deep, rem, light].compactMap { $0 }.reduce(0, +)
        let longest = max(deep ?? 0, rem ?? 0, light ?? 0, awake ?? 0, 1)
        return NathanCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Stages").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(NathanStyle.text)
                if let intervals = decoded?.intervals, intervals.count >= 2 {
                    Hypnogram(intervals: intervals, height: 120, showsStageAxis: true, showsHover: true,
                              nightStart: night.map { Date(timeIntervalSince1970: TimeInterval($0.effectiveStartTs)) },
                              showsTimeAxis: true)
                }
                VStack(spacing: 0) {
                    stageRow("Deep", minutes: deep, of: asleep, longest: longest, color: StrandPalette.sleepDeep)
                    stageRow("REM", minutes: rem, of: asleep, longest: longest, color: StrandPalette.sleepREM)
                    stageRow("Light", minutes: light, of: asleep, longest: longest, color: StrandPalette.sleepLight)
                    stageRow("Awake", minutes: awake, of: nil, longest: longest, color: StrandPalette.sleepAwake, last: true)
                }
            }
        }
    }

    private func stageRow(_ name: String, minutes: Double?, of total: Double?, longest: Double, color: Color, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
                Text(name).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(NathanStyle.text)
                    .frame(width: 56, alignment: .leading)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NathanStyle.inset)
                        Capsule().fill(color).frame(width: g.size.width * min(1, (minutes ?? 0) / longest))
                    }
                }
                .frame(height: 6)
                HStack(spacing: 4) {
                    Text(minutes.map(NathanFormat.hm) ?? "—").bold().foregroundStyle(NathanStyle.text)
                    if let minutes, let total, total > 0 {
                        Text("· \(Int((minutes / total * 100).rounded()))%").foregroundStyle(NathanStyle.text3)
                    }
                }
                .font(.system(size: 14, design: .rounded))
                .frame(width: 92, alignment: .trailing)
            }
            .padding(.vertical, 11)
            if !last { Divider().overlay(NathanStyle.line) }
        }
    }

    // MARK: Heart rate overnight

    private var heartRateCard: some View {
        let points = hr.filter { $0.bpm > 25 }
        let low = points.min(by: { $0.bpm < $1.bpm })
        let high = points.max(by: { $0.bpm < $1.bpm })
        let resting = night?.restingHr ?? dayRow?.restingHr
        return NathanCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Heart rate overnight").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(NathanStyle.text)
                    Spacer()
                    Text("bpm").font(.system(size: 12, design: .rounded)).foregroundStyle(NathanStyle.text3)
                }
                HStack(spacing: 22) {
                    hrStat(resting.map(String.init) ?? "—", "Resting", NathanStyle.text)
                    hrStat(low.map { NathanFormat.int($0.bpm) } ?? "—",
                           low.map { "Lowest · \(NathanFormat.clock($0.ts))" } ?? "Lowest", NathanStyle.good)
                    hrStat(high.map { NathanFormat.int($0.bpm) } ?? "—", "Highest", NathanStyle.text)
                }
                if points.count >= 4 {
                    Chart {
                        ForEach(points, id: \.ts) { p in
                            LineMark(x: .value("Time", Date(timeIntervalSince1970: TimeInterval(p.ts))),
                                     y: .value("BPM", p.bpm))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(NathanStyle.text)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        if let resting {
                            RuleMark(y: .value("Resting", resting))
                                .foregroundStyle(NathanStyle.sleepColor)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        }
                        if let low {
                            PointMark(x: .value("Time", Date(timeIntervalSince1970: TimeInterval(low.ts))),
                                      y: .value("BPM", low.bpm))
                                .foregroundStyle(NathanStyle.good)
                                .symbolSize(60)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                            AxisGridLine().foregroundStyle(NathanStyle.line)
                            AxisValueLabel(format: .dateTime.hour()).foregroundStyle(NathanStyle.text3)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                            AxisGridLine().foregroundStyle(NathanStyle.line)
                            AxisValueLabel().foregroundStyle(NathanStyle.text3)
                        }
                    }
                    .frame(height: 150)
                    .accessibilityLabel("Heart rate through the night")
                    Text(lowNote(low: low))
                        .font(.system(size: 12, design: .rounded)).foregroundStyle(NathanStyle.text3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Not enough heart-rate data for this night yet.")
                        .font(.system(size: 13, design: .rounded)).foregroundStyle(NathanStyle.text3)
                }
            }
        }
    }

    private func hrStat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(NathanStyle.number(26)).foregroundStyle(color)
            Text(label).font(.system(size: 11, design: .rounded)).foregroundStyle(NathanStyle.text3)
        }
    }

    /// Where in the night the low landed: early lows usually mean better recovery.
    private func lowNote(low: HRBucket?) -> String {
        guard let low, let night, night.endTs > night.effectiveStartTs else { return "" }
        let frac = Double(low.ts - night.effectiveStartTs) / Double(night.endTs - night.effectiveStartTs)
        if frac < 0.5 {
            return "Your heart rate bottomed out in the first half of the night, which usually means good recovery."
        }
        return "Your heart rate bottomed out late in the night. Late lows often follow hard training, alcohol or a late meal."
    }

    // MARK: 7-night trends

    private var vitalsTrends: some View {
        let upTo = wakeDay ?? "9999"
        let recent = Array(repo.days.filter { $0.day <= upTo }.suffix(7))
        let hrv = recent.compactMap(\.avgHrv)
        let rhr = recent.compactMap { $0.restingHr.map(Double.init) }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            trendTile("HRV", values: hrv, unit: "ms", better: .up)
            trendTile("Resting HR", values: rhr, unit: "bpm", better: .down)
        }
    }

    private func trendTile(_ label: String, values: [Double], unit: String, better: NathanBetter) -> some View {
        let first = values.first, last = values.last
        let improving: Bool? = (first != nil && last != nil && first != last)
            ? (better == .up ? last! > first! : last! < first!) : nil
        let color = improving.map { $0 ? NathanStyle.good : NathanStyle.bad } ?? NathanStyle.text3
        let word: String = {
            guard let f = first, let l = last, f != l else { return "steady" }
            return l > f ? "trending up" : "trending down"
        }()
        return VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(NathanStyle.label).tracking(0.6).foregroundStyle(NathanStyle.text3)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(last.map(NathanFormat.int) ?? "—").font(NathanStyle.number(32)).foregroundStyle(NathanStyle.text)
                if last != nil { Text(unit).font(.system(size: 15, design: .rounded)).foregroundStyle(NathanStyle.text3) }
            }
            if values.count >= 2 {
                Chart(values.indices.map { NathanPoint(x: $0, y: values[$0]) }) { p in
                    LineMark(x: .value("Night", p.x), y: .value(label, p.y))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 28)
            }
            Text("\(values.count) nights · \(word)").font(.system(size: 12, design: .rounded)).foregroundStyle(color)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NathanStyle.card, in: RoundedRectangle(cornerRadius: NathanStyle.tileRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NathanStyle.tileRadius, style: .continuous).stroke(NathanStyle.line, lineWidth: 1))
    }

    // MARK: Load

    private func loadSeries() async {
        func dict(_ s: [(day: String, value: Double)]) -> [String: Double] {
            Dictionary(s.map { ($0.day, $0.value) }, uniquingKeysWith: { _, b in b })
        }
        perf = dict(await repo.exploreSeries(key: "sleep_performance", source: "my-whoop", days: 120))
        need = dict(await repo.exploreSeries(key: "sleep_need_min", source: "my-whoop", days: 120))
    }

    private func loadHeartRate() async {
        guard let night else { hr = []; return }
        let buckets = await repo.hrBuckets(from: night.effectiveStartTs, to: night.endTs, bucketSeconds: 180)
        hr = buckets
        hrNightId = night.endTs
    }
}
