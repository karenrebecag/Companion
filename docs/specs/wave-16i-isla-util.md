# Wave 16i — La isla útil: popovers, estados de trabajo y complementos del notch

**Estado: APROBADO (2026-09-25, "me gusta!"), ampliado con §8–§11 de las grabaciones de las 18:09 y 18:11; 16i-1 EN CURSO.** Karen, sobre su grabación de Companion (18:01): "faltan status,
assets y complementos del notch que lo hacen muy útil. NotchNook también presenta funcionalidades
de drag to notch… que hay de los dropdown de Incredible, ¿puedes recrear su UI y sus estados
thinking?"

Fuentes: la grabación de Companion de las 18:01 (58 s, 120 fps), la de Incredible de las 14:03,
`~/.incredible/island-cards.json` (solo la forma de las tarjetas: `kind` = result | receipt,
`needs_input`, `spoken_line`) y los textos visibles de NotchNook 1.6.2 (su catálogo es; nada de su
código). Todo se diseña con nuestro patrón y el criterio de smooth motion (spec 16f §9).

## 1. Lo que muestra la grabación de Companion (18:01)

| Momento | Qué se ve | Qué falla |
|---|---|---|
| 6,5–7,0 s | Un panel con "MacBook Pro Speakers" y un deslizador se funde con "Hablando" | No es nuestro: es el aviso de salida de audio del sistema, en el mismo sitio que la isla. Hay que confirmarlo y decidir (§2.4) |
| 7,4 s y 38,6 s | Panel negro vacío un cuadro (≥ 100 ms) al abrir y al cerrar | M1: el contenido entra tarde (260 ms) y sale antes (35 ms) que la forma; el hueco se ve |
| 9–14 s | El campo, la respuesta grande, los tres huecos | Bien |
| 22–35 s | "Crear un archivo… de la usuaria" con el hueco girando, "1 paso", `Bash: ls -la…` | El objetivo interno se ve tal cual ("de la usuaria") y el comando crudo; es trabajo de 16h, pero la tarjeta de trabajo es de aquí (§3) |
| 36 s | "Listo" con luz verde | Bien; falta el recibo con palomita (§3) |
| 40 s | Menú "…" nativo con resaltado morado del sistema | No es de la isla: fondo claro, color del sistema, sin atajos (§2.1) |

## 2. Popovers como los de Incredible (lo que Karen llama sus dropdowns)

De la grabación de Incredible, todos comparten una pieza: un popover oscuro anclado bajo su botón,
radio 12, filas con tecla dibujada, sin color del sistema. Entra con *menu dropdown*
(250 ms, desde 0,97, anclado al botón) y sale en 150 ms.

| Popover | Contenido | Función detrás |
|---|---|---|
| **Menú "…"** | Ajustes, Abrir ventana, Atajos, Comentarios, Borrar historial (con su atajo a la derecha) | Ya existe; cambia solo la forma |
| **Clip → "Añadir archivos"** | Elegir archivo; ⌥C Capturar texto; ⌥X Captura de pantalla | Elegir ya existe. Captura: `screencapture -i` a un archivo temporal que entra como adjunto. Capturar texto: la misma captura por región pasada por Vision (OCR local) y pegada en el campo |
| **Altavoz → volumen** | "Volumen 100 %" con deslizador; silenciar la voz | Volumen de la voz de Companion (`setVolume` del puerto de voz), no el del sistema |
| **Tooltips** | "Hablar fn" sobre el orb, "Enviar ↵" sobre enviar, "Parar de hablar" mientras habla | *tooltip*: entra a los 80 ms en 150 ms, sale en 50 ms |

Y los estados que acompañan:
- **Orb → botón rojo de parar** mientras habla (*icon swap*: 200 ms, escala desde 0,25).
- **Píldora "Cancelado"** bajo el panel 2 s después de parar (*notification badge*).
- **Adjunto como tarjeta** bajo el campo (nombre, tipo, quitar), en vez de mandarlo a la ventana.

### 2.4 El aviso de audio del sistema

Si el panel "MacBook Pro Speakers" es el del sistema, cuando Companion empieza a hablar la isla
debe dejarle el sitio o no provocarlo (probable causa: cambiar la salida o el volumen al arrancar la
voz). Primero se reproduce y se confirma; sin confirmación no se toca.

## 3. Estados de trabajo ("thinking")

