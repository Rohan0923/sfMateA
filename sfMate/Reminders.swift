import SwiftUI
import UIKit
import UserNotifications

/// Day-before reminders for liturgy days (L1, L2) and activity days (A1–A4), at 6 PM school time.
/// The server (GET /reminders) says which days are coming up, when to remind, and what each notification says; the
/// phone schedules them itself (local notifications, no push needed). Every sync replaces them all, so a day the
/// school adds, moves, or cancels is picked up the next time the app opens.
@Observable
final class Reminders {
    enum Kind: String { case liturgy, activity }

    static let shared = Reminders()
    static let settingsURL = URL(string: UIApplication.openNotificationSettingsURLString)!
    private static let idPrefix = "reminder."

    // the switches live on this iPhone only (the website has no reminders)
    private(set) var liturgy = UserDefaults.standard.bool(forKey: "remind.liturgy")
    private(set) var activity = UserDefaults.standard.bool(forKey: "remind.activity")
    private(set) var denied = false   // notifications are off for sfMate in iOS Settings

    private let center = UNUserNotificationCenter.current()
    private let banner = ReminderBanner()
    private var lastSync: Task<Void, Never>?

    private init() {
        center.delegate = banner
    }

    func isOn(_ kind: Kind) -> Bool { kind == .liturgy ? liturgy : activity }

    /// Turning one on asks iOS for permission first; if the student says no, the switch stays off.
    func set(_ kind: Kind, _ on: Bool) async {
        if on {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            denied = !granted
            guard granted else { return }
        }
        switch kind {
        case .liturgy: liturgy = on
        case .activity: activity = on
        }
        UserDefaults.standard.set(on, forKey: "remind.\(kind.rawValue)")
        await sync()
    }

    func checkPermission() async {
        denied = await center.notificationSettings().authorizationStatus == .denied
    }

    /// Re-reads the upcoming days and reschedules every reminder. One sync at a time, so a switch flipped mid-sync wins.
    func sync() async {
        let previous = lastSync
        let task = Task { await previous?.value; await reschedule() }
        lastSync = task
        await task.value
    }

    func signOut() {
        liturgy = false
        activity = false
        UserDefaults.standard.removeObject(forKey: "remind.liturgy")
        UserDefaults.standard.removeObject(forKey: "remind.activity")
        Task { await sync() }   // clears what's scheduled
    }

    private func reschedule() async {
        let wanted = Set([Kind.liturgy, .activity].filter(isOn).map(\.rawValue))
        var days: [ReminderDay] = []
        if !wanted.isEmpty {
            guard API.shared.token != nil else { return }
            do {
                let response: RemindersResponse = try await API.shared.send("reminders", timeout: 30)
                days = response.days.filter { wanted.contains($0.kind) }
            } catch {
                return   // offline: keep what's already scheduled
            }
        }
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard !days.isEmpty else { return }

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let iso = ISO8601DateFormatter()
        for day in days {
            guard let at = iso.date(from: day.remind_at), at > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = day.title
            content.body = day.body
            content.sound = .default
            var when = utc.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            when.timeZone = .gmt   // an exact moment (6 PM in California), whatever time zone the phone is in
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: Self.idPrefix + day.date, content: content, trigger: trigger))
        }
    }
}

/// Shows a reminder even when sfMate is open at 6 PM (iOS hides notifications from the app in front by default).
final class ReminderBanner: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
