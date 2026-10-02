- **La lectura del navegador ya no ofrece controles escondidos por un contenedor (2026-10-02).**
  Antes solo se miraba el estilo del propio elemento, asi que un boton dentro de un bloque oculto
  o de un `details` cerrado le llegaba al modelo como si se pudiera pulsar. Ahora se usa la
  visibilidad real del navegador (`checkVisibility`).
