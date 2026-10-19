import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Values are copied out of the utterance between two tokens; the copy must be
// byte-exact, accents and emoji included.

@Test func sourceTokensCopyTheExactOriginalText() {
    let said = "escribe «hola, ¿qué tal?» 👋 en foo.com a las 10:30."
    let tokens = SourceTokens.tokens(said)
    let texts = tokens.map(\.text)
    expectEq(texts, ["escribe", "«", "hola", ",", "¿", "qué", "tal", "?", "»", "👋", "en",
                     "foo.com", "a", "las", "10:30", "."], "tokens: words, marks and in-word dots")
    expectEq(tokens.map(\.id).prefix(3), ["t0", "t1", "t2"], "tokens: positional ids")
    let first = tokens[2], last = tokens[7]
    expectEq(SourceTokens.copy(said, from: first, through: last), "hola, ¿qué tal?",
             "copy: the original span, spacing and accents kept")
    expectEq(SourceTokens.copy(said, from: tokens[9], through: tokens[11]), "👋 en foo.com",
             "copy: UTF-16 offsets survive an emoji")
    expect(SourceTokens.copy(said, from: last, through: first) == nil, "copy: reversed is nil")
    expect(SourceTokens.tokens("   ").isEmpty, "tokens: blank has none")
}
