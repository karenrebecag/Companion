# Wave DM0 — Línea base y arnés del modelo de decisión

**Estado: APROBADA / EN CURSO (2026-09-22).** Karen: "vamos con toda la spec". Primera wave del programa DM
(`docs/research/decision-model/README.md`, §6). Sin código de producto:
mide lo que hay y construye el conjunto contra el que se cerrarán DM2-DM5.
Sin esto no hay forma de decir "mejoró" ni de calibrar un umbral.

---

## 1. El defecto, medido

**A. No hay número propio.** El único tiempo de tool call escrito en el repo
es la traza de Incredible (`wave-14-baseline.md` §1: release→audible
5,073 ms). `TurnTimeline` mide press→mic, →ear, →ready, →partial,
release→commit y commit→audio; **no** mide cuánto tarda el modelo en
emitir la tool call ni cuánto tarda el padre en ejecutarla. "Abre Safari"
hoy tiene latencia desconocida.

**B. No hay conjunto de órdenes.** Ninguna decisión del padre es cerrada
(`sources/C-aterrizaje-en-companion.md` §1); para sustituirla por una
elección hace falta saber contra qué órdenes reales se evalúa. Los
experimentos de la discovery usaron 20 frases inventadas: sirven para
descartar, no para cerrar.

**C. Las masas 0.95-0.99 no son calibración.** Sin etiquetas no existe la
curva confianza→acierto, y sin curva el umbral de DM3 sería un número
inventado.

---

## 2. Decisión

Dos entregables, cero comportamiento nuevo para el usuario.

### 2.1 Dos marcas más en `TurnTimeline`

| Marca | Cuándo | Quién la pone |
|---|---|---|
| `.toolCallSeen` | llega el primer `.functionCall` del turno (Realtime) | `VoiceSession`, al ver `.parentActing` |
| `.toolDone` | el padre terminó de ejecutar | `VoiceSession`, al ver `.parentActed` |

La línea gana dos huecos: `commit→tool` (cuánto tarda el modelo en decidir)
y `tool→done` (cuánto tarda el código en ejecutar). Formato igual,
`—` cuando el turno no tuvo tool call. "La primera marca gana" se mantiene:
un turno con dos tools mide la primera.

Solo el camino Realtime (el hold caliente hoy, `wave-14-baseline.md`
§118). `ClassicRuntime` y el typed no marcan en v1: se anota y se
re-aprueba si hace falta medirlos.

### 2.2 El conjunto de órdenes

`docs/research/decision-model/dataset/ordenes.jsonl`, una orden por línea:

```json
{"id":"r017","texto":"abre safari","idioma":"es","accion":"open_app","args":{"app":"Safari"},"irreversible":false,"fuente":"real","notas":""}
```

- `accion` ∈ vocabulario del padre (`open_app`, `open_url`, `open_file`,
  `list_apps`, `read_skill`, `find_places`) + lo que la discovery mostró
  enumerable (`volume`, `shortcut`, `scroll`, `media`, `system`,
  `type_text`) + `task` (va al especialista) + `none` (no es una orden).
  `args` con las claves que esa acción consume, nada más.
- `fuente`: `real` = Karen la dijo o la diría tal cual; `sintetica` =
  variante escrita para cubrir un hueco (negaciones, español rioplatense
  vs mexicano, nombres de app parciales, ruido de ambiente). Objetivo
  **≥150 filas, ≥60 % reales, ambos idiomas, ninguna acción con menos de 5**.
- `irreversible: true` en lo que DM3 confirmará siempre (`empty_trash`,
  `quit_app`, enviar/submit, borrar).
- Sin datos personales: nada de contactos, rutas privadas ni contenido de
  mensajes reales; los textos a teclear son genéricos ("compra leche").

Un test lo protege: parsea el archivo, valida el schema, ids únicos,
`accion` dentro del vocabulario, los mínimos de arriba. Si Karen añade
una fila mal formada, `swift test` lo dice.

### 2.3 Protocolo de medición (manual, una vez)

30 holds reales sobre la app instalada, 10 por tipo: `abre <app>`,
`sube/baja el volumen`, `cierra esta pestaña`. Copiar las 30 líneas
`voice timeline:` a `docs/research/decision-model/baseline-2026-09.md`
con p50 y p95 de `commit→tool` y `tool→done`. Ese archivo es el "antes"
que DM3 tiene que batir.

---

## 3. Archivos

| Archivo | Qué |
|---|---|
| `Sources/CompanionCore/TurnTimeline.swift` | dos `Point`, dos huecos en `line()` |
| `Sources/CompanionServices/VoiceSession.swift` | marcar en `.parentActing` / `.parentActed` |
| `Tests/CompanionTests/TurnTimelineTests.swift` | los casos de §4 |
| `docs/research/decision-model/dataset/ordenes.jsonl` | el conjunto |
| `Tests/CompanionTests/DecisionDatasetTests.swift` | schema y mínimos, lee el jsonl por `#filePath` |
| `Sources/CompanionServices/RealtimeRuntime.swift` (§9) | `markTimeline`, dos llamadas en el ramal de tools del padre |
| `Sources/CompanionServices/VoiceSessionTimeline.swift` (§9, nuevo) | `markTool` con guarda de generación, `commitTimeline`; extracción forzada por el tope de 800 líneas |

