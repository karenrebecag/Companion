# Wave 5 — Producto

**Estado: BORRADOR REFINADO** — kickoff hecho (planner, 2026-08-21).
Pendiente aprobacion de Karen y las decisiones marcadas **[DECIDIR]**.

## Objetivo

De "funciona en la Mac de Karen" a "cualquiera lo descarga, lo abre y lo
entiende", y cualquiera puede contribuir.

## Recorte en tandas (cada una entrega valor por si sola)

- **5a — Lo imprescindible**: sistema de tokens completo + motion, onboarding
  pulido, ajustes (perfil, apariencia, voz con preview) y atajos. Es lo que
  hace que un extrano obtenga valor sin tocar la terminal.
- **5b — Chat rico**: protocolo comun de tarjetas + mapa, galeria, fuentes y
  reporte de encargo. Degradar a bloque de codigo si el JSON es invalido.
- **5c — Orb**: la mascota reactiva a los estados de voz.
- **5d — Distribucion**: firma, DMG, actualizaciones y CI.
- **5e — Open source**: README, CONTRIBUTING, NOTICE, licencia.

## Estado real de la UI (inventario del kickoff)

Existe y sirve: `Tokens.swift` (minimo, sin tema oscuro ni roles
semanticos), `CompanionRootView`, `OnboardingView` (esqueleto funcional),
`ThreadView` + los dos ViewModels, y los scripts `bundle.sh`,
`make-signing-cert.sh`, `gates.sh`.

No existe: motion, ajustes, preview de voz, atajos persistentes, tarjetas,
orb, notarizacion, CI, docs publicos.

Del prototipo conviene portar: la rampa de color y el enfasis elegible de
`Tokens.swift`, `Motion.swift` completo, la logica de preview de voz de
`SettingsVoice.swift`, y los codecs de las tarjetas (`MapCard`,
`GalleryCard`, `SourcesCard`). La UI de ajustes se rehace mas simple: el
prototipo usaba dropdowns propios que no valen la complejidad.

## Decisiones tecnicas recomendadas

- **Cero dependencias externas, se mantiene.** Hoy el repo no tiene ninguna
  y eso es un valor real para open source (nada que auditar, clona y
  compila). Por eso:
  - **Actualizaciones**: comprobador propio contra GitHub Releases (~80
    lineas testeables) en vez de Sparkle. → ADR 002.
  - **Orb**: SwiftUI puro (el `WavyBlobView` del prototipo) en vez de Rive,
    que anade un binario de 8-15 MB al DMG. → ADR 003.
- **Tema oscuro desde el principio** en los tokens: no es un extra, es la
  mitad de los usuarios de Mac.

## [DECIDIR] Decisiones de Karen

- **D4 — Apple Developer Program (99 USD/ano).** Con cuenta: DMG notarizado
  que abre sin advertencias. Sin cuenta: se distribuye igual por GitHub
  Releases, pero quien lo baje debe saltarse Gatekeeper a mano (aceptable
  para contribuidores, malo para "valor en 5 minutos"). Recomendacion:
  empezar sin cuenta y notarizar cuando el producto valga la pena publicar.
- **D5 — Licencia.** Recomendacion: MIT, coherente con el ecosistema del que
  tomamos referencias (hermes-agent, Orb, pow).

## Pruebas manuales al cierre de cada tanda

No hay E2E automatizado en este proyecto: es una app nativa de macOS y las
capas que fallan de verdad (TCC, CoreAudio, firma) no las ve ningun test.
La prueba manual es parte de la definicion de done, como en Wave 3.

- **5a**: empaquetar, abrir, onboarding con clave invalida (mensaje claro) y
  valida, cambiar modelo y voz con preview, cerrar y reabrir (persiste).
- **5b**: una respuesta con bloques `companion:*` renderiza tarjetas; JSON
  roto degrada a bloque de codigo sin romper el hilo.
- **5c**: el orb acompana los estados de voz, incluido el de error.
- **5d**: el DMG abre en una Mac limpia; CI verde en un PR.
- **5e**: clonar en otra maquina, seguir el README y llegar a chatear.

## Riesgos

- **Tocar la voz sin leer el ledger**: el preview de voz usa el endpoint de
  audio del chat, NO Realtime; no debe acercarse a `RealtimeAudio` ni al
  grafo del microfono (docs/REFERENCE.md, seccion audio).
- **Alcance**: 5b y 5c son pulido; si el tiempo aprieta, 5a + 5d + 5e ya
  entregan un producto distribuible.
