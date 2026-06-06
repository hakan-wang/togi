import Foundation
import Combine
import GRDB

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Decoded `GET /v1/account/status` payload.
struct AccountStatus: Codable, Equatable {
    var paid: Bool
    var plan: String
}

enum AccountStatusError: Error, Equatable {
    case notAuthenticated
    case http(status: Int)
    case decoding
    case transport
}

/// Seam for fetching paid status, so `AccountGate` can be tested without a
/// network. The live implementation is `AccountStatusClient`.
protocol AccountStatusChecking {
    func fetchStatus(accessToken: String) async throws -> AccountStatus
}

/// Live `AccountStatusChecking` calling `GET /v1/account/status` with the JWT.
/// 401 maps to `.notAuthenticated`; non-2xx to `.http`; decode failure to
/// `.decoding`. Mirrors `InferenceClientLive`'s mapping conventions.
final class AccountStatusClient: AccountStatusChecking {
    private let config: BackendConfig
    private let transport: HTTPTransport
    private let decoder: JSONDecoder

    init(config: BackendConfig, transport: HTTPTransport = URLSession.shared) {
        self.config = config
        self.transport = transport
        self.decoder = JSONDecoder()
    }

    func fetchStatus(accessToken: String) async throws -> AccountStatus {
        var request = URLRequest(url: config.accountStatusURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw AccountStatusError.transport
        }

        guard let http = response as? HTTPURLResponse else {
            throw AccountStatusError.decoding
        }

        switch http.statusCode {
        case 200...299:
            do {
                return try decoder.decode(AccountStatus.self, from: data)
            } catch {
                throw AccountStatusError.decoding
            }
        case 401:
            throw AccountStatusError.notAuthenticated
        default:
            throw AccountStatusError.http(status: http.statusCode)
        }
    }
}

/// What the UI should present. Derived purely from session + paid status.
enum GateState: Equatable {
    /// Still resolving the persisted session / first status check.
    case checking
    /// No session — show `LoginView`.
    case needsLogin
    /// Signed in but unpaid — show `PaywallView`.
    case needsPayment
    /// Signed in and paid — show the app.
    case allowed
}

/// Gates the app behind a signed-in, paid account. On launch it requires a
/// session and calls `GET /v1/account/status`, caching `paid`/`plan` into the
/// `account` table; it re-checks on launch and periodically. If a status check
/// fails (offline) it falls back to the cached value so a paid user isn't locked
/// out by a transient network blip.
@MainActor
final class AccountGate: ObservableObject {
    @Published private(set) var gateState: GateState = .checking

    /// True only when signed in AND confirmed paid.
    var isPaid: Bool { gateState == .allowed }

    private let auth: AuthProviding
    private let statusChecker: AccountStatusChecking
    private let database: DatabaseService
    private let refreshInterval: TimeInterval

    private var authCancellable: AnyCancellable?
    private var refreshTask: Task<Void, Never>?

    init(
        auth: AuthProviding,
        statusChecker: AccountStatusChecking,
        database: DatabaseService,
        refreshInterval: TimeInterval = 60 * 60
    ) {
        self.auth = auth
        self.statusChecker = statusChecker
        self.database = database
        self.refreshInterval = refreshInterval
    }

    deinit {
        refreshTask?.cancel()
    }

    // MARK: Pure decision logic (unit-tested)

    /// The core gate decision: block when there is no session or the account is
    /// not paid. Kept pure (no I/O) so it can be exhaustively unit-tested.
    static func shouldBlock(session: AuthSession?, paid: Bool) -> Bool {
        session == nil || !paid
    }

    /// Maps session + paid status onto the concrete screen to present.
    static func gateState(session: AuthSession?, paid: Bool) -> GateState {
        guard session != nil else { return .needsLogin }
        return paid ? .allowed : .needsPayment
    }

    // MARK: Lifecycle

    /// Begin observing auth changes and kick off the periodic re-check. Call once
    /// after the environment is built.
    func start() {
        authCancellable = auth.statePublisher
            .receive(on: RunLoop.main)
            .sink { _ in
                Task { [weak self] in await self?.refresh() }
            }
        startPeriodicRefresh()
    }

    /// Re-evaluate the gate: require a session, fetch live paid status, cache it,
    /// and publish the resulting `GateState`.
    func refresh() async {
        guard let session = auth.state.session else {
            gateState = .needsLogin
            return
        }

        guard let token = await auth.accessToken() else {
            gateState = .needsLogin
            return
        }

        do {
            let status = try await statusChecker.fetchStatus(accessToken: token)
            cache(userId: session.userId, status: status)
            gateState = Self.gateState(session: session, paid: status.paid)
        } catch AccountStatusError.notAuthenticated {
            gateState = .needsLogin
        } catch {
            // Network/transport error: fall back to the last cached decision so a
            // paid user keeps working offline.
            let cachedPaid = cachedPaidStatus(userId: session.userId)
            gateState = Self.gateState(session: session, paid: cachedPaid)
        }
    }

    private func startPeriodicRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.refreshInterval * 1_000_000_000))
                if Task.isCancelled { break }
                await self.refresh()
            }
        }
    }

    // MARK: Caching

    private func cache(userId: String, status: AccountStatus) {
        try? database.dbQueue.write { db in
            var record = AccountRecord(
                supabaseUserId: userId,
                paid: status.paid,
                plan: status.plan,
                checkedAt: Date()
            )
            try record.save(db)
        }
    }

    private func cachedPaidStatus(userId: String) -> Bool {
        let record = try? database.dbQueue.read { db in
            try AccountRecord.fetchOne(db, key: userId)
        }
        return record??.paid ?? false
    }
}
