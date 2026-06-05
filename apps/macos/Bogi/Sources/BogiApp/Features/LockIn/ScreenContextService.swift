import Foundation
import ScreenCaptureKit

struct ScreenContextPolicy: Equatable {
    let screenRecordingPermission: PermissionState
    let isLockInActive: Bool
    let isExplicitContextCommand: Bool

    var canUseOCRFallback: Bool {
        screenRecordingPermission.isUsable && (isLockInActive || isExplicitContextCommand)
    }
}

final class ScreenContextService {
    func captureCurrentDisplayForOCR(policy: ScreenContextPolicy) async throws -> Data? {
        guard policy.canUseOCRFallback else { return nil }
        return nil
    }
}
