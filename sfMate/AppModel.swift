import SwiftUI

/// Who's signed in, and which screen they're on: sign in -> first-time setup -> AI consent -> chat.
@Observable
final class AppModel {
    enum Screen { case launching, signedOut, setup, consent, chat }

    var screen: Screen = .launching
    var me: Me?
    var editingProfile = false   // setup opened from the chat's Profile button

    init() {
        Task { await start() }
    }

    var firstName: String? {
        guard let name = me?.profile?.first_name, !name.isEmpty else { return nil }
        return name
    }

    /// The student agreed to questions (and profile details) being sent to the AI provider. Apple requires asking.
    var hasAIConsent: Bool { me?.ai_consent == true }

    /// Where a signed-in student belongs: setup first, then the AI consent screen, then the chat.
    private func home(setupDone: Bool? = nil) -> Screen {
        guard setupDone ?? (me?.setup_done == true) else { return .setup }
        return hasAIConsent ? .chat : .consent
    }

    func start() async {
        guard API.shared.token != nil else { screen = .signedOut; return }
        do {
            try await refreshMe()
            screen = home()
        } catch let error as APIError where error.isUnauthorized {
            signOut()
        } catch {
            // offline: still show the chat; nothing is sent until the server confirms consent (ChatModel checks)
            screen = .chat
        }
    }

    func refreshMe() async throws {
        me = try await API.shared.send("auth/me")
    }

    private func enter(_ session: SessionResponse) async {
        API.shared.token = session.token
        try? await refreshMe()
        screen = home(setupDone: session.setup_done)
    }

    // ---------- permission to send questions to the AI provider ----------
    func setAIConsent(_ accepted: Bool) async throws {
        struct Body: Encodable { let accepted: Bool }
        struct OK: Decodable {}
        let _: OK = try await API.shared.send("consent", method: "POST", body: Body(accepted: accepted), timeout: 30)
        try await refreshMe()
        editingProfile = false
        screen = home()
    }

    /// A question was about to go out without a confirmed consent: re-check, and show the consent screen if needed.
    func requireConsent() async {
        try? await refreshMe()
        if !hasAIConsent, me != nil { screen = home() }
    }

    // ---------- accounts ----------
    func login(_ login: String, password: String) async throws {
        struct Body: Encodable { let login: String; let password: String }
        let session: SessionResponse = try await API.shared.send("auth/login", method: "POST",
                                                                 body: Body(login: login, password: password), timeout: 30)
        await enter(session)
    }

    /// Step 1 of signing up: the server emails a 6-digit code. Returns the email it went to.
    func startSignup(username: String, email: String, password: String) async throws -> String {
        struct Body: Encodable { let username: String; let email: String; let password: String }
        let pending: PendingSignup = try await API.shared.send("auth/signup", method: "POST",
                                                              body: Body(username: username, email: email, password: password),
                                                              timeout: 30)
        return pending.email
    }

    func resendCode(email: String) async throws {
        struct Body: Encodable { let email: String }
        struct OK: Decodable {}
        let _: OK = try await API.shared.send("auth/resend", method: "POST", body: Body(email: email), timeout: 30)
    }

    /// Step 2: the code from the email creates the account and signs in.
    func verify(email: String, code: String) async throws {
        struct Body: Encodable { let email: String; let code: String }
        let session: SessionResponse = try await API.shared.send("auth/verify", method: "POST",
                                                                 body: Body(email: email, code: code), timeout: 30)
        await enter(session)
    }

    func signOut() {
        if API.shared.token != nil {
            struct OK: Decodable {}
            Task { let _: OK? = try? await API.shared.send("auth/logout", method: "POST", timeout: 15) }
        }
        forgetSession()
    }

    /// Deletes the account on the server (and everything tied to it), then signs out on this iPhone.
    func deleteAccount() async throws {
        struct OK: Decodable {}
        let _: OK = try await API.shared.send("account", method: "DELETE", timeout: 30)
        forgetSession()
    }

    private func forgetSession() {
        API.shared.token = nil
        Reminders.shared.signOut()   // the next person to sign in on this iPhone starts with reminders off
        me = nil
        editingProfile = false
        screen = .signedOut
    }

    // ---------- feedback ----------
    func sendFeedback(_ message: String) async throws {
        struct Body: Encodable { let message: String; let app_version: String }
        struct OK: Decodable {}
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        let _: OK = try await API.shared.send("feedback", method: "POST", body: Body(message: message, app_version: version),
                                              timeout: 30)
    }

    // ---------- profile ----------
    func saveProfile(_ profile: Profile) async throws {
        struct OK: Decodable {}
        let _: OK = try await API.shared.send("profile", method: "POST", body: profile, timeout: 30)
        try? await refreshMe()
        editingProfile = false
        screen = home(setupDone: true)
    }

    func openProfile() {
        editingProfile = true
        screen = .setup
    }

    func closeProfile() {
        editingProfile = false
        screen = home(setupDone: true)
    }

    /// Any request that comes back 401 means the login expired.
    func handle(_ error: Error) {
        if let error = error as? APIError, error.isUnauthorized { signOut() }
    }
}
