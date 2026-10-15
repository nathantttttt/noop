#if os(iOS)
import Foundation
import AppIntents

/// Queue of actions requested by an App Intent while the app may be suspended. Intents can't reach
/// into the running `AppModel` directly (BLE only lives in the foreground app), so they enqueue here
/// and the app drains the queue when it next becomes active.
enum PendingIntents {
    enum Action: String { case markMoment, buzz, askCoach }

    private static let key = "noop.pendingIntents"
    /// K9: the question text for a pending `.askCoach` action. Stored separately because the
    /// action queue encodes as `[String]` and a question can contain colons.
    private static let coachQuestionKey = "noop.pendingCoachQuestion"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshot.suiteName) }

    /// Optional `at` is the invocation time, captured now and consumed on drain. Encoded into the
    /// stored string as "rawValue:epochSeconds" so the array stays a plain [String] (no schema
    /// migration; a legacy bare "markMoment" still decodes with a nil date).
    static func append(_ action: Action, at date: Date? = nil) {
        guard let d = defaults else { return }
        var list = d.stringArray(forKey: key) ?? []
        if let date { list.append("\(action.rawValue):\(date.timeIntervalSince1970)") }
        else { list.append(action.rawValue) }
        d.set(list, forKey: key)
    }

    /// K9: queue an "Ask Coach" action with the associated question text. The question is stored
    /// in a dedicated key (one pending question at a time — the user rarely queues multiple Siri
    /// questions before the app opens).
    static func appendAskCoach(question: String, at date: Date? = nil) {
        guard let d = defaults else { return }
        d.set(question, forKey: coachQuestionKey)
        append(.askCoach, at: date)
    }

    /// K9: read and clear the pending coach question. Returns nil when no question is queued.
    static func consumeCoachQuestion() -> String? {
        guard let d = defaults else { return nil }
        let q = d.string(forKey: coachQuestionKey)
        d.removeObject(forKey: coachQuestionKey)
        return q
    }

    static func drain() -> [(action: Action, date: Date?)] {
        guard let d = defaults else { return [] }
        let raw = d.stringArray(forKey: key) ?? []
        d.removeObject(forKey: key)
        return raw.compactMap { entry in
            // Guard `parts.first` rather than subscripting `parts[0]`: split(omittingEmptySubsequences:
            // true by default) returns an EMPTY array for an empty or ":"-leading entry, and indexing
            // [0] there is a fatal trap. This value comes from shared App Group defaults read untrusted,
            // so a corrupt/foreign entry must be skipped, not crash the app on foreground.
            let parts = entry.split(separator: ":", maxSplits: 1)
            guard let first = parts.first, let action = Action(rawValue: String(first)) else { return nil }
            let date = parts.count == 2 ? Double(parts[1]).map { Date(timeIntervalSince1970: $0) } : nil
            return (action, date)
        }
    }
}

/// Record a timestamped "moment" — the iOS analogue of the strap double-tap "mark a moment" action.
struct MarkMomentIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark a Moment"
    static var description = IntentDescription("Record a timestamped moment in NOOP.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        PendingIntents.append(.markMoment, at: Date())
        return .result(dialog: "Moment marked.")
    }
}

/// Send a confirming haptic buzz to the strap. Opens the app so the live BLE link can deliver it.
struct BuzzStrapIntent: AppIntent {
    static var title: LocalizedStringResource = "Buzz Strap"
    static var description = IntentDescription("Send a haptic buzz to your WHOOP strap.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingIntents.append(.buzz)
        return .result()
    }
}

/// Pull the strap's stored history now: the Shortcuts twin of the "Sync now" button, run WITHOUT opening NOOP.
/// iOS runs an in-app intent inside NOOP's own process (launching or resuming it in the background), where the
/// strap link lives under the bluetooth-central background mode, so the offload carries on after this returns.
/// The spoken/shown reply reports only what this path observed about the sync starting.
///
/// `LiveActivityIntent`, not plain `AppIntent`: that is what lets it START the strap-sync Live Activity
/// (the Dynamic Island "Connecting… / Syncing… N chunks" readout) from the background. A plain intent
/// running in a background-launched app is refused by ActivityKit.
struct SyncStrapIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Sync Strap"
    static var description = IntentDescription("Pull your WHOOP strap's stored history into NOOP now.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch await AppModel.startStrapSyncFromShortcut() {
        case .started:               return .result(dialog: "Syncing your strap.")
        case .alreadyRunning:        return .result(dialog: "Your strap is already syncing.")
        case .willSyncWhenConnected: return .result(dialog: "NOOP is connecting to your strap and will sync as soon as it's ready.")
        case .strapNotReady:         return .result(dialog: "Your strap isn't connected to NOOP yet, so the sync didn't start.")
        case .notStarted:            return .result(dialog: "NOOP couldn't start the sync. Open NOOP to see the strap log.")
        }
    }
}

/// K9: Ask the Coach a question via Siri. Queues the question and opens the app, which sends it
/// to the configured provider and surfaces the response. The question is spoken or typed in Siri;
/// the app handles the actual network call using the user's saved key.
struct AskCoachIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Coach"
    static var description = IntentDescription("Ask your NOOP Coach a question about your recovery, sleep, or training.")
    static var openAppWhenRun = true

    /// The question to ask, populated by Siri from the user's spoken phrase.
    @Parameter(title: "Question")
    var question: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        PendingIntents.appendAskCoach(question: question, at: Date())
        return .result(dialog: "Opening Coach with your question: \(question)")
    }
}

