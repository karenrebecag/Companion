- **Abrir o navegar una pestaña ya espera a que la página cargue (2026-10-03).**
  `browser_open` y `browser_navigate` respondían antes de que la página cargara, así que una lectura
  inmediata veía una página vacía o la anterior y el modelo concluía que estaba vacía. Ahora, como
  Incredible, esperan a que cargue con un tope de cinco segundos; si se agota, el modelo recibe que
  la página sigue cargando y que espere un momento antes de leerla.
