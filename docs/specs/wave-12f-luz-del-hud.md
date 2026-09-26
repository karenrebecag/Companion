# Wave 12f — La luz del HUD

**Estado: APROBADA (2026-09-06).** Karen: "1vamos" — morph líquido, pebble =
orb, **sin** envolver el notch (12b se mantiene: crece hacia abajo). El
marco de pantalla es 12g, no esta pieza.

Criterio de done: el ojo, hold FN, el pebble crece hasta la barra. Gates
verdes. Sin commit: Karen commitea.

---

## 1. El defecto, medido

**A. El marco salta.** `IslandPanel.present` hace `setFrame(..., display:
true)`. SwiftUI anima `.springSheet` sobre el contenido; AppKit no. 64 →
160 → 320 → 480 es un recorte, no un morph.

**B. El pebble no es el orb.** Cápsula 64×20 + punto de acento. El orb de
verdad vive a 68 pt en `ControlBar` y a 32 pt como medidor. En reposo no
se reconoce el mismo objeto.

**C. Fuera de esta pieza.** No hay marco de pantalla (12g). No se envuelve
la cámara (12b: bajo el menú, hacia el escritorio).

---

## 2. Decisión

| Decisión | Fuente |
|---|---|
| Spring en el **frame del panel**, no solo SwiftUI | metodología HUD; `springSheet` 0.32 / 0.82 |
| Colapso más rápido que la apertura | Motion HIG; `MotionTime.fast` |
| Hidden sigue `orderOut`, sin animar | 12b |
| De hidden a visible: dock instantáneo | si no, el panel vuela desde (0,0) |
| Pebble = `Orb(.idle)` al token del medidor (círculo 32) | misma presencia |
| Reduce-motion: duración 0 | `design-system.md` Motion |
| `SessionMachine`, FN, dictado, paleta del orb: no se tocan | alcance |

---

## 3. Archivos

| Archivo | Qué |
|---|---|
| `IslandChrome.swift` | pebble = `meterSide`; `dock(_:in:)` puro; `morphDuration`; `present` anima |
| `IslandView.swift` | pebble es el orb idle, no la cápsula |
| `Tests/CompanionTests/IslandChromeTests.swift` | círculo, dock, reloj del morph |
| este spec | |

Tope 4 archivos. Tokens. Comentarios solo WHY.

---

## 4. TDD

| # | Test | Espera |
|---|---|---|
| 1 | pebble width = height = meterSide | círculo, no pastilla |
| 2 | `width(for: .pebble)` es ese lado | el panel no sobra |
| 3 | `dock` centra en X, pega a `visible.maxY` | 12b intacto |
| 4 | pebble → bar, motion on | `morphExpand` (0.32) |
| 5 | bar → pebble, motion on | `MotionTime.fast` |
| 6 | cualquier → hidden, o reduce-motion, o hidden → pebble | 0 |

---

## 5. Fuera

- Envolver el notch físico
- Overlay de borde de pantalla (12g)
- Reescribir `OrbView` / partículas / `voiceInk`
- `SessionMachine`, tecla, dictado, gates 12d
- Instanciar `NSPanel` en tests (el contrato es puro)

---

## 6. Done

Hold FN: el pebble **crece** hasta la barra. Idle: el mismo orb que abajo,
dormido. Reduce-motion: el marco salta, el estado cambia. Comparar con
esta app, no con Incredible.
