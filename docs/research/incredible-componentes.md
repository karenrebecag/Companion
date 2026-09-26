# Incredible — inventario de componentes (medido)

Fecha: 2026-09-25. Fuente: CSS y nombres de fragmentos de JS de Incredible 0.2.36, extraídos en
solo lectura del binario. Solo valores y nombres de componentes; nada de su código entra al repo.
Complementa `incredible-tipografia.md` (escala, espaciado, radios) y las specs 16c–16j (interacción).

## 1. Superficies de la app

| Superficie | Familia de clases | Qué contiene |
|---|---|---|
| Ventana principal | Tailwind + `btn-*`, `card-*`, `glow-card`, `action-card`, `keycap-*`, `status-dot` | Páginas: home, skills ("Teach Incredible your tasks", "Set Incredible on autopilot"), connectors (Apps), browser, history, reminders, memory, contacts |
| Ajustes | `ui-*` | Pestañas: general, shortcuts, voice, permissions, vocabulary, contacts |
| Isla (notch) | `ov-island-*`, `ci-*` (campo), `sg-*` (onda y orbe) | Barra, campo, tarjetas, menú, avisos, dictado, tooltip |
| Respuestas ricas | `ovx-*` | Popup de 580 px con h2/h3, listas, tablas, callouts, código con copiar, file chips, gráficas |
| Flujos / grabar tarea | `ov-wf-*` | Preguntas, checklist, pasos de ejecución, tarjetas de fase |
| Bienvenida | `fr-*`, `onb-*`, `brandauth-*` | Escenas, permisos guiados, prueba de sonido, nombre, testimonios, login |

## 2. Tokens de color, sombra y curva (tema claro)

| Token | Valor |
|---|---|
| surface-primary | `#fff` |
| surface-canvas | `#fcfcfc` |
| surface-secondary | `#f9f9f9` |
| surface-hover | negro 2 % |
| surface-active | negro 5 % |
| surface-inset | `#e5e5ea` |
| status green / orange / red | `#34c759` / `#ff9500` / `#ff3b30`, muted al 12 % |
| border-default | `#e5e5ea` |
| border-input | `#e0e0e5` |
| border-chrome | `#eee` |
| border-row | negro 5 % |
| accent | `#007aff` (solo enlaces y foco; los botones son negros) |
| btn-ghost-fg | `#8e8e93` |
| focus-ring | `#007aff` al 25 %, 3 px |
| popup-hover | negro 5 % |
| popup-danger | `#f5d3d8` |
| brand (naranja) | `#ff7802`, claro `#fff1e6` |
| shadow-card | `0 1 2 #0000 3 %` + `0 4 10 −2 #0000 4 %` |
| shadow-raised | `0 6 20` negro 8 % |
| shadow-popup | `0 16 48` negro 14 % |
| shadow-modal | `0 32 100` negro 20 % |
| ease-standard | `(.4, 0, .2, 1)` |
| ease-settle | `(.32, .72, 0, 1)` |
| ease-glide | `(.22, 1, .36, 1)` |
| ease-bounce | `(.34, 1.56, .64, 1)` |

Isla (oscura): fondo `#000`; texto 95 / 64 / 42 % de blanco; tile 6 % (hover 12 %); borde 9 %;
divisor 7 %; acento `#78aaff`; error `#ff7a64`; verde de señal `#78d6a8`.

## 3. Componentes de la ventana principal y ajustes

