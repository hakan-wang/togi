import Foundation

/// Where the Mac app reaches the Bogi backend (API Gateway → Lambda → Bedrock).
/// Function URLs are blocked by the AWS org SCP, so this is an API Gateway endpoint.
enum BackendConfig {
    static let baseURL = URL(string: "https://e7fsq18rqf.execute-api.eu-west-1.amazonaws.com")!
}

/// Google OAuth (installed-app / iOS client type, PKCE, no secret). Tokens live only in the
/// macOS Keychain; calendar data goes straight to Google, never to the Bogi backend.
enum GoogleConfig {
    static let clientID = "217551213798-j2hjo7ghkgd2t3mh10o5haf8hqqgbokb.apps.googleusercontent.com"
    /// Reversed-client-ID custom scheme Google requires for iOS-type OAuth clients.
    static let redirectScheme = "com.googleusercontent.apps.217551213798-j2hjo7ghkgd2t3mh10o5haf8hqqgbokb"
}

/// Supabase project (auth only — no user data). The anon key is public by design.
enum SupabaseConfig {
    static let url = URL(string: "https://qpbmrmmnojpqwcaxmqww.supabase.co")!
    static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
        "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFwYm1ybW1ub2pwcXdjYXhtcXd3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2ODE0MDMsImV4cCI6MjA5NjI1NzQwM30." +
        "t3e_XkiwZo4IlBaCFBe_88F9NgxI5tesDYz7LTLbLAs"
}
