import Foundation
import Combine
import Supabase

/// Framework-light snapshot of an authenticated session. We deliberately do NOT
/// pass Supabase's `Session` around the app so that decision logic (`AccountGate`)
/// and views stay testable without importing the SDK.
struct AuthSession: Equatable {
    var userId: String
    var accessToken: String
    var email: String?

    init(userId: String, accessToken: String, email: String? = nil) {
        self.userId = userId
        self.accessToken = accessToken
        self.email = email
    }
}

/// Observable auth state. `unknown` is the launch state before the persisted
/// session (if any) has been restored.
enum AuthState: Equatable {
    case unknown
    case signedOut
    case signedIn(AuthSession)

    var session: AuthSession? {
        if case let .signedIn(session) = self { return session }
        return nil
    }

    var isSignedIn: Bool { session != nil }
}

/// Supplies the current JWT for authorized backend calls. Split out from
/// `AuthProviding` so `InferenceClientLive` only depends on the token, not the
/// whole auth surface, and can be unit-tested with a trivial stub.
protocol AccessTokenProviding {
    func accessToken() async -> String?
}

/// The auth surface the rest of the app builds against. `SupabaseAuth` is the
/// production implementation; tests inject a mock so the gate and views never
/// touch the network.
protocol AuthProviding: AnyObject, AccessTokenProviding {
    var state: AuthState { get }
    var statePublisher: AnyPublisher<AuthState, Never> { get }

    /// Restore a persisted session (called once on launch).
    func restoreSession() async
    func signIn(email: String, password: String) async throws
    /// Passwordless magic-link / OTP email sign-in.
    func signInWithMagicLink(email: String) async throws
    func signOut() async
}

/// Configuration for the Supabase project. The anon key is a public,
/// client-safe key (RLS enforces access); it is NOT a secret. Resolved from the
/// environment / Info.plist so it isn't hard-coded in source.
struct SupabaseConfig: Equatable {
    var url: URL
    var anonKey: String

    static func resolved(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> SupabaseConfig? {
        func value(_ envKey: String, _ plistKey: String) -> String? {
            if let raw = environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty {
                return raw
            }
            if let raw = (bundle.object(forInfoDictionaryKey: plistKey) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                return raw
            }
            return nil
        }
        guard
            let urlString = value("BOGI_SUPABASE_URL", "BogiSupabaseURL"),
            let url = URL(string: urlString),
            let anonKey = value("BOGI_SUPABASE_ANON_KEY", "BogiSupabaseAnonKey")
        else { return nil }
        return SupabaseConfig(url: url, anonKey: anonKey)
    }
}

/// Wraps `supabase-swift` for email/password + magic-link sign-in, session
/// persistence (handled by the SDK's session storage), the current JWT access
/// token, and sign-out. Publishes an observable `AuthState`.
@MainActor
final class SupabaseAuth: ObservableObject, AuthProviding {
    @Published private(set) var state: AuthState = .unknown

    var statePublisher: AnyPublisher<AuthState, Never> { $state.eraseToAnyPublisher() }

    private let client: SupabaseClient
    private var observationTask: Task<Void, Never>?

    init(config: SupabaseConfig) {
        self.client = SupabaseClient(supabaseURL: config.url, supabaseKey: config.anonKey)
        observeAuthChanges()
    }

    /// Inject a pre-built client (used if other modules already construct one).
    init(client: SupabaseClient) {
        self.client = client
        observeAuthChanges()
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: AccessTokenProviding

    /// Returns a valid (refreshed if necessary) access token, or nil if there is
    /// no session. `client.auth.session` refreshes transparently when expired.
    func accessToken() async -> String? {
        do {
            return try await client.auth.session.accessToken
        } catch {
            return nil
        }
    }

    // MARK: AuthProviding

    func restoreSession() async {
        do {
            let session = try await client.auth.session
            apply(session)
        } catch {
            state = .signedOut
        }
    }

    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(email: email, password: password)
        apply(session)
    }

    func signInWithMagicLink(email: String) async throws {
        // Sends the OTP / magic-link email. The session arrives later via the
        // deep-link callback, surfaced through `observeAuthChanges`.
        try await client.auth.signInWithOTP(email: email)
    }

    func signOut() async {
        try? await client.auth.signOut()
        state = .signedOut
    }

    // MARK: Internals

    private func observeAuthChanges() {
        observationTask = Task { [weak self] in
            guard let self else { return }
            for await change in self.client.auth.authStateChanges {
                self.handle(event: change.event, session: change.session)
            }
        }
    }

    private func handle(event: AuthChangeEvent, session: Session?) {
        switch event {
        case .signedOut, .userDeleted:
            state = .signedOut
        default:
            if let session {
                apply(session)
            } else if event == .initialSession {
                state = .signedOut
            }
        }
    }

    private func apply(_ session: Session) {
        state = .signedIn(
            AuthSession(
                userId: session.user.id.uuidString,
                accessToken: session.accessToken,
                email: session.user.email
            )
        )
    }
}
