import Foundation
import UserNotifications

/// Nathan's hourly water reminder: one strap buzz at the top of each hour inside a daytime window
/// (default 1 PM – 9 PM), plus an optional phone notification at the same times.
///
/// The strap buzz rides the existing curated haptic command (the same one the inactivity reminder
/// sends) and is driven from Bluetooth activity the app already receives, so it needs no new strap
/// command and no background timer. The phone notification is a repeating local notification, which
/// fires even while NOOP is suspended. UserDefaults only, so this file builds for macOS as well.
enum WaterReminder {
    static let enabledKey = "nathan.water.enabled"
    static let startHourKey = "nathan.water.startHour"
    static let endHourKey = "nathan.water.endHour"
    static let phoneKey = "nathan.water.phone"
    static let lastBuzzKey = "nathan.water.lastBuzz"

    static let defaults: [String: Any] = [enabledKey: true, startHourKey: 13, endHourKey: 21, phoneKey: true]

    /// How long after the top of the hour a buzz may still fire. Bluetooth traffic is bursty while the
    /// phone sleeps, so the first event inside this window is the one that buzzes.
    static let windowMinutes = 20

    static func register(_ d: UserDefaults = .standard) { d.register(defaults: defaults) }

    /// "yyyy-MM-dd-HH" when a buzz is due now and has not fired for this hour yet; nil otherwise.
    static func dueHourKey(now: Date = Date(), _ d: UserDefaults = .standard, calendar: Calendar = .current) -> String? {
        guard d.bool(forKey: enabledKey) else { return nil }
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let start = d.integer(forKey: startHourKey), end = d.integer(forKey: endHourKey)
        guard hour >= start, hour <= end, minute < windowMinutes else { return nil }
        let c = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        let key = String(format: "%04d-%02d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0)
        return d.string(forKey: lastBuzzKey) == key ? nil : key
    }

    static func markBuzzed(_ key: String, _ d: UserDefaults = .standard) { d.set(key, forKey: lastBuzzKey) }

    static let notificationPrefix = "nathan.water."

    /// Replace the repeating hourly phone notifications to match the current settings.
    static func reschedulePhoneNotifications(_ d: UserDefaults = .standard) {
        let center = UNUserNotificationCenter.current()
        let ids = (0..<24).map { "\(notificationPrefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard d.bool(forKey: enabledKey), d.bool(forKey: phoneKey) else { return }
        let start = d.integer(forKey: startHourKey), end = d.integer(forKey: endHourKey)
        guard start <= end else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            for hour in start...end {
                let content = UNMutableNotificationContent()
                content.title = "Drink some water"
                content.body = "It's \(hour > 12 ? hour - 12 : hour) \(hour >= 12 ? "PM" : "AM"). Have a glass."
                content.sound = .default
                var comps = DateComponents(); comps.hour = hour; comps.minute = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                center.add(UNNotificationRequest(identifier: "\(notificationPrefix)\(hour)", content: content, trigger: trigger))
            }
        }
    }
}
