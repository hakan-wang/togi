enum CalendarAuthorizationState: Equatable {
    case unknown
    case authorized
    case denied

    var requiresUserAction: Bool {
        switch self {
        case .denied:
            return true
        case .unknown, .authorized:
            return false
        }
    }
}
