# Wave 9b — Base local, nube opcional

**Estado: APROBADO (2026-08-22).** Karen aprobo la v3 completa. Las ocho
condiciones de la auditoria estan cerradas; los dos numeros del criterio de
done #1 siguen sin medir y se fijan antes de dar la pieza por terminada, con
la advertencia de que medir en un M4 Max da el techo, no el suelo.

**En curso:** 9b-1 entregada completa (PR 1, el cable; PR 2, el muro).
Siguiente pieza: 9b-3, panel de claves y `providerOrder`.

### Una contradiccion de esta spec, resuelta al implementar (2026-08-23)

La spec se contradecia a si misma en un punto, y hubo que elegir:

- El **TDD #1 de 9b-1** (heredado de la v2) pedia que `needsOnboarding` fuera
  `false` en cuanto el sondeo encontrara un camino vivo — es decir, entrar
  directo al hilo.
- La **tabla de estados** (escrita despues, en la v3) dice que `base(camino)`
  muestra "la pantalla base con el camino que si esta, **y el boton de
  aceptar**".

Gana la tabla, por ser mas reciente y mas especifica, y porque el producto lo
pide: la primera vez conviene que el usuario LEA con que va a hablar
("Usar qwen3:14b en tu Mac") antes de hablar. A partir del segundo arranque el
camino guardado se acepta solo y no hay clic. El TDD #1 queda reescrito a esa
forma y su intencion —que nadie quede encarcelado sin clave— la cubre
`acceptLocalBase`.

**Depende de:** Wave 9 (arranque ajeno), ADR 001 (ninguna capacidad exige un
runtime Python), ADR 004 (detección read-only de capacidades ajenas).
**Produce:** ADR 006 — Base local, nube opcional (borrador en `DECISIONS.md`).
**No depende de:** Realtime premium, capa de conocimiento, visión, control de UI.

---

## Por qué esta wave

Companion hoy es usable solo con una clave de pago. Eso contradice su propia
tesis: conversación natural con el Mac y acceso al ecosistema local de AI, con
menos fricción que Siri. Wave 9 abrió la puerta del DMG y del idioma; no abrió
la de "puedo hablar y trabajar sin pagar". Un desconocido que descarga el
release se estrella contra un campo de texto que pide `sk-proj-...`.

La wave no inventa una arquitectura nueva. Quita un muro, arregla un cable
suelto, y decide qué se promete.

---

## Lo que la auditoría del código cambió (medido 2026-08-22)

### Ya está hecho, y el borrador lo pedía como trabajo

| Lo que pedía el borrador | Estado real |
|---|---|
| "Reordenar routing: local primero cuando no hay clave" | Ya es el comportamiento. `ChatProviderClient.swift:93-103` recorre el catálogo, salta con `continue` cualquier proveedor con `secretKey` cuyo Keychain esté vacío, y salta los locales cuyo probe falle. Sin clave de OpenAI la escalera ya cae sola en Ollama |
| "Sin clave, preferir el pipeline clásico de voz" | Ya: `VoiceSession.swift:184` — `startVoice(preferRealtime: openAIKey() != nil)` |
| "NativeExecutor contra el mismo endpoint local" | Ya, y mejor: el executor depende del puerto `ChatProvider` (`NativeExecutor.swift:9,65`), no de una URL. Cambiar de proveedor no lo toca |
| "Probe de salud del runtime local" | Ya existe: `LiveCapabilityProbe` hace GET `/v1/models` con timeout de 1 s, y `EndpointPolicy` ya permite `http` únicamente en localhost |
| "Recuperarse si el proveedor local falla el POST" | Ya: `ChatSSEAttempt.mapStatus` manda un 404 a `.httpStatus(404)`, `DeltaSink.finish` lo convierte en `.failed` sin texto emitido, y el router hace `continue`. **Verificado, no supuesto** — ver 9b-1, apartado del 404 |
| "Tests de caracterización del orden de proveedores" | El andamio está puesto: `ChatProviderClientTests`, `CapabilityProbeTests` y `ChatFakes` ya existen |

**Consecuencia:** la mitad técnica del borrador era trabajo ya pagado.

### El muro real son tres líneas de onboarding

- `ChatViewModel.swift:120,125` — `needsOnboarding` se decide con un único
  criterio: que exista una clave de OpenAI en el Keychain.
- `ChatViewModel.swift:177` y `:334` — `send()` y el drenado de la cola están
  bloqueados por `guard !needsOnboarding`.
- `OnboardingView.cannotContinue` — el botón exige texto en el campo.

Ese es el 80% del valor de la wave y es el cambio más pequeño de todos.

### Un fallo latente que nadie había medido

`Config.swift:57` fija `qwen3.6:27b` como constante del descriptor de Ollama.
El probe pregunta por `/v1/models` y devuelve `true` con un 200 **aunque ese
tag no esté instalado**. El router da Ollama por vivo y el POST muere.

Traducido: **hoy, un Mac con Ollama corriendo y un modelo pequeño instalado
falla el primer mensaje.** El camino gratis que la wave quiere ofrecer está
roto antes de empezar.

### Dos cables sueltos que la wave destapa

- **Groq no es alcanzable.** `SecretKey.groq` existe (`Config.swift:5`) y el
  descriptor también (`:45`), pero **nada en `Sources/` escribe esa clave**.
- **`preferredProviderName` no llega nunca.** `Config.swift:140` solo se lee en
  `ChatProviderClient:93`, y `StoredConfigProvider.current` construye
  `chat: .default`, así que el campo es `nil` por construcción aunque alguien
  lo guardara. Ver 9b-1, apartado de persistencia.

---

## Modelo de tiers — dos personas, no una

La decisión de producto del 2026-08-22 no fue sobre Groq. Fue sobre **para
quién arranca esta app**, y de ahí sale todo lo demás.

