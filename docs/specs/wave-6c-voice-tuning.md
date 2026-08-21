# Wave 6c — Voz configurable y presencia sonora

**Estado: CERRADO** — 2026-08-21. Ajustes de voz en sesion, velocidad en
caliente, AEC rearmable, sonido al pensar, imagen a sesion viva.

## Objetivo

Devolver a la voz lo que el prototipo dejaba ajustar y lo que la hacia
sentirse viva. El alcance real **no es "anadir UI"**: hoy **ningun** ajuste
llega a una sesion viva. Esta tanda construye por primera vez el camino
Ajustes → Config → codec, mas velocidad en caliente, AEC re-armable y el
sonido de fondo de thinking.

## Correcciones de kickoff

- `main.swift` construye `Config(ownerFirstName:)` con **todos los defaults**.
  `VoiceProfile.stored` (Wave 5a) se escribe y no lo lee nadie.
  `ownerFirstName` sale de `NSFullUserName()` e ignora `UserProfile.ownerName`.
  Lo que falta es la frontera Config viva, no solo pantallas.
- El veto persistente de AEC **ya existe** (`UserDefaultsAECVeto` en
  `MicCapture.init`). El ledger que dice "veto in-process" esta
  desactualizado. `MicCapture` fotografia el veto en `init`, asi que borrar
  el UserDefault no basta: hace falta `rearmEchoCancellation()`.
- Sonido de fondo: observacion del snapshot en `VoiceSession.apply(_:)`, con
  funcion pura `AmbienceCue.forTransition` en Core. Cero efectos nuevos en
  el reducer, cero cambios en `TurnMachine`.
- UI de ajustes de voz necesita el Dropdown de 6b-2.
- Imagen a sesion viva (diferida desde 6a-4) entra en 6c-3, unico punto de
  la wave que ya toca la sesion.

## Alcance

Secuencia: 6c-1 (Config viva) bloquea todo. Luego 6c-2 (UI). 6c-3 velocidad
en caliente + imagen viva. 6c-4 y 6c-5 en paralelo tras 6c-1.

### 6c-1. Frontera Config viva (prerrequisito)

| Archivo | Contenido |
|---|---|
| UI `UserPreferences.swift` | `VoicePreferences.settings` con todos los campos + `StoredConfigProvider` |
| Core `Config.swift` | Puerto `ConfigProviding` |
| Services `VoiceSession.swift` | Deja de capturar `Config` en `init`; lee el provider **al abrir sesion** |
| App `main.swift` | Construye el provider desde las preferencias persistidas |

```swift
public protocol ConfigProviding: Sendable { var current: Config { get } }
```

`openRealtimeSession()` lee `configProvider.current`. El cambio se limita a
*de donde sale el Config* — nada mas dentro del arranque. Releer Audio/AEC
del ledger ANTES de escribir.

Bonus obligatorio: `Config.ownerFirstName` sale de `UserProfile.ownerName`
(`NSFullUserName()` solo como default inicial); `VoiceProfile.stored` por
fin llega al codec.

### 6c-2. UI de ajustes de voz

Seccion nueva `SettingsVoiceSection.swift` (mantiene SettingsView bajo el
warn de 400 lineas). Criterio de turno (silencio 200-1500 ms vs sentido con
avidez baja/auto/alta), velocidad y volumen con preview, tono, toggle de
AEC con texto honesto de que en algunos equipos VPIO no inicializa. Los
clamps ya viven en `VoiceSettings` y estan testeados: la UI no los
reimplementa. Cada ajuste debe alcanzar el codec (grep al cerrar, no solo
tests).

### 6c-3. Velocidad en caliente + imagen a sesion viva

```swift
extension RealtimeCodec {
    /// Sin voice ni instructions: la voz NO cambia tras el primer audio
    /// (ledger Realtime). La velocidad si.
    public static func speedUpdate(speed: Double) -> String
    public static func imageItem(dataURL: String, caption: String) -> String
}
```

La UI no toca Services: se expone por `VoiceControlling`.

### 6c-4. Re-armado del veto de AEC

```swift
extension MicCapturing { func rearmEchoCancellation() }
```

Tocar el toggle limpia `vetoStore.isVetoed` **y** la foto `vetoVoiceProcessing`
de `init`, y reintenta VPIO **una vez** en la proxima sesion. El watchdog de
silencio de mic no se toca. Tests con `InMemoryAECVeto`.

### 6c-5. Presencia sonora

| Archivo | Contenido |
|---|---|
| Core `SoundPorts.swift` | `AmbienceCue` + puerto `AmbiencePlaying` |
| Services `ThinkingSound.swift` (nuevo) | Engine **propio efimero** — jamas el compartido con el mic/AEC |
| Services `VoiceSession.swift` | Aplica la senal en `apply(_:)` |

```swift
public enum AmbienceCue: Sendable, Equatable {
    case start, stop, none
    public static func forTransition(from previous: TurnState, to next: TurnState) -> AmbienceCue
}
```

Contrato: `listening → thinking` ⇒ start; `thinking → speaking|error|idle`
⇒ stop; `thinking → thinking` ⇒ none. Volumen bajo, rampas 0.6/0.35 s
(prototipo `Ambience.swift`), acorde C4+G4+C3 sintetizado. Toggle propio
en Ajustes de voz, on por defecto. **No** se ata a reduce-motion (es audio).
Nunca por encima de la voz del agente.

## Tests

- `VoiceConfigBridgeTests`: cambiar `turnDetection` cambia el `session.update`
  de la **siguiente** sesion (fixture); `UserProfile.ownerName` llega a
  `Config.ownerFirstName` y al prompt.
- `speedUpdate` lleva `speed` y **no** lleva `voice` (ancla:
  `testRealtimeSessionUpdate`).
- Rearm: con `InMemoryAECVeto(true)`, `rearmEchoCancellation()` deja
  `isVetoed == false` y el siguiente `start()` intenta VPIO una vez.
- `AmbienceCueTests`: transiciones de arriba, reloj/motor inyectado, sin
  AVAudioEngine real.

## Definicion de done

Cambiar paciencia y criterio se refleja en la siguiente sesion (visible en
el log); la velocidad cambia en caliente; el toggle de AEC re-intenta VPIO
una vez; el silencio de thinking tiene presencia; **todo ajuste de Ajustes
llega al codec** (grep, no solo tests). Veredicto manual de Karen en su
hardware.

## Riesgos

- Tocar el arranque de sesion: releer ledger Audio/AEC ANTES. El cambio de
  6c-1 es de donde sale Config, nada mas.
- ThinkingSound comparte salida con el player: engine propio efimero, nunca
  `sharedEngine`. Robarlo con AEC activo es exactamente la clase de fallo
  que costo Wave 3.

## Desviaciones respecto al borrador original

1. Alcance real = camino Ajustes→sesion completo, no "solo UI".
2. Config via `ConfigProviding` leido al abrir sesion.
3. AEC re-arm es metodo explicito, no basta con borrar UserDefaults.
4. Ambience por observacion del snapshot, no efecto nuevo en el reducer.
5. Imagen-en-voz-viva entra aqui (desde 6a).
