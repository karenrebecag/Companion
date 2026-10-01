# Decisiones de arquitectura

## ADR 001 — Desacoplar Hermes: absorber capacidades, no el ecosistema

**Fecha:** 2026-08-20 · **Estado:** aceptada (pendiente ratificar en spec Wave 4)

### Contexto

El prototipo original depende de hermes-agent (Python + Node, instalado en
`~/.hermes/hermes-agent`) para cuatro cosas de peso muy distinto:

| Capacidad | Uso real en el original | Peso de la dependencia |
|---|---|---|
| API keys | dotenv `~/.hermes/.env` (`TalkClient.swift:48`, `SettingsStore.swift:146`) | Accidental: solo es un archivo de texto |
| STT fallback | subprocess Python faster-whisper (`Hermes.swift:264`) | Baja: el camino caliente ya es SFSpeechRecognizer del sistema (`Transcribe.swift:6-8`) |
| TTS fallback | subprocess Python `tools.tts_tool` (`Speech.swift:261`) | Baja: el primario ya es OpenAI TTS |
| Ejecutor especialista | `hermes chat -Q` como uno de dos brains (`Hermes.swift:3`, `JobRunner.swift:185-187`) | Alta: la mitad de la delegacion |

hermes-agent es un ecosistema completo (40+ tools, skills auto-mejorables,
gateways Telegram/Discord/etc., multiples backends de terminal). Exigirlo
como requisito mata la adopcion: un usuario nuevo no va a instalar un agente
Python para probar una app de voz.

### Decision

**Ninguna capacidad del producto requiere Hermes.** Se absorbe lo minimo de
su *diseno* (no su codigo: es Python, nosotros Swift) y todo lo demas se
resuelve nativo:

1. **Keys** -> Keychain via `Config` (ya decidido, Wave 2). Muere `~/.hermes/.env`.
2. **STT** -> SFSpeechRecognizer on-device como unico camino local; la
   transcripcion de la sesion Realtime (gpt-4o-mini-transcribe) cubre voz en
   vivo. Evaluar el API SpeechAnalyzer de macOS 26 como upgrade. Cero Python.
3. **TTS** -> OpenAI TTS primario + AVSpeechSynthesizer (nativo, offline,
   gratis) como fallback. Cero Python.
4. **Ejecutor** -> `NativeExecutor` integrado en CompanionServices: loop de
   agente en Swift (chat/completions con tool calling contra CUALQUIER
   endpoint OpenAI-compatible: OpenAI, OpenRouter, Groq, Ollama) con un set
   curado y deliberadamente chico de tools nativas — leer/escribir/editar
   archivo, shell, fetch web, busqueda — todas pasando por el sistema de
   approvals propio. Funciona con la misma API key del chat: valor inmediato
   sin instalar nada.

Claude Code y Hermes quedan como **adapters opcionales del puerto `Executor`,
detectados en runtime** (binario en PATH -> aparece la opcion). La escalera:
`NativeExecutor` (siempre) < Claude Code (si esta) < Hermes (si esta).

### Que se toma de hermes-agent (MIT, con atribucion en NOTICE.md)

- Referencia de schemas/nombres de tools y semantica del loop.
- La cadena de modelos abiertos como *configuracion posible* del
  NativeExecutor (OpenRouter/Ollama), que es el valor real que Hermes
  aportaba a Karen.

### Que NO se toma (explicitamente fuera)

Skills auto-mejorables, gateways de mensajeria, backends de terminal remotos,
plugins, los 40+ tools. Si el NativeExecutor empieza a crecer hacia eso, es
smell de scope: para poder infinito ya existen los adapters opcionales.

### Consecuencias

- Wave 4 se reescribe: su entregable central es el NativeExecutor + puerto
  Executor + approvals; los adapters CLI son la cola de la wave, no el centro.
- El sandbox/approvals es responsabilidad NUESTRA (ya no se hereda de
  `~/.hermes/config.yaml`): politica en Config, confirmacion humana en UI/voz,
  auto-deny con timeout (ver ledger).
- `Brain` deja de ser {fast, hermes, claude} hardcodeado: es una lista de
  ejecutores descubiertos + el nativo.

### Nota 2026-08-24 — la septima tool, y por que no viola el "chico"

El set nativo pasa de seis a siete con `list_directory`. Se anota aqui porque
este ADR eligio un set "curado y deliberadamente chico" y advirtio que crecer
hacia los 40+ tools de hermes seria smell de scope.

