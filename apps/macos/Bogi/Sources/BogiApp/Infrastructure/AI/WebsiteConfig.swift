import Foundation

/// Marketing/billing site. Subscriptions are created and managed on the web (website-first);
/// the app only ever opens these URLs in the browser.
enum WebsiteConfig {
    static let pricingURL = URL(string: "https://heytogi.com/pricing")!
    static let accountURL = URL(string: "https://heytogi.com/account")!
}
