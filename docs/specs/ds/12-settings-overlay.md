# DS-12 — Ajustes overlay

**Estado: BORRADOR.** Capa: organismo. Depende de: 04, 05.

## Objetivo

Ajustes no es el `.sheet` de macOS. Es overlay centrado con scrim +
material, hoja propia (titulo, X, tabs), dropdowns fuera del ScrollView.
Escape cierra en cascada: confirm → ajustes → dropdown → cortar turno.

## Referencia

`CompanionRoot.swift` 111-179.
`SettingsView.swift` del prototipo: `SettingsSheet` GeometryReader,
max 560, tabs.

El contenido de panes (voz, perfil, atajos) ya esta en el rebuild:
se **mueve** de sistema-sheet a esta hoja, no se reescribe la logica.

## Archivos

- `Sources/CompanionUI/SettingsView.swift` (envolver)
- `Sources/CompanionUI/CompanionRootView.swift` (quitar `.sheet`, overlay)
- Approval/confirm encima, como el prototipo

## Portar

- Overlay centrado, scrim + material, hoja propia (titulo, X, tabs)
- Dropdowns fuera del ScrollView (portal 04)
- Escape en cascada: confirm → ajustes → dropdown → cortar turno
- GeometryReader, max 560, tabs del prototipo

## Fuera

- Tabs de Hermes / `~/.hermes` / `.env` (ADR 001)
- Reescribir la logica de los panes (voz, perfil, atajos): se **mueven**

## Reescribir

- Quitar `.sheet` de macOS; overlay en root
- Approval/confirm encima, como el prototipo
- Mismo `OpenMenu` que 04, no un host aislado

## Hallazgos

- Sin tabs Hermes/MCP (ADR 001). Panes: apariencia, perfil, voz,
  sistema, atajos.
- Esc con ajustes abiertos cierra primero el dropdown de la hoja, luego
  el overlay. Si no, el menu quedaba huerfano.

## Done

Engranaje: la ventana no empuja un sheet de Cocoa; la app se atenua y
la hoja flota. Junto al prototipo, el gesto es el mismo.
