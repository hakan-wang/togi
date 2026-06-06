import Foundation
import AppKit

/// Adapts `GoogleCalendarService` to the planner's `PlannedBlockCalendarWriter` so Bogi-created
/// blocks are mirrored to the user's Google primary calendar. All calls fail soft (return nil/false)
/// when Google isn't connected, leaving the block local-only.
struct GoogleCalendarWriter: PlannedBlockCalendarWriter {
    let service: GoogleCalendarService
    let clientId: String
    let clientSecret: String

    func createEvent(for block: PlannedBlock) async -> (calendarId: String, externalEventId: String)? {
        do {
            let eventId = try await service.createEvent(
                title: block.title, start: block.startAt, end: block.endAt,
                clientId: clientId, clientSecret: clientSecret)
            return (GoogleCalendarService.writeCalendarId, eventId)
        } catch {
            return nil
        }
    }

    func updateEvent(for block: PlannedBlock) async -> Bool {
        guard let calendarId = block.calendarId, let eventId = block.externalEventId else { return false }
        do {
            try await service.updateEvent(
                calendarId: calendarId, eventId: eventId,
                title: block.title, start: block.startAt, end: block.endAt,
                clientId: clientId, clientSecret: clientSecret)
            return true
        } catch {
            return false
        }
    }
}

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

    func connectGoogle() async {
        lastError = nil
        // The loopback OAuth flow opens the user's default browser, so the menu-bar (accessory)
        // app doesn't need to present its own web-auth sheet. Bring Bogi forward afterwards.
        do {
            try await google.authorize(clientId: GoogleConfig.clientID, clientSecret: GoogleConfig.clientSecret)
            NSApp.activate(ignoringOtherApps: true)
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
            let events = try await google.fetchEvents(start: start, end: end, clientId: GoogleConfig.clientID, clientSecret: GoogleConfig.clientSecret)
            planner.reconcileExternal(events)
            lastSync = Date()
            lastError = nil
        } catch {
            lastError = "Calendar sync failed: \(error.localizedDescription)"
        }
    }
}
