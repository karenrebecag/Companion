# R-04 — Estado seleccionado

**Estado: BORRADOR.** Capa: atomo. Depende de: 01, 03.

## Objetivo

Que "seleccionado" sea un token, no un numero magico inventado en cada sitio.
Hoy Ajustes tiene **tres idiomas distintos** para el mismo estado, y dos de
ellos son 40 lineas duplicadas.

## Referencia

OSMO resuelve variantes de un control con **una** capa dedicada y un atributo
declarado, no con opacidades por call site:

```html
<a class="button" data-shape="round">
  <div data-wf--button-theme--variant="electric" class="button-bg"></div>
```

```css
.button-bg { background-color: var(--color-electric); inset: 0%; }
.button-bg, .button { transition: all var(--animation-ease); }
```

Un elemento de fondo, una variante nombrada, una transicion compartida.

Estado medido hoy:

| control | fondo | borde |
|---|---|---|
| tabs (`SettingsView.swift:158`) | `surface` op. 0 → 1 | `clear` → `border` |
| `themeCard` (`SettingsAppPane.swift:288`) | `surface` op. 0.4 → 1 | `border` → `foreground` op. 0.65, hairline → thin |
| `typeCard` (`SettingsAppPane.swift:326`) | identico a `themeCard` | identico a `themeCard` |

`themeCard` y `typeCard` son la misma vista con el `label` cambiado.

Opacidades sueltas en todo el modulo: `0.4`, `0.55`, `0.65`, `0.5`, `0.001`.

## Archivos

- `Sources/CompanionUI/TokensChoices.swift` (roles `selected*`)
- `Sources/CompanionUI/Controls.swift` (`SelectableCard`)
- `Sources/CompanionUI/SettingsAppPane.swift` (`themeCard` + `typeCard` → uno)
- `Sources/CompanionUI/SettingsView.swift` (tabs)
- `Tests/CompanionTests/ControlTests.swift`

## Contrato

Roles nuevos en `Semantic`, resueltos por tema como el resto — no
`.opacity()` sobre otro rol:

```swift
public static var selected: Color          // fondo de lo elegido
public static var selectedBorder: Color     // su filete
public static var unselected: Color         // fondo de lo no elegido
```

Un componente, tres usos:

```swift
struct SelectableCard<Content: View>: View {
    let selected: Bool
    var label: String
    var help: String? = nil
    let action: () -> Void
    @ViewBuilder var content: () -> Content   // el glifo o la muestra "Aa"
}
```

Contrato de comportamiento, igual en los tres:

- Fondo `selected` / `unselected`, filete `selectedBorder` / `border`.
- Grosor de filete **constante**. Hoy salta de `hairline` a `thin` al
  seleccionar y eso mueve el layout 0.5 pt: es un bug, no un enfasis.
- `PressableStyle`, `.springSelect`, `accessibilityAddTraits(.isSelected)`.
- El aire lo pone quien lo usa; la tarjeta no trae padding propio.

Los tabs son el mismo control con `content` = icono + etiqueta. No se
inventa un cuarto idioma para ellos.

## Portar

- La capa de fondo dedicada de OSMO y la variante nombrada.
- La transicion compartida (`--animation-ease` ≈ `.springSelect`), una sola
  para los tres.

## Fuera

- Tocar `AppButton` / `AppField` / `ControlLook`. Ese eje ya esta resuelto y
  es otro problema.
- Las opacidades del `Orb` y del `Halftone`: son textura, no estado.
- `Color.black.opacity(0.001)` de los hit-catchers: es un truco de hit
  testing, no color. Se marca `// token-exempt:` y se queda.
- Radios. Es R-06.

## Reescribir

- `themeCard` y `typeCard` → un `SelectableCard`. Menos ~40 lineas.
- Tabs de `SettingsView` → `SelectableCard`.
- `modeToggle` de `HeaderView.swift:104-110` usa `surface.opacity(0.55)` y
  `border.opacity(0.5)`: mismo estado, cuarto idioma. Entra aqui.
- Las opacidades restantes sobre roles semanticos se sustituyen por el rol
  que corresponda. Si un valor no tiene rol, se le crea uno o se justifica.

## Hallazgos

- El grosor variable de filete (`hairline` → `thin`) desplaza el contenido al
  seleccionar. Con `SelectableCard` desaparece; verificar que el enfasis
  sigue leyendose solo con color.
- `Semantic.hover` y `Semantic.pressed` ya existen como `tint()` con alfa
  declarada. `selected` sigue ese patron, no uno nuevo.
- Con el acento elegible por el usuario, `selectedBorder` **no** debe ser el
  acento: hay acentos claros (lima, amarillo, blanco) que sobre `surface`
  claro no se ven. Sigue la logica ya resuelta en `Semantic.accentText`.
  Re-aprobar esta linea si al implementar se prefiere acento.

## Done

Los tres grupos de tarjetas de Ajustes —tema, tipografia, tabs— y el toggle
de modo del header se ven y se comportan **igual** al seleccionarse. Cambiar
el acento a lima y a amarillo no rompe el filete de ninguno. Nada salta al
hacer clic.
