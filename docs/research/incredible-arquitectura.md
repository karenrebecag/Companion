# Incredible por dentro: mapa de módulos (2026-09-25)

Fuentes, de más a menos fiable:
1. **Lo instalado en esta Mac** (v0.2.36): estructura de carpetas y esquemas de `~/.incredible/` (no contenido), el
   manifiesto de mensajería nativa de Chrome y los puertos abiertos (referencia local).
   abiertos.
2. **Nombres de módulos** que el binario conserva en sus rutas de compilación (~130 módulos de Rust).
   Solo nombres, descritos aquí con palabras; no se extrajo ni se leyó su lógica, prompts ni frontend. El detalle
   vive en la referencia local, no en el repo.
3. **Documentación pública**: incredible.one/learn (secciones app-connectors, browser, knowledge,
   tasks, scheduled, autopilot, dictation, contacts, vocabulary), /pricing, /terms,
   trust.incredible.one.

Lo inferido va marcado **(inferido)**.

## 1. Forma general

- **App:** Tauri 2 (Rust + webview), macOS y Windows. Helpers nativos sueltos (accesibilidad, captura de
  audio, grabación de pantalla, mux y póster) y un Python embebido con ffmpeg embebido.
- **Backend propio:** Supabase, Sentry, telemetría de producto. La empresa es
  Norditech, bajo ley sueca.
- **Modelos:** hay clientes para Anthropic, Gemini, OpenAI, Groq y Cerebras.
  - Voz a texto: AssemblyAI realtime, Groq y ElevenLabs Scribe realtime.
  - Texto a voz: ElevenLabs.
  - Búsqueda web: Exa.
  - Imagen: módulo propio de generación.
  - "Hey Incredible": detector local de palabra de activación.
- **Cerebro:** un orquestador (turno, esquemas de tools, turno especulativo), un núcleo de agente (plan,
  bucle con guarda, resumen, recorte de historial), sub-agentes (clasificador de intención),
  un supervisor de trabajo en segundo plano y compactación de contexto.
- **Aprobaciones:** una compuerta con política de aprobación y de payload. Puntúa el riesgo por
  acción: leer no pregunta; crear o cambiar confirma; borrar exige aprobación (docs, app-connectors).
- **Libro de trabajo:** un registro de proyección de tareas y libro de trabajo, guardado como log de eventos en la carpeta de datos de la app
  (referencia local). Alimenta el Home (Working · Needs
  you · Upcoming · Done) y el log de actividad.

## 2. Módulo por módulo

