# R-05 — Contrato de reticula

**Estado: CONSTRUIDO** (2026-08-24), pendiente de veredicto de Karen.
Capa: proceso. No depende de los demas R.

## Objetivo

Cerrar la fuga por la que se escapo la reticula, y que el gate deje de
afirmar cosas falsas.

## Que cambio respecto al plan original

El spec original decia: ampliar los `grep` de `gates.sh` y ponerlo **al
final**, porque "un gate que falla en 28 sitios el dia que se enciende no es
un gate, es ruido; primero 01-04 dejan la casa limpia".

Ese razonamiento tenia un defecto: un gate que espera a que la casa este
limpia **no se enciende nunca**, y mientras tanto entra deuda nueva.

El modelo de `ATOMUIKIT/atom-uikit-ds/conformance` lo resuelve con un
**ratchet**: se mide la deuda por archivo, se congela como `baseline`, y a
partir de ahi solo puede bajar. El gate se enciende HOY, con 86 infracciones
dentro, sin fingir que el pasado es perfecto. Por eso R-05 dejo de ir al
final y se construyo primero.

## Referencia

`ATOMUIKIT/atom-uikit-ds/conformance/` — `css-contract.json` y
`scripts/conformance.mjs`. Tres ideas que se portan enteras:

1. **El contrato es data, el runner es tonto** (modelo Willison). Relajar una
   regla obliga a tocar el JSON, y eso se ve en el diff; un literal enterrado
   en una vista no.
2. **Ratchet, no big-bang.** Empeora → falla. Mejora → nota para bajar el
   numero.
3. **Cada regla lleva su `why`**, y es lo que se imprime al fallar.

## Lo que el gate viejo no veia (medido 2026-08-24)

```
regla de gates.sh:  cornerRadius\([0-9]     →  0 hits
la forma real:      cornerRadius: *[0-9]    →  9 hits en 5 archivos
```

`RoundedRectangle(cornerRadius: 8)` lleva dos puntos, asi que no matcheaba. Y
es la forma **mas comun** del repo: `.cornerRadius(x)` esta deprecado en
SwiftUI, nadie lo escribe. El gate llevaba tiempo diciendo "sin literales de
cornerRadius" con nueve enfrente.

Igual con el copy: la regla exigia la comilla pegada a `Text(`, asi que se
escapaban cuatro sitios en espanol duro — dos de ellos en el chrome
principal, no en las tarjetas del modelo:

```swift
StatusLine.swift           Text(chat.queued.count == 1 ? "En cola: ..." : "... en cola")
ShortcutCaptureField.swift Text(isCapturing ? "Escuchando..." : displayText)
MapCard.swift              Text(block.title ?? "Ubicaciones")
SourcesCard.swift          Text(ext.isEmpty ? "Archivo" : "Archivo \\(ext)")
```

Total real: **86 infracciones en 23 archivos**, con el gate en verde.

## Archivos

- `conformance/ui-contract.json` (reglas, exenciones, baseline)
- `conformance/README.md`
- `Tests/CompanionTests/ConformanceTests.swift` (runner)
- `scripts/gates.sh` (deuda visible en Gate 3; Gate 4 la aplica)

## Contrato

Siete reglas, cada una con su motivo escrito:

| regla | que caza | deuda |
|---|---|---|
| `radius-literal` | `cornerRadius(8)` y `cornerRadius: 8` | 9 |
| `frame-literal` | medidas de lienzo a mano en `.frame` | 16 |
| `space-arithmetic` | `Space.x1 * 52`, `Space.x1 / 2` | 43 |
| `system-font` | `.system(size: 12)` | 4 |
| `role-opacity` | `Semantic.X.opacity(...)` | 8 |
| `raw-duration` | `duration: 0.2` | 3 |
| `copy-literal` | `Text(x ?? "...")`, ternarios | 4 |

Tres valvulas, todas con motivo obligatorio: `// token-exempt: <por que>` por
linea, `exemptFiles` por archivo generado, `baseline` para deuda triada.

El escaner **une las lineas de una llamada partida**: sin eso `.frame(` arriba
y `width: 16` abajo no matchean nada y el archivo se reporta limpio. Descarta
comentarios puros. No entiende Swift — son regex sobre texto, y un caso gris
se triage con baseline o exempt, nunca bajando la regla.

## Portar

- Las tres ideas de ATOMUIKIT (data / ratchet / why).
- El formato de salida `OK` / `FAIL` / `nota`.

## Fuera

- Ampliar el contrato a color o motion mas alla de `duration`. Un eje por vez.
- `CompanionCore` y `CompanionServices`: el contrato es de `CompanionUI`.
- Limpiar la deuda. El ratchet la congela; bajarla es trabajo de R-02, R-03,
  R-04, R-06 y de la pieza pendiente de los widgets de chat.

## Reescribir

- Los dos `pass` de Gate 3 mentian sobre su alcance. No estaban mal en lo que
  verifican; estaban mal en lo que **afirmaban**. Ahora dicen exactamente
  hasta donde llegan y quien cubre el resto.

## Hallazgos

- Cero falsos positivos en las 86: se revisaron los hits de las cuatro reglas
  mas dudosas uno por uno antes de congelar el baseline. Un baseline de falsos
  positivos es peor que no tener gate.
- Dos casos grises quedaron en baseline a proposito, no exentos:
  `Orb/RotatingGlowView.swift` usa `duration: 360 / rotationSpeed` (periodo
  derivado, no duracion de motion) y `Pressable.swift` pasa
  `Semantic.surface.opacity(PressMotion.fillOpacity(...))` (alfa con nombre,
  pero sigue siendo estado como alfa cuando `Semantic.hover` ya existe). Los
  decide R-04.
- `AttachmentViews.swift` concentra 12 de las 43 aritmeticas sobre `Space`, y
  `HeaderView.swift` 11. Son los dos primeros candidatos cuando se empiece a
  bajar el baseline.
- El runner se salta el escaneo si no encuentra `conformance/` desde
  `#filePath`: compilar el paquete fuera del checkout no debe fallar el test,
  pero tampoco pasar en silencio fingiendo que escaneo algo.

## Done

Verificado por mutacion en las dos direcciones:

- Meter `RoundedRectangle(cornerRadius: 8)` en `Toasts.swift` (limpio) →
  `FAIL  Toasts.swift — radius-literal 1 > baseline 0` con el motivo.
- Quitar el `frame(maxWidth: 280)` que el baseline conoce → pasa con
  `nota  Toasts.swift: frame-literal bajo a 0 (baseline 1) — baja el baseline`.

`./scripts/gates.sh` verde, 206 tests. La deuda es visible en cada corrida y
solo puede bajar.
