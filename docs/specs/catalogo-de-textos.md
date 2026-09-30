# Catalogo unico de textos (pantalla, voz y modelo)

Estado: APROBADO (Karen, 2026-09-30; medido 2026-09-30).
Research: `docs/research/catalogo-de-textos.md` (APROBADO).

## Objetivo

Que todo texto que lee o escucha la usuaria salga de un solo catalogo en/es,
que una traduccion faltante no pinte la clave cruda, y que un idioma nuevo no
herede el ingles o el espanol en silencio.

## Lo que hay

- UI: `Localizable.strings` en/es con 645 claves cada uno, 569 llamadas a
  `Localized.string` en 73 archivos. Bien cubierto.
- Core: 224 lineas con literales en espanol en 33 archivos, en tablas Swift
  (`ApprovalCopy`, `BridgeCopy`, `BrowserCopy`, `DecisionCopy`,
  `Escalation+Copy`...). Viven ahi porque los actores de Services no alcanzan
  `Localized`, que es `@MainActor` por la isolation de UI.
- Services: 10 lineas en 5 archivos; `JobRunner` elige idioma con un booleano.
  `RealtimeRuntime.functionRefusal` duplica la clave `voice.function.refusal`
  de UI, que no tiene llamadores.
- App: un toast solo en espanol (`CompanionMainWindow.swift:93`).
- El gate de copy solo mira `Text(`, `.help(` y `.accessibilityLabel(` en UI.

## Bugs que salen del research (se arreglan primero, test en rojo)

1. **Clave faltante en `es` pinta la clave cruda.** `Localized.string` solo cae
   al ingles si falta el `.lproj` entero (`Localized.swift:68`). Fix: tratar
   `value == key` como faltante y caer a `en`, como CodexBar.
2. **`Bundle(path:)` en cada llamada** (`Localized.swift:81`). Fix: cachear los
   sub-bundles por idioma.
3. **La paridad parte lineas por comillas** (`LocalizedTests.swift:59`): no ve
   valores multilinea ni compara `%@`/`%d`. Fix: leer con el parser de
   Foundation y exigir los mismos especificadores por clave en en y es.

Estos tres no dependen de ninguna decision y pueden ir en un PR propio.

## Forma

- **Formato: `.strings` (+ `.stringsdict` si aparecen plurales).** El build
  nativo de SwiftPM 6.3.3 copia un `.xcstrings` sin compilarlo; solo Xcode y
  el backend `swiftbuild` lo compilan. Se reabre al pasar a Swift 6.4.
- **Tres canales:**
  - Pantalla: tabla `Localizable`.
  - Voz hablada a la usuaria: misma clave si la frase se sostiene sola; tabla
    `Spoken` solo para lo que se pronuncia distinto (sin simbolos, mas corto).
  - Instrucciones al modelo (prompts, estilo de TTS, `functionAccepted`): fuera
    del catalogo, en tablas Swift con `switch` exhaustivo sobre `AppLanguage`,
    sin `default`. Cambian conducta del modelo; no las edita un traductor.
- **Core no lee bundles.** Donde hoy arma texto para personas, devuelve un
  valor semantico y Services o UI lo traducen.
- Accesores tipados y computados (`static var`), nunca `static let`: el idioma
  cambia en caliente.

## Donde vive (decision de Karen)

- **L1 (recomendada): target nuevo `CompanionCopy`.** Foundation, sin
  `defaultIsolation`, con los `.lproj`; depende de Core y lo usan Services y
  UI. Pasa por `ResourceBundleLocator` como los otros dos, entra al probe y a
  `BUNDLES` del smoke. Toca `Package.swift`, `bundle.sh` y el smoke.
- **L2: el catalogo sigue en UI** y App inyecta una funcion
  `(clave, idioma) -> String` a los actores de Services. Sin tocar el
  manifiesto, pero con plumbing por actor y `Localized` tendria que volverse
  `nonisolated`.

## Secuencia

1. PR de los tres bugs (independiente, puede ir ya).
2. Decision L1/L2 y, con ella, el target y la migracion por dominio
   (aprobaciones, puente, navegador, trabajos), un dominio por PR.
3. Gate de copy ampliado a Core, Services y App para literales de pantalla.

Va despues de `tests-por-modulo`: los tests de copy ya caen en su target.

## Aceptacion

- Una clave faltante en `es` muestra el ingles, con test.
- Paridad de claves y de especificadores en/es, con el parser de Foundation.
- Ningun literal para personas fuera del catalogo en Core, Services y App
  (gate).
- `package-smoke.sh` verde con el bundle nuevo si se elige L1.
- `scripts/gates.sh` verde.

## Decisiones de Karen (2026-09-30)

1. L1: target `CompanionCopy`, con el ADR de capas de `tests-por-modulo`.
2. Canales separados: pantalla y voz en el catalogo; instrucciones al modelo
   en tablas Swift exhaustivas.
3. Los textos de permisos del sistema entran al alcance: `InfoPlist.strings`
   en/es en el bundle principal (siguen el idioma del sistema).
4. La semilla de memoria entra al alcance y se traduce.
