# DS-01 — Ventana

**Estado: BORRADOR.** Capa: template. No depende de otros DS.

## Objetivo

La ventana es la de Companion, no una ventana de Xcode. Mismas proporciones,
titlebar invisible, el contenido pinta debajo, el fondo es pagina +
halftone. Sin esto, ningun componente posterior se lee como el producto.

## Referencia

`../companion/Sources/ConversationWindow.swift` 34-60:
`560×840`, aspect 2:3, min `440×660`, max `680×1020`,
`fullSizeContentView`, `titleVisibility = .hidden`,
`titlebarAppearsTransparent`, `hosting.sizingOptions = []`.

Fondo: `CompanionRoot.swift` 49-51 — `bg1` + `HalftoneOverlay` a ventana
completa, no solo onboarding.

## Archivos

- `Sources/CompanionApp/CompanionMain.swift` (creacion del `NSWindow`)
- `Sources/CompanionUI/CompanionRootView.swift` (fondo)

## Contrato

La ventana del rebuild iguala esas mascaras y medidas. El hosting no
impone minimo al marco. Halftone detras de todo el root (onboarding y
hilo). No se toca el layout interno del hilo en esta pieza.

## Portar

- Medidas: `560×840`, aspect 2:3, min `440×660`, max `680×1020`
- `fullSizeContentView`, title hidden, titlebar transparente
- `hosting.sizingOptions = []` (SwiftUI no infla el marco)
- `isReleasedWhenClosed = false` (AppDelegate retiene)
- `bg1` + `HalftoneOverlay` a ventana completa

## Fuera

- `KeyableWindow`, confirmacion de cierre
- Header, orb, chat, settings, ViewModels
- Padding `10 * grid` del header: es DS-05, no un recorte callado

## Reescribir

- `WindowChrome` en CompanionUI: App no es target de tests
- `Semantic.background`, no `Color.bg1`
- `contentMinSize` / `contentMaxSize` / `contentAspectRatio`, no `minSize` del marco
- `install`: autoresizing **despues** de `contentView`
- Tests de metricas; no instanciar `NSWindow` (el helper SIGSEGV)

## Hallazgos

- Clearance de semaforos/logo queda en DS-05 (`10 * grid`). Esta pieza cierra silueta, no el header. Re-aprobar el aplazamiento.
- Tests no crean `NSWindow`. El contrato de chrome se verifica por constantes.

## Done

Al lado del prototipo, las dos ventanas tienen la misma silueta: columna
esbelta, chrome de macOS casi invisible, textura de puntos en el fondo.
Si la titlebar sigue comiendo el logo, no esta.
