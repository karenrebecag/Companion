# Estructura: subcarpetas por feature

Estado: APROBADO (2026-09-30), con los ajustes de la auditoria abajo

## Objetivo

Core (147), Services (146) y la raiz de UI (88) son carpetas planas donde la
feature solo se lee en el prefijo del nombre (`Browser*`, `VoiceSession*`,
`ParentTool*`). Esta tarea agrupa esos 381 archivos en subcarpetas por
dominio, con los mismos nombres de dominio en los tres targets cuando el
dominio existe en mas de uno. Ningun tipo, firma ni comportamiento cambia: solo rutas y nombres de
archivo.

## Auditoria contra proyectos de referencia

| Referencia | Que hace | Que tomamos |
|---|---|---|
| CodeEdit (app macOS SwiftUI) | `CodeEdit/Features/<Feature>/` con subcarpetas `Views/`, `Models/` | Carpetas por feature dentro del target: es el paso que corresponde a este tamano |
| isowords (Point-Free, 87 targets) | Un modulo por feature y pares interfaz/implementacion (`ApiClient` / `ApiClientLive`) | El mismo nombre de dominio en Core (puertos) y Services (adaptadores), para que extraer un modulo despues sea mecanico |
| IceCubes (app SwiftUI) | Un paquete por feature mas `DesignSystem/`, `Models/`, `Env/` | `DesignSystem/` en UI y el mismo nombre en Core para `Contrast` |
| swift-package-manager, sourcekit-lsp, swift-nio | Muchos targets chicos; dentro de cada uno, carpeta casi plana. Tests en `Tests/<Target>Tests/` | Confirma que el destino final son mas targets, no carpetas mas profundas; los tests se parten por target en la tarea siguiente |
| Google Swift Style Guide, File Names | "Multiple extensions to a type → `MyType+Additions.swift`" | Los archivos que solo extienden un tipo pasan a `Type+Concern.swift` |

Cambios al mapa por la auditoria:
- `Chrome/` de Core era un cajon sin dominio: `Welcome` va a `Welcome/`,
  `SettingsSearch` a `Settings/` (los mismos nombres que en UI), `HomeTasks` a
  `Chat/` (cada conversacion es una tarea) y `Contrast` a `DesignSystem/`.
- 40 archivos que solo extienden un tipo se renombran a `Type+Concern.swift`
  (`SessionMachineJobs` -> `SessionMachine+Jobs`, las 12 extensiones de
  `VoiceSession`, las 6 de `ChatViewModel`, etc.). No se renombran
  `VoiceSessionAttachments` ni `ParentToolRunnerHands`: la mitad de su
  contenido son tipos propios, no la extension.

## Fuera de alcance

- `CompanionApp` (13 archivos): se queda plano.
- `Tests/`: se reorganiza en la tarea que parte el target de tests por modulo
  (una carpeta por target en lugar de subcarpetas dentro de uno).
- Renombrar tipos o archivos, `public` -> `package`, partir `VoiceSession`.
- `Package.swift`: no se toca. SPM compila las subcarpetas de un target sin
  declararlas.

## Restriccion: nombres de carpeta reservados

`Services/Skills`, `Services/Diagram`, `UI/Fonts` y `UI/Mascot` son recursos
`.copy(...)` en el manifest. Ninguna carpeta nueva usa esos nombres: un
`.swift` dentro de un recurso copiado dejaria de compilar. Por eso
`SkillStore` va a `Storage/` y los adaptadores de diagramas a
`Deliverables/`. Los `.lproj` se quedan en la raiz de UI.

## Mapa

### CompanionCore

