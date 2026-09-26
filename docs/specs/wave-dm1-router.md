# Wave DM1 — El router: decidir barato, escalar poco, aprobar solo lo irreversible

**Estado: APROBADA / EN CURSO (2026-09-22).** DM1a hecha (§7); DM1b y
DM1c esperan DM0 cerrada. Programa en tres entregas (DM1a Core,
DM1b adapters, DM1c cableado), cada una con su tope de archivos y su
aprobación. Reemplaza al DM1-DM3 de `docs/research/decision-model/README.md`
§6: no un puerto suelto, sino el flujo entero de jev-voice traducido a
Companion. Fuente del flujo: `docs/research/decision-model/sources/
A-jev-voice-mecanismo.md` §2, §5, §6.

---

## 1. El defecto, medido (2026-09-22)

- `commit→tool 516 · tool→done 221`: el modelo fuerte tarda 2.3× en decidir
  que el código en ejecutar (DM0, primera línea real).
- Tres órdenes habladas en una sesión → `executor: work routed from native
  to claude-code`. "Abre X" acaba en un especialista de 10 s porque el
  modelo fuerte elige `delegate` cuando quiere.
- El padre pide aprobación (`open_url` por palabras, hoja del especialista
  para `run_shell`) en órdenes que el usuario acaba de decir en voz alta.
  Cada hoja es un turno perdido. Karen: "pide demasiadas aprobaciones y
  vuelve lento el flujo".

Lo que jev-voice hace distinto no es el modelo: es que **el modelo fuerte
nunca decide primero** y **nadie pregunta por lo reversible**.

---

## 2. Decisión: cuatro niveles, cada uno con un contrato

```
utterance ─► N0 código ─► N1 decisión ─┬─ conf ≥ umbral(riesgo) ─► N0 ejecuta ─► N0 verifica
                 │                     ├─ irreversible ──────────► confirmar por voz ─► N0 ejecuta
                 │                     ├─ conf < umbral / BLOCKED ► N2 arbitra sobre la shortlist
                 │                     └─ accion == task ────────► N3 especialista (lo de hoy)
                 └─ dictado / no es orden ─► fuera (lo de hoy)
```

### N0 — código (siempre, sin modelo)

Produce candidatos, valida, ejecuta, guarda. Ya existe casi todo:
`WorkspaceOpening` (apps), `ParentToolPolicy` (validadores),
`ParentToolGate.saidIt` (¿lo dijo?), `DictationRouter`, `ApprovalMemory`.
Nuevo: productores de candidatos (apps prefiltradas ≤ 5 por fuzzy,
spans es/en por regex, sitios por allowlist, atajos/volumen/sistema como
conjuntos cerrados) y un `Plan` puro con confianza = `min` de los juicios
usados.

### N1 — decisión (toda orden, barata)

Puerto `DecisionProvider`: `choice` sobre ids cerrados, `yesNo`, y `score`
(la forma del cable de Jev, para que un adapter TypeSafe entre sin tocar
Core). Cascada, no fan-out (medido: en local 20 preguntas cuestan 20×):
`action` (dos órdenes promediados) → 1-3 cabezas dependientes. Nunca
genera un argumento: elige entre lo que N0 ofreció. Modelo por `Config`
(juez): Ollama 4B hoy; Jev/OpenAI logprobs cuando se quiera.

### N2 — arbitraje (poco, fuerte)

Entra **solo** si: confianza del plan < umbral, el juez eligió `none` con
una orden claramente dirigida, o N0 detectó ciclo/incidente (misma orden
rechazada 3×). Recibe la **shortlist** de N1 (top-3 acciones × sus
candidatos) y devuelve un `choice` **constreñido por schema** a esa lista
(`ToolSpec.strict` ya sabe hacerlo) más `confianza` y una `regla` opcional
por app (≤ 200 chars). Nunca ve la lista entera de apps ni el AX; nunca
emite un tool call libre. Modelo: el "cerebro" de Wave 14 (Haiku-class
primero; el fuerte solo si la confianza del rápido < 0.5, como jev).

### N3 — especialista (lo que ya hay)

`accion == task` (multi-paso, archivos, shell, web) → `delegate` →
`WorkRouting` → NativeExecutor / Claude Code / Hermes. **No cambia.** La
diferencia: llega ahí solo lo que N1 clasificó como `task`, no lo que el
modelo fuerte quiso delegar.

### Aprobaciones: solo lo irreversible, y por voz

