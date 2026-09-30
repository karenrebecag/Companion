import Foundation

/// Acumula bytes de un pipe y entrega solo líneas completas (NDJSON).
/// Un pipe entrega bloques arbitrarios: una línea puede llegar partida en
/// varios reads o varias líneas pegadas en uno — tratarlos como líneas era
/// el bug que rompía el parser del especialista.
package struct LineBuffer: Sendable {
    private var buffer = Data()

    package init() {}

    /// Suma un bloque y devuelve las líneas que se completaron con él.
    /// Las vacías se descartan: no significan nada en NDJSON.
    package mutating func feed(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let chunk = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let line = String(data: chunk, encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }

    /// En EOF: lo que quedó sin salto final también cuenta como línea.
    package mutating func flush() -> String? {
        defer { buffer.removeAll() }
        guard !buffer.isEmpty,
              let line = String(data: buffer, encoding: .utf8),
              !line.isEmpty else { return nil }
        return line
    }
}
