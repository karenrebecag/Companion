# R-01 — Escala tipografica

**Estado: APROBADO** (Karen, 2026-08-24). Capa: fundamento. No depende de otros R.

## Objetivo

Que la escala que el sistema documenta sea la que se pinta. Hoy no lo es:
`TypeScale.apply` resta 3 pt y recorta a 12, asi que siete estilos de texto
salen identicos. Al terminar, cinco escalones reales derivados de la banda UI
de OSMO, con las razones conservadas en todos los pasos del control de
tamano.

Es la pieza de mayor impacto del programa y la mas aislada: dos archivos de
tokens y sus tests. Ninguna vista cambia de codigo.

## Referencia

OSMO `css/main.css` — banda UI de la escala en `em` sobre root 16:
`eyebrow 0.6875` (11 px), `body 1` (16), `h-xs 1.25` (20), `h-s 1.875` (30).
Razones consecutivas 1.4545 / 1.25 / 1.5.

Derivacion en `README.md` de este programa. Resumen: el body se ancla en 13
(`NSFont.systemFontSize`), lo que deja 1.18x por debajo y 2.23x por encima;
la forma de OSMO se ajusta al rango superior con exponente 0.875.

Estado medido hoy (`Typography.swift:110`):

```swift
apply(size) = max(12, size + (origin + delta))   // origin = -3
```

| token | spec | delta 0 | delta +3 |
|---|---|---|---|
| `xs` 10.24 | 10.24 | **12** piso | **12** piso |
| `sm` 12.8 | 12.8 | **12** piso | 12.8 |
| `base` 16 | 16 | 13 | 16 |
| `md` 18 | 18 | 15 | 18 |
| `lg` 20 | 20 | 17 | 20 |
| `xl` 25 | 25 | 22 | 25 |
| `display` 31.25 | 31.25 | 28.25 | 31.25 |

## Archivos

- `Sources/CompanionUI/TokensChoices.swift` (enum `TypeSize`)
- `Sources/CompanionUI/Typography.swift` (`TypeScale`, `Font.ui*`, helpers)
- `Tests/CompanionTests/DesignFoundationTests.swift` (test nuevo de razones)
- `Tests/CompanionTests/SettingsTests.swift` (rango de delta)
- `docs/design-system.md` (tabla de tipografia)

## Contrato

La rampa nominal es **11 / 13 / 16 / 22 / 29**, con nombres que dicen su
papel y no su talla:

```swift
public enum TypeSize {
    public static let micro: CGFloat = 11    // mono, eyebrow, caption
    public static let base: CGFloat = 13     // cuerpo y etiqueta de fila
    public static let strong: CGFloat = 16   // subtitulo, encabezado de grupo
    public static let title: CGFloat = 22    // titulo de hoja
    public static let display: CGFloat = 29  // logo, onboarding
}
```

El control de tamano pasa de **aditivo a multiplicativo**. Aditivo destruye
las razones en los extremos: es lo que hoy funde `xs` y `sm` en un solo
valor. Multiplicativo las conserva en todo el rango.

```swift
factor(delta) = pow(1.08, delta)
apply(size)   = max(floor, (size * factor).rounded())
floor = 10        // NSFont caption2, piso real de macOS
min = -1, max = 3 // -2 no existe: el body ya esta en el piso de plataforma
```

Rampa resultante en cada paso — monotona y con razones estables:

| delta | micro | base | strong | title | display | desviacion |
|---|---|---|---|---|---|---|
| −1 | 10 | 12 | 15 | 20 | 27 | 3.0% |
| **0** | **11** | **13** | **16** | **22** | **29** | 0.0% |
| +1 | 12 | 14 | 17 | 24 | 31 | 2.7% |
| +2 | 13 | 15 | 19 | 26 | 34 | 2.9% |
| +3 | 14 | 16 | 20 | 28 | 37 | 3.3% |

Razones nominales 1.182 / 1.231 / 1.375 / 1.318. La desviacion es el redondeo
a punto entero; el test tolera 5%.

Remapeo de estilos. **La direccion es hacia arriba**, no hacia abajo:

| estilo | hoy (delta 0) | nuevo | familia / caja |
|---|---|---|---|
| `uiEyebrow` | 12 | 11 | mono bold, uppercase, `Tracking.wider` |
| `uiMicro` | 12 | 11 | sans |
| `uiCaption` | 12 | 11 | sans |
| `uiMono` | 12 | 11 | mono |
| `uiMonoSm` | 12 | 11 | mono |
| `uiAction` | 12 | 11 | mono bold |
| `uiLabel` | 12 | **13** | sans — sube |
| `uiBody` | 13 | 13 | sans |
| `uiCode` | 13 | 13 | mono |
| `uiSubtitle` | 15 | **16** | sans |
| `uiTitle` | 17 | **22** | sans, `Tracking.tight` |
| `uiHeading` | 22 | 22 | sans, `Tracking.tight` |
| `uiLogo` | 28.25 | 29 | logo, `Tracking.tighter` |

`uiTitle` y `uiHeading` colapsan en el mismo escalon (22). Son el mismo papel
—titulo de hoja— con dos nombres. Se conservan los dos identificadores en
esta pieza para no tocar 11 call sites; unificarlos es trabajo de R-04.

