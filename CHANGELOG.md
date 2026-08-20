# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/es/1.1.0/). Una
entrada por wave cerrada; sin releases versionados hasta Wave 5.

## [Unreleased]

## [0.1.0-wave1] — 2026-08-20

### Added
- Nucleo puro de dominio: maquina de estados del turno, codecs Realtime/SSE
  /NDJSON, splitter de frases, endpointer, escalacion, markdown y cards
  `companion:*`, catalogo de proveedores y ejecutores (nativo siempre).
- Suite de caracterizacion portada del prototipo (mismos casos, tipos
  nuevos). 640 tests. `approval: 1` ya no concede permiso.

### Fixed
- Review post-cierre (code-reviewer + security-reviewer + tdd-guide, rojo
  primero): `request_id` vacio ya no crea solicitudes de permiso; URLs de
  `companion:locations` solo https; paths de gallery absolutos y sin `..`;
  suite de robustez ante JSON hostil (anidado 200+, multi-MB, tipos
  inesperados, UTF-8 invalido) en los cuatro codecs. 656 tests.
- Defensa anti-inyeccion de prompt: requisito estructural anadido al spec de
  Wave 4 (tools destructivas siempre via approvals).

### Changed
- `Build.version` a `0.1.0-wave1`.

## [0.1.0-wave0] — 2026-08-20

### Added
- Paquete SPM con 4 targets (Core/Services/UI/App); las dependencias entre
  targets codifican la arquitectura y las vigila el compilador.
- Swift 6.2 tools, strict concurrency; UI y App con MainActor por default.
- Suite de compliance `scripts/gates.sh`: build, estatico (secretos, prints,
  `try?` prohibido en Core/Services, topes de tamano), arquitectura (imports
  por capa) y tests.
- Harness de tests ejecutable (CLT no trae Swift Testing ni XCTest); API
  espejo de Swift Testing para migracion mecanica.
- Programa de reconstruccion por waves, ledger de cicatrices del prototipo
  de referencia, ADR 001 (desacople de Hermes).
