import SwiftUI

/// First-time setup, and the Profile screen later: name, grade, hobbies, food, Announcement Preferences, and reminders.
struct SetupView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    // keys and labels must match TOPICS in sfmate/app/announcements.py
    static let topics: [(key: String, label: String)] = [
        ("daytype_birthdays", "Day type and Birthdays"),
        ("highlights", "Highlights and school-wide announcements"),
        ("happening_today", "Happening today"),
        ("activities", "Activities Announcements"),
        ("clubs_events", "Clubs and Events Announcements"),
        ("affinity", "Affinity Groups"),
        ("mission_ministry", "Mission and Ministry"),
        ("athletics", "Athletics"),
        ("counseling", "Counseling Announcements"),
        ("library", "Library Announcements"),
    ]
    static let gradeNames = [9: "Freshman", 10: "Sophomore", 11: "Junior", 12: "Senior"]

    @State private var firstName = ""
    @State private var grade = 9
    @State private var hobbies = ""
    @State private var food = ""
    @State private var chosen = Set(SetupView.topics.map(\.key))
    @State private var topicsOpen = false
    @State private var error = ""
    @State private var busy = false
    @State private var confirmSkip = false
    @State private var confirmStopSharing = false
    @State private var loaded = false
    @FocusState private var focus: Field?

    enum Field { case name, hobbies, food }

    private var editing: Bool { app.editingProfile }
    private var hasProfile: Bool { app.me?.profile != nil && app.me?.profile?.skipped != true }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image("Logo").resizable().scaledToFit().frame(height: 48).padding(.top, 24)
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 6) {
                        Text(editing && hasProfile ? "Update your info" : "Let's get you set up")
                            .font(.system(size: 24, weight: .bold)).foregroundStyle(Color.sfBrown)
                        Text(editing && hasProfile ? "Change whatever you like. sfMate will pick it up on your next message."
                                                    : "A few quick things so sfMate actually knows who it's talking to. Everything's optional.")
                            .font(.system(size: 14)).foregroundStyle(Color.sfMuted).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    if !error.isEmpty { NoticeText(text: error) }

                    labeled("First name") {
                        TextField("What should sfMate call you?", text: $firstName)
                            .textContentType(.givenName).focused($focus, equals: .name)
                            .sfField(focused: focus == .name)
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("Grade").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.sfBrown)
                            Spacer()
                            Text("\(grade) · \(Self.gradeNames[grade] ?? "")")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.sfGoldDark)
                        }
                        Picker("Grade", selection: $grade) {
                            ForEach(9...12, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    labeled("Hobbies & extracurriculars") {
                        TextField("Clubs, sports, music, art, gaming, volunteering — whatever you're into",
                                  text: $hobbies, axis: .vertical)
                            .lineLimit(3...6).focused($focus, equals: .hobbies)
                            .sfField(focused: focus == .hobbies)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        labeled("Favorite food") {
                            TextField("Be honest", text: $food).focused($focus, equals: .food)
                                .sfField(focused: focus == .food)
                        }
                        hint("(Optional)")
                    }

                    announcementPreferences

                    reminderSwitches

                    if editing && app.hasAIConsent { aiSharing }

                    VStack(spacing: 4) {
                        Button(busy ? "Saving…" : (editing ? "Save & back to chatting" : "Save & start chatting"), action: save)
                            .buttonStyle(GoldButtonStyle()).disabled(busy)
                        Button(editing ? "Nah, take me back to the chatbot" : "Yo, just get me to the chatbot") {
                            if editing { app.closeProfile() } else { confirmSkip = true }
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }
                .sfCard()
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(LinearGradient(colors: [Color(hex: 0xfaf7f2), Color.sfCream], startPoint: .topLeading, endPoint: .bottomTrailing))
        .alert("You sure?", isPresented: $confirmSkip) {
            Button("No", role: .cancel) {}
            Button("Yes") { skip() }
        } message: {
            Text("sfMate won't know your name or grade, so answers will be a little less personal. You can always fill this in later from Profile in the chatbot.")
        }
        .onAppear(perform: prefill)
    }

    // ---------- Announcement Preferences: a dropdown of checkboxes ----------
    private var announcementPreferences: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Announcement Preferences").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.sfBrown)
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { topicsOpen.toggle() }
                } label: {
                    HStack {
                        Text(topicsSummary).font(.system(size: 15)).foregroundStyle(Color.sfText)
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.sfMuted).rotationEffect(.degrees(topicsOpen ? 180 : 0))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if topicsOpen {
                    Divider().overlay(Color.sfBorder)
                    HStack(spacing: 16) {
                        Button("Select all") { chosen = Set(Self.topics.map(\.key)) }
                        Button("Clear") { chosen = [] }
                        Spacer()
                    }
                    .font(.system(size: 12.5, weight: .semibold)).tint(.sfGoldDark)
                    .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
                    ForEach(Self.topics, id: \.key) { topic in
                        Button {
                            if chosen.contains(topic.key) { chosen.remove(topic.key) } else { chosen.insert(topic.key) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: chosen.contains(topic.key) ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 18)).foregroundStyle(chosen.contains(topic.key) ? Color.sfGold : Color.sfBorder)
                                Text(topic.label).font(.system(size: 14)).foregroundStyle(Color.sfText)
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 4)
                }
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(topicsOpen ? Color.sfGold : Color.sfBorder, lineWidth: 1))
            hint("When sfMate summarizes the Daily Announcements for you, it covers just these (plus that day's lunch).")
        }
    }

    // ---------- day-before reminders (this iPhone only; they switch on right away, not on Save) ----------
    private var reminderSwitches: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Remind me the night before").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.sfBrown)
            VStack(spacing: 0) {
                reminderRow(.liturgy, "Liturgy days", "L1 and L2")
                Divider().overlay(Color.sfBorder)
                reminderRow(.activity, "Activity days", "A1 – A4 schedules")
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.sfBorder, lineWidth: 1))
            if Reminders.shared.denied {
                NoticeText(text: "Notifications are off for sfMate. Turn them on in Settings to get reminders.")
                Button("Open Settings") { openURL(Reminders.settingsURL) }
                    .font(.system(size: 13, weight: .semibold)).tint(.sfGoldDark)
            }
            hint("sfMate sends a notification at 6 PM the day before, with what's happening and when school starts.")
        }
        .task { await Reminders.shared.checkPermission() }
    }

    // ---------- withdrawing permission to send questions to the AI provider ----------
    private var aiSharing: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("AI data sharing").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.sfBrown)
            hint("You agreed to sfMate sending your questions and profile details to RunPod, which runs its AI, to write answers.")
            Button("Stop sharing (turns off the chat)", role: .destructive) { confirmStopSharing = true }
                .font(.system(size: 14, weight: .semibold))
        }
        .alert("Stop sharing with the AI?", isPresented: $confirmStopSharing) {
            Button("Cancel", role: .cancel) {}
            Button("Stop sharing", role: .destructive) {
                Task {
                    do { try await app.setAIConsent(false) } catch {
                        app.handle(error)
                        self.error = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("sfMate can't answer questions without it. You can turn it back on any time.")
        }
    }

    private func reminderRow(_ kind: Reminders.Kind, _ label: String, _ detail: String) -> some View {
        Toggle(isOn: Binding(get: { Reminders.shared.isOn(kind) },
                             set: { on in Task { await Reminders.shared.set(kind, on) } })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 15)).foregroundStyle(Color.sfText)
                Text(detail).font(.system(size: 12.5)).foregroundStyle(Color.sfMuted)
            }
        }
        .tint(.sfGold)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var topicsSummary: String {
        switch chosen.count {
        case Self.topics.count: "All topics"
        case 0: "No topics (just lunch)"
        default: "\(chosen.count) of \(Self.topics.count) topics"
        }
    }

    // ---------- pieces ----------
    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.sfBrown)
            content()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 12.5)).foregroundStyle(Color.sfMuted).lineSpacing(2)
    }

    // ---------- loading and saving ----------
    private func prefill() {
        guard !loaded else { return }
        loaded = true
        guard let p = app.me?.profile, p.skipped != true else { return }
        firstName = p.first_name ?? ""
        grade = p.grade ?? 9
        hobbies = p.hobbies ?? ""
        food = p.favorite_food ?? ""
        if let topics = p.announcements { chosen = Set(topics) }
    }

    private func save() {
        error = ""
        busy = true
        let profile = Profile(first_name: firstName.trimmingCharacters(in: .whitespaces), grade: grade,
                              hobbies: hobbies.trimmingCharacters(in: .whitespacesAndNewlines),
                              favorite_food: food.trimmingCharacters(in: .whitespaces),
                              announcements: Self.topics.map(\.key).filter(chosen.contains))
        Task {
            do { try await app.saveProfile(profile) } catch {
                app.handle(error)
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    private func skip() {
        Task {
            try? await app.saveProfile(Profile(skipped: true))   // remember it, so setup doesn't come back
            app.closeProfile()
        }
    }
}
