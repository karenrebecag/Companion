# Wave 16q — Paridad con Incredible en las decisiones abiertas

Este archivo lo crea 16q-1 en su rama; aquí solo va la sección de 16q-2. El conflicto se
resuelve al integrar (conservar ambas secciones).

## 16q-2 — Ubicación, tarjeta de opciones y comentarios

**Estado: APROBADO (2026-09-29).** Karen: "todo lo que funcione igual que Incredible".
Fuente de verdad: `docs/research/auditoria-decisiones-incredible.md`, decisiones 4, 5 y 6. No se
leyó ni se copió código de Incredible; los nombres y textos son propios.

### Ubicación (decisión 4)

Incredible no tiene ubicación; aquí la función se queda. Lo que se iguala es que nunca pida
permiso por su cuenta.

- `NativeToolRunner.findPlaces` respeta el canal "Tu ciudad" (`locationChannelOn`, leído en cada
  llamada; `ParentToolRunner` lo reenvía; `CompanionMainSensing` lo cablea a
  `ContextPreference.channels`).
- Canal apagado: solo la ciudad escrita en Ajustes (`UserLocationSource.typedCity()`); si no hay,
  `NearMe.needsCity`. No se abre el diálogo de macOS y **tampoco se lee la ciudad del sistema**
  (ver decisiones abiertas).
- Canal encendido: igual que antes (`current(prompting: true)`).
- El texto de Ajustes ya no dice que una búsqueda puede pedir la ubicación con el canal apagado.

### Tarjeta de opciones (decisión 5)

- **Dos pasos.** Un clic, Espacio o un dígito 1-9 solo seleccionan; el botón Confirmar envía.
  Return selecciona la opción del cursor y, con algo ya seleccionado, confirma.
- **Selección múltiple**: `"multiple": true` en la fence. La respuesta lista las etiquetas en el
  orden de las opciones, separadas por ", "; el hilo la lee de vuelta por subconjuntos (una etiqueta
  puede llevar coma). Sin la bandera, la fence es la de siempre.
- **Respuesta libre**: `"allowText": true`. Es la alternativa a las opciones (escribir vacía la
  selección y al revés). Tope `ChoiceBlock.maxAnswer` = 500, una línea, sin escalares invisibles.
  Una respuesta libre cierra la pregunta sin marcar opción.
- Una bandera mal tipada se lee como apagada; no rompe la fence.
- **Diferencia deliberada**: Incredible no tiene atajos numéricos. Aquí siguen, pero solo
  seleccionan, por accesibilidad de teclado.
- **Tools**: un turno de tarjeta usa `ParentToolExecuting.noteChoiceTurn()`, que deja
  `.allConnected` (antes `.none` en la primera petición). Entrada aparte para que la etiqueta
  jamás llegue a `noteTurn` como palabras suyas.
- **Invariante intacto**: `said = ""` para la compuerta y para `noteTurn`; una elección nunca es
  consentimiento y cada escritura de app sigue pidiendo su hoja. Los grants mueren al empezar el
  turno de tarjeta.
- El vocabulario de tarjetas enseña las dos banderas al modelo.

### Comentarios (decisión 6)

- 5 ánimos (`upset, bad, meh, good, love`, de peor a mejor; los cuatro anteriores conservan
  nombre) y 6 temas (`voice, screen, apps, errands, dictation, other`), multiselección.
- Tope de texto 5000. Tope de mailto 6000 sin cambio: 5000 caracteres sin nada que escapar caben
  con ánimo y temas; un texto normal (espacios y acentos se codifican a 3-6 caracteres) no cabe, y
  entonces sale **completo** por el servicio de compartir, o se corta y se avisa si no hay
  servicio. El corte solo come texto: ánimo y temas quedan.
- Hasta 3 capturas de 4 MB o menos (`maxCaptureBytes`), desde archivo (selector), pegadas
  (imagen del portapapeles a un archivo privado) o la captura de región. El tope de 3 es para
  el conjunto. Se rechaza lo que no es imagen, lo ilegible y lo que pesa más (con su aviso).
- Solo se borra lo que la app escribió (región y pegadas). Un archivo elegido por ella nunca se
  borra, ni al quitarlo ni al cancelar. Tras enviar no se borra nada (el correo puede estar
  leyendo).
- Destino sin cambio: `mailto:` / `composeEmail`. **No se construye** backend, diagnósticos ni
  metadatos de la máquina (decisión de producto de Karen). Si algún día se adjunta un paquete de
  turnos, debe excluir `<user_location>`.

### Decisiones abiertas

1. Canal apagado sin ciudad escrita: se pidió `prompting: false`; se implementó "no leer el
   sistema" (más estricto). Volver a `current(prompting: false)` es una línea si Karen prefiere
   usar una ciudad ya en caché.
2. Las capturas de región no pasan por el tope de 4 MB (solo archivo y pegado).
3. Pegar solo por botón, no con Cmd+V: `onPasteCommand` podría interceptar el pegado de texto.
4. Los tres textos ("Al límite", temas) son propios; Karen puede cambiarlos sin tocar lógica.
5. Los archivos pegados quedan en la carpeta temporal hasta que macOS la limpie.