| | Persona | Qué necesita | Qué obtiene |
|---|---|---|---|
| **Base** | Alguien que no sabe qué es una API key | Nada que teclear | Chat, encargos y voz por turnos con IA que corre en su Mac |
| **Premium** | Power user | Sus claves, pegadas en Ajustes | Voz en tiempo real, modelos frontier, y la escalera ordenada a su gusto |

Cuatro consecuencias, y las cuatro cambian el diseño:

1. **Ninguna clave es requisito. Todas son mejora.** Da igual si es OpenAI,
   Groq u OpenRouter: son la misma clase de cosa — una clave secundaria que
   vive en Ajustes y sube el techo del producto. La única razón por la que
   OpenAI parecía distinta es que era la única, y por eso se comió el
   onboarding.

2. **Todo lo que no sea el modelo base es personalizable.** La escalera de
   proveedores deja de ser una constante del código y pasa a ser configuración
   del usuario: qué va primero, qué queda de respaldo, qué se apaga. Con una
   excepción real, medida, que está en la tabla de voz de abajo.

3. **El copy no dice "modelos gratis de Companion".** Los pesos son de Ollama
   o del sistema; Companion solo orquesta. Se dice **"IA en tu Mac"** o
   **"runtime local"**, nunca algo que suene a que la app los hospeda o los
   regala. Prometer paternidad sobre pesos ajenos es la misma familia de
   deshonestidad que llamar "premium" a un tier atado a un vendor.

4. **La descarga del modelo base es opcional y va dentro de la app.** Un
   usuario que no sabe qué es una API key tampoco sabe qué es una terminal:
   mandarlo a pegar `ollama pull` en Terminal.app no es un camino, es un muro
   con otra forma. Y un power user que ya tiene sus modelos nunca la ve.

### Runtime, no bundle — y el ADR que lo sostiene es el 004

Los pesos siguen sin viajar en el DMG. Lo que cambia respecto de la v2 es
**quién dispara la descarga**, no dónde viven los pesos.

| Meter los pesos en el DMG | Traerlos en runtime |
|---|---|
| DMG de varios GB | DMG sigue en su tamaño actual |
| Cada bump de modelo es un release | El cerebro se actualiza sin republicar la app |
| Firma y notarización más pesadas | El binario de la app no cambia |
| Segunda dependencia binaria opaca (exigiría otro ADR) | Los pesos viven donde ya viven: caché de Ollama, o el OS |
| "¿Qué modelo meto para 8 GB y para 64 GB?" | Se elige después de ver la máquina |

El ADR 004 sigue siendo el precedente del **scan** (leer qué modelos hay: un
adapter, read-only, comportamiento idéntico si Ollama no está). La descarga
parecía cruzar la línea de "leer, jamás ejecutar", y por eso la v2 la dejó
fuera. **No la cruza**, y la razón está medida en 9b-4: Ollama expone el pull
por HTTP, así que Companion nunca ejecuta un binario ajeno. Lo que estaba mal
era la premisa —suponer que pull significa subprocess—, no el ADR.

---

## Escalera de proveedores — personalizable

El orden deja de ser `[openAI, groq, ollama]` escrito en `Config.swift:61`. El
catálogo efectivo se arma en runtime con lo que de verdad está vivo, y el
usuario puede reordenarlo, apagar filas y elegir el modelo de cada una.

Orden **por defecto** cuando nadie ha tocado nada:

```
1. Apple SystemLanguageModel   (si el Mac califica Y el idioma está soportado)
2. Ollama local                (con el modelo REAL del usuario, no una constante)
3. Proveedores con clave       (OpenAI, Groq, OpenRouter — en el orden que el usuario deje)
```

Por defecto lo local va primero: es gratis, es privado y no depende de la red.
Un power user que prefiera empezar por su modelo frontier lo sube en el panel y
esa decisión se persiste. **La escalera es del usuario, no del código.**

### Voz: dónde sí y dónde no hay personalización

Aquí está el matiz que la pregunta de Karen destapó. "Voz premium" no es una
cosa, son tres capas, y **solo una está atada a OpenAI**:

| Capa | Base (sin clave) | ¿Personalizable? | Por qué |
|---|---|---|---|
| STT | `SFSpeech` del sistema | **Sí** | Puerto `Transcriber` en Core. Whisper, WhisperKit o SpeechAnalyzer entran ahí sin tocar nada más |
| TTS | `AVSpeechSynthesizer` | **Sí, y ya hoy** | Puerto `SpeechSynthesizer`, con dos implementaciones vivas: `OpenAITTS` y `SpeechSynthesis`. Cualquier otro TTS (ElevenLabs, Kokoro local) es una tercera |
| Diálogo full-duplex | Pipeline clásico | **No** | `RealtimeCodec.swift:25` construye `wss://api.openai.com/v1/realtime?model=…`. El protocolo **es** la implementación: eventos, codec y transporte están escritos contra el esquema de OpenAI |

Así que la respuesta a "¿la voz premium siempre sería de OpenAI?" es **sí para
el barge-in, no para el resto**. Cambiar de proveedor de Realtime no es un
campo de configuración: es un segundo protocolo full-duplex completo, con su
codec y sus tests. Eso ya está declarado como no-objetivo.

Lo honesto en el copy: **"Voz en tiempo real (OpenAI)"** como nombre del tier,
en vez de "voz premium" a secas. Nombrar al proveedor evita prometer una
personalización que la arquitectura no da.

Y la mitad buena: la calidad de voz del pipeline clásico —el que usa la
persona base— **sí** es un hueco intercambiable. Si `AVSpeechSynthesizer`
termina doliendo, se sustituye sin tocar Realtime ni la escalera de chat.

---

## Piezas

```
9b-1 arranque sin clave ──┬──→ 9b-3 panel de proveedores y claves
                          ├──→ 9b-4 descarga opcional del modelo base
                          └──→ 9b-2 Apple FM (con puerta de evidencia)
```

