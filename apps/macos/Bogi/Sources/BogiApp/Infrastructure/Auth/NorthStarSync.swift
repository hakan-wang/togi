import Foundation

/// Mirrors the North Star to Supabase over PostgREST, directly and RLS-scoped to the signed-in user
/// (the same raw-URLSession approach `SupabaseAuth` uses, NOT through the AWS proxy). It carries only
/// the user's stated goal text, never capture data. Best-effort: every call quietly no-ops when the
/// user is signed out, offline, or the table is unavailable, so the app stays fully local-first.
final class NorthStarSync {
    struct Remote: Decodable {
        let id: String
        let text: String
        let why: String?
    }

    private let baseURL: URL
    private let anonKey: String
    private let tokenProvider: () async -> String?
    private let session: URLSession

    init(baseURL: URL = SupabaseConfig.url,
         anonKey: String = SupabaseConfig.anonKey,
         tokenProvider: @escaping () async -> String?,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.tokenProvider = tokenProvider
        self.session = session
    }

    private func request(_ path: String, method: String) async -> URLRequest? {
        guard let token = await tokenProvider(),
              let url = URL(string: baseURL.absoluteString + path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    /// The user's North Star row, or nil if none exists / signed out / unreachable.
    func fetch() async -> Remote? {
        guard let req = await request("/rest/v1/north_star?select=id,text,why", method: "GET") else { return nil }
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([Remote].self, from: data) else { return nil }
        return rows.first
    }

    /// Insert or update the user's North Star (one row per user). Returns the stored row, or nil on
    /// failure. `user_id` defaults to auth.uid() server-side, so the client never sends it.
    @discardableResult
    func upsert(text: String, why: String?) async -> Remote? {
        guard var req = await request("/rest/v1/north_star?on_conflict=user_id", method: "POST") else { return nil }
        req.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        var body: [String: Any] = ["text": text]
        body["why"] = why ?? NSNull()
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([Remote].self, from: data) else { return nil }
        return rows.first
    }
}
