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
| Idioma | CERRADO |
| Onboarding en frio | ABIERTO |
| README como puerta de entrada | PARCIAL |

Cerrado despues de esa medicion:

- **El idioma manda en todo el plano de voz.** El reconocedor escucha en el
  idioma del usuario, el permiso se pregunta en ese idioma y la voz de
  respaldo sin red contesta en el. Los tres puntos donde se decidia un locale
  a mano derivan ahora de `AppLanguage`, unica fuente.
- **Un encargo que falla dice por que.** Los ejecutores de CLI devolvian una
  salida vacia y la voz rellenaba el hueco con un reloj que nunca corrio.
- **Un permiso negado se reporta como permiso**, no como sintesis rota.
- **Lo imposible se responde sin red**: un pegado que no puede ser una clave
  ya no cuesta un viaje a OpenAI para volver culpando a la clave.

Lo que sigue abierto, en orden:

1. **La guia de Gatekeeper no viaja con el DMG**: quien solo descarga se
   queda sin ella justo cuando la necesita, y en macOS 15+ no hay clic
   derecho que lo salve.
2. **La voz clasica calla los encargos** (`VoiceSession.jobAnnounce`): no
   miente, pero en el pipeline de respaldo el que delego por voz no oye ni
   el exito ni el fallo. Decidir entre narrarlo o declararlo solo-pantalla
   en un ADR; hasta entonces no se le escribe test, porque fijaria por
   contrato una conducta que quiza cambie.
3. **Los especialistas no instalados no se distinguen en la UI**: se ofrecen
   igual que los disponibles.
4. **Cambiar el idioma no alcanza a una sesion de voz ya abierta**, como
   tampoco la alcanzan la voz ni la velocidad: se aplica en la siguiente.
5. **README sin captura y sin video**: la narrativa de producto ya esta
   (que problema resuelve, para quien, por que se reconstruyo), pero de un
   producto visual no se ve un solo pixel antes de compilarlo.

Dos hallazgos de aquella auditoria no sobrevivieron a la verificacion contra
el codigo, y quedan anotados para que nadie los persiga otra vez: el circuito
de anuncios **si** tiene tests (`VoiceJobCircuitTests` cubre que el anuncio
sale al escuchar y que espera su turno mientras el agente habla), y un
llavero rechazado **no** pierde la clave: se queda en el campo y el boton la
reintenta.

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
