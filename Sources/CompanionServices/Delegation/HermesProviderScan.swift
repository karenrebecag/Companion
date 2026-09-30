import Foundation

/// Which inference providers the user's hermes CLI already has configured,
/// read from hermes's OWN model-picker cache. This is runtime DETECTION of
/// an optional CLI's capabilities — the same family as probing ~/.local/bin
/// for the binary — not config coupling: the product never writes here and
/// behaves identically when the file is missing (ADR 001). The path lives in
/// this one adapter only.
public enum HermesProviderScan {
    public static func providers(
        reading: () -> Data? = {
            let url = URL(fileURLWithPath:
                NSHomeDirectory() + "/.hermes/provider_models_cache.json")
            do {
                return try Data(contentsOf: url)
            } catch {
                return nil
            }
        }
    ) -> [String] {
        guard let data = reading() else { return [] }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            return []
        }
        guard let byProvider = parsed as? [String: Any] else { return [] }
        return byProvider.keys.sorted()
    }
}
