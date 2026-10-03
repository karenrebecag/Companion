# Reference Brief: que la onda del micro no dibuje barras con el ruido de la sala (voiced como Incredible 0.2.36)

Slug: waveform-vad-voiced | Nivel: standard | Fecha: 2026-10-03 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-03 ESCALATE
Decision de Karen (2026-10-03): D1 = b1, compuerta pura de energia en Core como v1; el VAD de dispositivo de Apple (a2) va despues, tras el experimento de la seccion 9. Ataque de 1 cuadro. Con reducir movimiento la columna viva sigue al ultimo cuadro (fix con test en rojo primero). b2 (micVoiced en VoiceLevels) solo si la medida en vivo muestra cuadros perdidos. Se acepta la API VoiceActivityGate en Core. [KAREN:chat 2026-10-03 via orquestador]

## 1. Pregunta y decisiones abiertas

Pregunta: como hace Companion para que el ruido de la sala no dibuje barras en la onda del micro (`VoiceLevelWaveform` / `WaveformHistory`, llegados en #213), igual que Incredible 0.2.36, que apaga la onda con una bandera `voiced` de su VAD nativo.

Toolchain al investigar: swift-tools 6.2 en Package.swift, compilador Apple Swift 6.3.3, SDK de macOS 26.5 (`xcrun --show-sdk-version`), plataforma minima macOS 26.

Encargo relayado por el orquestador el 2026-10-03; no es palabra directa de Karen. La politica de no subir extractos de Incredible se respeta: aqui van valores y comportamiento descritos con offset de byte, sin codigo.

### Hallazgos en Incredible 0.2.36 (referencia local de solo lectura en ~/Desktop/incredible-ref)

La referencia local no es una URL ni un archivo del repo, asi que el linter no acepta marcas para ella; por eso estos hallazgos van aqui, citados por archivo, offset de byte y prefijo sha256 del archivo leido (overlay-DstkIEbM.js 9d280ba68346, audioLevelsSource-DSOQLR23.js bf72f03abc54, main-BL-DABKy.js 8dadeb4e26d9, firstRun-BOTAwJJ8.css 50e35522efc6, incredible.md e04e9fa2f699). Todos se leyeron en esta corrida.

- Productor: el nativo emite el evento `audio:mic-level` con `level` y `voiced` (audioLevelsSource-DSOQLR23.js @163). La fuente de audio del front acepta `voiced` solo si es booleano; si no, lo deja indefinido (@622) y lo publica como `micVoiced` (@612).
- Consumidor: la onda de la isla toma `micLevel` y `micVoiced` de esa fuente al suscribirse (overlay-DstkIEbM.js @32468 y @32514). Es el unico consumidor de la bandera en el front.
- main-BL-DABKy.js no usa la bandera: su unico `voiced` (@1083705) es parte de la palabra "invoiced" en una lista de integraciones, y su `audio:mic-level` (@199463) alimenta solo el medidor del tour, sin `voiced`. createFirstRunIO-Dv00aAyF.js (@39001) tambien lee solo el nivel.
- Detector: el binario enlaza el crate Rust `earshot` 1.2.2 (incredible.md lineas 2148, 2149 y 5612: rutas de `fft/mod.rs`, `default_predictor.rs` y `lib.rs`). earshot es una red neuronal sobre bandas mel (seccion 4), no energia, ZCR, WebRTC VAD ni Silero.
- Desconocido: las cadenas extraidas del nativo no muestran umbral, ataque, hangover ni la cadencia del evento; como se pasa del puntaje de earshot a `voiced` vive en codigo nativo no extraido.
- Constantes de la onda (overlay-DstkIEbM.js @30654 a @30764): columna cada 5 px, barra de 2.5, rango de 60 dB, piso de pico 0.08, decaimiento 0.991 por columna, crecimiento maximo x2, ventana de 22 dB y compuerta por defecto 0.08.
- Seleccion (@30905 y @31175): la primera bandera recibida marca `hasVad` y desde ahi decide la bandera; sin bandera decide la compuerta de nivel.
- Ataque en el front (@31187): la bandera se acumula con un O logico dentro de la columna; basta un cuadro con voz para que la columna sea voz.
- Liberacion en el front (@31542): al cerrar cada columna la bandera vuelve a falso; el front no retiene nada, la siguiente columna sin voz ya es punto.
- Sin voz (@30930 y @31638): la columna guarda muestra 0 y toda muestra igual o menor que la compuerta se dibuja como punto: ni barra minima ni decaimiento.
- Tamanos (@31704): el punto mide el ancho de barra (2.5) y la barra mas baja mide 2.5 + 2 = 4.5; la altura sigue una potencia 0.85.
- Referencia (@31377): sin voz el pico solo decae (x0.991, nunca bajo 0.08); con voz sigue al nivel hasta el doble por columna.
- Ritmo (@31904 y @31911): la tira se desplaza a 56 px/s (una columna cada 89 ms) y relee sus colores cada 500 ms.
- Usos (@34664, @71976 y @75686): las tres tiras pasan compuerta 0.08.
- Reducir movimiento: el componente de la onda (@32044 a @33610) no lo menciona; las referencias a reduced motion del archivo estan en otros componentes (@6370, @89976).
- Colores (firstRun-BOTAwJJ8.css @218452 a @218610): barra en texto secundario y punto en texto tenue; en dictado, naranja y naranja al 45 %.

### Decisiones a tomar

- D1. De donde sale `voiced`: (a) el VAD de Apple (escucha de voz silenciada de VPIO o propiedad VAD del HAL), (b) una compuerta pura de energia con histeresis y hangover en Core, (c) la senal de voz del servidor o de la sesion, o (d) `SpeechDetector` de Speech.
- D2. Umbrales y tiempos: umbral de apertura, umbral de cierre, ataque y hangover, y de donde sale cada numero.
- D3. Donde vive la compuerta: en la vista (sin tocar contratos) o en la sesion de voz (cambia `VoiceLevels`, un tipo de Core).
- D4. Reducir movimiento: que dibuja la columna viva cuando la tira no se desplaza.

Banderas de escalado: la opcion recomendada no agrega dependencias, permisos ni cambia contratos de modulo. La variante b2 (bandera dentro de `VoiceLevels`) y la opcion a2 (puerto nuevo) si cambian un contrato de Core; ninguna opcion pide un permiso TCC nuevo (el micro ya esta concedido).

## 2. Estado actual

- `WaveformHistory` ya porta la onda de Incredible con las mismas constantes, incluida la compuerta 0.08 [repo:Sources/CompanionCore/Voice/WaveformHistory.swift:38]
- Sus pruebas fijan los valores calculados a mano desde los bytes 30654-31911 del overlay de Incredible [repo:Tests/CompanionCoreTests/WaveformHistoryTests.swift:4]
- `WaveformHistory` ya tiene la costura para un detector: `ingest(level:voiced:)` con bandera opcional [repo:Sources/CompanionCore/Voice/WaveformHistory.swift:83]
- Como en Incredible, la primera bandera recibida reemplaza para siempre a la compuerta en esa historia [repo:Sources/CompanionCore/Voice/WaveformHistory.swift:95]
- La bandera se acumula con O y se reinicia al empujar cada columna [repo:Sources/CompanionCore/Voice/WaveformHistory.swift:128]
- `micMeterGain` es 6: el medidor del micro es RMS x 6 recortado a 1, y la onda lo deshace para volver a dBFS [repo:Sources/CompanionCore/Voice/WaveformHistory.swift:47]
- `MicCapture` calcula ese medidor por cuadro sobre el PCM16 de 24 kHz [repo:Sources/CompanionServices/Voice/Audio/MicCapture.swift:306]
- El tap del micro pide buffers de 2048 cuadros [repo:Sources/CompanionServices/Voice/Audio/MicCapture.swift:173]
- La vista hoy no pasa bandera: un HACK lo dice y apunta a la brecha 4 [repo:Sources/CompanionUI/Voice/VoiceLevelWaveform.swift:47]
- La vista alimenta la historia solo cuando cambia `amplitude` (`onChange`) [repo:Sources/CompanionUI/Voice/VoiceLevelWaveform.swift:45]
- La isla muestra la onda solo con el medidor del micro; mientras habla el agente no hay onda [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:140]
- La sesion publica `VoiceLevels(mic:agent:)` en cada cuadro del micro [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:231]
- `VoiceLevels` solo lleva `mic` y `agent`; no hay campo de voz [repo:Sources/CompanionCore/Voice/VoicePorts.swift:130]
- El piso de ruido medido de este micro en silencio es 0.12 en la escala del medidor [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:292]
- La voz real medida va de 0.3 a 0.8 y el umbral conservador de "hubo voz" es 0.2 [repo:Sources/CompanionCore/Voice/HoldAudioBuffer.swift:20]
- Ese umbral exige 3 cuadros para descartar un clic o un crujido [repo:Sources/CompanionCore/Voice/HoldAudioBuffer.swift:26]
- El endpointer de transcripcion usa 0.18 como piso de voz, tambien por encima del 0.12 medido [repo:Sources/CompanionCore/Voice/Endpointing.swift:94]
- `BackchannelGate` cuenta cuadros sobre 0.08 y exige 6 seguidos (~0.5 s) mientras habla el agente [repo:Sources/CompanionCore/Voice/BackchannelGate.swift:14]
- Cuenta: 0.12 en el medidor son -34 dBFS, nivel 0.43 en la escala de 60 dB, muy por encima de la compuerta 0.08 (-55 dBFS, medidor 0.010) [repo:Sources/CompanionCore/Voice/WaveformHistory.swift:71]
- Cuenta: con la referencia en su piso 0.08, ese ruido queda 12 dB bajo el pico y dibuja barras de ~11 pt de 26; esa es la falla que se ve hoy [repo:Sources/CompanionCore/Voice/WaveformHistory.swift:102]
- La cancelacion de eco (VPIO) esta activada por defecto en la configuracion [repo:Sources/CompanionCore/Platform/Config.swift:234]
- Con VPIO, `MicCapture` apaga el AGC y pone el ducking de otro audio al minimo [repo:Sources/CompanionServices/Voice/Audio/MicCapture.swift:289]
- Si VPIO no arranca, `MicCapture` lo veta y sigue con el motor plano, sin cancelacion de eco [repo:Sources/CompanionServices/Voice/Audio/MicCapture.swift:91]
- El oido de Apple crea `SpeechAnalyzer` con un solo modulo, el transcriptor; no hay `SpeechDetector` ni otra VAD local en Sources (grep de esta corrida) [repo:Sources/CompanionServices/Voice/Ear/AppleSpeechEngine.swift:75]
- En realtime el oido es la transcripcion de OpenAI, cuya VAD de servidor manda `speechStarted` al oido segmentador [repo:Sources/CompanionServices/Voice/Ear/OpenAITranscriber.swift:270]
- Los eventos del oido segmentador son solo `speechStarted` y `finished(text:)`; no hay borde de fin de voz [repo:Sources/CompanionCore/Voice/VoicePorts.swift:70]
- La conversacion realtime tiene `turn_detection` nulo: el modelo de conversacion no escucha el micro [repo:Sources/CompanionCore/Voice/RealtimeCodec.swift:115]
- Bajo reducir movimiento la vista no avanza la historia y solo dibuja la columna viva [repo:Sources/CompanionUI/Voice/VoiceLevelWaveform.swift:68]
- La columna viva usa `current`, el maximo desde el ultimo empuje, y pico y bandera solo se reinician al empujar [repo:Sources/CompanionCore/Voice/WaveformHistory.swift:144]
- Hay pruebas de Core para la costura (`onceAFlagArrivesItReplacesTheGate`, `theFlagHoldsForTheColumnAndResetsAfterIt`) [repo:Tests/CompanionCoreTests/WaveformHistoryTests.swift:56]
- Hay una prueba de Core para la columna viva sin desplazamiento, sin caso de voz que se apaga [repo:Tests/CompanionCoreTests/WaveformHistoryTests.swift:391]
- Core es puro (solo Foundation); Services son adaptadores; UI va en MainActor [repo:docs/ARCHITECTURE.md:12]
Contextos: app instalada en /Applications (release, micro real, VPIO activado o vetado, pipeline clasico con oido de Apple y realtime con oido de OpenAI, reducir movimiento encendido o apagado), swift test (CompanionCoreTests puro y CompanionUITests con NSHostingController, sin micro ni HAL), gates de scripts/gates.sh (grep y build, sin audio). La onda no tiene preview propio.

## 3. Fuentes primarias

- La cabecera del SDK 26.5 define `kAudioDevicePropertyVoiceActivityDetectionEnable` y `...State` como propiedades de dispositivo del HAL, no del AU VoiceIO [doc:https://developer.apple.com/tutorials/data/documentation/coreaudio/kaudiodevicepropertyvoiceactivitydetectionenable.json@macOS26.5-sdk]
- Segun esa cabecera, el estado es 1 con voz y 0 sin voz, se lee al cambiar (listener), y vale 0 si la entrada no corre o la deteccion esta apagada [doc:https://developer.apple.com/tutorials/data/documentation/coreaudio/kaudiodevicepropertyvoiceactivitydetectionenable.json@macOS26.5-sdk]
- En el SDK no existen `kAUVoiceIOProperty_VoiceActivityDetectionEnable` ni `...State`; el AU VoiceIO solo trae la escucha de voz silenciada (propiedad 2106) [doc:https://developer.apple.com/tutorials/data/documentation/avfaudio/avaudioinputnode/setmutedspeechactivityeventlistener(_:).json@macOS26.5-sdk]
- `setMutedSpeechActivityEventListener` existe desde macOS 14 y avisa solo inicio y fin de voz mientras la entrada esta silenciada con `voiceProcessingInputMuted` [doc:https://developer.apple.com/tutorials/data/documentation/avfaudio/avaudioinputnode/setmutedspeechactivityeventlistener(_:).json@macOS26.5-sdk]
- WWDC23 10235: el bloque de voz silenciada se invoca solo si la usuaria esta silenciada y cambia el estado de voz [doc:https://developer.apple.com/videos/play/wwdc2023/10235/@WWDC23]
- WWDC23 10235: la alternativa del HAL (solo macOS) detecta voz sobre la entrada con eco cancelado y funciona sin importar el estado de silencio del proceso [doc:https://developer.apple.com/videos/play/wwdc2023/10235/@WWDC23]
- WWDC23 10235: el procesamiento de voz aplica cancelacion de eco, supresion de ruido y control automatico de ganancia [doc:https://developer.apple.com/videos/play/wwdc2023/10235/@WWDC23]
- Activar el procesamiento de voz en un nodo lo activa en el otro, solo con el motor parado, y exige el mismo formato entre la salida del nodo de entrada y la entrada del nodo de salida (cabecera AVAudioIONode.h) [doc:https://developer.apple.com/tutorials/data/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:).json@macOS26.5-sdk]
- `SpeechDetector` (macOS 26) es un modulo VAD de `SpeechAnalyzer` que solo funciona junto a `SpeechTranscriber` o `DictationTranscriber` [doc:https://developer.apple.com/tutorials/data/documentation/speech/speechdetector.json@macOS26]
- Apple advierte que el VAD de `SpeechDetector` puede tirar audio con voz y ofrece niveles de sensibilidad, con medium recomendado [doc:https://developer.apple.com/tutorials/data/documentation/speech/speechdetector.json@macOS26]
- `SpeechDetector.Result` trae `speechDetected` y un `range` de tiempo de audio, no un puntaje [doc:https://developer.apple.com/tutorials/data/documentation/speech/speechdetector/result.json@macOS26]
- La VAD de servidor de OpenAI Realtime emite `input_audio_buffer.speech_started` y `speech_stopped`, con umbral, relleno previo y silencio configurables [doc:https://developers.openai.com/api/docs/guides/realtime-vad@2026-10-03]
- `accessibilityReduceMotion` pide evitar animaciones grandes, no ocultar informacion [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/environmentvalues/accessibilityreducemotion.json@macOS26]
- Swift Testing permite parametrizar un test con colecciones de argumentos, un caso por argumento [doc:https://developer.apple.com/tutorials/data/documentation/testing/parameterizedtesting.json@swift-6.2]

## 4. Implementaciones de referencia

- earshot 1.2.2 (pykeio, Apache-2.0, ~200 estrellas, activo en 2026-08), el VAD que enlaza Incredible: trabaja en cuadros de 16 ms a 16 kHz y dice resistir ruido con SNR de 3 dB o mas [ref:https://github.com/pykeio/earshot/blob/c400f15bd232dda30a297eec90235bd09066cab7/README.md#L6@c400f15]
- earshot devuelve un puntaje 0-1 por cuadro y sugiere 0.5 como umbral; el crate no trae histeresis ni hangover, eso queda al llamador [ref:https://github.com/pykeio/earshot/blob/c400f15bd232dda30a297eec90235bd09066cab7/src/lib.rs#L145@c400f15]
- El detector de earshot es una red neuronal sobre 40 bandas mel con capas convolucionales y minGRU, no energia ni ZCR [ref:https://github.com/pykeio/earshot/blob/c400f15bd232dda30a297eec90235bd09066cab7/src/default_predictor.rs#L57@c400f15]
- WebKit (Apple, captura de audio de Safari) activa la VAD del HAL en el dispositivo de entrada y escucha `...VoiceActivityDetectionState`; en macOS usa el HAL y en iOS la escucha de voz silenciada de VoiceIO [ref:https://github.com/WebKit/WebKit/blob/0a314be5ad51d9d6cae901fa0aea25a4a1e8eed3/Source/WebCore/platform/mediastream/cocoa/CoreAudioCaptureUnit.mm#L142@0a314be]
- WebKit solo reacciona al borde con voz (estado 1) y lo usa para avisar a quien habla en silencio, no para dibujar nivel [ref:https://github.com/WebKit/WebKit/blob/0a314be5ad51d9d6cae901fa0aea25a4a1e8eed3/Source/WebCore/platform/mediastream/cocoa/CoreAudioCaptureUnit.mm#L173@0a314be]
- En macOS WebKit enciende la VAD del HAL con el capturador arrancado aunque produzca muestras; la condicion de no producir muestras es solo de iOS [ref:https://github.com/WebKit/WebKit/blob/0a314be5ad51d9d6cae901fa0aea25a4a1e8eed3/Source/WebCore/platform/mediastream/cocoa/CoreAudioCaptureUnit.cpp#L923@0a314be]
- pipecat (Daily, ~16k estrellas, commits diarios), marco de agentes de voz: su VAD tiene estados QUIET, STARTING, SPEAKING y STOPPING con 0.2 s para confirmar inicio y 0.2 s para confirmar fin [ref:https://github.com/pipecat-ai/pipecat/blob/c027943125c0ef7ea1b946b6c438032eb8ff0483/src/pipecat/audio/vad/vad_analyzer.py#L25@c027943]
- pipecat exige a la vez confianza del modelo (0.7) y volumen suavizado minimo (0.6): la energia sola no abre la voz [ref:https://github.com/pipecat-ai/pipecat/blob/c027943125c0ef7ea1b946b6c438032eb8ff0483/src/pipecat/audio/vad/vad_analyzer.py#L211@c027943]
- En pipecat un cuadro con voz durante STOPPING vuelve a SPEAKING y reinicia la cuenta: eso es el hangover con rearme [ref:https://github.com/pipecat-ai/pipecat/blob/c027943125c0ef7ea1b946b6c438032eb8ff0483/src/pipecat/audio/vad/vad_analyzer.py#L220@c027943]
- La onda de Incredible 0.2.36 es la referencia de comportamiento visual (seccion 1); Companion ya la porto y sus pruebas la fijan por bytes [repo:Tests/CompanionCoreTests/WaveformHistoryTests.swift:4]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| a1. Escucha de voz silenciada de VPIO (`setMutedSpeechActivityEventListener`) | API publica, eco cancelado | Solo avisa con la entrada silenciada; silenciar VPIO corta el audio que necesita el oido; no sirve con la usuaria hablando | media | descartar |
| a2. VAD del HAL (`kAudioDevicePropertyVoiceActivityDetectionEnable` / `State`) | Detector de Apple sobre audio con eco cancelado, funciona sin silencio, usado por WebKit en macOS; mas cerca de un VAD de modelo como earshot | Solo bordes (sin cuadro a cuadro), latencia y algoritmo no documentados; adaptador nuevo en Services con listener del HAL y puerto nuevo en Core (cambio de contrato); no se prueba en swift test; dispositivo correcto con VPIO o vetado sin verificar | media-alta | siguiente paso, tras un experimento |
| b1. Compuerta pura de energia con histeresis y hangover en Core, usada por la vista | Pura y probada por tabla en Swift Testing; funciona en clasico y realtime, con VPIO o vetado y sin red; sin cambio de contrato; 2 archivos de producto | No distingue voz de otros sonidos fuertes (tele, musica, otra persona); umbrales fijados con un solo micro medido | baja | recomendada |
| b2. Igual que b1 pero en la sesion, con `micVoiced` dentro de `VoiceLevels` | Ve cada cuadro del micro, no depende de `onChange` | Cambia `VoiceLevels` (contrato de Core) y toca sesion, modelo de vista y vista | media | si b1 pierde cuadros |
| c. Senal del servidor (`speechStarted` del oido de OpenAI) | Ya existe | Solo realtime y con red; solo borde de inicio; llega tras la ida y vuelta; no existe en clasico | baja | descartar para la onda |
| d. `SpeechDetector` en el `SpeechAnalyzer` del oido de Apple | API de Apple en macOS 26, sin dependencia | Solo con el oido de Apple (clasico); resultados por rango de tiempo con latencia del analizador; el micro arranca antes que el oido | media | descartar para la onda |

Costo, latencia, testeabilidad y riesgo por opcion: a1 no aplica (no dispara sin silencio). a2 cuesta un adaptador HAL y un puerto, latencia desconocida, sin prueba automatica, riesgo medio por el dispositivo agregado de VPIO. b1 cuesta un tipo puro y una linea en la vista, latencia de un cuadro del micro, prueba completa en CompanionCoreTests, riesgo de falsos positivos con ruido fuerte. b2 igual que b1 con mas archivos. c cuesta casi nada pero llega tarde y solo en realtime. d cuesta un modulo extra en el analizador y solo cubre el clasico.

Energia mas ZCR: la ZCR se puede calcular en Core desde el PCM16 de `MicFrame`, pero el repo no tiene ninguna medida de ZCR de este micro; se deja fuera de la primera version y entra solo si la prueba en vivo de la seccion 9 muestra ruido por encima del umbral de energia.

Recomendacion (b1): una compuerta pura `VoiceActivityGate` en Core que recibe el medidor y el instante de cada cuadro y devuelve `voiced`; la vista la llama en el mismo `onChange` y pasa la bandera a `ingest(level:voiced:)`. Valores de partida, con su procedencia en las secciones 2 y 4:

| Parametro | Valor | Procedencia |
|---|---|---|
| Abrir | medidor >= 0.20 (-29.5 dBFS) | umbral de voz medido del repo, sobre el piso 0.12 y bajo la voz 0.3-0.8 |
| Cerrar (histeresis) | medidor < 0.15 (-32 dBFS), solo tras haber abierto | entre el piso 0.12 y el 0.18 del endpointer; derivado, a medir |
| Ataque | 1 cuadro sobre el umbral de apertura | la onda debe mostrar el inicio; Incredible no retiene en el front |
| Hangover | 0.20 s desde el ultimo cuadro sobre el umbral de cierre, rearmable | pipecat stop_secs 0.2 s; son unas 2 columnas de 89 ms |
| Entrada rota (NaN, negativa, infinita) | sin voz | igual que `WaveformHistory.ingest` hoy |
| Sin voz | punto (muestra 0), sin barra minima ni decaimiento | Incredible overlay @31638 (seccion 1) |

## 6. Evidencia en contra

- Contra b1, lo mas fuerte: el propio repo dice que el RMS de este micro no sirve como VAD porque el piso de ruido supera cualquier umbral util [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:292]
- Se resuelve en parte: esa frase habla de abrir turnos con 0.06; el mismo repo despues midio voz en 0.3-0.8 y fijo 0.2 como umbral conservador sobre el piso 0.12 [repo:Sources/CompanionCore/Voice/HoldAudioBuffer.swift:20]
- Se acepta el resto: en la onda un falso positivo es una barra de mas, cosmetico; la bandera solo entra a la historia de la onda, nunca a la logica de turnos [repo:Sources/CompanionUI/Voice/VoiceLevelWaveform.swift:49]
- Contra b1: la energia no separa voz de tele, musica u otra persona; Incredible usa un VAD neuronal que si lo intenta [ref:https://github.com/pykeio/earshot/blob/c400f15bd232dda30a297eec90235bd09066cab7/README.md#L6@c400f15]
- Se acepta: igualar eso exige un VAD de modelo; sin dependencias nuevas, el candidato es la VAD del HAL (a2), que queda como siguiente paso tras medirla [doc:https://developer.apple.com/videos/play/wwdc2023/10235/@WWDC23]
- Contra b1: los umbrales salen de un solo micro medido; con AirPods u otro micro el piso puede ser otro [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:299]
- Se mitiga con la medida en vivo de la seccion 9 y dejando los umbrales como constantes con nombre en Core, no literales en la vista [repo:Sources/CompanionCore/Voice/WaveformHistory.swift:38]
- Contra a2: la VAD del HAL solo avisa bordes y su latencia no esta documentada; WebKit solo usa el borde de inicio para un aviso, no para dibujar [ref:https://github.com/WebKit/WebKit/blob/0a314be5ad51d9d6cae901fa0aea25a4a1e8eed3/Source/WebCore/platform/mediastream/cocoa/CoreAudioCaptureUnit.mm#L173@0a314be]
- Contra c: el oido segmentador no tiene borde de fin de voz y la conversacion realtime no escucha el micro, asi que la onda quedaria encendida hasta `finished` [repo:Sources/CompanionCore/Voice/VoicePorts.swift:70]
- Contra d: `SpeechDetector` solo funciona junto a un transcriptor, y en realtime el oido es OpenAI, no Apple [doc:https://developer.apple.com/tutorials/data/documentation/speech/speechdetector.json@macOS26]
- Contra a1: la escucha de VPIO solo dispara con la entrada silenciada, que es justo cuando no hay onda [doc:https://developer.apple.com/tutorials/data/documentation/avfaudio/avaudioinputnode/setmutedspeechactivityeventlistener(_:).json@macOS26.5-sdk]

## 7. Ejemplares y anti-ejemplos

- Bien hecho: la bandera decide por columna, se reinicia al empujar y una columna sin voz es muestra 0, como en Incredible (seccion 1) [repo:Sources/CompanionCore/Voice/WaveformHistory.swift:100]
- Bien hecho: estados con cuenta de confirmacion y rearme al volver la voz, separados del calculo de confianza [ref:https://github.com/pipecat-ai/pipecat/blob/c027943125c0ef7ea1b946b6c438032eb8ff0483/src/pipecat/audio/vad/vad_analyzer.py#L211@c027943]
- Bien hecho: la costura ya existe y esta probada; la compuerta nueva solo produce el booleano que entra por ella [repo:Tests/CompanionCoreTests/WaveformHistoryTests.swift:64]
- Bien hecho: un umbral medido y comentado con su medida, como `speechRMSThreshold` [repo:Sources/CompanionCore/Voice/HoldAudioBuffer.swift:23]
- Anti-ejemplo: compuerta de nivel fija en 0.08 (-55 dBFS) sobre un micro cuyo piso es -34 dBFS: todo el ruido es voz [repo:Sources/CompanionCore/Voice/WaveformHistory.swift:38]
- Anti-ejemplo: una retencion por conteo de cuadros sin saber cuanto dura un cuadro; el hangover va en segundos [repo:Sources/CompanionCore/Voice/BackchannelGate.swift:13]
- Anti-ejemplo: silenciar la entrada de VPIO para recibir eventos de voz; el oido deja de oir [doc:https://developer.apple.com/tutorials/data/documentation/avfaudio/avaudioinputnode/setmutedspeechactivityeventlistener(_:).json@macOS26.5-sdk]

## 8. Trampas

- Reducir movimiento: la vista no empuja columnas, asi que pico y bandera nunca se reinician y la columna viva queda en la barra mas alta desde que aparecio la tira; con `voiced` empeora porque la bandera se pega en verdadero [repo:Sources/CompanionUI/Voice/VoiceLevelWaveform.swift:68]
- La causa esta en Core: `peak` y `voiced` solo vuelven a cero dentro de `push` [repo:Sources/CompanionCore/Voice/WaveformHistory.swift:127]
- Incredible no tiene rama de reducir movimiento en la onda (seccion 1), asi que no hay valor que copiar; Companion decide, y hoy pausa el reloj de la tira con la preferencia [repo:Sources/CompanionUI/Voice/VoiceLevelWaveform.swift:27]
- Una vez que llega una bandera, la compuerta de nivel no vuelve; si el detector deja de mandar banderas la onda queda en puntos [repo:Sources/CompanionCore/Voice/WaveformHistory.swift:89]
- La vista solo ingiere cuando cambia `amplitude`; la bandera debe calcularse en el mismo `onChange`, nunca observarse aparte [repo:Sources/CompanionUI/Voice/VoiceLevelWaveform.swift:45]
- `VoiceLevels` tambien se publica cuando cambia el nivel del agente, repitiendo el ultimo `mic`; `onChange` no dispara con el mismo valor, asi que no se duplica la ingesta [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:328]
- El medidor se recorta en 1 (RMS 0.167); no afecta a la compuerta, que abre en 0.2 [repo:Sources/CompanionServices/Voice/Audio/MicCapture.swift:306]
- Hay ya tres umbrales de "voz" en Core (0.2, 0.18, 0.08); la compuerta nueva debe nombrar de cual parte y no crear un cuarto suelto [repo:Sources/CompanionCore/Voice/Endpointing.swift:94]
- Contexto app con VPIO: AGC apagado y supresion de ruido de VPIO activa; el piso de 0.12 pudo medirse con o sin VPIO [repo:Sources/CompanionServices/Voice/Audio/MicCapture.swift:289]
- Contexto app con VPIO vetado: motor plano sin supresion de ruido, el piso puede subir; la compuerta debe probarse en los dos [repo:Sources/CompanionServices/Voice/Audio/MicCapture.swift:93]
- Contexto clasico y realtime: b1 se comporta igual en los dos porque solo usa el medidor del micro, comun a ambos [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:230]
- Contexto swift test: no hay micro ni HAL; b1 se prueba entera con la compuerta pura y el reloj como argumento; a2 no tendria prueba automatica [repo:docs/ARCHITECTURE.md:109]
- Contexto gates: la regla de duraciones literales del contrato de UI aplica a la vista; los tiempos de la compuerta viven en Core [repo:conformance/ui-contract.json:31]
- Para a2: activar procesamiento de voz cambia los dos nodos y solo con el motor parado; MicCapture ya maneja eso y no debe tocarse para la onda [doc:https://developer.apple.com/tutorials/data/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:).json@macOS26.5-sdk]
- Para a2: con la entrada parada o la deteccion apagada el estado del HAL vale 0, que la onda leeria como silencio [doc:https://developer.apple.com/tutorials/data/documentation/coreaudio/kaudiodevicepropertyvoiceactivitydetectionenable.json@macOS26.5-sdk]

## 9. Incertidumbre

- ASSUMPTION: el piso 0.12 y la voz 0.3-0.8 valen para el micro integrado con VPIO activo, con VPIO vetado y con AirPods. prueba: en la app instalada, registrar el medidor 10 s en silencio y 10 s hablando en esos tres casos, y fijar abrir/cerrar en la mitad en dB entre piso y voz si difieren de 0.20/0.15.
- ASSUMPTION: cerrar en 0.15 no deja barras con un ventilador o teclado cerca. prueba: misma grabacion con ventilador y tecleando; contar columnas con barra en silencio (meta: cero).
- ASSUMPTION: un cuadro del micro dura unos 43 u 85 ms segun la tasa del hardware. prueba: leer en Companion.log la linea "audio: first mic buffer (N frames)" junto a la de formato de inicio del micro.
- ASSUMPTION: el ataque de 1 cuadro no dibuja barras por clics sueltos de forma molesta. prueba: dar golpes en la mesa con la isla escuchando y contar barras; si molesta, pasar a 2 cuadros (ver la pregunta de abajo).
- ASSUMPTION: el `voiced` de Incredible sale de earshot en el nativo y no del STT remoto. prueba: cortar la red y ver si la onda de Incredible sigue alternando barras y puntos al hablar y callar.
- ASSUMPTION: el umbral, el ataque y el hangover que Incredible aplica al puntaje de earshot son desconocidos porque viven en el nativo no extraido. prueba: grabar Incredible a 120 fps, callar de golpe tras una frase y contar cuantas columnas de 89 ms siguen en barra antes del primer punto.
- ASSUMPTION: la VAD del HAL funciona con la entrada activa y sin silencio en macOS 26 sobre el dispositivo que fija MicCapture, con latencia menor a 100 ms. prueba: en un ejecutable de prueba fuera del producto, activar la propiedad en el dispositivo integrado, registrar los cambios de estado con marca de tiempo y compararlos con el medidor.
- ASSUMPTION: `SpeechDetector` entrega rangos con latencia mayor que un cuadro del micro. prueba: agregar el modulo en un ejecutable de prueba y medir el retraso entre el inicio de voz y el primer resultado con `speechDetected`.
- [NEEDS CLARIFICATION: el ataque es de 1 cuadro (muestra el inicio, acepta alguna barra por un clic) o de 2 cuadros (sin clics, inicio unos 40-85 ms tarde)?]
- [NEEDS CLARIFICATION: con reducir movimiento, la columna viva debe seguir al ultimo cuadro (barra con voz, punto sin voz) en lugar del maximo desde que aparecio la tira?]
- [NEEDS CLARIFICATION: si la medida en vivo muestra cuadros perdidos en la vista, se acepta b2, que cambia `VoiceLevels` en Core?]

## 10. Checklist de estandar

- [ ] Existe `VoiceActivityGate` en CompanionCore, pura (solo Foundation), con umbrales y hangover como constantes con nombre y comentario de su medida.
- [ ] Prueba en rojo primero: un medidor sostenido de 0.12 durante 5 s nunca da voz (parametrizada con 0, 0.05, 0.12 y 0.149).
- [ ] Prueba en rojo primero: `WaveformHistory` alimentada por la compuerta con ruido de 0.12 durante 30 columnas guarda solo muestras 0 y todas sus columnas son `.dot` (hoy son barras de ~11 pt).
- [ ] Prueba: un cuadro de 0.3 abre la voz en ese mismo cuadro, y un 0.17 sin apertura previa no la abre.
- [ ] Prueba de histeresis: ya abierta, un 0.17 la mantiene abierta.
- [ ] Prueba de hangover parametrizada: tras el ultimo cuadro de voz, sigue con voz a 0.19 s y sin voz a 0.21 s; un cuadro de voz a 0.1 s rearma la cuenta.
- [ ] Prueba: NaN, infinito, negativo y un reloj que retrocede no dejan la voz encendida para siempre.
- [ ] Prueba de habla: una frase simulada (0.3-0.8 con huecos de 0.12) dibuja barras en las columnas con voz y puntos a mas de 0.2 s del ultimo cuadro de voz.
- [ ] Prueba de reducir movimiento: sin desplazamiento, un cuadro fuerte con voz seguido de cuadros de 0.12 sin voz deja la columna viva en punto.
- [ ] La vista calcula la bandera en el mismo `onChange` del medidor y la pasa a `ingest(level:voiced:)`; el HACK de la brecha 4 se reemplaza.
- [ ] Ningun archivo fuera de Core y de `VoiceLevelWaveform` cambia; Package.swift, CI y `VoiceLevels` intactos.
- [ ] Medida en vivo en la app instalada (micro integrado con VPIO, con VPIO vetado y con AirPods): cero barras en 10 s de silencio de sala y barras al hablar, anotada en el PR.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | AudioHardware.h, kAudioDevicePropertyVoiceActivityDetectionEnable/State | Apple | macOS SDK 26.5 | 2026-10-03 | high |
| 2 | AVAudioIONode.h, setMutedSpeechActivityEventListener y setVoiceProcessingEnabled | Apple | macOS SDK 26.5 | 2026-10-03 | high |
| 3 | What's new in voice processing (WWDC23 10235) | Apple | 2023 | 2026-10-03 | high |
| 4 | SpeechDetector y SpeechDetector.Result | Apple | macOS 26 | 2026-10-03 | high |
| 5 | Voice activity detection (Realtime) | OpenAI | sin fecha en la pagina | 2026-10-03 | medium |
| 6 | accessibilityReduceMotion | Apple | macOS 26 | 2026-10-03 | high |
| 7 | Parameterized testing | Apple (Swift Testing) | Swift 6.2 | 2026-10-03 | high |
| 8 | earshot | pykeio | 1.2.2 (c400f15) | 2026-10-03 | high |
| 9 | WebKit CoreAudioCaptureUnit | WebKit / Apple | 0a314be | 2026-10-03 | high |
| 10 | pipecat VADAnalyzer | Daily / pipecat-ai | c027943 | 2026-10-03 | medium |
| 11 | Front de Incredible 0.2.36 (overlay, audioLevelsSource, main, firstRun), offsets en la seccion 1 | referencia local de Karen | 0.2.36 | 2026-10-03 | high |
| 12 | Cadenas del binario de Incredible (incredible.md) | referencia local de Karen | 0.2.36 | 2026-10-03 | medium |
