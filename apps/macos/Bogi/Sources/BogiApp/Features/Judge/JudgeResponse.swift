import Foundation

/// Decoded judge output: the segments the model carved the window into, plus an
/// optional nudge decision. Mirrors the plan's "Expected output" shape.
struct JudgeResult: Codable, Equatable {
    var segments: [JudgeSegment]
    var nudge: JudgeNudge?
}

/// One judged time segment, labeled `category → sub_category → sub_sub`.
struct JudgeSegment: Codable, Equatable {
    var startAt: String?
    var endAt: String?
    var minutes: Double
    var category: String?
    var subCategory: String?
    var subSub: String?
    var onTask: Bool?
    var confidence: Double?

    enum CodingKeys: String, CodingKey {
        case minutes, category, confidence
        case startAt = "start_at"
        case endAt = "end_at"
        case subCategory = "sub_category"
        case subSub = "sub_sub"
        case onTask = "on_task"
    }
}

/// The judge's nudge decision. `should` is false when the user is on-task or has
/// no plan; severity escalates the mascot's presentation.
struct JudgeNudge: Codable, Equatable {
    var should: Bool
    var severity: Int?
    var message: String?
}

enum JudgeParseError: Error, Equatable {
    /// No `{ … }` object could be located in the model's text.
    case noJSONObject
    /// A JSON object was found but failed to decode into `JudgeResult`.
    case decoding
}

/// Strict, tolerant parser for the judge's JSON output.
///
/// Models frequently wrap JSON in prose ("Here is the result:") or fenced code
/// blocks (```json … ```), and may emit stray braces in the surrounding text.
/// This parser scans for every balanced top-level `{ … }` object — correctly
/// skipping braces inside string literals — and returns the first one that
/// decodes into `JudgeResult`, so the rest of the pipeline never has to care how
/// the model framed its answer.
enum JudgeResponseParser {
    static func parse(_ raw: String) throws -> JudgeResult {
        let candidates = extractJSONObjects(from: raw)
        guard !candidates.isEmpty else { throw JudgeParseError.noJSONObject }

        let decoder = JSONDecoder()
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let result = try? decoder.decode(JudgeResult.self, from: data) {
                return result
            }
        }
        throw JudgeParseError.decoding
    }

    /// Returns the first balanced top-level JSON object, or nil. Convenience over
    /// `extractJSONObjects`.
    static func extractJSONObject(from raw: String) -> String? {
        extractJSONObjects(from: raw).first
    }

    /// Returns every balanced top-level `{ … }` substring, in source order. Brace
    /// depth tracking ignores `{`/`}` inside string literals and honors backslash
    /// escapes so braces inside a `"message"` string don't confuse it. Nested
    /// objects are part of their enclosing top-level object, not separate entries.
    static func extractJSONObjects(from raw: String) -> [String] {
        let scalars = Array(raw)
        var objects: [String] = []

        var index = 0
        while index < scalars.count {
            guard scalars[index] == "{" else { index += 1; continue }

            let start = index
            var depth = 0
            var inString = false
            var escaped = false
            var closed = false

            while index < scalars.count {
                let character = scalars[index]
                if inString {
                    if escaped {
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == "\"" {
                        inString = false
                    }
                } else {
                    switch character {
                    case "\"":
                        inString = true
                    case "{":
                        depth += 1
                    case "}":
                        depth -= 1
                        if depth == 0 {
                            objects.append(String(scalars[start...index]))
                            closed = true
                        }
                    default:
                        break
                    }
                }
                index += 1
                if closed { break }
            }

            if !closed { break } // unbalanced trailing `{` — stop scanning.
        }
        return objects
    }
}
