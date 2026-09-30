import Foundation

/// Resuelve la ruta real de un CLI opcional (claude, hermes).
/// Una app GUI no hereda el PATH del shell, así que ni `which` ni una ruta
/// fija sirven: se consulta el sistema de archivos en los lugares donde los
/// instaladores dejan estos binarios, en orden de preferencia.
public struct CLIBinaryLocator: Sendable {
    private let home: String
    private let isExecutable: @Sendable (String) -> Bool

    public init(
        home: String = NSHomeDirectory(),
        isExecutable: @escaping @Sendable (String) -> Bool = { path in
            FileManager.default.isExecutableFile(atPath: path)
        }
    ) {
        self.home = home
        self.isExecutable = isExecutable
    }

    /// Primera ruta ejecutable entre las candidatas; nil si no está instalado.
    public func locate(_ name: String) -> String? {
        let candidates = [
            home + "/.local/bin/" + name,
            "/usr/local/bin/" + name,
            "/opt/homebrew/bin/" + name,
        ]
        return candidates.first(where: isExecutable)
    }
}
