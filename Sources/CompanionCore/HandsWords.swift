import Foundation

/// How the hands compare what they are about to type or send with what the
/// user said (review 2026-09-25, H1/H3). Speech arrives with its own case,
/// accents and punctuation ("Google.com", "google com"), so both sides are
/// folded to words before comparing.
public enum HandsWords {
    /// Spoken ways of asking to submit what was typed. One word is enough:
    /// "dale enter", "envíalo ya", "búscalo".
    static let sendCues: Set<String> = [
        "enter", "intro", "return", "envia", "envialo", "enviar", "envie", "manda", "mandalo",
        "mandar", "busca", "buscalo", "buscar", "send", "submit", "search",
    ]

    /// Buttons that cannot be taken back (Wave 16a): deleting, paying,
    /// sending. A label in one of these families needs a word of the same
    /// family from the user — "borra este correo" presses "Eliminar" — or
    /// the sheet. Whole words only: "Página" is not "pagar".
    /// One family per kind of act: saying "envíalo" must not authorize
    /// "Publicar" (security review 16). Spanish and English as spoken, plus
    /// the labels a page in another language shows — a finite list is
    /// defence in depth; an unlabeled control asks regardless.
    static let destructiveFamilies: [Set<String>] = [
        // delete
        ["borrar", "borra", "borralo", "borrala", "eliminar", "elimina", "eliminalo", "eliminala",
         "suprimir", "descartar", "descarta", "vaciar", "vacia", "papelera", "basura", "delete",
         "remove", "trash", "bin", "discard", "erase", "wipe", "loschen", "entfernen", "supprimer",
         "effacer", "excluir", "cancella", "rimuovi"],
        // pay
        ["pagar", "paga", "pagalo", "comprar", "compra", "compralo", "pedido", "pay", "buy",
         "purchase", "order", "checkout", "kaufen", "bezahlen", "acheter", "payer", "compre",
         "acquista"],
        // subscribe
        ["suscribirse", "suscribete", "suscribir", "subscribe", "abonnieren", "abonner", "assinar"],
        // send
        ["enviar", "envia", "envialo", "enviala", "manda", "mandalo", "mandar", "send", "submit",
         "senden", "envoyer", "invia"],
        // sign out: phrases fused into one token by `tokens`, since "cerrar",
        // "sesion" and "out" alone are ordinary words
        ["signout", "logout"],
        // publish
        ["publicar", "publica", "publicalo", "publish", "post", "veroffentlichen", "publier"],
    ]

    /// Buttons that back out: pressing them never does the harm the dialog
    /// is about.
    static let cancelWords: Set<String> = [
        "cancelar", "cancel", "no", "cerrar", "close", "conservar", "keep", "volver", "back",
        "abbrechen", "annuler", "annulla",
    ]

    public static func isCancel(_ label: String) -> Bool {
        let tokens = words(label).split(separator: " ").map(String.init)
        return !tokens.isEmpty && tokens.allSatisfy { cancelWords.contains($0) }
    }

    /// The family a button label belongs to, if any.
    public static func destructiveFamily(of label: String) -> Int? {
        let tokens = tokens(label)
        return destructiveFamilies.firstIndex { !$0.isDisjoint(with: tokens) }
    }

    public static func asks(family: Int, in said: String) -> Bool {
        let tokens = tokens(said)
        return !destructiveFamilies[family].isDisjoint(with: tokens)
    }

    public static func said(_ text: String, in said: String) -> Bool {
        let needle = words(text)
        guard !needle.isEmpty else { return false }
        return " \(words(said)) ".contains(" \(needle) ")
    }

    public static func asksToSend(_ said: String) -> Bool {
        !sendCues.isDisjoint(with: words(said).split(separator: " ").map(String.init))
    }

    /// A URL, a host, a path or a command-line flag: things that navigate or
    /// act when typed into an address bar or a prompt.
    public static func looksLikeAddress(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.contains("://") || lowered.contains("www.") { return true }
        return lowered.split(whereSeparator: \.isWhitespace).contains { token in
            if let first = token.first, "/~-".contains(first), token.count > 1 { return true }
            return token.range(of: #"^[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}(/.*)?$"#,
                               options: .regularExpression) != nil
        }
    }

    /// Control characters other than line breaks and tabs; with `format`,
    /// also invisible format characters (bidi overrides, zero-width marks)
    /// that make a command read differently from what it runs.
    public static func isControl(_ scalar: Unicode.Scalar, format: Bool) -> Bool {
        switch scalar.properties.generalCategory {
        case .control: return !["\n", "\r", "\t"].contains(scalar)
        case .format: return format
        default: return false
        }
    }

    public static func hasControl(_ text: String, format: Bool) -> Bool {
        text.unicodeScalars.contains { isControl($0, format: format) }
    }

    /// Words of a text, with the sign-out phrases fused into one token so
    /// "Cerrar ventana" or "Sesión nueva" never land in the family.
    static func tokens(_ text: String) -> Set<String> {
        let fused = words(text).replacingOccurrences(
            of: #"\b(?:(?:cerrar|cierra|cierro) (?:la )?sesion|log out|sign out)\b"#,
            with: "signout", options: .regularExpression)
        return Set(fused.split(separator: " ").map(String.init))
    }

    static func words(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let spaced = String(folded.map { $0.isLetter || $0.isNumber ? $0 : " " })
        return spaced.split(separator: " ").joined(separator: " ")
    }
}
