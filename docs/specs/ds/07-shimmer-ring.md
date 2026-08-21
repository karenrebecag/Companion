# DS-07 — ShimmerRing

**Estado: BORRADOR.** Capa: atomo. Depende de: 06.

## Objetivo

El anillo de pelo alrededor del orb es el unico chrome de estado mientras
escucha o piensa. Idle no lleva instruccion. Portar `ShimmerRing` del
prototipo (`Shimmer.swift` 74-94).

## Referencia

`../companion/Sources/Shimmer.swift`. Sweep 2 s en thinking, 1.15 s en
listening. Off si reduce-motion.

## Archivos

- `Sources/CompanionUI/Shimmer.swift` (el modifier de texto puede
  quedarse; el anillo es aparte)
- Componer en `Orb.swift` como el `VoiceOrb` del prototipo: ZStack orb +
  ring

## Portar

- `ShimmerRing` (`Shimmer.swift` 74-94)
- Sweep 2 s thinking, 1.15 s listening
- Off si reduce-motion. Idle sin anillo

## Fuera

- Shimmer de captions en ThreadView como sustituto del anillo
- ControlBar. Cambiar el modifier de texto existente

## Reescribir

- Componer en `Orb` como `VoiceOrb` del prototipo: ZStack orb + ring
- El modifier de texto de `Shimmer.swift` se queda; el anillo es aparte
- Duraciones ya en `MotionTime` si calzan; si no, constantes del anillo
  anotadas aqui, no springs nuevos de W5-5

## Hallazgos

- 2.0 y 1.15 no calzan en `MotionTime`. Viven en `ShimmerRingMotion`.
  Fade del anillo usa `MotionTime.fast` (0.15), igual que el prototipo.

## Done

Escuchando y pensando: el anillo barre. Idle: nada alrededor. Comparar
con el prototipo, no con W5-2.