9b-1 es el cimiento: sin catálogo resuelto en runtime, ni el panel ni la
descarga tienen dónde apoyarse. **El orden queda fijado:**

```
9b-1  muro + scan + modelo real      cimiento, no negociable
9b-3  panel de claves + providerOrder desbloquea a la persona power user
9b-4  pull opcional                   desbloquea a la persona no técnica
9b-2  Apple FM                        solo si 9b-1 se usa y duele depender de Ollama
```

9b-3 antes que 9b-4 porque el panel es donde la descarga vive: construir el
botón antes que la habitación obliga a moverlo después.

**9b-2 sigue detrás de su puerta de evidencia.** Meter Apple FM en el mismo PR
que el onboarding mezclaría el 80% del valor con el riesgo del SDK 26 y de una
ventana de 4096 tokens.

Esta wave es ahora **cuatro piezas y cinco PRs**. Es más de lo que cabe en una
wave sana, y se dice antes de empezar: si hay que recortar, se recorta 9b-2,
que es la única cuyo valor no está demostrado.

---

## 9b-1 · La app arranca sin clave

El entregable de la wave. Sin esto, lo demás no importa.

### El sondeo, y el parpadeo que hay que evitar

Hoy `onAppear` decide en una lectura síncrona de Keychain. El sondeo que esta
pieza necesita es asíncrono, y eso introduce un estado que la v1 no nombraba.
Sin diseñarlo, la raíz puede pintar chat, luego onboarding, luego chat.

**Regla, y es la que evita el bug:** la raíz no se pinta como hilo de chat
hasta que el arranque se resolvió. Un solo cambio de estado, nunca dos.

El arranque tiene tres desenlaces y un tránsito:

| Estado | Cuándo | Qué se ve |
|---|---|---|
| `premium` | Hay clave de OpenAI en el Keychain | Recorrido de hoy, sin sondeo. **El arranque con clave no se ralentiza ni un milisegundo** |
| `probing` | No hay clave, el sondeo está en curso | Pantalla base con indicador. Nunca el hilo |
| `base(camino)` | El sondeo encontró al menos un camino vivo | Pantalla base con el camino que sí está, y el botón de aceptar |
| `none` | El sondeo terminó sin nada vivo | Pantalla base con la guía de instalar Ollama y el campo de clave como opción |

Restricciones del sondeo:

- **Se acota a 2 s en total.** El probe local ya trae 1 s propio; lo que no
  contestó cuenta como no disponible. Un arranque no se queda esperando a un
  daemon que quizá no exista.
- **Un fallo parcial no es un fallo.** Si Apple FM no aplica y Ollama sí, el
  desenlace es `base`. Solo `none` cuando fallan todos.
- **El camino local jamás llama a `chat.verify(_:provider:.openAI)`.** Salir a
  `api.openai.com` para confirmar una clave que no existe es exactamente el bug
  que Wave 9 cerró en el guardia de forma de la clave.

### El seam en el ViewModel

La v1 describía la pantalla y no nombraba dónde se codea. Es aquí:

```swift
// ChatViewModel
func acceptLocalBase(_ path: LocalPath) async
```

Hace cuatro cosas, en este orden:

1. Confirma el camino **con el sondeo ya hecho**; no vuelve a sondear.
2. Persiste la preferencia (ver abajo) y, si es Ollama, el tag elegido.
3. `needsOnboarding = false`.
4. `loadMostRecent()`, igual que tras aceptar una clave.

`submitOnboarding()` no cambia: sigue siendo el camino premium. Deja de ser el
único.

### Cuándo se re-escanea Ollama

Decisión: **al armar el catálogo, más un botón explícito.** No hay resolución
mágica continua ni scan perezoso dentro del stream.

- Se escanea en el sondeo de arranque y al entrar a la pantalla base.
- Hay un **"Reintentar detección"** en esa pantalla y en Ajustes.
- No se escanea por request.

El costo dicho en voz alta: si haces `ollama pull` con la app abierta, hay que
pulsar Reintentar. Es una línea de UI a cambio de que el camino caliente no
dependa de un scan, y de que el tiempo al primer token sea determinista.

### Qué es un modelo usable

"Lista no vacía" no alcanza — sería la constante disfrazada de scan. La regla,
corta y testeable, en un solo sitio y fechada:

1. **Se excluyen** los tags cuyo nombre contenga `embed`, `bge` o `rerank`. No
   sirven para chat, y ofrecerlos es fallar el primer mensaje con otra cara.
2. Si el tag guardado en preferencias **sigue en la lista**, gana. La
   estabilidad entre arranques vale más que "el mejor de hoy".
3. Si no, el mayor que quepa en el escalón de RAM. El tamaño sale de lo que
   `/api/tags` reporta en disco, no de adivinar por el nombre.
4. Empate → orden lexicográfico, para que la elección sea determinista.
5. **Lista vacía tras el filtro → Ollama no se ofrece.** No es "vivo sin
   modelo": es no disponible, y el copy muestra el comando de pull.

### Heurística de recomendación por RAM

Sugerencia de qué traer, nunca una descarga. Orientativa a 2026:

| RAM unificada | Sugerencia | Nota |
|---|---|---|
| ≤ 8 GB | clase 3B (~2-3 GB) | Evitar swap |
| 16 GB | clase 7-9B (~4-8 GB) | Punto dulce de laptop |
| 24-32 GB | clase 14-27B | Buen razonamiento local |
| 64 GB+ | 32B en adelante | Quien tiene esa máquina ya sabe |

**El default del producto es el tramo de 16 GB, no el de Karen.** La Mac de
desarrollo es un M4 Max de 32 GB y cae en el tercer tramo (clase 14-27B, que
es donde una base local deja de ser un consuelo y empieza a ser útil). Esa es
su referencia personal y **no puede ser la que el producto asume**: un default
calibrado sobre un M4 Max convierte el primer arranque de un MacBook Air de
16 GB en swap. La tabla manda; la máquina de quien la escribe, no.

