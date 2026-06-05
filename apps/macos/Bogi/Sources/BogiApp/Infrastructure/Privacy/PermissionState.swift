enum PermissionState: Equatable {
    case unknown
    case granted
    case denied

    var isUsable: Bool {
        self == .granted
    }
}