/// "Send Health Data to NOOP": the fill-in-the-blanks Shortcuts action for a sideloaded build with no
/// HealthKit entitlement. The user's Shortcut finds the scale and sleep-mat samples in Health and drops
/// them into these fields; NOOP files them under the `apple-health` source exactly as the
/// `noop://import-health` link does, minus the text line, base64 and URL the link needs.
struct SendHealthDataIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Health Data to NOOP"
    static var description = IntentDescription("Import weight, body fat, lean mass and last night's sleep window from Apple Health into NOOP. Leave any field empty to skip it.")
    static var openAppWhenRun = false

    @Parameter(title: "Weight") var weight: String?
    @Parameter(title: "Body fat") var bodyFat: String?
    @Parameter(title: "Lean mass") var leanMass: String?
    @Parameter(title: "Sleep start") var sleepStart: Date?
    @Parameter(title: "Sleep end") var sleepEnd: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$weight), \(\.$bodyFat), \(\.$leanMass), sleep \(\.$sleepStart) to \(\.$sleepEnd) to NOOP")
    }

    /// A Health sample turned into text loses its unit ("154.10…"), so a bare number follows the app's
    /// unit setting; an explicit "kg"/"lb" wins.
    static func kilograms(_ raw: String?) -> Double? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
              let v = ShortcutHealthImport.leadingNumber(s), v > 0 else { return nil }
        let lower = s.lowercased()
        if lower.contains("kg") { return v }
        if lower.contains("lb") || lower.contains("pound") { return v / 2.2046226218 }
        let imperial = (UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "imperial") == UnitSystem.imperial.rawValue
        return imperial ? v / 2.2046226218 : v
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        var day = ShortcutHealthImport.ParsedDay(day: Repository.localDayKey(sleepEnd ?? Date()))
        day.weightKg = Self.kilograms(weight)
        if let s = bodyFat?.trimmingCharacters(in: .whitespacesAndNewlines), let v = ShortcutHealthImport.leadingNumber(s) {
            let pct = v <= 1 ? v * 100 : v
            if pct > 1, pct < 70 { day.bodyFatPct = pct }
        }
        day.leanKg = Self.kilograms(leanMass)
        var sleepNote = "no sleep"
        if let s = sleepStart, let e = sleepEnd, e > s, e.timeIntervalSince(s) < 20 * 3600 {
            day.sleepStartTs = Int(s.timeIntervalSince1970)
            day.sleepEndTs = Int(e.timeIntervalSince1970)
            let f = DateFormatter(); f.dateFormat = "h:mm a"
            sleepNote = "sleep \(f.string(from: s))–\(f.string(from: e))"
        } else if sleepStart != nil || sleepEnd != nil {
            sleepNote = "sleep skipped (needs both a start and an end)"
        }
        guard day.hasAnyMetric else {
            return .result(dialog: "Nothing to send: every field was empty. Check that Health has a weight or sleep reading in the range your Find steps use.")
        }

        // A cold launch can hand the intent its first tick before the model exists.
        var model = AppModel.shared
        for _ in 0..<8 where model == nil {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            model = AppModel.shared
        }
        guard let model else {
            return .result(dialog: "NOOP didn't start in time. Open NOOP once, then run the shortcut again.")
        }
        let pending = ShortcutHealthImport.PendingImport(
            text: "intent", parsed: ShortcutHealthImport.Parsed(days: [day], workouts: []))
        switch await model.importFromShortcutAction(pending) {
        case .imported:
            var parts: [String] = []
            if let w = day.weightKg { parts.append(String(format: "weight %.1f lb", w * 2.2046226218)) }
            if let b = day.bodyFatPct { parts.append(String(format: "body fat %.1f%%", b)) }
            if let l = day.leanKg { parts.append(String(format: "lean %.1f lb", l * 2.2046226218)) }
            parts.append(sleepNote)
            return .result(dialog: "Sent to NOOP: \(parts.joined(separator: ", ")).")
        case .nothingToImport:
            return .result(dialog: "Nothing new to import.")
        case .rejected(let reason):
            return .result(dialog: "NOOP couldn't import it: \(reason)")
        }
    }
}

/// Surfaces NOOP's intents to Siri, Spotlight, and the Shortcuts gallery without any user setup.
struct NOOPShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SyncStrapIntent(),
                    phrases: [
                        "Sync my \(.applicationName) strap",
                        "Sync \(.applicationName)",
                    ],
                    shortTitle: "Sync Strap",
                    systemImageName: "arrow.triangle.2.circlepath")
        AppShortcut(intent: MarkMomentIntent(),
                    phrases: ["Mark a moment in \(.applicationName)"],
                    shortTitle: "Mark a Moment",
                    systemImageName: "mappin.and.ellipse")
        AppShortcut(intent: BuzzStrapIntent(),
                    phrases: ["Buzz my \(.applicationName) strap"],
                    shortTitle: "Buzz Strap",
                    systemImageName: "waveform.path")
        // K9: "Ask Coach" via Siri — opens Coach with the question and sends it. The question
        // parameter is provided via the Shortcuts app or Siri prompts for it when the phrase fires.
        AppShortcut(intent: AskCoachIntent(),
                    phrases: [
                        "Ask \(.applicationName) about my recovery",
                        "Ask \(.applicationName) how I'm doing",
                        "Ask \(.applicationName) Coach",
                    ],
                    shortTitle: "Ask Coach",
                    systemImageName: "sparkles")
    }
}
#endif