| Carpeta | Archivos |
|---|---|
| Session/ | SessionMachine, SessionMachineBrakes, SessionMachineDictation, SessionMachineJobs, SessionMachineResting, SessionTypes, TurnMachine, TurnTypes, TurnContext, TurnTimeline, AmbienceCue, Acknowledgement, Notices, SoundPorts |
| Voice/ | VoicePorts, VoiceStack, VoiceTapAction, VoiceAuditReport, Endpointing, BackchannelGate, HoldKey, HoldAudioBuffer, Dictation, DictatedText, SentenceSplitter, SpeechBudget, SpeechFilter, MouthLanguageGate, Vocabulary, RealtimeCodec |
| Chat/ | ChatPorts, ChatPrompt, ChatParameters, SSECodec, RetryPolicy, Conversation, ConversationMemory, ConversationRollover, Memory, HomeTasks |
| Delegation/ | Escalation, EscalationCopy, Executors, ExecutorSessions, Job, JobSteps, JobTimeline, HandoffInText, HandoffProposal, AgentStreamCodec, ProcessPorts, LineBuffer |
| Decision/ | Decision, DecisionRouting, Arbitration, Candidates, Plan, PlanSteps, LocalModels |
| Tools/ | ParentTools, ParentToolHands, ParentToolPolicy, ParentToolSight, NativeTools, ToolArguments, ToolSpec, HandsWords, TypedProof, ActionBand, ActionReceipt, UndoReceipt |
| Approvals/ | ApprovalCopy, ApprovalMemory, ApprovalPorts, ApprovalRisk |
| Perception/ | ContextBlock, ScreenBriefParser, ScreenNeed, ScreenScan, ScreenSeePrompt, PointerTrace, UserLocation, Permissions |
| Browser/ | BrowserCodec, BrowserCopy, BrowserLease, BrowserLink, BrowserPolicy, BrowserProtocol, BrowserRender, BrowserSanitize, BrowserTool, BrowserVerdicts |
| Bridge/ | BridgeCopy, BridgePolicy, BridgeProtocol, BridgeRequestLedger |
| Apps/ | ConnectedApps, ConnectPoll, CatalogSeed, AppMention, MCPTools, OwnMCP |
| Blocks/ | AnswerBlocks, CompanionBlocks, DataBlocks, ChoiceBlock, CardVocabulary, ChartSummary, Markdown, Feedback |
| Deliverables/ | DeliverableTools, DocumentHTML, DocumentSpec, ChartSVG, DiagramBlock, DiagramPage, DiagramPorts, DiagramScheduler, Sheets, SheetApproval, FormulaPolicy, XLSXWriter |
| Island/ | IslandAttach, IslandEvents, IslandParts, IslandState, NotchGeometry, AttachmentPolicy, Mention, MentionPorts |
| Welcome/ | Welcome |
| Settings/ | SettingsSearch |
| DesignSystem/ | Contrast |
| Text/ | Syntax, SyntaxFamily, TextHygiene, TextSanitizer |
| Skills/ | Skills |
| Platform/ | Config, HostSecrets, AppLanguage, Build, ProductIdentity, SemanticVersion, RegularFile, APIKeyShape |

### CompanionServices

| Carpeta | Archivos |
|---|---|
| Voice/Session/ | VoiceSession + sus 13 extensiones, VoiceJobBridge, VoiceFailureMapping, IslandEventBuffer |
| Voice/Classic/ | ClassicRuntime + 5 extensiones, ClassicEarOwnership, ClassicHoldAudio |
| Voice/Realtime/ | RealtimeRuntime, RealtimeEncoder, RealtimePlayer, RealtimeWSTransport |
| Voice/Audio/ | MicCapture, MicCaptureStartPlan, MicCaptureWatchdog, AudioDevicePin, AudioOutputWatcher, AECVeto, HoldKeyTap, AmbienceObserver, ThinkingSound, SynthesizedUISound |
| Voice/Ear/ | AnalyzerTranscriber, AppleSpeechEngine, OpenAITranscriber, TranscriptFinalizer, TranscriptDebugLog, VoiceAudit, NaturalLanguageRecognizer |
| Voice/Mouth/ | SpeechSynthesis, SpeechPrefetch, OpenAITTS, ElevenLabsTTS, MouthRouter, PhraseCache, TTSVoiceSampler |
| Chat/ | ChatProviderClient, ChatSSEAttempt, ChatTransport, FastBrainChatProvider, EndpointPolicy, RedirectPolicy, NetworkReachability |
| Decision/ | DecisionGate, ArbiterClient, OllamaDecisionProvider, OllamaModelScan |
| Delegation/ | JobQueue, JobRunner, NativeExecutor, ClaudeCodeExecutor, HermesExecutor, HermesProviderScan, ExecutorIntegration, ExecutorProvider, CLIBinaryLocator, CLIExecutorProbe, ProcessGroup, ProcessRegistry, LiveCapabilityProbe |
| Tools/ | NativeToolRunner (+2), ParentToolGuard, ParentToolRunner (+3), SystemActionRunner, ActionUndoer, WebSearch, PlacesSearch, NSWorkspaceOpener |
| Approvals/ | Approvals |
| Accessibility/ | AXScreen, AXScreenText, AXSecure, AXTextInjector, AXTextInjectorHands, PointerSampler |
| Perception/ | ContextSensors, ScreenCapture, ScreenSight, ScreenVision, RegionGrabber, CityLocator, CoreLocationCity, Contacts, RecentFiles, InstalledAppsCache |
| Permissions/ | AccessibilityPermission, InputMonitoringPermission, ScreenRecordingPermission, SystemWelcomeDevices |
| Browser/ | BrowserChannel, BrowserHost, BrowserHostRelay, BrowserLeases, BrowserRelayIO, BrowserToolRunner (+2), NativeHostInstaller |
| Bridge/ | BridgeListener, BridgeParkedSheet, BridgePaths, BridgePeer, BridgeSession, BridgeSession+Calls, BridgeSocketSupport |
| Apps/ | AppToolRunner, HTTPAppsService, MCPConfigFile |
| Deliverables/ | PDFRenderer, AppleEventSheets, DocumentBackup, DiagramFileWriter, DiagramPNG, WebKitDiagramRenderer |
| Storage/ | ConversationStore, FileMemoryStore, FileExecutorSessionStore, SkillStore, AttachmentStore |
| Platform/ | KeychainBackend, KeychainSecretStore, CachingSecretStore, Log, UpdateChecker, LegacyURLCachePurge, Services |

