# Wave 2 — Chat vertical

**Estado: APROBADO / EN CURSO** — Karen 2026-08-20 ("vamos con el
siguiente wave"). Kickoff planner + architect contra Wave 1 cerrado.

## Objetivo

Abrir la app, pegar una API key de OpenAI, chatear por texto con
streaming, reabrir y ver el historial. Producto usable solo con esa
key. Groq/Ollama son fallbacks opcionales (Groq sin UI de key esta
wave; Ollama si el probe lo ve).

## Desviaciones vs BORRADOR

1. Puertos viven en Core (`ChatPorts.swift`). Wave 1 no los dejo.
2. `ChatDelta` = `.text` / `.handoff`. `spokePartial` es politica del
   router, no un caso del enum. Finish feliz cierra el stream; la ruta
   muerta tira `ChatError`.
3. `ChatProvider.verify(_:provider:)` = `GET /models` (no un chat
   facturable). Onboarding **bloquea** hasta 200; 401 y red no entran.
4. `SecretStore.delete` entra (upsert cubre cambiar clave; Wave 5 lo
   usara). `CapabilityProbe` esta wave = HTTP Ollama; PATH es Wave 4.
5. `ConversationStoring` + records en Core; Codable+disco en Services.
   UI no importa Services.
6. Se **manda** `tools: [.delegate]`. UI pinta prefacio + linea de
   estado; no corre Executor (Wave 4).
7. `ChatProviderClient` se parte (transport / attempt / router) para
   no cruzar 400 lineas.
8. Restaurar la conversacion mas reciente al abrir (done-def).
9. `CompanionTests` enlaza CompanionServices + CompanionUI.
10. Ping / onboarding solo OpenAI. `try?` prohibido; original ChatStore
    se reescribe.

## Archivos

### CompanionCore
| Archivo | Contenido |
|---|---|
| `ChatPorts.swift` | `ChatDelta`, `ChatError`, `SecretStore`, `ChatProvider`, `CapabilityProbe`, `ConversationStoring`, records |
| `ChatPrompt.swift` | system prompt parametrizado (`ownerFirstName`, `delegateEnabled`) |

### CompanionServices
| Archivo | Contenido |
|---|---|
| `KeychainSecretStore.swift` | service `"Companion"`, account = `SecretKey.rawValue` |
| `ChatTransport.swift` | protocol + `URLSessionChatTransport` |
| `ChatSSEAttempt.swift` | un proveedor: body, SSE, timeouts, spokePartial |
| `ChatProviderClient.swift` | ruta OpenAI→Groq→Ollama, skip sin key, probe, verify |
| `LiveCapabilityProbe.swift` | Ollama GET /models 1s; remotos siempre true |
| `ConversationStore.swift` | JSON iso8601, cap 30, prune, dir inyectado |
| `Log.swift` | archivo; nunca print; nunca loguear la key |

### CompanionUI
Onboarding, Thread, Markdown basico (splitter Wave 1; cards Wave 5),
`ChatViewModel` `@Observable`, `Tokens` (UN sistema de color),
`ChatCopy` en espanol.

### CompanionApp
`@main` composicion: adapters, ventana 560x840, `ownerFirstName` desde
`NSFullUserName` **aqui**.

## API congelada (resumen)

```swift
public enum ChatDelta: Sendable, Equatable {
    case text(String)
    case handoff(Handoff)
}
public protocol ChatProvider: Sendable {
    func stream(_ history: [Turn], tools: [ToolSpec]) -> AsyncThrowingStream<ChatDelta, Error>
    func verify(_ key: String, provider: ProviderDescriptor) async throws
}
public protocol SecretStore: Sendable {
    func read(_ key: SecretKey) throws -> String?
    func write(_ key: SecretKey, value: String) throws
    func delete(_ key: SecretKey) throws
}
public protocol CapabilityProbe: Sendable {
    func isAvailable(_ provider: ProviderDescriptor) async -> Bool
}
```

Router: `ProviderDescriptor.route`; skip si falta key; skip si probe
false; inactividad `ChatSettings.inactivityTimeout` entre lineas SSE;
tope `turnTimeout` por intento; `spokePartial` = `takeSentence` ya
corto; Handoff.parse nil → texto, no delega. Sin semaforo, sin
`generation`, sin `try?`.

Keychain: generic password, no iCloud, AfterFirstUnlockThisDeviceOnly.

## Tests

Fixtures SSE, sin red. Failover, spokePartial, verify 401/200,
ConversationStore roundtrip + attachments ausentes, ViewModel cola
durante busy + error visible. Keychain real no corre en el harness
(InMemory).

## Construccion

- 0 orquestador: Package.swift + `runAsync` en TestKit.
- 1 Core ports. 2 paralelo: Keychain+Log | Store | Probe.
- 3 ChatProviderClient. 4 ViewModel+Tokens. 5 vistas. 6 App.

## Restricciones

Sin voz, sin Executor, sin settings, sin dotenv, sin `~/.hermes`.
Solo OpenAI obligatorio.

## Definicion de done

`swift run companion` → onboarding → chat streaming → reabrir y ver
historial. Gates verdes. Changelog + roadmap.

## Riesgos

- Keychain + `swift run` sin firma puede re-pedir acceso (Wave 5).
- SwiftUI + stream largo: medir antes de optimizar.
