enum UpdateChannel: Equatable {
    case beta
    case stable
}

struct UpdatePolicy: Equatable {
    let channel: UpdateChannel

    var canCheckForUpdates: Bool {
        switch channel {
        case .beta, .stable:
            return true
        }
    }
}