Tope 5 archivos de contrato; los dos de §9 son desviaciones de review. `baseline-2026-09.md` lo escribe Karen con las líneas
del log (o yo, si me pega las 30 líneas). Comentarios solo WHY.

---

## 4. TDD

| # | Test | Espera |
|---|---|---|
| 1 | `mark(.toolCallSeen)` y `mark(.toolDone)` tras `committed` | `line()` trae `commit→tool N · tool→done M` |
| 2 | turno sin tool call | ambos huecos `—`, el resto igual que hoy |
| 3 | dos `.toolCallSeen` en un turno | gana la primera |
| 4 | `.toolDone` sin `.toolCallSeen` | `tool→done —`, no crash |
| 5 | dataset: cada línea parsea al schema | ninguna falla |
| 6 | dataset: ids únicos, `accion` en vocabulario, `args` solo claves permitidas | pasa |
| 7 | dataset: ≥150, ≥60 % `real`, ≥5 por acción, ambos idiomas | pasa (rojo hasta que el conjunto esté completo: es el criterio de done) |

---

## 5. Fuera

- Cualquier `DecisionProvider`, adapter, prompt o modelo (DM1+).
- Cambiar `actRule` / `delegateRule` o el vocabulario del padre.
- Marcar Classic o typed.
- Toggle, ajuste, UI.
- Descargar modelos o tocar Ollama desde la app.

---

## 6. Seguridad

- `TurnTimeline` sigue registrando solo milisegundos; nunca el texto del
  turno ni los argumentos de la tool.
- El dataset se revisa antes de commit: sin nombres reales, sin rutas
  personales, sin URLs personales. `open_file` solo acepta rutas bajo
  `$HOME` (`ParentToolPolicy.homePath`), así que sus filas sintéticas usan
  nombres genéricos (`~/Documents/notas.txt`); lo prohibido es un nombre
  que identifique a alguien, no el prefijo. `fuente: real` describe el uso,
  no lo transcribe.

---

## 7. Done

- 30 líneas `voice timeline:` con `commit→tool` y `tool→done` en
  `baseline-2026-09.md`, con p50/p95.
- `ordenes.jsonl` ≥150 filas y el test 7 en verde.
- Gates verdes. Sin commit: Karen commitea.
- ROADMAP: fila DM0 con los dos números.

---

## 8. Decisiones tomadas sin preguntar (anotadas)

- JSONL en `docs/research/` leído por `#filePath`, no un fixture Swift ni
  un `resources:` del target de tests: 150 filas se editan mejor a mano y
  el test lo valida igual.
- Vocabulario de `accion` = padre + enumerables de la discovery. Si DM1
  recorta, el test se ajusta ahí.

---

## 9. Desviaciones (EN CURSO, 2026-09-22)

- **Sexto archivo: `RealtimeRuntime.swift`.** `.parentActing`/`.parentActed`
  son `SessionEvent` y `VoiceSession` no consume su propia corriente (la
  cablea a la UI). Un *tap* sobre esa corriente habría sido una tarea más,
  un salto extra por evento y un ciclo de vida que cuidar. En su lugar, el
  runtime expone `markTimeline: (@Sendable (TurnTimeline.Point) async ->
  Void)?` junto a `onStopJob`/`onDelegate`, y la sesión marca. Tres líneas
  en el runtime, cuatro en la sesión.
- **Test 7 envuelto en `withKnownIssue`.** Un rojo permanente en `main`
  bloquearía los gates de todo lo demás. Swift Testing registra el hueco
  sin fallar la suite. Al cerrar DM0 (≥60 % reales) el wrapper se quita;
  hasta entonces la suite dice "1 known issue".
- **Solo 4 filas `real`.** El agente que redactó el conjunto marcó 10; se
  reclasificaron 6 que Karen nunca dijo. Las reales son las que están en
  los docs: "abre safari, puedes?", "cines cerca de Reforma", "crea un
  archivo", "abre Safari". El resto (167) es sintético y espera su
  reclasificación fila a fila.
- `VoiceSession.swift` queda en 800 líneas, el tope duro del Gate 2.
  Partirlo no es de esta wave; la siguiente que lo toque tendrá que hacerlo.
- **Review 2026-09-22.** code-reviewer: REQUEST_CHANGES — `markTool` sin
  guarda de generación (HIGH): una respuesta de tool del turno N que llega
  cuando ya empezó el hold N+1 marcaba la cronología equivocada. Fix: la
  generación se captura en el commit (`commitTimeline`) y `markTool` descarta
  si cambió; `VoiceSession.swift` estaba en 800 líneas justas, así que
  `markTool`/`commitTimeline` viven en `VoiceSessionTimeline.swift`.
  security-reviewer: APPROVE con un MEDIUM — `s154` ("envia un email",
  `task`) sin `irreversible`; la regla entra al test 6 (todo `task` cuyo
  goal envía/borra/paga es irreversible) y la fila se corrige.

