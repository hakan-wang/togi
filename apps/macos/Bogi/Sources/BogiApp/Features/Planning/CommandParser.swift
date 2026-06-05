struct CommandParser {
    func parse(_ input: String) -> BogiCommand {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        if lowercased.hasPrefix("reality log:") {
            let text = String(trimmed.dropFirst("Reality log:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .saveRealityLog(text: text)
        }

        if lowercased == "start lock in" || lowercased == "start lock-in" {
            return .startLockIn
        }

        return .unknown(raw: input)
    }
}