| Módulo | Qué hace | Cómo funciona | Dónde corre | Evidencia |
|---|---|---|---|---|
| **Apps (conectores)** | 1.700+ apps en la UI (3.000+ en docs) | **MCP como protocolo interno**: cliente MCP con proveedores Pipedream (y Composio citado), integraciones nativas (MCP remotos oficiales de apps como Notion o Granola) y MCP propios (servidores con OAuth y directorio). OAuth de Pipedream Connect; tokens en Pipedream, no en la Mac. Las tools se descubren con búsqueda y listado, con un calentamiento del catálogo; un módulo guarda notas de cómo usar cada conector | nube (Pipedream) + cliente MCP en la Mac | binario; docs app-connectors |
| **Browser** | Actúa en **tu** Chrome/Edge/Brave/Arc, en segundo plano, con pestañas marcadas | Extensión Chromium. La **mensajería nativa solo arranca el secreto**: un host nativo le entrega un secreto a la extensión (3 IDs de extensión permitidos). Después la extensión habla con la app por un **puerto local** autenticado con ese secreto (referencia local para el nombre del host y el puerto). Descubre perfiles, mira páginas y muestra una vista flotante de la pestaña de fondo. Quita campos sensibles antes de que el contenido salga del navegador | Mac (extensión + app); nada va de la extensión a internet | manifiesto instalado; binario; docs browser |
| **Computer use** | Controla apps nativas | Un módulo de superficie: ventanas, puntero, observación, espera a que la UI se asiente, pausa fuera del Space, diff de cambios; helper de accesibilidad aparte; un modelo de computer use en la nube (inferido) | Mac | binario |
| **Knowledge** | Notas y archivos que "lee cuando importan" | Notas con frontmatter y ranking, un vigilante de archivos, un descubrimiento que extrae de tus archivos y apps con un pipeline, y un descubrimiento de contactos desde correo y calendario | Mac en `~/.incredible/knowledge` (+ nube, inferido) | binario; docs knowledge/contacts |
| **Skills** | Cómo hacer un tipo de trabajo | **Formato Agent Skills**: carpetas con `SKILL.md` (`name`, `description`) en `~/.incredible/skills/`. Trae 10 de fábrica (navegador, constructor de tareas, Excel en vivo, constructor de conocimiento, documentos, layout de pantalla, redacción, confianza y privacidad, sobre Incredible y una por defecto). Una carpeta `custom/` es para las tuyas. Un vigilante sincroniza las de fábrica y recarga en caliente | Mac | carpeta instalada; binario |
| **Saved tasks** | "Guarda esto como tarea" | Son **workflows generados**: se graba la corrida (elementos, segmentos, texto, video con ffmpeg); un generador convierte eso en un workflow con código que corre en el **Python embebido** llamando conectores, navegador y computer use; un editor lo corrige conversando; un runtime lo reproduce con preflight y auditoría | Mac (inferido: la grabación se sube) | binario; docs tasks |
| **Scheduled** | Calendario: una vez o recurrente | Un módulo de disparadores y su scheduler de escritorio lanzan un workflow guardado a su hora | **Mac** según el binario (scheduler local con un archivo de disparadores en `~/.incredible/`); la doc sugiere nube → probablemente híbrido | binario; docs scheduled |
| **Autopilot** | "Cuando pase X en tus apps, haz Y" | Mismo motor de disparadores; condición + acción; **polling cada 30 min** (configurable), no webhooks; cada corrida al log de Activity | device o nube (ver arriba) | docs autopilot; binario |
| **Isla / notch** | La app de diario | Tarjetas de atención confirmadas, un host de proyección del overlay y un detector de hover nativo | Mac | binario; grabación |
| **Contexto de pantalla** | Qué ves al hablar | Capturas, fragmentos, adjunto pendiente, prewarm del foco, texto de pantalla sin lo tapado, línea de tiempo de qué pasaba al pulsar la tecla, y documentos y carpetas abiertos | Mac | binario |
| **Dictation** | Mantén una tecla, el texto cae en el cursor | Sesión de dictado con limpieza, vocabulario (correcciones, semilla), niveles de limpieza none/light/medium/high | STT en la nube | binario; docs dictation |
| **Day** | Tu día y sugerencias | Calendario del dispositivo y del conector, vistazo al correo, y sugerencias del día | Mac + conectores | binario |

## 3. Lo que Companion ya tiene y lo que falta

| Incredible | Companion hoy | Hueco |
|---|---|---|
| Conectores por MCP (Pipedream + MCP oficiales + MCP propios) | `MCPTools` en Core; el especialista (Claude Code) usa los MCP que tenga configurados | Un **cliente MCP en el propio cerebro** con catálogo y búsqueda de tools; OAuth de MCP remotos. Pipedream Connect es un servicio de pago de terceros, no aplica sin backend |
| Extensión de navegador + puente local con secreto por mensajería nativa | Vista y click por Accesibilidad (16a) sobre el navegador que tengas; Chromium preparado | La extensión (leer DOM, pestañas de fondo). Es el mismo patrón y está al alcance: extensión MV3 + host nativo + WebSocket local con secreto |
| Skills en `SKILL.md` | `Skills.swift` (catálogo en el prompt, 11a) | Alinear al formato Agent Skills y cargar desde carpeta con recarga en caliente |
| Saved tasks = workflow grabado → código → Python local | No existe | Lo más caro. Versión mínima: guardar el **plan** de un turno exitoso como skill y reproducirlo |
| Scheduled / Autopilot | No existe | Scheduler local (`launchd` o timer en la app) sobre tareas guardadas; autopilot = polling de un conector |
| Knowledge / Contactos / Vocabulario | Memoria (`Memory.swift`), vocabulario (16d) | Carpeta de conocimiento con ranking; contactos para nombres |
| Libro de trabajo + Home | `JobTimeline`, conversaciones | Un registro único de tareas con estados para un Home |
| Aprobación por riesgo | `HandsGate`, `clickVerdict`, `ApprovalTickets` | Equivalente ya hecho |

## 4. Notas

- La doc pública no menciona el notch, "Hey Incredible", MCP ni skills; el binario sí los tiene.
- Todo lo de este documento es comportamiento observable y nombres. Para construir el equivalente en
  Companion se diseña desde cero con nuestro patrón (Core puro, puertos, adapters).
