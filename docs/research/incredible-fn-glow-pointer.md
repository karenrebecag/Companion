# Incredible.app (v0.2.36) — glow de pantalla, puntero y tooltips/dropdowns del island (cualitativo)

Investigación de solo lectura sobre la app instalada. Este brief ya no lleva extractos del binario: nada de
valores de shaders, CSS, JS, nombres de archivos del bundle, claves de configuración ni texto de
`Info.plist`. Esos detalles (constantes, tiempos, curvas, colores, selectores, rutas) viven solo en la
referencia local. Aquí queda lo observable, en palabras.

---

## 1. Glow de pantalla al mantener fn

- Hay dos implementaciones del efecto en la app: un shader WebGL a pantalla completa, que es el que se
  usa hoy, y un método anterior en CSS puro (gradientes cónicos y máscaras) que sigue presente pero ya no
  es el predeterminado. Hay además variantes alternativas del shader que no se usan en producción.
- El ajuste del usuario es un solo interruptor de activar o desactivar el glow; no hay selector de método
  expuesto de forma normal. Existe una función separada para capturar pantallas al soltar fn.

### 1.A — Glow actual (shader)

- **Color:** una paleta de cuatro tonos (azul, teal, violeta, cian) en rueda continua; el color depende del
  ángulo alrededor del centro de pantalla y deriva muy despacio en el tiempo, de modo que una vuelta
  completa tarda alrededor de un minuto (referencia local).
- **Variación por activación:** cada hold de fn sortea una fase y semilla nuevas; el dibujo no se repite igual.
- **Forma:** el brillo entra desde el borde con una caída suave y un borde ondulado, no una franja recta.
  Sigue el rectángulo de la pantalla con esquinas cuadradas, no la curvatura del bisel.
- **Opacidad:** techo en torno a la mitad.
- **Entrada y salida:** entra rápido y sale bastante más despacio. En estado de espera la pantalla se
  atenúa a la mitad.
- **Audio:** no reacciona al nivel de voz. El único pulso es la deriva temporal y el estado
  (apagado, esperando, activo).

### 1.B — Método CSS anterior

- Banda de borde de grosor moderado con opacidad alta y esquina redondeada; el gradiente usa los mismos
  cuatro tonos que el shader.
- Una variante anterior era toda azul: dos pinturas cónicas que rotaban en sentidos contrarios, con una
  "respiración" lenta del marco.
- La aparición lleva un retraso y una curva asentada; la activación dispara una onda que se expande y se desvanece.
- Tampoco reacciona al audio.

(referencia local para todas las constantes)

---

## 2. Puntero / selección de elemento al mantener fn

### 2.A — Rastro de tinta

- La posición real del cursor llega desde el lado nativo y se redistribuye a la página; el rastro solo se
  dibuja mientras dura el hold.
- Trazo azul sólido y grueso que se afina hasta desaparecer en la cola, con un suavizado que deja un
  pequeño arrastre respecto al cursor, y un corte cuando el cursor salta de pantalla.
- Se compone con transparencia sobre un canvas, con recorte al área viva por rendimiento.

### 2.B — Orbe cerca del cursor (no es un highlight del elemento)

- No se encontró ningún contorno o relleno que resalte el elemento de UI bajo el cursor. Lo que existe es
  un orbe pequeño que sigue al cursor durante el hold, con un seguimiento más perezoso que el rastro.
- Cuando el sistema captura algo (archivo, texto seleccionado o texto copiado) aparece una píldora oscura
  con icono; entra con rebote, sale acelerando hacia arriba y las píldoras se apilan.
- El mecanismo de captura es nativo; el tamaño de recorte de captura y la estructura del nodo de
  accesibilidad no están en el frontend.
- Un cursor a medida con colores por acción (click, escribir, captura, scroll, navegar) existe en la
  demo o tour de un cursor inyectado en páginas web; se cita solo como idea de paleta por modo, no como
  comportamiento confirmado del puntero de escritorio.

---

## 3. Tooltips y dropdowns del island/notch

### Tooltip

- Aparece arriba del disparador, centrado, con una variante hacia abajo y otra dentro de la isla que
  deja espacio para no tapar la barra de chat activa.
- Píldora oscura, alta, con borde tenue y texto blanco mediano.
- Anima solo la opacidad, rápido y sin escala ni traslado.
- Es un portal dentro de la misma ventana del overlay, no una ventana nativa nueva (evidencia indirecta).

### Dropdown / menú

- Estrecho, con radio grande, padding pequeño, fondo claro, borde fino y sombra amplia; el popover
  hermano comparte el estilo.
- Ítems compactos con hover de fondo suave.
- Abre con fade y un pequeño deslizamiento vertical (la capa base de la librería usa una escala leve);
  cierra más rápido.
- Tiene un backdrop invisible que captura clics fuera para cerrar, y capas por encima del contenido de la isla.
- Se posiciona según el lado disponible. No queda recortado por la forma de píldora de la isla.
- El popover de una pila de tarjetas aparece arriba del disparador con fade y deslizamiento corto, y
  cierra más rápido y lineal.

(referencia local para medidas, tiempos y curvas)

---

## Notas / lo que NO se pudo confirmar

- La lista real de ventanas de Tauri no se pudo confirmar; la evidencia indirecta apunta a portal DOM,
  no a ventana nueva para tooltips y menús.
- Reactividad del glow al audio: no encontrada.
- Highlight del elemento bajo el cursor: no encontrado.
- Estructura del nodo de accesibilidad y tamaño de recorte de captura: del lado nativo, fuera del alcance.
- Investigación estática; no se verificó con un pantallazo en vivo.
