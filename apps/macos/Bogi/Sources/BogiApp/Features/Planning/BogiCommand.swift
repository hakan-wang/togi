enum BogiCommand: Equatable {
    case saveRealityLog(text: String)
    case startLockIn
    case unknown(raw: String)
}
