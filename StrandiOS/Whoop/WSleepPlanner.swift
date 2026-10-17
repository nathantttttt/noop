//
//  WSleepPlanner.swift
//  NOOP (Nathan's build)
//
//  Tonight's bedtime, worked out from what tonight's sleep needs to cover: a personal baseline, extra
//  for today's strain, and part of the recent sleep debt. The need is asleep time, so it is divided by
//  your usual sleep efficiency and given 15 minutes to fall asleep before it becomes time in bed. An
//  optional reminder fires 30 minutes before the chosen bedtime.
//

import SwiftUI
import UserNotifications
import WhoopStore

struct WSleepPlan {
    var baseline: Double          // asleep minutes a normal night needs
    var strainAdd: Double         // extra asleep minutes for today's strain
    var debt: Double              // weighted shortfall over the last 7 nights
    var debtRepay: Double         // the part of that debt tonight should pay back
    var efficiency: Double        // 0–1, asleep / in bed
    var latency: Double = 15      // minutes to fall asleep
    var wake: Date
    var wakeIsUsual: Bool         // wake time read from your recent nights rather than set by you
    var baselineFromHistory: Bool
    var strain: Double?

    var asleepNeed: Double { baseline + strainAdd + debtRepay }
    func inBedMinutes(_ goal: Double) -> Double { asleepNeed * goal / efficiency + latency }
    func bedtime(_ goal: Double) -> Date { wake.addingTimeInterval(-inBedMinutes(goal) * 60) }

    static let goals: [(name: String, pct: Double, note: String)] = [
        ("Peak", 1.0, "All of tonight's need"),
        ("Perform", 0.85, "85% of tonight's need"),
        ("Get By", 0.70, "70% of tonight's need"),
    ]

    static let wakeKey = "w.planner.wakeMinutes"     // minutes after midnight; absent = use usual
    static let goalKey = "w.planner.goal"
    static let reminderKey = "w.planner.reminder"

