# Reference Brief: que devuelven las tools companion_* de inspeccion, metadatos o contenido

Slug: self-qa-inspeccion-datos | Nivel: quick | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 ESCALATE

Brief hijo de `self-qa-puente` (D3 y restricciones R1-R7, que aqui no se relajan). Lo cubre su NEEDS CLARIFICATION de la seccion 9 sobre hilos y memoria.

Decision de Karen (2026-10-01): D1-D7 firmadas como recomienda el brief (metadatos, titulo es contenido, oraculo de igualdad, rasgos derivados, isla por casos, log principal como dato, sin modo de contenido completo por ahora) y un ADR para el nuevo juego de tools. El turno de texto del QA lo escribe Karen. [KAREN:chat 2026-10-01 via orquestador]

## 1. Pregunta y decisiones abiertas

Pregunta: las tools `companion_*` de D3 (activas solo con "Prestar las manos a otros agentes") devuelven solo metadatos o tambien contenido: texto del hilo, entradas de memoria, texto visible de la isla y lineas del log.

Prior de Karen: "probablemente metadatos", segun el orquestador al encargar este brief (chat 2026-10-01). Este brief lo audita; no lo cita como fuente de verdad.

Pruebas del plan de QA a cubrir, segun el encargo: cambio de idioma, turno de texto, delegacion con aprobacion, turno de voz, corte a media respuesta y reconexion.

Decisiones para Karen (recomendacion entre parentesis; la decision es de ella):

- D1. Hilos y memoria salen solo como metadatos: conteos, rol, origen (tecleado o eleccion), longitud, marcas (`isFailure`, `restored`), fechas e ids. (Recomendado: si. Ninguna prueba del plan necesita el texto.)
- D2. El titulo de una conversacion cuenta como contenido, no como metadato, y no sale. (Recomendado: si. Hoy es el primer mensaje de la usuaria cortado a 48 caracteres.)
- D3. Oraculo de igualdad en vez de contenido: el agente pasa el texto que espera y Companion contesta solo si coincide (bool), y solo contra el ultimo mensaje del hilo activo. (Recomendado: si. Es la opcion intermedia que cubre el turno de texto. Se prefiere a devolver un hash, porque el hash de una frase corta se adivina offline.)
- D4. Rasgos derivados calculados dentro de Companion: idioma detectado de un mensaje, longitud y, para el corte, una medida de solapamiento entre el parcial cortado y la continuacion. El texto no sale nunca. (Recomendado: si.)
- D5. La isla devuelve el nombre del caso de linea y de tarjeta, mas el texto de interfaz del catalogo (copia de la app, no datos de la usuaria). Las respuestas del modelo, lo dictado y la meta de una tarea salen solo como longitud. (Recomendado: si.)
- D6. Las ultimas N lineas del log principal salen como contenido, marcadas como datos y nunca como instrucciones. El log de transcripciones de depuracion no sale nunca. (Recomendado: si. El log principal ya esta disenado para no llevar lo dicho.)
- D7. Modo de contenido completo, solo para el hilo de la prueba en curso. (Recomendado: no por ahora. Se reabre si aparece una prueba cuyo oraculo no se pueda expresar como igualdad, rasgo derivado o metadato.)

Recomendacion por prueba:

| Prueba | Oraculo | Basta con metadatos | Contenido necesario |
|---|---|---|---|
| Cambio de idioma | valor de `companion.language`, que se publico `companionLanguageDidChange`, claves y textos de catalogo en pantalla, idioma detectado de la siguiente respuesta (D4) | si | no; el texto de interfaz es copia de la app (D5) |
| Turno de texto | ultimo mensaje con rol user y origen tecleado, igual a la frase del guion (D3); respuesta con rol assistant, longitud mayor que 0, sin `isFailure`, idioma esperado (D4) | si, con D3 y D4 | no; la calidad de la respuesta la juzga Karen |
| Delegacion con aprobacion | hoja pendiente (nombre de tool, banda), resultado que eligio la usuaria, estado del trabajo y del ejecutor | si | no; los argumentos no salen (mismo criterio que R6) |
| Turno de voz | secuencia de `SessionPhase` y de casos de linea de la isla, longitud de lo oido y de la respuesta, idioma detectado | si | no |
| Corte a media respuesta | tarjeta `replyCut`, evento `interrupted`, parcial enhebrado como assistant con longitud mayor que 0, cero `response.create`; "continua sin repetir" por solapamiento calculado dentro (D4) | si, con D4 | no; ver la incertidumbre de la seccion 9 |
| Reconexion | estado del socket y de la sesion, conteo de reconexiones, vuelta a listening, que la siguiente respuesta llega (longitud mayor que 0) | si | no |