| Componente | Medidas |
|---|---|
| Botón (el que usa la app) | píldora, `font-semibold`, disabled 50 %, curva settle 0.2 s. md: alto 40, padding 0 × 20, 14 px. hero: padding 12 × 24, 15 px |
| Botón solid neutro | negro con texto blanco; hover escala 1.03 (sobre foto: blanco con texto negro) |
| Botón ghost neutro | fondo negro 5 %, texto negro, padding 0 × 16, 13 px; hover escala 1.03 |
| Botón danger | solid `#dc2626` (hover `#b91c1c`); ghost rojo al 10 % con texto `#b91c1c` (hover 15 %) |
| Botón de icono | sm 28 (icono 16), md 34 (icono 18); redondo o radio chip; gris secundario; hover fondo 2 % y texto primario |
| Badge | radio chip 10, padding 2 × 8, 11 px / 500, interlineado 1.35; tonos neutral (negro 5 % + secundario), accent, positive, warning, danger (color al 12 %), solid |
| `btn-primary` azul | clase heredada, casi sin uso (8 apariciones contra el botón de arriba): **no se copia** |
| Botón de bienvenida | alto 46, padding 0 × 30, píldora, 15 px / 600, tracking −0.01em |
| Cerrar | círculo 32, fondo 5 % |
| Switch | md 38 × 23 (pulgar 19), sm 28 × 16 (pulgar 12), padding 2; apagado negro 16 %, encendido texto primario; en oscuro 12 % y verde `#78d6a8` al 90 %; 0.22 s settle |
| Select | alto 42 (sm 34 con 12 px), padding 0 × 12, radio 14, fondo 5 %, 13 px / 500, gap 8; foco anillo 1 px negro 10 % |
| Menú (popup) | padding 6, gap 2, radio 18, fondo blanco, borde negro 8 %, sombra popup; entra y sale en 0.2 s |
| Ítem de menú | padding 8 × 10, radio 8, 13 px / 500, gap 10, hover negro 5 %, peligro `#f5d3d8` |
| Tarjeta elevada | fondo blanco, borde `#eee`, radio 16 |
| Action card | padding 24 / 24 / 26, gap 24, radio 28, borde `#eee`, sombra card, halo radial de acento que sigue al cursor (0.9 s settle) |
| Glow card | fila que se ilumina en hover (`#f9f9f9`), CTA y flecha que pasan a negro |
| Keycap sm | radio 4, padding 2 × 6, 10 px, sombra `0 1` 8 % |
| Keycap lg | radio 12, padding 8 × 16, 16 px, sombra `0 2 4` + borde inferior interior de 2 px |
| Status dot | círculo de 8 |
| Toasts | Sonner (éxito y error) |

## 4. Componentes de la isla

| Componente | Medidas |
|---|---|
| Isla cerrada | píldora de 90 × 36, 12 px |
| Barra abierta | alto 100, radio 28 al abrir (10 como semilla, 12 como indicio), morph 0.26 s |
| Campo (`ci-shell`) | padding 16 / 18 / 14, 14 px / 1.45 |
| Botón enviar | círculo 30; activo blanco con sombra |
| Botones de herramienta | ancho 31, icono 18, ítem 32 |
| Menú de la isla | ancho 230, padding 6, gap 4, radio 16, 13 px |
| Aviso | píldora, padding 6 × 12, 11.5 px / 500 |
| Tooltip | píldora de 40 de alto, padding 0 × 18, 14 px / 500 |
| Tarjetas de captura | alto 64, radio 6: texto 120, captura de pantalla 96, archivo 120, tarea 140 |
| Confirmación | padding 18 / 52 / 18 / 18, ancho 380–480, 13.5 px, icono con acento verde, azul, naranja o ámbar al 16 % |
| Chip de referencia | radio 7, padding 1 / 7 / 1 / 5, 12.5 px / 500, color al 13 % y borde al 24 % |
| Opción de respuesta | padding 11 × 12, radio 12, gap 11, fondo blanco 6 %; hover índigo `#8184f8` |
| Popup de respuesta rica | ancho mín(580, 76 % de la pantalla), padding 18 / 22 / 16 |

## 5. Contra Companion

| Incredible | Companion hoy | Hueco |
|---|---|---|
| Switch propio 38 × 23 | `SettingsSwitch` envuelve el `Toggle` nativo | No se puede medir igual: hay que dibujarlo |
| Select propio | `Picker` nativo en Ajustes y en la barra lateral | Igual: hace falta un select propio |
| Menú popup propio | `Dropdown` propio (ventana) + `IslandPopover` (isla) | Existe; faltan medidas y estados |
| Botón solid / ghost / danger / icono | `AppButton`, `SettingsPill`, `HoverIconButton` | Existen con otras medidas; el primario es negro, no azul |
| Keycap sm / lg | `SettingsKeycap`, `WelcomeKeycap` | Dos piezas para una: unificar |
| Action card y glow card | `HomeStartCard`, `GalleryCard` | Falta el halo que sigue al cursor |
| Opción de respuesta, confirmación, chip de referencia | `IslandNoticeCard`, `ApprovalSheet` | La confirmación sí; opción y chip no existen |
| Popup de respuesta rica (`ovx`) | `MarkdownView` en el hilo | Ni tablas ni callouts ni file chips en la isla |
| Tarjetas de captura | adjuntos del chat | Falta la tira de capturas en la isla |
| Status dot, toasts | `Toasts` | Existen; falta verificar medidas |
