- **Leer el navegador ya busca como Incredible: por texto, por rol y dentro de un elemento (2026-10-03).**
  `browser_read` solo leía la página entera o lo que nombrara un selector CSS. Ahora acepta un texto
  (los controles y líneas que lo dicen, entero si se pide `exact`), un rol con su nombre, un elemento
  de la lectura anterior dentro del cual buscar, y topes de elementos y de caracteres. Si nada
  coincide, o solo coinciden cosas ocultas, el modelo recibe cuál de las dos es y qué hacer.