**El disparador fue de uso real, no de deseo.** Karen pidio buscar una carpeta
en el escritorio; el especialista contesto "no encontre ninguna carpeta llamada
'Software Development Projects'". La carpeta existe y se llama
`SoftwareDevProjects`. No fue torpeza del modelo: con seis tools, `read_file`
exige saber la ruta y la unica forma de mirar alrededor era `run_shell`, que
pide aprobacion humana en cada comando. El especialista no tenia ojos.

**Por que una tool y no una busqueda.** La tentacion era `find_files` con glob
o substring. No habria servido: "Software Development Projects" no coincide con
`SoftwareDevProjects` por ninguna de las dos. Lo que faltaba no era mejor
busqueda sino VER la lista y dejar que el modelo reconozca el nombre. Una
primitiva, no un motor.

**Por que es `.safe`.** Si mirar costara una aprobacion, explorar una carpeta
costaria un clic por nivel y el especialista volveria a adivinar rutas en vez
de mirarlas. Escribir sigue pidiendo permiso; mirar no.

El limite del ADR sigue en pie: la siguiente tool exige el mismo ejercicio —
un fallo observado, y la prueba de que ninguna de las que ya existen lo cubre.

---

### Nota 2026-08-24 — la octava tool, con una razon mas debil y dicha asi

`find_places` (MKLocalSearch, nativo y sin clave) entra al set nativo.

**El disparador NO fue un fallo observado**, y eso importa: la nota anterior
fijo la regla de que cada tool nueva exige un fallo visto y la prueba de que
ninguna existente lo cubre. Aqui no hemos visto un pin equivocado. Lo que hay
es un defecto de arquitectura documentado — las tarjetas de lugares las
originaba el MODELO, escribiendo coordenadas de memoria dentro de un fence — y
la industria define lo contrario: la aplicacion aporta el dato y el modelo solo
elige que mostrar.

Es una razon legitima y es mas debil que la de `list_directory`. Queda escrita
como lo que es, para que la regla no se ablande por acumulacion.

**Lo que ninguna tool existente cubria:** `web_search` devuelve prosa, no
coordenadas. Que el modelo las extraiga de la prosa es exactamente el paso que
esta wave elimina.

**Lo que NO se hizo, y por que.** Prohibir el fence habria dejado sin tarjetas
a los especialistas CLI, que no corren nuestras tools y solo devuelven texto.
En vez de eso la tarjeta lleva PROCEDENCIA: la nacida de una consulta se pinta
como siempre; la que escribio el modelo lo dice en pantalla. Si no podemos
impedir que la invente, dejamos de presentarla con la misma autoridad que un
dato verificado.

---

## ADR 002 — Actualizaciones sin Sparkle

**Fecha:** 2026-08-21 · **Estado:** aceptada

### Contexto

Wave 5 pide actualizaciones. El estandar de facto en macOS es Sparkle, que
seria la PRIMERA dependencia externa del proyecto.

### Decision

No usar Sparkle. Publicar releases en GitHub y comprobar la version contra la
API publica de releases (~80 lineas, testeables, sin dependencias).

### Por que

Hoy el repo se clona y compila sin descargar nada de terceros: no hay cadena
de suministro que auditar ni versiones que mantener al dia. Para una app que
maneja las llaves de la usuaria y ejecuta comandos en su disco, esa propiedad
vale mas que la comodidad de las actualizaciones automaticas en segundo plano.

### Consecuencias

La actualizacion no es silenciosa: la app avisa y abre la pagina de la
release. Si algun dia el proyecto crece hasta necesitar actualizacion
delta o firmada por EdDSA, se revisa este ADR.

### Nota 2026-08-22 — la premisa perdio una parte

"Se clona y compila sin descargar nada de terceros" dejo de ser cierto al
aceptarse ADR 003: `vendor/RiveRuntime.xcframework` es un binario
precompilado. La decision NO se reabre — Sparkle sigue fuera —, pero el
argumento honesto ya no es "cero terceros" sino **uno solo, elegido,
atribuido y fijado por checksum** en `NOTICE.md`. Un segundo binario exige
su propio ADR; si alguna vez son varios, este ADR se revisa entero.

## ADR 003 — Rive para la mascota (revisa y REVIERTE la version original)

**Fecha:** 2026-08-21 · **Estado:** RETIRADA 2026-09-29 (16p-2)

