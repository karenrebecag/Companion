# Wave 6 — Ordenes de trabajo restantes

**Estado: APROBADO para ejecucion por agentes.** Cada orden (W1-W5) es un
prompt autocontenido: dale a un agente UNA orden completa, espera su reporte,
verifica la seccion "Verificacion" con grep antes de dar la orden siguiente.

## Reglas que TODO agente recibe (copiar en cada prompt)

- Proyecto: Swift 6 strict concurrency. Tests con Swift Testing
  (`swift test`), helpers `expect`/`expectEq` de TestKit, suites
  `@Test @MainActor func xxxTests()`. TDD estricto: test primero, verifica
  ROJO, implementacion minima, VERDE, con evidencia en el reporte.
- Sin `try?` en Core/Services; sin print (usar `Log`); archivos ≤400 lineas
  (si crece, archivo nuevo); comentarios WHY en ingles; sin emojis en codigo
  ni en UI. Core no importa nada de Apple salvo Foundation.
- Tests: JAMAS audio real (AVAudioEngine/AVAudioPlayer sin arrancar), jamas
  red viva, jamas dormir tiempos reales largos ni bloquear el main actor (la
  suite entera debe seguir < 3 s). Todo lo temporal, con reloj/sleep
  inyectado.
- GIT: hay VARIAS sesiones en el mismo arbol. Commit por pieza cerrada con
  `git add` de archivos EXPLICITOS — `git add -A` esta PROHIBIDO. Antes de
  empezar: `git pull`. No toques archivos fuera de tu orden.
- ANTES DE REPORTAR "terminado": verifica con grep que el flujo real invoca
  cada capacidad nueva (el repo lleva TRECE casos de codigo testeado que
  nadie llamaba) y pega los greps en el reporte. Si difieres algo del
  alcance, dilo con todas sus letras — nunca lo declares hecho.
- Lectura obligatoria antes de codear: docs/ARCHITECTURE.md y, si la orden
  toca voz o audio, docs/REFERENCE.md completo (el ledger). El prototipo en
  ../companion es SOLO LECTURA: se porta comportamiento, no se copia estilo.

## Mapa de carriles (que puede ir en paralelo)

- **Carril VOZ**: W1 → W2, en ese orden (comparten VoiceSession).
- **Carril ESCRITORIO**: W3 → W4, en ese orden (W4 usa los toasts de W3).
- VOZ y ESCRITORIO pueden correr EN PARALELO (archivos disjuntos).
- **W5 (design system) SOLO cuando W1-W4 esten cerradas**: reestiliza lo que
  las demas crean.

---

## W1 — Sonido de fondo mientras piensa (6c-2)

Referencias: docs/specs/wave-6c-voice-tuning.md seccion "Presencia sonora";
prototipo `../companion/Sources/Ambience.swift` (sintesis C4+G4+C3, rampas
0.6 s entrada / 0.35 s salida, volumen ~0.12); ledger seccion Audio.

Alcance:
1. Core: `AmbienceCue.forTransition(from:to:) -> Cue` — funcion PURA que
   decide start/stop/nada ante cada transicion de `TurnState` (decision del
   kickoff: cero efectos nuevos en el reducer). `.thinking` enciende; salir
   de `.thinking` apaga; el primer audio del agente apaga aunque el estado
   tarde.
2. Services `ThinkingSound.swift`: sintesis EN MEMORIA del acorde del
   prototipo (sin WAVs — decision de assets), en un AVAudioEngine PROPIO y
   efimero. PROHIBIDO tocar el engine compartido del microfono: cuando AEC
   esta activo ese engine es del canceller (ledger). Rampas de volumen, stop
   idempotente.
3. Observacion: VoiceSession ya publica snapshots; un observador (en
   Services, cableado en la composicion) consume el stream, llama a
   AmbienceCue y maneja el ThinkingSound. VoiceSession NO se toca (va en 428
   lineas).
4. Toggle "Sonido al pensar" en la seccion VOZ de Ajustes
   (`SettingsVoiceSection.swift`), persistido en `VoiceProfile.settings`
   (campo nuevo con default true) y respetado por el observador.

Tests: AmbienceCue exhaustiva sobre transiciones; el observador con un
stream fake ⇒ enciende/apaga en los momentos correctos y respeta el toggle;
cero audio real (motor inyectable — el ThinkingSound real se prueba a oido).

Verificacion (grep en el reporte): el observador se construye e inyecta en
CompanionMain; AmbienceCue se llama desde el observador; el toggle escribe
la preferencia y el observador la lee.

## W2 — Imagen a sesion de voz viva (6c-3)

Referencias: wave-6c spec; `RealtimeCodec.imageItem` (LISTO, no lo
reescribas); prototipo `RealtimeConversation.push` (reescala a maxEdge 1024
antes del base64 — `AttachmentPolicy` de 6a-2 ya reescala: reusa); ledger
Realtime ("las imagenes no sobreviven a la reconexion" — no intentes
re-mandarlas al reconectar).

Alcance:
1. Puerto: `VoiceControlling` gana `func push(attachment:) async` (o firma
   equivalente minima). VoiceSession lo implementa en ARCHIVO NUEVO
   (extension, p.ej. `VoiceSessionAttachments.swift`): si hay sesion realtime
   activa, codifica la imagen (via AttachmentPolicy) y manda
   `RealtimeCodec.imageItem` con caption tipo "El usuario adjunto X; miralo y
   espera a que pregunte". Sin sesion activa o si el adjunto no es imagen:
   no-op silencioso (el camino de texto ya lo cubre).
