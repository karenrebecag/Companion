# DS-09 — Chat

**Estado: BORRADOR.** Capa: organismo. Depende de: 01, 05.

## Objetivo

El hilo se lee como el prototipo: idle centrado, lista invertida con
autoscroll, burbuja de usuario sobre acento, agente a la izquierda en
prosa (Markdown + syntax ya existe), esqueleto shimmer si esta busy sin
stream, cursor `▍` en streaming.

## Referencia

`../companion/Sources/vendor/livekit-ui/ChatViews.swift`.
`upsideDown` + `LazyVStack` de mensajes reversed.
Burbuja usuario: `fgOnAccent` sobre `accent`, `cornerRadiusLarge`.

**Desviacion explicita:** `RiveIdleView` no se porta (ADR 003). Idle =
frase + caption ("Toca el orb…" / "Escribe abajo…"), sin mascota Rive.
El orb de 08 es la presencia. No sustituir Rive por un GIF ni por el
Canvas pobre.

## Archivos

- `Sources/CompanionUI/ThreadView.swift` (reescribir el hilo)
- Sacar recents de la cabecera (viven en dropdown 05)

## Portar

- Idle centrado. Lista invertida (`upsideDown` + `LazyVStack` reversed)
- Autoscroll. Burbuja usuario: tinta on-accent sobre accent
- Agente a la izquierda, Markdown + syntax (ya existe)
- Esqueleto shimmer si busy sin stream. Cursor `▍` en streaming

## Fuera

- `RiveIdleView` (ADR 003). No GIF ni Canvas pobre de mascota
- Input (10). Recents en cabecera (dropdown 05)
- Reabrir cards de mapa/galeria

## Reescribir

- Idle = frase + caption ("Toca el orb…" / "Escribe abajo…"); el orb de 08
  es la presencia
- `ThreadView` se reescribe el hilo, no el composer
- Tokens `Semantic` / `Radius` (cornerRadiusLarge → token de este repo)

## Hallazgos

- Idle sin Rive (ADR 003): frase + caption. El orb de 08 es la presencia.
- Composer sigue siempre visible (DS-10).
- Copy overlay del agente no se porta aqui; Markdown ya permite seleccionar.

## Done

Hilo vacio: frase centrada, no una lista vacia. Un turno tuyo es burbuja
a la derecha; el del agente no. Scroll ancla abajo. Si parece un log de
Xcode, no esta.
