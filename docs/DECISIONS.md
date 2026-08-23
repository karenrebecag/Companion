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

**Fecha:** 2026-08-21 · **Estado:** aceptada (sustituye a la version previa)

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
