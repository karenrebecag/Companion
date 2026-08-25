# R-03 — Reticula de Ajustes

**Estado: BORRADOR.** Capa: organismo. Depende de: 01, 02.

## Objetivo

Ajustes es la pantalla donde se ve el problema. Al terminar tiene columna
real: las etiquetas en un track, los controles en otro, todos empezando en la
misma x. Y una sola fila, no cuatro maneras de escribir la misma fila.

Esta pieza **no** rediseña Ajustes. Aplica 01 y 02 y unifica la fila.

## Referencia

OSMO — fracciones de container `.container.is--m/.is--sm/.is--s` = 0.825 /
0.65 / 0.5. Adimensionales, transfieren 1:1 (ver `README.md`).

Estado medido hoy:

- `SettingsLine` empuja con `Spacer(minLength: Space.x3)`. El borde izquierdo
  de cada control trailing cae donde termine su propio texto: el stepper de
  tamano, el dropdown de acento y el boton destructivo arrancan en **tres x
  distintos**.
- La mitad del modulo no usa `SettingsLine`: el `Toggle` de sonidos mete su
  propio `VStack` inline (`SettingsAppPane.swift:186`), el bloque de version
  es un `VStack` suelto (`:213`), `slider` tiene su propio `HStack` con
  `Spacer` (`SettingsVoiceSection.swift:146`). Los cuatro son "etiqueta +
  descripcion + control" y espacian distinto: `Space.x1`, `x2`, `x3`.
- La hoja es un cuadrado fijo: `SettingsOverlayMetrics.maxSide = 560` se usa
  para ancho **y** alto (`CompanionRootView.swift:186-190`). El panel App mide
  bastante mas de 560 de alto y hace scroll dentro de un cuadrado.
- Los tabs se estiran a ~170 pt cada uno (`frame(maxWidth: .infinity)`) para
  contener una etiqueta de 11 pt centrada.

## Archivos

- `Sources/CompanionUI/SettingsAppPane.swift` (`SettingsLine`, `SettingsMultiline`, bloques)
- `Sources/CompanionUI/SettingsView.swift` (metricas de hoja, tabs, panel Tu)
- `Sources/CompanionUI/SettingsVoiceSection.swift` (`slider` a la fila comun)
- `Tests/CompanionTests/SettingsTests.swift`

## Contrato

**Dos tracks.** Contenido = ancho de hoja − 2 x `Layout.containerPadding`.
A 560: 528. Track de etiqueta = `Layout.sm` (0.65); track de control = el
resto menos `Layout.gutter`.

```
|<-16->|<------- etiqueta 343 ------->|<-16->|<-- control 169 -->|<-16->|
                                              ^ x = 375, fijo
```

Se expresa en fraccion, no en punto, para que sobreviva el resize de 440 a
680: `containerRelativeFrame(.horizontal)` (macOS 14+) o el ancho de hoja
propagado. El contrato es la fraccion; la mecanica la elige quien implemente.

**Una fila.** `SettingsLine` absorbe los cuatro idiomas actuales:

```swift
struct SettingsLine<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var control: ControlPlacement = .trailing   // .trailing | .below
    @ViewBuilder var trailing: () -> Trailing
}
```

- `.trailing` — control en el track derecho, alineado a la derecha. Stepper,
  dropdown, boton, toggle.
- `.below` — control a ancho completo bajo la etiqueta. Slider, campo de
  texto, captura de atajo. El track de etiqueta sigue mandando el ancho del
  bloque de texto.

Espaciado interno de la fila, fijo y unico: titulo → subtitulo `Space.x1`;
fila → fila `Space.x3`; grupo → grupo `Section.s`; bloque → bloque
`Section.m`.

El `Toggle` con descripcion, el bloque de version y el `slider` pasan a ser
`SettingsLine`. `SettingsMultiline` se conserva como esta —es un caso
`.below` con altura propia— pero toma el espaciado de la tabla.

**La hoja deja de ser cuadrada.** `maxSide` se parte en dos:

```swift
public enum SettingsOverlayMetrics {
    public static let maxWidth: CGFloat = 560   // = Layout.designWidth
    public static let maxHeight: CGFloat = 680  // el alto lo decide la ventana
    ...
}
```

**Los tabs dejan de estirarse.** Ancho por contenido + `Space.x4` de aire,
agrupados a la izquierda. Un tab de 170 pt para una etiqueta de 11 no es una
decision, es un `maxWidth: .infinity` que nadie miro.

## Portar

- Las fracciones de container de OSMO como definicion de los dos tracks.
- El principio de una fila con variantes declaradas, no cuatro filas.

## Fuera

- Rediseñar Ajustes: mismos paneles, mismo contenido, mismo orden.
- Tocar la logica de preferencias, `UserProfile`, `VoiceProfile`, atajos.
- El estado seleccionado de tabs / `themeCard` / `typeCard`. Es R-04.
- El overlay, el scrim, la cascada de Escape. Eso es DS-12 y esta bien.
- Radios. Es R-06.

## Reescribir

- `Spacer(minLength:)` → track fijo por fraccion. Es la causa raiz de la
  columna desalineada.
- Los tres bloques ad-hoc (`Toggle` con `VStack`, version, `slider`) a
  `SettingsLine`.
- `maxSide` → `maxWidth` / `maxHeight`.
- `padding(Space.x5)` del `ScrollView` → `Layout.containerPadding`.
- Espaciados de bloque `Space.x5` → `Section.s` / `Section.m` segun la tabla.
- `SettingsLine(title:..., subtitle:...) { EmptyView() }` en
  `SettingsAppPane.swift:110` es una fila cuyo control esta en el `LazyVGrid`
  de abajo: se vuelve `.below` con la grilla como contenido, no una fila
  vacia seguida de una grilla suelta.

## Hallazgos

- El `LazyVGrid` de tipografias es la **unica** grilla del proyecto. Tres
  columnas flexibles con `Space.x2` — coincide con la reticula nueva por
  casualidad, no por derivacion. Se deja y se re-ancla a `Layout.gutter`.
- Con `uiLabel` a 13 y `uiCaption` a 11 (R-01), varias filas cambian de alto.
  `SettingsOverlayMetrics.cardHeight = 68` fue medido contra los tamanos
  viejos: verificar al abrir y re-derivar de `ControlHeight` si baila.
- `SettingsOverlayMetrics.avatar = Space.x8 + Space.x1` (36) es aritmetica
  sobre `Space` — el patron que R-05 prohibe. Se resuelve aqui porque es de
  este modulo: pasa a `IconSize` o a un valor derivado de `ControlHeight`.

## Done

Abrir Ajustes, panel App, y **poner una regla vertical en la pantalla**: el
stepper, el dropdown de acento, el dropdown de idioma y el boton de borrar
tocan todos la misma linea. Los cuatro bloques se leen como bloques. Nada
hace scroll dentro de un cuadrado.

Si dos controles del track derecho no empiezan en la misma x, no esta.