La forma de Incredible (sus tarjetas): una **tarjeta de resultado** (título, cuerpo, "Descartar") y
un **recibo** (palomita + una línea: `Created "prueba 1.md" on your Desktop`); `needs_input` las
marca como que te necesitan. Sus estados de "pensando" no salen en ninguna grabación que tengo:
**hace falta una grabación de Incredible pensando** (un pedido que tarde, p. ej. "¿qué hay en mi
pantalla?") para medirlos igual que el notch. Hasta entonces, lo nuestro con el catálogo:

| Estado | Cómo se ve | Transición |
|---|---|---|
| Pensando (voz) | "Pensando…" con *shimmer* y el orb respirando | ya existe |
| Trabajando (encargo) | Tarjeta: el objetivo en palabras de la usuaria (de 16h), debajo los pasos como líneas que entran una a una ("Buscando el archivo", "Creándolo") en vez del comando crudo; el hueco de arriba gira | *texts reveal* por paso, *shimmer* en el paso actual |
| Te necesita | Luz ámbar, la tarjeta sube un poco y muestra la pregunta o "Permitir" | *panel reveal* |
| Hecho | Recibo con palomita dibujada + una línea; se va solo a los 6 s | *success check* |
| Falló | La línea de por qué + "Reintentar" | *error state shake* leve, una vez |

## 4. Complementos del notch (ideas de NotchNook, para un asistente)

NotchNook (sus textos visibles): bandeja de archivos ("Drag and drop files to access multiple
functions", "Remove from tray", AirDrop), control de medios, widget y actividad en vivo del
calendario, reemplazo del HUD de volumen y brillo, espejo de cámara, notas y to-do, temporizador,
atajos y Quick Apps, gestos verticales para abrir y cerrar, notch simulado en pantallas sin notch,
"evitar cerrar cuando el ratón salga".

Lo que sirve a Companion, por orden:

| # | Complemento | Qué hace en Companion | Coste / riesgo |
|---|---|---|---|
| 1 | **Soltar en el notch** | Arrastras un archivo, la pantalla se oscurece como zona de soltar (como Incredible), el notch crece y ofrece: "Pregúntale" (adjunta y abre el campo), "Guardar en la bandeja", "AirDrop" | Medio. `NSDraggingDestination` en el panel; AirDrop con `NSSharingService` |
| 2 | **Bandeja** | Hasta 6 archivos guardados en la isla para arrastrarlos luego a otra app o pedírselos a Companion ("mándale esto a Ana") | Medio; los archivos se copian a una carpeta propia y se borran al quitarlos |
| 3 | **Actividades en vivo** | En reposo, a los lados de la muesca: el temporizador que le pediste, la próxima reunión en X min, el encargo corriendo | Medio; calendario con permiso de EventKit (pregunta, no se asume) |
| 4 | **Temporizador y recordatorio por voz** | "Pon 10 minutos": cuenta atrás en el notch, suena al final | Bajo |
| 5 | **Gesto vertical** | Deslizar hacia abajo con dos dedos sobre el notch abre; hacia arriba cierra | Bajo |
| 6 | **Control de medios** | Qué suena y pausa/siguiente | Alto: la API de "Now Playing" es privada y macOS 15.4+ la restringe. Fuera por ahora |
| 7 | **HUD de volumen/brillo** | Reemplazar el del sistema | Alto y privado. Fuera |

## 5. Arreglos de motion de la grabación (van primero)

- Abrir: el contenido empieza con el panel creciendo (a +40 ms de la fase 2, no +100), recortado por
  la forma, para que nunca se vea el panel vacío.
- Cerrar: la forma empieza a recogerse a la vez que el contenido se desvanece (80 ms), en vez de
  esperar 35 ms con el panel vacío.
- Test: ningún instante en que la forma esté abierta y el contenido con opacidad 0 más de 40 ms.

## 6. Orden propuesto (sesiones; reemplazado por §12)

1. **16i-1** Arreglos de motion (§5) + popovers: pieza común, menú "…", tooltips, orb de parar,
   "Cancelado", volumen.
2. **16i-2** Añadir archivos: captura y capturar texto, tarjeta de adjunto, soltar en el notch con la
   pantalla oscurecida.
3. **16i-3** Estados de trabajo (§3), con la grabación de Incredible pensando si llega.
4. **16i-4** Bandeja, temporizador y actividades en vivo (calendario con permiso).


## 8. Incredible pensando y buscando (grabación 18:09, 64 s)

Medido cuadro a cuadro; reemplaza lo supuesto en §3.

| Fase | Cómo se ve |
|---|---|
| Escuchando | Orb a la izquierda; a la derecha una onda sobre una línea punteada y un × para cancelar; debajo, la transcripción en vivo creciendo línea a línea |
| Pensando | Tres puntos azules que laten a la izquierda (en el sitio del orb), "Thinking" a la derecha, la transcripción queda debajo |
| Acuse | Una frase corta ("Of course! Searching the web…") con las palabras aclarándose, y el campo vuelve |
| Tarea (dropdown) | Una tarjeta que **cae desde el hueco de tareas** de arriba a la derecha y sobresale del panel: icono en un anillo de progreso que cambia por fase (rayo → documento → lupa), título ("Search the web about the US"), subtítulo con dónde estabas y lo que pediste, luego el paso en vivo ("Checking today's news about the US ···" con puntos animados), botones "■ Stop" (rojo al pasar) y "View →" |
| En reposo con tarea | La isla se recoge a una barra algo más ancha que la muesca: puntos a la izquierda, el icono de la tarea girando a la derecha (actividad en vivo) |
| Resultado | La frase dicha arriba y una tarjeta grande con icono y título ("Panorama de Estados Unidos, con fuentes"), secciones, viñetas y enlaces de fuentes, con scroll dentro de la isla y un desvanecido abajo |
| Parar | El orb se vuelve rojo con "Stop talking"; al soltar, píldora "Cancelled" bajo la muesca |

## 9. "No te oí" como tarjeta (captura 18:10)

Tarjeta oscura: a la izquierda un cuadro con el micrófono tachado en azul; título "No te oí";
subtítulo "Mantén [fn] mientras hablas y di unas palabras" con la tecla dibujada; arriba a la
derecha un × dentro de un anillo que se vacía (los 6 s de `noticeDelay`); abajo a la derecha una
píldora blanca "Revisar micrófono →" que abre el permiso o Ajustes › General. Mismo molde para los
demás avisos con salida (sin claves, sin permiso, sin red).

## 10. Señalar con el cursor mientras hablas (lo que hace fn en Incredible)

Visto en la grabación: mientras mantienes fn, el cursor deja un **rastro de tinta azul** que se
desvanece (como un cometa) y los bordes de la pantalla brillan en azul. En sus ajustes existen
"screen glow" y "screenshots while holding fn", y la conversación guardada marca cada palabra con
lo que había bajo el cursor al decirla (así "esto" y "aquí" se resuelven). Para Companion:

- **Rastro:** un overlay transparente a pantalla completa, sin clics, que dibuja el recorrido del
  cursor de los últimos ~0,6 s mientras fn está abajo; se borra al soltar.
- **Brillo del borde:** degradado azul suave en los bordes mientras escucha (desactivable).
- **Qué señalaste:** cada ~100 ms mientras hablas se guarda qué hay bajo el cursor (app, ventana, el
  elemento de Accesibilidad con su texto) con la hora; al cerrar el turno se alinea con las palabras
  de la transcripción y viaja como contexto del turno. Opcional: una captura recortada alrededor del
  punto donde más se detuvo el cursor (solo con el permiso de pantalla ya dado).
- Privacidad: nada se guarda en disco ni en el log; se descarta al terminar el turno.

## 11. NotchNook: el hover y la bandeja (grabación 18:11, 23 s)

Medido a 60 cuadros por segundo:
- **Asomo al pasar el ratón:** la muesca crece de 294×38 a ~314×47,5 pt en 175 ms, se relaja a
  ~308×45 en los 300 ms siguientes (resorte con rebote visible) y a la vez aparece una **sombra
  suave debajo**: el fondo 4 pt bajo la forma se oscurece ~55 % y 30 pt más abajo ~40 %. No se abre:
  abre con clic.
- **Abrir:** el panel sale casi entero en un cuadro y el alto se asienta de 197 a 185 pt en ~400 ms.
- **Arrastrar un archivo:** la muesca se abre sola con dos zonas, "Files Tray" y "AirDrop"; la zona
  bajo el cursor se enciende (borde discontinuo azul y fondo azul oscuro).
- **Cerrado con bandeja:** a los lados de la muesca, el icono de la bandeja y "1" con el número de
  archivos.

Para Companion: **asomo antes de abrir**. Al entrar el puntero, la muesca crece a +20×+9 pt con un
resorte de 0,35/0,65 y la sombra aparece; si el puntero se queda 150 ms, abre con las dos fases de
Incredible; si se va antes, vuelve sin abrir. Así pasar por encima camino a la barra de menús no
abre nada.

## 12. Sesiones (actualizado)

1. **16i-1** (en curso): arreglos de motion (§5), asomo con sombra (§11), popovers y tooltips (§2),
   orb de parar y "Cancelado", tarjeta de avisos (§9).
2. **16i-2**: Añadir archivos (captura, capturar texto), tarjeta de adjunto, soltar en el notch (§4, §11).
3. **16i-3**: estados de trabajo como Incredible (§8): tarjeta de tarea que cae del hueco,
   actividad en vivo, tarjeta de resultado con scroll, escucha y pensando nuevos.
4. **16i-4**: señalar con el cursor (§10).
5. **16i-5**: bandeja, temporizador y actividades en vivo (§4).

## 13. Cierre de 16i-1 (2026-09-25)

Hecho, con tests (`IslandUsefulTests`, 386 verdes, gates 0 fallos) e instalado:
- §5: contenido a +40 ms de la fase 2; al cerrar, forma y fundido (80 ms) a la vez. Test: ningún
  cambio de tamaño deja el panel abierto y vacío más de 40 ms.
- §11: asomo +20×+9 pt con resorte 0,35/0,65 (6,8 % de rebote, excepción nombrada a M4 en
  `MotionSpring.lively`) y sombra; abre tras 150 ms; abrir desde el asomo nunca encoge.
- §2: popover propio para "…" y volumen (250/150 ms desde 0,97), tooltips (80 ms, 150/50 ms),
  orb rojo de parar con icon swap, píldora "Cancelado" 2 s.
- §9: tarjeta de aviso para "No te oí", permisos y fallos (tamaño card).

Revisiones: seguridad HIGH (el área de clic no seguía un cambio de muesca; `renotch`) y LOW (el
asomo agrandaba el área con el panel abierto); código HIGH (el popover no animaba), MEDIUM (ocultar
dejaba un hover tardío; el volumen reescribía todas las preferencias en cada tick, ahora al soltar).
Todas arregladas con test, salvo la animación del popover y el volumen, que no tienen test unitario
posible y se verifican en vivo.

Decidido sin preguntar: el menú "…" no muestra atajos (la isla no activa la app, así que ⌘, no
funcionaría desde ahí); "silenciar la voz" no se añadió porque `toggleMute` silencia el micrófono,
no la voz.

Pendiente de Karen: prueba en vivo (asomo, popovers, tooltips en un panel no activo, orb de parar,
tarjeta), y confirmar el aviso "MacBook Pro Speakers" (§2.4).

## 14. Cierre de 16i-2 (2026-09-28)

Hecho, con tests (`IslandAttachTests`, `IslandAttachWiringTests`; gates 0 fallos, 473 tests):
- §2: el clip abre su menú por el portal, como los de la cabecera: "Elegir archivo…", "Capturar
  texto", "Captura de pantalla". La captura es `screencapture -i -x -o` a una carpeta temporal
  propia (0700) y entra como adjunto; "Capturar texto" pasa la región por Vision en el Mac (sin
  red) y añade el texto al campo, recortado con el tope de cualquier texto en línea. Sin Grabación
  de pantalla no se abre el selector: se pide el permiso y se dice en una línea.
- Adjunto como tarjeta bajo el campo (captura con su miniatura, archivo con icono y nombre, ×
  para quitarlo); un adjunto esperando mantiene el campo abierto y basta para enviar.
- §4/§11: arrastrar un archivo a la muesca la abre en tarjeta con dos zonas, "Pregúntale"
  (adjunta) y "AirDrop" (hoja del sistema); la zona bajo el puntero se enciende con el azul
  discontinuo de NotchNook. Soltar sin zona es "Pregúntale". El arrastre nunca tapa una hoja, un
  aviso ni un trabajo en curso.

Revisiones: seguridad APPROVE con dos MEDIUM arreglados con test (una carpeta pasaba el tope de
20 MB porque su tamaño es el del inodo, y un enlace apuntaba fuera: solo entran archivos
regulares; la ventana que recibe el arrastre también recibe clics: en reposo solo cubre la muesca
física, y sigue a la tarjeta solo durante un arrastre). Código APPROVE con un MEDIUM arreglado con
test (el arrastre tapaba un aviso).

Desviaciones, decididas sin preguntar:
- "Elegir archivo…" sigue abriendo el selector de la ventana: la isla no puede activar la app
  (conformance 12d), y un selector de una app inactiva se abre detrás.
- Sin atajos ⌥C/⌥X en el menú del clip, por la misma razón que el "…" de 16i-1.
- Sin oscurecer la pantalla al arrastrar (§4 fila 1): se siguió §11, que es lo medido.
- La bandeja es 16i-5: la tarjeta de soltar tiene dos zonas, no tres.

Pendiente de Karen, en vivo (sin test unitario posible): arrastrar desde Finder a la muesca con
la isla en reposo y abierta (el paso de una ventana a otra durante el arrastre), la captura y el
OCR con el permiso dado y sin él, y AirDrop. Decisión abierta: un archivo soltado con la voz en
vivo se le pasa a la sesión de voz sin confirmar, igual que en la ventana; ¿debe esperar a enviar?
