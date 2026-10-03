- **Los errores del navegador dicen qué hacer después (2026-10-03).**
  Cuando la persona cancelaba el control de la pestaña, el modelo solo leía "el navegador falló" y
  volvía a intentar. Ahora `debugger_revoked`, `debugger_unavailable`, `unreadable_page` y
  `not_typable` llegan con su propio texto en español e inglés (no reintentar y preguntar, cerrar las
  herramientas de desarrollo, avisar que la página no se puede leer, elegir otro elemento), y leer una
  pestaña que ya no existe libera el control de esa pestaña.
