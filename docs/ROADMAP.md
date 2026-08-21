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

## Foco actual

Port fiel del prototipo, spec por spec: `docs/specs/ds/README.md`.
W5-5 congelado. Primera pieza para aprobar: DS-01 ventana.


## Brecha con el prototipo (medida 2026-08-21)

El rebuild tiene ~10.600 lineas contra 15.300 del prototipo, con 10.500
lineas de tests contra 1.200 y cero dependencias externas. Lo que falta para
igualarlo en utilidad diaria, en orden de dolor:

1. **Menu de la aplicacion** — sin `NSApp.mainMenu` NO funcionan Cmd+C/V/X en
   ningun campo de texto. El prototipo lo documenta en la primera linea de
   `AppMenu.swift`: "en Cocoa eso no es cosmetico". Es el unico fallo que
   hace la app frustrante de usar.
2. **Adjuntar archivos e imagenes** — los tipos existen en Core
   (`AttachmentRef` viaja en los turnos) pero no hay UI: no se puede
   arrastrar una imagen ni compartir un archivo con el especialista.
3. **Actualizaciones** — decididas contra GitHub Releases (ADR 002), sin
   implementar: hoy actualizar es recompilar a mano.
4. **Pulido con impacto**: avisos efimeros (no hay confirmacion visual de
   nada), sonido de fondo mientras piensa (el silencio se hace largo),
   resaltado de sintaxis en bloques de codigo, y los ajustes de deteccion de
   fin de turno (silencio vs semantico, paciencia, AEC).

Fuera por decision, no por olvido: handoff a terminal de Hermes (ADR 001),
mascota interactiva con Rive (ADR 003), Sparkle (ADR 002). El mapa pasa de
Mapbox a MapKit: menos personalizable, sin token ni WebView.

## Deuda consciente (con trigger)

- Firma ad-hoc: los permisos TCC de microfono se re-piden en cada rebuild.
  Identidad estable "Companion Dev" -> Wave 5.

- Notarizacion requiere Xcode (notarytool) -> resolver antes de cerrar Wave 5.

## Despues de v1 (ideas, sin compromiso)

- Transporte WebRTC (AEC3 por software) — **trigger probado 2026-08-21**: en
  la Mac de Karen VPIO no inicializa (-10875); era el camino primario del
  prototipo por esta exacta razon. Primera candidata post-v1.
- SpeechAnalyzer (macOS 26) como STT local de proxima generacion.
- Servidores MCP como fuente de tools extra del NativeExecutor.
- Localizacion (la UI nace en espanol; en para contribuir).
