import SwiftUI

/// Log in, or sign up with a school email: details first, then the 6-digit code the server emails.
struct AuthView: View {
    @Environment(AppModel.self) private var app

    enum Mode { case login, signup, verify }
    @State private var mode: Mode = .login
    @State private var login = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var code = ""
    @State private var pendingEmail = ""
    @State private var error = ""
    @State private var notice = ""
    @State private var busy = false
    @State private var resendIn = 0
    @FocusState private var focus: Field?

    enum Field { case login, password, username, email, signupPassword, confirm, code }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image("Logo").resizable().scaledToFit().frame(height: 64).padding(.top, 36)
                Text("Your Saint Francis advisor").font(.system(size: 14)).foregroundStyle(Color.sfMuted)

                VStack(alignment: .leading, spacing: 16) {
                    switch mode {
                    case .login: loginForm
                    case .signup: signupForm
                    case .verify: verifyForm
                    }
                }
                .sfCard()
                .padding(.horizontal, 20)

                HStack(spacing: 18) {
                    Link("Privacy policy", destination: API.shared.baseURL.appendingPathComponent("privacy"))
                    Link("Support", destination: API.shared.baseURL.appendingPathComponent("support"))
                }
                .font(.system(size: 13, weight: .semibold)).tint(.sfGoldDark)
            }
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(LinearGradient(colors: [Color(hex: 0xfaf7f2), Color.sfCream], startPoint: .topLeading, endPoint: .bottomTrailing))
        .task(id: resendIn) {
            guard resendIn > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            resendIn -= 1
        }
    }

    // ---------- log in ----------
    private var loginForm: some View {
        Group {
            title("Log in")
            if !error.isEmpty { NoticeText(text: error) }
            labeled("Username or email") {
                TextField("Enter your username or email", text: $login)
                    .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: .login).submitLabel(.next).onSubmit { focus = .password }
                    .sfField(focused: focus == .login)
            }
            labeled("Password") {
                SecureField("Enter your password", text: $password)
                    .textContentType(.password)
                    .focused($focus, equals: .password).submitLabel(.go).onSubmit(doLogin)
                    .sfField(focused: focus == .password)
            }
            Button(busy ? "Logging in…" : "Log in", action: doLogin).buttonStyle(GoldButtonStyle())
                .disabled(busy || login.isEmpty || password.isEmpty)
            switchLink("Don't have an account?", "Sign up") { switchTo(.signup) }
        }
    }

    // ---------- sign up, step 1 ----------
    private var signupForm: some View {
        Group {
            title("Create account")
            if !error.isEmpty { NoticeText(text: error) }
            labeled("Username") {
                TextField("Choose a username", text: $username)
                    .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: .username).submitLabel(.next).onSubmit { focus = .email }
                    .sfField(focused: focus == .username)
            }
            VStack(alignment: .leading, spacing: 6) {
                labeled("Email") {
                    TextField("you@example.com", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: .email).submitLabel(.next).onSubmit { focus = .signupPassword }
                        .sfField(focused: focus == .email)
                }
                Text("Use your @sfhs.com school email to also get the Daily Announcements.")
                    .font(.system(size: 12.5)).foregroundStyle(Color.sfMuted).lineSpacing(2)
            }
            labeled("Password") {
                SecureField("At least 8 characters", text: $password)
                    .textContentType(.newPassword)
                    .focused($focus, equals: .signupPassword).submitLabel(.next).onSubmit { focus = .confirm }
                    .sfField(focused: focus == .signupPassword)
            }
            labeled("Confirm password") {
                SecureField("Confirm your password", text: $confirm)
                    .textContentType(.newPassword)
                    .focused($focus, equals: .confirm).submitLabel(.go).onSubmit(doSignup)
                    .sfField(focused: focus == .confirm)
            }
            Button(busy ? "Sending code…" : "Sign up", action: doSignup).buttonStyle(GoldButtonStyle())
                .disabled(busy || username.isEmpty || email.isEmpty || password.isEmpty)
            switchLink("Already have an account?", "Log in") { switchTo(.login) }
        }
    }

    // ---------- sign up, step 2: the emailed code ----------
    private var verifyForm: some View {
        Group {
            title("Check your email")
            (Text("We emailed a 6-digit code to ") + Text(pendingEmail).bold().foregroundColor(.sfBrown)
             + Text(". It expires in 15 minutes. Not seeing it? Check spam or junk."))
                .font(.system(size: 14)).foregroundStyle(Color.sfMuted).lineSpacing(3)
            if !error.isEmpty { NoticeText(text: error) }
            if !notice.isEmpty { NoticeText(text: notice) }
            labeled("Verification code") {
                TextField("••••••", text: $code)
                    .textContentType(.oneTimeCode).keyboardType(.numberPad)
                    .font(.system(size: 22, weight: .medium).monospacedDigit())
                    .multilineTextAlignment(.center).kerning(8)
                    .focused($focus, equals: .code)
                    .onChange(of: code) { _, new in
                        let digits = String(new.filter(\.isNumber).prefix(6))   // people paste "123 456" or "Code: 123456"
                        if digits != new { code = digits }
                        if digits.count == 6 { doVerify() }
                    }
                    .sfField(focused: focus == .code)
            }
            Button(busy ? "Checking…" : "Verify & continue", action: doVerify).buttonStyle(GoldButtonStyle())
                .disabled(busy || code.count != 6)
            HStack(spacing: 6) {
                Button(resendIn > 0 ? "Resend code (\(resendIn)s)" : "Resend code", action: doResend)
                    .disabled(resendIn > 0)
                Text("·").foregroundStyle(Color.sfMuted)
                Button("Use a different email") { switchTo(.signup) }
            }
            .font(.system(size: 13, weight: .medium)).tint(.sfGold)
            .frame(maxWidth: .infinity)
        }
    }

    // ---------- pieces ----------
    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 24, weight: .bold)).foregroundStyle(Color.sfBrown)
            .frame(maxWidth: .infinity, alignment: .center).padding(.bottom, 2)
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.sfBrown)
            content()
        }
    }

    private func switchLink(_ prompt: String, _ action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(prompt).foregroundStyle(Color.sfMuted)
            Button(action, action: perform).fontWeight(.semibold).tint(.sfGold)
        }
        .font(.system(size: 14)).frame(maxWidth: .infinity).padding(.top, 4)
    }

    private func switchTo(_ new: Mode) {
        error = ""; notice = ""; code = ""
        if new != .verify { confirm = "" }
        mode = new
    }

    // ---------- actions ----------
    private func run(_ work: @escaping () async throws -> Void) {
        error = ""; notice = ""
        busy = true
        Task {
            do { try await work() } catch { self.error = error.localizedDescription }
            busy = false
        }
    }

    private func doLogin() {
        guard !login.isEmpty, !password.isEmpty, !busy else { return }
        run { try await app.login(login.trimmingCharacters(in: .whitespaces), password: password) }
    }

    private func doSignup() {
        guard !busy else { return }
        guard password == confirm else { error = "Passwords do not match"; return }
        run {
            pendingEmail = try await app.startSignup(username: username.trimmingCharacters(in: .whitespaces),
                                                     email: email.trimmingCharacters(in: .whitespaces), password: password)
            switchTo(.verify)
            resendIn = 60   // the server's cooldown between code emails
            focus = .code
        }
    }

    private func doVerify() {
        guard code.count == 6, !busy else { return }
        run { try await app.verify(email: pendingEmail, code: code) }
    }

    private func doResend() {
        run {
            try await app.resendCode(email: pendingEmail)
            notice = "New code sent. Check your inbox."
            resendIn = 60
        }
    }
}
