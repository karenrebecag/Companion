- **Pulsar un elemento que se ocultó después de leer la página ya no responde "pulsado" (2026-10-03).**
  Si un menú se cerraba entre la lectura y el clic, sus opciones seguían numeradas: el clic real no
  encontraba dónde caer y la extensión pulsaba el nodo oculto por código, así que el modelo creía
  haber pulsado algo que la persona no ve. Ahora pulsar o escribir en un elemento oculto se rechaza
  y el modelo recibe que debe volver a leer la pestaña.
