import SwiftUI
import AuthenticationServices
import CryptoKit
import Security
import Supabase

/// Sign in. External providers appear only when they are enabled in Supabase
/// and have completed the live provider verification gate for this release.
/// Email supports both the magic link AND typing the 6-digit code from the
/// same email (survives cross-device and link-scanner problems).
struct SignInView: View {
    @Environment(Session.self) private var session
    @State private var providers = AuthProviderFlags.fallback
    @State private var providersLoaded = false
    @State private var email = ""
    @State private var code = ""
    @State private var isSendingEmail = false
    @State private var emailLinkSent = false
    @State private var codeEmail = ""
    @State private var verifyingCode = false
    @State private var currentNonce: String?
    @State private var errorText: String?

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Spacer(minLength: 28)
                    BeerGlassView(pour: 0.82)
                        .frame(width: 92)
                    HStack(spacing: 0) {
                        Text("Tapt").foregroundStyle(Brand.text)
                        Text(".").foregroundStyle(Brand.gold)
                    }
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                    Text("THE Beer Superapp. All of beer, one app.")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Brand.muted)
                        .multilineTextAlignment(.center)
                    Text("Discover, log, learn, play, and find what is pouring near you.")
                        .font(.subheadline)
                        .foregroundStyle(Brand.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    Spacer(minLength: 24)

                    if providers.email {
                        emailSection.padding(.horizontal, 36)
                    }

                    if hasExternalProviders {
                        divider("or continue with")

                        if providers.apple {
                            appleButton.padding(.horizontal, 36)
                        }

                        VStack(spacing: 10) {
                            if providers.google { oauthButton("Continue with Google", "globe", .google) }
                            if providers.facebook { oauthButton("Continue with Facebook", "person.2.fill", .facebook) }
                            if providers.twitter { oauthButton("Continue with X", "x.circle.fill", .x) }
                        }
                        .padding(.horizontal, 36)
                    }

                    if !session.isGuest {
                        Button {
                            session.continueAsGuest()
                        } label: {
                            Label("Explore without an account", systemImage: "safari.fill")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .foregroundStyle(Brand.text)
                                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.malt.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 36)
                    }

                    if let errorText = errorText ?? session.authError {
                        Text(errorText)
                            .font(.footnote).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                    }

                    #if targetEnvironment(simulator)
                    if Self.devCredentialsAvailable {
                        Button {
                            Task { await devSignIn() }
                        } label: {
                            Label("Dev sign in (sim only)", systemImage: "hammer.fill")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Brand.malt, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Brand.gold)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 36)
                        .padding(.top, 8)
                    }
                    #endif

                    VStack(spacing: 6) {
                        Text("By continuing you confirm you are of legal drinking age and agree to the Tapt Terms of Service and Privacy Policy.")
                            .font(.caption2)
                            .foregroundStyle(Brand.muted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                        HStack(spacing: 14) {
                            Link("Terms of Service", destination: URL(string: "https://taptbeer.com/terms")!)
                            Link("Privacy Policy", destination: URL(string: "https://taptbeer.com/privacy")!)
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Brand.gold)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .task {
            guard !providersLoaded else { return }
            providersLoaded = true
            providers = await AuthProvidersService.flags()
            #if targetEnvironment(simulator)
            if Self.devCredentialsAvailable,
               ProcessInfo.processInfo.environment["TAPT_DEV_AUTOLOGIN"] == "1" {
                await devSignIn()
            }
            #endif
        }
    }

    private var hasExternalProviders: Bool {
        providers.apple || providers.google || providers.facebook || providers.twitter
    }

    private func divider(_ label: String) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(Brand.muted.opacity(0.25)).frame(height: 1)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.muted)
                .fixedSize()
            Rectangle().fill(Brand.muted.opacity(0.25)).frame(height: 1)
        }
        .padding(.horizontal, 36)
    }

    private var emailSection: some View {
        VStack(spacing: 10) {
            TextField("Email address", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .rounded))
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Brand.text)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.malt.opacity(0.14)))

            Button {
                Task { await sendEmailLink() }
            } label: {
                Label(isSendingEmail ? "Sending..." : (emailLinkSent ? "Send a new email" : "Email me a sign-in link"),
                      systemImage: "envelope.fill")
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .disabled(!canSendEmail || isSendingEmail)
            .opacity(canSendEmail && !isSendingEmail ? 1 : 0.55)

            if emailLinkSent {
                VStack(spacing: 8) {
                    Text("Check \(codeEmail), tap the link, or type the 6-digit code here:")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 8) {
                        TextField("6-digit code", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .frame(height: 50)
                            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Brand.malt.opacity(0.14)))
                        Button {
                            Task { await verifyCode() }
                        } label: {
                            Text(verifyingCode ? "..." : "Verify")
                                .font(.system(.headline, design: .rounded))
                                .padding(.horizontal, 18)
                                .frame(height: 50)
                                .background(Brand.hop, in: RoundedRectangle(cornerRadius: 13))
                                .foregroundStyle(Brand.malt)
                        }
                        .buttonStyle(.plain)
                        .disabled(code.filter(\.isNumber).count < 6 || verifyingCode)
                        .opacity(code.filter(\.isNumber).count >= 6 ? 1 : 0.55)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            let nonce = Self.randomNonce()
            currentNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            handle(result)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var canSendEmail: Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).contains("@")
    }

    private func sendEmailLink() async {
        isSendingEmail = true
        errorText = nil
        let target = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sent = await session.sendEmailSignInLink(to: target)
        if sent {
            codeEmail = target
            code = ""
            emailLinkSent = true
        }
        isSendingEmail = false
    }

    private func verifyCode() async {
        verifyingCode = true
        errorText = nil
        _ = await session.verifyEmailCode(email: codeEmail, code: code)
        verifyingCode = false
    }

    #if targetEnvironment(simulator)
    private static var devCredentialsAvailable: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["TAPT_DEV_EMAIL"]?.isEmpty == false && env["TAPT_DEV_PASSWORD"]?.isEmpty == false
    }

    /// Simulator-only shortcut configured through the local Xcode scheme. No test
    /// identity or credential is compiled into device, TestFlight, or App Store builds.
    private func devSignIn() async {
        errorText = nil
        let env = ProcessInfo.processInfo.environment
        guard let email = env["TAPT_DEV_EMAIL"], !email.isEmpty,
              let password = env["TAPT_DEV_PASSWORD"], !password.isEmpty else {
            errorText = "Add TAPT_DEV_EMAIL and TAPT_DEV_PASSWORD to the local Xcode scheme."
            return
        }
        do {
            try await Supa.client.auth.signIn(email: email, password: password)
            let userId = try await Supa.client.auth.session.user.id.uuidString
            var ids = Set((UserDefaults.standard.string(forKey: "onboardedUserIDs") ?? "")
                .split(separator: ",").map(String.init))
            ids.insert(userId)
            UserDefaults.standard.set(ids.sorted().joined(separator: ","), forKey: "onboardedUserIDs")
        } catch {
            errorText = "Dev sign in failed: \(error.localizedDescription)"
        }
    }
    #endif

    private func oauthButton(_ title: String, _ icon: String, _ provider: Provider) -> some View {
        Button {
            errorText = nil
            Task { await session.signInWithOAuth(provider) }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Brand.text)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.malt.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard
                let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = cred.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                errorText = "Could not read the Apple credential."
                return
            }
            Task {
                do {
                    try await Supa.client.auth.signInWithIdToken(
                        credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                    )
                    await saveAppleName(cred.fullName)
                } catch {
                    errorText = error.localizedDescription
                }
            }
        case .failure(let err):
            // User-cancel is not an error worth showing.
            if (err as? ASAuthorizationError)?.code != .canceled {
                errorText = err.localizedDescription
            }
        }
    }

    /// Apple provides the person's name only on the first authorization and does
    /// not include it in the identity token, so preserve it immediately.
    private func saveAppleName(_ components: PersonNameComponents?) async {
        guard let components else { return }
        let fullName = PersonNameComponentsFormatter().string(from: components)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var metadata: [String: AnyJSON] = [:]
        if !fullName.isEmpty { metadata["full_name"] = .string(fullName) }
        if let given = components.givenName, !given.isEmpty {
            metadata["given_name"] = .string(given)
        }
        if let family = components.familyName, !family.isEmpty {
            metadata["family_name"] = .string(family)
        }
        if !metadata.isEmpty {
            try? await Supa.client.auth.update(user: UserAttributes(data: metadata))
        }
    }

    // MARK: - Nonce helpers (Apple requires a hashed nonce; Supabase needs the raw one)
    static func randomNonce(_ length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var byte: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
            if Int(byte) < charset.count {
                result.append(charset[Int(byte)])
                remaining -= 1
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
