# R-02 — Tier de seccion y container

**Estado: BORRADOR.** Capa: fundamento. Depende de: 01.

## Objetivo

Dar al sistema el piso de espaciado que le falta. Hoy el salto mayor
disponible es `Space.x8` (32) y el gap interno es `Space.x3` (12): razon 2.7x.
En OSMO esa razon es 12.5x. Por eso un encabezado de grupo tiene el mismo
respiro que una fila cualquiera y deja de leerse como encabezado.

`Space` **no se toca**: ya es la rampa de gaps de OSMO transformada. Lo que
se agrega es el tier de arriba.

## Referencia

OSMO `css/main.css` `:root` — dos familias separadas, no una:

```
--gap-xxs .5em  --gap-xs .75em  --gap-s 1em   --gap-sm 1.25em
--gap-m  1.5em  --gap-l 1.875em --gap-xl 2em  --gap-xxl 2.5em

--padding-xs 3.75em  --padding-s 5em  --padding-m 7.5em
--padding-l 10em     --padding-xl 12.5em
```

Los gaps van por `mu_r` (x13) y ya existen como `Space`:

| OSMO | em | x13 | Companion |
|---|---|---|---|
| `gap-xxs` | 0.5 | 6.5 | `Space.x2` |
| `gap-xs` | 0.75 | 9.75 | `Space.x3` |
| `gap-sm` | 1.25 | 16.25 | `Space.x4` |
| `gap-m` | 1.5 | 19.5 | `Space.x5` |
| `gap-l` | 1.875 | 24.4 | `Space.x6` |
| `gap-xxl` | 2.5 | 32.5 | `Space.x8` |

Los paddings reparten el lienzo: van por `mu_c` (x0.389):

| OSMO | px@1440 | x0.389 | tier |
|---|---|---|---|
| `padding-xs` | 60 | 23.3 | **24** |
| `padding-s` | 80 | 31.1 | **32** |
| `padding-m` | 120 | 46.7 | **48** |
| `padding-l` | 160 | 62.2 | 64 |
| `padding-xl` | 200 | 77.8 | 80 |

Y el corte de seccion de OSMO no es solo espacio — `.rich-text h3` usa
`margin-top: gap-xl` + `padding-top: gap-xl` + `border-top: 1px solid`.
Razon contra el gap interno: 4.0.

## Archivos

- `Sources/CompanionUI/TokensChoices.swift` (enums `Section` y `Layout`)
- `Sources/CompanionUI/CompanionRootView.swift` (padding de container)
- `Sources/CompanionUI/HeaderView.swift` (clearance, altura de barra)
- `Tests/CompanionTests/DesignFoundationTests.swift` (rampa y monotonia)

## Contrato

```swift
/// Reparte el lienzo. Sigue el mapa de container (mu_c), no el de root:
/// un quiebre de seccion no lo dimensiona su texto.
public enum Section {
    public static let xs: CGFloat = 24
    public static let s: CGFloat = 32
    public static let m: CGFloat = 48
    public static let l: CGFloat = 64
    public static let xl: CGFloat = 80
}

/// Fracciones de container de OSMO. Adimensionales: transfieren 1:1.
public enum Layout {
    public static let designWidth: CGFloat = 560
    public static let containerPadding: CGFloat = Space.x4
    public static let gutter: CGFloat = Space.x4
    public static let full: CGFloat = 1.0
    public static let m: CGFloat = 0.825
    public static let sm: CGFloat = 0.65
    public static let s: CGFloat = 0.5
}
```

Reglas de uso, que es lo que hace util al tier:

- **Entre grupos de una pantalla**: `Section.s` (32).
- **Entre secciones mayores** (bloques de Ajustes, tramos del onboarding):
  `Section.m` (48).
- **Dentro de un grupo**: sigue siendo `Space.x3` / `Space.x4`.
- Un `Section.*` nunca separa dos filas hermanas. Si aparece ahi, el
  problema es que faltaba un grupo.

Container: **un solo** valor de padding horizontal en todo el producto,
`Layout.containerPadding` = 16. Hoy el shell usa 16 y Ajustes 20; el bug no
es cual de los dos, es que hay dos.

Alturas de control por `mu_r`, para que el header deje de improvisar:

```swift
public enum ControlHeight {
    public static let button: CGFloat = 32   // --btn-height 2.5em x 13
    public static let field: CGFloat = 40    // --input-height 3em x 13
    public static let bar: CGFloat = 60      // --nav-bar-height 4.625em x 13
}
```

`HeaderMetrics.topClearance` deja de ser `Space.x1 * 10` y pasa a
`Section.xs` (24) + el clearance de semaforos, o directamente
`ControlHeight.bar` como altura de la barra.

## Portar

- Las dos familias separadas de OSMO: gaps de texto y paddings de lienzo son
  escalas distintas, no un continuo.
- Las fracciones `1 / 0.825 / 0.65 / 0.5`.
- El corte de seccion como **espacio + filete**, no solo espacio.

## Fuera

- Tocar `Space`. Ya es correcto.
- `Section.l` / `Section.xl` (64 / 80) en la ventana de chat: no caben en
  840 pt de alto. Quedan declarados para onboarding y hero, sin uso en esta
  pieza.
- Aplicar el tier a Ajustes. Es R-03.
- El barrido de literales de `.frame`. Es R-05.

## Reescribir

- `HeaderMetrics.topClearance = Space.x1 * 10` → token de seccion. Es
  aritmetica sobre `Space.x1` para escribir 40, exactamente el patron que
  R-05 va a prohibir.
- Padding horizontal del shell y de Ajustes a un solo `Layout.containerPadding`.
- `CompanionRootView.swift:90` `padding(.top, Space.x6 * 2)` (= 48) →
  `Section.m`.
- `CompanionRootView.swift:120` `padding(.top, Space.x1 * 25)` (= 100) es la
  posicion del `ChoiceDropdown` bajo el header: pasa a derivarse de
  `ControlHeight.bar`, no de un multiplo inventado.

## Hallazgos

- El valor derivado del padding de container es **13.6**, no 16. OSMO sube el
  porcentaje al angostar (2.08% en desktop, 2.56% en movil); interpolado en
  logaritmo a 560 da 2.43% = 13.6 pt. Se elige 16 porque cae en la reticula
  de 4 y es el valor que el shell ya usa: el diff es menor y la desviacion
  (2.86% contra 2.43%) esta dentro de la tolerancia de OSMO. Registrado para
  no re-derivarlo cada vez.
- `Space.x1` (4) sobrevive como token pero **deja de ser una unidad de
  composicion**. Su unico uso legitimo es un gap real de 4 pt. R-05 lo
  vigila.
- `--gap-xs` (0.75em → 9.75) y `--gap-xl` (2em → 26) no tienen equivalente en
  `Space` y no se agregan: la rampa de 4 ya cubre el rango y meter 10 y 26
  la volveria un continuo.

## Done

Abrir Ajustes y ver los cuatro bloques como **cuatro bloques**, separados,
antes de leer una palabra. El eyebrow tiene aire arriba y su contenido pegado
abajo. Ningun borde del producto usa dos paddings de container distintos.
