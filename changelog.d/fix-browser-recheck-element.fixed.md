- **El navegador ya no pulsa un elemento que cambió desde la lectura (2026-10-03).**
  Entre leer la página y pulsar, una página podía reutilizar el mismo nodo con otro texto (de
  "Siguiente" a "Eliminar cuenta") y el clic se hacía sin hoja de aprobación. Ahora la extensión
  recuerda el rol, la etiqueta, el diálogo o formulario que lo contiene y el enlace de cada elemento leído y, si cambiaron, responde
  `stale_id` para que se vuelva a leer antes de actuar. Vale para clic y escritura, también dentro de
  iframes.
