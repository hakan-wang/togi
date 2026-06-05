enum PrivacyAction: Equatable {
    case exportData
    case deleteLocalData
    case deleteCloudData

    var requiresConfirmation: Bool {
        switch self {
        case .exportData:
            return false
        case .deleteLocalData, .deleteCloudData:
            return true
        }
    }
}
