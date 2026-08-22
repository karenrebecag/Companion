# Roadmap

## Estado

| Wave | Nombre | Estado | Hito |
|---|---|---|---|
| 0 | Scaffold | CERRADA (2026-08-20) | Paquete compila, gates verdes |
| 1 | Core de dominio | CERRADA (2026-08-20) | Logica pura 100% testeada |
| 2 | Chat vertical | CERRADA (2026-08-20) | **App usable solo con una API key** |
| 3 | Voz | APROBADO / EN CURSO | **Conversacion por voz con barge-in** |
| 4 | Delegacion | CERRADA (4a y 4b) | **Especialista integrado sin instalar nada** |
| 5 | Producto | CERRADA (5a-5e) | **Distribuible open source** |
| 6 | Paridad y craft | 6a CERRADA; 6c CERRADA; 6b EN CURSO | **Iguala o supera al prototipo en uso diario** |
| 7 | Delegacion de verdad | CERRADA (7a y 7b, 2026-08-21) | **"Crea un archivo" por voz termina en archivo real** |
| 8 | Cabos sueltos | CERRADA (2026-08-22) | **Nada probado se queda sin cablear; ningun doc miente** |
| 9 | Que la use alguien que no seas tu | EN CURSO | **Un desconocido instala, pega su key y conversa** |

## Foco actual

**Wave 9 en curso.** El grueso salio en la release 0.10.0 (2026-08-22):
idioma de UI y de prompts, nombre del producto, ruta de instalacion sin
compilar y el primer DMG publicado. La auditoria del flujo completo hecha
ese mismo dia midio que tan cerrado esta el circuito, dimension por
dimension:

| Dimension | Estado |
|---|---|
| Mecanica (build, tests, gates, TurnMachine) | SOLIDO |
| Release y trazabilidad (DMG, tag, CHANGELOG, licencias) | CERRADO |
| Voz vs especialista: la voz nunca inventa un final feliz | PARCIAL |
| Idioma | PARCIAL |
| Onboarding en frio | ABIERTO |
| README como puerta de entrada | PARCIAL |

Cerrado despues de esa medicion: el idioma manda tambien en el plano de voz
— el reconocedor escucha en el idioma del usuario y el permiso se pregunta
en ese idioma.

Lo que sigue abierto, en orden:

1. **Voz sintetizada offline en es-MX** (`OpenAITTS.swift`): el fallback sin
   red le contesta en espanol a quien eligio ingles. Ultimo tramo del mismo
   bug de idioma.
2. **Onboarding**: la key no se valida de forma antes de salir a la red; un
   Keychain rechazado deja la key solo en memoria y sin reintento; la guia
   de Gatekeeper vive en el README de GitHub y no dentro del DMG.
3. **La voz clasica calla los encargos** (`VoiceSession.jobAnnounce`): no
   miente, pero en el pipeline de respaldo el que delego por voz no oye ni
   el exito ni el fallo. Decidir entre narrarlo o declararlo solo-pantalla
   en un ADR.
4. **Sin tests de `jobAnnounce`/`flushAnnouncements`**: la costura entre el
   resultado del encargo y lo que sale por la bocina es invisible a la
   suite.
5. **README sin captura y sin video**: la narrativa de producto ya esta
   (que problema resuelve, para quien, por que se reconstruyo), pero de un
   producto visual no se ve un solo pixel antes de compilarlo.

Y lo que solo Karen puede cerrar: repetir la prueba manual de delegacion
("crea un archivo prueba1.md en mi escritorio"), el veredicto visual del
design system (criterio de done de 6b, programa atomico en
`docs/specs/ds/`), y despues notarizar o las ideas post-v1.


## Brecha con el prototipo (medida 2026-08-22)

| | Prototipo | Rebuild |
|---|---|---|
| Sources | 15.307 lineas | 18.125 |
| Tests | 1.228 lineas | 14.838 |
| Dependencias | Pow, livekit-ui, Orb (vendoreados), Mapbox, Hermes (Python) | RiveRuntime.xcframework |

La medicion del 2026-08-21 ("~10.600 contra 15.300, cero dependencias
externas") quedo obsoleta en un dia y en dos sentidos: el rebuild ya es mas
grande que el prototipo en codigo fuente, y tiene una dependencia binaria
(ADR 003, atribuida y fijada por checksum en `NOTICE.md`). Es la unica, y
sumar otra exige otro ADR.

Los cuatro puntos de dolor de aquella medicion estan **cerrados**: menu de
aplicacion (Cmd+C/V/X), adjuntos con arrastre, actualizaciones contra
GitHub Releases, y el pulido (avisos, sonido al pensar, sintaxis resaltada,
ajustes de fin de turno). Lo que queda vive en Wave 8 y en el programa DS.

Fuera por decision, no por olvido: handoff a terminal de Hermes (ADR 001),
Sparkle (ADR 002). El mapa pasa de Mapbox a MapKit: menos personalizable,
sin token ni WebView.

## Deuda consciente (con trigger)

- Firma ad-hoc: los permisos TCC de microfono se re-piden en cada rebuild.
  Identidad estable "Companion Dev" -> Wave 5.

- Notarizacion: notarytool ya esta disponible (Xcode instalado); falta la
  cuenta de Apple Developer -> decision de Karen, no bloqueo tecnico.

## Despues de v1 (ideas, sin compromiso)

- Transporte WebRTC (AEC3 por software) — **trigger probado 2026-08-21**: en
  la Mac de Karen VPIO no inicializa (-10875); era el camino primario del
  prototipo por esta exacta razon. Primera candidata post-v1.
- SpeechAnalyzer (macOS 26) como STT local de proxima generacion.
- Servidores MCP como fuente de tools extra del NativeExecutor.
