# Incredible — inventario de componentes (cualitativo)

Fecha: 2026-09-25. Fuente: inspección en solo lectura de la app instalada de Incredible 0.2.36. Este brief
ya no lleva valores, selectores ni nombres de clases tomados del binario: los números exactos (colores,
medidas, curvas, sombras) se consultan solo en la referencia local. Aquí quedan las observaciones en
palabras. Complementa `incredible-tipografia.md` y las specs 16c–16j (interacción).

## 1. Superficies de la app

| Superficie | Qué contiene |
|---|---|
| Ventana principal | Home, skills, conectores (Apps), navegador, historial, recordatorios, memoria y contactos; botones, tarjetas, teclas y puntos de estado propios (referencia local) |
| Ajustes | Pestañas: general, atajos, voz, permisos, vocabulario, contactos |
| Isla (notch) | Barra, campo de texto, tarjetas, menú, avisos, dictado, tooltip, onda y orbe de voz |
| Respuestas ricas | Popup ancho con encabezados, listas, tablas, callouts, código con copiar, chips de archivo y gráficas |
| Flujos / grabar tarea | Preguntas, checklist, pasos de ejecución y tarjetas de fase |
| Bienvenida | Escenas, permisos guiados, prueba de sonido, nombre, testimonios y login |

## 2. Tokens de color, sombra y curva (tema claro)

- Superficies en una escala corta de blancos y grises casi neutros; hover y activo son velos de negro de muy baja opacidad (referencia local).
- Estados verde, naranja y rojo con la paleta de sistema de Apple, con un fondo atenuado para cada uno.
- El acento azul se reserva para enlaces y anillo de foco; los botones principales son negros, no azules.
- Un naranja de marca aparte, con su versión clara.
- Cuatro niveles de sombra (tarjeta, elevado, popup, modal) que crecen en desenfoque y opacidad.
- Cuatro curvas con nombre: estándar, asentada (la de uso general), deslizante y con rebote.
- La isla es oscura: fondo negro, texto en tres niveles de blanco, tiles y bordes como velos de blanco, y colores de acento y de error propios más claros (referencia local).

## 3. Componentes de la ventana principal y ajustes

- **Botones:** píldora semibold con deshabilitado atenuado y transición asentada corta; variantes sólido neutro (negro con texto blanco), ghost neutro (velo de negro con texto negro) y peligro (rojo sólido o ghost rojo). Los neutros crecen levemente al hover. Variante de icono en dos tamaños, redonda o de radio chip, y un botón de bienvenida más alto. Existe una clase azul heredada casi sin uso: no se copia.
- **Badge:** chip pequeño con tonos neutral, acento, positivo, aviso, peligro y sólido.
- **Cerrar:** círculo con fondo de velo.
- **Switch:** en dos tamaños; apagado en velo de negro, encendido en el color de texto primario (verde de señal en oscuro); transición asentada.
- **Select:** campo redondeado con fondo de velo, texto mediano y anillo de foco fino.
- **Menú (popup):** radio grande, fondo blanco, borde fino y sombra de popup; ítems compactos con hover de velo y estado de peligro rosado; entra y sale rápido.
- **Tarjeta elevada** y **action card:** fondo blanco, borde claro, radio grande; la action card lleva un halo radial de acento que sigue al cursor con una transición lenta asentada.
- **Glow card:** fila que se ilumina en hover, con CTA y flecha que pasan a negro.
- **Keycap:** dos tamaños; el grande lleva un borde inferior interior que lo vuelve tecla.
- **Status dot:** círculo pequeño.
- **Toasts:** librería Sonner (éxito y error).

(referencia local para todas las medidas)

## 4. Componentes de la isla

- **Isla cerrada:** píldora pequeña; la **barra abierta** crece con un morph corto y radio grande.
- **Campo:** padding generoso, texto de cuerpo con interlineado holgado; **botón enviar** circular que se activa en blanco con sombra.
- **Botones de herramienta e ítems de menú** compactos; **menú de la isla** estrecho con radio medio.
- **Aviso:** píldora pequeña; **tooltip:** píldora más alta con texto mediano.
- **Tarjetas de captura:** fila de tarjetas de altura fija y radio chico, de ancho distinto según sean texto, captura de pantalla, archivo o tarea.
- **Confirmación:** tarjeta con ícono de acento (verde, azul, naranja o ámbar) y ancho acotado.
- **Chip de referencia:** chip pequeño con color tenue y borde algo más fuerte.
- **Opción de respuesta:** fila con fondo de velo blanco y hover índigo.
- **Popup de respuesta rica:** ancho limitado a una fracción de la pantalla.

(referencia local para todas las medidas)

## 5. Contra Companion

| Incredible | Companion hoy | Hueco |
|---|---|---|
| Switch propio (referencia local) | `SettingsSwitch` envuelve el `Toggle` nativo | No se puede medir igual: hay que dibujarlo |
| Select propio | `Picker` nativo en Ajustes y en la barra lateral | Igual: hace falta un select propio |
| Menú popup propio | `Dropdown` propio (ventana) + `IslandPopover` (isla) | Existe; faltan medidas y estados |
| Botón solid / ghost / danger / icono | `AppButton`, `SettingsPill`, `HoverIconButton` | Existen con otras medidas; el primario es negro, no azul |
| Keycap sm / lg | `SettingsKeycap`, `WelcomeKeycap` | Dos piezas para una: unificar |
| Action card y glow card | `HomeStartCard`, `GalleryCard` | Falta el halo que sigue al cursor |
| Opción de respuesta, confirmación, chip de referencia | `IslandNoticeCard`, `ApprovalSheet` | La confirmación sí; opción y chip no existen |
| Popup de respuesta rica | `MarkdownView` en el hilo | Ni tablas ni callouts ni file chips en la isla |
| Tarjetas de captura | adjuntos del chat | Falta la tira de capturas en la isla |
| Status dot, toasts | `Toasts` | Existen; falta verificar medidas |
