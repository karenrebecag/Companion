# Wave 6a — Fundamentos de escritorio

**Estado: BORRADOR** — kickoff 2026-08-21 (planner + architect). Pendiente de
aprobacion de Karen.

## Objetivo

Cerrar lo que hace al rebuild frustrante frente al prototipo: menu de
aplicacion, adjuntos, avisos y actualizaciones (ADR 002). Es la tanda que
convierte "funciona" en "se siente como una app de Mac".

## Correcciones de kickoff (contra waves 1-5 reales)

- `AttachmentRef` y `Turn.attachments` existen y estan testeados, pero **nada
  los escribe**: `ChatViewModel.windowedTurns()` construye `Turn` sin
  adjuntos y `persist()` no llena `attachmentPaths`. El alcance incluye ese
  cableado (patron del ledger: logica correcta, sin camino real).
- `UISound` NO vive en CompanionUI: el gate prohibe `import AVFoundation`
  ahi. Puerto en Core, adapter en Services.
- Los tests de update del prototipo (`testUpdateCheck` / `testUpdateInstaller`)
  no se portan: prueban auto-recompilacion con `launchctl`. Bajo ADR 002 se
  escriben tests nuevos.
- Hay tres versiones que no coinciden: `Build.version` = `0.2.0-wave2` (nadie
  la lee), `bundle.sh` escribe `0.3.0`, CHANGELOG va por `0.6.0`. Unificar
  es prerrequisito del checker.
- Imagen a sesion de voz viva se **difiere a 6c-3**: no tocar VoiceSession
  dos veces en la wave.
- Long-paste collapse: **fuera**. No justifica un tercer `AttachmentKind`.

## Alcance

Orden: 6a-1 (menu) en paralelo con 6a-2 (core adjuntos), 6a-5a (avisos) y
6a-6 (updates). Luego 6a-2 → 6a-3 → 6a-4; 6a-5a → 6a-5b.

### 6a-1. Menu de la aplicacion

| Archivo | Contenido |
|---|---|
| UI `MenuPlan.swift` (nuevo) | Arbol de menu como valor puro (testeable; CompanionApp no es importable desde tests) |
| UI `Shortcuts.swift` (ampliar) | `ShortcutAction` nuevos (`newConversation`, `attach`, `history`, `settings`) y `keyEquivalent` |
| App `AppMenu.swift` (nuevo) | Construye `NSMenu` desde el plan, ancla de retencion, `rebuild()` |
| App `main.swift` | Instala el menu tras crear los ViewModels |

```swift
public enum MenuCommand: String, Sendable, Equatable { /* about…bringAllToFront */ }
public struct MenuItemPlan: Sendable, Equatable { /* title, command?, keyEquivalent, modifiers */ }
public enum MenuPlan {
    public static func build(shortcuts: ShortcutSet) -> [MenuSectionPlan]
}
```

Contratos (prototipo `AppMenu.swift:1-3, 25-30, 77-79`):

- Items de Edicion con `target = nil`: la accion viaja por la cadena de
  respondedores hasta el `NSTextView`. Sin esto el menu se ve y no hace nada.
- `cut/copy/paste/selectAll` son `x/c/v/a`+Cmd, **fijos**. Solo voz,
  adjuntar, nueva, historial y ajustes salen de `ShortcutSet`.
- Atajo invalido o apagado ⇒ `keyEquivalent = ""` y el item se conserva.
- `AppMenu` se guarda en un `static`: `NSMenu` no retiene su target.

El menu se reconstruye cuando cambian los atajos en Ajustes. Los items de
Conversacion enrutan a los ViewModels via `MenuCommand`; el menu no conoce
Services.

### 6a-2. Adjuntos — Core + store

| Archivo | Contenido |
|---|---|
| Core `Conversation.swift` | `AttachmentRef` gana `byteCount: Int` y `id: UUID`. `AttachmentKind` se queda en `{image, file}` |
| Core `AttachmentPolicy.swift` (nuevo) | Topes, extensiones, mime, `delivery(for:)`, puerto `AttachmentStoring` |
| Services `AttachmentStore.swift` (nuevo) | Adopcion (copia a Application Support), miniaturas, reescalado, descarte |

```swift
public enum AttachmentDelivery: Sendable, Equatable {
    case imageDataURL, inlineText, pathOnly
}
public protocol AttachmentStoring: Sendable {
    func adopt(_ source: URL, conversationId: String) throws -> AttachmentRef
    func adopt(imageData: Data, name: String, conversationId: String) throws -> AttachmentRef
    func restore(path: String) -> AttachmentRef?
    func discard(_ ref: AttachmentRef)
    func payload(for ref: AttachmentRef) -> AttachmentPayload?
}
```

El puerto vive en Core porque CompanionUI no puede importar Services; la App
inyecta el adapter. `try?` del prototipo se reescribe con `throws` +
`AttachmentError` (gate). Reescalar a `maxImageEdge = 1024` **en ambos
caminos** (chat y realtime) — el prototipo solo lo hacia en Realtime;
portar eso seria portar un bug. Miniaturas: el store las produce como
`Data`; la UI las pinta. Core no conoce AppKit.

### 6a-3. Serializacion multimodal

