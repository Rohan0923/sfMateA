import SwiftUI

@main
struct sfMateApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.light)   // the website's look is light only
                .tint(.sfGold)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.screen {
        case .launching:
            ZStack {
                Color.sfBackground.ignoresSafeArea()
                KnightAvatar(size: 96)
            }
        case .signedOut:
            AuthView()
        case .setup:
            SetupView()
        case .consent:
            ConsentView()
        case .chat:
            ChatView()
        }
    }
}
