import Foundation
import Security

// Talks to the same sfMate server as the website (sfmate/app/main.py), with the same bearer-token login.

struct APIError: LocalizedError {
    let status: Int          // 0: couldn't reach the server
    let message: String
    var errorDescription: String? { message }
    var isUnauthorized: Bool { status == 401 }
}

struct SessionResponse: Decodable {
    let token: String
    let name: String
    let setup_done: Bool
}

struct Profile: Codable, Equatable {
    var first_name: String?
    var grade: Int?
    var hobbies: String?
    var favorite_food: String?
    var announcements: [String]?
    var skipped: Bool?
}

struct Me: Decodable {
    let name: String
    let username: String
    let email: String
    let setup_done: Bool
    let profile: Profile?
    let ai_consent: Bool?    // agreed to questions being sent to the AI provider (POST /consent)
    let school_member: Bool? // signed up with an @sfhs.com email: also gets the Daily Announcements (nobody else does)
}

struct PendingSignup: Decodable {
    let pending: Bool
    let email: String
}

struct WelcomeResponse: Decodable { let message: String? }

struct AnnouncementStatus: Decodable {
    let available: Bool
    let id: String?
    let date: String?
    let message: String?
}

/// A liturgy or activity day coming up, and the reminder for it (sfmate/app/reminders.py).
struct ReminderDay: Decodable {
    let date: String        // YYYY-MM-DD, the liturgy or activity day itself
    let kind: String        // "liturgy" or "activity"
    let remind_at: String   // ISO 8601: 6 PM school time the day before
    let title: String
    let body: String
}

struct RemindersResponse: Decodable { let days: [ReminderDay] }

struct Source: Decodable, Hashable, Identifiable {
    let n: Int
    let title: String
    let url: String
    var id: Int { n }
}

enum StreamEvent {
    case sources([Source])
    case delta(String)
}

private struct ErrorBody: Decodable { let detail: String? }
private struct EventBody: Decodable {
    let sources: [Source]?
    let delta: String?
    let error: String?
    let done: Bool?
}

final class API {
    static let shared = API()

    let baseURL: URL
    var token: String? {
        didSet { Keychain.save(token) }
    }

    private init() {
        #if DEBUG
        // Test builds only: SFMATE_API=http://127.0.0.1:8000 points at a server on this Mac; SFMATE_TOKEN signs in.
        let env = ProcessInfo.processInfo.environment
        if let override = env["SFMATE_API"], let url = URL(string: override) {
            baseURL = url
        } else {
            baseURL = URL(string: "https://sfmate.onrender.com")!
        }
        token = env["SFMATE_TOKEN"] ?? Keychain.load()
        #else
        baseURL = URL(string: "https://sfmate.onrender.com")!
        token = Keychain.load()
        #endif
    }

    private func request(_ path: String, method: String, body: (any Encodable)?, timeout: TimeInterval,
                         headers: [String: String] = [:]) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: timeout)
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { req.setValue(value, forHTTPHeaderField: name) }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        return req
    }

    private static func failure(_ status: Int, _ data: Data) -> APIError {
        let detail = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.detail
        return APIError(status: status, message: detail ?? "Something went wrong (\(status))")
    }

    private static let lost = APIError(status: 0, message: "Couldn't reach the sfMate server. Check your connection and try again.")

    private static func unreachable(_ error: Error) -> APIError {
        if (error as? URLError)?.code == .cancelled { return APIError(status: -1, message: "Stopped") }
        return lost
    }

    /// A JSON request; the server's "detail" message becomes the error.
    /// The 4-minute timeout covers the GPU waking up (the welcome message uses the model).
    func send<T: Decodable>(_ path: String, method: String = "GET", body: (any Encodable)? = nil,
                            timeout: TimeInterval = 240) async throws -> T {
        let req = try request(path, method: method, body: body, timeout: timeout)
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw Self.unreachable(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Self.failure(status, data) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// A streamed answer (Server-Sent Events): {sources} and {delta} pieces, then {done}; {error} ends it with a message.
    /// With a `requestID` the server keeps writing the answer if the connection drops; GET answers/{id} picks it back up.
    func stream(_ path: String, method: String = "POST", body: (any Encodable)?,
                requestID: String? = nil) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let req = try request(path, method: method, body: body, timeout: 300,   // cold starts can take minutes
                                          headers: requestID.map { ["X-Request-ID": $0] } ?? [:])
                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, response) = try await URLSession.shared.bytes(for: req)
                    } catch {
                        throw Self.unreachable(error)
                    }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw Self.failure(status, data)
                    }
                    var done = false
                    for try await line in bytes.lines {   // ": ok" keep-alive comments are skipped
                        guard line.hasPrefix("data: "),
                              let event = try? JSONDecoder().decode(EventBody.self, from: Data(line.dropFirst(6).utf8))
                        else { continue }
                        if let sources = event.sources { continuation.yield(.sources(sources)) }
                        if let delta = event.delta { continuation.yield(.delta(delta)) }
                        if let error = event.error { throw APIError(status: 200, message: error) }
                        if event.done == true { done = true; break }
                    }
                    guard done else { throw Self.lost }   // ended without {done}: the connection dropped mid-answer
                    continuation.finish()
                } catch let error as APIError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? APIError(status: -1, message: "Stopped") : Self.unreachable(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The Stop button: otherwise the server would finish the answer, in case the app came back for it.
    func stopAnswer(_ requestID: String) async {
        struct OK: Decodable {}
        let _: OK? = try? await send("answers/\(requestID)", method: "DELETE", timeout: 20)
    }
}

/// The login token lives in the iPhone Keychain, not in plain app storage.
enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.sfmate.app",
        kSecAttrAccount as String: "session",
    ]

    static func save(_ token: String?) {
        SecItemDelete(query as CFDictionary)
        guard let token else { return }
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load() -> String? {
        var item = query
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
