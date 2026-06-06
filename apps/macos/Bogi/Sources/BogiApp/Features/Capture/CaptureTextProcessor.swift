import Foundation

/// Pure, AppKit-free core that turns a raw accessibility read into the canonical
/// fields persisted on an `ActivityObservation`: cleaned + truncated text, a
/// deterministic content hash, and the diff decision (skip persisting when the
/// content is unchanged since the last snapshot).
///
/// Kept free of AppKit/AX so it is directly unit-testable. The capture service
/// supplies the raw text; this type owns "what counts as a meaningful delta".
struct CaptureTextProcessor {
    /// Hard cap on stored verbatim text (characters). Keeps rows small and bounds
    /// how much raw text ever lands on disk.
    let maxLength: Int

    init(maxLength: Int = 4_000) {
        self.maxLength = max(1, maxLength)
    }

    /// Collapses runs of whitespace/newlines into single spaces and trims. This
    /// normalization is what the hash is computed over, so cosmetic reflowing of
    /// the same content does not register as a change.
    func clean(_ raw: String) -> String {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Truncates to `maxLength` on a Character boundary (so multi-byte glyphs are
    /// never split).
    func truncate(_ text: String) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength))
    }

    /// Deterministic 64-bit FNV-1a hash over the bytes, rendered as zero-padded
    /// hex. Unlike Swift's `Hasher` this is stable across launches, which is
    /// required for diffing against a previously persisted snapshot.
    func hash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01b3
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(format: "%016llx", hash)
    }

    /// Full pipeline: clean → truncate → hash. Returns the canonical text and its
    /// hash. A whitespace-only / empty read yields nil so the caller skips it.
    func process(_ raw: String) -> (text: String, hash: String)? {
        let cleaned = truncate(clean(raw))
        guard !cleaned.isEmpty else { return nil }
        return (cleaned, hash(cleaned))
    }

    /// The diff decision: persist only when the new content hash differs from the
    /// last persisted one. A nil previous hash (first capture) always persists.
    func shouldPersist(newHash: String, previousHash: String?) -> Bool {
        newHash != previousHash
    }
}
