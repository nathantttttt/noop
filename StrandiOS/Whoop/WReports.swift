//
//  WReports.swift
//  NOOP (Nathan's build)
//
//  Two reports that come to you:
//  - the morning summary, a local notification posted once a day after the night has synced, with the
//    sleep score, recovery and today's strain target;
//  - the weekly report, Monday to Sunday against the week before, with Coach takeaways, announced by a
//    notification every Sunday evening.
//  All local: notifications are scheduled on the phone, and the takeaways use the Coach key you set up.
//

import SwiftUI
import Combine
import UserNotifications
import WhoopStore

/// Opens a page from a tapped notification.
final class WDeepLink: ObservableObject {
    static let shared = WDeepLink()
    @Published var weeklyReport = 0
}

// MARK: - Morning summary

@MainActor
enum WMorningSummary {
    static let enabledKey = "w.morningSummary"
    static let sentKey = "w.morningSummary.sentDay"
    private static var bag: AnyCancellable?
    private static var busy = false

    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Watches the daily history; each change after a night has finished may post today's summary.
    static func start(_ repo: Repository) {
        guard bag == nil else { return }
        bag = repo.$days
            .debounce(for: .seconds(4), scheduler: RunLoop.main)
            .sink { _ in Task { @MainActor in await check(repo) } }
        WWeeklyReport.scheduleNotification()
        if enabled || WWeeklyReport.enabled {
            UNUserNotificationCenter.current().getNotificationSettings { s in
                if s.authorizationStatus == .notDetermined {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
                        if ok { Task { @MainActor in WWeeklyReport.scheduleNotification() } }
                    }
                }
            }
        }
    }

    static func check(_ repo: Repository) async {
        guard enabled, !busy else { return }
        let now = Date()
        let today = Repository.localDayKey(now)
        guard UserDefaults.standard.string(forKey: sentKey) != today else { return }
        let nights = repo.sleeps.filter {
            Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.endTs))) == today
                && $0.endTs - $0.effectiveStartTs >= 3 * 3600
        }
        guard let night = nights.max(by: { $0.endTs < $1.endTs }),
              Double(night.endTs) < now.timeIntervalSince1970 - 15 * 60 else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        busy = true
        defer { busy = false }
        let data = WhoopData()
        await data.load(repo)
        let recovery = data.value(.recovery, today)
        // Recovery is scored a moment after the night lands; wait for it unless NOOP is still calibrating
        // or two hours have passed since waking.
        let calibrating = WhoopData.recoveryCalibration(repo) != nil
        if recovery == nil, !calibrating, now.timeIntervalSince1970 - Double(night.endTs) < 2 * 3600 { return }

        let sleep = data.value(.sleepPerformance, today)
        let asleep = data.value(.hoursVsNeeded, today)
        var title = "Good morning"
        if let r = recovery { title += " · Recovery \(Int(r.rounded()))%" }
        var parts: [String] = []
        if let s = sleep { parts.append("Sleep \(Int(s.rounded()))%") }
        if let a = asleep {
            let need = data.need[today].map { " of \(WFmt.hm($0)) needed" } ?? ""
            parts.append("\(WFmt.hm(a)) asleep\(need)")
        }
        if let band = CoupledView.optimalStrainRange(recovery: recovery) {
            parts.append("Strain target \(band.lowerBound)–\(band.upperBound)")
        } else if calibrating, let n = WhoopData.recoveryCalibration(repo) {
            parts.append("Recovery calibrating, \(n) of \(WhoopData.recoverySeedNights) nights")
        }
        var vitals: [String] = []
        if let h = data.value(.hrv, today) { vitals.append("HRV \(Int(h.rounded())) ms") }
        if let r = data.value(.rhr, today) { vitals.append("RHR \(Int(r.rounded()))") }
        if !vitals.isEmpty { parts.append(vitals.joined(separator: ", ")) }
        guard !parts.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = parts.joined(separator: " · ") + "."
        content.sound = .default
        content.categoryIdentifier = "w.morning"
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "w.morning.\(today)", content: content, trigger: nil))
        UserDefaults.standard.set(today, forKey: sentKey)
    }
}

// MARK: - Weekly report

struct WWeeklyReport {
    struct Row: Identifiable {
        let id: String
        let this: Double?
        let last: Double?
        let higherIsBetter: Bool?
        let format: (Double) -> String
    }

    let start: Date          // Monday
    let end: Date            // Sunday
    var rows: [Row] = []
    var training: Row?
    var lifts = 0, liftSets = 0, liftLb = 0.0, lastLiftLb = 0.0, workouts = 0, workoutMin = 0.0
    var body: [Row] = []

