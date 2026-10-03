- **El navegador ya desplaza la página y pasa el puntero (2026-10-03).** Dos herramientas nuevas,
  como las de Incredible: `browser_scroll` desplaza una pestaña unos píxeles (con la rueda real, en
  el centro de la vista, así que también mueve listas y paneles con su propio scroll) o trae a la
  vista un elemento de la última lectura, y `browser_hover` pasa el puntero sobre un elemento para
  abrir los menús o ayudas que solo aparecen al pasar por encima. No piden permiso porque no
  cambian nada de la página, pero exigen controlar la pestaña, y el puntero solo va a un elemento
  que no tenga nada encima. Un desplazamiento tiene un tope de 20 000 píxeles por eje.
