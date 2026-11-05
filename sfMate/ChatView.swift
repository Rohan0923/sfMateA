import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var chat = ChatModel()
    @State private var draft = ""
    @State private var showFeedback = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteError: String?
    @FocusState private var typing: Bool

    /// The Daily Announcements are for @sfhs.com accounts only, so everyone else gets a different suggestion there.
    private var suggestions: [String] {
        ["When is the next liturgy?",
         app.isSchoolMember ? "Announcement summary" : "What's the dress code?",
         "What's on the menu?",
         "Upcoming events this week?"]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            messages
            composer
        }
        .background(Color.sfBackground)
        .sheet(isPresented: $showFeedback) { FeedbackView() }
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: deleteAccount)
        } message: {
            Text("This permanently deletes your sfMate account, profile, and feedback. It can't be undone.")
        }
        .alert("Couldn't delete your account", isPresented: Binding(get: { deleteError != nil },
                                                                    set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .disabled(deleting)
        .task { await chat.loadWelcome(for: app) }
        .task { await Reminders.shared.sync() }
        .task {
            while !Task.isCancelled {   // the website checks each minute too
                await chat.checkAnnouncements(app: app)
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await chat.checkAnnouncements(app: app) }
                Task { await Reminders.shared.sync() }   // picks up liturgy and activity days added since last time
            }
        }
        #if DEBUG
        .task {   // test builds only: SFMATE_ASK asks a question on launch (for screenshots)
            if let question = ProcessInfo.processInfo.environment["SFMATE_ASK"] {
                try? await Task.sleep(for: .seconds(2))
                chat.send(question, app: app)
            }
        }
        #endif
    }

    // ---------- header: logo, new chat, profile menu, gold line ----------
    private var header: some View {
        HStack(spacing: 10) {
            Image("Logo").resizable().scaledToFit().frame(height: 30)
            Spacer()
            Button {
                chat.newChat()
                Task { await chat.checkAnnouncements(app: app) }
            } label: {
                Label("New chat", systemImage: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.sfBorder, lineWidth: 1))
            }
            .foregroundStyle(Color.sfText)
            Button { showFeedback = true } label: {
                Image(systemName: "exclamationmark.bubble")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 34, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.sfBorder, lineWidth: 1))
            }
            .foregroundStyle(Color.sfText)
            .accessibilityLabel("Send feedback")
            Menu {
                if let me = app.me {
                    Text(app.firstName ?? me.name)
                }
                Button("Profile, topics & reminders", systemImage: "person.text.rectangle") { app.openProfile() }
                Button("Send feedback", systemImage: "exclamationmark.bubble") { showFeedback = true }
                Link(destination: API.shared.baseURL.appendingPathComponent("support")) {
                    Label("Support", systemImage: "questionmark.circle")
                }
                Link(destination: API.shared.baseURL.appendingPathComponent("privacy")) {
                    Label("Privacy policy", systemImage: "hand.raised")
                }
                Divider()
                Button("Log out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { app.signOut() }
                Button("Delete account", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 24)).foregroundStyle(Color.sfBrown)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Account")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.sfGold).frame(height: 2) }
    }

    // ---------- the conversation ----------
    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if chat.showingWelcome { welcome }
                    ForEach(chat.messages) { message in
                        MessageRow(message: message, chat: chat).id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16).padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.last?.text) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: chat.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            KnightAvatar(size: 96).padding(.bottom, 14)
            Text(app.firstName.map { "Hey \($0), I'm sfMate 👋" } ?? "Hey, I'm sfMate 👋")
                .font(.system(size: 26, weight: .bold)).foregroundStyle(Color.sfBrown)
                .multilineTextAlignment(.center).padding(.bottom, 6)
            if chat.welcomeLoading {
                TypingDots().padding(.horizontal, 16).padding(.vertical, 14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sfBorder, lineWidth: 1))
                    .padding(.vertical, 10)
            } else if let note = chat.welcomeNote {
                Text(note)   // the personalized greeting, styled like one of sfMate's bubbles
                    .font(.system(size: 15)).foregroundStyle(Color.sfText).lineSpacing(3)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(alignment: .leading) {
                        ZStack(alignment: .leading) { Color.white; Color.sfGold.frame(width: 3) }   // gold left edge
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sfBorder, lineWidth: 1))
                    .padding(.vertical, 10)
            }
            Text(app.isSchoolMember ? "Ask me about announcements, the calendar, lunch, clubs, classes, or school rules."
                                    : "Ask me about the calendar, lunch, clubs, classes, or school rules.")
                .font(.system(size: 15)).foregroundStyle(Color.sfMuted).multilineTextAlignment(.center)
                .padding(.top, 4).padding(.bottom, 22)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button { chat.send(suggestion, app: app) } label: {
                        Text(suggestion)
                            .font(.system(size: 14)).foregroundStyle(Color.sfText).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sfBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(chat.busy)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }

    // ---------- the message box ----------
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask sfMate anything about Saint Francis…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($typing)
                .font(.system(size: 15))
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(typing ? Color.sfGold : Color.sfBorder, lineWidth: 1))
                .onSubmit(send)
            Button(action: chat.busy ? chat.stop : send) {
                Image(systemName: chat.busy ? "stop.fill" : "arrow.up")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(canSend || chat.busy ? Color.sfGold : Color.sfGold.opacity(0.45), in: Circle())
            }
            .disabled(!canSend && !chat.busy)
            .accessibilityLabel(chat.busy ? "Stop" : "Send")
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
        .background(Color.sfBackground)
    }

    private func deleteAccount() {
        deleting = true
        Task {
            do { try await app.deleteAccount() } catch {
                app.handle(error)
                deleteError = error.localizedDescription
            }
            deleting = false
        }
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func send() {
        guard canSend, !chat.busy else { return }
        chat.send(draft, app: app)
        draft = ""
    }
}

