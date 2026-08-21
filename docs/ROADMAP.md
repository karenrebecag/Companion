# Roadmap

## Estado

| Wave | Nombre | Estado | Hito |
|---|---|---|---|
| 0 | Scaffold | CERRADA (2026-08-20) | Paquete compila, gates verdes |
| 1 | Core de dominio | CERRADA (2026-08-20) | Logica pura 100% testeada |
| 2 | Chat vertical | CERRADA (2026-08-20) | **App usable solo con una API key** |
| 3 | Voz | Spec BORRADOR | **Conversacion por voz con barge-in** |
| 4 | Delegacion | Spec BORRADOR | **Especialista integrado sin instalar nada** |
| 5 | Producto | Spec BORRADOR | **Distribuible open source** |

## Foco actual

Wave 3: kickoff del spec (`docs/specs/wave-3-voice.md`).

## Deuda consciente (con trigger)

- Harness de tests propio -> migrar a Swift Testing cuando se instale Xcode.
- Notarizacion requiere Xcode (notarytool) -> resolver antes de cerrar Wave 5.

## Despues de v1 (ideas, sin compromiso)

- Transporte WebRTC (AEC3 sin CoreAudio) si el WS + Voice Processing no basta.
- SpeechAnalyzer (macOS 26) como STT local de proxima generacion.
- Servidores MCP como fuente de tools extra del NativeExecutor.
- Localizacion (la UI nace en espanol; en para contribuir).