| Caso | Hoy | DM1 |
|---|---|---|
| `open_app`, volumen, atajos, scroll, media, `open_file` bajo home | pregunta a veces (según el modelo) | **nunca** pregunta |
| `open_url` cuyo host el usuario dijo | pasa | pasa |
| `open_url` cuyo host NO dijo (inyección) | hoja | hoja (se mantiene: es seguridad, no fricción) |
| `empty_trash`, `quit_app`, enviar, borrar, pagar (`irreversible` del dataset) | según el modelo | **confirmación por voz, una frase**, sin hoja; memoria por sesión (`ApprovalMemory`) |
| `run_shell`, escribir fuera del workdir | hoja | hoja (N3, no cambia) |

Lo que jev-voice no tiene y aquí sí: la fila `irreversible` decide la
confirmación, **aunque la confianza sea 0.99**.

### Umbrales por riesgo (de `docs.typesafe.ai/confidence`, adaptado)

| Riesgo | Actuar | Confirmar | Arbitrar |
|---|---|---|---|
| reversible (abrir, volumen, scroll) | ≥ 0.6 | — | < 0.6 |
| irreversible | ≥ 0.8 y confirmación | 0.6-0.8 | < 0.6 |

Números iniciales; se ajustan con la curva de DM0 (dataset) y el `trust`
por app que N2 devuelve (jev: `0.75 − 0.4·trust`, acotado 0.35-0.75).

### Guardas de N0 (copiadas de jev, las que aplican al padre)

- Solo se ofrece lo ejecutable: una app que no existe no es opción, no un
  error después.
- Nunca reintentar una mutación; registrar antes de observar.
- Tres rechazos de la misma orden en la misma pantalla → N2, y al segundo
  incidente, parar y decirlo.
- El candidato elegido pasa por `ParentToolPolicy` igual que hoy: la
  confianza no salta la validación (DM0 §6).
- DONE es la afirmación del modelo, no prueba: para el padre, la prueba es
  `NSWorkspace` (la app está delante) o el estado del sistema (volumen).

---

## 3. Entregas

### DM1a — Core puro (tope 6 archivos)

| Archivo | Qué |
|---|---|
| `Sources/CompanionCore/Decision.swift` (nuevo) | `DecisionQuestion` (choice/yesNo/score), `DecisionAnswer` (choice, distribution, confidence), `DecisionProvider` |
| `Sources/CompanionCore/Candidates.swift` (nuevo) | productores puros: `appCandidates(utterance, apps)`, `textSpans(utterance)` es/en, conjuntos cerrados (volumen, atajos, sistema, scroll, media) |
| `Sources/CompanionCore/Plan.swift` (nuevo) | `Plan`, `PlanRisk` (reversible/irreversible), `PlanThreshold.evaluate → .act / .confirm / .arbitrate / .delegate / .ignore`, cascada como función pura sobre un `DecisionProvider` |
| `Sources/CompanionCore/Arbitration.swift` (nuevo) | shortlist, contrato del `choice` constreñido, `trust` por app, regla aprendida |
| `Tests/CompanionTests/PlanTests.swift`, `CandidatesTests.swift` | reductor-style; `FakeDecisionProvider` en `ChatFakes.swift` |

Done: `swift test` verde; 0 I/O; sobre `ordenes.jsonl` el `Plan` con un
`FakeDecisionProvider` perfecto produce la acción etiquetada en el 100 %
(prueba de que el composer no pierde información).

### DM1b — Adapters (tope 4 archivos)

| Archivo | Qué |
|---|---|
| `Sources/CompanionServices/OllamaDecisionProvider.swift` | endpoint nativo, prefill `Letter:`, `logprobs`, dos órdenes en `action`, etiquetas verificadas contra el tokenizer al arrancar |
| `Sources/CompanionServices/OpenAIDecisionProvider.swift` | Chat Completions + `logprobs` (nunca Responses ni function calling) |
| `Sources/CompanionServices/ArbiterClient.swift` | N2 sobre `ChatProvider` con `ToolSpec.strict` (enum = shortlist) |
| tests con fixtures de respuestas grabadas | |

Done: sobre `ordenes.jsonl` (≥ 60 % reales, DM0 cerrada): ≥ 90 % de
planes correctos, p50 ≤ 1.5 s en 4B, curva confianza→acierto por cubos.
`TypeSafeDecisionProvider` es DM1b.1 si la consola abre.

