# DS-10 — Composer

**Estado: BORRADOR.** Capa: molecula. Depende de: 05 (toggle de modo), 09.

## Objetivo

Modo texto: campo propio abajo, Enter envia, sin `.roundedBorder`.
Modo voz: el campo no esta; la ControlBar ocupa su sitio, con transicion
blur+opacity nativa. El rebuild hoy muestra composer siempre.

## Referencia

`CompanionRoot.swift` 28-40 (`ChatInputView` vs `ControlBar` segun
`model.mode`). Input en el prototipo: `ChatViews.swift` (ChatInputView).

## Archivos

- `Sources/CompanionUI/ChatInputView.swift`
- `Sources/CompanionUI/CompanionRootView.swift`

El toggle de 05 es la unica forma de cambiar de modo. No un segmento
duplicado.

## Portar

- Modo texto: campo propio, Enter envia, sin `.roundedBorder`
- Modo voz: el campo no esta; ControlBar ocupa su sitio
- Transicion blur + opacity al cambiar de modo

## Fuera

- Adjuntos (11)
- Dictado en vivo si el rebuild no lo tiene: no inventar
- Segmento de modo duplicado (el toggle es 05)

## Reescribir

- Transicion nativa, no Pow
- El campo escribe `draft` como ahora
- `ChatInputView` propio; el rebuild deja de mostrar composer siempre

## Hallazgos

- Cristal `desktopGlass` del prototipo no se porta: superficie + borde
  con tokens. El campo no usa `.roundedBorder`.
- En texto no hay ControlBar (tampoco orb de 46 pt). El orb vive solo
  en modo voz, como el prototipo.

## Done

Voz: no hay textfield. Texto: hay campo y no hay orb gigante de sesion
hasta pulsar. El intercambio se siente, no es un if seco sin motion.
