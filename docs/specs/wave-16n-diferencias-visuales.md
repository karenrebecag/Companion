# Wave 16n — Diferencias visuales contra Incredible (capturas 2026-09-25 20:13)

**Estado: CERRADO EN CÓDIGO (2026-09-25, sin commit). Aprobado con "corrige todo. lanza una investigacion mas a profundidad".**
Evidencia: cuatro capturas de Karen, Companion junto a Incredible (Home, barra lateral, isla), y
`docs/research/incredible-ui-detalle.md` (valores exactos sacados de su JS y CSS).

## 1. Qué falla (visto en las capturas)

| Zona | Companion | Incredible |
|---|---|---|
| Fuente de la ventana | Geist | Sistema (SF Pro) — **16k-2, hecha en esta wave** |
| Saludo | regular | semibold, −0.02em |
| Banner | negro plano, título ~16, cuerpo ~11, tecla pequeña | foto con degradado, título grande semibold, cuerpo 16 al 72 %, tecla grande blanca |
| Fila de tarea | título 13, globo suelto, círculo con flecha que se vuelve negro (error de 16l) | título mayor, globo en círculo con borde, insignia "Done", hora 14 en gris, chevron sin círculo |
| Etiqueta de grupo | "Hoy" 13 | "Today" mayor |
| Barra lateral | blanca, nombre en texto normal, una fila pequeña | panel gris propio, logo, grupos con etiqueta, filas grandes con icono de línea, píldora gris a todo el ancho |
| Cuenta | foto, nombre cortado 13, flechas arriba/abajo | monograma en círculo, nombre mayor, chevron abajo |
| Isla | texto sobre negro sin campo, cuatro píldoras sueltas, orbe pequeño, volumen abajo | campo propio con clip y enviar dentro, orbe grande fuera, volumen arriba a la izquierda, filo claro en el borde |

## 2. Sesiones

- **16n-1 Home**: saludo, banner, lista (fila, globo en círculo, insignia, hora, chevron,
  etiqueta de grupo), quitar el `GlowChip` de las filas.
- **16n-2 Barra lateral**: panel, marca, filas, grupos, cuenta. Solo la forma: las páginas que
  Incredible lista y Companion no tiene no se inventan (16j decide cuáles entran).
- **16n-3 Isla**: campo con clip y enviar dentro, orbe fuera, volumen arriba, filo.

## 3. Límites

- La foto del banner y la tarjeta "Use cases" son imágenes de Incredible: no se copian. El
  banner toma su forma y tipografía; la imagen queda como hueco para un asset propio.
- Insignia "Done": se muestra solo si la conversación tiene un estado de terminado que
  Companion conozca; si no existe el dato, no se inventa.

## 4. Cierre (2026-09-25, sin commit)

- **16k-2 hecha aquí**: la ventana habla SF Pro (`Fonts.sans`); la isla, la bienvenida y la
  hoja de aprobación, Geist (`GeistFont`, `Fonts.geist`).
- **16n-1 Home**: cabecera de 98 con el saludo a 20 semibold −0.02em; columna de 1300 con 40 a
  los lados; banner `#171310`, radio 22, 40 × 24, título 22 semibold, cuerpo 15 al 75 %, tecla
  de marca con degradado y labio (`BrandKeycapView`); lista con radio 22, divisores a 18, filas
  18 × 14 con título 14 medium, icono redondo de 24 con borde, hora 12 y chevron de 16 sin
  círculo. El círculo con flecha de 16l (`GlowChip`, `glowRow`) se borró.
- **16n-2 Barra lateral**: 248, `#f9f9f9`, separador `#eee`, marca en 22 semibold, filas de 38
  en banda de 42 (radio 10, icono 18, 14 medium, seleccionado negro 7 %), cuenta de 54 con
  monograma `#C8DCF1` si no hay foto y chevron abajo al 35 %.
- **16n-3 Isla**: campo propio (38 de alto, radio 12, blanco 7.5 %) con el texto a 14, el clip
  (30) y enviar (28, blanco 13 %; blanco sólido cuando hay texto) dentro; orbe de 36 fuera a 8;
  volumen y "…" como iconos sueltos en la franja del notch a la izquierda; filo blanco 12 % al
  abrirse. Medidas del campo tomadas de la captura de las 20:13 (el CSS pone radio 0 en ese modo
  y la captura muestra el campo redondeado: manda la captura).

No entra, por falta de dato o de asset: la insignia "Done" (las conversaciones no guardan un
estado de terminado), la foto del banner y la tarjeta "Use cases" (imágenes de Incredible), el
logo con icono (no hay asset propio) y las páginas de la barra que Companion no tiene (16j).

Revisión (code-reviewer, APPROVE tras re-revisión acotada): la lógica del popover y de Escape pasó a
funciones puras con test (`IslandPopoverToggle`, `IslandEscape`); la tecla de marca escala una
sola vez (`BrandKeycapView.em`, probado en cada delta); chevron de la cuenta (`Semantic.chevron`)
e icono de la fila (`Semantic.surface`) respetan el modo oscuro. Queda código muerto de la
reescritura de 16j (HeaderView, StatusLine, ControlBar, ChatInputView, AttachmentStrip): no se
tocó en esta wave.
