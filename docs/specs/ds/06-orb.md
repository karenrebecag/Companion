# DS-06 — OrbView

**Estado: BORRADOR.** Capa: organismo. Depende de: 01.

## Objetivo

El orb es el de metasidd, no un blob de Canvas. Portar las capas del
prototipo: fondo en gradiente, glows que rotan, dos wavy blobs, core glow,
particulas, inner glows, mascara circular, sombras realistas. Paleta por
estado como `VoiceState.orb(palette:)` en `../companion/Sources/Orb.swift`.

La pieza W5-4 (Canvas 30 fps) se **reemplaza**. No se "mejora".

## Referencia

`../companion/Sources/vendor/{OrbView,WavyBlobView,RotatingGlowView,
ParticlesView,RealisticShadows,OrbConfiguration}.swift`
y el puente `Orb.swift` 82-109 (scale por nivel, hover, shimmer ring se
queda para 07).

Particulas: SpriteKit como el prototipo. CompanionUI **puede** importar
SpriteKit (el gate no lo prohibe). No Rive. NOTICE ya cita MIT; mantenerlo.

## Archivos

- `Sources/CompanionUI/Orb/` (partir por archivo, cada uno ≤400)
- Reescribir `Orb.swift` / borrar `OrbLayers.swift` del Canvas pobre
- Contrato publico `Orb(state:levels:accentColor:)` se mantiene; por
  dentro usa `OrbView(configuration:)`

## Contrato

`OrbConfiguration` con los mismos flags y speeds por `TurnState` que
`VoiceState.orb`. Idle sin particulas; listening/thinking/speaking con;
error paleta ambar, sin particulas.

Reduce-motion: speed 0, particulas off, scale de audio off.

Coste: el prototipo ya vive con eso al lado del hilo. Si algo se recorta
por rendimiento, se anota en el spec y se re-aprueba — no se recorta
callado.

## Portar

- Capas metasidd: gradiente, glows que rotan, wavy blobs, core, particulas,
  inner glows, mascara, sombras
- Paleta por estado como `VoiceState.orb(palette:)`
- Particulas SpriteKit. NOTICE MIT intacto
- Idle sin particulas; listening/thinking/speaking con; error ambar, sin

## Fuera

- Rive (ADR 003). ControlBar (08). ShimmerRing (07). VoiceSession
- El Canvas de W5-4: se **reemplaza**, no se mejora
- Recorte por rendimiento callado

## Reescribir

- Contrato publico `Orb(state:levels:accentColor:)` se mantiene
- Por dentro `OrbView(configuration:)` + `TurnState`, no `VoiceState`
- Reduce-motion: speed 0, particulas off, scale de audio off
- Archivos en `Orb/`, cada uno ≤400; borrar `OrbLayers` del Canvas
- Coste: si algo se recorta, se anota y se re-aprueba

## Hallazgos

- Paleta de "quien responde" del prototipo era 3 tintas por cerebro.
  El rebuild solo tiene `accent`: tres paradas derivadas de ese color.
  Error sigue ambar, no el acento.
- `OrbLayers.swift` no se borra (regla de casa); el Canvas se vacio.

## Done

Al lado del prototipo, idle/listen/think/speak/error se reconocen como
el mismo objeto. Si se ve un circulo plano con puntitos, no esta.
