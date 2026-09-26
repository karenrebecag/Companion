# Incredible — componentes de la isla (medido)

Fecha: 2026-09-25. Fuente: CSS del overlay de Incredible 0.2.36 (576 clases `ov-*`, `ovx-*`,
`ci-*`), extraído en solo lectura. Solo valores; nada de su código entra al repo. Complementa
`incredible-componentes.md` (piezas base de la isla ya aplicadas en 16l-4).

## 1. Display de datos: el popup de respuesta rica (`ovx-*`)

Superficie: `rgb(14,14,16)`, borde blanco 12 %, radio 20, ancho mín(580, 76 % de pantalla),
padding 18 / 22 / 16. Tintas: 94 / 72 / 46 % de blanco y `#fff` para lo fuerte. Líneas 7 % y
14 %; rellenos 5 / 9 / 13 %; acento `#4a9cff`. Radio interior de los bloques: 12.

| Bloque | Medidas |
|---|---|
| h1 | 21 px / 650, −0.02em, interlineado 1.2, blanco |
| h2 | 15.5 px / 620, −0.01em |
| h3 | 11.5 px / 600, tinta 3 (46 %) — funciona como eyebrow |
| párrafo | 13.5 px, interlineado 1.62, −0.003em, máx. 66 caracteres de ancho |
| lista | 13.5 px, interlineado 1.6 |
| tabla | 12.5 px, interlineado 1.45, dentro de un marco con borde 7 % y radio 12 |
| callout | padding 11 × 14, gap 11, radio 12, tono al 11 % y borde al 26 %; con icono, título y cuerpo |
| código | fondo `rgb(6,6,8)`, borde 7 %, radio 12; barra de 26 con lenguaje, copiar y plegar |
| código en línea | mono 12 px, padding 1.5 × 6, radio 6, relleno 5 % |
| clave-valor | clave en tinta 3, 550, +0.01em; valor en tinta 1 |
| chip de archivo | mono 11.5 px, padding 1 / 7 / 1 / 6, radio 6, relleno 5 %; hover 9 % y blanco |
| cita | 14 px, interlineado 1.55, tinta 2, padding 10 × 16, relleno 5 %, radio 12 |
| tareas | casilla en tinta 3, etiqueta |
| enlace | acento; hover mezcla al 80 % con blanco; foco anillo de 2 |
| gráfica | lienzo de 240 de alto (264 para pie, dona, polar y radar) |
| visual (contenedor de gráfica o diagrama) | padding 14 / 16 / 12, relleno 5 %, borde 7 %, radio 12, con herramientas (copiar, ver) |
| diagrama | Mermaid |

## 2. Estados de trabajo

| Estado | Medidas |
|---|---|
| Pensando (`thinking`) | alto 36, gap 6, 14 px / 500, tinta 72 % |
| Transcripción en vivo | 14 px / 500, interlineado 1.5, +0.004em; 72 % mientras llega, 94 % al quedar fija |
| Voz hablando (`speech`) | igual que la transcripción; se asienta a opacidad 1 |
| Línea de tiempo | alto 36, a todo el ancho |
| Carrete (`reel`) | alto 26: iconos de lo que va tocando |
| Agentes (`agents`, `sub-agent-bars`) | barras por subagente, gap 10 |
| Tarjeta de ejecución (`wf-runcard`) | ancho 320–420, padding 14 / 16 / 12, radio 20, fondo `#16161b`, sombra `0 18 48` 32 % |
| Paso (`wf-runstep`) | padding 5 × 2, gap 2 |
| Checklist (`wf-checklist`) | ancho 320, padding 18 / 20 / 12, radio 20, fondo `#16161b`, con insignia, asa y descarte |
| Tarjeta de fase (`wf-phasecard`) | como la de ejecución |
| Fuera de este escritorio (`offspace`) | ancho 360, padding 18 × 20, gap 10; icono de la app, punto, "esperando", reanudar, parar |
| Cuenta atrás | anillo con pista y progreso |
| Aviso (`island-notice`) | píldora 6 × 12, 11.5 px / 500; info `#96c8ff`, error `#ff8278`, éxito `#8cdc96` |