> **Retirada.** La mascota dejó de mostrarse en la reconstrucción de la UI (16c–16n: la
> identidad pasó al orbe) y `Mascot.swift` quedó sin instancias. 16p-2 la borró y Karen pidió
> quitar Rive (2026-09-29): sin binario tercero en el bundle. Lo que sigue es el registro de por
> qué entró; volver a meter un binario exige una ADR nueva.

### Que decia la version original

"El orb en SwiftUI, no en Rive": rechazaba el runtime de Rive porque
"anade un binario de 8 a 15 MB al DMG".

### Por que se revierte

El argumento era flojo y no estaba medido. Al medirlo:

| | Peso |
|---|---|
| App sin mascota | 8.7 MB |
| RiveRuntime dentro del .app | 15 MB |
| El .riv de la mascota | 0.5 MB |
| **App con mascota** | **24 MB** |

24 MB es un tercio de lo que ocupa Slack y lo mismo que pesaba el prototipo.
Para una app de escritorio en 2026, el peso NO es un costo relevante, y
rechazar por esa razon una pieza de identidad del producto fue un error de
criterio: exactamente la clase de simplificacion con perdida visual que el
principio rector de Wave 6 prohibe.

### Decision

La mascota del prototipo (`hello.riv`, con su maquina de estados y sus
listeners de puntero) se integra con RiveRuntime vendoreado como
`binaryTarget`, sin dSYMs (15 MB en el repo en vez de 56).

### El costo que SI se asume, dicho con claridad

Rive entra como **binario precompilado que nadie puede auditar**, en un
proyecto cuyo valor declarado era "se clona y compila sin descargar nada de
terceros". Ese es el argumento honesto en contra, no el tamano. Se acepta
porque la mascota es identidad del producto y su dueña la quiere. Los ADR
001 y 002 (sin ecosistema Hermes, sin Sparkle) siguen en pie: esta es la
UNICA dependencia binaria del proyecto y ampliarla exige otro ADR.

### Trampas resueltas (para quien toque el empaquetado)

- SPM no sabe que el framework viaja en el bundle: hay que anadir el rpath
  `@executable_path/../Frameworks` al binario despues de copiarlo, o dyld no
  lo encuentra y la app muere al arrancar sin decir por que.
- Rive resuelve `fileName` contra el bundle PRINCIPAL, no contra el bundle
  del modulo donde SPM guarda los recursos: el `.riv` se copia a
  `Contents/Resources`.
- El framework se firma con la misma identidad que la app, antes que ella.


## ADR 004 — Deteccion de capacidades ajenas: leer, jamas acoplar

**Contexto.** El prototipo ofrecia 12 modelos, pero las filas de Copilot y
Grok cableaban en el menu los perfiles OAuth personales de UNA Mac — la
espaguetizacion que motivo el rebuild. La regla "cero paths a ~/.hermes"
nacio de ahi. Al restaurar el selector de modelos hizo falta distinguir dos
cosas que esa regla mezclaba.

**Decision.** Se prohibe el acoplamiento de CONFIGURACION (el producto
requiere/escribe/asume dotfiles); se permite la DETECCION de solo lectura
de capacidades de un CLI opcional ya detectado, bajo tres condiciones:
vive en un unico adapter (`HermesProviderScan`), es read-only, y el
producto se comporta identico cuando el archivo no existe. Es la misma
familia que sondear `~/.local/bin` buscando el binario.

**Consecuencia.** El catalogo de especialistas se arma en runtime: tiers de
claude por alias documentado del CLI (Sonnet por defecto, como el
claudeWorker del prototipo), y una fila por proveedor que hermes ya tenga
en su cache de modelos. En una Mac sin CLIs el catalogo queda vacio y solo
existe el ejecutor nativo (ADR 001 intacto).

---

## ADR 005 — El encargo es UI asistiva: no habla por su cuenta

**Contexto.** La Wave 8 le dio voz al encargo por dos motivos buenos: un
permiso que nadie miraba moria en el auto-deny de los 120 s, y la voz seguia
diciendo "voy en camino" despues de que el encargo habia terminado. Ambas se
resolvieron mandando items de sistema al modelo para que narrara. Medido
despues, eso producia dos mensajes por un resultado: el texto del especialista
entraba al hilo como mensaje del assistant, y la parafrasis hablada volvia a
entrar al transcribirse. El que sonaba era el resumen del que estaba escrito.