Para **encargos** la recomendación mínima sube a la clase 7-8B cuando la RAM lo
permita: un 3B falla tool calling con frecuencia.

La función que va de bytes a escalón es **dominio puro y vive en
`CompanionCore`**, no en Services. Se testea sin red, como el resto de Core. El
scan HTTP se queda en Services.

### El 404 ya se recupera solo — verificado

La auditoría preguntó dónde se retoma la escalera si el POST muere con
model-not-found, y si eso metía un sexto archivo. Se leyó el código:

`ChatSSEAttempt.mapStatus` manda cualquier código no especial a
`.httpStatus(code)`; `DeltaSink.finish` con error y sin texto emitido devuelve
`.failed(...)`; el router hace `continue` con `.failed`. **La red de seguridad
existe y no hay que escribirla.**

Por lo tanto: la corrección principal sigue siendo **no POST-ear un tag que no
esté en la lista**, y el test del 404 es de **caracterización** — fija el
comportamiento actual para que nadie lo rompa. `ChatSSEAttempt` no entra en el
diff de 9b-1.

### Cambiar la clave no vuelve a encarcelar

`changeKey()` hoy fuerza `needsOnboarding = true`. Con base local eso
devolvería el muro justo al tocar Ajustes: alguien que usa Ollama y entra a
pegar una clave premium se quedaría sin chat.

Decisión: **"cambiar clave" abre el campo premium sin bloquear el chat.** Si
hay un camino local aceptado, la app sigue usable mientras el campo está
abierto. Solo se vuelve a `needsOnboarding` cuando no queda ningún camino.

### La voz entra con el mismo flag

El routing de voz ya prefiere el pipeline clásico sin clave
(`VoiceSession.swift:184`), pero si toda la raíz está detrás de
`needsOnboarding`, el micrófono no existe hasta terminar el onboarding.

Se dice explícito, y es criterio de done: **tras aceptar la base local, el
mismo flag desbloquea la voz clásica. No se exige clave para el micrófono.**

### Dónde se persiste la preferencia

`preferredProviderName` existe en `ChatSettings` y no llega nunca, porque
`StoredConfigProvider.current` construye `chat: .default`. Dos piezas:

- Un `ProviderPreference` en `UserPreferences.swift`, con la misma forma que
  `LanguagePreference` y `WorkdirPreference` (UserDefaults, `nonisolated`).
  Guarda el nombre del proveedor y, para Ollama, el tag elegido.
- `StoredConfigProvider.current` deja de pasar `chat: .default` y arma el
  `ChatSettings` con esa preferencia.

Sin esto, aceptar "usa Ollama" no sobrevive al relaunch.

En 9b-1 basta con guardar el proveedor elegido y su tag. **En 9b-3 ese campo
crece hasta ser el orden completo de la escalera** (`providerOrder`). Se
construye pensando en eso desde el principio para no migrar preferencias dos
veces.

### Restricciones

- El scan vive en **un solo adapter**, es read-only, y con Ollama apagado el
  producto se comporta idéntico al de hoy (ADR 004).
- Ni un `Process` nuevo. Solo HTTP a localhost, que `EndpointPolicy` autoriza.
- Nada de descargas silenciosas. Ni una.
- La regla de "modelo usable" y la tabla de RAM viven cada una en un sitio, no
  repartidas por la UI.

### TDD

Los siete de la v1, con los ajustes que pidió la auditoría, más tres nuevos:

1. `needsOnboarding` es `false` cuando no hay clave pero el sondeo devuelve un
   camino vivo, y sigue `true` cuando no hay ninguno. **Con clave presente el
   sondeo ni se lanza.**
2. La raíz nunca pasa por chat durante `probing`: un solo cambio de estado.
   Es el test del parpadeo.
3. `send()` con cero claves y Ollama vivo llega al proveedor local.
4. Scan: lista vacía → no se ofrece; lista con solo `nomic-embed-text` → **no
   se ofrece**; lista mixta → elige un tag de la lista, nunca la constante.
5. El tag guardado que sigue instalado gana sobre el "mejor" de la heurística.
6. Ollama responde 200 a `/v1/models` pero el tag pedido no existe → el router
   baja de peldaño. Caracterización del comportamiento ya verificado.
7. La función RAM → escalón es pura, vive en Core y devuelve el mismo escalón
   para los cuatro tramos de la tabla.
8. `acceptLocalBase` persiste la preferencia y **sobrevive un relaunch**
   (con store falso).
9. `changeKey()` con base local aceptada **no** vuelve a bloquear `send()`.
10. Con clave de OpenAI no cambia una sola decisión respecto de hoy: test de
    no-regresión del recorrido premium.
11. Ningún test descarga un modelo ni sale de localhost. Se verifica en el
    gate, no de palabra.

### Archivos

La v1 decía cinco. La auditoría tenía razón: son siete de producto, más copy y
tests. Se escribe honesto para que el PR se parta bien.

Producto:

```
Sources/CompanionServices/OllamaModelScan.swift   nuevo, read-only
Sources/CompanionCore/Config.swift                modelo del descriptor resoluble
Sources/CompanionCore/RAMTier.swift               nuevo, función pura
Sources/CompanionUI/ChatViewModel.swift           sondeo, acceptLocalBase, changeKey
Sources/CompanionUI/OnboardingView.swift          tres caminos, no un campo
Sources/CompanionUI/UserPreferences.swift         ProviderPreference
Sources/CompanionApp/StoredConfigProvider.swift   deja de pasar chat: .default
Sources/CompanionApp/CompanionMain.swift          arma el catálogo efectivo
```

Ocho, contando el composition root. Más el catálogo de copy con sus dos
traducciones (obligatorio desde Wave 9) y los tests.

**Esto excede el techo de 3-5 archivos de `CLAUDE.md`, y se dice antes de
empezar, no después.** Se parte en dos PRs:

