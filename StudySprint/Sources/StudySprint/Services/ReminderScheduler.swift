import Foundation
import UserNotifications

/// Schedules a local notification for when flashcards come due, so spaced repetition actually happens.
enum ReminderScheduler {
    static let enabledKey = "reviewReminders"
    private static let id = "studysprint.review-due"

    /// UNUserNotificationCenter only works inside a real .app bundle (not `swift run`).
    private static var available: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Replaces any pending reminder with one at `due` (pushed to a sensible hour if it falls overnight).
    static func schedule(nextDue due: Date?, dueNow: Int) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard isEnabled else { return }

        let fireDate: Date
        if dueNow > 0 {
            fireDate = Date().addingTimeInterval(3 * 3600) // nudge later today if cards are already waiting
        } else if let due {
            fireDate = due
        } else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Time for a quick review 🧠"
        content.body = dueNow > 0
            ? "\(dueNow) card\(dueNow == 1 ? " is" : "s are") due. Two minutes now saves an hour of re-learning."
            : "Your flashcards are due — review them before they fade."
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: awakeHours(fireDate))
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        center.add(request)
    }

    /// Moves times between 10pm and 8am to 9am.
    static func awakeHours(_ date: Date, calendar: Calendar = .current) -> Date {
        let hour = calendar.component(.hour, from: date)
        guard hour >= 22 || hour < 8 else { return date }
        let base = hour >= 22 ? calendar.date(byAdding: .day, value: 1, to: date) ?? date : date
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? date
    }
}
