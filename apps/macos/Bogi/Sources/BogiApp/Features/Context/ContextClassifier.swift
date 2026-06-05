struct ContextClassifier {
    func classify(activeApp: String, text: String) -> ContextClassification {
        let app = activeApp.lowercased()
        let content = text.lowercased()

        if app.contains("final cut") || content.contains("timeline") || content.contains("export") {
            return ContextClassification(category: "video_editing", confidence: 0.82)
        }

        if app.contains("calendar") {
            return ContextClassification(category: "planning", confidence: 0.72)
        }

        return ContextClassification(category: "unknown", confidence: 0.25)
    }
}