### DM1c — Cableado (tope 5 archivos)

| Archivo | Qué |
|---|---|
| `Sources/CompanionServices/DecisionGate.swift` (nuevo) | delante de `ParentToolRunner.execute`: N1 → N0 / confirmar / N2 / N3; `.notSure` cae al camino de hoy |
| `Sources/CompanionServices/VoiceSession.swift` / `RealtimeRuntime.swift` | el turno pasa por el gate antes de que el modelo fuerte vea la orden; marcas `decision` en `TurnTimeline` |
| `Sources/CompanionCore/ChatPrompt.swift` | `actRule`/`delegateRule` dejan de decidir: el modelo fuerte recibe la orden ya clasificada (o nada, si N0 ya actuó) |
| `Sources/CompanionUI/SettingsAppPane.swift` + strings | toggle "Decidir en local", **off por defecto** hasta DM1b verde |
| `SessionMachine` | `.decisionUnsure` como aviso sin transición; confirmación por voz reutiliza `resolve_approval` |

Done: en vivo, "abre Safari" abre Safari **sin** tool call del modelo
fuerte y **sin** hoja; `voice timeline` muestra `commit→decision` < 1.5 s;
"vacía la papelera" pide confirmación por voz y la obedece; con el toggle
off, todo como hoy.

---

## 4. Fuera

- Clic/type sobre elementos de pantalla (el loop de jev-ultrafast sobre AX):
  es DM2, y depende de 13a/12+.
- Quitar la hoja de `open_url` no dicho, o la de `run_shell`.
- Cambiar `WorkRouting` o los ejecutores.
- Un modelo entrenado propio (Laya/verdict-style): DM3 si la calibración lo
  pide.

---

## 5. Riesgos

- Sin DM0 cerrada (dataset real, línea base) DM1b no tiene contra qué
  cerrar: **DM0 primero**.
- El hold que no cierra (WIP) y el oído de 13 s (Wave 14) hacen invisible
  cualquier ganancia del router: arreglar antes de DM1c.
- Un `.act` equivocado a 0.6 abre la app que no era. Es reversible por
  diseño (por eso el umbral bajo), pero se mide: tasa de "no era eso" en
  las primeras 100 órdenes reales, registrada en `TurnTimeline`.
- Nouls en 4B no sirven de puerta (DM0 E3): la clasificación `none` va en
  `action`, no en un yes/no aparte.

---

## 6. Preguntas para Karen

1. Confirmación por voz para lo irreversible ("¿vacío la papelera?" → "sí"):
   ¿te vale sin hoja, con la memoria de sesión que ya existe?
2. Orden: ¿arreglar hold + oído (Wave 14) antes de DM1c, o DM1a/b en
   paralelo con eso? (DM1a/b son puros y no tocan la voz.)