- **PR 1 — el cable:** scan, `RAMTier`, `Config`, `CompanionMain`. Resuelve el
  modelo real y arregla el fallo latente. Testeable sin tocar la UI.
- **PR 2 — el muro:** `ChatViewModel`, `OnboardingView`, `UserPreferences`,
  `StoredConfigProvider`, copy. Quita el muro apoyándose en PR 1.

---

## 9b-2 · Apple Foundation Models · CON PUERTA DE EVIDENCIA

**No se abre hasta que 9b-1 esté cerrada y usada.**

### Lo que el borrador tenía mal

Proponía `appleFM` como una entrada más del catálogo. **No cabe.**
`ProviderDescriptor` tiene `baseURL: URL` no opcional, y `route` →
`ChatSSEAttempt.run` asume un endpoint OpenAI-compatible sobre HTTP y SSE.
Apple FM es una API in-process. Meterlo obliga a inventar una URL falsa y a
poner un `if` de tipo dentro del router.

La forma que respeta la arquitectura ya existe: **un `ChatProvider` compuesto**
que intenta Apple FM y delega en `ChatProviderClient` cuando no aplica. El
puerto es exactamente esa junta. El cambio vive en `CompanionMain`, no en
`Config`, y `ChatProviderClient` no se entera.

### La restricción que decide si esto es usable

`SystemLanguageModel.contextSize` — verificado en el `.swiftinterface` del SDK
instalado, `@backDeployed` con valor 4096. Cuatro mil noventa y seis tokens
**de entrada y salida juntos**.

Contra eso: `historyWindow` son 20 turnos, más el prompt de sistema, más el
perfil del dueño, más la `ToolSpec`. La ventana revienta pronto y el SDK tiene
el error preparado: `GenerationError.exceededContextWindowSize`.

**Nadie adivina ese número: se lee de `contextSize` en runtime.** El proveedor
Apple necesita su propio presupuesto de historia y una política explícita
cuando el error salta. Ese es el trabajo real; el adapter es la parte fácil.

### Encargos cuando Apple FM es lo único que hay

La auditoría preguntó qué pasa si alguien pide un encargo con solo Apple FM
vivo. Decisión: **el `delegate` no se ofrece.** No se manda esa `ToolSpec`.

Razón: el chat pasa una sola tool (`ChatViewModel.swift:275`) y el protocolo
`Tool` de FoundationModels pide tipos `Generable`, no el `ToolSpec` plano.
Ofrecer una herramienta que el proveedor no puede ejecutar con garantía repite
el bug que Wave 9 dejó abierto — ofrecer especialistas no instalados.

Si el usuario pide un encargo, recibe **una frase que lo explica** y le dice
qué le falta (Ollama, o una clave), no un intento que falla a medias y deja la
tarjeta colgada. Va al copy de la pantalla base: charla sí, encargos no.

### Otras dos cosas que el SDK ya resuelve

- **Disponibilidad con motivo.** `availability` distingue `deviceNotEligible`,
  `appleIntelligenceNotEnabled` y `modelNotReady`. Tres mensajes distintos, no
  un "no disponible" genérico. El segundo es accionable.
- **Idioma.** `supportedLanguages` devuelve el set real. Si el idioma de
  `Config` no está ahí, el proveedor se salta en silencio. Ofrecerlo a alguien
  cuyo idioma el modelo no habla repetiría el bug de Wave 9 en otra superficie.

### Disponibilidad de plataforma

`Package.swift` fija `.macOS(.v14)`; FoundationModels es `macOS 26.0`. El
framework está en el SDK instalado y compila, pero cada uso va con
`@available(macOS 26, *)`.

**No se sube el mínimo del paquete.** Dejaría fuera a todo Mac sin Apple
Intelligence — justo el usuario que esta wave quiere rescatar.

### TDD

1. El compuesto delega en `ChatProviderClient` cuando Apple FM no está
   disponible, para cada uno de los tres motivos, sin perder el stream.
2. Idioma fuera de `supportedLanguages` → se salta, no se ofrece.
3. Historia que excede el presupuesto → se recorta antes de enviar; si el error
   salta igual, se degrada al siguiente peldaño en vez de romper el turno.
4. El presupuesto sale de `contextSize`, no de una constante a mano.
5. Con Apple FM como único proveedor, `delegate` no viaja en las tools y una
   petición de encargo responde con la frase explicativa.
6. Los tests pasan en una máquina sin Apple Intelligence: el camino no
   disponible es el que más se ejercita en CI.

---

## 9b-3 · Panel de proveedores y claves

Aquí aterriza la decisión de Karen: **toda clave es secundaria**. Ninguna es
requisito, todas viven en el mismo sitio, y la escalera es del usuario.

### Un panel nuevo en Ajustes

Ajustes tiene hoy tres paneles (`you`, `voice`, `app`). Se añade un cuarto:
**Modelos**. Contiene tres cosas y nada más:

1. **Una fila por proveedor con clave** — OpenAI, Groq, OpenRouter. Cada una
   con su campo, su estado (sin clave / verificando / lista / rechazada) y el
   modelo a usar.
2. **La base local** — qué modelo de Ollama está en uso, "Reintentar
   detección", y el botón de descarga de 9b-4 cuando aplique.
3. **El orden de la escalera** — reordenable, con filas que se pueden apagar.

`SecretKey` ya tiene los tres casos (`openAI`, `groq`, `openRouter`): la
enumeración se escribió para esto y lleva desde entonces sin superficie.

### Dos cosas que ya funcionan y nadie usa

- **La verificación de clave ya es genérica.** `ChatProvider.verify(_:provider:)`
  recibe el descriptor y pega contra `provider.baseURL + "/models"`. Verificar
  una clave de Groq o de OpenRouter **no necesita código nuevo**: lo único que
  falta es dejar de llamarla siempre con `.openAI` cableado
  (`ChatViewModel.submitOnboarding`).
