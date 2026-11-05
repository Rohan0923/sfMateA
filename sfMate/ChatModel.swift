import SwiftUI
import UIKit

struct ChatMessage: Identifiable {
    enum Role { case user, bot }
    enum State { case waiting, streaming, done, stopped, failed }

    let id = UUID()
    let role: Role
    var text: String
    var historyText: String? = nil      // what the server sees for this turn, if different from what's shown
    var sources: [Source] = []
    var state: State = .done
    var waking = false                   // no answer after a few seconds: the GPU is probably starting up
    var prompt: AnnouncementStatus? = nil // "Daily announcements are out. Want me to summarize?"
}

/// One conversation: what's on screen, what's sent as history, and the answer streaming in.
@Observable
final class ChatModel {
    static let historyTurns = 6   // messages of context sent with each question (the server keeps the last 6 too)
    static let pickups = 3        // tries at picking an answer back up after its connection drops

    var messages: [ChatMessage] = []
    var welcomeNote: String?
    var welcomeLoading = false
    var busy: Bool { task != nil }

    private var task: Task<Void, Never>?
    private var requestID: String?   // the answer being written (the server knows it by this, for pickups and Stop)
    private var shownAnnouncementID: String?
    private var welcomeFor: String?

    var showingWelcome: Bool { messages.allSatisfy { $0.prompt != nil } }

    // ---------- welcome ----------
    func loadWelcome(for app: AppModel) async {
        guard app.hasAIConsent, let profile = app.me?.profile, profile.skipped != true, app.firstName != nil else {
            welcomeNote = nil
            return
        }
        let key = "\(profile.first_name ?? "")|\(profile.grade ?? 0)|\(profile.hobbies ?? "")|\(profile.favorite_food ?? "")"
        guard key != welcomeFor else { return }
        welcomeFor = key
        welcomeLoading = true
        defer { welcomeLoading = false }
        do {
            let r: WelcomeResponse = try await API.shared.send("welcome", method: "POST")
            welcomeNote = r.message
        } catch {
            app.handle(error)
            welcomeNote = nil   // keep the generic welcome
        }
    }

