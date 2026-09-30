import CompanionCore
import Foundation
import NaturalLanguage

/// Wave 15f-2: the system's on-device recognizer behind Core's port.
/// Constrained to the languages the app speaks: unconstrained, a short
/// Spanish sentence full of product names reads as Catalan or Portuguese
/// with enough confidence to be dropped.
package struct NaturalLanguageRecognizer: LanguageRecognizing {
    package init() {}

    package func dominant(_ text: String) -> DetectedLanguage? {
        // A fresh recognizer per call: NLLanguageRecognizer is a mutable
        // class, and the mouth may be asked from more than one turn.
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = AppLanguage.allCases.map {
            NLLanguage(rawValue: $0.rawValue)
        }
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0
        return DetectedLanguage(code: language.rawValue, confidence: confidence)
    }
}
