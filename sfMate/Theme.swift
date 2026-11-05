import SwiftUI

// The website's colors (app/static/*.html in the sfmate repo)
extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }

    static let sfGold = Color(hex: 0xb27a3f)
    static let sfGoldDark = Color(hex: 0x8a5d2e)       // gold for text-sized things, readable on white
    static let sfBrown = Color(hex: 0x3e251b)
    static let sfBackground = Color(hex: 0xfaf7f2)     // warm off-white
    static let sfText = Color(hex: 0x2a1d16)
    static let sfMuted = Color(hex: 0x7d6b5d)
    static let sfBorder = Color(hex: 0xe6ddd2)
    static let sfCream = Color(hex: 0xf3ede5)
    static let sfErrorText = Color(hex: 0x7a4b14)
    static let sfErrorBackground = Color(hex: 0xfbf3e8)
    static let sfErrorBorder = Color(hex: 0xe9cfae)
}

struct GoldButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(configuration.isPressed ? Color.sfGoldDark : Color.sfGold, in: RoundedRectangle(cornerRadius: 10))
            .opacity(isEnabled ? 1 : 0.6)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Color.sfBrown : Color.sfMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(configuration.isPressed ? Color.sfCream : .clear, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A text field with the website's look: white, thin warm border, gold when focused.
struct SFField: ViewModifier {
    var focused: Bool
    func body(content: Content) -> some View {
        content
            .font(.system(size: 15))
            .foregroundStyle(Color.sfText)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused ? Color.sfGold : Color.sfBorder, lineWidth: 1))
    }
}

extension View {
    func sfField(focused: Bool = false) -> some View { modifier(SFField(focused: focused)) }

    /// The white card with a soft shadow the login and setup pages sit in.
    func sfCard() -> some View {
        padding(.horizontal, 24).padding(.vertical, 28)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.sfBrown.opacity(0.08), radius: 16, y: 8)
    }
}

/// The site's form error / notice box.
struct NoticeText: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.sfErrorText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color.sfErrorBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.sfErrorBorder, lineWidth: 1))
    }
}

/// The knight in a gold ring (the chat avatar and the welcome screen).
struct KnightAvatar: View {
    var size: CGFloat = 30
    var body: some View {
        Image("Knight")   // already cut to a circle, so it fills the ring edge to edge
            .resizable().scaledToFit()
            .frame(width: size, height: size)
            .background(.white, in: Circle())
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.sfGold, lineWidth: size > 60 ? 2 : 1.5))
            .accessibilityLabel("sfMate")
    }
}

/// Three blinking gold dots while sfMate is thinking.
struct TypingDots: View {
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle().fill(Color.sfGold).frame(width: 7, height: 7)
                    .opacity(dotOpacity(i))
            }
        }
        .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 } }
        .accessibilityLabel("sfMate is typing")
    }

    private func dotOpacity(_ i: Int) -> Double {
        let t = (phase - Double(i) * 0.17).truncatingRemainder(dividingBy: 1)
        return t < 0.4 ? 0.25 + 1.9 * t : max(0.25, 1 - (t - 0.4) * 1.9)
    }
}
