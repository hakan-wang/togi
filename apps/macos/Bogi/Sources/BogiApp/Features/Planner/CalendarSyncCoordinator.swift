import Foundation
import AuthenticationServices

/// Connects Google Calendar and periodically reconciles events into `planned_blocks` so the
/// judge has real intent to compare reality against. Google only (Apple deferred). Calendar
/// data flows Mac → Google directly; tokens stay in the Keychain.
@MainActor
final class CalendarSyncCoordinator: ObservableObject {
    @Published private(set) var googleConnected: Bool
    @Published private(set) var lastSync: Date?
    @Published var lastError: String?

    private let google: GoogleCalendarService
    private let planner: PlannerService
    private let settings: SettingsStore
    private let syncWindowDays = 7
    private var timer: DispatchSourceTimer?

    init(google: GoogleCalendarService, planner: PlannerService, settings: SettingsStore) {
        self.google = google
        self.planner = planner
        self.settings = settings
        self.googleConnected = settings.bool("google_connected", default: false)
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 5, repeating: 900) // first sync ~5s after launch, then every 15 min
        t.setEventHandler { [weak self] in Task { await self?.syncNow() } }
        t.resume()
        timer = t
    }

    func connectGoogle(anchor: ASPresentationAnchor) async {
        lastError = nil
        do {
            try await google.authorize(clientId: GoogleConfig.clientID, presentationAnchor: anchor)
            googleConnected = true
            settings.setBool("google_connected", true)
            await syncNow()
        } catch {
            googleConnected = false
            lastError = "Google sign-in failed: \(error.localizedDescription)"
        }
    }

    func disconnectGoogle() {
        google.signOut()
        googleConnected = false
        settings.setBool("google_connected", false)
    }

    func syncNow() async {
        guard googleConnected else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: syncWindowDays, to: start)
            ?? start.addingTimeInterval(Double(syncWindowDays) * 86_400)
        do {
            let events = try await google.fetchEvents(start: start, end: end, clientId: GoogleConfig.clientID)
            planner.reconcileExternal(events)
            lastSync = Date()
            lastError = nil
        } catch {
            lastError = "Calendar sync failed: \(error.localizedDescription)"
        }
    }
}