- **`SecretKey.openRouter` no tiene descriptor.** Es la única pieza que falta
  para que la tercera fila exista.

### La escalera deja de ser un `String?`

`ChatSettings.preferredProviderName: String?` no alcanza para "ordena y apaga".
Se sustituye por un orden explícito:

```swift
// ChatSettings
var providerOrder: [String]   // ids, en orden; lo ausente está apagado
```

Y `ProviderDescriptor.route(preferred:catalog:)` pasa a resolver contra ese
orden. **Sustituir en vez de sumar sale gratis**: `preferredProviderName` no lo
escribe nadie hoy, así que no hay dato viejo que migrar ni comportamiento que
preservar. El único llamador es `ChatProviderClient:93` y los tests.

Reglas del orden, para que no se convierta en una forma de romper la app:

- Un proveedor que no está en la lista guardada se añade **al final** cuando
  aparece. Instalar Ollama no reordena lo que el usuario ya decidió.
- La lista vacía no existe: si el usuario lo apaga todo, la base local vuelve.
  Un producto sin ningún camino no es una configuración, es un fallo.
- El modelo de cada fila es editable, con el valor de hoy como defecto.

### Prerrequisito que no es de esta wave, pero la bloquea

Hoy `ChatProviderClient.storedKey(for:)` lee el llavero **dentro del bucle de
routing**, una vez por proveedor con clave, más otra al pasar la clave a
`ChatSSEAttempt`. Con dos proveedores con clave eso ya son tres lecturas por
mensaje. **Este panel añade un tercero**, así que pasan a cinco — y la voz suma
las suyas (`VoiceSession:184,259`, `VoiceSessionPumps:59`).

Mientras el ACL del ítem del llavero esté sano eso es solo desperdicio. En
cuanto se desajusta —como pasó al renombrar el bundle en Wave 9— cada lectura
es un diálogo de contraseña, y este panel multiplica el dolor por proveedor.

**Antes de 9b-3: memoizar la lectura, invalidándola al escribir o borrar.**
Convierte cualquier desajuste futuro en un diálogo, no en cinco. Son ~15 líneas
en `ChatProviderClient` y el mismo patrón en `VoiceSession`.

### TDD

1. `route(order:)` respeta el orden guardado y omite lo apagado.
2. Un proveedor nuevo aparece al final, no al principio.
3. Apagarlo todo devuelve la base local, no una lista vacía.
4. `verify` contra Groq y contra OpenRouter usa el baseURL de cada uno.
5. Una clave guardada en una fila no se filtra a la petición de otra: el test
   que impide el peor bug posible de este panel.
6. El orden sobrevive al relaunch.

---

## 9b-4 · La descarga opcional del modelo base

La v2 dejaba esto fuera citando el ADR 004: leer capacidades ajenas sí,
ejecutar el binario ajeno no. La decisión de producto de Karen lo reabre, y con
razón: **quien no sabe qué es una API key tampoco sabe qué es una terminal.**
Mandarlo a pegar `ollama pull` es cambiar un muro por otro.

### La tensión con el ADR 004 se disuelve sola

Ollama expone la descarga **por HTTP en su propia API**:

```
POST http://localhost:11434/api/pull   →  NDJSON con status, total y completed
```

Eso significa que Companion **nunca ejecuta un binario de terceros**. Hace una
petición HTTP a un daemon que el usuario ya decidió tener corriendo — la misma
superficie que el scan, y sobre el mismo host que `EndpointPolicy` ya autoriza.
No hay `Process`, no hay PATH, no hay shell. El ADR 004 se respeta tal cual
está escrito.

Lo que sí cambia respecto de la v2 es el ADR 006, que decía "el pull queda
fuera". Se corrige ahí, con el motivo, en vez de dejar dos documentos que se
contradicen.

### Cuándo se ofrece, y cuándo no

Se ofrece **solo** si se cumplen las tres a la vez:

- no hay clave de ningún proveedor,
- Apple FM no está disponible (o el idioma no está soportado),
- Ollama responde, pero no tiene ningún modelo usable según la regla de 9b-1.

Un power user con modelos instalados **nunca ve este botón**. Es la mitad de la
decisión de Karen que suele olvidarse: la descarga es opcional en las dos
direcciones, y saltarla no es un camino degradado.

### Contrato de la descarga

Ninguno de estos puntos es negociable, porque son los que separan una descarga
de un cuelgue:

- **Acción explícita.** Nunca automática, nunca al arrancar.
- **Tamaño antes de empezar.** El diálogo dice cuántos GB son y qué modelo, con
  la sugerencia que sale de la tabla de RAM.
- **Progreso visible** en bytes, alimentado por el NDJSON del daemon.
- **Cancelable de verdad:** cancelar la tarea corta la petición, y la UI vuelve
  al estado anterior sin dejar el panel a medias.
- **Fallo accionable:** disco lleno, red caída y daemon muerto son tres
  mensajes distintos. "No se pudo descargar" no es ninguno de los tres.
- **Al terminar, se re-escanea** y el modelo queda seleccionado. Sin ese último
  paso el usuario descarga y sigue sin poder hablar.

### Lo que sigue fuera: instalar Ollama

Descargar un modelo por la API de un daemon vivo y **descargar e instalar el
daemon** son cosas distintas. Lo segundo es traerse el instalador firmado de
otro proveedor, ejecutarlo y pedir permisos de administrador. Eso no es leer ni
llamar a una API: es cadena de suministro, y exigiría su propio ADR.

Companion enlaza a `ollama.com` y explica el paso. Queda un hueco honesto —
persona no técnica, Mac sin Apple Intelligence, sin Ollama — y está anotado
como decisión pendiente al final de esta spec.

### TDD

1. El botón no aparece si hay clave, si Apple FM sirve, o si ya hay un modelo
   usable. Tres tests, porque son tres razones distintas.
