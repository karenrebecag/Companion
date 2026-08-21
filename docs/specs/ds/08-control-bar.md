# DS-08 — ControlBar

**Estado: BORRADOR.** Capa: organismo. Depende de: 02, 03, 06, 07.

## Objetivo

El orb flota abajo, sin caja. Inactivo: solo el orb (68 pt en modo voz,
46 en texto). Activo: mute (circulo rojo solido si silenciado) y colgar
(cruz del set). Desaparecen Mute/Unmute/Interrumpir/barras de nivel del
rebuild. Esc sigue cortando el turno.

## Referencia

`../companion/Sources/vendor/livekit-ui/ControlBar.swift`.
Transiciones nativas (`.blur` + scale + opacity), no Pow.

## Archivos

- `Sources/CompanionUI/ControlBar.swift`
- `Sources/CompanionUI/VoiceControlsView.swift` (retirar o vaciar)
- `Sources/CompanionUI/CompanionRootView.swift` (orb deja el ZStack
  esquina y baja a la barra)

## Contrato

```swift
struct RoundIconButton: View { ... }
struct ControlBar: View { ... }
```

Mute usa `Semantic.destructive` + tinta on-destructive, no un rojo suelto.

## Portar

- Orb flota, sin caja. Inactivo: solo orb (68 pt voz, 46 texto)
- Activo: mute (circulo rojo solido si silenciado) + colgar (cruz del set)
- Esc corta el turno
- `RoundIconButton`

## Fuera

- Composer (10). Maquina de voz
- Mute/Unmute/Interrumpir/barras de nivel del rebuild: desaparecen
- Rojo de sistema suelto. `Color == .bg2` para el borde

## Reescribir

- `Semantic.destructive` + tinta on-destructive (cicatriz dark)
- Flag `bordered:` explicito, no comparar `background == .bg2`
- Transicion nativa `.blur` + scale + opacity, no Pow
- Cruz via `IconGlyph`. Orb baja del ZStack esquina a la barra
- `VoiceControlsView` se retira o vacia

## Hallazgos

- El composer sigue visible debajo/arriba de la barra: ocultarlo es DS-10.
  La barra ya no es Mute/Unmute/niveles.

## Done

Modo voz del prototipo: el orb es la protagonista, mute/colgar aparecen
solo en sesion. Si la barra parece un panel de debug, no esta.
