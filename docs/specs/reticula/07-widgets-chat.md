# R-07 — Widgets de chat

**Estado: APROBADO** (Karen, 2026-08-24). Capa: organismo.
Depende de: 01 (escala), 05 (contrato).

## Objetivo

Meter al sistema las tres tarjetas que renderizan **salida del modelo**.
`MapCard`, `GalleryCard` y `SourcesCard` se escribieron en otra pasada y nunca
entraron: son las unicas vistas de `CompanionUI` que usan
`.font(.system(size:))`, asi que **R-01 no las toco** — no responden ni al
control de tamano ni a la tipografia que elija el usuario.

## Referencia

Medido por el contrato de R-05 (`conformance/ui-contract.json`):

| archivo | radius | frame | system-font | copy | duration |
|---|---|---|---|---|---|
| `MapCard.swift` | 3 | 2 | 1 | 1 | — |
| `GalleryCard.swift` | 3 | 2 | 1 | — | — |
| `SourcesCard.swift` | 1 | 1 | 2 | 1 | 1 |

19 de las 86 infracciones del repo en tres archivos.

Contraste con `JobCardView` y `ThreadView`, que **si** estan dentro: usan
`Radius.lg` / `bubbleRadius`, `Font.uiMicro` / `uiCaption` y `Space.*`. Su
unica deuda es aritmetica sobre `Space`, que es de R-05.

Dos defectos concretos que no salen en la tabla:

1. **El chrome esta copiado tres veces**: `padding(Space.x4)` +
   `background(Semantic.surface)` + `cornerRadius(Radius.md)` +
   `overlay(RoundedRectangle(cornerRadius: 8).stroke(...))`. El relleno usa el
   token y el filete un literal. Hoy valen lo mismo por coincidencia; R-06
   borra `Radius.md`, la linea del relleno **no compila** y se arregla, y la
   del filete compila igual y se queda en 8. Relleno en 4, contorno en 8.
2. **`SourcesCard` usa `uiCaption` para nueve cosas distintas** — titulo,
   seccion, contador, titulo de enlace, host, detalle, nombre de archivo,
   extension. Despues de R-01 son nueve textos a 11 pt. El mismo mal de
   Ajustes, pero sin siquiera un `uiLabel` que lo rompa.

## Archivos

- `Sources/CompanionUI/CardView.swift` (chrome comun + `CardMetrics`)
- `Sources/CompanionUI/MapCard.swift`
- `Sources/CompanionUI/GalleryCard.swift`
- `Sources/CompanionUI/SourcesCard.swift`
- `Sources/CompanionUI/{en,es}.lproj/Localizable.strings`
- `conformance/ui-contract.json` (bajar el baseline)

## Contrato

**Un chrome, no tres.** En `CardView.swift`, que ya es el despachador:

```swift
extension View {
    /// Relleno y filete comparten UN token de radio. Escribirlos por separado
    /// es como se desincronizan.
    func cardSurface() -> some View
}
```

**Jerarquia de tres niveles, igual en las tres tarjetas.** Es la direccion de
R-01: hacia arriba, no hacia abajo.

| papel | estilo | pt |
|---|---|---|
| titulo de tarjeta | `.uiSubtitle` | 16 |
| titulo de fila (ubicacion, enlace, archivo) | `.uiLabel` | 13 |
| apoyo (direccion, host, detalle, extension) | `.uiCaption` | 11 |
| encabezado de grupo | `typeEyebrow()` | 11 mono/caja alta |

**Iconos por token.** `.font(.system(size:))` desaparece: los `Image(systemName:)`
toman `.uiCaption` / `.uiTitle` como el resto del producto.

**Metricas de componente** en `CardMetrics`, patron ya usado por
`HeaderMetrics` y `SettingsOverlayMetrics`. La columna de icono es `Space.x4`;
el alto del mapa y el lado de la miniatura quedan como metrica nombrada hasta
que R-02 aterrice el tier de `Section` y se re-deriven.

**Copy al catalogo.** Claves nuevas `map.title` y `sources.file*`.
`sources.web` ya existia y la tarjeta pasaba `"Web"` a mano.

**Motion por token y con reduce-motion**, como `Shimmer`.

## Portar

- Nada de OSMO. Esta pieza es traer tres vistas al sistema que ya existe.

## Fuera

- Rediseñar las tarjetas: mismo contenido, misma disposicion, mismos datos.
- `JobCardView`, `ThreadView`, `AttachmentViews`: ya estan dentro; su deuda
  es aritmetica sobre `Space` y la baja R-05.
- El copy duro de `StatusLine` y `ShortcutCaptureField`. Son chrome, no
  widgets de chat; quedan en el baseline.
- Elegir el radio definitivo. Es R-06: aqui solo se garantiza que relleno y
  filete usen **el mismo token**, sea cual sea.

## Reescribir

- El chrome triplicado a `cardSurface()`.
- Los cuatro `.system(size:)`.
- Los siete radios literales.
- Los cinco literales de `.frame`.
- Los dos copys fuera del catalogo.
- El `easeInOut(duration: 0.2)` de `SourcesCard`.
- Los nueve `uiCaption` de `SourcesCard`, a la tabla de arriba.

## Hallazgos

- `sources.web` estaba en el catalogo, en los dos idiomas, y la tarjeta
  pasaba `"Web"` literal al lado. La clave llevaba tiempo muerta.
- `CardView` ya existia pero solo despacha el payload; nunca fue el chrome.
  Por eso las tres tarjetas lo reimplementaron.
- **No habia test de paridad del catalogo.** La regla `copy-literal` empuja el
  copy HACIA el catalogo, asi que sin paridad se puede mover una cadena y
  publicar el idioma que falta en silencio: la UI cae al identificador crudo
  delante del usuario. Se agrego `catalogParityTests` junto al contrato — 176
  claves, verificado por mutacion (quitar una de `es` falla nombrandola).
- **Cambio de recorte a verificar con el ojo.** `.cornerRadius(Radius.md)`
  recortaba a los hijos; `cardSurface()` pinta el fondo con un
  `RoundedRectangle` y **no** recorta. Ningun contenido parecia depender de
  ese recorte (el mapa y las miniaturas se recortan por su cuenta), pero si
  algo se desborda por una esquina se vera cuadrado. `.cornerRadius` esta
  deprecado en SwiftUI, por eso no se conservo.

## Done

El contrato de R-05 baja de 86 a 67 infracciones y las tres tarjetas salen del
baseline por completo. Con la app abierta: cambiar la tipografia en Ajustes
cambia tambien el texto de las tarjetas — hoy no lo hace — y subir el tamano
las escala con el resto.