### CompanionUI (raiz; `Island/`, `Orb/`, `Feedback/` ya existen)

| Carpeta | Archivos |
|---|---|
| DesignSystem/ | Tokens, TokensChoices, Typography, Palette, Motion, Layout, Icons, Halftone, Shimmer, Pressable, ChromeMotion, Controls, ControlChrome, SharedControls, IncredibleCards, IncredibleChrome, IncredibleControls, Dropdown, DropdownSession, Toasts, SyntaxHighlighter |
| Chat/ | ChatViewModel + 6 extensiones, ChatCopy, ChatErrorSurface, ChatMessage, MarkdownView, AttachmentViews |
| Cards/ | CardView, DataCards, GalleryCard, MapCard, SourcesCard |
| Window/ | CompanionRootView, RootOverlays, WindowChrome, IncredibleWindow, MainSidebar, HomePage, TaskDetailSheet, MenuPlan, KeyboardMonitor, Shortcuts |
| Island/ | IslandView |
| Orb/ | Orb, OrbAppearance |
| Overlay/ | ScreenGlow, ScreenGlowShader, ScreenOverlay, PointerTrail |
| Settings/ | Settings* (9), ContextSettings, HoldSettings, KeysSettings, ElevenLabsVoiceSettings, BrowserSettingsModel, UserPreferences, UpdateState, PermissionRow |
| Apps/ | AppsModel, AppsPage, AppPanel, ConnectingSheet, OwnMCPSheet |
| Voice/ | VoiceViewModel, VoiceCopy, VoicePreview, SessionModel, ApprovalSheet |
| Welcome/ | WelcomeModel, WelcomeScreens, WelcomeView |
| Localization/ | Localized |

## Lo que se rompe con el movimiento (y se ajusta en el mismo PR)

Todo lo que lee fuentes por ruta en lugar de por tipo:

1. `scripts/gates.sh`: las dos exenciones de `SessionMachine*.swift` buscan
   `/CompanionCore/SessionMachine...`; pasan a `/CompanionCore/Session/...`.
2. `conformance/ui-contract.json`: las claves de `exemptFiles` y `baseline`
   son rutas relativas a `Sources/CompanionUI`.
3. Tests que abren un archivo por ruta: `RateLimitRetryTests`,
   `FailureReportingTests`, `BatchFallbackArgsTests`, `Contacts16m7Tests`,
   `Choice16m6FixesTests` (ChatViewModel), `TypeLeadingConformanceTests`
   (claves relativas a UI). `Parity16q2RoundTests` y `Choice16m6GateTests`
   apuntan a App e `Island/Choice`, que no se mueven.
4. `docs/ARCHITECTURE.md`: una seccion corta con la convencion de carpetas.

## Ejecucion

- `git mv` por archivo (sin copiar y borrar) para que git registre renames
  al 100% y `git log --follow` / `blame` sigan funcionando.
- Commit 1: solo los movimientos. Commit 2: los ajustes de ruta de arriba.
  Asi el diff del commit 1 son renames puros y el 2 se revisa solo.
- Aceptacion: `scripts/gates.sh` verde y `git diff --stat -M origin/main`
  con 381 renames sin cambios de contenido en el commit 1.

## Riesgo: ramas en vuelo

Hay unas 20 worktrees con ramas sin mergear. Git sigue los renames al hacer
rebase o merge, asi que sus ediciones a archivos movidos se aplican bien.
Lo que no se arregla solo: un archivo NUEVO en esas ramas cae en la raiz
plana y habra que moverlo a mano despues. Cuantas menos ramas abiertas al
mergear esto, menos limpieza.

## Pendiente de decision

- `Services/Services.swift` es un placeholder de Wave 0 ("los adaptadores
  llegan en Wave 2+"). Se mueve a `Platform/`; borrarlo es otra decision.
