import Foundation

/// The judge's structured output. Decoded from the LLM's (possibly fenced) JSON reply.
/// Expected segment shape: { start_at, end_at, minutes, cat, sub, title, desc, on_task, confidence }
struct JudgeOutput: Codable {
    var segments: [JudgeSegment]
    var nudge: JudgeNudge
}

struct JudgeSegment: Codable {
    var startAt: Date
    var endAt: Date
    var minutes: Double
    var cat: String?
    var sub: String?
    var title: String?
    var desc: String?
    var onTask: Bool?
    var confidence: Double?

    enum CodingKeys: String, CodingKey {
        case startAt = "start_at"
        case endAt = "end_at"
        case minutes
        case cat
        case sub
        case title
        case desc
        case onTask = "on_task"
        case confidence
    }
}

struct JudgeNudge: Codable {
    var should: Bool
    var severity: Int
    var message: String?
}

enum JudgeParseError: Error {
    case noJSONObject
}

extension JudgeOutput {
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Tolerantly parse the model reply: strips ```json fences / leading prose by extracting
    /// the first balanced top-level `{...}` object, then JSON-decodes it. Pure + testable.
    static func parse(_ raw: String) throws -> JudgeOutput {
        guard let jsonSlice = firstBalancedObject(in: raw),
              let data = jsonSlice.data(using: .utf8) else {
            throw JudgeParseError.noJSONObject
        }
        return try decoder.decode(JudgeOutput.self, from: data)
    }

    /// Returns the substring spanning the first balanced `{ ... }`, ignoring braces that
    /// appear inside string literals (and their escapes).
    private static func firstBalancedObject(in raw: String) -> String? {
        let chars = Array(raw)
        guard let start = chars.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var escaped = false

        for i in start..<chars.count {
            let c = chars[i]
            if inString {
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    inString = false
                }
                continue
            }
            switch c {
            case "\"":
                inString = true
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(chars[start...i])
                }
            default:
                break
            }
        }
        return nil
    }
}