    /// The usual wake time (minutes after midnight): the median wake of the last 7 nights.
    @MainActor static func usualWakeMinutes(_ repo: Repository) -> Int? {
        let cal = Calendar.current
        let recent = repo.sleeps.sorted { $0.endTs > $1.endTs }.prefix(7)
        let mins = recent.map { s -> Int in
            let d = Date(timeIntervalSince1970: TimeInterval(s.endTs))
            return cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d)
        }.sorted()
        guard mins.count >= 2 else { return nil }
        return mins[mins.count / 2]
    }

    @MainActor static func make(data: WhoopData, repo: Repository, now: Date = Date()) -> WSleepPlan {
        let cal = Calendar.current
        let today = Repository.localDayKey(now)

        // Baseline: the lower quartile of the needs NOOP has on record (those carry debt and strain on top
        // of the baseline, so the low end is closest to a plain night), else 8 hours.
        let needs = data.need.values.filter { $0 >= 300 && $0 <= 720 }.sorted()
        let fromHistory = needs.count >= 5
        let baseline = fromHistory ? min(540, max(420, needs[needs.count / 4])) : 480

        // Debt: each of the last 7 nights' shortfall against the baseline, recent nights weighted most.
        let weights: [Double] = [1, 0.8, 0.65, 0.5, 0.4, 0.3, 0.2]
        var debt = 0.0
        for (back, w) in weights.enumerated() {
            guard let d = cal.date(byAdding: .day, value: -back, to: now),
                  let asleep = data.value(.hoursVsNeeded, Repository.localDayKey(d)) else { continue }
            debt += max(0, baseline - asleep) * w
        }
        let repay = min(75, debt / 3)

        // Strain: a light day adds nothing; each point above 8 adds 3 minutes, up to 45.
        let strain = data.value(.strain, today)
        let strainAdd = min(45, max(0, ((strain ?? 0) - 8) * 3))

        let effs = (0..<14).compactMap { b -> Double? in
            cal.date(byAdding: .day, value: -b, to: now).flatMap { data.value(.sleepEfficiency, Repository.localDayKey($0)) }
        }.sorted()
        let efficiency = effs.isEmpty ? 0.9 : min(0.97, max(0.75, effs[effs.count / 2] / 100))

        let set = UserDefaults.standard.object(forKey: wakeKey) as? Int
        let wakeMin = set ?? usualWakeMinutes(repo) ?? 6 * 60 + 30
        var wake = cal.date(bySettingHour: wakeMin / 60, minute: wakeMin % 60, second: 0, of: now) ?? now
        if wake < now.addingTimeInterval(3600) { wake = cal.date(byAdding: .day, value: 1, to: wake) ?? wake }

        return WSleepPlan(baseline: baseline, strainAdd: strainAdd, debt: debt, debtRepay: repay,
                          efficiency: efficiency, wake: wake, wakeIsUsual: set == nil,
                          baselineFromHistory: fromHistory, strain: strain)
    }

    static var goalIndex: Int {
        min(goals.count - 1, max(0, UserDefaults.standard.integer(forKey: goalKey)))
    }

    /// Schedules (or clears) tonight's wind-down reminder for the chosen goal's bedtime.
    static func scheduleReminder(_ plan: WSleepPlan) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["w.planner.bedtime"])
        guard UserDefaults.standard.bool(forKey: reminderKey) else { return }
        let g = goals[goalIndex]
        let bed = plan.bedtime(g.pct)
        let fire = bed.addingTimeInterval(-30 * 60)
        guard fire > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Bedtime in 30 minutes"
        content.body = "Be in bed by \(bed.formatted(date: .omitted, time: .shortened)) to wake at "
            + "\(plan.wake.formatted(date: .omitted, time: .shortened)) with \(WFmt.hm(plan.asleepNeed * g.pct)) of sleep (\(g.name))."
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        center.add(UNNotificationRequest(identifier: "w.planner.bedtime", content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
}

// MARK: - Home card

struct WSleepPlannerCard: View {
    @EnvironmentObject var data: WhoopData
    @EnvironmentObject var repo: Repository
    @AppStorage(WSleepPlan.goalKey) private var goal = 0

    var body: some View {
        let plan = WSleepPlan.make(data: data, repo: repo)
        let g = WSleepPlan.goals[min(2, max(0, goal))]
        NavigationLink(value: WRoute.sleepPlanner) {
            WCard {
                VStack(alignment: .leading, spacing: 10) {
                    WCardHeader(title: "Sleep Planner", chevron: true)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Bed by").font(W.body(17)).foregroundStyle(W.text2)
                        Text(plan.bedtime(g.pct).formatted(date: .omitted, time: .shortened))
                            .font(W.num(34)).foregroundStyle(W.text)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "moon.fill").foregroundStyle(W.sleep)
                        Text("\(g.name.uppercased()) · WAKE \(plan.wake.formatted(date: .omitted, time: .shortened)) · NEED \(WFmt.hm(plan.asleepNeed))")
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .font(W.caps(12, .semibold)).foregroundStyle(W.text3)
                }
            }
        }
        .buttonStyle(WPressStyle())
    }
}

// MARK: - Planner page

struct WSleepPlannerView: View {
    @EnvironmentObject var data: WhoopData
    @EnvironmentObject var repo: Repository
    @AppStorage(WSleepPlan.goalKey) private var goal = 0
    @AppStorage(WSleepPlan.reminderKey) private var reminder = false
    @State private var wakePick = Date()
    @State private var tick = 0

