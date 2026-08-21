# DS-02 — Press y hover

**Estado: BORRADOR.** Capa: atomo. Depende de: 01 (para juzgarlo en la
ventana correcta). Se puede construir en paralelo a 01 si hace falta.

## Objetivo

Todo control clicable del prototipo tiene el mismo spring de presion y el
mismo chip de hover. Hoy el rebuild mezcla `.plain`, `AppButton` y nada.

## Referencia

- `PressableStyle` y `hoverChip` en el prototipo (Tokens / CompanionRoot).
- `HoverIconButton` en `CompanionRoot.swift` (gear, folder, historial).
- Springs: `Motion.swift` — `springPress`, `springHover`. El rebuild ya
  los tiene; no inventar duraciones.

## Archivos

- `Sources/CompanionUI/Pressable.swift` (nuevo, ≤400)
- Cablear en engranaje actual y en botones de chrome que 05 reusara.

## Contrato

```swift
struct PressableStyle: ButtonStyle { ... } // scale 0.98, springPress
struct HoverChip: ViewModifier { ... }     // Semantic.hover, Radius.md
struct HoverIconButton: View { ... }       // icono + help nativo
```

Reduce-motion: el scale de press se apaga; el hover de color se queda.

## Portar

- `PressableStyle` + `springPress`; opacity 0.85 al press
- `HoverChip`: rampa fill 0.55→1, stroke 0.5→1, scale 1.04
- `HoverIconButton`: scale 1.05, tinta muted→foreground, frame 7 grid
- Reduce-motion: scale de press/hover off; color de hover se queda
- Gear `gearshape` + help

## Fuera

- Redisenar `AppButton`. Orb. `RoundIconButton` (08)
- Tooltip propio (`HoverTooltipModifier`): spec pide help nativo
- `UISound` al press
- `IconGlyph` (03)

## Reescribir

- Scale de press **0.98**, no 0.94 del prototipo (contrato, alineado a AppButton)
- `Semantic.surface` + overlay `Semantic.hover`, `Radius.md`, `IconSize.hero`
- Chip **dentro** del label: el press mueve icono y chrome juntos
- `PressMotion` extraido para tests sin ventana
- Spacers del overlay: `allowsHitTesting(false)` para no tapar el hilo

## Hallazgos

- Gear vs drag de titlebar: el padding 40 pt es DS-05. Anotado, no callado.
- Fill no sustituye surface por un tint mas debil: misma rampa + overlay hover.

## Done

Un icono del chrome se siente al pasar el mouse y al clicar igual que en
el prototipo. Si es un boton de sistema plano, no esta.
