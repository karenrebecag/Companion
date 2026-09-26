# Modelo de decisión para Companion — investigación

Fecha: 2026-09-22. Estado: DISCOVERY (no es spec; precede a una). Máquina de pruebas: M4 Max, 36 GB, macOS 26.5, Ollama 0.34.

Pregunta que abrió esto: jev-voice (kevinbadi) y jev-ultrafast (browser-use) resuelven "abre Safari, escribe X, busca Y" con un **modelo de decisión** (el modelo elige entre candidatos que produce el código y devuelve una distribución de probabilidad) en vez de con tool calls generativas. ¿Es mejor arquitectura para el 90 % de lo que Companion hace sin especialista, y se puede tener en local?

Respuesta corta: **sí al patrón, no al runtime.** El patrón (el modelo nunca emite un argumento, siempre elige; la confianza es una distribución real; el código produce candidatos, valida y ejecuta) se porta a Swift y ataca fallos que ya están documentados en este repo. Lo que no se porta es el fan-out de 20 preguntas en 250 ms: eso es una propiedad del servidor de TypeSafe, no del patrón. En local, con lo que hay en esta máquina, la forma correcta es una **cascada de 2-5 preguntas con candidatos acotados en código**, que midió **1.4 s de media con 18/20 planes correctos** sobre un Qwen3 4B. Es usable, no es "ultrafast", y deja el enchufe listo para un proveedor rápido (TypeSafe u otro) el día que exista.

Los cuatro informes de fondo están en `sources/` (mecanismo de jev-voice con file:line; TypeSafe, proveedores y literatura de calibración; aterrizaje en este repo con file:line; ecosistema de reproducciones abiertas). Los scripts de `experiments/` reproducen todos los números de abajo.

---

## 1. El patrón, con precisión

Lo que jev-voice hace (referencias en `sources/A-jev-voice-mecanismo.md`):

1. **Select, don't generate.** Cada valor libre se convierte en una elección. Apps: la lista real instalada. Sitios, atajos (48), carpetas: conjuntos cerrados en código. El texto a teclear: **spans cortados del transcript por regex** (`brain.py:82-125`), el modelo elige cuál es exactamente el payload. En el loop de agente, cada nodo del árbol de Accesibilidad se indexa y el modelo elige un índice; **nunca emite selectores, coordenadas, scripts ni shell**.
2. **Solo se ofrece lo ejecutable.** `action_space()` (`policy.py:73-108`) construye el menú de operaciones *a partir del mismo dict* que guarda los targets válidos: una operación sin target en esta pantalla no existe como opción. No es un `if`, es una comprensión sobre la misma fuente.
3. **La confianza es una distribución, no una opinión.** `validate_choice` (`policy.py:55-70`) rechaza la respuesta si las probabilidades no cubren exactamente los ids ofrecidos, no suman 1 (±0.02) o la elegida no es el argmax. La confianza del plan es `min` sobre los juicios usados (`brain.py:317-371`); bajo 0.35 dice "not sure" y no toca nada.
4. **Fan-out especulativo.** Una petición lleva las 20 preguntas (`brain.py:180-283`); `_to_plan` lee solo las que la acción elegida necesita y tira el resto. Se paga en tokens para no pagar dos viajes de red.
5. **Guardas de código, cero modelo.** Frescura (re-leer rol/valor/enabled, re-resolver geometría, hit-test del centro antes de tocar), poda de modales, retirada de acciones cíclicas o fútiles, BLOCKED dubitativo que ejecuta el segundo mejor de la *misma* respuesta, DONE es "la afirmación del modelo, no prueba", presupuestos (40 acciones / 80 llamadas), "nunca reintentar una mutación", "registrar antes de observar".
6. **Híbrido 90/10.** Solo en el driver de navegador: Claude (Haiku, luego Fable) entra si BLOCKED, confianza < 0.6 (ajustada por sitio), ciclo detectado o incidente; y **arbitra sobre la shortlist de Jev**, con el `choice` constreñido por schema a esos candidatos. Nunca ve la tabla cruda ni genera una acción. Lo único que Claude genera libremente es el valor de TYPE_TEXT.