**Decision (Karen, 2026-08-22).** Un encargo es UI asistiva y no habla por su
cuenta. Solo se leen las respuestas del assistant. En concreto:

- El resultado vuelve **una vez**: el texto del especialista es el mensaje del
  hilo y la voz solo acusa que termino, sin releerlo.
- El permiso **no se pregunta en voz alta**: vive en la hoja.

**Referencia.** Es la forma en que OpenAI cierra una tool: el resultado vuelve
como `function_call_output` y el modelo produce UNA respuesta que lo incorpora
— la salida nunca llega a ser un segundo mensaje.

**Donde NO se copia, y por que.** Copiar el patron entero — resultado
invisible, el mensaje del hilo es lo que dice el modelo — se lleva por delante
el texto integro del especialista: rutas, comandos, codigo, y las cards, que
se renderizan del markdown del mensaje. Un encargo que devuelve un mapa
perderia el mapa. El artefacto se queda como mensaje; lo que se recorta es la
relectura. La condicion fue explicita: la forma de OpenAI mientras no quite
valor de producto.

**Consecuencias.**
- La garantia de la Wave 8 sobrevive por otra via: cual de los dos finales
  ocurrio lo decide `result.isError`, no el modelo. El fallo conserva su
  motivo, que es una linea que cambia lo que haces despues.
- Aprobar por voz pierde el aviso, no la respuesta: `resolve_approval` sigue
  declarada, asi que quien ve la hoja y dice "si, autorizalo" resuelve sin
  tocar el trackpad. Esto NO salio gratis: la descripcion de la tool exigia un
  anuncio previo del sistema, asi que al callar el anuncio quedaba prohibida la
  unica via que sobrevivia. Corregido el mismo dia; sin eso, este ADR
  prometia algo que el codigo negaba. Un permiso que nadie mira sigue muriendo en el auto-deny,
  ahora en silencio. Es el precio elegido.
- `Escalation.approvalAnnouncement` se fue con su llamador; dejarla probada y
  sin invocar es el patron que este repo lleva corrigiendo desde la Wave 8.
- Queda abierto: el acuse hablado no llega al pipeline clasico, donde no hay
  modelo que lo genere. Decidir si se dice por el sintetizador o si el clasico
  se queda mudo tambien para el acuse.

---

## ADR 006 — Base local, nube opcional

**Fecha:** 2026-08-22 · **Estado:** BORRADOR (sale de la spec Wave 9b)

**Contexto.** Companion se presenta como conversacion natural con el Mac y
acceso al ecosistema local de AI, con menos friccion que Siri, pero hoy solo
arranca con una clave de pago: `ChatViewModel.onAppear` decide el onboarding
leyendo unicamente la clave de OpenAI del Keychain, y `send()` esta detras de
ese flag. La escalera de proveedores YA salta los que no tienen clave y los
locales caidos (`ChatProviderClient:93-103`); el muro no esta en el routing,
esta en el arranque. Y el unico camino local que existe apunta a un tag
constante (`qwen3.6:27b`) que casi ningun Mac tiene instalado, asi que el
camino gratis falla en silencio antes de empezar.

**Decision.**

1. **La base no exige clave, y ninguna clave es requisito.** OpenAI, Groq y
   OpenRouter son la misma clase de cosa: claves secundarias que viven en
   Ajustes y suben el techo del producto. La unica razon por la que OpenAI
   parecia distinta es que era la unica, y por eso se comio el onboarding. El
   producto tiene dos personas: quien no sabe que es una API key, y quien pega
   las suyas para sacarle todo el jugo.

2. **Los pesos no viajan en el DMG.** Companion instala app y logica. Los pesos
   los aporta el sistema (Apple Foundation Models) o un runtime que el usuario
   ya tiene (Ollama). El binario no crece, actualizar el cerebro no exige
   republicar, y el modelo correcto lo decide la RAM de quien la usa.

3. **Detectar es leer.** El scan de los modelos instalados cumple las tres
   condiciones del ADR 004: vive en un unico adapter, es read-only sobre HTTP a
   localhost, y con Ollama apagado el producto se comporta identico. Es la
   misma familia que `HermesProviderScan`.

