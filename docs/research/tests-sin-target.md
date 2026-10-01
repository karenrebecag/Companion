# Reference Brief: que todo .swift bajo Tests/ lo compile algun target (exclude, sources, path)

Slug: tests-sin-target | Nivel: quick | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 ESCALATE

## 1. Pregunta y decisiones abiertas

La regla R3 de `scripts/check-test-layers.sh` (python sobre el JSON de `swift package dump-package`) debe garantizar que cada `.swift` bajo `Tests/` lo compila algun target declarado. Ya falla con una carpeta `Tests/<dir>` sin target y (desde e05be88) con un `.swift` suelto en `Tests/`. Falta cubrir: `exclude:`, `sources:` y un `path:` propio que cubre solo parte de una carpeta.
Decisiones abiertas:
- D1. De donde sale "este archivo lo compila un target": reimplementar en python las reglas de SwiftPM sobre `dump-package` (opcion A) o preguntarle a SwiftPM con `swift package describe --type json` (opcion B).
- D2. Si las dos comprobaciones actuales (carpeta sin target, `.swift` suelto) se conservan o se absorben en la nueva.

## 2. Estado actual

- El paquete declara `swift-tools-version: 6.2`; la toolchain local medida en esta corrida es Swift 6.3.3 [repo:Package.swift:1]
- Ningun target usa `exclude:` ni `sources:`; los de `Tests/` solo fijan `path:` a su carpeta, p. ej. `CompanionTestKit` [repo:Package.swift:49]
- Los test targets tambien fijan `path:` a una carpeta propia, p. ej. `CompanionCoreTests` [repo:Package.swift:79]
- `dump-package` del repo hoy da `exclude: []` en los 12 targets, sin clave `sources` y con `path` solo en los 8 de `Tests/` (salida leida en esta corrida) [repo:Package.swift:49]
- `gates.sh` genera el JSON con `swift package dump-package` y se lo pasa al gate [repo:scripts/gates.sh:127]
- El gate marca una carpeta como "con Swift" si `find` halla un `.swift` dentro [repo:scripts/check-test-layers.sh:113]
- El gate falla con cualquier `Tests/*.swift` suelto (commit e05be88) [repo:scripts/check-test-layers.sh:119]
- La comprobacion de carpeta compara el NOMBRE de la carpeta con el NOMBRE del target, no con su `path` [repo:scripts/check-test-layers.sh:139]
- Los tests del gate le pasan un JSON fabricado (`manifest.json`) con la forma de `dump-package` [repo:Tests/CompanionCoreTests/TestLayerGateTests.swift:47]
- `swift package describe --type json` sobre el repo lista 12 targets cuyos `sources` cubren los 417 `.swift` versionados bajo `Tests/`, sin huerfanos (medido en esta corrida; 0.3 s de CPU, 24 s de pared esperando el lock de otro SwiftPM) [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/Commands/Utilities/DescribedPackage.swift#L251@6.2]
Contextos: `scripts/gates.sh` local y en CI (macos-26) que corre el gate; `swift test` y `swift build` que deciden que se compila; los tests del gate (`TestLayerGateTests`) que alimentan JSON fabricado.

## 3. Fuentes primarias

- `path` es relativo a la raiz del paquete; sin `path`, los test targets se buscan en `Tests/<Nombre>` y otros directorios predefinidos [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageDescription/Target.swift#L73@6.2]
- `sources` nil incluye todo fuente valido de la ruta del target; sus entradas son relativas a la ruta del target y un directorio se recorre recursivamente [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageDescription/Target.swift#L100@6.2]
- `exclude` es relativo a la ruta del target y tiene precedencia sobre `sources` y `resources` [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageDescription/Target.swift#L117@6.2]
- `TargetDescription` es `Encodable` sintetizado: las claves JSON son `path` (String opcional), `sources` ([String] opcional) y `exclude` ([String]) [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageModel/Manifest/TargetDescription.swift#L108@6.2]
- Un opcional nil se omite (codificacion sintetizada), asi que `path` y `sources` FALTAN cuando no se declaran, mientras `exclude` siempre esta; confirmado en la salida real de esta corrida [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageModel/Manifest/TargetDescription.swift#L120@6.2]
- `dump-package` solo carga el manifiesto raiz y lo codifica; no recorre archivos ni valida solapes [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/Commands/PackageCommands/DumpCommands.swift#L125@6.2]
- Las cadenas de `exclude` se resuelven como ruta absoluta relativa a la ruta del target (normalizada) [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/TargetSourcesBuilder.swift#L84@6.2]
- `sources` solo se vuelve "declarado" si tiene al menos una entrada valida: `sources: []` se comporta como nil y compila todo [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/TargetSourcesBuilder.swift#L102@6.2]
- El recorrido salta nombres que empiezan con punto [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/TargetSourcesBuilder.swift#L452@6.2]
- Un excluido se salta por igualdad exacta de ruta, y si es directorio no se entra en el [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/TargetSourcesBuilder.swift#L470@6.2]
- Con `sources` declarado se quitan las reglas de compilacion automaticas: un `.swift` fuera de esas rutas queda sin regla [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/TargetSourcesBuilder.swift#L293@6.2]
- Los archivos sin regla se devuelven como `others` [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/TargetSourcesBuilder.swift#L215@6.2]
- Un `path` propio debe ser relativo, estar dentro del paquete y ser un directorio existente [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/PackageBuilder.swift#L571@6.2]
- Desde tools 5.9, si es el unico target de su tipo, puede ocupar todo el directorio predefinido (`Tests/`) [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/PackageBuilder.swift#L612@6.2]
- Un archivo no puede pertenecer a dos targets: el segundo que lo reclama lanza "has overlapping sources" [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/PackageBuilder.swift#L1435@6.2]
- Un target que se queda sin fuentes (p. ej. todo excluido) no se crea; solo se emite un aviso "no sources" [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/PackageBuilder.swift#L819@6.2]
- En el build nativo, solo `others` produce el aviso "found N file(s) which are unhandled"; un excluido nunca llega ahi [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/Build/BuildOperation.swift#L742@6.2]
- El texto del aviso pide declararlos como recursos o excluirlos [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/Build/BuildOperation.swift#L765@6.2]
- El build system por defecto en 6.2 es `native` [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/CoreCommands/Options.swift#L538@6.2]
- `swift package describe` carga el paquete raiz con `loadRootPackage` (PackageBuilder completo, sin build) [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/Commands/PackageCommands/Describe.swift#L41@6.2]
- Su modo JSON usa claves snake_case [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/Commands/PackageCommands/Describe.swift#L56@6.2]
- El codigo declara el modo JSON "guaranteed to be parsable and stable across time" [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/Commands/PackageCommands/Describe.swift#L69@6.2]
- Cada target descrito trae `path` relativo a la raiz y `sources` relativas a ese `path`, ya calculadas por SwiftPM [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/Commands/Utilities/DescribedPackage.swift#L250@6.2]
- `describe` lista `package.modules`, que no incluye los targets vacios [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/Commands/Utilities/DescribedPackage.swift#L60@6.2]
- En release/6.3 (f096e72) `Describe.swift` y `DescribedPackage.swift` tienen la misma forma y `TargetSourcesBuilder.swift` solo cambia un `print` por un aviso de observabilidad [doc:https://github.com/swiftlang/swift-package-manager/blob/f096e728bff0aa5449b0fcf7ab4619472d968e1c/Sources/Commands/Utilities/DescribedPackage.swift#L250@6.3]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Python sobre `dump-package`: raiz = `normpath(path)` o `Tests/<name>`; dueño si esta bajo la raiz, no bajo `raiz/e` para ningun `exclude`, y bajo algun `raiz/s` si `sources` no esta vacio | Sin otra llamada a SwiftPM; los tests siguen con JSON fabricado | Copia reglas de SwiftPM que pueden derivar: `sources: []` = nil, puntos iniciales, directorios opacos, recursos que ganan a `sources`, regla de target unico, igualdad exacta (sensible a mayusculas) del exclude | ~35-50 lineas de python | No, salvo que B no se pueda usar |
| B. `swift package describe --type json`: dueño = union de `path/sources` de todos los targets; huerfano = `find Tests -name '*.swift'` menos esa union | Es el calculo real de SwiftPM; absorbe la carpeta sin target y el `.swift` suelto; falla si dos targets solapan; JSON declarado estable | Segundo proceso de SwiftPM (sin build, ~0.3 s CPU); espera el lock de `.build` si otro SwiftPM corre; los tests del gate necesitan un JSON fabricado con forma de `describe` | ~15-20 lineas (3-4 en gates.sh, 10-15 en el gate) | Si |

## 6. Evidencia en contra

- Contra B: `describe` toma el lock de `.build`; en esta corrida espero 24 s a otro SwiftPM; en `gates.sh` corre en serie, asi que se acepta [repo:scripts/gates.sh:127]
- Contra B: el `type` de un target regular sale `library` en `describe` y `regular` en `dump-package`; si R3 se pasara entera a `describe` habria que reescribir las comprobaciones de tipo, por eso B solo AGREGA la propiedad y deja R3 sobre `dump-package` [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/Commands/Utilities/DescribedPackage.swift#L246@6.2]
- Contra B: el gate deja de ser una funcion pura de un JSON y un arbol; se resuelve aceptando un tercer argumento con el JSON de `describe`, que los tests fabrican igual que hoy fabrican el manifiesto [repo:Tests/CompanionCoreTests/TestLayerGateTests.swift:60]
- Contra A: cada regla copiada es una que SwiftPM puede cambiar sin avisar; `sources: []` = "todo" es contraintuitivo y una implementacion ingenua lo leeria como "nada" [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/TargetSourcesBuilder.swift#L102@6.2]

## 8. Trampas

- Un `.swift` excluido no produce ningun aviso en build: nunca entra en `contents` y por tanto tampoco en `others` [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/TargetSourcesBuilder.swift#L470@6.2]
- Un `.swift` que `sources:` deja fuera SI produce "unhandled" en `swift build`, pero es un aviso: el build pasa y el test no corre [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/Build/BuildOperation.swift#L765@6.2]
- `describe` y `dump-package` no emiten ese aviso (observado en un paquete de prueba con `sources: ["Only"]`); solo el build lo hace [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/Commands/PackageCommands/Describe.swift#L41@6.2]
- Un exclude que no existe solo avisa "Invalid Exclude ... File not found" (observado en `describe`); no falla [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/TargetSourcesBuilder.swift#L121@6.2]
- En APFS, `exclude: ["x.swift"]` no excluye `X.swift` (igualdad de ruta exacta) aunque el chequeo de existencia pase; un gate que normalice mayusculas lo daria por excluido (falso positivo, falla cerrado) [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/TargetSourcesBuilder.swift#L470@6.2]
- Rutas anidadas (`Tests/Nest` y `Tests/Nest/Inner`) sin exclude del interior: `describe` falla con "has overlapping sources" y `dump-package` pasa; con A el solape no se ve [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/PackageBuilder.swift#L1435@6.2]
- Un `.swift` cuyo nombre empieza con punto no se compila nunca; con B aparece como huerfano (correcto) [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/TargetSourcesBuilder.swift#L452@6.2]
- `path` llega tal como se escribio (`./Tests/Nest/`) en `dump-package`, pero `describe` lo devuelve normalizado (`Tests/Nest`, observado) [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/Commands/Utilities/DescribedPackage.swift#L250@6.2]
- La comprobacion actual por NOMBRE de carpeta da falso fallo si un target con otro nombre usa `path: "Tests/X"`; con B desaparece [repo:scripts/check-test-layers.sh:139]
- Enumerar con `find` sobre el disco y no con `git ls-files`: SwiftPM compila tambien lo no versionado [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/TargetSourcesBuilder.swift#L452@6.2]
- Contexto `gates.sh` (local y CI): B suma una llamada a `describe` tras `dump-package`; un fallo de `describe` debe contar como fallo del gate [repo:scripts/gates.sh:127]
- Contexto `TestLayerGateTests`: hoy fabrican solo el manifiesto; con B hay que fabricar tambien el JSON de `describe` [repo:Tests/CompanionCoreTests/TestLayerGateTests.swift:47]

## 9. Incertidumbre

- ASSUMPTION: en 6.2/6.3 con el build nativo, un `.swift` dejado fuera por `sources:` imprime "unhandled" y el build termina con exito (leido en fuente, no ejecutado: la tarea prohibe `swift build`). prueba: en un paquete de prueba con `sources: ["Only"]` y un `Top.swift` fuera, correr `swift build` y ver el aviso y el codigo de salida 0.
- ASSUMPTION: `swift package describe` no crea `.build` ni `.swiftpm` (observado en el paquete de prueba, no en CI). prueba: en un checkout limpio de CI, correr `describe` y listar la raiz.
- ASSUMPTION: el JSON de `describe` en 6.2 es igual al de 6.3.3 local (misma fuente en ambos tags, solo ejecutado 6.3.3). prueba: correr `swift package describe --type json` en macos-26 de CI y comparar las claves `targets[].path` y `targets[].sources`.
- [NEEDS CLARIFICATION: Karen, ¿se acepta una segunda llamada a SwiftPM (`describe`) en `gates.sh`, o el gate debe seguir dependiendo solo de `dump-package`?]

## 10. Checklist de estandar

- [ ] El gate falla si un `.swift` bajo `Tests/` (enumerado con `find`, no con git) no aparece en la union de `path/sources` de `swift package describe --type json`.
- [ ] Casos negativos: archivo excluido por `exclude:`, archivo fuera de `sources:`, archivo en una subcarpeta que un `path:` propio no cubre, `.swift` suelto en `Tests/`, carpeta sin target.
- [ ] Un fallo o salida no JSON de `describe` hace fallar el gate (falla cerrado).
- [ ] `sources: []` en un fixture NO marca huerfanos (SwiftPM lo trata como nil).
- [ ] Las comprobaciones de carpeta sin target y de `.swift` suelto se conservan o se reemplazan, y la spec lo dice.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | PackageDescription Target.swift (path, sources, exclude) | swiftlang | release/6.2 215e9f9 | 2026-10-01 | high |
| 2 | TargetDescription.swift, DumpCommands.swift | swiftlang | release/6.2 215e9f9 | 2026-10-01 | high |
| 3 | TargetSourcesBuilder.swift, PackageBuilder.swift | swiftlang | release/6.2 215e9f9 (diff contra 6.3 f096e72) | 2026-10-01 | high |
| 4 | BuildOperation.swift, Options.swift | swiftlang | release/6.2 215e9f9 | 2026-10-01 | high |
| 5 | Describe.swift, DescribedPackage.swift | swiftlang | release/6.2 215e9f9 y release/6.3 f096e72 | 2026-10-01 | high |
| 6 | Paquete de prueba local (dump-package, describe) | propio | Swift 6.3.3 | 2026-10-01 | medium |

[KAREN:chat 2026-10-01] Opcion B: swift package describe en gates.sh.
