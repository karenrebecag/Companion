# DS-04 — Dropdown

**Estado: BORRADOR.** Capa: molecula. Depende de: 02, 03.

## Objetivo

El dropdown del prototipo vive en el **header** (modelo / historial), no
solo en Ajustes. Un `OpenMenu` a nivel root, portal fuera de todo
ScrollView, scrim solo en `.choice`, cierre por click fuera / Escape /
elegir. El de Ajustes se conecta al mismo panel.

## Referencia

`../companion/Sources/Dropdown.swift`.
`CompanionRoot.swift` 67-104 (scrim, overlays, anclas).
Blur: nativo (`.blur` + scale), no Pow. Decision de 6b intacta.

## Archivos

- `Sources/CompanionUI/Dropdown.swift` (extender, no clonar)
- `Sources/CompanionUI/CompanionRootView.swift` (overlays de portal)
- SettingsItem deja de ser un host aislado: habla con `OpenMenu` o con el
  host que ya existe, un solo mecanismo.

## Contrato

```swift
enum OpenMenu: Equatable { case choice, history, settingsPick(String) }
```

Filas: hover, check con `IconGlyph`, stagger existente. RainbowDot en el
acento "Predeterminado" como el prototipo.

Tests: `DropdownSession` ya cubre teclado; añadir que un segundo menu
cierra el primero.

## Portar

- Un `OpenMenu` a nivel root; portal fuera de todo ScrollView
- Scrim solo en `.choice`; cierre: click fuera / Escape / elegir
- Filas: hover, check con `IconGlyph`, RainbowDot en Predeterminado
- El panel de Ajustes es el mismo objeto que header (05)

## Fuera

- Componer el header (05). Orb
- Pow. Un segundo dropdown distinto para Ajustes

## Reescribir

- Blur nativo (`.blur` + scale), no Pow
- `Semantic` / `Space` / `Radius`; stagger ya heredado, no duraciones nuevas
- `SettingsItem` habla con el mismo `OpenMenu`, no un host aislado
- Tests: un segundo menu cierra el primero (`DropdownSession`)

## Hallazgos

- El `.sheet` de macOS no deja pasar el `Anchor` al root. Settings conserva
  su `dropdownPortal` local hasta DS-12; el `DropdownHost` / `OpenMenu` ya
  es el mismo objeto. No es un segundo dropdown.
- Click-away / hit-testing de root solo para `.choice` / `.history`
  (`blocksRoot`). Settings no arma el sink de la ventana. Escape en la
  hoja cierra el pick primero; `onDisappear` limpia la sesion.
- Panel anclado al borde derecho del disparador. Lista con tope
  `65 * Space.x1` y scroll (Voz/Highlight no caben).
- Choice/history en 05 son overlays con el mismo `DropdownPanel`, no un
  segundo ForEach generico.

## Done

En Ajustes el panel ya existe; al cerrar 05, el de modelo e historial
tiene que ser el mismo objeto visual. Si Ajustes y header se ven dos
familias de menu, no esta.
