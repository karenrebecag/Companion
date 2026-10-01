# Research briefs

- voicesession-division | deep | APROBADO | Versiones: swift-tools=6.2 | Si partir VoiceSession (actor de voz de ~2180 lineas en 14 archivos) y en que forma
- tests-por-modulo-soporte | standard | APROBADO | Versiones: swift-tools=6.2 | Como partir CompanionTests en un test target por modulo y organizar el soporte compartido sin romper swift build -c release
- catalogo-de-textos | standard | APROBADO | Versiones: swift-tools=6.2 | Que forma, ubicacion por capa, canales (pantalla/voz/modelo) y pruebas de completitud debe tener el catalogo unico de textos en/es de companion-next con SwiftPM native
- bridge-conexion-arranque-dos-fases | standard | APROBADO | Versiones: swift-tools=6.2 | Como arrancar el hilo lector de BridgeConnection solo despues de cablear onClosed y que el aviso de cierre no se pueda perder
- classic-runtime-submit-speak | standard | BORRADOR | Versiones: swift-tools=6.2 | Como eliminar la carrera de datos de ClassicRuntime entre submit (turno) y speak (aviso o turno cortado) sin romper el corte por pulsacion
- resource-locator-scratch-path | standard | APROBADO | Versiones: swift-tools=6.2 | Como decide ResourceBundleLocator que Bundle.module es seguro sin fijar .build/debug, para que swift test con --scratch-path, --triple o TSan encuentre los bundles
- tsan-gate-ci | standard | APROBADO | Versiones: swift-tools=6.2 | Como agregar un gate de ThreadSanitizer a CI (tiempo en runner, alcance, forma del job, aislamiento del build, carreras conocidas, requerido o informativo)
- classic-turn-serialize | standard | APROBADO | Versiones: swift-tools=6.2 | Como serializar los turnos clasicos (el nuevo espera al cortado) para que la nota de corte y el hilo lleguen en orden: plazo, aviso, forma, latencia y test en rojo
- interrupciones-por-causa | standard | APROBADO | Versiones: swift-tools=6.2 | Si los agentes de voz en produccion reaccionan distinto segun la causa del corte (barge-in, red, herramienta atascada, stop) y si el plazo y el rastro del turno cortado deben variar por causa
- ci-cola-macos | quick | APROBADO | Versiones: swift-tools=6.2 | Como bajar la cola de macOS en CI: CodeQL Swift solo en main y semanal (advanced setup) y cancelar corridas reemplazadas por PR sin tocar las de main
- changelog-por-fragmentos | standard | APROBADO | Versiones: swift-tools=6.2 | Como evitar que cada merge haga conflictuar CHANGELOG.md en los demas PR (fragmentos por PR, ensamblado con shell, gate de un fragmento)