4. **La descarga del modelo base la orquesta la app, por la API del daemon.**
   Esta decision CORRIGE el borrador del mismo dia, que dejaba el pull fuera
   por el ADR 004. Se corrige por dos razones, y la segunda es la que importa:

   - De producto: quien no sabe que es una API key tampoco sabe que es una
     terminal. Ofrecerle un comando para pegar en Terminal.app es cambiar un
     muro por otro con mejor educacion.
   - De arquitectura: **Ollama expone el pull por HTTP**
     (`POST localhost:11434/api/pull`, NDJSON con progreso). Companion no
     ejecuta ningun binario ajeno — hace una peticion al daemon que el usuario
     ya decidio correr, sobre el mismo host que `EndpointPolicy` autoriza. Sin
     `Process`, sin PATH, sin shell. **El ADR 004 se respeta tal cual esta
     escrito**; la premisa que estaba mal era suponer que pull = subprocess.

   La descarga es opcional en las dos direcciones: nunca automatica, y no se
   ofrece siquiera a quien ya tiene un modelo usable, una clave, o Apple FM.

5. **Instalar el propio Ollama sigue fuera.** Traerse el instalador firmado de
   otro proveedor y ejecutarlo es cadena de suministro, no deteccion. Eso si
   exigiria su propio ADR. Companion enlaza a `ollama.com`.

6. **La escalera es del usuario.** El orden de proveedores y el modelo de cada
   uno dejan de ser constantes del codigo: son configuracion persistida
   (`providerOrder`), reordenable y apagable, con la base local por defecto
   delante porque es gratis, privada y no depende de la red. Apagarlo todo
   devuelve la base local: una app sin ningun camino no es una configuracion,
   es un fallo.

7. **Apple FM no es una fila del catalogo.** `ProviderDescriptor` tiene
   `baseURL` no opcional y todo lo que va aguas abajo asume un endpoint
   OpenAI-compatible sobre HTTP y SSE. `SystemLanguageModel` es una API
   in-process. Entra como un `ChatProvider` compuesto en la raiz de
   composicion, que es la junta que el puerto ya ofrece.

**Consecuencias.**

- `needsOnboarding` deja de significar "no hay clave de OpenAI" y pasa a
  significar "no hay ningun camino vivo". La decision se vuelve asincrona, con
  un estado de sondeo explicito para que la raiz no parpadee.
- `ProviderDescriptor.model` deja de ser constante: el catalogo efectivo se
  arma en runtime en la raiz de composicion, donde `ChatProviderClient` ya
  acepta que se lo inyecten.
- `ChatSettings.preferredProviderName` se sustituye por `providerOrder`.
  Sustituir sale gratis: hoy nadie escribe ese campo, y `StoredConfigProvider`
  pasa `chat: .default`, asi que no hay dato viejo que migrar.
- `ChatProvider.verify(_:provider:)` ya es generica sobre el descriptor;
  verificar Groq u OpenRouter no necesita codigo nuevo, solo dejar de llamarla
  con `.openAI` cableado. A `SecretKey.openRouter` le falta su descriptor.
- **Un limite que no se puede configurar, y se nombra en el copy:** el tier de
  voz en tiempo real es de OpenAI y punto. `RealtimeCodec:25` construye
  `wss://api.openai.com/v1/realtime`; el codec, los eventos y el transporte
  estan escritos contra ese esquema. Cambiar de proveedor ahi no es un campo de
  configuracion, es un segundo protocolo full-duplex. En cambio STT y TTS **si**
  son huecos intercambiables: `Transcriber` y `SpeechSynthesizer` son puertos, y
  el segundo ya tiene dos implementaciones vivas. Por eso el copy dice "Voz en
  tiempo real (OpenAI)" y no "voz premium".
- El techo de contexto de Apple FM (`contextSize`, 4096 tokens de entrada y
  salida juntos, leido del SDK) obliga a un presupuesto de historia propio para
  ese proveedor. Si no da para una conversacion util, el adapter no se escribe:
  es la puerta de evidencia de la pieza 9b-2.

---

## ADR 007 — Manifiesto de host nativo en la carpeta del navegador

**Fecha:** 2026-09-29 · **Estado:** ACEPTADO (spec Wave 18, D5 y D7)

**Contexto.** Para que la extension hable con la app, Chrome exige un
manifiesto `com.karen.companion.browser.json` dentro de
`NativeMessagingHosts/` del propio navegador (Chrome y Comet). No hay otro
camino: es escribir en la config de otra app, justo lo que ADR 004 prohibe.

