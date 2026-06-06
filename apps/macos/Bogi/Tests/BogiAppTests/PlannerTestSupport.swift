import Foundation
@testable import BogiApp

// Shared test doubles for the Planner / Calendar / Voice modules.

/// In-memory `CalendarSource` that records mutations so tests can assert that
/// Bogi never deletes user events and that pushes/reconciliation behave.
final class MockCalendarSource: CalendarSource {
    let provider: CalendarProvider
    var events: [ExternalCalendarEvent]
    var accessGranted: Bool

    private(set) var removedIds: [String] = []
    private(set) var createdDrafts: [CalendarEventDraft] = []
    private(set) var updatedDrafts: [(externalId: String, draft: CalendarEventDraft)] = []
    /// When set, `removeBogiEvent` throws this (e.g. to simulate a user event).
    var removeError: CalendarSourceError?

    init(provider: CalendarProvider = .apple, events: [ExternalCalendarEvent] = [], accessGranted: Bool = true) {
        self.provider = provider
        self.events = events
        self.accessGranted = accessGranted
    }

    func requestAccess() async throws -> Bool { accessGranted }

    func fetchEvents(from: Date, to: Date) async throws -> [ExternalCalendarEvent] {
        events.filter { $0.startAt < to && $0.endAt > from }
    }

    func createBogiEvent(_ draft: CalendarEventDraft) async throws -> ExternalCalendarEvent {
        createdDrafts.append(draft)
        let event = ExternalCalendarEvent(
            externalId: "ext-\(draft.bogiBlockId)",
            provider: provider,
            title: draft.title,
            startAt: draft.startAt,
            endAt: draft.endAt,
            isBogiCreated: true,
            bogiBlockId: draft.bogiBlockId,
            lastModified: Date()
        )
        events.append(event)
        return event
    }

    func updateBogiEvent(externalId: String, with draft: CalendarEventDraft) async throws -> ExternalCalendarEvent {
        updatedDrafts.append((externalId, draft))
        let event = ExternalCalendarEvent(
            externalId: externalId,
            provider: provider,
            title: draft.title,
            startAt: draft.startAt,
            endAt: draft.endAt,
            isBogiCreated: true,
            bogiBlockId: draft.bogiBlockId,
            lastModified: Date()
        )
        return event
    }

    func removeBogiEvent(externalId: String) async throws {
        if let removeError { throw removeError }
        removedIds.append(externalId)
        events.removeAll { $0.externalId == externalId }
    }
}

/// In-memory `TokenStore` for OAuth token tests (no Keychain).
final class InMemoryTokenStore: TokenStore {
    private var tokens: [String: OAuthToken] = [:]

    func load(account: String) throws -> OAuthToken? { tokens[account] }
    func save(_ token: OAuthToken, account: String) throws { tokens[account] = token }
    func delete(account: String) throws { tokens[account] = nil }
}

/// Records the last request and returns a canned response / error.
final class MockInferenceClient: InferenceClient {
    var response: InferenceResponse
    var error: Error?
    private(set) var lastRequest: InferenceRequest?

    init(response: InferenceResponse = InferenceResponse(text: "{}")) {
        self.response = response
    }

    func infer(_ request: InferenceRequest) async throws -> InferenceResponse {
        lastRequest = request
        if let error { throw error }
        return response
    }
}

/// Trivial transcriber returning a fixed transcript.
struct StubTranscriber: Transcribing {
    var transcript: String
    func transcribe(_ audio: Data) async throws -> String { transcript }
}

enum TestClock {
    static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Build a deterministic UTC date from components.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return utcCalendar.date(from: comps)!
    }

    /// A fixed reference instant: 2026-06-06 12:00 UTC (a Saturday).
    static let reference = date(2026, 6, 6, 12, 0)
}
