import SwiftUI

/// Asks permission before anything is sent to the AI provider (Apple guideline 5.1.2: explicit permission before
/// sharing personal data with third-party AI). Shown after setup, and again if the student withdraws it in Profile.
struct ConsentView: View {
    @Environment(AppModel.self) private var app
    @State private var busy = false
    @State private var declined = false
    @State private var error = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                KnightAvatar(size: 72).padding(.top, 32)
                VStack(alignment: .leading, spacing: 16) {
                    Text("sfMate uses AI to answer you")
                        .font(.system(size: 24, weight: .bold)).foregroundStyle(Color.sfBrown)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    Text("To write each answer, sfMate sends these to **RunPod**, the company that runs sfMate's AI model:")
                        .font(.system(size: 15)).foregroundStyle(Color.sfText)
                    VStack(alignment: .leading, spacing: 8) {
                        bullet("your question and the last few messages of the chat")
                        bullet("your profile details, if you filled them in (first name, grade, hobbies, favorite food)")
                        bullet("the school information that answers your question")
                    }
                    Text("RunPod uses this only to write your answer. sfMate never sells your information or uses it for ads.")
                        .font(.system(size: 14)).foregroundStyle(Color.sfMuted).lineSpacing(2)

                    if !error.isEmpty { NoticeText(text: error) }
                    if declined {
                        NoticeText(text: "No problem. sfMate can't answer questions without this, so the chat stays off. You can agree any time, or log out below.")
                    }

                    VStack(spacing: 4) {
                        Button(busy ? "Saving…" : "I agree", action: agree)
                            .buttonStyle(GoldButtonStyle()).disabled(busy)
                        if declined {
                            Button("Log out") { app.signOut() }.buttonStyle(GhostButtonStyle())
                        } else {
                            Button("No thanks") { declined = true }.buttonStyle(GhostButtonStyle())
                        }
                    }

                    Text("You can change this any time in Profile, topics & reminders.")
                        .font(.system(size: 12.5)).foregroundStyle(Color.sfMuted)
                        .frame(maxWidth: .infinity)
                    Link("Privacy policy", destination: API.shared.baseURL.appendingPathComponent("privacy"))
                        .font(.system(size: 13, weight: .semibold)).tint(.sfGoldDark)
                        .frame(maxWidth: .infinity)
                }
                .sfCard()
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 30)
        }
        .background(LinearGradient(colors: [Color(hex: 0xfaf7f2), Color.sfCream], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Color.sfGold).frame(width: 6, height: 6)
            Text(text).font(.system(size: 15)).foregroundStyle(Color.sfText)
        }
    }

    private func agree() {
        error = ""
        busy = true
        Task {
            do { try await app.setAIConsent(true) } catch {
                app.handle(error)
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
