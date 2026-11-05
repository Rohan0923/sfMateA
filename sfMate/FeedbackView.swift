import SwiftUI

/// "Send feedback": a bug, a wrong answer, an idea. Saved on the server and emailed to the developer (POST /feedback).
struct FeedbackView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error = ""
    @State private var busy = false
    @State private var sent = false
    @FocusState private var focused: Bool

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if sent {
                    VStack(spacing: 12) {
                        KnightAvatar(size: 72)
                        Text("Thanks! Your feedback was sent.")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.sfBrown)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    Text("Found a bug, got a wrong or weird answer, or have an idea? Tell us. If it's about an answer, include the question you asked.")
                        .font(.system(size: 14)).foregroundStyle(Color.sfMuted).lineSpacing(2)
                    if !error.isEmpty { NoticeText(text: error) }
                    TextField("What's on your mind?", text: $text, axis: .vertical)
                        .lineLimit(6...12).focused($focused)
                        .sfField(focused: focused)
                }
                Spacer()
            }
            .padding(20)
            .background(Color.sfBackground)
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                }
                if !sent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(busy ? "Sending…" : "Send", action: send).disabled(!canSend)
                    }
                }
            }
            .onAppear { focused = true }
        }
        .tint(.sfGoldDark)
    }

    private func send() {
        error = ""
        busy = true
        Task {
            do {
                try await app.sendFeedback(text.trimmingCharacters(in: .whitespacesAndNewlines))
                sent = true
            } catch {
                app.handle(error)
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