    // ---------- asking ----------
    func send(_ raw: String, app: AppModel) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        struct Body: Encodable { let message: String; let history: [[String: String]] }
        stream("chat", body: Body(message: text, history: history()), shown: text, historyText: text, app: app)
    }

    func stop() {
        task?.cancel()
        if let requestID { Task { await API.shared.stopAnswer(requestID) } }
    }

    func newChat() {
        stop()
        messages = []
        shownAnnouncementID = nil
    }

    private func history() -> [[String: String]] {
        let turns = messages.filter { $0.prompt == nil && ($0.role == .user || $0.state == .done || $0.state == .stopped) }
            .filter { !($0.role == .bot && $0.text.isEmpty) }
            .map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.historyText ?? $0.text] }
        return Array(turns.suffix(Self.historyTurns))
    }

    private func stream(_ path: String, body: any Encodable, shown: String, historyText: String, app: AppModel) {
        guard app.hasAIConsent else {   // nothing goes to the AI before the student agrees (e.g. launched offline)
            Task { await app.requireConsent() }
            return
        }
        messages.append(ChatMessage(role: .user, text: shown, historyText: historyText))
        messages.append(ChatMessage(role: .bot, text: "", state: .waiting))
        let index = messages.count - 1
        let requestID = UUID().uuidString
        self.requestID = requestID

        task = Task {
            let waking = Task {
                try? await Task.sleep(for: .seconds(6))
                if !Task.isCancelled, messages.indices.contains(index), messages[index].text.isEmpty {
                    messages[index].waking = true
                }
            }
            let backgroundTime = BackgroundTime()
            defer { waking.cancel(); backgroundTime.end(); task = nil; self.requestID = nil }
            var call: (path: String, method: String, body: (any Encodable)?) = (path, "POST", body)
            var pickups = 0
            while true {
                var replaying = pickups > 0   // a pickup sends the whole answer again, from the start
                do {
                    for try await event in API.shared.stream(call.path, method: call.method, body: call.body,
                                                             requestID: requestID) {
                        guard messages.indices.contains(index) else { return }   // "New chat" cleared it
                        if replaying {
                            messages[index].text = ""
                            messages[index].sources = []
                            replaying = false
                        }
                        switch event {
                        case .sources(let sources): messages[index].sources = sources
                        case .delta(let piece):
                            messages[index].text += piece
                            messages[index].state = .streaming
                            messages[index].waking = false
                        }
                    }
                    guard messages.indices.contains(index) else { return }
                    if messages[index].text.isEmpty {
                        fail(index, "Empty response from the model.")
                    } else {
                        messages[index].state = .done
                    }
                    return
                } catch let error as APIError where error.status == 0 && pickups < Self.pickups {
                    // The connection dropped mid-answer, almost always because they switched apps and iOS suspended
                    // this one. The server kept writing it: pick it back up once the app is on screen again.
                    pickups += 1
                    await Self.untilOnScreen()
                    try? await Task.sleep(for: .seconds(pickups == 1 ? 0.3 : 2))   // let the network come back first
                    guard !Task.isCancelled, messages.indices.contains(index) else {
                        if messages.indices.contains(index) { messages[index].state = .stopped }
                        return
                    }
                    call = ("answers/\(requestID)", "GET", nil)
                } catch {
                    guard messages.indices.contains(index) else { return }
                    if let error = error as? APIError, error.status == -1 {
                        messages[index].state = .stopped
                    } else {
                        app.handle(error)
                        fail(index, error.localizedDescription)
                    }
                    return
                }
            }
        }
    }

    /// A suspended app can't reconnect: wait until it's back on screen.
    private static func untilOnScreen() async {
        while UIApplication.shared.applicationState != .active, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func fail(_ index: Int, _ message: String) {
        messages[index].state = .failed
        messages[index].waking = false
        messages[index].text = message
    }

    // ---------- Daily Announcements ----------
    func checkAnnouncements(app: AppModel) async {
        guard app.isSchoolMember else { return }   // the Daily Announcements are for @sfhs.com accounts only
        do {
            let status: AnnouncementStatus = try await API.shared.send("announcements/status", timeout: 20)
            guard status.available, let id = status.id, id != shownAnnouncementID else { return }
            shownAnnouncementID = id
            messages.append(ChatMessage(role: .bot, text: status.message ?? "Daily announcements are out. Want me to summarize?",
                                        prompt: status))
        } catch {
            app.handle(error)   // offline for a moment: try again next time
        }
    }

    private func closePrompt(_ id: UUID) -> AnnouncementStatus? {
        guard let i = messages.firstIndex(where: { $0.id == id }), let status = messages[i].prompt else { return nil }
        messages[i].prompt = AnnouncementStatus(available: false, id: status.id, date: status.date, message: status.message)
        return status
    }

    func summarize(prompt id: UUID, app: AppModel) {
        guard !busy, let status = closePrompt(id), let annID = status.id else { return }
        struct Body: Encodable { let id: String }
        stream("announcements/summary", body: Body(id: annID), shown: "Yes",
               historyText: "Summarize the Daily Announcements from \(status.date ?? "today").", app: app)
    }

    func decline(prompt id: UUID) {
        guard let status = closePrompt(id), let annID = status.id else { return }
        struct Body: Encodable { let id: String }
        struct OK: Decodable {}
        Task { let _: OK? = try? await API.shared.send("announcements/dismiss", method: "POST", body: Body(id: annID), timeout: 20) }
        messages.append(ChatMessage(role: .user, text: "No thanks"))
        messages.append(ChatMessage(role: .bot, text: "No worries. If you change your mind, just ask me what's in today's announcements."))
    }
}

/// Extra running time from iOS (about 30 seconds) after the student switches apps, so a quick trip away doesn't cut the
/// answer off. Past that iOS suspends the app, and the answer is picked back up from the server when they return.
private final class BackgroundTime {
    private var id = UIBackgroundTaskIdentifier.invalid

    init() {
        id = UIApplication.shared.beginBackgroundTask(withName: "sfMate answer") { [weak self] in self?.end() }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