Tarjeta genérica (`ov-card`): eyebrow 11 px / 600 al 42 %; título 15 px / 600, −0.01em, blanco
96 %; botón primario blanco 92 % con texto `#121317`, padding 0 × 16; botón ghost; tile de icono.

## 3. Adjuntos

| Pieza | Medidas |
|---|---|
| Tarjeta de adjunto (`ci-att-card`) | 84 × 102, radio 10, tile 6 %, borde blanco 22 %, padding 8 (imagen a sangre); error con fondo `#ff7a64` al 8 % |
| Nombre | 12 px / 500, interlineado 16 |
| Extensión | 10 px / 600, +0.04em, padding 3 × 6, radio 5, blanco 13 % |
| Quitar (x) | círculo 24, borde blanco 30 %, fondo `#141519` al 90 %; aparece al pasar |
| Vista previa | fondo `#141519`, gap 16: cabecera, título, metadatos, texto, monograma, vacío |
| Fila de chips | gap 8, padding 12 / 12 / 0 / 0, con desvanecido al final |
| Pila de capturas | 96 × 64; insignia de 18 de alto con el número, radio 6, 10 px / 600 |
| Tira de capturas | gap 6, padding 10 / 10 / 0 |
| Zona para soltar | alto 36, padding 0 × 16, borde discontinuo 1.5 blanco 28 %, radio 12, 12 px / 500 |
| Subida | tarjeta 340–440, padding 18 × 20, gap 12; chip 8 × 12, radio 12, 13 px / 600; flecha de transferencia |
| Mención (@) | selector con padding 4, máx. 240 de alto, radio 11; ítem 6 × 8, radio 7, 13 px, hover acento al 16 % |

## 4. Dictado

Resultado: tarjeta 320–424, padding 16 / 18 / 14, gap 10; texto 15 px / 500, interlineado 1.38,
−0.01em; acciones copiar y ocultar. Confirmación con título, cuerpo, primario y ghost. Envío
automático con cuenta atrás.

## 5. Avisos del sistema

| Aviso | Medidas |
|---|---|
| Límite de uso | ancho 380, rejilla 38 + resto, gap 10 × 12, padding 18 × 20 |
| Actualización disponible | ancho 522, rejilla 30 + resto + acciones, padding 18 × 20 |
| Consentimiento | 340–440, padding 18 × 20, gap 10 |
| Iniciar sesión | como límite de uso |
| Diagnóstico | mín(420, 86 %), rejilla 38 + resto |
| Pregunta con opciones (`answer-card`) | 340–440, padding 18 × 20, gap 14 |
| Comentarios | modal 480, padding 32, radio 28, estados de ánimo, capturas, contador |

## 6. Contra la isla de Companion

| Familia | Companion hoy | Falta |
|---|---|---|
| Datos | una tarjeta de resultado (título + línea + "Ver") | todo el popup rico: títulos, párrafos, listas, tablas, callouts, código, clave-valor, chips de archivo, citas, tareas, gráficas, diagramas |
| Estados | línea de estado con texto (escucha, pienso, actuando, trabajo con n pasos), barras de onda, anillo de cuenta atrás, luz ámbar / verde, chip de referencia (16l) | transcripción viva vs fija, carrete de lo que toca, línea de tiempo, barras de agentes, tarjeta de ejecución con pasos, checklist, fuera de este escritorio |
| Adjuntos | el clip abre la ventana | tarjetas 84 × 102 con vista previa, extensión y quitar; pila y tira de capturas; zona para soltar; subida; menciones |
| Dictado | dictado en el campo (12e) | tarjeta de resultado con copiar / ocultar; confirmación; envío automático |
| Avisos | tarjeta de aviso genérica | límite, actualización, consentimiento, sesión, diagnóstico con su rejilla |
