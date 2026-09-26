# Incredible por dentro: mapa de módulos (2026-09-25)

Fuentes, de más a menos fiable:
1. **Lo instalado en esta Mac** (v0.2.36, `one.incredible.new`): `Info.plist`, `~/.incredible/`
   (estructura y esquemas, no contenido), el manifiesto de mensajería nativa de Chrome y los puertos
   abiertos.
2. **Nombres de módulos** que el binario conserva en sus rutas de compilación
   (`crates/<crate>/src/<módulo>.rs`, ~130 crates de Rust). Solo nombres: no se extrajo ni se leyó
   su lógica, prompts ni frontend.
3. **Documentación pública**: incredible.one/learn (secciones app-connectors, browser, knowledge,
   tasks, scheduled, autopilot, dictation, contacts, vocabulary), /pricing, /terms,
   trust.incredible.one.

Lo inferido va marcado **(inferido)**.

## 1. Forma general

- **App:** Tauri 2 (Rust + webview), macOS y Windows. Helpers nativos sueltos:
  `accessibility-helper`, `incredible-audiocap`, `incredible-screenrec`, `incredible-mux`,
  `incredible-poster`, un `python-kernel` con Python embebido y ffmpeg embebido.
- **Backend propio:** Supabase (`supabase-edge`), Sentry, telemetría de producto. La empresa es
  Norditech, bajo ley sueca.
- **Modelos:** hay clientes para Anthropic, Gemini, OpenAI, Groq y Cerebras (`llm-client`).
  - Voz a texto: AssemblyAI realtime, Groq y ElevenLabs Scribe realtime (`stt`).
  - Texto a voz: ElevenLabs (`tts`).
  - Búsqueda web: Exa (`exa-client`).
  - Imagen: `image-gen`.
  - "Hey Incredible": detector local (`wake-word`: spotter).
- **Cerebro:** `orchestrator` (turno, esquemas de tools, turno especulativo), `agent-core` (plan,
  bucle con guarda, resumen, recorte de historial), sub-agentes (clasificador de intención),
  `agent-supervisor` (trabajo en segundo plano), `context-compaction`.
- **Aprobaciones:** `action-gate` con `approval_policy` y `payload_policy`. Puntúa el riesgo por
  acción: leer no pregunta; crear o cambiar confirma; borrar exige aprobación (docs, app-connectors).
- **Libro de trabajo:** `spine` (task_projection, work_ledger), guardado en `~/.incredible/spine/spine.jsonl`
  con eventos `{kind, item, seq, ts_ms, title, delta_summary}`. Alimenta el Home (Working · Needs
  you · Upcoming · Done) y el log de actividad.

## 2. Módulo por módulo

