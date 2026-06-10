import AppKit
import ApplicationServices

/// Reads on-screen text via the macOS Accessibility tree. No screenshots, ever.
final class AccessibilityCaptureService: SnapshotProviding {
    private let maxNodes = 500
    private let maxChars = 6000

    func permissionState() -> PermissionState {
        AXIsProcessTrusted() ? .granted : .denied
    }

    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func snapshot() -> CaptureSnapshot? {
        guard AXIsProcessTrusted() else { return nil }

        let front = NSWorkspace.shared.frontmostApplication
        let system = AXUIElementCreateSystemWide()

        var parts: [String] = []
        var hasSecure = false
        var windowTitle: String?

        if let appEl = element(system, kAXFocusedApplicationAttribute) {
            if let focused = element(appEl, kAXFocusedUIElementAttribute) {
                if string(focused, kAXRoleAttribute) == "AXSecureTextField" { hasSecure = true }
                if let v = string(focused, kAXValueAttribute) { parts.append(v) }
                if let s = string(focused, kAXSelectedTextAttribute) { parts.append(s) }
            }
            if let window = element(appEl, kAXFocusedWindowAttribute) {
                windowTitle = string(window, kAXTitleAttribute)
                var nodesLeft = maxNodes
                var charsLeft = maxChars
                collectText(window, into: &parts, nodesLeft: &nodesLeft, charsLeft: &charsLeft)
            }
        }

        let text = parts
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return CaptureSnapshot(
            activeApp: front?.localizedName,
            bundleId: front?.bundleIdentifier,
            windowTitle: windowTitle,
            text: text.isEmpty ? nil : String(text.prefix(maxChars)),
            hasSecureField: hasSecure
        )
    }

    // MARK: - AX helpers

    private func rawValue(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success ? value : nil
    }

    private func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        guard let v = rawValue(el, attr), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private func string(_ el: AXUIElement, _ attr: String) -> String? {
        guard let v = rawValue(el, attr), CFGetTypeID(v) == CFStringGetTypeID() else { return nil }
        return (v as! CFString) as String
    }

    private func children(_ el: AXUIElement) -> [AXUIElement] {
        guard let v = rawValue(el, kAXChildrenAttribute) else { return [] }
        return (v as? [AXUIElement]) ?? []
    }

    private func collectText(_ el: AXUIElement, into parts: inout [String], nodesLeft: inout Int, charsLeft: inout Int) {
        if nodesLeft <= 0 || charsLeft <= 0 { return }
        nodesLeft -= 1

        let role = string(el, kAXRoleAttribute)
        if role == "AXStaticText" || role == "AXTextField" || role == "AXTextArea" {
            if let v = string(el, kAXValueAttribute), !v.isEmpty {
                let take = String(v.prefix(charsLeft))
                parts.append(take)
                charsLeft -= take.count
            }
        }

        for child in children(el) {
            if nodesLeft <= 0 || charsLeft <= 0 { break }
            collectText(child, into: &parts, nodesLeft: &nodesLeft, charsLeft: &charsLeft)
        }
    }
}
