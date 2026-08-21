# DS-05 — Header

**Estado: BORRADOR.** Capa: organismo. Depende de: 01, 02, 03, 04.

## Objetivo

Quitar el chrome de herramienta ("Nueva conversación", "Cambiar clave",
controles de voz en la cabecera). El header es: logo Companion, selector
de quien responde, toggle voz/texto, historial, carpeta, engranaje,
avatar. Padding superior grande (`10 * grid`) porque la titlebar es
transparente.

## Referencia

`../companion/Sources/CompanionRoot.swift` 182-307.

Choice: `Fonts.mono` ~11.5, chevron que rota, `hoverChip`.
Mode: capsula con `matchedGeometryEffect` en el segmento activo.
Historial: `HoverIconButton` clock.
Gear: `gearshape` + help. Avatar: circulo 7 grid.

## Archivos

- `Sources/CompanionUI/HeaderView.swift` (nuevo)
- `Sources/CompanionUI/ThreadView.swift` (sacar chrome actual)
- `Sources/CompanionUI/CompanionRootView.swift` (componer header)

Carpeta de trabajo: si el rebuild no tiene `onFolder` todavia, el boton
existe y no-op o abre Ajustes; no se omite el hueco.

## Portar

- Logo, choice, modo, historial, carpeta, gear, avatar
- Padding superior `10 * grid` (titlebar transparente: hallazgo 01/02)
- Choice: mono ~11.5, chevron que rota, `hoverChip`
- Modo: capsula + `matchedGeometryEffect`
- Historial: `HoverIconButton` clock. Gear: `gearshape` + help
- Avatar: circulo 7 grid
- Cascada Escape confirm → sheet → menu → stop (cicatriz)

## Fuera

- ControlBar, chat, settings overlay (12)
- Inventar `onFolder` si no existe: el boton ocupa el hueco (no-op o Ajustes)
- Chrome de herramienta ("Nueva conversación", "Cambiar clave", mute en header)

## Reescribir

- `Space` / `Semantic` / `HoverIconButton` / `IconGlyph` de 02-04
- `HeaderView` nuevo; `ThreadView` pierde el chrome actual
- Engrane abre el `.sheet` de hoy hasta 12
- Clearance de semaforos que 01/02 aplazaron: aqui se cierra

## Hallazgos

- Mute/orb-bar no vuelven al header: viven en DS-08. Hasta entonces el
  atajo y el orb siguen cortando la sesion.
- El toggle de modo no esconde el composer: eso es DS-10.
- Avatar sin foto local todavia: circulo + SF, abre Ajustes. Carpeta abre
  Ajustes (no hay `onFolder`).
- Choice/history se pintan en el root, despues del click-away. Dentro de
  HeaderView el sink se comia las filas.

## Done

Al abrir las dos apps, la franja de arriba es la misma composicion.
Si siguen existiendo "Nueva conversación" y "Mute" en la cabecera, no esta.
