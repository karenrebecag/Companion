# DS-11 — Status y adjuntos

**Estado: BORRADOR.** Capa: molecula. Depende de: 09, 10.

## Objetivo

Linea de estado debajo del hilo (carpeta, caption con shimmer, cola,
jobs) — no encima como debug. Tira de adjuntos sobre el input. Drop en
toda la ventana con velo. Los adjuntos del turno van sobre la burbuja
del usuario, alineados a la derecha.

## Referencia

`CompanionRoot.swift` 19-27, 53-63, 310+.
`ChatViews.swift` 166-177 (`MessageAttachments`).
`AttachmentViews.swift` del prototipo.

## Archivos

- `Sources/CompanionUI/StatusLine.swift`
- `Sources/CompanionUI/AttachmentViews.swift`
- Root: dropDestination + velo

El attach por menu/⌘U ya existe; esta pieza es la superficie.

## Portar

- Linea de estado debajo del hilo (carpeta, caption shimmer, cola, jobs)
- Tira de adjuntos sobre el input
- Drop en toda la ventana con velo
- Adjuntos del turno sobre la burbuja de usuario, a la derecha

## Fuera

- Reabrir AttachmentStore o VoiceSession
- El attach por menu/⌘U ya existe: no rehacer el pipeline

## Reescribir

- `dropDestination` + velo en root
- `StatusLine` / `AttachmentViews` con `Semantic` / `Space`
- Status de especialista no se pinta como error de consola

## Hallazgos

- El store no se reabre: se anade tira pendiente en el ViewModel.
- Jobs vivos del prototipo no tienen lista en el rebuild; el permiso del
  especialista va en StatusLine, no como error.
- Adjuntos del turno no persisten en ConversationRecord (el schema no
  los tiene). Se ven en la sesion viva.

## Done

Arrastrar una imagen: la ventana se vela y la tira aparece. Un status
del especialista no parece un error de consola. Comparar con el
prototipo en un turno con foto.
