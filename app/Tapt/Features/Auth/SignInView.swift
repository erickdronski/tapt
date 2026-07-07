import SwiftUI
import AuthenticationServices
import CryptoKit
import Supabase

/// Sign in with Apple (native) -> Supabase. Bundle id app.tapt.tapt is registered
/// with the Sign in with Apple capability; enable the Apple provider in Supabase and
/// add app.tapt.tapt to its Authorized Client IDs (see docs/07-APPLE-SETUP.md).
struct SignInView: View {
    @State private var currentNonce: String?
    @State private var errorText: String?

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Text("Tapt")
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                    .foregroundStyle(Brand.text)
                Text("THE beer app")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Brand.muted)
                Text("Scan it. Score it. Find it on tap.")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
                Spacer()

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
                .padding(.horizontal, 36)

                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.red).padding(.horizontal, 36)
                }

                Text("By continuing you confirm you are of legal drinking age.")
                    .font(.caption2)
                    .foregroundStyle(Brand.muted)
                    .padding(.bottom, 24)
            }
        }
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