Lo que **no** copiar de jev-voice: `brain.py` no valida la respuesta (asimetría con `policy.py`); no hay confirmación para acciones irreversibles (`empty_trash`, `quit_app`, enviar mensaje) más allá del 0.35 plano; ~15 `except Exception` que degradan la escalación en silencio; el driver desktop no verifica DONE; `web.py` (1125 líneas, toda la escalación y las guardas) no tiene tests.

---

## 2. TypeSafe, proveedores y calibración (lo verificado)

Detalle y URLs en `sources/B-typesafe-y-viabilidad-logprobs.md` y `sources/D-ecosistema-openjev.md`.

- **Jev** (TypeSafe, lanzado 2026-09-15): `POST /v1/systemone` con `state` + `questions` de tipo `choice` (≤255 opciones), `noul` (0-1) y `score` (≤10 niveles). Responde `{choice, probabilities, confidence}` por pregunta. `confidence` es una estadística de la distribución: `(3·p_max − 1)/2` para 3 opciones (la generalización `(n·p_max − 1)/(n − 1)` es nuestra, no de ellos). $0.042 / MTok de entrada, salida gratis; 70-500 ms declarados, 170-420 ms medidos por jev-voice. Entrenamiento propietario ("RLCD"), arquitectura no divulgada. Fuentes secundarias dicen que la waitlist se retiró el 2026-09-21 con $5 de crédito; la consola mostró "we're full" el 22. Reintentar.
- **Distribución real con logprobs**: OpenAI Chat Completions (`logprobs` + `top_logprobs` ≤ 20; **no** en Responses API, **no** combinable con function calling); OpenRouter la pasa en ~23 % de endpoints y descarta el parámetro en silencio en el resto; **Anthropic: no**; **Groq: no**; Cerebras, Fireworks, Together: sí. **Ollama**: el endpoint nativo `/api/chat` la devuelve (verificado aquí en 0.34.0) y `/v1` también, pero `/v1` no acepta `think:false`, así que con modelos *thinking* el primer token es prosa. **Apple Foundation Models**: sin logprobs; solo generación guiada (`@Generable`) y una confianza verbalizada auditada en AUROC 0.47.
- **Calibración**: la literatura (Tian 2023, informe GPT-4 fig. 8, ICLR 2026 "semantic calibration") dice que el RLHF degrada la calibración de los logprobs y que en modelos instruidos la confianza verbalizada puede calibrar mejor. **Nadie en el ecosistema que envuelve un chat model con prefill afirma calibración**; dos lo desmienten explícitamente. Los únicos que la reportan son modelos entrenados a propósito: Laya (421M, ECE 0.081) y openJev-verdict-2.0 (150M, ECE 0.014 en la cabeza de confianza), y sobre un solo benchmark sintético (`LocalLLaMA/typed-decisions`) donde el propio Jev saca 72.7 %.
- **Reproducciones abiertas**: seis repos en una semana. Las portables a Apple Silicon: `zhihz/openjev` (Qwen3-4B en MLX, 533 ms/petición en M3, secuencial, sin caché compartida), `bnsd55/jevmlx` (librería MLX, softmax restringido, ~0.6 s/decisión en M5 Max con 7B), `razorback16/openjev` (DiffusionGemma 26B no autorregresivo, backend MLX, **0.39 s por petición de 3 preguntas en M4 Max**). Ninguna aporta algo que no tengamos ya con el truco de prefill; lo que vale la pena tomar es la **forma del cable** (choice/noul/score) para que el adapter local sea intercambiable con un servidor compatible.

---

## 3. Experimentos en esta máquina

Todos con las **preguntas reales de `jev_voice/brain.py`** (15 acciones, 48 atajos, etc.) contra Ollama nativo, `think:false`, `num_predict=1`, `temperature=0`, `top_logprobs=20`, etiquetas de una sola letra y prefill del asistente `Letter:`. Masa = fracción de probabilidad que cayó en etiquetas válidas antes de renormalizar.

