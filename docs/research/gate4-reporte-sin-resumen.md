# Reference Brief: reporte de Gate 4 cuando swift test muere sin resumen

Slug: gate4-reporte-sin-resumen | Nivel: quick | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 ESCALATE

## 1. Pregunta y decisiones abiertas

Cambio: que Gate 4 de `scripts/gates.sh`, cuando `swift test` falla, diga que lo mato. En la corrida 36903280273 la salida termino en `◇ Test bridgeListenerTests() started.`, sin linea `Test run with` y sin ninguna linea con `✘`, y nadie pudo saber la causa. El orquestador pidio imprimir rc, la senal cuando rc > 128, y el ultimo test iniciado cuando no hay `✘`.

Decisiones:
1. Que imprimir y de donde sale cada dato. El hallazgo central de este brief es que, cuando muere el proceso de tests, `swift test` sale con rc=1 y no con 128+n, asi que "rc > 128" casi nunca dispara.
2. Donde vive la logica: dentro de `gates.sh` o en `scripts/report-test-failure.sh`, con su propio test.
3. Si conviene, mas adelante, pasar a la salida estructurada (event stream JSON) de Swift Testing en vez de parsear la consola.

Toolchain observado: CI (macos-26) y la Mac local corren Apple Swift 6.3.3 (swiftlang-6.3.3.1.3), Testing Library Version 1902. Las fuentes se fijaron al tag `swift-6.3.3-RELEASE` de swift-package-manager (5f6969f) y swift-testing (48d727c). Bash: /bin/bash 3.2.57, fuente de Apple (apple-oss-distributions/bash 51bf3fc).

## 2. Estado actual

