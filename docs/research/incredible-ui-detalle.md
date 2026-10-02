# Incredible (macOS/Tauri) — detalle visual de UI (cualitativo)

Inspección en solo lectura de la app instalada de Incredible. Este brief ya no lleva extractos del
binario: nada de selectores, nombres de archivos del bundle, variables CSS, constantes del código ni
valores literales de className. Las medidas, colores y tiempos exactos viven solo en la referencia local.
Aquí quedan las observaciones en palabras. Donde algo no se pudo confirmar se marca **no encontrado**.

---

## 1. Home — layout de página

- Columna central ancha, con padding lateral generoso que se reduce en contenedores estrechos.
- Cabecera pegajosa de altura fija sobre el fondo de lienzo, con el saludo ("Welcome, {nombre}") como título de diálogo semibold y tracking ligeramente cerrado.
- Una columna lateral cuyo ancho cambia según haya progreso visible o no, pegada bajo la misma cabecera.

(referencia local para las medidas)

---

## 2. Home — hero banner

- Banner de radio grande sobre un fondo oscuro cálido, con título blanco semibold, párrafo corto al 75 % de blanco y las teclas del atajo incrustadas en el título a un tamaño algo mayor que el texto.
- Una foto a la derecha, fundida hacia la izquierda con una máscara de gradiente; se oculta en anchos pequeños.
- Las teclas (keycaps) son piezas claras con borde, relieve inferior y sombra; la variante del hero es más contrastada. Llevan un símbolo atenuado y un separador "+" más pequeño, y una animación de "respiración" suave en reposo.

(referencia local para las medidas)

---

## 3. Home — lista Today/historial

- Secciones con una etiqueta de grupo ("Today") pegajosa bajo la cabecera, con un desvanecido debajo, texto de cuerpo mediano y color atenuado.
- Cada grupo es una tarjeta de radio grande; las filas se separan con un divisor casi invisible con margen lateral, salvo antes de la primera fila.
- Fila: título mediano que se trunca, chips de apps o sitios como círculos con borde, un badge de estado y, si terminó, la hora relativa en cifras tabulares y atenuada; chevron tenue al final. Hover con velo de negro; foco con contorno visible.
- Badges: "Scheduled" y "On autopilot" como píldoras de velo con icono; estados Done (verde tenue), Working (azul con icono girando), Needs you (naranja, más llamativo) y Stalled.
- Chips de archivo sin miniatura en un cuadro de radio chip.
- No se pudo aislar la función que formatea "hace 2 horas".

(referencia local para las medidas)

---

## 4. Sidebar

- Panel lateral de ancho fijo sobre el gris secundario, con borde derecho fino y un espacio superior para los semáforos de macOS.
- Fila del logo con el wordmark, con más margen superior en macOS, y un chip de plan opcional en tono de marca claro.
- Etiquetas de sección pequeñas y atenuadas (generadas desde una lista, no strings sueltas).
- Ítems de navegación de altura fija, con icono, texto de fila mediano, hover de velo y estado activo con un velo algo más fuerte sin cambiar el color del texto. Admiten sangría, punto naranja de notificación, punto verde con ping y badge numérico tabular.
- Un riel de "use cases" con una tarjeta promocional de radio medio que crece levemente al hover: zona de imagen con fondo de dos gradientes radiales, círculo blanco con una bombilla al centro, título y subtítulo.
- Fila de cuenta al fondo: botón con avatar circular (foto o monograma sobre azul claro), nombre, chip de plan y un chevron que rota según el menú esté abierto. El menú de perfil se abre hacia arriba y es más ancho que el botón.

(referencia local para las medidas)

---

## 5. Island (overlay del notch) — composer

- El composer tiene dos modos: tarjeta independiente (superficie oscura, borde tenue, radio grande, sombra y anillo de foco azul) y modo isla, donde la superficie es negra, sin borde ni radio propio porque la forma la da la isla.
- Tres niveles de texto en blanco, acento azul claro, color de error propio y una curva de salida suave (referencia local).
- Campo de texto de varias líneas con altura máxima; la toolbar queda debajo.
- **Clip (adjuntar):** primer botón de la toolbar, a la izquierda.
- **Texto de ayuda** ("↑↓ history · esc to close") atenuado, y un espaciador que empuja micrófono y enviar a la derecha.
- **Micrófono:** mismo botón circular; grabando se tiñe de rojo.
- **Enviar:** último elemento, circular; se vuelve blanco con texto oscuro cuando hay texto listo.
- En modo isla hay un botón-orbe "Talk/Stop" recortado en círculo, que da un destello rojo, y un botón cerrar pequeño.
- Tarjeta de adjunto vertical con borde, imagen a sangre.

(referencia local para las medidas)

---

## 6. Island (overlay del notch) — rim / hairline / glow / header / controles / volumen / stack

### Contenedor (pill colapsado)

- Píldora pequeña, con fondo y borde de píldora, texto pequeño.
- La línea de la isla es más corta en reposo y más larga con actividad; el radio sube por tres pasos (semilla, indicio, abierto) hasta el radio de panel.
- Varias dimensiones (altura de barra, ancho del notch, padding, alto abierto) no están en el CSS: se inyectan por JS según el notch físico detectado.
- Ítems de acción circulares de diámetro fijo y un tamaño de icono algo mayor en la topline con slots de cabecera.

### Rim / hairline / glow

- **Rim:** halo azul horizontal que sobresale un poco de los lados, invisible por defecto y que aparece con los estados de actividad.
- **Hairline:** línea fina de borde que aparece cuando la isla está abierta, detrás del rim.
- **Glow:** resplandor desenfocado que se activa según la señal de la tarea (naranja si está bloqueada, verde si terminó), en la capa más profunda.

### Header / controles / bar-side

- La topline usa una rejilla de tres columnas con el hueco del notch en el centro y padding lateral.
- **El volumen vive en la columna izquierda**, junto al contenido trailing de la cabecera; la columna derecha aloja las barras de agentes.
- Los controles son botones circulares sin fondo, blancos, con separación pequeña.

### Menú de volumen

- Popover anclado arriba del botón, centrado. Cabecera con título pequeño semibold y valor ("Muted" o porcentaje) en cifras tabulares.
- Pista delgada redondeada con relleno de acento y perilla blanca que se ve algo más pequeña en reposo; zona de toque invisible más alta que la pista; atenuada si está silenciado.

### Stack de contenido

- Columna vertical bajo la barra, con márgenes laterales iguales al inset de la fila de chat.
- El slot del composer anima opacidad y desplazamiento; los slots de conversación y de tarjetas pueden hacer scroll vertical.
- **"Tres círculos punteados de slots": no encontrado.** Ningún selector combina borde discontinuo con forma circular, y los candidatos más cercanos no usan borde discontinuo.

### Otros elementos (ya resueltos antes)

Aviso en píldora con variantes de información, error y éxito; tooltip en píldora; tarjetas de captura por
tipo (texto del portapapeles, captura, archivo, referencia de tarea); confirmación con ancho acotado; popup
de contenido enriquecido de radio grande y sombra profunda. Ver `incredible-isla-componentes.md`.

---

## Notas metodológicas

- Los tokens de radio y tipografía son los mismos en toda la app (home y sidebar); los del composer y de
  la isla son propios del overlay (referencia local).
- Algunos componentes tienen en el bundle alias de dos letras por el empaquetado; cuando no fue posible
  rastrear la definición exacta se dejó constancia en la fila en vez de adivinar el valor.