| # | Qué | Modelo | Resultado |
|---|---|---|---|
| E1 | Cabeza `action`, 10 frases en/es | qwen3.6:27b | **10/10**, masa 1.00, incertidumbre informativa ("what time is dinner" → none 0.59 / web_search 0.29). **~3.1 s por pregunta**: Ollama re-evalúa los 551 tokens del prefijo en cada petición (arquitectura `qwen35`, no reutiliza prefijo); con prompt idéntico baja a 180 ms |
| E2 | Igual | qwen3:1.7b | 30 ms por pregunta (aquí sí reutiliza prefijo) pero **3/8**. Demasiado chico |
| E2b | Igual | qwen3:4b | Sin prefill ignora `think:false` y arranca prosa ("First", "We"). Con prefill `Letter:` → open_app 0.99, none 0.995, shortcut 0.95 |
| E3 | **Fan-out completo: 20 preguntas → `brain._to_plan` real**, 15 frases en/es | qwen3:4b | **13/15 acciones correctas** (falla "busca en youtube…" → none y no detecta el compuesto). Spans, submit, engine, dirección, volumen, sistema: correctos. **3.0-3.5 s por frase**; secuencial ≈ concurrente (Metal serializa). Nouls poco fiables: `addressed` 0.95-0.98 incluso para "what time is dinner", `recommend` siempre true |
| E4 | Menús fijos en un prefijo cacheado (10.9k chars), utterance al final | qwen3:4b | **1.6 s** por frase (2×) pero la precisión cae (scroll → open_app 0.47), nouls al azar (0.4-0.6), masa fuera de etiqueta hasta 0.68. Contexto largo + letras reutilizadas confunden al 4B |
| E5 | Cabeza `app` con 48 apps ofrecidas (Safari y Comet dentro) | qwen3:4b | **Falla**: "abre safari" → ChatGPT 0.41 / none 0.37 / Safari 0.18; "switch to slack" → none 0.69. La indirección letra→ítem en listas largas no funciona en un 4B |
| E6 | Sesgo de posición: mismo menú en orden inverso | qwen3:4b | Cambia respuestas ("what time is dinner": none 0.99 vs type_text 0.61; 4 frases en español pasan de none a la correcta al invertir). **Promedio de los dos órdenes: 14/15** |
| E7 | **Cascada**: `action` (2 órdenes promediados) → solo las cabezas que esa acción consume; apps **prefiltradas en código** (fuzzy, ≤5) antes de preguntar | qwen3:4b | **1.39 s de media, 2-5 llamadas, 18/20 planes correctos** en 20 frases en/es. "abre safari" → Safari, "switch to slack" → Slack, "abre finder" → Finder, "mute" → volume(mute) 0.99, "open my downloads folder" → open_folder 0.96. Fallos: "busca en youtube" queda en engine=google con el texto entero (regex de spans de jev es solo inglés) y el compuesto "open notes and type…" no se parte (noul `compound` débil) |

Notas honestas: n pequeña (15-20 frases), sin conjunto etiquetado; las masas 0.95-0.99 son **nitidez**, no calibración (no sabemos si 0.97 acierta el 97 % de las veces); llama.cpp de brew no carga el blob `qwen35` del 27B, así que la reutilización de prefijo con el modelo grande queda sin medir en local; `qwen3:1.7b` y `qwen3:4b` se descargaron para esto (`ollama rm` si estorban).

---

## 4. Qué significa para la arquitectura

