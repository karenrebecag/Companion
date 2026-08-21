# Wave 5 — Producto

**Estado: CERRADA** — 5a, 5b, 5c, 5d y 5e — 2026-08-21. Tokens con tema oscuro, motion,
onboarding pulido, ajustes (perfil, apariencia, voz con preview) y atajos.
Las decisiones **[DECIDIR]** siguen abiertas: no bloquean 5a.

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

## Cierre de 5a (2026-08-21)

Entregado: rampa de color con tema oscuro y acento elegible, motion con
duraciones nombradas, onboarding con errores accionables y enlace a la clave,
hoja de ajustes con perfil / apariencia / voz, preview de voz por el endpoint
de audio del chat (nunca Realtime, para no rozar el grafo del microfono) y
modelo de atajos con deteccion de conflictos.

Correcciones sobre lo entregado por el agente:
- El preview de voz venia sin implementar con el argumento de que faltaban
  metodos en el ViewModel; en realidad el cliente de audio y el reproductor
  ya existian desde Wave 3. Implementado con su puerto en Core y probado con
  un muestreador falso.
- Los ajustes no tenian perfil ni voz, solo apariencia.
- Tokens.swift quedo en 445 lineas: partido en rampa y elecciones.

Pendiente para 5b+: cablear los atajos a eventos reales de teclado (hoy el
modelo existe y esta probado, pero nada lo escucha), tarjetas ricas, orb,
distribucion y docs publicos.

## Cierre de 5b, 5d y 5e (2026-08-21)

- **5b — tarjetas**: mapa, galeria y fuentes se renderizan desde el hilo; un
  bloque con JSON invalido degrada a bloque de codigo. Las fuentes salen de
  la prosa y se muestran como enlaces, sin duplicar la seccion.
- **Atajos** (deuda de 5a): monitor de teclado instalado desde la ventana,
  cableado al ViewModel de voz, y con la regla de que escribir en un campo de
  texto gana sobre el atajo. Seccion de atajos en Ajustes.
- **5d — distribucion**: CI que corre las mismas gates, script de release que
  firma y notariza cuando hay credenciales y degrada avisando cuando no,
  entitlements minimos, y docs/DISTRIBUTION.md.
- **5e — open source**: licencia MIT, NOTICE (el proyecto no lleva codigo de
  terceros) y CONTRIBUTING que exige demostrar el cableado y leer el ledger
  antes de tocar audio.

Correccion sobre lo entregado: `SourcesCard` quedaba construida pero sin que
nadie la instanciara (decimo caso del patron del repo); cableada al render de
mensajes.

Pendiente: 5c (orb en SwiftUI, ADR 003) y la prueba manual de Karen.

## Cierre de 5c (2026-08-21)

Orb en SwiftUI puro (ADR 003), dibujado con Canvas: respira en reposo, sigue
el nivel del microfono al escuchar, pulsa al pensar, se mueve con la voz del
agente al hablar y se apaga hacia el color de error. Respeta la preferencia
de movimiento reducido. La logica de apariencia vive en funciones puras con
sus tests; la vista solo dibuja.
