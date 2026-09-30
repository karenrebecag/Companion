# Acceso: `public` -> `package`

Estado: APROBADO (Karen, 2026-09-30: PR aparte de la reestructura).

## Objetivo

Core, Services y UI declaraban 4577 `public` en 341 archivos solo para
poder usarse entre targets del mismo paquete. SE-0386 (Swift 5.9) creo
`package` para eso: visible en todo el paquete, invisible fuera. Hoy no hay
forma de distinguir API real de detalle interno, y el paso siguiente (target
`CompanionTestSupport`) necesita que los fakes vean simbolos sin
`@testable import`, que no compila en release.

## Hechos verificados

- Ningun consumidor externo: `companion-mcp` es un paquete Node; ningun
  `Package.swift` fuera de las worktrees de companion-next cita
  `CompanionCore`. El producto `.library(name: "CompanionCore")` no lo usa
  nadie.
- Cero `open`, `@inlinable`, `@usableFromInline`, `@frozen`, `@_exported` o
  `public import`: nada que exija `public` por ABI o inlining.
- swift-tools 6.2: `package` disponible y SwiftPM pasa `-package-name` solo.

## Cambio

1. `public` -> `package` en posicion de declaracion en los tres targets
   (incluye `public private(set)` -> `package private(set)`), nunca en
   comentarios ni strings.
2. Quitar `.library(name: "CompanionCore", ...)` de `Package.swift` (config
   raiz): exportarlo prometia una API que nadie consume.
3. Ajustar lo que busca el texto `public`: `Choice16m6FixesTests` escanea
   `"public func choose"`; grep de todo test/gate que cite `public `.
4. `docs/ARCHITECTURE.md`: una linea en la seccion de capas.

Conformancias a protocolos de Apple (`var body: some View`, `Codable`,
`Hashable`) quedan bien con `package`: el requisito es el acceso minimo entre
tipo y protocolo, y el tipo ya es `package`.

## Ejecucion

Script que reemplaza solo `public` seguido de un modificador o palabra de
declaracion; `swift build` y arreglar lo que quede a mano; gates. Un commit
mecanico (el reemplazo) y otro con los ajustes, si los hay.

## Coordinacion (b6, d2)

Toca una linea en casi todos los archivos: choca con cualquier rama que
edite declaraciones. Va en un PR propio despues de la reestructura (#50);
b6 y d2 no tocan `Sources/` hasta que entre, asi que sufren una sola
ventana de rebase.

## Aceptacion

`swift build -c release`, `scripts/gates.sh` verdes; cero `public` de
declaracion en Sources; 1369+ tests.