**Decision.** Excepcion explicita y acotada a ADR 004. `NativeHostInstaller`
escribe el manifiesto solo cuando Karen pulsa *Conectar navegador* en Ajustes;
*Quitar* lo borra; sin pulsar el boton no se escribe nada, ni al arrancar ni
al actualizar. Solo toca navegadores detectados (existe su carpeta de soporte),
escribe de forma atomica con modo 0644, se niega si el destino es un symlink y
`Quitar` solo borra un archivo cuyo campo `name` es el nuestro.

**Modelo de amenaza.** El candado 1 (`argv[1]` = origen de extension fijado)
es defensa en profundidad y nada mas: cualquier proceso del mismo usuario puede
lanzar el binario con ese argumento. Los candados reales son el token por
lanzamiento y `getpeereid` en el socket del puente. El atacante del mismo uid
queda aceptado, como en la wave 17. No hay puerto TCP ni secreto de larga vida.

**Consecuencia.** El estado "conectado" es la existencia de un manifiesto
nuestro, no un flag guardado. Disparador de mejora: con cuenta de Apple
Developer, pasar el secreto al Keychain con acceso restringido por firma y
revisar este ADR.

---

## ADR 008 — Contadores de generacion: solo para descartar escrituras tardias

**Fecha:** 2026-10-01 · **Estado:** ACEPTADO (Aprobado por Karen 2026-10-01 [KAREN:chat 2026-10-01 via orquestador]; briefs `classic-turn-serialize` Q2 y `interrupciones-por-causa` R1)

**Contexto.** `ARCHITECTURE.md:79` dice "Cancellation is structured, not
generation counters". Sigue siendo la regla: cancelar con `Task.cancel()` y
esperar a que el trabajo termine. Pero hay trabajo que la cancelacion
estructurada no puede detener a tiempo: una herramienta del turno clasico que
espera un permiso del sistema o la ubicacion (hasta 50 s) no mira la
cancelacion, y su `cutTurn` llega despues de que el turno nuevo ya empezo.

**Decision.** Excepcion acotada. Un contador de generacion se permite solo para
**descartar las escrituras tardias** de trabajo que la cancelacion estructurada
no puede parar a tiempo; nunca para decidir si cancelar. El trabajo se sigue
cancelando con `Task.cancel()`; el contador solo protege lo que escribe al
despertar. Precedentes, con su ubicacion actual:

- `realtimeGeneration`: declarado en `VoiceSession.swift:113`, bumpeado en
  `VoiceSession+Pumps.swift:14` y comprobado en `VoiceSession+Pumps.swift:128`
  y `:167` (#59, `72c36eb`: una reconexion de la sesion anterior se aparta).
- `holdGeneration`: declarado en `VoiceSession.swift:145`, bumpeado en
  `VoiceSession+Hold.swift:66` y `:214`, comprobado en
  `VoiceSession+Hold.swift:178` y `:197`, `VoiceSession+Pumps.swift:381` y
  `VoiceSession+Timeline.swift:22`.
- `armGeneration`: `HoldKeyTap.swift:33`, bumpeado en `:149`, `:181` y `:205`,
  comprobado en `:212` (un armado tardio del tap de la tecla).
- `turnGeneration` (nuevo): campo de `Crossing` en `ClassicRuntime.swift`,
  bumpeado por `supersedeStuckTurn()` cuando vence la espera, comprobado en
  `cutTurn` antes de leer `spokenSoFar`, antes de enhebrar el parcial y al
  poner `steerPending`.

**Espera acotada.** Cada turno clasico espera al turno cortado que lo
precede, con un plazo inyectable (`turnWaitDeadline`, 2 s por defecto, el mismo
para toda causa de corte). Al vencer, el turno nuevo empieza igual y sube la
generacion; el cut tardio del atascado no enhebra su parcial ni deja nota. La
espera NO es estructurada a proposito: `await task.value` no se interrumpe por
cancelacion, y un plazo con `withTaskGroup` espera igual a su hijo y no acota
nada (sondas A1 y A2 del brief). Son dos tareas sueltas que reanudan una
continuacion una sola vez, con un `Mutex`; el antecesor no se cancela ni se
espera al vencer.

**Consecuencia.** Un turno cortado antes de que sus palabras lleguen al modelo
no deja rastro (Q3). El control y la escritura del hilo son dos pasos: un bump
entre ambos aun enhebra ese parcial; marcado `HACK:` en `cutTurn`, con su
disparador de mejora. Todo contador nuevo exige entrar en la lista de arriba.