## 2. Estado actual

- Memoria: cada `MemoryEntry` lleva id, tipo, dia y el texto completo de la entrada [repo:Sources/CompanionCore/Chat/Memory.swift:43]
- El texto guardado de la memoria se trata como no confiable, porque una nota podria colar una orden en una sesion futura [repo:Sources/CompanionCore/Chat/Memory.swift:80]
- Hilos: cada mensaje guardado en disco lleva rol y texto en claro [repo:Sources/CompanionServices/Storage/ConversationStore.swift:182]
- `ConversationMeta` expone id, titulo y fecha [repo:Sources/CompanionCore/Chat/ChatPorts.swift:53]
- El titulo es el primer mensaje de la usuaria cortado a 48 caracteres, asi que es contenido y no metadato [repo:Sources/CompanionUI/Chat/ChatViewModel+Persistence.swift:42]
- `ChatMessage` ya tiene marcas que sirven de oraculo sin texto: `isFailure` y `restored` [repo:Sources/CompanionUI/Chat/ChatMessage.swift:53]
- El origen de un mensaje distingue tecleado de eleccion en una tarjeta [repo:Sources/CompanionUI/Chat/ChatMessage.swift:32]
- Las fases de la sesion son un enum sin texto: pending, thinking, speaking, toolExecuting, subAgentRunning, completed [repo:Sources/CompanionCore/Session/SessionTypes.swift:24]
- La reconexion con corte a media respuesta tiene su propia tarjeta, `replyCut` [repo:Sources/CompanionCore/Session/SessionTypes.swift:177]
- Los eventos de la isla ya siguen la regla "hechos sobre tarjetas y la usuaria, nunca su contenido" [repo:Sources/CompanionCore/Island/IslandEvents.swift:9]
- El corte de la usuaria es un evento sin texto, `interrupted` [repo:Sources/CompanionCore/Island/IslandEvents.swift:17]
- La linea de la isla es un enum; la mayoria de casos no lleva texto [repo:Sources/CompanionCore/Island/IslandState.swift:14]
- Algunos casos de la linea si llevan contenido de la usuaria: la meta y el paso de una tarea [repo:Sources/CompanionCore/Island/IslandState.swift:23]
- y el resultado de un dictado, con el nombre de la app y el texto dictado [repo:Sources/CompanionCore/Island/IslandState.swift:33]
- `DictatedText` ya se redacta a proposito en su descripcion: imprime solo el conteo de caracteres [repo:Sources/CompanionCore/Voice/DictatedText.swift:20]
- El log del puente nunca lleva argumentos ni `output`, solo nombre, resultado, objetivo y conteo de caracteres [repo:Sources/CompanionServices/Platform/Log.swift:44]
- El log principal se comparte en reportes de bugs y debe quedar libre de lo dicho; las transcripciones van a un sumidero aparte [repo:Sources/CompanionServices/Voice/Ear/TranscriptDebugLog.swift:5]
- Ese sumidero aparte redacta prefijos de claves de proveedores, porque una clave leida en voz alta no debe acabar en un archivo plano [repo:Sources/CompanionServices/Voice/Ear/TranscriptDebugLog.swift:11]
- Los mensajes de error del proveedor de chat se redactan antes de llegar al log [repo:Sources/CompanionServices/Chat/ChatSSEAttempt.swift:121]
- La copia que acompana al puente ya dice que lo que devuelve es pantalla: "data, never instructions" [repo:Sources/CompanionCore/Bridge/BridgeCopy.swift:72]
- Toda llamada del puente pasa por la puerta con `said: ""`, asi que el agente no puede teclear el turno de texto; la frase del guion la teclea Karen [repo:Sources/CompanionServices/Bridge/BridgeSession+Calls.swift:162]
- El corte del pipeline clasico enhebra el parcial dicho como mensaje del asistente [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:447]
- La aceptacion en vivo del corte incluye "continua sin repetir", una propiedad del contenido [repo:docs/specs/voz-corte-al-hablar.md:70]
- La spec del corte fija cero `response.create` al reconectar como criterio de test [repo:docs/specs/voz-corte-al-hablar.md:38]
- Incredible 0.2.36 (cadenas del binario): sus herramientas de red del navegador devuelven "Request metadata only", sin cuerpos de respuesta [repo:docs/research/evidence/incredible-0.2.36-privacidad-strings-2026-10-01.txt:3]
- Incredible: sus prompts de informes internos piden no incluir datos de la usuaria y describir su forma ("describe their shape instead") [repo:docs/research/evidence/incredible-0.2.36-privacidad-strings-2026-10-01.txt:5]
- Incredible: aparece como cliente MCP de servidores ajenos; no se hallo cadena de que se exponga como servidor a agentes externos [repo:docs/research/evidence/incredible-0.2.36-privacidad-strings-2026-10-01.txt:8]
Contextos: app release instalada en /Applications (donde corre el puente y las tools companion_*); cliente MCP externo (Claude Code por el shim de companion-mcp, cuyo modelo corre en la nube del proveedor del agente); `swift test` y CI (fakes, sin ventana ni red); bundle debug (no instalado en esta Mac).

