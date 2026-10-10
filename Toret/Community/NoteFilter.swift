import Foundation

/// What the note field refuses.
///
/// A public note is user-generated content, and the store expects it to be
/// filtered before it is posted. This is deliberately small: the words that
/// should never reach another person, and anything that turns a note about
/// water into an advertisement or a way to reach the author. Everything subtler
/// is for the people reading it to report.
enum NoteFilter {
    enum Verdict: Equatable, Sendable {
        case ok
        /// Slurs and explicit language.
        case objectionable
        /// A link, an address or a phone number.
        case containsContact
    }

    static func check(_ note: String) -> Verdict {
        if containsContact(note) { return .containsContact }
        let tokens = normalised(note)
            .split { !$0.isLetter }
            .map(String.init)
        return tokens.contains { blocked.contains($0) } ? .objectionable : .ok
    }

    /// Lowercased, unaccented, with the substitutions people use to dodge a
    /// filter (`f0da`, `p#ta`) undone.
    private static func normalised(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let map: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "@": "a", "$": "s"]
        return String(folded.map { map[$0] ?? $0 })
    }

    private static let contact = try! NSRegularExpression(
        pattern: #"(https?://|www\.|[a-z0-9-]+\.(com|net|org|it|br|io|me)\b|@[a-z0-9_.]{3,}|\+?\d[\d\s().-]{7,}\d)"#,
        options: [.caseInsensitive]
    )

    private static func containsContact(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return contact.firstMatch(in: text, range: range) != nil
    }

    /// Portuguese, Italian and English — the three languages the app speaks.
    /// Matched as whole words, so "Scunthorpe" problems cannot happen.
    private static let blocked: Set<String> = [
        "puta", "putas", "viado", "viada", "caralho", "buceta", "cuzao", "arrombado", "fdp",
        "cazzo", "puttana", "troia", "stronzo", "frocio", "negro",
        "fuck", "fucking", "bitch", "cunt", "nigger", "faggot", "whore",
    ]
}