    var body: some View {
        let _ = tick
        let plan = WSleepPlan.make(data: data, repo: repo)
        let g = WSleepPlan.goals[min(2, max(0, goal))]
        ScrollView {
            VStack(alignment: .leading, spacing: W.rowGap) {
                WCard {
                    VStack(spacing: 6) {
                        Text("TONIGHT").font(W.caps(13)).tracking(1.5).foregroundStyle(W.text3)
                        Text(plan.bedtime(g.pct).formatted(date: .omitted, time: .shortened))
                            .font(W.num(56)).foregroundStyle(W.text)
                        Text("Go to bed by this time to wake at \(plan.wake.formatted(date: .omitted, time: .shortened)) with \(WFmt.hm(plan.asleepNeed * g.pct)) of sleep.")
                            .font(W.body(15)).foregroundStyle(W.text2).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }

                WCard {
                    VStack(alignment: .leading, spacing: 4) {
                        WCardHeader(title: "Sleep Goal")
                        ForEach(WSleepPlan.goals.indices, id: \.self) { i in
                            let gi = WSleepPlan.goals[i]
                            Button {
                                WHaptics.select(); goal = i; WSleepPlan.scheduleReminder(plan)
                            } label: {
                                HStack {
                                    Image(systemName: goal == i ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(goal == i ? W.mint : W.text3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(gi.name.uppercased()).font(W.caps(14)).tracking(1.2).foregroundStyle(W.text)
                                        Text(gi.note).font(W.body(13)).foregroundStyle(W.text3)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(plan.bedtime(gi.pct).formatted(date: .omitted, time: .shortened))
                                            .font(W.num(20)).foregroundStyle(W.text)
                                        Text("\(WFmt.hm(plan.inBedMinutes(gi.pct))) IN BED").font(W.caps(11)).foregroundStyle(W.text3)
                                    }
                                }
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if i < 2 { Divider().overlay(W.hairline) }
                        }
                    }
                }

                WCard {
                    VStack(alignment: .leading, spacing: 12) {
                        WCardHeader(title: "Wake Time")
                        DatePicker("Wake up at", selection: $wakePick, displayedComponents: .hourAndMinute)
                            .font(W.body(16)).foregroundStyle(W.text).tint(W.mint)
                            .onChange(of: wakePick) { _, v in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: v)
                                UserDefaults.standard.set((c.hour ?? 6) * 60 + (c.minute ?? 30), forKey: WSleepPlan.wakeKey)
                                tick += 1
                                WSleepPlan.scheduleReminder(WSleepPlan.make(data: data, repo: repo))
                            }
                        if plan.wakeIsUsual {
                            Text("Using your usual wake time from your last 7 nights. Pick a time to set your own.")
                                .font(W.body(13)).foregroundStyle(W.text3)
                        } else if let usual = WSleepPlan.usualWakeMinutes(repo) {
                            Button {
                                UserDefaults.standard.removeObject(forKey: WSleepPlan.wakeKey)
                                wakePick = Self.date(minutes: usual)
                                tick += 1
                            } label: {
                                Text("USE MY USUAL (\(Self.date(minutes: usual).formatted(date: .omitted, time: .shortened)))")
                                    .font(W.caps(13)).tracking(1).foregroundStyle(W.lineBlue)
                            }
                        }
                    }
                }

                WCard {
                    VStack(alignment: .leading, spacing: 12) {
                        WCardHeader(title: "Tonight's Sleep Need")
                        needRow("Baseline", plan.baseline, plan.baselineFromHistory ? "From your recorded sleep needs" : "8 hours until NOOP has your history", sign: false)
                        needRow("Strain", plan.strainAdd, plan.strain.map { "Today's strain \(WFmt.one($0))" } ?? "No strain yet today", sign: true)
                        needRow("Sleep debt", plan.debtRepay, "A third of your \(WFmt.hm(plan.debt)) debt from the last 7 nights", sign: true)
                        Divider().overlay(W.hairline)
                        HStack {
                            Text("TOTAL ASLEEP").font(W.caps(14)).tracking(1.2).foregroundStyle(W.text)
                            Spacer()
                            Text(WFmt.hm(plan.asleepNeed)).font(W.num(22)).foregroundStyle(W.mint)
                        }
                        Text("Asleep time becomes time in bed at your usual \(Int((plan.efficiency * 100).rounded()))% sleep efficiency, plus 15 minutes to fall asleep.")
                            .font(W.body(13)).foregroundStyle(W.text3).fixedSize(horizontal: false, vertical: true)
                    }
                }

                WCard {
                    Toggle(isOn: $reminder) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Bedtime reminder").font(W.body(17, .semibold)).foregroundStyle(W.text)
                            Text("A notification 30 minutes before your \(g.name) bedtime.").font(W.body(13)).foregroundStyle(W.text3)
                        }
                    }
                    .tint(W.mint)
                    .onChange(of: reminder) { _, on in
                        if on {
                            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                                Task { @MainActor in WSleepPlan.scheduleReminder(plan) }
                            }
                        } else {
                            WSleepPlan.scheduleReminder(plan)
                        }
                    }
                }
            }
            .padding(.horizontal, W.margin)
            .padding(.vertical, 12)
        }
        .wPage(title: "Sleep Planner")
        .onAppear {
            let m = (UserDefaults.standard.object(forKey: WSleepPlan.wakeKey) as? Int)
                ?? WSleepPlan.usualWakeMinutes(repo) ?? 390
            wakePick = Self.date(minutes: m)
        }
    }

    static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    private func needRow(_ title: String, _ minutes: Double, _ note: String, sign: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased()).font(W.caps(13)).tracking(1.2).foregroundStyle(W.text)
                Text(note).font(W.body(13)).foregroundStyle(W.text3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text((sign ? "+" : "") + WFmt.hm(minutes)).font(W.num(19)).foregroundStyle(W.text)
        }
    }
}
