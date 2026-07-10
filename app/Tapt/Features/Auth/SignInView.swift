import SwiftUI
import AuthenticationServices
import CryptoKit
import Security
import Supabase

/// Sign in. Providers are detected at runtime from the Supabase project, so
/// only buttons that can actually succeed are shown, the moment a provider is
/// enabled in the dashboard it appears here with no app update.
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
                    Text("THE Beer Superapp")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Brand.muted)
                    Text("Scan it. Score it. Stamp your Passport.")
                        .font(.subheadline)
                        .foregroundStyle(Brand.muted)
                    Spacer(minLength: 24)

                    if providers.apple {
                        appleButton.padding(.horizontal, 36)
                    }

                    VStack(spacing: 10) {
                        if providers.google { oauthButton("Continue with Google", "globe", .google) }
                        if providers.facebook { oauthButton("Continue with Facebook", "person.2.fill", .facebook) }
                        if providers.twitter { oauthButton("Continue with X", "x.circle.fill", .x) }
                    }
                    .padding(.horizontal, 36)

                    divider

                    emailSection.padding(.horizontal, 36)

                    if let errorText = errorText ?? session.authError {
                        Text(errorText)
                            .font(.footnote).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                    }

                    Text("By continuing you confirm you are of legal drinking age.")
                        .font(.caption2)
                        .foregroundStyle(Brand.muted)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
            }
        }
        .task {
            guard !providersLoaded else { return }
            providersLoaded = true
            providers = await AuthProvidersService.flags()
        }
    }

    private var divider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Brand.muted.opacity(0.25)).frame(height: 1)
            Text("or use email")
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
                    Text("Check your email, tap the link, or type the 6-digit code from the same email here:")
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
        code = ""
        emailLinkSent = await session.sendEmailSignInLink(to: email)
        isSendingEmail = false
    }

    private func verifyCode() async {
        verifyingCode = true
        errorText = nil
        _ = await session.verifyEmailCode(email: email, code: code)
        verifyingCode = false
    }

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