Migracion de preferencia. El delta guardado se re-basa: bajo `origin = -3` el
valor **+3 era el nominal**; ahora el nominal es 0.

```swift
new = clamp(old - 3, -1, 3)     // +3 → 0 nominal; 0 → -1
key nuevo: "companionFontDeltaV3"
```

## Portar

- Banda UI de OSMO: razones 1.25 / 1.5 / 1.333 comprimidas con exponente
  0.875 al rango superior disponible.
- El principio de OSMO de que cada escalon cambia **mas de un canal**:
  el eyebrow ya no se distingue solo por tamano (no puede, esta en el piso)
  sino por familia mono + uppercase + `Tracking.wider`.
- `Tracking.tight` en `title` y `display`, como OSMO cierra el espacio en
  sus tallas grandes (`-0.04`, `-0.06`).

## Fuera

- La banda display de OSMO (62..150 px). No cabe en 560 pt.
- La ley fluida `--size-font: container/90`. En una app nativa el texto no
  encoge al achicar la ventana. El root queda fijo.
- Tocar `Space`, `Radius`, `Elevation` o cualquier vista. Solo tokens.
- Peso variable como canal. Inter-Regular es lo unico empaquetado; abrir
  pesos es otra pieza y arrastra licencias.
- Unificar `uiTitle` / `uiHeading`. Es R-04.

## Reescribir

- `TypeSize`: siete tokens por talla → cinco por papel. `xs`/`sm`/`md`/`lg`/
  `xl` desaparecen; no se dejan alias (regla de la casa: sin extras).
- `TypeScale.apply`: aditivo → multiplicativo. `origin` desaparece.
- `TypeScale.floor`: 12 → 10.
- `TypeScale.min`: −2 → −1, con migracion V3.
- `bodyLead` / `codeLead` siguen derivando de `apply(TypeSize.base)`; los
  multiplicadores 0.3 y 0.15 no cambian.
- `Typewriter.swift:194,202` usa `TypeSize.lg` como **altura de frame**, no
  como tamano de texto. Se sustituye por un token de espacio (`Space.x5`),
  que es lo que siempre fue. Unica vista que toca esta pieza.

## Hallazgos

- **Dos poblaciones de usuarios.** La migracion V2 hace `old - origin` =
  `old + 3`. Quien alguna vez movio el tamano antes de V2 quedo en +3 y ve
  la escala nominal; quien nunca lo toco lee 0 y ve la escala aplastada. El
  producto se ve distinto en dos maquinas por la misma version. La migracion
  V3 los junta.
- **`uiTitle` no siempre es texto.** `SettingsView.swift:244`,
  `HeaderView.swift:149` y `AttachmentViews.swift:75` lo usan como tamano de
  un `Image(systemName:)`. Subirlo de 17 a 22 tambien agranda esos iconos.
  Verificar los tres al abrir; si el icono queda grande, el arreglo es darles
  `IconSize.hero`, no bajar el token. Re-aprobar esta linea si aparece.
- **`floor` 12 tapaba el bug.** Con piso 10 y rampa multiplicativa el piso
  deja de actuar salvo en `delta = -1`, que es justo su papel.
- El gate de `gates.sh` no ve nada de esto: no hay literales de padding en
  juego. Esta pieza pasa el gate actual sin cambiarlo.

- **`Typewriter` cambio respecto a lo aprobado — RE-APROBAR esta linea.** El
  spec decia sustituir `TypeSize.lg` por `Space.x5`. Es incorrecto: los dos
  usos son el alto del caret y el hueco de la frase, o sea **alto de linea**,
  y un token de espacio fijo se queda en 20 mientras el texto crece a 37 en
  delta +3. Se implemento `TypeScale.bodyLine` (tamano renderizado del cuerpo
  mas su interlineado), que sigue al texto. De paso arregla un defecto que ya
  estaba: el frame usaba el token **crudo** (20) mientras el texto renderizaba
  a 13, asi que el caret siempre fue mas alto que su propia linea.
- `TypeSize` no vive en `Tokens.swift` sino en `TokensChoices.swift`, junto a
  `Space`, `Radius`, `Semantic` y `Elevation`. `Tokens.swift` solo tiene la
  rampa neutral y los acentos. Corregido en los cuatro specs que lo nombraban
  mal (01, 02, 04, 06).
- Swift 6: una constante global de test no puede inicializarse desde estaticos
  aislados al MainActor. La escalera de prueba es una funcion `@MainActor`.
- Los tests se verificaron por **mutacion**, no solo con el rojo de
  compilacion: devolviendo `floor` a 12 el suite falla con
  `delta -1 — el escalon 1 no crece (12.0 → 12.0)`, que es literalmente el bug
  original reproducido.

## Done

Abrir Ajustes y ver **cinco tamanos distintos**, no uno. El encabezado de
grupo se lee como encabezado, el titulo de la hoja domina, la etiqueta de
fila se separa de su descripcion. Movido el control de tamano de −1 a +3, la
proporcion entre esos cinco se mantiene: la pantalla crece, no se deforma.

Si al bajar el tamano dos textos vuelven a verse iguales, no esta.