| Módulo | Qué hace | Cómo funciona | Dónde corre | Evidencia |
|---|---|---|---|---|
| **Apps (conectores)** | 1.700+ apps en la UI (3.000+ en docs) | **MCP como protocolo interno**: `mcp-client` con proveedores `pipedream` (y Composio citado), `native-integrations` (MCP remotos oficiales, p. ej. `mcp.notion.com/mcp`, `mcp.granola.ai/mcp`) y `custom-mcp` (servidores MCP propios con OAuth y directorio). OAuth de Pipedream Connect; tokens en Pipedream, no en la Mac. Las tools se descubren con `search_tools`/`list_all_tools` y un calentamiento del catálogo (`catalogue_warmup`); `connector-learn` guarda notas de cómo usar cada conector | nube (Pipedream) + cliente MCP en la Mac | binario; docs app-connectors |
| **Browser** | Actúa en **tu** Chrome/Edge/Brave/Arc, en segundo plano, con pestañas marcadas | Extensión Chromium. La **mensajería nativa solo arranca el secreto**: `com.incredible.bridge_auth` → `~/.incredible/bridge-auth-host.sh` le entrega `bridge-secret` a la extensión (3 IDs de extensión permitidos). Después la extensión habla con la app por un **puerto local** (`browser-bridge::port`; la app escucha en `127.0.0.1:37423`) autenticado con ese secreto. Descubre perfiles (`chromium-profiles`), mira páginas (`browser-surface::look_at`) y muestra una vista flotante de la pestaña de fondo (`browser-pip`: watch/reveal/poller). Quita campos sensibles antes de que el contenido salga del navegador | Mac (extensión + app); nada va de la extensión a internet | manifiesto instalado; binario; docs browser |
| **Computer use** | Controla apps nativas | `computer-surface`: ventanas, puntero, observación, espera a que la UI se asiente, pausa fuera del Space, diff de cambios; `accessibility-helper` aparte; `computer-use-api` (inferido: modelo de computer use en la nube) | Mac | binario |
| **Knowledge** | Notas y archivos que "lee cuando importan" | `knowledge` (frontmatter, ranking), `knowledge-watcher` (vigila archivos), `knowledge-discovery` (extrae de tus archivos y apps con un pipeline), `contact-discovery` (arma Contactos desde correo y calendario) | Mac en `~/.incredible/knowledge` (+ nube, inferido) | binario; docs knowledge/contacts |
| **Skills** | Cómo hacer un tipo de trabajo | **Formato Agent Skills**: carpetas con `SKILL.md` (`name`, `description`) en `~/.incredible/skills/`. Trae 10 de fábrica: browser-use, task-builder, excel-live, knowledge-builder, premium-documents, screen-layout, writing-content, trust-and-privacy, about-incredible y default. `custom/` es para las tuyas. `skills-watcher` sincroniza las de fábrica (`default_sync`) y recarga en caliente | Mac | carpeta instalada; binario |
| **Saved tasks** | "Guarda esto como tarea" | Son **workflows generados**: `workflow-recording` graba la corrida (elementos, segmentos, texto, video con ffmpeg); `workflow-generator` convierte eso en un workflow con código (`code_classifier`, `execution`) que corre en el **Python embebido** (`python-kernel`, `connector_kernel`) llamando conectores, navegador y computer use; `workflow-editor` lo corrige conversando; `workflow-runtime` lo reproduce con preflight y auditoría | Mac (inferido: la grabación se sube, `upload_service`) | binario; docs tasks |
| **Scheduled** | Calendario: una vez o recurrente | `triggers` + `triggers-desktop-host::scheduler` lanzan un workflow guardado a su hora (`teach_schedule`) | **Mac** según el binario (scheduler local, `~/.incredible/triggers.json`); la doc sugiere nube → probablemente híbrido | binario; docs scheduled |
| **Autopilot** | "Cuando pase X en tus apps, haz Y" | Mismo motor de `triggers`; condición + acción; **polling cada 30 min** (configurable), no webhooks; cada corrida al log de Activity | device o nube (ver arriba) | docs autopilot; binario |
| **Isla / notch** | La app de diario | `island-attention` (tarjetas confirmadas), `desktop-projection-host` (overlay, atención), `data-mac-notch` en el webview, `HoverDetector` nativo | Mac | binario; grabación |
| **Contexto de pantalla** | Qué ves al hablar | `screen-context` (capturas, fragmentos, adjunto pendiente, prewarm del foco), `screen-text` (texto sin lo tapado), `activation-timeline` (qué pasaba al pulsar la tecla), `open-documents`/`open-folders` | Mac | binario |
| **Dictation** | Mantén una tecla, el texto cae en el cursor | `dictation-core`, `voice-application` (sesión de dictado, limpieza), `vocabulary` (correcciones, semilla), niveles de limpieza none/light/medium/high | STT en la nube | binario; docs dictation |
| **Day** | Tu día y sugerencias | `day-desktop-host` (calendario del dispositivo y del conector, vistazo al correo) + `day-suggestions` | Mac + conectores | binario |

## 3. Lo que Companion ya tiene y lo que falta

| Incredible | Companion hoy | Hueco |
|---|---|---|
| Conectores por MCP (Pipedream + MCP oficiales + MCP propios) | `MCPTools` en Core; el especialista (Claude Code) usa los MCP que tenga configurados | Un **cliente MCP en el propio cerebro** con catálogo y búsqueda de tools; OAuth de MCP remotos. Pipedream Connect es un servicio de pago de terceros, no aplica sin backend |
| Extensión de navegador + puente local con secreto por mensajería nativa | Vista y click por Accesibilidad (16a) sobre el navegador que tengas; Chromium preparado | La extensión (leer DOM, pestañas de fondo). Es el mismo patrón y está al alcance: extensión MV3 + host nativo + WebSocket local con secreto |
| Skills en `SKILL.md` | `Skills.swift` (catálogo en el prompt, 11a) | Alinear al formato Agent Skills y cargar desde carpeta con recarga en caliente |
| Saved tasks = workflow grabado → código → Python local | No existe | Lo más caro. Versión mínima: guardar el **plan** de un turno exitoso como skill y reproducirlo |
| Scheduled / Autopilot | No existe | Scheduler local (`launchd` o timer en la app) sobre tareas guardadas; autopilot = polling de un conector |
| Knowledge / Contactos / Vocabulario | Memoria (`Memory.swift`), vocabulario (16d) | Carpeta de conocimiento con ranking; contactos para nombres |
| `spine` (libro de trabajo) + Home | `JobTimeline`, conversaciones | Un registro único de tareas con estados para un Home |
| Aprobación por riesgo (`action-gate`) | `HandsGate`, `clickVerdict`, `ApprovalTickets` | Equivalente ya hecho |

## 4. Notas

- La doc pública no menciona el notch, "Hey Incredible", MCP ni skills; el binario sí los tiene.
- Todo lo de este documento es comportamiento observable y nombres. Para construir el equivalente en
  Companion se diseña desde cero con nuestro patrón (Core puro, puertos, adapters).