2. El progreso se deriva del NDJSON del daemon, con un transporte falso.
3. Cancelar corta la petición y no deja estado a medias.
4. Disco lleno, red caída y daemon muerto producen tres copys distintos.
5. Al terminar se re-escanea y el modelo queda seleccionado.
6. **Ningún test de esta pieza descarga nada de verdad.** El transporte es
   falso, como el resto de la wave.

### Solapamiento con Wave 9

Wave 9 sigue abierta en "los especialistas no instalados se ofrecen igual que
los disponibles". Misma forma de problema que 9b-4 resuelve para los modelos:
no ofrecer lo que no está, y cuando se ofrezca, que lleve a algún lado. Ya hay
adapters con el patrón — `HermesProviderScan`, `CLIExecutorProbe`. Se reutiliza
el patrón; no se escribe un tercer probe con otra forma.

---

## Fuera de alcance, por decisión

- Meter GGUF o MLX dentro del `.app`.
- **Descargar e instalar Ollama desde la app.** Traerse el instalador firmado
  de otro proveedor y ejecutarlo es cadena de suministro, no detección.
  Exigiría su propio ADR. Se enlaza a `ollama.com`.
- **Un segundo protocolo full-duplex** que sustituya a OpenAI Realtime. Ver la
  tabla de voz: el codec y el transporte están escritos contra el esquema de
  OpenAI, y cambiarlo es reescribirlos, no configurarlos.
- Bundlear un TTS neuronal (Kokoro, Qwen3-TTS). El puerto `SpeechSynthesizer`
  ya deja el hueco abierto; se evalúa solo si `AVSpeechSynthesizer` duele en
  uso real.
- Capa de conocimiento o memoria.
- Notarización con cuenta de Apple Developer. Vive en Wave 9.
- Windows y Linux.

---

## Criterios de done

1. **Mac sin clave, con Ollama y un modelo instalado: el primer mensaje
   responde.** Con dos umbrales, porque uno solo falla por azar — el primer
   request tras arrancar Ollama carga pesos y el segundo no.

   | | Umbral **provisional** | Hardware de referencia |
   |---|---|---|
   | Caliente (modelo ya cargado) | primer token ≤ 2 s | M-series, 16 GB, clase 7-8B Q4 |
   | Frío (primer request tras arrancar el daemon) | ≤ 30 s | mismo |

   **Y una trampa que hay que decir antes de medir:** la Mac de Karen es un
   M4 Max de 32 GB, y el hardware de referencia de la tabla es un M-series de
   16 GB. Medir en el M4 Max da el **mejor caso**, no el umbral. O el número se
   fija con margen sobre esa medición, o la promesa se acota por escrito a
   "Apple Silicon, 16 GB o más" y el número de 16 GB queda marcado como sin
   medir hasta que alguien lo pruebe. Lo que no vale es medir en la máquina más
   rápida de la casa y llamarlo el suelo del producto.

   **Los dos números están sin medir y Karen los confirma antes de codear.** Y el criterio de producto real del caso frío no es el número: es
   que **la UI diga que está cargando** y no parezca colgada.

2. Mac sin clave, sin Ollama, con Apple Intelligence encendido: mismo resultado
   por `SystemLanguageModel`. Solo aplica si 9b-2 pasó su puerta.
3. Mac sin clave, sin Ollama y sin Apple FM: el onboarding **no** presenta la
   clave como único camino.
4. **Tras aceptar la base local, el micrófono funciona sin clave.** La voz
   clásica entra con el mismo flag que el chat.
5. Con clave de OpenAI: Realtime y nube siguen igual. Sin regresión en la
   confianza voz-encargos de las Waves 8 y 9.
6. Aceptar un camino local **sobrevive al relaunch**.
7. El sondeo y el scan tienen tests, y **ningún test descarga un modelo ni sale
   de localhost**. Verificado por gate.
8. README: "Works without an API key when a local runtime is available; OpenAI
   is an upgrade."
9. **Ninguna clave es requisito y todas viven en el mismo panel.** Pegar una
   clave de Groq o de OpenRouter funciona igual que una de OpenAI, con su
   propia verificación contra su propio baseURL.
10. **El orden de la escalera es del usuario y sobrevive al relaunch.** Apagar
    todas las filas devuelve la base local en vez de dejar la app muda.
11. **La descarga del modelo base no aparece cuando no hace falta** — con
    clave, con Apple FM útil, o con un modelo ya instalado. Y cuando aparece:
    tamaño por delante, progreso en bytes, cancelable, y re-escaneo al acabar.
12. El copy nombra al proveedor donde la arquitectura lo obliga: **"Voz en
    tiempo real (OpenAI)"**, no "voz premium".
13. ADR 006 aceptado, con la corrección del pull escrita.

---

## Riesgos

| Riesgo | Mitigación |
|---|---|
| El usuario cree que local es igual que un modelo frontier | Copy de tier explícito. No se promete paridad agéntica con un 3B |
| Tool calling débil en modelos chicos | Para encargos, la recomendación mínima sube a la clase 7-8B |
| **La ventana de 4096 deja Apple FM en decorativo** | Se mide con `contextSize` antes de escribir el adapter. Es la puerta de evidencia de 9b-2 |
| Parpadeo de la raíz durante el sondeo | Estado `probing` explícito y un solo cambio de estado. Tiene su test |
| El scan envejece con la app abierta | "Reintentar detección", dicho en el copy. No se escanea por request |
| Apple FM solo en un subconjunto de Macs y de idiomas | La escalera. Ollama es el plan B universal |
| La tabla de RAM envejece | Es orientativa y está fechada. Vive en un solo sitio |
| Scope creep hacia un full-duplex propio | No-objetivo declarado. El protocolo es la implementación |
| **La descarga se percibe como un cuelgue** | Tamaño por delante, progreso en bytes del NDJSON, cancelación real, y tres mensajes de fallo distintos |
| Una clave de un panel se filtra a la petición de otro proveedor | Es el peor bug posible de 9b-3 y tiene test propio |
| El usuario apaga toda la escalera y se queda sin app | La lista vacía no existe: la base local vuelve |
| "Voz premium" promete una personalización que no hay | El copy nombra a OpenAI en el tier de tiempo real |
| La wave crece a cuatro piezas y cinco PRs | Dicho antes de empezar. Si hay que recortar, cae 9b-2, la única sin valor demostrado |