- Gate 4 captura stdout y stderr juntos en una variable y toma el rc de la sustitucion [repo:scripts/gates.sh:267]
- El rc se guarda en la linea siguiente, sin distinguir fallo de test, muerte por senal o fallo del propio swift test [repo:scripts/gates.sh:268]
- En CI se agrega `--no-parallel` cuando CI=true, asi que la corrida es serial alli [repo:scripts/gates.sh:266]
- Ante fallo se imprimen solo las ultimas 20 lineas de la salida [repo:scripts/gates.sh:273]
- El grep de detalle busca `✘|↳|Issue recorded|Expectation failed`, que no incluye `error:` ni `signal` [repo:scripts/gates.sh:280]
- El script declara Bash 3.2 y corre con /bin/bash [repo:scripts/gates.sh:2]
- `set -u` sin `set -e`, asi que el rc no aborta el script [repo:scripts/gates.sh:4]
- gates.sh ya crea un temporal para el manifiesto con mktemp [repo:scripts/gates.sh:125]
- y ya registra a nivel de script `trap 'rm -f "$manifest_tmp"' EXIT`, que es el unico trap del archivo [repo:scripts/gates.sh:126]
- CI corre el gate en macos-26 con `scripts/gates.sh` tal cual [repo:.github/workflows/ci.yml:21]
- `scripts/tsan.sh` captura la salida igual que Gate 4, con el rc de la sustitucion, y no tiene ningun trap [repo:scripts/tsan.sh:18]
- Ante rc != 0, tsan.sh imprime el rc y un grep que si incluye `error:` pero cortado a 40 lineas, mas el tail de 20; no nombra la senal ni el ultimo test iniciado [repo:scripts/tsan.sh:37]
- `bridgeListenerTests()` es un despachador que llama 9 sub-pruebas de sockets reales en un solo @Test, asi que "ultimo test iniciado" nombra el despachador y no la sub-prueba [repo:Tests/CompanionServicesTests/BridgeListenerTests.swift:12]
- El patron para probar un script de shell desde Swift ya existe: la ruta al script se resuelve desde la raiz del repo [repo:Tests/CompanionCoreTests/TestLayerGateTests.swift:9]
- Ese test ejecuta el script con /bin/bash y un PATH minimo, y devuelve status y salida [repo:Tests/CompanionCoreTests/TestLayerGateTests.swift:61]
- `runProcess` junta stdout y stderr en un pipe y lee hasta EOF antes de esperar [repo:Tests/CompanionCoreTests/PackagingScripts21cTests.swift:153]
- Los fixtures van a un directorio temporal propio por caso [repo:Tests/CompanionTestKit/ScriptTemp.swift:4]
- En la corrida 36903280273, Gate 4 empezo 18:13:06 y fallo 18:17:32; el log solo muestra el tail, que termina en `◇ Test bridgeListenerTests() started.`, y el job tsan del mismo commit paso con 1643 tests [doc:https://github.com/karenrebecag/Companion/actions/runs/36903280273@36903280273]
Contextos: CI (GitHub Actions macos-26, bash 3.2, serial por --no-parallel), local (Mac de Karen, paralelo), y el test del script (swift test ejecutando /bin/bash sobre fixtures; no corre swift test anidado).

## 3. Fuentes primarias

- SwiftPM corre XCTest primero y Swift Testing despues, cada uno como su propio proceso hijo [ref:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Commands/SwiftTestCommand.swift#L290@5f6969f]
- En macOS, el hijo de Swift Testing es `swiftpm-testing-helper --test-bundle-path <bundle>` [ref:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Commands/SwiftTestCommand.swift#L1010@5f6969f]
- El helper hace dlopen del bundle y llama `exit(main(...))`, asi que el proceso que muere por un crash del test es el helper, no swift test [ref:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/swiftpm-testing-helper/Entrypoint.swift#L50@5f6969f]
- Si el hijo termina por senal que no sea SIGINT, SIGKILL o SIGTERM, SwiftPM emite `error: Process '<args>' exited with unexpected signal code N` y devuelve failure [ref:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Commands/SwiftTestCommand.swift#L1057@5f6969f]
- SIGINT, SIGKILL y SIGTERM del hijo, y cualquier exit code distinto de 0 (salvo EXIT_NO_TESTS_FOUND), caen en `default: return .failure` sin ningun mensaje [ref:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Commands/SwiftTestCommand.swift#L1061@5f6969f]
- Un resultado failure pone `executionStatus = .failure` [ref:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Commands/SwiftTestCommand.swift#L387@5f6969f]
- Con executionStatus failure, swift test lanza `ExitCode.failure` [ref:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/CoreCommands/SwiftCommandState.swift#L139@5f6969f]
- `ExitCode.failure` de ArgumentParser es EXIT_FAILURE, es decir 1 [ref:https://github.com/apple/swift-argument-parser/blob/1021ac8cea2a15420588e21a6497b264b56fa09c/Sources/ArgumentParser/Utilities/Platform.swift#L150@1021ac8]
- La salida de los tests se reenvia con `print` al stdout de swift test, mientras los diagnosticos van por el handler de observabilidad a stderr [ref:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Commands/SwiftTestCommand.swift#L546@5f6969f]
- El handler de diagnosticos se construye sobre TSCBasic.stderrStream [ref:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/CoreCommands/SwiftCommandState.swift#L318@5f6969f]
- Comprobado con un paquete desechable (swift 6.3.3, --no-parallel, un test que se mata a si mismo): SIGKILL, SIGTERM y exit(3) dan rc=1 sin ninguna linea de error; abort da rc=1 y `exited with unexpected signal code 6`; fatalError da rc=1 y `signal code 5` [ref:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Commands/SwiftTestCommand.swift#L1051@5f6969f]
- En ese mismo experimento la linea `error: ... signal code N` salio ANTES de `◇ Test run started.`, porque stderr se escribe al momento y el stdout de swift test se vacia al salir; en una suite de 1643 tests queda miles de lineas arriba del tail [ref:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Commands/SwiftTestCommand.swift#L549@5f6969f]
- Los argumentos de la linea de comando de swift test, incluido `--no-parallel`, se reenvian a Swift Testing [ref:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Commands/SwiftTestCommand.swift#L504@5f6969f]
- Swift Testing reconoce `--no-parallel` y apaga la paralelizacion [ref:https://github.com/swiftlang/swift-testing/blob/48d727cc1cf4eda667c858c501495f1018f69d21/Sources/Testing/ABI/EntryPoints/EntryPoint.swift#L489@48d727c]
- Swift Testing escribe sus eventos de consola a stderr [ref:https://github.com/swiftlang/swift-testing/blob/48d727cc1cf4eda667c858c501495f1018f69d21/Sources/Testing/ABI/EntryPoints/EntryPoint.swift#L73@48d727c]
- Cada escritura a FileHandle hace fflush por defecto, asi que la linea `started` sale del helper antes de que corra el cuerpo del test [ref:https://github.com/swiftlang/swift-testing/blob/48d727cc1cf4eda667c858c501495f1018f69d21/Sources/Testing/Support/FileHandle.swift#L379@48d727c]
- El evento testStarted se imprime con el simbolo default como `<Test|Suite> <nombre> started.` [ref:https://github.com/swiftlang/swift-testing/blob/48d727cc1cf4eda667c858c501495f1018f69d21/Sources/Testing/Events/Recorder/Event.HumanReadableOutputRecorder.swift#L410@48d727c]
- El cierre de un test es `<Test|Suite> <nombre>[ with N test cases] <passed|failed|was cancelled> after <duracion>...`, con el conteo de casos ENTRE el nombre y el verbo en los parametrizados [ref:https://github.com/swiftlang/swift-testing/blob/48d727cc1cf4eda667c858c501495f1018f69d21/Sources/Testing/Events/Recorder/Event.HumanReadableOutputRecorder.swift#L441@48d727c]
- El resumen final es `Test run with N tests in M suites <passed|failed> after ...` y solo se imprime en runEnded [ref:https://github.com/swiftlang/swift-testing/blob/48d727cc1cf4eda667c858c501495f1018f69d21/Sources/Testing/Events/Recorder/Event.HumanReadableOutputRecorder.swift#L620@48d727c]
- Glifos en Apple y Linux: default U+25C7 `◇`, pass U+2714 `✔`, pass con known issues U+2501 `━`, fail U+2718 `✘`, details U+21B3 `↳`; en Windows son otros [ref:https://github.com/swiftlang/swift-testing/blob/48d727cc1cf4eda667c858c501495f1018f69d21/Sources/Testing/Events/Recorder/Event.Symbol.swift#L117@48d727c]
- Bash 3.2: el valor de retorno de un comando simple es su exit status, o 128+n si termino por la senal n [ref:https://github.com/apple-oss-distributions/bash/blob/51bf3fc6f26e9517c3a2e4bc3d208f9b39b87178/bash-3.2/doc/bash.1#L480@51bf3fc]
- Bash 3.2: si tras la expansion no queda nombre de comando (solo la asignacion `out=$(...)`), el status es el de la ultima sustitucion de comandos [ref:https://github.com/apple-oss-distributions/bash/blob/51bf3fc6f26e9517c3a2e4bc3d208f9b39b87178/bash-3.2/doc/bash.1#L3691@51bf3fc]
- POSIX: un comando que solo tiene asignaciones con sustitucion de comandos termina con el status de la ultima sustitucion, y un comando terminado por senal recibe un status mayor que 128 [doc:https://pubs.opengroup.org/onlinepubs/9799919799/utilities/V3_chap02.html@POSIX.1-2024]
- Bash 3.2: el argumento de `kill -l` puede ser un numero de senal o el exit status de un proceso terminado por senal; verificado en /bin/bash 3.2.57 local (`kill -l 137` da KILL, `kill -l 134` da ABRT) [ref:https://github.com/apple-oss-distributions/bash/blob/51bf3fc6f26e9517c3a2e4bc3d208f9b39b87178/bash-3.2/doc/bash.1#L7194@51bf3fc]
- Bash 3.2: `trap arg EXIT` asocia un solo comando a la salida del shell; un segundo `trap ... EXIT` reemplaza al primero, no se suma (verificado en /bin/bash 3.2.57: `trap "echo uno" EXIT; trap "echo dos" EXIT` imprime solo `dos`) [ref:https://github.com/apple-oss-distributions/bash/blob/51bf3fc6f26e9517c3a2e4bc3d208f9b39b87178/bash-3.2/doc/bash.1#L8335@51bf3fc]
- Apple documenta EXC_CRASH (SIGKILL) como terminacion por el sistema (recursos, force quit), EXC_BAD_ACCESS como SIGSEGV o SIGBUS, EXC_BREAKPOINT como SIGTRAP y SIGABRT como abort [doc:https://developer.apple.com/tutorials/data/documentation/xcode/understanding-the-exception-types-in-a-crash-report.json@2026-10-01]

## 4. Implementaciones de referencia

- La referencia de como se clasifica una terminacion es el propio TestRunner de SwiftPM (mantenido por swiftlang, es el codigo que corre en CI): el reporte debe reproducir su particion senal-con-mensaje / senal-muda / exit code [ref:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Commands/SwiftTestCommand.swift#L1051@5f6969f]
- La salida estructurada alternativa existe: swift test tiene `--event-stream-output-path` y `--event-stream-version`, pero estan marcadas `.hidden` [ref:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Commands/SwiftTestCommand.swift#L111@5f6969f]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Inline en gates.sh: echo rc, kill -l, awk del ultimo started | Diff minimo | Sin test; gates.sh ya mezcla 4 gates; la logica de parseo queda sin fixture | baja | No |
| B. `scripts/report-test-failure.sh <rc> <archivo>` llamado por Gate 4, con test Swift sobre fixtures como TestLayerGateTests | Testeable sin correr swift test; reusable por tsan.sh; fixtures fijan el formato de 6.3.3 | Un archivo mas; Gate 4 debe escribir la salida a un temporal y convivir con el trap EXIT que ya existe | baja | Si |
| C. Event stream JSON (`--event-stream-output-path`) y parsear testStarted/testEnded | Formato estructurado, no depende de glifos | Flag oculta; parsear JSON en bash 3.2 sin jq; no da la senal (eso sigue en stderr de SwiftPM) | media | Despues, si el parseo de consola se rompe |

Diseno recomendado (B). El script recibe rc y la ruta de un archivo con la salida completa y escribe el reporte a stdout:
1. Siempre: `rc=<n>`.
2. Si rc > 128: `swift test murio por SIG<kill -l rc>`; avisar que su stdout pudo quedar truncado, por lo que el ultimo started puede no ser el real.
3. Buscar en TODA la salida `exited with unexpected signal code ([0-9]+)` e imprimir la linea mas `SIG<kill -l N>`.
4. Si no hay linea `Test run with` (el helper no llego a runEnded): decir "el proceso de tests murio sin resumen"; si ademas no hubo linea de error de senal, decir que fue SIGKILL, SIGTERM, SIGINT o un exit() del codigo, porque SwiftPM calla esos casos.
5. En ese caso, listar los tests abiertos: cada `◇ Test X started.` sin una linea posterior `<glifo> Test X ` seguida de `with N test case`, `passed`, `failed` o `was cancelled`. Comparar el nombre como prefijo literal (awk index), no como regex, porque los nombres traen parentesis. Con --no-parallel hay a lo sumo uno; en paralelo puede haber varios y se listan todos.
6. Mantener el tail y el grep actuales, agregando `error:` al grep.

Gate 4 pasa a escribir `out` a un temporal con mktemp y llama al script solo cuando rc != 0. Limpieza del temporal: gates.sh ya tiene `trap 'rm -f "$manifest_tmp"' EXIT` en la linea 126, y un segundo `trap ... EXIT` lo reemplazaria, asi que el temporal del manifiesto quedaria sin borrar. Dos formas validas, a elegir en la spec:
- (B1) Extender el trap existente para que borre ambos: declarar `manifest_tmp=""` y `test_out_tmp=""` antes del trap y dejar un solo `trap 'rm -f "$manifest_tmp" "$test_out_tmp"' EXIT`. Con `set -u` las dos variables deben existir antes de que el trap pueda dispararse.
- (B2) No tocar el trap y borrar el temporal de la salida con `rm -f` explicito justo despues de llamar al reporte. Es mas simple, pero si el script se interrumpe entre mktemp y rm, el temporal queda en $TMPDIR.
B1 es la forma que no deja nada si el script muere a mitad; B2 es aceptable porque el temporal vive segundos y esta en $TMPDIR.

## 6. Evidencia en contra

- La razon mas fuerte contra B: parsear consola humana es fragil; Swift Testing puede cambiar el texto de `started.` o de los verbos entre versiones, y el reporte dejaria de ver el test abierto sin que nada falle [ref:https://github.com/swiftlang/swift-testing/blob/48d727cc1cf4eda667c858c501495f1018f69d21/Sources/Testing/Events/Recorder/Event.HumanReadableOutputRecorder.swift#L410@48d727c]
- Se acepta porque el reporte solo corre cuando ya hay fallo (no puede volver rojo un gate verde) y porque el test del script fija el formato con un fixture tomado de la salida real de 6.3.3; si cambia el formato, el reporte cae a "sin test abierto identificado" y el rc y la senal se siguen imprimiendo [repo:scripts/gates.sh:269]
- Segundo punto en contra: "ultimo test iniciado" no identifica la sub-prueba dentro de un despachador como bridgeListenerTests; eso no lo resuelve el reporte y queda como limite conocido [repo:Tests/CompanionServicesTests/BridgeListenerTests.swift:13]

## 7. Ejemplares y anti-ejemplos

- Ejemplar: el test del script debe correrlo con /bin/bash y PATH minimo, como ya hace el gate de capas [repo:Tests/CompanionCoreTests/TestLayerGateTests.swift:61]
- Ejemplar de fixture: salida que termina en `◇ Test bridgeListenerTests() started.` con rc 1 y sin `Test run with`, copiada de la corrida real [doc:https://github.com/karenrebecag/Companion/actions/runs/36903280273@36903280273]
- Anti-ejemplo: buscar la causa solo en las ultimas 20 lineas; la linea de senal de SwiftPM queda arriba del bloque de Swift Testing [repo:scripts/gates.sh:273]
- Anti-ejemplo: tratar `rc > 128` como el detector de crash; el crash del helper llega como rc=1 [ref:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/CoreCommands/SwiftCommandState.swift#L140@5f6969f]
- Anti-ejemplo: agregar en Gate 4 un `trap 'rm -f "$test_out_tmp"' EXIT` propio; pisa el trap del manifiesto y ese temporal deja de borrarse [repo:scripts/gates.sh:126]

## 8. Trampas

- rc=1 no distingue "un test fallo" de "el helper murio": el discriminante es la ausencia de `Test run with` [ref:https://github.com/swiftlang/swift-testing/blob/48d727cc1cf4eda667c858c501495f1018f69d21/Sources/Testing/Events/Recorder/Event.HumanReadableOutputRecorder.swift#L620@48d727c]
- SIGKILL, SIGTERM y SIGINT del helper no dejan ninguna linea; un reporte que solo busque `signal code` concluiria "sin senal" cuando si la hubo [ref:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Commands/SwiftTestCommand.swift#L1057@5f6969f]
- La linea `error: ... signal code N` aparece fuera de orden respecto a la salida de los tests; hay que buscarla en todo el archivo [ref:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Commands/SwiftTestCommand.swift#L549@5f6969f]
- Los parametrizados cierran con `Test X with N test cases passed`, asi que un match de `Test X passed` dejaria abierto un test que si cerro [ref:https://github.com/swiftlang/swift-testing/blob/48d727cc1cf4eda667c858c501495f1018f69d21/Sources/Testing/Events/Recorder/Event.HumanReadableOutputRecorder.swift#L441@48d727c]
- Las suites tambien emiten `◇ Suite X started.`; el reporte debe nombrar el Test abierto y no la Suite que lo contiene [ref:https://github.com/swiftlang/swift-testing/blob/48d727cc1cf4eda667c858c501495f1018f69d21/Sources/Testing/Events/Recorder/Event.HumanReadableOutputRecorder.swift#L187@48d727c]
- Los nombres de test no son unicos entre suites, y en local la corrida es paralela: el par started/ended por nombre puede confundirse; en CI (--no-parallel) el ultimo started abierto es fiable [repo:scripts/gates.sh:266]
- Trap EXIT existente: gates.sh ya registra un trap EXIT para el temporal del manifiesto, y en bash un segundo `trap ... EXIT` lo reemplaza; si Gate 4 agrega el suyo, el temporal del manifiesto se fuga, y si no agrega nada, el temporal de la salida nunca se borra. Arreglo: extender el trap unico a ambos archivos (B1) o borrar el temporal de la salida con `rm -f` explicito tras el reporte (B2) [repo:scripts/gates.sh:126]
- La regla de reemplazo del trap es de bash, no de gates.sh: un solo comando por senal [ref:https://github.com/apple-oss-distributions/bash/blob/51bf3fc6f26e9517c3a2e4bc3d208f9b39b87178/bash-3.2/doc/bash.1#L8335@51bf3fc]
- Contexto CI: corre bash 3.2, sin `mapfile` ni arrays asociativos; awk y grep -E del sistema bastan [repo:scripts/gates.sh:2]
- Contexto local: paralelo, pueden quedar varios tests abiertos y hay que listarlos todos [repo:scripts/gates.sh:266]
- Contexto del test del script: corre dentro de swift test pero solo ejecuta /bin/bash sobre fixtures, nunca un swift test anidado [repo:Tests/CompanionCoreTests/TestLayerGateTests.swift:57]
- Contexto tsan.sh: tiene el mismo punto ciego (no nombra senal ni ultimo test iniciado, y su grep de `error:` se corta en 40 lineas) y no tiene trap, asi que si adopta el reporte necesita su propio trap EXIT para el temporal [repo:scripts/tsan.sh:33]
- Si el proyecto suma tests XCTest, sus lineas son `Test Case '-[...]' started.` y corren antes de Swift Testing; hoy no hay `import XCTest` en Tests/, pero el reporte no los cubriria [ref:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Commands/SwiftTestCommand.swift#L291@5f6969f]

## 9. Incertidumbre

- ASSUMPTION: el swift-package-manager que trae Xcode (swiftlang-6.3.3.1.3) se comporta como el tag abierto swift-6.3.3-RELEASE. prueba: ya corroborado en parte por el paquete desechable local (mismo texto de error y rc=1); repetirlo en macos-26 con un workflow aparte si hiciera falta.
- ASSUMPTION: en la corrida 36903280273 no se sabe la senal; con la evidencia de este brief pudo ser SIGKILL/SIGTERM (mudas) o una senal con mensaje (SIGSEGV, SIGBUS, SIGPIPE) cuya linea quedo arriba del tail, porque el log no conserva la salida completa. prueba: re-correr el job con el reporte nuevo (gates.sh no imprime la salida completa, asi que el log actual no la tiene).
- ASSUMPTION: bridgeListenerTests usa sockets reales y un write a un socket cerrado sin SIG_IGN produce SIGPIPE (13), que SwiftPM si reportaria con mensaje; es una hipotesis de causa, no un hallazgo. prueba: correr `swift test --filter bridgeListenerTests --no-parallel` en bucle en un runner y buscar `signal code 13`.
- ASSUMPTION: macOS deja un `.ips` de swiftpm-testing-helper en ~/Library/Logs/DiagnosticReports para crashes con senal sincronica (SIGSEGV, SIGABRT, SIGTRAP) y no para SIGKILL externo; en la Mac local existen archivos `swiftpm-testing-helper-*.ips` de corridas anteriores, pero no se abrieron. prueba: tras un abort en el paquete desechable, listar el directorio y comparar con un SIGKILL. Subir esos reportes como artifact de CI es un cambio de CI y escala a Karen.
- ASSUMPTION: ExitCode.failure = 1 se leyo en swift-argument-parser main (1021ac8), no en la version exacta que fija SwiftPM 6.3.3. prueba: el experimento local ya dio rc=1 en los cinco modos de muerte.
- [NEEDS CLARIFICATION: el reporte debe vivir solo en Gate 4 o tambien en scripts/tsan.sh, que corre la misma suite y tiene el mismo punto ciego?]
- [NEEDS CLARIFICATION: para el temporal de la salida, extender el trap EXIT unico de gates.sh a ambos archivos (B1), borrarlo con rm explicito tras el reporte (B2), o pasar la salida por stdin y no crear archivo?]

## 10. Checklist de estandar

- [ ] Gate 4 imprime `rc=<n>` en todo fallo de swift test.
- [ ] Si rc > 128, imprime el nombre de la senal con `kill -l <rc>` y avisa que la salida pudo quedar truncada.
- [ ] Busca en la salida completa (no en el tail) `exited with unexpected signal code N` e imprime la linea y el nombre de la senal.
- [ ] Si falta la linea `Test run with`, dice que el proceso de tests murio sin resumen, y si ademas no hay linea de senal, que fue SIGKILL/SIGTERM/SIGINT o un exit() del codigo.
- [ ] En ese caso lista los `◇ Test X started.` sin cierre, tolerando `with N test cases` entre nombre y verbo, ignorando lineas `Suite`, y comparando el nombre literal.
- [ ] La logica vive en `scripts/report-test-failure.sh <rc> <archivo>` y corre en bash 3.2 con herramientas del sistema.
- [ ] Un test Swift lo ejecuta con /bin/bash y PATH minimo sobre fixtures: (a) termina en started, rc 1, sin resumen, sin senal; (b) igual con la linea de signal code 6 al inicio; (c) rc 134; (d) fallo normal con `✘` y resumen, donde NO debe hablar de crash; (e) parametrizado cerrado con `with N test cases`.
- [ ] El grep de detalle actual se mantiene y suma `error:`.
- [ ] gates.sh sigue teniendo un solo `trap ... EXIT`: o ese trap borra tanto `$manifest_tmp` como el temporal de la salida de tests (ambas variables inicializadas antes del trap por `set -u`), o el temporal de la salida se borra con `rm -f` explicito tras el reporte; tras una corrida de gates.sh no queda ningun `companion-manifest.*` ni temporal de salida en $TMPDIR.
- [ ] Si el reporte se adopta tambien en `scripts/tsan.sh` (lineas 18-19 capturan la salida, 33-41 la reportan con el mismo punto ciego), tsan.sh agrega su propio `trap ... EXIT` para su temporal, porque hoy no tiene ninguno.
- [ ] Ningun cambio a .github/workflows en este PR.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | SwiftTestCommand.swift (TestRunner, run, args) | swiftlang/swift-package-manager | swift-6.3.3-RELEASE 5f6969f | 2026-10-01 | high |
| 2 | SwiftCommandState.swift | swiftlang/swift-package-manager | swift-6.3.3-RELEASE 5f6969f | 2026-10-01 | high |
| 3 | swiftpm-testing-helper/Entrypoint.swift | swiftlang/swift-package-manager | swift-6.3.3-RELEASE 5f6969f | 2026-10-01 | high |
| 4 | Event.HumanReadableOutputRecorder.swift, Event.Symbol.swift, EntryPoint.swift, FileHandle.swift | swiftlang/swift-testing | swift-6.3.3-RELEASE 48d727c | 2026-10-01 | high |
| 5 | Platform.swift (exitCodeFailure) | apple/swift-argument-parser | main 1021ac8 | 2026-10-01 | medium |
| 6 | bash.1 de bash 3.2 (comando simple, expansion, kill -l, trap) | apple-oss-distributions/bash | bash-3.2 51bf3fc | 2026-10-01 | high |
| 7 | Shell Command Language 2.8.2 | The Open Group | POSIX.1-2024 | 2026-10-01 | high |
| 8 | Understanding the exception types in a crash report | Apple | 2026-10-01 | 2026-10-01 | medium |
| 9 | CI run 36903280273 | karenrebecag/Companion | 2026-10-01 | 2026-10-01 | high |
| 10 | Paquete desechable en scratch (swift 6.3.3, modos kill/term/abort/trap/exit) | experimento propio | 2026-10-01 | 2026-10-01 | high |

[KAREN:chat 2026-10-01] Q1: si, tambien en scripts/tsan.sh, con su propio trap EXIT. Q2: B1, un temporal con un solo trap EXIT que borra ambos archivos. Q3: aceptado como limite conocido que el ultimo test iniciado nombre el dispatcher y no el sub-test.