1. **El fan-out especulativo es del runtime, no del patrón.** Jev responde 20 preguntas en un forward batcheado. En un Mac con Ollama, 20 peticiones cuestan 20× y concurrente no ayuda. Localmente conviene la **cascada**: `action` primero, luego 1-3 cabezas dependientes. Se pierde paralelismo que aquí no existía; se gana 2-3×. Con un proveedor que sí batchee (TypeSafe), el mismo puerto vuelve a fan-out.
2. **El código acota, el modelo elige.** Un 4B elige bien entre ≤ 8-10 opciones y mal entre 48. Antes de preguntar: apps por fuzzy match (Companion ya tiene `resolveApp` en `ParentToolPolicy.swift:95-106`), texto por regex de spans (hay que escribir la versión en español), sitios por allowlist curada. Es exactamente lo que jev hace con el texto y lo que companion hace ya con la dictación (`DictationRouter`, función pura sin modelo).
3. **Sesgo de posición es real y barato de mitigar**: dos órdenes promediados en la cabeza que decide (una llamada extra). Un modelo entrenado (Laya, verdict) lo corrige en entrenamiento ("Symmetric Permutation-KL"); nosotros no.
4. **Nouls no sirven como puerta en un 4B.** Derivar las puertas de cabezas `choice` (`action == none`) y no de `addressed`/`compound`. O usar `score`. O confiar la puerta a la wake word / hold-FN, que es lo que Companion ya hace y evita la pregunta.
5. **La confianza decide entre actuar, confirmar o caer al camino actual; nunca sustituye la validación.** El candidato elegido sigue pasando por `ParentToolPolicy` y por la puerta de `open_url` ("lo dijo el usuario"). Y las acciones irreversibles piden confirmación **aunque** la confianza sea 0.99 — jev-voice no lo hace y es su peor defecto.
6. **El modelo es el cuello.** 4B es el suelo de calidad; 27B es el techo de precisión pero hoy son 3 s/pregunta en Ollama. La decisión de modelo es de producto (memoria, latencia) y debe medirse con la instrumentación de 12c, no adivinarse.
7. **La tesis "modelo de decisión > convencional para el 90 %" se sostiene para el vocabulario del padre** (`open_app`, `open_url`, `open_file`, `list_apps`, `read_skill`, volumen, atajos: todo enumerable). No se sostiene todavía para "clic en lo que hay en pantalla": 13a difiere el clic por visión y 10b lo manda a Wave 12+. Ese es el segundo escalón (el loop de jev-ultrafast sobre AX), no este.

---

## 5. Dónde aterriza en Companion

Evidencia file:line en `sources/C-aterrizaje-en-companion.md`. Hoy **ninguna** decisión del padre es una elección cerrada: el modelo primario genera JSON libre y `ParentToolPolicy` valida después (§1). La única rama sin modelo es la dictación (`Dictation.swift:44-59`), que prueba que el patrón ya es nativo aquí.

- **Puerto en Core**: `DecisionProvider` con `DecisionQuestion` (choice sobre ids cerrados / yesNo) y `DecisionAnswer` (choice?, distribution, confidence). Nuevo puerto, no reutilizar `ChatProvider` (contrato distinto; `ChatSSEAttempt` ya roza el tope de 800 líneas).
- **Productores de candidatos + `Plan` puro en Core**: apps vía `WorkspaceOpening` (Core no importa AppKit; el puerto ya existe en `ParentTools.swift:184-190`); spans por regex es/en (reutilizar la disciplina de `saidIt`, `ParentToolPolicy.swift:209-228`); sitios: no existe allowlist hoy, sería `UserPreferences`; atajos/volumen: conjuntos nuevos. `PlanThreshold.evaluate` con `min` y `.act / .confirm / .notSure`, en el estilo de `LocalModelChoice.choose` (`LocalModels.swift:78-101`).
- **Posición: delante de `ParentToolRunner.execute`, como fast path, con caída al camino actual.** `.notSure` → el turno sigue por `actRule`/`delegateRule` sin cambios (mismo patrón que la dictación fallida, la visión pendiente o Ollama ausente). Nunca toca `NativeTool`, `run_shell`, `delegate`/`Escalation` (que aquí significa *handoff al especialista*, no "modelo más fuerte").
- **Eventos**: `.parentActing(targets:)` / `.parentActed` ya significan lo que hace falta (`SessionMachine.swift:46-51`); un `.decisionUnsure` nuevo como aviso sin transición (patrón `.dictationFailed`). `TurnTimeline` gana una marca `decision` para medir el antes/después.
- **Adapters en Services**: `OllamaDecisionProvider` (endpoint nativo, prefill, `logprobs`), `OpenAIDecisionProvider` (Chat Completions con `logprobs`, nunca Responses API ni function calling), y opcional `TypeSafeDecisionProvider` con el cable de Jev. Descubiertos en runtime, nunca asumidos (ADR 004/006).
- **Config**: umbral(es) por riesgo de acción y el proveedor juez, por `Config`; toggle en `SettingsAppPane` como `ContextPreference`; apagado por defecto hasta medir.
- **Restricciones que muerden**: Swift 6 y `Sendable`; Core sin AppKit (Gate 3); sin `try?` ni `print`; 800 líneas por archivo; ADR 003 (no hace falta ninguna dependencia nueva: es un cambio de forma de petición sobre transportes OpenAI-compatibles que ya existen); **spec APROBADO antes de código**, y reconciliar con Wave 14 (roles cerebro/boca/oído, PROPUESTA sin aprobar): un "juez" es un rol hermano.