---

## Hechos del repo verificados (2026-08-22)

Todo lo de abajo se leyó del código:

- `ChatProviderClient.swift:93-103` — la escalera con salto por clave ausente y
  por probe caído ya existe.
- `ChatSSEAttempt.mapStatus` + `DeltaSink.finish` — un 404 sin texto emitido
  produce `.failed`, y el router hace `continue`. El fallback ya está.
- `VoiceSession.swift:184` — `preferRealtime: openAIKey() != nil`.
- `NativeExecutor.swift:9,65` — depende del puerto `ChatProvider`.
- `LiveCapabilityProbe.swift` — GET `/v1/models`, timeout 1 s, devuelve `Bool`.
- `EndpointPolicy.swift` — `http` y `ws` solo en localhost.
- `ChatViewModel.swift:120,125,177,334` — el muro de la clave.
- `ChatViewModel.swift:275` y `ClassicRuntime.swift:73` — una tool y ninguna.
- `Config.swift:5,45,57,61,140` — `SecretKey.groq` sin escritor, modelo
  constante, `preferredProviderName` sin escritor.
- `StoredConfigProvider.swift` — construye `chat: .default`: la preferencia no
  llega aunque se guarde.
- `UserPreferences.swift` — la forma a copiar para `ProviderPreference`.
- `RealtimeCodec.swift:25` — `wss://api.openai.com/v1/realtime?model=…`: el
  tier de tiempo real está atado a OpenAI a nivel de protocolo.
- `VoicePorts.swift` — `Transcriber` y `SpeechSynthesizer` son puertos; STT y
  TTS sí son huecos intercambiables. `OpenAITTS` y `SpeechSynthesis` son dos
  implementaciones vivas del segundo.
- `ChatProvider.verify(_:provider:)` — ya es genérica sobre el descriptor;
  `ChatViewModel.submitOnboarding` es quien la llama con `.openAI` cableado.
- `SecretKey` — tiene `openAI`, `groq` y `openRouter`; solo el tercero no tiene
  descriptor.
- `Package.swift` — `platforms: [.macOS(.v14)]`.
- Tests: 91 archivos, ~696 casos.

Del SDK instalado (`FoundationModels`, módulo 1.5.2, `macOS 26.0`):

- `SystemLanguageModel.contextSize` — `@backDeployed`, 4096.
- `SystemLanguageModel.availability` — `deviceNotEligible`,
  `appleIntelligenceNotEnabled`, `modelNotReady`.
- `SystemLanguageModel.supportedLanguages`.
- `LanguageModelSession.streamResponse`,
  `GenerationError.exceededContextWindowSize`, `DynamicGenerationSchema`.

---

## Estado del checklist de APROBADO

| # | Condición | Estado |
|---|---|---|
| 1 | Estado de sondeo + API de aceptar sin clave | Cerrado: tabla de estados, regla anti-parpadeo, `acceptLocalBase` |
| 2 | Cuándo se re-escanea + qué es modelo usable | Cerrado: scan al armar catálogo + botón; cinco reglas de usable |
| 3 | Dónde se reintenta tras model-not-found | Cerrado **leyendo el código**: ya se recupera. Test de caracterización, sin archivo nuevo |
| 4 | Números frío/caliente | Provisionales escritos y marcados. **Falta que Karen los mida** |
| 5 | Encargos con solo Apple FM | Cerrado: `delegate` no se ofrece, frase explicativa |
| 6 | Dónde se persiste `preferredProviderName` | Cerrado, y en 9b-3 crece a `providerOrder` |
| 7 | ADR 006 enlazado al 004 con el pull | Escrito, y **corregido en v3**: el pull entra por la API HTTP del daemon |
| 8 | Groq: UI o silencio | **Cerrado por Karen:** clave secundaria en Ajustes, como todas |

### Lo que la decisión de Karen añadió (2026-08-22)

| Decisión | Dónde vive |
|---|---|
| Toda clave es secundaria; ninguna es requisito | Modelo de tiers + 9b-3 |
| La escalera y los modelos son personalizables | 9b-3, `providerOrder` |
| La descarga del modelo base es opcional y va en la app | 9b-4, vía `POST /api/pull` |
| El tier de voz en tiempo real es de OpenAI | Tabla de voz. STT y TTS **sí** son personalizables |

### El hueco que se acepta a sabiendas

Persona no técnica, Mac que no califica para Apple Intelligence, sin Ollama
instalado. 9b-4 le descarga el modelo, pero **no le instala el daemon**: queda
un enlace a `ollama.com` y un paso manual.

**Cerrado el 2026-08-22: el enlace basta.** Traerse el instalador firmado de
otro proveedor y ejecutarlo es cadena de suministro, no detección, y exigiría
su propio ADR. Se acepta el hueco y se documenta en `FIRST-RUN.md` en vez de
taparlo con código.

---

## Respuesta a la intuición que originó la spec

Sí: los pesos se traen en runtime desde una fuente — el pull de Ollama, o el
propio OS — y no se mezclan con la instalación de Companion.

- El DMG sigue siendo una app, no un zoológico de GGUF.
- El modelo correcto depende de la RAM de quien la usa, no de la de quien la
  escribe.
- Actualizar el cerebro no obliga a republicar el producto.
- Es lo que el ADR 004 ya decidió para las capacidades ajenas.

La corrección al borrador es de precedente y de límite: el ADR que sostiene
esto es el 004; y ese mismo ADR autoriza leer, no ejecutar. La única descarga
que Companion debería orquestar es, por ahora, ninguna.