2. Cableado: cuando se adopta un adjunto en la UI (flujo de 6a-2) y
   `voice.isActive`, se llama al push. Confirmacion visual: toast si W3 ya
   existe; si no, linea de estado en el hilo.
3. La codificacion NO bloquea el turno: en tarea aparte, como el prototipo.

Tests: con transporte fake — imagen adjuntada con sesion activa ⇒ viaja UN
imageItem con caption y base64; sin sesion ⇒ nada; adjunto no-imagen ⇒
nada; cancelar sesion durante la codificacion ⇒ no manda ni cuelga.

Verificacion: grep de que el flujo real de adjuntos llama al push cuando la
voz esta activa; que VoiceSession.swift NO crecio (la extension es archivo
nuevo).

## W3 — Toasts y sonido de interfaz (6a-4)

Referencias: wave-6a spec seccion Feedback; prototipo
`../companion/Sources/{Toasts,UISound}.swift`. Decision de kickoff: UISound
vive en Services con puerto en Core (el gate PROHIBE AVFoundation en
CompanionUI). Decision de assets: sonidos por SINTESIS, sin WAVs.

Alcance:
1. Core: puerto `InterfaceSounding` (p.ej. `play(_ cue: SoundCue)` con casos
   alerta/confirmacion) y modelo de toast (id, texto, variante, duracion).
2. Services: `SynthesizedUISound.swift` — los cues sintetizados en memoria
   (tonos cortos con envolvente; inspiracion en los del prototipo, sin
   copiar WAVs), motor propio efimero, respetando un toggle persistido.
3. UI: `Toasts.swift` — cola visible arriba a la derecha, entrada/salida con
   el motion existente, expiracion ~4 s con reloj inyectable, variante de
   error, apilable. API unica desde los ViewModels (`toast(_:)`).
4. Cablear los emisores que ya existen y hoy no avisan: permiso resuelto,
   encargo terminado/fallido, version nueva (W4), adjunto agregado (W2).
5. Toggle "Sonidos de interfaz" en Ajustes.

Tests: cola de toasts (orden, expiracion, apilado) con reloj fake; decision
de cue por evento; el puerto de sonido con un fake que registre cues.

Verificacion: grep de que los cuatro emisores reales llaman a `toast(_:)`;
que CompanionUI NO importa AVFoundation (el gate lo confirma).

## W4 — Actualizaciones (6a-5, implementa ADR 002)

Referencias: wave-6a spec; docs/DECISIONS.md ADR 002; docs/DISTRIBUTION.md.
PRERREQUISITO dentro de esta orden: unificar las TRES versiones que hoy
divergen — `Build.version` (0.2.0-wave2), `scripts/bundle.sh` (0.3.0) y
CHANGELOG (0.6.0). Una sola fuente: `Build.version`; bundle.sh la LEE (grep
del archivo Swift), no la duplica.

Alcance:
1. Services `UpdateChecker.swift`: GET a la API publica de releases de
   GitHub (repo karenrebecag/Companion), parsea el ultimo tag, compara
   semver contra `Build.version`. Cachea el resultado del dia (UserDefaults
   con fecha). SIN red o con API caida: silencio absoluto, jamas un error
   visible. Usa `ChatTransport` + `EndpointPolicy` existentes, no URLSession
   a pelo.
2. UI: si hay nueva — toast discreto (W3) y fila en Ajustes → SISTEMA con
   boton "Ver la version X" que abre la pagina de la release. Nada de
   descargas en segundo plano (ADR 002).
3. Chequeo al arrancar (tras un pequeño delay para no competir con el
   launch) y a demanda desde Ajustes.

Tests: comparacion semver con fixtures (mayor/menor/igual/tag malformado/
prerelease); cache del dia con reloj fake; respuesta hostil de la API ⇒
silencio; el checker jamas lanza.

Verificacion: grep de que bundle.sh extrae la version de Build.swift; que el
chequeo se dispara desde CompanionMain; que el boton de Ajustes existe.

## W5 — Design system (wave-6b entera) — SOLO al cerrar W1-W4

Referencias: docs/specs/wave-6b-design-system.md (contrato completo, con las
decisiones de kickoff y assets ya tomadas: fuentes solo-local salvo Inter
con su OFL; Rive NO — orb SwiftUI portando el vendor del prototipo).

Pieza 1 CERRADA (`9fc56fd`). Piezas 2-5: prompts autocontenidos en
`docs/specs/wave-6b-remaining.md`. En serie, un agente por pieza.

Criterio de done de W5: el veredicto VISUAL de Karen. Los agentes entregan;
ella juzga con la app abierta.

---

## Cierre de cada orden

Gates verdes + commit scoped + push + entrada de CHANGELOG si es visible
para la usuaria. Al cerrar W4: marcar 6a CERRADA en su spec y ROADMAP. Al
cerrar W2: marcar 6c CERRADA (W1+W2+lo ya entregado). Al cerrar W5: marcar
6b y la Wave 6 completa, y programar la prueba manual integral de Karen.