    static let enabledKey = "w.weeklyReport"
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Every Sunday at 6 PM, a local notification that the week's report is ready.
    static func scheduleNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["w.weekly"])
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your weekly report is ready"
        content.body = "See how this week compared with last, with Coach takeaways for next week."
        content.sound = .default
        content.categoryIdentifier = "w.weekly"
        var when = DateComponents()
        when.weekday = 1; when.hour = 18; when.minute = 0
        center.add(UNNotificationRequest(identifier: "w.weekly", content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
    }

    /// The week shown: Monday to Sunday, the current one on Sunday, otherwise the last finished one.
    static func week(offset: Int = 0, now: Date = Date()) -> (start: Date, end: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let today = cal.startOfDay(for: now)
        let wd = cal.component(.weekday, from: today)          // 1 = Sunday
        let back = wd == 1 ? 0 : wd - 1
        let sunday = cal.date(byAdding: .day, value: -back - 7 * offset, to: today) ?? today
        return (cal.date(byAdding: .day, value: -6, to: sunday) ?? sunday, sunday)
    }

    @MainActor static func build(data: WhoopData, repo: Repository, offset: Int = 0) async -> WWeeklyReport {
        let (start, end) = week(offset: offset)
        let prevEnd = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? end
        var r = WWeeklyReport(start: start, end: end)

        func avg(_ m: WMetric, _ e: Date) -> Double? { data.mean(m, end: e, days: 7) }
        func change(_ m: WMetric, _ e: Date) -> Double? {
            // Last reading of the week minus the last reading before it.
            let w = data.window(m, end: e, days: 7).compactMap(\.value)
            guard let last = w.last, let k = Calendar.current.date(byAdding: .day, value: -7, to: e),
                  let before = data.carried(m, Repository.localDayKey(k), maxBack: 21)?.value else { return nil }
            return last - before
        }
        let int: (Double) -> String = { "\(Int($0.rounded()))" }
        let pct: (Double) -> String = { "\(Int($0.rounded()))%" }
        let hm: (Double) -> String = { WFmt.hm($0) }
        let one: (Double) -> String = { WFmt.one($0) }
        let unit = WMetric.massUnit
        let signed: (Double) -> String = { ($0 >= 0 ? "+" : "−") + WFmt.one(abs($0)) + " \(unit)" }
        let signedPct: (Double) -> String = { ($0 >= 0 ? "+" : "−") + WFmt.one(abs($0)) + "%" }

        r.rows = [
            Row(id: "Recovery", this: avg(.recovery, end), last: avg(.recovery, prevEnd), higherIsBetter: true, format: pct),
            Row(id: "HRV", this: avg(.hrv, end), last: avg(.hrv, prevEnd), higherIsBetter: true, format: { int($0) + " ms" }),
            Row(id: "Resting HR", this: avg(.rhr, end), last: avg(.rhr, prevEnd), higherIsBetter: false, format: { int($0) + " bpm" }),
            Row(id: "Sleep score", this: avg(.sleepPerformance, end), last: avg(.sleepPerformance, prevEnd), higherIsBetter: true, format: pct),
            Row(id: "Hours asleep", this: avg(.hoursVsNeeded, end), last: avg(.hoursVsNeeded, prevEnd), higherIsBetter: true, format: hm),
            Row(id: "Sleep consistency", this: avg(.sleepConsistency, end), last: avg(.sleepConsistency, prevEnd), higherIsBetter: true, format: pct),
            Row(id: "Strain", this: avg(.strain, end), last: avg(.strain, prevEnd), higherIsBetter: nil, format: one),
            Row(id: "Steps", this: avg(.steps, end), last: avg(.steps, prevEnd), higherIsBetter: true, format: { WFmt.grouped($0) }),
            Row(id: "Calories eaten", this: avg(.caloriesIn, end), last: avg(.caloriesIn, prevEnd), higherIsBetter: nil, format: { WFmt.grouped($0) }),
            Row(id: "Protein", this: avg(.protein, end), last: avg(.protein, prevEnd), higherIsBetter: true, format: { int($0) + " g" }),
        ]
        r.body = [
            Row(id: "Weight", this: change(.weight, end), last: nil, higherIsBetter: nil, format: signed),
            Row(id: "Lean mass", this: change(.leanMass, end), last: nil, higherIsBetter: true, format: signed),
            Row(id: "Body fat", this: change(.bodyFat, end), last: nil, higherIsBetter: false, format: signedPct),
        ]

        let from = Int(start.timeIntervalSince1970), to = Int(end.timeIntervalSince1970) + 86_400
        let pFrom = from - 7 * 86_400
        for w in data.workouts where w.startTs >= from && w.startTs < to {
            r.workouts += 1
            r.workoutMin += (w.durationS ?? Double(w.endTs - w.startTs)) / 60
        }
        if let store = await repo.storeHandle() {
            let sessions = ((try? await store.liftSessions(deviceId: repo.deviceId, fromTs: pFrom, toTs: to)) ?? [])
                .filter { $0.endTs != nil }
            for s in sessions {
                let sets = ((try? await store.liftSets(sessionId: s.id)) ?? []).filter { !$0.isWarmup && ($0.reps ?? 0) > 0 }
                let kg = sets.reduce(0.0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
                if s.startTs >= from {
                    r.lifts += 1; r.liftSets += sets.count; r.liftLb += kg / 0.45359237
                } else {
                    r.lastLiftLb += kg / 0.45359237
                }
            }
        }
        return r
    }

    var rangeText: String {
        "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// Plain-text version for the Coach.
    var text: String {
        var out = ["WEEKLY REPORT \(rangeText) (averages, this week vs last week)"]
        for row in rows {
            out.append("- \(row.id): \(row.this.map(row.format) ?? "no data") (last week \(row.last.map(row.format) ?? "no data"))")
        }
        out.append("- Workouts: \(workouts), \(Int(workoutMin.rounded())) min")
        out.append("- Lift sessions: \(lifts), \(liftSets) working sets, \(WFmt.grouped(liftLb)) lb lifted (last week \(WFmt.grouped(lastLiftLb)) lb)")
        for row in body { out.append("- \(row.id) change over the week: \(row.this.map(row.format) ?? "no data")") }
        return out.joined(separator: "\n")
    }

    var instruction: String {
        """
        \(text)

        Write my weekly report takeaways from the report above and the full data. Format:
        Verdict: one line on how the week went.
        Wins: up to three, each with the number behind it.
        Fix next week: up to three, each a specific action for training, sleep or nutrition.
        Focus: one thing for next week.
        Under 180 words. Short lines, no headings beyond those four labels, no markdown symbols.
        """
    }
}

// MARK: - Weekly report page

struct WWeeklyReportView: View {
    @EnvironmentObject var data: WhoopData
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var coach: AICoachEngine
    @State private var offset = 0
    @State private var report: WWeeklyReport?
    @State private var takeaways: String?
    @State private var thinking = false
    @State private var failed = false
    @State private var failReason: String?

    private var cacheKey: String { "w.weekly.takeaways.\(Repository.localDayKey(WWeeklyReport.week(offset: offset).end))" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: W.rowGap) {
                HStack {
                    Button { step(1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text((report?.rangeText ?? "").uppercased()).font(W.caps(14)).tracking(1.4).foregroundStyle(W.text)
                    Spacer()
                    Button { step(-1) } label: { Image(systemName: "chevron.right") }
                        .disabled(offset == 0).opacity(offset == 0 ? 0.3 : 1)
                }
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(W.text)
                .padding(.vertical, 6)

                takeawaysCard
                if let r = report {
                    WCard {
                        VStack(alignment: .leading, spacing: 12) {
                            WCardHeader(title: "This Week vs Last")
                            ForEach(r.rows) { row in rowView(row) }
                        }
                    }
                    WCard {
                        VStack(alignment: .leading, spacing: 12) {
                            WCardHeader(title: "Training")
                            stat("Workouts", "\(r.workouts)", "\(Int(r.workoutMin.rounded())) min")
                            stat("Lift sessions", "\(r.lifts)", "\(r.liftSets) working sets")
                            stat("Pounds lifted", WFmt.grouped(r.liftLb), r.lastLiftLb > 0 ? "last week \(WFmt.grouped(r.lastLiftLb))" : "")
                        }
                    }
                    WCard {
                        VStack(alignment: .leading, spacing: 12) {
                            WCardHeader(title: "Body This Week")
                            ForEach(r.body) { row in
                                stat(row.id, row.this.map(row.format) ?? "—", row.this == nil ? "needs a scan this week and before" : "",
                                     color: color(row.this, row.higherIsBetter))
                            }
                        }
                    }
                } else {
                    ProgressView().tint(W.text).frame(maxWidth: .infinity).padding(40)
                }
                Toggle(isOn: Binding(get: { WWeeklyReport.enabled }, set: {
                    UserDefaults.standard.set($0, forKey: WWeeklyReport.enabledKey)
                    WWeeklyReport.scheduleNotification()
                })) {
                    Text("Sunday notification").font(W.body(16)).foregroundStyle(W.text)
                }
                .tint(W.mint)
                .padding(.horizontal, 4).padding(.top, 6)
            }
            .padding(.horizontal, W.margin)
            .padding(.bottom, 30)
        }
        .wPage(title: "Weekly Report")
        .task(id: offset) { await reload() }
    }

    private func step(_ by: Int) {
        let n = max(0, offset + by)
        guard n != offset else { return }
        WHaptics.select()
        offset = n
    }

    private func reload() async {
        report = nil
        takeaways = UserDefaults.standard.string(forKey: cacheKey)
        failed = false
        report = await WWeeklyReport.build(data: data, repo: repo, offset: offset)
        if takeaways == nil, offset == 0 { await ask() }
    }

    private func ask() async {
        guard let r = report, !thinking else { return }
        thinking = true
        failed = false
        let key = cacheKey
        let reply = await coach.generate(instruction: r.instruction)
        thinking = false
        if let reply {
            takeaways = reply
            UserDefaults.standard.set(reply, forKey: key)
        } else {
            failed = true
            failReason = coach.lastGenerateError
        }
    }

    private var takeawaysCard: some View {
        WCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(W.mint)
                    WCardHeader(title: "Coach Takeaways")
                }
                if let t = takeaways {
                    Text(t).font(W.body(15)).foregroundStyle(W.text).fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } else if thinking {
                    HStack(spacing: 10) {
                        ProgressView().tint(W.text)
                        Text("Reading your week…").font(W.body(15)).foregroundStyle(W.text2)
                    }
                } else {
                    Text(failed ? "The Coach couldn't answer: \(failReason ?? "unknown error"). Tap to try again."
                                : "Ask the Coach what this week means for next week.")
                        .font(W.body(15)).foregroundStyle(W.text2).fixedSize(horizontal: false, vertical: true)
                }
                if !thinking, report != nil {
                    Button { Task { await ask() } } label: {
                        Text(takeaways == nil ? "GET TAKEAWAYS" : "REFRESH").font(W.caps(13)).tracking(1.3).foregroundStyle(W.lineBlue)
                    }
                }
            }
        }
    }

    private func color(_ delta: Double?, _ higher: Bool?) -> Color {
        guard let d = delta, let higher, abs(d) > 0.05 else { return W.text }
        return (d > 0) == higher ? W.mint : W.orange
    }

    private func rowView(_ row: WWeeklyReport.Row) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(row.id.uppercased()).font(W.caps(13)).tracking(1.1).foregroundStyle(W.text)
            Spacer()
            if let t = row.this, let l = row.last, l != 0 {
                let d = (t - l) / abs(l) * 100
                if abs(d) >= 1 {
                    HStack(spacing: 3) {
                        Image(systemName: d > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 9))
                        Text("\(Int(abs(d).rounded()))%")
                    }
                    .font(W.caps(12)).foregroundStyle(color(d, row.higherIsBetter) == W.text ? W.text3 : color(d, row.higherIsBetter))
                }
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(row.this.map(row.format) ?? "—").font(W.num(19)).foregroundStyle(W.text)
                Text("LAST \(row.last.map(row.format) ?? "—")").font(W.caps(10)).foregroundStyle(W.text3)
            }
            .frame(minWidth: 82, alignment: .trailing)
        }
    }

    private func stat(_ title: String, _ value: String, _ note: String, color: Color = W.text) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased()).font(W.caps(13)).tracking(1.1).foregroundStyle(W.text)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(value).font(W.num(19)).foregroundStyle(color)
                if !note.isEmpty { Text(note.uppercased()).font(W.caps(10)).foregroundStyle(W.text3) }
            }
        }
    }
}

/// Home card on Sundays and Mondays: the week's report is ready.
struct WWeeklyReportCard: View {
    var body: some View {
        NavigationLink(value: WRoute.weeklyReport) {
            WCard(padding: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "calendar.badge.checkmark").font(.system(size: 28, weight: .light)).foregroundStyle(W.mint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WEEKLY REPORT").font(W.caps(14)).tracking(1.5).foregroundStyle(W.text)
                        Text("\(WWeeklyReport.week().start.formatted(.dateTime.month(.abbreviated).day())) – \(WWeeklyReport.week().end.formatted(.dateTime.month(.abbreviated).day())) · with Coach takeaways")
                            .font(W.body(14)).foregroundStyle(W.text2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(W.text3)
                }
            }
        }
        .buttonStyle(WPressStyle())
    }
}
