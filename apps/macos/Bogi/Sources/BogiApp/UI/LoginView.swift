import SwiftUI

/// Paid-account-first gate shown before the app unlocks. Rendering-only: auth and the
/// website hand-off are injected closures so this view has no Supabase/network coupling.
struct LoginView: View {
    /// Authenticates with email + password; throws on failure.
    let signIn: (String, String) async throws -> Void
    /// Opens the marketing/billing site (subscriptions are managed on the web).
    let openWebsite: () -> Void

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var signingIn: Bool = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                BogiAsset.mascot
                    .resizable().scaledToFit()
                    .frame(width: 56, height: 56)
                Text("Sign in to Togi")
                    .font(.title2).bold()
                Text("Togi requires an active subscription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            VStack(spacing: 10) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .disableAutocorrection(true)

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .onSubmit(submit)
            }
            .textFieldStyle(.roundedBorder)
            .disabled(signingIn)

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: submit) {
                if signingIn {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Sign In").frame(maxWidth: .infinity)
                }
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)

            Button("Need an account? Subscribe on the website", action: openWebsite)
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(28)
        .frame(width: 340)
    }

    private var canSubmit: Bool {
        !signingIn
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        errorText = nil
        signingIn = true

        Task {
            do {
                try await signIn(email.trimmingCharacters(in: .whitespaces), password)
            } catch {
                errorText = error.localizedDescription
            }
            signingIn = false
        }
    }
}

#if DEBUG
#Preview("Login") {
    LoginView(
        signIn: { _, _ in
            try? await Task.sleep(nanoseconds: 600_000_000)
            throw NSError(domain: "Bogi", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No active subscription for this account."])
        },
        openWebsite: {}
    )
}
#endif
