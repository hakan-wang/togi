import Foundation

/// Where the Mac app reaches the Bogi backend (API Gateway → Lambda → Bedrock).
/// Function URLs are blocked by the AWS org SCP, so this is an API Gateway endpoint.
enum BackendConfig {
    static let baseURL = URL(string: "https://e7fsq18rqf.execute-api.eu-west-1.amazonaws.com")!
}

/// Google OAuth installed-app flow (Desktop client type, PKCE). Google issues a client_secret for
/// Desktop clients; per RFC 8252 it is NOT confidential for a public native client — it ships in
/// the app and PKCE is the real security boundary. Tokens live only in the macOS Keychain; calendar
/// data goes straight to Google, never to the Bogi backend.
///
/// This is a Google **Desktop** OAuth client. Authorization uses the supported 127.0.0.1 loopback
/// redirect flow (see `LoopbackOAuthListener`); custom URI schemes are no longer accepted by Google.
/// No redirect URI needs to be registered in the Console — Desktop clients accept any loopback port.
enum GoogleConfig {
    static let clientID = "217551213798-j2hjo7ghkgd2t3mh10o5haf8hqqgbokb.apps.googleusercontent.com"
    /// Desktop OAuth client secret (copy from the Google Cloud Console Desktop client). Non-confidential.
    static let clientSecret = "REMOVED_GOOGLE_OAUTH_SECRET"
}

/// Supabase project (auth only — no user data). The anon key is public by design.
enum SupabaseConfig {
    static let url = URL(string: "https://qpbmrmmnojpqwcaxmqww.supabase.co")!
    static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
        "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFwYm1ybW1ub2pwcXdjYXhtcXd3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2ODE0MDMsImV4cCI6MjA5NjI1NzQwM30." +
        "t3e_XkiwZo4IlBaCFBe_88F9NgxI5tesDYz7LTLbLAs"
}