---

## 6. Programa propuesto (para convertir en specs)

| Wave | Entrega | Métrica de cierre |
|---|---|---|
| DM0 Línea base y arnés | Marca `decision` en `TurnTimeline`; medir la latencia real del tool call actual en 30 holds; **conjunto etiquetado de ~150 órdenes es/en** del uso real de Karen (frase → acción + argumentos + ¿irreversible?). Sin código de producto | Números del antes en el ROADMAP; el dataset existe y se versiona |
| DM1 Core puro | `DecisionProvider`, tipos, productores de candidatos (apps, spans es/en), `Plan` + `PlanThreshold`; `FakeDecisionProvider`; tests reductor-style | `swift test` verde; 0 I/O en Core; el fake demuestra que `.notSure` deja el camino actual intacto |
| DM2 Adapter Ollama + cascada | Endpoint nativo, prefill, logprobs, dos órdenes en `action`, cascada; prefiltro de apps ≤ 5 | Sobre el dataset de DM0: ≥ 90 % de planes correctos, p50 ≤ 1.5 s en 4B; curva confianza→acierto por cubos (primera medida de calibración propia) |
| DM3 Cableado | Fast path delante de `ParentToolRunner`; `.decisionUnsure`; confirmación obligatoria para irreversibles; toggle en Settings, off por defecto | Prueba en vivo: "abre Safari" por voz sin tool call del modelo; nada de lo que hoy funciona deja de funcionar con el toggle off |
| DM4 Proveedores | `OpenAIDecisionProvider`; `TypeSafeDecisionProvider` si la consola abre; selección por `Config` | Mismo dataset, tres proveedores, tabla latencia/acierto/coste |
| DM5 Decidir el default | Umbrales por riesgo con la curva de DM2/DM4; ¿on por defecto? | Decisión de Karen con números, registrada como ADR |

Fuera de este programa, como escalón siguiente: el loop de agente sobre el árbol AX (operación + target indexado, guardas de frescura de jev). Depende de que 13a/12+ desbloqueen el clic.

---

## 7. Riesgos

- Que la nitidez pase por calibración: hasta DM2 no hay curva. Mientras, umbrales conservadores y confirmación para lo irreversible.
- Regex de spans en español: hoy no existe; sin ella, `type_text` en español teclea la orden entera (visto en E7).
- Modelos *thinking* por `/v1`: el adapter de Ollama tiene que usar el endpoint nativo; documentarlo en `REFERENCE.md` como cicatriz.
- Ollama no reutiliza prefijo en algunas arquitecturas (visto con `qwen35`): la latencia depende del modelo elegido más de lo esperado; medir, no asumir.
- Tentación de reemplazar en vez de anteponer: el fast path que rompe el camino actual es una regresión peor que no tenerlo.

---

## Referencias locales

- jev-voice clonado y configurado en `~/Desktop/SoftwareDevProjects/jev-voice` (falta `TYPESAFE_API_KEY`); rama local `fix/wake-word-gate-defaults` con el fix del issue #1 sin commit.
- `sources/A-jev-voice-mecanismo.md` — protocolo, fan-out, candidatos, texto, escalación, guardas, latencia, debilidades, heredado vs añadido.
- `sources/B-typesafe-y-viabilidad-logprobs.md` — TypeSafe, matriz de proveedores, técnica y pitfalls, literatura de calibración, prior art.
- `sources/C-aterrizaje-en-companion.md` — camino actual de una orden, vocabulario del padre, escalación real, ruta local, fallos documentados, diseño y tests propuestos, restricciones.
- `sources/D-ecosistema-openjev.md` — seis reproducciones, Laya, typed-decisions, jevmlx.
- `experiments/` — `probe_logprobs.py` (E1-E2), `prefix_reuse.py`, `fanout.py` (E3, E6), `fanout2.py` (E4-E6), `fanout3.py` (E7). Corren con el venv de jev-voice: `cd ../jev-voice && uv run python <script> <modelo-ollama>`.