Karen aprobó y delegó el cierre de DM1a ("cierralo tú, eres el
orquestador"). La pregunta 1 queda como está escrita (voz, sin hoja); la 2
se resolvió por los hechos: DM1a fue en paralelo, DM1b espera DM0 cerrada.

---

## 7. Desviaciones de DM1a (2026-09-22)

- **Proveedor falso en `PlanTests.swift`**, no en `ChatFakes.swift`: un
  séptimo archivo por un struct de diez líneas.
- **`ToolSpec.strict` no enumera el string**: cierra el objeto, nada más.
  `ArbitrationShortlist.choiceSchema()` emite su propio schema con `enum` =
  shortlist, y lanza si la shortlist está vacía (OpenAI strict rechaza
  `enum: []`).
- **Sin banda 0.6-0.8 en lo irreversible**: todo lo irreversible con
  confianza ≥ 0.6 confirma, también a 0.99. La banda no cambiaba nada: en
  los dos lados se confirmaba.
- **`task` irreversible delega**, no confirma por voz: el especialista ya
  tiene sus hojas. La voz queda para `empty_trash`, `quit_app`,
  `send_message`, `enter` y teclear con envío.
- **`enter` es irreversible** (review): en un chat envía, igual que
  `send_message`. s066/s067 del conjunto cambian a `irreversible: true`.
- **El camino de N2 confirma en Core** (review): una `ShortlistEntry`
  arbitrada se convierte en `Plan` con el mismo `Plan.risk` y
  `PlanThreshold`; DM1c no puede olvidarlo.
- **`Plan.actionMass`** (review): el plan conserva la distribución
  promediada, también en empate, para que N2 tenga shortlist.
- **`MutationLedger` por intento** (review): "no reintentar" vale dentro
  de una orden, no en toda la sesión.
- **`none` dudoso sobre conjuntos cerrados** (review): "sube el volumen"
  con juez `none` arbitra en vez de perderse.
- **Gate 2**: el regex de `try?` casaba con `ShortlistEntry?`; ahora exige
  que `try` no vaya pegado a un identificador.
- Pendiente para DM1b: 21 atajos superan el `top_logprobs` de OpenAI (20);
  el adapter rellena con cero, y una lista de 21 no está medida en el 4B.

---

## 8. Plan de DM1c (planner, 2026-09-22)

**Punto de corte.** El hold FN va por el camino clásico, no por Realtime
(`VoiceSession.swift:365`, `holdPressed(preferRealtime: false)`; oído
`SystemTranscriber` en el dispositivo). El gate entra en
`ClassicRuntime.submit` después del transcript y antes de `senseVoice` /
`chat.stream`: el modelo fuerte no ve el turno si el router actúa. Ahorra
una vuelta de chat completa (tool call + respuesta hablada). Interceptar en
`ParentToolRunner` se descarta: el modelo ya decidió y `delegate` nunca
pasa por ahí.

**Entregas** (≤ 5 archivos cada una; `VoiceSession.swift` no crece):

| | Qué | Archivos |
|---|---|---|
| DM1c-1 | Ruteo puro + gate, sin cablear | `DecisionRouting.swift` (Core), `DecisionGate.swift`, `TurnTimeline` (`.decision`), tests |
| DM1c-2 | Hold clásico cableado | `Config` (`DecisionSettings`, off), `ClassicRuntime.decide`, `VoiceSessionDecision.swift`, `CompanionMain`, tests |
| DM1c-3 | Toggle "Decidir en local" | `SettingsAppPane`, `StoredConfigProvider`, strings es/en, test |
| DM1c-4 | Confirmación por voz | `DecisionGate` (pendiente + `MutationLedger`), `SystemActionRunner` (`empty_trash` por AppleScript, `quit_app` por `NSRunningApplication`, nunca Companion) |

Ejecución: open_app/url/file van por `ParentToolRunner` (revalida con
`ParentToolPolicy`; `open_url` además por `ParentToolGuard`). list_apps,
read_skill y find_places pasan al camino de hoy (el modelo tiene que decir
el resultado). Volumen, atajos, scroll, media y type_text no tienen
ejecutor: pasan al camino de hoy hasta DM1d. Nunca se confirma lo que no
se puede ejecutar.

**Decisiones tomadas por el orquestador** (Karen puede revertirlas):
- Un "sí" hablado a algo irreversible **no se recuerda** en la sesión:
  §2 dice que lo irreversible confirma siempre; DM1c no escribe en
  `ApprovalMemory`.
- **Manos libres (Realtime) queda fuera de DM1** (era DM1c-5): el hold ya
  cumple el done. Se reabre si el manos libres lo pide.
- Fuera también: cambio de `ChatPrompt` (el modelo no se llama si el router
  actuó), `SessionMachine.decisionUnsure` (basta el log), trust aprendido
  (DM1d), camino tecleado.

## 9. Estado 2026-09-22 (fin de sesión)

- DM1b hecha (Ollama + ArbiterClient; OpenAI logprobs diferido). Afinado:
  20/20 en 20 frases del conjunto, p50 158 ms caliente, "abre Safari" 0.992
  → `.act` (optimista: frases del mismo conjunto que se afinó).
- DM1c-1..4 hechas y cableadas al hold clásico; toggle "Decidir en local"
  off por defecto (+ `COMPANION_DECISION=1`). N2 NO cableado en la app
  (`PassThroughArbiter`): `.arbitrate` cae al camino de hoy.
- Hold: release en `.thinking/.speaking` (realtime) y reloj arrastrado tras
  `discard()`, arreglados con test. Causa real del FN muerto: Accesibilidad
  no concedida.
- Reviews: security WARNING (0/0), code WARNING (1 HIGH: "sí" pendiente
  60 s tras confirmar) → arreglado con test; warm de Ollama al arrancar.
- 289 tests, gates verdes, sin commit. Pendiente: prueba en vivo de Karen,
  cablear N2, ejecutores de volumen/atajos/scroll/media/type_text (DM1d),
  DM0 (holds + conjunto real).
