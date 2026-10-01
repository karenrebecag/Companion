# Research briefs

- voicesession-division | deep | APROBADO | Versiones: swift-tools=6.2 | Si partir VoiceSession (actor de voz de ~2180 lineas en 14 archivos) y en que forma
- tests-por-modulo-soporte | standard | APROBADO | Versiones: swift-tools=6.2 | Como partir CompanionTests en un test target por modulo y organizar el soporte compartido sin romper swift build -c release
- catalogo-de-textos | standard | APROBADO | Versiones: swift-tools=6.2 | Que forma, ubicacion por capa, canales (pantalla/voz/modelo) y pruebas de completitud debe tener el catalogo unico de textos en/es de companion-next con SwiftPM native
- bridge-conexion-arranque-dos-fases | standard | APROBADO | Versiones: swift-tools=6.2 | Como arrancar el hilo lector de BridgeConnection solo despues de cablear onClosed y que el aviso de cierre no se pueda perder
- classic-runtime-submit-speak | standard | BORRADOR | Versiones: swift-tools=6.2 | Como eliminar la carrera de datos de ClassicRuntime entre submit (turno) y speak (aviso o turno cortado) sin romper el corte por pulsacion
