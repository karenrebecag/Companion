# DS-03 — IconGlyph

**Estado: BORRADOR.** Capa: atomo. Depende de: 02.

## Objetivo

Los glifos de identidad (check, cruz, folder, reloj) son el set de trazo 1
pt del prototipo, no SF Symbols engordados. SF Symbols siguen para lo que
este set no cubre (mic, chevron, waveform).

## Referencia

`../companion/Sources/Icons.swift` entero. Path 24×24, stroke 1, miter 10.
`IconGlyph` hereda `foregroundStyle`.

## Archivos

- `Sources/CompanionUI/Icons.swift`

## Contrato

```swift
public enum CompanionIcon { case check, clock, cross, folder }
public struct IconGlyph: View {
    public init(icon: CompanionIcon, size: CGFloat = 16)
}
```

Tests: el path no esta vacio para cada case (puro, sin instanciar View si
se extrae `path(in:)`).

## Portar

- `Icons.swift` entero: path 24×24, stroke 1, miter 10
- `CompanionIcon`: check, clock, cross, folder
- `IconGlyph` hereda `foregroundStyle`

## Fuera

- Mic, gear, chevron, waveform en Path (siguen SF)
- Dropdown (04 lo enchufa). Header (05). ControlBar (08)
- No redibujar el set

## Reescribir

- Tokens `IconSize` / `Space`, no `.grid` suelto
- Tests sobre `path(in:)`, sin instanciar `View`
- `HoverIconButton` sigue en SF hasta que 05/08 pidan el glifo cubierto
- `Shape.path(in:)` es nonisolated: `lineWidth = 1` literal; el test lo
  iguala a `Stroke.hairline`
- Default 16 es constante de contrato, no `TypeSize.base`. `IconSize.glyph`
  cuando un spec toque tokens.

## Done

Check del dropdown y cruz de colgar (08) se leen como linea fina, no como
SF Symbol. Comparar con el prototipo a mismo tamaño.
