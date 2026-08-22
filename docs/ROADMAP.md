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

## Foco actual

**Wave 8 cerrada** (`docs/specs/wave-8-cabos.md`): aprobar por voz ya esta
declarado y cableado, la sesion del especialista sobrevive al reinicio, un
cable stdio muerto ya no pierde el encargo, la tarjeta del encargo tiene
paso vivo y reloj, y los docs dejaron de afirmar cosas que el codigo
desmiente. Gates en 0 fallos y 0 avisos, 168 tests.

Queda lo que solo Karen puede cerrar: repetir la prueba manual de
delegacion ("crea un archivo prueba1.md en mi escritorio"), el veredicto
visual del design system (criterio de done de 6b, programa atomico en
`docs/specs/ds/`), y despues notarizar o las ideas post-v1.


## Brecha con el prototipo (medida 2026-08-22)

| | Prototipo | Rebuild |
|---|---|---|
| Sources | 15.307 lineas | 16.828 |
| Tests | 1.228 lineas | 13.622 |
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
- Localizacion (la UI nace en espanol; en para contribuir).
