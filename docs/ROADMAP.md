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

## Foco actual

Las cinco waves del programa estan cerradas. Lo que queda es la prueba manual
de Karen y lo que ella decida despues: notarizar (requiere cuenta de Apple),
y las ideas post-v1 de abajo.

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
