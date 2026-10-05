# Incredible — componentes de la isla (cualitativo)

Fecha: 2026-09-25. Fuente: inspección en solo lectura del overlay de Incredible 0.2.36. Este brief ya no
lleva clases, colores, medidas ni nombres de componentes tomados del binario: eso vive solo en la referencia
local. Aquí quedan las observaciones en palabras. Complementa `incredible-componentes.md` (piezas base de la
isla ya aplicadas en 16l-4).

## 1. Display de datos: el popup de respuesta rica

Superficie oscura casi negra con borde tenue, radio grande y ancho limitado a una fracción de la pantalla
(referencia local). Tres niveles de tinta blanca y un acento azul. Bloques que soporta:

- **Encabezados:** h1 grande y firme, h2 medio, h3 pequeño que funciona como eyebrow atenuado.
- **Párrafo y lista:** cuerpo cómodo con interlineado holgado y ancho de línea limitado.
- **Tabla:** texto algo menor, dentro de un marco con borde tenue y radio.
- **Callout:** icono, título y cuerpo, con un tono al que se tiñen fondo y borde.
- **Código:** fondo aún más oscuro, barra superior con lenguaje, copiar y plegar; código en línea con relleno tenue.
- **Clave-valor:** clave atenuada, valor en tinta fuerte.
- **Chip de archivo:** mono pequeño con relleno tenue y hover más claro.
- **Cita, tareas y enlaces:** cita con relleno y radio; casilla de tarea; enlace en acento con anillo de foco.
- **Gráfica y diagrama:** lienzo de altura fija (algo más alto para circulares) dentro de un contenedor con herramientas de copiar y ver; los diagramas son Mermaid.

## 2. Estados de trabajo

- **Pensando, transcripción en vivo y voz hablando:** una línea de texto mediano; la transcripción se ve atenuada mientras llega y más firme al quedar fija; la voz se asienta a opacidad completa.
- **Línea de tiempo, carrete de iconos de lo que va tocando y barras por subagente.**
- **Tarjeta de ejecución, checklist y tarjeta de fase:** tarjetas oscuras de radio grande con sombra marcada; el checklist lleva insignia, asa y descarte. Ese checklist (`ov-wf-checklist`) es un consejo fijo de tres pasos numerados que aparece mientras se graba un workflow, no un checklist de trabajos ni casillas que se marcan; la tarjeta de ejecución solo existe para workflows guardados y aparece al pasar el puntero sobre la píldora (referencia local).
- **Fuera de este escritorio:** tarjeta con icono de la app, punto, "esperando", reanudar y parar.
- **Cuenta atrás:** anillo con pista y progreso.
- **Aviso:** píldora pequeña con tintes distintos para información, error y éxito.
- **Tarjeta genérica:** eyebrow pequeño, título firme, botón primario claro con texto oscuro, botón ghost y tile de icono.

(referencia local para las medidas y colores)

## 3. Adjuntos

- **Tarjeta de adjunto:** vertical, con imagen a sangre, nombre, extensión en etiqueta y botón de quitar que aparece al pasar el cursor; estado de error con fondo rojizo tenue.
- **Vista previa:** panel oscuro con cabecera, título, metadatos, texto, monograma y estado vacío.
- **Fila de chips** con desvanecido al final; **pila y tira de capturas** con insignia numerada.
- **Zona para soltar:** borde discontinuo y texto mediano.
- **Subida:** tarjeta con chip y flecha de transferencia.
- **Mención (@):** selector con altura máxima, ítems compactos y hover en acento.

(referencia local para las medidas)

## 4. Dictado

Tarjeta de resultado con texto mediano y acciones de copiar y ocultar. Confirmación con título, cuerpo,
primario y ghost. Envío automático con cuenta atrás.

## 5. Avisos del sistema

Tarjetas con rejilla de icono más texto y acciones: límite de uso, actualización disponible, consentimiento,
iniciar sesión, diagnóstico y pregunta con opciones. El modal con estados de ánimo, capturas y contador
es el de **feedback** (enviar una opinión o un error al fabricante), no comentarios entre personas.
Anchos y paddings en la referencia local; el ancho base del diagnóstico es `min(520px, 70vw)`, y
`min(420px, 86vw)` es solo el respaldo de pantallas de 560 px o menos.

## 6. Contra la isla de Companion

| Familia | Companion hoy | Falta |
|---|---|---|
| Datos | una tarjeta de resultado (título + línea + "Ver") | todo el popup rico: títulos, párrafos, listas, tablas, callouts, código, clave-valor, chips de archivo, citas, tareas, gráficas, diagramas |
| Estados | línea de estado con texto (escucha, pienso, actuando, trabajo con n pasos), barras de onda, anillo de cuenta atrás, luz ámbar / verde, chip de referencia (16l) | transcripción viva vs fija, carrete de lo que toca, línea de tiempo, barras de agentes, tarjeta de ejecución con pasos, checklist, fuera de este escritorio |
| Adjuntos | el clip abre la ventana | tarjetas verticales con vista previa, extensión y quitar; pila y tira de capturas; zona para soltar; subida; menciones |
| Dictado | dictado en el campo (12e) | tarjeta de resultado con copiar / ocultar; confirmación; envío automático |
| Avisos | tarjeta de aviso genérica | límite, actualización, consentimiento, sesión, diagnóstico con su rejilla |
