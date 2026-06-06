import SwiftUI

/// Sign-in screen shown when there is no session (gate state `.needsLogin`).
/// Supports email/password and passwordless magic-link sign-in. On success the
/// auth state changes, `AccountGate` advances, and the host swaps this view out;
/// this view only triggers the sign-in calls.
struct LoginView: View {
    let auth: any AuthProviding

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var magicLinkSent = false

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Sign in to \(AppMetadata.name)")
                    .font(.title2).bold()
                Text("Bogi requires a paid account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .disableAutocorrection(true)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .onSubmit { submitPassword() }
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 320)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if magicLinkSent {
                Text("Check your email for a sign-in link.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Button(action: submitPassword) {
                    Text("Sign in").frame(maxWidth: 320)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmitPassword)

                Button("Email me a magic link", action: submitMagicLink)
                    .buttonStyle(.link)
                    .disabled(!isValidEmail || isWorking)
            }

            if isWorking {
                ProgressView().controlSize(.small)
            }
        }
        .padding(32)
        .frame(width: 420, height: 360)
    }

    private var isValidEmail: Bool {
        email.contains("@") && !email.hasPrefix("@") && !email.hasSuffix("@")
    }

    private var canSubmitPassword: Bool {
        isValidEmail && !password.isEmpty && !isWorking
    }

    private func submitPassword() {
        guard canSubmitPassword else { return }
        run { try await auth.signIn(email: email, password: password) }
    }

    private func submitMagicLink() {
        guard isValidEmail, !isWorking else { return }
        run {
            try await auth.signInWithMagicLink(email: email)
            magicLinkSent = true
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        magicLinkSent = false
        Task {
            do {
                try await operation()
            } catch {
                errorMessage = friendlyMessage(for: error)
            }
            isWorking = false
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        "Could not sign in. Check your credentials and try again."
    }
}