/// One message: the student's (brown, right) or sfMate's (white, left, with the knight).
struct MessageRow: View {
    @Environment(AppModel.self) private var app
    let message: ChatMessage
    let chat: ChatModel

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(.system(size: 15)).foregroundStyle(.white).lineSpacing(3)
                    .padding(.horizontal, 15).padding(.vertical, 11)
                    .background(Color.sfBrown, in: UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14,
                                                                           bottomTrailingRadius: 4, topTrailingRadius: 14))
                    .textSelection(.enabled)
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                KnightAvatar(size: 30)
                bubble
                Spacer(minLength: 24)
            }
        }
    }

    private var failed: Bool { message.state == .failed }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.state == .waiting || (message.state == .stopped && message.text.isEmpty) {
                if message.state == .stopped {
                    Text("(stopped)").italic().font(.system(size: 15)).foregroundStyle(Color.sfMuted)
                } else {
                    TypingDots().padding(.vertical, 4)
                    if message.waking {
                        Text("Waking up sfMate's brain… the first question after a quiet spell can take a minute or two.")
                            .font(.system(size: 13)).foregroundStyle(Color.sfMuted)
                    }
                }
            } else if failed {
                Text(message.text).font(.system(size: 15)).foregroundStyle(Color.sfErrorText)
            } else {
                MessageText(text: message.text, sources: message.sources)
                if message.state == .stopped {
                    Text("(stopped)").italic().font(.system(size: 15)).foregroundStyle(Color.sfMuted)
                }
                if let prompt = message.prompt {
                    announcementButtons(prompt)
                }
                if message.state == .done && !message.sources.isEmpty {
                    SourcesView(sources: message.sources)
                }
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
        .background(failed ? Color.sfErrorBackground : .white,
                    in: UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 4, bottomTrailingRadius: 14, topTrailingRadius: 14))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 4, bottomTrailingRadius: 14, topTrailingRadius: 14)
            .stroke(failed ? Color.sfErrorBorder : Color.sfBorder, lineWidth: 1))
    }

    private func announcementButtons(_ prompt: AnnouncementStatus) -> some View {
        HStack(spacing: 8) {
            Button("Yes, summarize") { chat.summarize(prompt: message.id, app: app) }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(Color.sfGold, in: Capsule())
            Button("No thanks") { chat.decline(prompt: message.id) }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.sfGoldDark)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .overlay(Capsule().stroke(Color.sfBorder, lineWidth: 1.5))
        }
        .disabled(!prompt.available || chat.busy)
        .opacity(prompt.available ? 1 : 0.45)
        .padding(.top, 2)
    }
}