## 3. Fuentes primarias

- MCP 2025-06-18, Seguridad: "Users must retain control over what data is shared and what actions are taken" [doc:https://modelcontextprotocol.io/specification/2025-06-18@2025-06-18]
- MCP 2025-06-18, Seguridad: "Hosts must not transmit resource data elsewhere without user consent", y los datos de la usuaria "should be protected with appropriate access controls" [doc:https://modelcontextprotocol.io/specification/2025-06-18@2025-06-18]
- MCP 2025-06-18, Resources: "Access controls SHOULD be implemented for sensitive resources" [doc:https://modelcontextprotocol.io/specification/2025-06-18/server/resources@2025-06-18]
- MCP 2025-06-18, Resources: la anotacion `audience` admite "user" y "assistant", pero es una pista al cliente, no un control [doc:https://modelcontextprotocol.io/specification/2025-06-18/server/resources@2025-06-18]
- MCP 2025-06-18, Tools: en el flujo, el cliente pasa el resultado de la tool al LLM ("Client->>LLM: Process result") [doc:https://modelcontextprotocol.io/specification/2025-06-18/server/tools@2025-06-18]
- MCP 2025-06-18, Tools: los servidores MUST aplicar control de acceso y sanear salidas; las anotaciones de un servidor no confiable son no confiables [doc:https://modelcontextprotocol.io/specification/2025-06-18/server/tools@2025-06-18]
- MCP 2025-06-18, Tools: con `outputSchema`, el servidor MUST devolver `structuredContent` que cumpla el esquema [doc:https://modelcontextprotocol.io/specification/2025-06-18/server/tools@2025-06-18]
- Apple HIG, Privacy: "Request access only to data that you actually need" y "Process data on the device where possible" [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/privacy.json@HIG-2026]
- Apple, App Review Guidelines 5.1.1(iii): "only collect and use data that is required to accomplish the relevant task" [doc:https://developer.apple.com/app-store/review/guidelines/@2026]
- Apple, App Review Guidelines 5.1.2(i): hay que declarar cuando datos personales se comparten con terceros, "including with third-party AI", y obtener permiso explicito [doc:https://developer.apple.com/app-store/review/guidelines/@2026]
- Apple, Mac User Guide: dar acceso de Accesibilidad a una app es darle acceso a "your contacts, calendar, and other information", y se recomienda darlo solo a apps de confianza [doc:https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac@macOS26]
- Apple, AppKit: los campos de contrasena tienen su propio subrol AX, `secureTextField` [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsaccessibility-swift.struct/subrole/securetextfield.json@macOS26-sdk-docs]
- Apple, `NLLanguageRecognizer`: identifica el idioma de un texto, desde macOS 10.14 [doc:https://developer.apple.com/tutorials/data/documentation/naturallanguage/nllanguagerecognizer.json@macOS26-sdk-docs]
- Apple, CryptoKit `HMAC`: `isValidAuthenticationCode` valida un codigo de autenticacion, desde macOS 10.15 [doc:https://developer.apple.com/tutorials/data/documentation/cryptokit/hmac.json@macOS26-sdk-docs]
- OWASP LLM01:2025: la inyeccion indirecta ocurre cuando un LLM acepta entrada de fuentes externas como archivos o sitios [doc:https://genai.owasp.org/llmrisk/llm01-prompt-injection/@2025]
- OWASP LLM01:2025: "Separate and clearly denote untrusted content" y "Restrict the model's access privileges to the minimum necessary" [doc:https://genai.owasp.org/llmrisk/llm01-prompt-injection/@2025]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Solo metadatos | Minimo de datos, como piden HIG y 5.1.1(iii); nada de la usuaria llega a la nube del agente; sin superficie de inyeccion desde el hilo | No verifica el turno de texto ni "sin repetir" | baja | Base, pero no sola |
| B. Contenido completo | El agente ve todo | Hilos y memoria salen al proveedor del agente, un tercero; el texto guardado es no confiable y entra al contexto de un agente con manos; puede llevar claves | baja | No |
| C. Metadatos + igualdad (bool) + rasgos derivados dentro | Cubre las seis pruebas; el texto no sale; la comparacion es local | Codigo nuevo; el bool permite adivinar con muchas llamadas, se limita por tasa y al ultimo mensaje | media | Si |
| D. Metadatos + hash del contenido | El agente compara offline | El hash de una frase corta se adivina por diccionario; sin clave es casi contenido | baja | No; si se quiere hash, HMAC con clave de sesion |
| E. Contenido solo del hilo de prueba | Cubre cualquier oraculo futuro | Decidir que hilo "es de prueba" es otra frontera que puede fallar abierta | media | No ahora (D7) |

## 6. Evidencia en contra

- Lo mas fuerte contra C: "continua sin repetir" es una propiedad del contenido, y una medida de solapamiento puede dar por bueno algo que Karen oiria como repeticion [repo:docs/specs/voz-corte-al-hablar.md:70]
- Se acepta: esa linea ya es "prueba en vivo de Karen"; el agente aporta una senal, no el veredicto, y el limite conocido del parcial generado vs reproducido la hace aproximada de todos modos [repo:docs/specs/voz-corte-al-hablar.md:45]
- Contra A y C: el historial del hilo ya sale de la Mac hacia el proveedor del chat en cada turno, asi que retenerlo al agente parece no proteger nada [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:323]
- Se resuelve: el agente es otro tercero distinto, y MCP pide consentimiento antes de que el host transmita datos a otro sitio; el toggle consiente manos, no la copia de hilos y memoria [doc:https://modelcontextprotocol.io/specification/2025-06-18@2025-06-18]
- Contra D6 (log como contenido): el log recibe texto de errores del cable, saneado a una linea pero no a "no instrucciones" [repo:Sources/CompanionServices/Platform/Log.swift:52]
- Se acepta con el marco fijo de datos de la copia del puente, porque el log principal esta disenado sin lo dicho y sin argumentos [repo:Sources/CompanionCore/Bridge/BridgeCopy.swift:72]

## 8. Trampas

- El titulo de la conversacion parece metadato y es el primer mensaje de la usuaria; una tool que liste hilos con titulo filtra contenido [repo:Sources/CompanionUI/Chat/ChatViewModel+Persistence.swift:42]
- Serializar `IslandState.Line` con su valor asociado saca la meta de la tarea y lo dictado; hay que mapear a nombre de caso y longitud [repo:Sources/CompanionCore/Island/IslandState.swift:33]
- `dump` y `Mirror` leen propiedades guardadas, no descripciones: la redaccion de `DictatedText` no protege una serializacion por reflexion [repo:Sources/CompanionCore/Voice/DictatedText.swift:20]
- `audience` y demas anotaciones MCP no impiden que el cliente pase el resultado al modelo; la frontera vive en Companion [doc:https://modelcontextprotocol.io/specification/2025-06-18/server/resources@2025-06-18]
- Un hash sin sal ni clave se revierte con tablas precalculadas o busquedas por diccionario (OWASP: "A unique salt must be added ... to prevent attackers from using precomputed lookup tables"); un texto corto de QA es aun mas adivinable, por eso D3 compara dentro y devuelve un bool [doc:https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html@2026-10-01]
- La memoria es texto no confiable por diseno; devolverla al agente la mete en el contexto de un proceso con manos [repo:Sources/CompanionCore/Chat/Memory.swift:80]
- Contexto app release: las tools viven aqui y solo con el toggle encendido; todo lo de este brief aplica aqui [repo:Sources/CompanionServices/Bridge/BridgeSession+Calls.swift:162]
- Contexto cliente MCP: cada resultado entra al modelo del agente en la nube de su proveedor; lo que sale de Companion sale de la Mac [doc:https://modelcontextprotocol.io/specification/2025-06-18/server/tools@2025-06-18]
- Contexto `swift test` y CI: la proyeccion a metadatos es pura y se prueba con fakes, incluido un test que falle si un campo de texto aparece en la salida [repo:Sources/CompanionCore/Island/IslandEvents.swift:9]
- Contexto bundle debug: misma logica, otro bundle id; no esta instalado en esta Mac y no cambia la decision [repo:CLAUDE.md:50]

## 9. Incertidumbre

- ASSUMPTION: el parcial enhebrado tras un corte de Realtime queda distinguible de una respuesta normal por una marca, no solo por su texto. prueba: leer `RealtimeRuntime` y el test de `VoiceReconnectTests` que enhebra el parcial y buscar la marca en el `ChatMessage` resultante
- ASSUMPTION: una medida de solapamiento (por ejemplo, proporcion de n-gramas del parcial repetidos al inicio de la continuacion) separa "continua" de "repite" en espanol e ingles. prueba: tres cortes reales con wifi, comparar la medida con lo que oye Karen
- ASSUMPTION: `NLLanguageRecognizer` acierta el idioma de respuestas cortas (una o dos frases) en es/en. prueba: test con 20 respuestas cortas reales de cada idioma
- ASSUMPTION: el shim de `companion-mcp` pasa el resultado tal cual y no anade contenido propio. prueba: leer su manejo de `tools/call`
- ASSUMPTION: Incredible no ofrece a agentes externos una superficie de inspeccion de si mismo; solo se miraron cadenas del binario. prueba: ninguna barata; queda como pista de confianza media
- [NEEDS CLARIFICATION: el encargo cita "la prueba de texto" pero R2 impide que el agente teclee en Companion; se confirma que la frase del guion la teclea o la dice Karen?]
- [NEEDS CLARIFICATION: se acepta que la decision "contenido nunca, salvo log principal" se revise solo cuando una prueba nueva no quepa en igualdad o rasgo derivado (disparador de D7)?]

## 10. Checklist de estandar

- [ ] La salida de toda tool `companion_*` sobre hilos y memoria es `structuredContent` con `outputSchema` sin campos de texto libre de la usuaria (ni `text`, ni `title`, ni `goal`, ni texto dictado); test que serializa un fixture con texto centinela y falla si el centinela aparece.
- [ ] El listado de hilos devuelve id, fecha, conteos por rol y marcas; nunca el titulo.
- [ ] La memoria devuelve conteo por tipo, dias e ids; nunca el texto de una entrada.
- [ ] La igualdad de D3 compara dentro de Companion, solo contra el ultimo mensaje del hilo activo, devuelve un bool y tiene limite por tasa; test que comprueba que el texto esperado no se registra en el log.
- [ ] Los rasgos derivados (idioma, longitud, solapamiento) se calculan en el proceso y solo sale el numero o la etiqueta.
- [ ] La isla se serializa como nombre de caso, nombre de tarjeta y textos de catalogo; los valores asociados con texto salen como longitud.
- [ ] Las lineas de log devueltas son solo del log principal, van con el marco fijo de datos, y el log de transcripciones de depuracion no es accesible por ninguna tool.
- [ ] Ninguna tool `companion_*` devuelve valores de campos seguros ni del Keychain (R4).
- [ ] R1-R7 de `self-qa-puente` siguen cumpliendose; security-reviewer revisa la proyeccion como frontera de confianza.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | MCP Specification, overview (Security and Trust & Safety) | Model Context Protocol | 2025-06-18 | 2026-10-01 | high |
| 2 | MCP Specification, Server Resources | Model Context Protocol | 2025-06-18 | 2026-10-01 | high |
| 3 | MCP Specification, Server Tools | Model Context Protocol | 2025-06-18 | 2026-10-01 | high |
| 4 | Human Interface Guidelines, Privacy | Apple | sitio actual | 2026-10-01 | high |
| 5 | App Review Guidelines 5.1.1, 5.1.2 | Apple | sitio actual | 2026-10-01 | high (politica de App Store, aplicada por analogia) |
| 6 | Allow accessibility apps to access your Mac | Apple Support | macOS actual | 2026-10-01 | high |
| 7 | NSAccessibility.Subrole.secureTextField | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 8 | NLLanguageRecognizer | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 9 | CryptoKit HMAC | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 10 | LLM01:2025 Prompt Injection | OWASP GenAI Security Project | 2025 | 2026-10-01 | high |
| 11 | Incredible.app 0.2.36, cadenas del binario `Contents/MacOS/incredible` | Norditech, binario instalado | 0.2.36 | 2026-10-01 | medium (solo cadenas, sin flujo) |
| 12 | Codigo y specs del repo (Memory, ConversationStore, ChatViewModel+Persistence, IslandState, IslandEvents, Log, TranscriptDebugLog, voz-corte-al-hablar) | companion-next | d563ca3 | 2026-10-01 | high |
