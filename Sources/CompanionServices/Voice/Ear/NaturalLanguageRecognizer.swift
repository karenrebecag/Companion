import CompanionCore
import Foundation
import NaturalLanguage

/// Wave 15f-2: the system's on-device recognizer behind Core's port.
/// Constrained to the languages the app speaks: unconstrained, a short
/// Spanish sentence full of product names reads as Catalan or Portuguese
/// with enough confidence to be dropped.
package struct NaturalLanguageRecognizer: LanguageRecognizing {
    private let constrainToAppLanguages: Bool

    /// The mouth gate wants es/en only (its question is "is this the app's
    /// language"); the inspection that labels a reply must see any language,
    /// or a clear Portuguese text is forced into the nearest allowed one.
    /// The labels a reply can carry. Unconstrained, the recognizer chose
    /// Indonesian ("id") for Spanish with English terms (QA 606): the set is
    /// the languages the people reading the thread write in, so a Latin-script
    /// reply can only land on one of them.
    static let labelLanguages: [NLLanguage] = [.spanish, .english, .portuguese, .french, .italian, .german]

    package init(constrainToAppLanguages: Bool = true) {
        self.constrainToAppLanguages = constrainToAppLanguages
    }

    package func dominant(_ text: String) -> DetectedLanguage? {
        // A fresh recognizer per call: NLLanguageRecognizer is a mutable
        // class, and the mouth may be asked from more than one turn.
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = constrainToAppLanguages
            ? AppLanguage.allCases.map { NLLanguage(rawValue: $0.rawValue) }
            : Self.labelLanguages
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0
        return DetectedLanguage(code: language.rawValue, confidence: confidence)
    }
}
