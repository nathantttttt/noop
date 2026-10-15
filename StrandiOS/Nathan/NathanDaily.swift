//  NathanDaily.swift
//  The morning journal (opens full screen once a day after last night's sleep lands), the "something's
//  off" signals card for Today, and Nathan's settings screen.

import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Morning journal

struct NathanMorningJournal: View {
    @EnvironmentObject var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var importedQuestions: [String] = []
    @State private var answers: [String: Bool] = [:]
    @State private var numeric: [String: Double] = [:]
    @State private var dayOffset = 1   // yesterday

    private var dayKey: String {
        Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NathanStyle.sectionGap) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Good morning").font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(NathanStyle.text)
                        Text("Log what you did yesterday. Over a few weeks NOOP learns which habits raise or lower your recovery and sleep.")
                            .font(.system(size: 14)).foregroundStyle(NathanStyle.text2)
                    }
                    JournalLogCard(importedQuestions: importedQuestions, answers: answers,
                                   numericAnswers: numeric, dayOffset: $dayOffset,
                                   onChanged: { Task { await load() } })
                    NavigationLink { InsightsHubView() } label: {
                        HStack {
                            Image(systemName: "wand.and.sparkles")
                            Text("See what moves your recovery").font(.system(size: 15, weight: .semibold))
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
                .padding(.horizontal, NathanStyle.page)
                .padding(.vertical, 16)
            }
            .background(NathanStyle.canvas.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.bold).foregroundStyle(NathanStyle.accent)
                }
            }
        }
        .task(id: dayOffset) { await load() }
    }

    private func load() async {
        let imported = await repo.importedJournalEntries()
        var seen = Set<String>(), qs: [String] = []
        for e in imported where seen.insert(e.question).inserted { qs.append(e.question) }
        importedQuestions = qs
        answers = await repo.nativeJournalAnswers(day: dayKey)
        numeric = await repo.nativeJournalNumeric(day: dayKey)
    }
}

/// Decides whether the morning journal should open: on, last night's sleep has landed for today, and it
/// has not been shown today.
enum NathanMorningJournalGate {
    static let enabledKey = "nathan.morningJournal"
    static let shownKey = "nathan.morningJournal.shownDay"

    static func shouldShow(today: DailyMetric?, now: Date = Date(), _ d: UserDefaults = .standard) -> Bool {
        guard d.bool(forKey: enabledKey), let today, today.totalSleepMin != nil else { return false }
        let key = Repository.localDayKey(now)
        guard Calendar.current.component(.hour, from: now) >= 4 else { return false }
        return d.string(forKey: shownKey) != key
    }

    static func markShown(now: Date = Date(), _ d: UserDefaults = .standard) {
        d.set(Repository.localDayKey(now), forKey: shownKey)
    }
}

// MARK: - Signals ("something's off")

/// Compares today's overnight signals with the previous 30 nights and speaks up only when something is
/// genuinely unusual: two or more of HRV down / resting HR up / skin temperature up / breathing rate up
/// reads as "your body may be fighting something"; a single one as a heads-up. Silent on a normal day.
struct NathanSignalsCard: View {
    @EnvironmentObject var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitRaw = UnitSystem.imperial.rawValue

    struct Flag: Identifiable {
        let id: String
        let text: String
        let core: Bool
    }