| Archivo | Contenido |
|---|---|
| Services `ChatSSEAttempt.swift` | `content` como array de partes **solo** cuando el turno lleva imagenes |
| Services `ChatProviderClient.swift` | Inyecta el resolvedor de payloads |
| Core `RealtimeCodec.swift` | `imageItem(dataURL:caption:)` — usado en 6c-3 |

Si el turno no lleva imagenes, `content` sigue siendo `String` (Groq/Ollama
no aceptan partes multimodales). Texto legible se inlinea recortado;
binario solo aporta `promptLine`.

### 6a-4. Adjuntos en la UI

| Archivo | Contenido |
|---|---|
| UI `AttachmentViews.swift` (nuevo) | Chips removibles + overlay de arrastre sobre toda la ventana; pegar imagen del portapapeles |
| UI `ChatViewModel.swift` | `pending`, `attach`, `remove`; `windowedTurns()` y `persist()` conservan adjuntos |
| UI `ThreadView.swift` | Composer con chips, `onDrop`, adjuntos en las filas |
| App `main.swift` | Inyecta `AttachmentStore` |

`ChatViewModel.init` gana `attachments: (any AttachmentStoring)?` — opcional,
como `jobSubmitter`. Al cerrar: grep de `windowedTurns()`, `attachmentPaths`
y `restore(path:)` en el flujo real.

Drag & drop: patron del prototipo (`AttachmentViews.swift`), no inventar.

### 6a-5a. Avisos efimeros

| Archivo | Contenido |
|---|---|
| Core `Notices.swift` (nuevo) | `Notice` + `NoticeQueue` (cola, expiracion 4 s, tope 3, reloj inyectado) |
| UI `Toasts.swift` (nuevo) | `NoticeCenter` (`@Observable`) + `ToastStack` |
| UI `CompanionRootView.swift` | Monta el stack arriba a la derecha |

`ToastStack` es `allowsHitTesting(false)` y nunca entra a la conversacion.

### 6a-5b. Sonido de interfaz

Bloqueado por la pregunta de assets de Karen. Default si no hay wavs:
sintesis en memoria o `NSSound` del sistema — cero binarios.

| Archivo | Contenido |
|---|---|
| Core `SoundPorts.swift` (nuevo) | `UISoundCue` + puerto `UISoundPlaying` |
| Services `UISoundPlayer.swift` (nuevo) | Adapter AVFoundation / NSSound |
| UI `Toasts.swift` | `NoticeCenter` dispara la senal al encolar |

Toggle en Ajustes, default on. **No va en CompanionUI.**

### 6a-6. Actualizaciones (ADR 002)

Prerrequisito: `Build.version` unica fuente; `bundle.sh` la lee (tocar
`bundle.sh` requiere OK explicito). SemVer con precedencia de prerelease
(`0.6.0-wave6 < 0.6.0`).

| Archivo | Contenido |
|---|---|
| Core `Version.swift` (nuevo) | `SemVer` + `ReleaseInfo.parse` (nil ante payload malformado) |
| Core `Build.swift` | Version al dia y unica |
| Services `UpdateChecker.swift` (nuevo) | GET a GitHub Releases via `ChatTransport`; cache del dia; sin red ⇒ silencio |

Sin descargas en segundo plano. Si hay version nueva: toast discreto +
entrada en Ajustes → Sistema que abre la pagina (URL filtrada por
`EndpointPolicy`). El resultado llega a UI via puerto/valor en Core, no
importando Services.

## Tests (rojo primero)

- Menu: Edicion fija `x/c/v/a`+Cmd aunque `ShortcutSet` intente rebindear;
  cambiar atajo de `attach` cambia `keyEquivalent`; atajo invalido deja `""`
  y conserva el item.
- Adjuntos: `delivery` por extension; `adopt` sobre `maxBytes` lanza
  `.tooLarge`; descarte borra. `Turn.numbered` se re-verifica con el
  `AttachmentRef` ampliado (caracterizacion que ya existe).
- Serializacion: turno con imagen ⇒ `content` array con `image_url`; sin
  imagen ⇒ `String`.
- ChatViewModel: `attach`+`send` ⇒ el Turn lleva adjuntos; persist/restore
  conservan `attachmentPaths`.
- Notices: con reloj inyectado, desaparece a los 4 s; mas de `maxVisible`
  desplaza el mas viejo.
- Updates: parse `v0.6.0`; comparacion; malformado ⇒ nil; transporte que
  falla ⇒ nil sin lanzar; segunda llamada el mismo dia no toca la red.

## Definicion de done

Cmd+C/V/X funcionan en todos los campos; arrastrar una imagen a la ventana
la adjunta y el modelo la ve; los avisos aparecen y se van solos; la app
avisa cuando hay version nueva y no dice nada cuando no hay red. Prueba
manual de Karen. Gates verdes.

## Riesgos

- Drag & drop global + SwiftUI: usar el patron del prototipo.
- Imagenes grandes: reescalar a 1024 **antes** de base64, en chat y realtime.
- Tres versiones que no coinciden: 6a-6 empieza unificando `Build.version`.

## Desviaciones respecto al borrador original

1. UISound en Services, no UI.
2. Puerto `AttachmentStoring` en Core (UI no importa Services).
3. Imagen-en-voz-viva diferida a 6c-3.
4. Tests de update del prototipo no se portan.
5. Long-paste fuera de alcance.
