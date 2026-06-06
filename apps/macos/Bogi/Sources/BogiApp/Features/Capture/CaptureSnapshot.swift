import Foundation
import CryptoKit

/// A single point-in-time read of what's on screen (text-only, via accessibility).
struct CaptureSnapshot {
    let activeApp: String?
    let bundleId: String?
    let windowTitle: String?
    let text: String?
    let hasSecureField: Bool
    let focused: Bool
    let contentHash: String

    init(activeApp: String?, bundleId: String?, windowTitle: String?, text: String?,
         hasSecureField: Bool, focused: Bool = true) {
        self.activeApp = activeApp
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.text = text
        self.hasSecureField = hasSecureField
        self.focused = focused
        let basis = "\(bundleId ?? "")|\(windowTitle ?? "")|\(text ?? "")"
        let digest = SHA256.hash(data: Data(basis.utf8))
        self.contentHash = digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Anything that can report capture permission + produce snapshots. Lets tests inject fakes.
protocol SnapshotProviding {
    func permissionState() -> PermissionState
    func snapshot() -> CaptureSnapshot?
    func requestPermission()
}

extension SnapshotProviding {
    func requestPermission() {}
}