    private var flags: [Flag] {
        guard let today = repo.today else { return [] }
        let prior = Array(repo.days.filter { $0.day < today.day }.suffix(30))
        guard prior.count >= 10 else { return [] }
        var out: [Flag] = []

        func stats(_ xs: [Double]) -> (mean: Double, sd: Double)? {
            guard xs.count >= 7 else { return nil }
            let m = xs.reduce(0, +) / Double(xs.count)
            let sd = (xs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(xs.count)).squareRoot()
            return (m, sd)
        }

        if let v = today.avgHrv, let s = stats(prior.compactMap(\.avgHrv)) {
            let floor = max(s.sd, s.mean * 0.08)
            if (v - s.mean) / floor <= -2 {
                out.append(Flag(id: "hrv", text: "HRV \(Int(v.rounded())) ms, \(Int(((s.mean - v) / s.mean * 100).rounded()))% below your normal", core: true))
            }
        }
        if let v = today.restingHr.map(Double.init), let s = stats(prior.compactMap { $0.restingHr.map(Double.init) }) {
            let floor = max(s.sd, 1.5)
            if (v - s.mean) / floor >= 2 {
                out.append(Flag(id: "rhr", text: "Resting HR \(Int(v)) bpm, \(Int((v - s.mean).rounded())) above your normal", core: true))
            }
        }
        if let v = today.skinTempDevC, let s = stats(prior.compactMap(\.skinTempDevC)) {
            if v - s.mean >= max(0.5, 2 * s.sd) {
                let imperial = (UnitSystem(rawValue: unitRaw) ?? .imperial) == .imperial
                let d = v - s.mean
                out.append(Flag(id: "temp", text: "Skin temperature up \(String(format: "%.1f", imperial ? d * 1.8 : d))°\(imperial ? "F" : "C")", core: true))
            }
        }
        if let v = today.respRateBpm, let s = stats(prior.compactMap(\.respRateBpm)) {
            if v - s.mean >= max(1.0, 2 * s.sd) {
                out.append(Flag(id: "resp", text: "Breathing rate \(String(format: "%.1f", v)) /min, up from \(String(format: "%.1f", s.mean))", core: true))
            }
        }
        if let v = today.spo2Pct, v > 50, v < 94 {
            out.append(Flag(id: "spo2", text: "Blood oxygen \(Int(v.rounded()))% overnight, lower than usual", core: false))
        }
        if let v = today.efficiency, let s = stats(prior.compactMap(\.efficiency)), (v - s.mean) / max(s.sd, 1) <= -2.5 {
            out.append(Flag(id: "eff", text: "Restless night: sleep efficiency well below normal", core: false))
        }
        return out
    }

    var body: some View {
        let f = flags
        let core = f.filter(\.core).count
        if !f.isEmpty {
            let serious = core >= 2
            WCard(padding: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: serious ? "cross.case" : "exclamationmark.circle")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(serious ? W.red : W.orange)
                        Text((serious ? "Health Monitor: signals are off" : "Health Monitor: one signal is off").uppercased())
                            .font(W.caps(13)).tracking(1.3).foregroundStyle(W.text)
                    }
                    ForEach(f) { flag in
                        Text("• \(flag.text)").font(W.body(15)).foregroundStyle(W.text2)
                    }
                    Text(serious
                         ? "Your body may be fighting something. Take it easy today: skip hard training, keep any workout light, and prioritize sleep and fluids."
                         : "Fine to train, but keep an eye on how you feel and don't chase a big day.")
                        .font(W.body(15, .semibold))
                        .foregroundStyle(serious ? W.orange : W.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous)
                .stroke(serious ? W.red.opacity(0.7) : W.orange.opacity(0.5), lineWidth: 1))
        }
    }
}

// MARK: - Settings

struct NathanSettingsView: View {
    @AppStorage(WaterReminder.enabledKey) private var waterOn = true
    @AppStorage(WaterReminder.startHourKey) private var startHour = 13
    @AppStorage(WaterReminder.endHourKey) private var endHour = 21
    @AppStorage(WaterReminder.phoneKey) private var phone = true
    @AppStorage(NathanMorningJournalGate.enabledKey) private var journal = true

    private func label(_ h: Int) -> String {
        h == 0 ? "12 AM" : h < 12 ? "\(h) AM" : h == 12 ? "12 PM" : "\(h - 12) PM"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Hourly water buzz", isOn: $waterOn)
                Picker("From", selection: $startHour) { ForEach(6..<23) { Text(label($0)).tag($0) } }
                Picker("Until", selection: $endHour) { ForEach(7..<24) { Text(label($0)).tag($0) } }
                Toggle("Also notify on my phone", isOn: $phone)
            } header: {
                Text("Water reminder")
            } footer: {
                Text("The strap buzzes once near the top of each hour while it's on your wrist and connected. The phone notification fires even when NOOP is closed.")
            }
            Section {
                Toggle("Open the journal each morning", isOn: $journal)
            } footer: {
                Text("After last night's sleep comes in, the journal opens once so you can log yesterday.")
            }
        }
        .navigationTitle("My settings")
        .onChange(of: waterOn) { _, _ in WaterReminder.reschedulePhoneNotifications() }
        .onChange(of: startHour) { _, _ in WaterReminder.reschedulePhoneNotifications() }
        .onChange(of: endHour) { _, _ in WaterReminder.reschedulePhoneNotifications() }
        .onChange(of: phone) { _, _ in WaterReminder.reschedulePhoneNotifications() }
    }
}
